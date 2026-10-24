import crypto from "crypto";
import { Pool, PoolClient, QueryResultRow } from "pg";
import { config } from "../config";
import { pool, withTransaction } from "../db";
import { AppError } from "../http/errors";
import { createShortCode, createTicketToken, sha256 } from "../utils/crypto";
import { isPlatformAdmin } from "../auth/roles";

export type BookingItemInput = {
  ticket_type_id: string;
  quantity: number;
};

type BookingRow = {
  id: string;
  user_id: string;
  event_id: string;
  status: "pending" | "confirmed" | "cancelled" | "expired";
  total_minor: number;
  currency: string;
  idempotency_key: string;
  expires_at: Date | null;
  created_at: Date;
  updated_at: Date;
  event_title: string;
  event_venue: string;
  event_starts_at: Date;
  event_ends_at: Date;
  event_status: string;
  organizer_id: string;
  organizer_name: string;
};

type BookingItemRow = {
  id: string;
  ticket_type_id: string;
  ticket_type_name: string;
  quantity: number;
  unit_price_minor: number;
};

type TicketRow = {
  id: string;
  ticket_type_id: string;
  ticket_type_name: string;
  short_code: string;
  attendee_name: string | null;
  status: "valid" | "used" | "cancelled";
  used_at: Date | null;
  created_at: Date;
};

type PaymentRow = {
  id: string;
  booking_id: string;
  provider: string;
  provider_reference: string | null;
  amount_minor: number;
  currency: string;
  status: "pending" | "succeeded" | "failed";
  phone: string | null;
  network: string | null;
  created_at: Date;
  updated_at: Date;
};

type Queryable = Pool | PoolClient;

async function queryable<T extends QueryResultRow>(
  db: Queryable,
  text: string,
  params: unknown[] = [],
) {
  return db.query<T>(text, params);
}

export async function getBookingView(
  db: Queryable,
  bookingId: string,
): Promise<Record<string, unknown> | null> {
  const bookingResult = await queryable<BookingRow>(
    db,
    `SELECT b.id, b.user_id, b.event_id, b.status, b.total_minor, b.currency,
            b.idempotency_key, b.expires_at, b.created_at, b.updated_at,
            e.title AS event_title, e.venue AS event_venue,
            e.starts_at AS event_starts_at, e.ends_at AS event_ends_at,
            e.status AS event_status, e.organizer_id,
            u.full_name AS organizer_name
     FROM bookings b
     JOIN events e ON e.id = b.event_id
     JOIN users u ON u.id = e.organizer_id
     WHERE b.id = $1`,
    [bookingId],
  );
  const booking = bookingResult.rows[0];
  if (!booking) return null;

  const items = await queryable<BookingItemRow>(
    db,
    `SELECT bi.id, bi.ticket_type_id, tt.name AS ticket_type_name,
            bi.quantity, bi.unit_price_minor
     FROM booking_items bi
     JOIN ticket_types tt ON tt.id = bi.ticket_type_id
     WHERE bi.booking_id = $1
     ORDER BY bi.id`,
    [bookingId],
  );

  const tickets = await queryable<TicketRow>(
    db,
    `SELECT t.id, t.ticket_type_id, tt.name AS ticket_type_name, t.short_code,
            t.attendee_name, t.status, t.used_at, t.created_at
     FROM tickets t
     JOIN ticket_types tt ON tt.id = t.ticket_type_id
     WHERE t.booking_id = $1
     ORDER BY t.created_at, t.id`,
    [bookingId],
  );

  const payment = await queryable<PaymentRow>(
    db,
    `SELECT id, booking_id, provider, provider_reference, amount_minor, currency,
            status, phone, network, created_at, updated_at
     FROM payments WHERE booking_id = $1
     ORDER BY created_at DESC LIMIT 1`,
    [bookingId],
  );

  return {
    id: booking.id,
    user_id: booking.user_id,
    event_id: booking.event_id,
    status: booking.status,
    total_minor: booking.total_minor,
    currency: booking.currency,
    idempotency_key: booking.idempotency_key,
    expires_at: booking.expires_at,
    created_at: booking.created_at,
    updated_at: booking.updated_at,
    event: {
      id: booking.event_id,
      title: booking.event_title,
      venue: booking.event_venue,
      starts_at: booking.event_starts_at,
      ends_at: booking.event_ends_at,
      status: booking.event_status,
      organizer_id: booking.organizer_id,
      organizer_name: booking.organizer_name,
    },
    items: items.rows,
    tickets: tickets.rows.map((ticket) => ({
      ...ticket,
      token: createTicketToken(ticket.id),
    })),
    payment: payment.rows[0] ?? null,
  };
}

export async function listBookingsForUser(userId: string) {
  const result = await pool.query<{ id: string }>(
    "SELECT id FROM bookings WHERE user_id = $1 ORDER BY created_at DESC",
    [userId],
  );
  const rows = await Promise.all(result.rows.map((row) => getBookingView(pool, row.id)));
  return rows.filter(Boolean);
}

export async function getBookingForUser(
  bookingId: string,
  userId: string,
  role: string,
) {
  const booking = await getBookingView(pool, bookingId);
  if (!booking) throw new AppError(404, "BOOKING_NOT_FOUND", "Booking not found");
  if (!isPlatformAdmin(role) && booking.user_id !== userId) {
    throw new AppError(403, "FORBIDDEN", "This booking belongs to another user");
  }
  return booking;
}

export async function createBooking(input: {
  userId: string;
  eventId: string;
  idempotencyKey: string;
  items: BookingItemInput[];
  attendeeName?: string;
}) {
  const merged = new Map<string, number>();
  for (const item of input.items) {
    merged.set(item.ticket_type_id, (merged.get(item.ticket_type_id) ?? 0) + item.quantity);
  }
  const items = [...merged.entries()].map(([ticket_type_id, quantity]) => ({
    ticket_type_id,
    quantity,
  }));

  if (items.length === 0) {
    throw new AppError(400, "EMPTY_BOOKING", "Choose at least one ticket");
  }
  const totalTickets = items.reduce((sum, item) => sum + item.quantity, 0);
  if (totalTickets > 20) {
    throw new AppError(400, "TOO_MANY_TICKETS", "A booking can hold at most 20 tickets");
  }

  const bookingId = await withTransaction(async (client) => {
    const existing = await client.query<{ id: string }>(
      "SELECT id FROM bookings WHERE user_id = $1 AND idempotency_key = $2",
      [input.userId, input.idempotencyKey],
    );
    if (existing.rows[0]) return existing.rows[0].id;

    const eventResult = await client.query<{
      id: string;
      status: string;
      starts_at: Date;
      currency: string;
    }>("SELECT id, status, starts_at FROM events WHERE id = $1", [input.eventId]);
    const event = eventResult.rows[0];
    if (!event) throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");
    if (event.status !== "published") {
      throw new AppError(409, "EVENT_NOT_ON_SALE", "This event is not on sale");
    }
    if (event.starts_at.getTime() <= Date.now()) {
      throw new AppError(409, "EVENT_STARTED", "This event has already started");
    }

    let totalMinor = 0;
    let currency = "ZMW";
    const pricedItems: Array<{ ticket_type_id: string; quantity: number; price_minor: number }> = [];

    for (const item of items) {
      const reserved = await client.query<{
        price_minor: number;
        currency: string;
      }>(
        `UPDATE ticket_types
         SET sold_count = sold_count + $1
         WHERE id = $2 AND event_id = $3 AND sold_count + $1 <= capacity
         RETURNING price_minor, currency`,
        [item.quantity, item.ticket_type_id, input.eventId],
      );

      if (!reserved.rows[0]) {
        throw new AppError(
          409,
          "SOLD_OUT",
          "One of the ticket types no longer has enough tickets available",
        );
      }

      totalMinor += reserved.rows[0].price_minor * item.quantity;
      currency = reserved.rows[0].currency.trim();
      pricedItems.push({ ...item, price_minor: reserved.rows[0].price_minor });
    }

    const expiresAt = new Date(Date.now() + config.bookingHoldMinutes * 60_000);
    const booking = await client.query<{ id: string }>(
      `INSERT INTO bookings (user_id, event_id, total_minor, currency, idempotency_key, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id`,
      [input.userId, input.eventId, totalMinor, currency, input.idempotencyKey, expiresAt],
    );
    const newBookingId = booking.rows[0].id;

    for (const item of pricedItems) {
      await client.query(
        `INSERT INTO booking_items (booking_id, ticket_type_id, quantity, unit_price_minor)
         VALUES ($1, $2, $3, $4)`,
        [newBookingId, item.ticket_type_id, item.quantity, item.price_minor],
      );
    }

    const profile = await client.query<{ full_name: string }>(
      "SELECT full_name FROM users WHERE id = $1",
      [input.userId],
    );
    const attendeeName = input.attendeeName?.trim() || profile.rows[0]?.full_name || null;

    for (const item of pricedItems) {
      for (let i = 0; i < item.quantity; i += 1) {
        const ticketId = crypto.randomUUID();
        const tokenHash = sha256(createTicketToken(ticketId));
        let shortCode = createShortCode();
        for (let attempt = 0; attempt < 6; attempt += 1) {
          const codeCheck = await client.query(
            "SELECT 1 FROM tickets WHERE short_code = $1",
            [shortCode],
          );
          if (codeCheck.rowCount === 0) break;
          shortCode = createShortCode();
        }
        await client.query(
          `INSERT INTO tickets
             (id, booking_id, ticket_type_id, token_hash, short_code, attendee_name)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [ticketId, newBookingId, item.ticket_type_id, tokenHash, shortCode, attendeeName],
        );
      }
    }

    return newBookingId;
  });

  return (await getBookingView(pool, bookingId))!;
}

async function releaseCapacity(client: PoolClient, bookingId: string) {
  const items = await client.query<{ ticket_type_id: string; quantity: number }>(
    `SELECT ticket_type_id, SUM(quantity)::int AS quantity
     FROM booking_items WHERE booking_id = $1 GROUP BY ticket_type_id`,
    [bookingId],
  );
  for (const item of items.rows) {
    await client.query(
      `UPDATE ticket_types
       SET sold_count = GREATEST(0, sold_count - $1)
       WHERE id = $2`,
      [item.quantity, item.ticket_type_id],
    );
  }
}

export async function cancelBooking(bookingId: string, userId: string, role: string) {
  await withTransaction(async (client) => {
    const result = await client.query<{
      id: string;
      user_id: string;
      status: string;
      event_starts_at: Date;
    }>(
      `SELECT b.id, b.user_id, b.status, e.starts_at AS event_starts_at
       FROM bookings b JOIN events e ON e.id = b.event_id
       WHERE b.id = $1 FOR UPDATE OF b`,
      [bookingId],
    );
    const booking = result.rows[0];
    if (!booking) throw new AppError(404, "BOOKING_NOT_FOUND", "Booking not found");
    if (!isPlatformAdmin(role) && booking.user_id !== userId) {
      throw new AppError(403, "FORBIDDEN", "This booking belongs to another user");
    }
    if (booking.status === "cancelled" || booking.status === "expired") return;
    if (booking.event_starts_at.getTime() <= Date.now()) {
      throw new AppError(409, "EVENT_STARTED", "Tickets cannot be cancelled after the event starts");
    }

    await releaseCapacity(client, bookingId);
    await client.query(
      "UPDATE bookings SET status = 'cancelled', updated_at = now() WHERE id = $1",
      [bookingId],
    );
    await client.query(
      "UPDATE tickets SET status = 'cancelled' WHERE booking_id = $1 AND status = 'valid'",
      [bookingId],
    );
    await client.query(
      "UPDATE payments SET status = 'failed', updated_at = now() WHERE booking_id = $1 AND status = 'pending'",
      [bookingId],
    );
  });

  return (await getBookingView(pool, bookingId))!;
}

export async function releaseExpiredBookings(): Promise<number> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const expired = await client.query<{ id: string }>(
      `SELECT id FROM bookings
       WHERE status = 'pending' AND expires_at IS NOT NULL AND expires_at <= now()
       ORDER BY expires_at
       LIMIT 100
       FOR UPDATE SKIP LOCKED`,
    );

    for (const row of expired.rows) {
      await releaseCapacity(client, row.id);
      await client.query(
        "UPDATE bookings SET status = 'expired', updated_at = now() WHERE id = $1",
        [row.id],
      );
      await client.query(
        "UPDATE tickets SET status = 'cancelled' WHERE booking_id = $1 AND status = 'valid'",
        [row.id],
      );
      await client.query(
        "UPDATE payments SET status = 'failed', updated_at = now() WHERE booking_id = $1 AND status = 'pending'",
        [row.id],
      );
    }

    await client.query("COMMIT");
    return expired.rowCount ?? 0;
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function initiatePayment(input: {
  bookingId: string;
  userId: string;
  role: string;
  phone?: string;
  network?: string;
}) {
  const booking = (await getBookingView(pool, input.bookingId)) as {
    user_id: string;
    status: string;
    total_minor: number;
    currency: string;
  } | null;
  if (!booking) throw new AppError(404, "BOOKING_NOT_FOUND", "Booking not found");
  if (!isPlatformAdmin(input.role) && booking.user_id !== input.userId) {
    throw new AppError(403, "FORBIDDEN", "This booking belongs to another user");
  }
  if (booking.status === "cancelled" || booking.status === "expired") {
    throw new AppError(409, "BOOKING_CLOSED", "This booking is no longer payable");
  }

  const existing = await pool.query<PaymentRow>(
    `SELECT id, booking_id, provider, provider_reference, amount_minor, currency,
            status, phone, network, created_at, updated_at
     FROM payments WHERE booking_id = $1
     ORDER BY created_at DESC LIMIT 1`,
    [input.bookingId],
  );
  if (existing.rows[0]?.status === "pending") {
    return existing.rows[0];
  }
  if (existing.rows[0]?.status === "succeeded") {
    return existing.rows[0];
  }

  const reference = `SIM-${crypto.randomUUID()}`;
  const result = await pool.query<PaymentRow>(
    `INSERT INTO payments (booking_id, provider, provider_reference, amount_minor, currency, phone, network)
     VALUES ($1, 'simulated', $2, $3, $4, $5, $6)
     RETURNING id, booking_id, provider, provider_reference, amount_minor, currency,
               status, phone, network, created_at, updated_at`,
    [
      input.bookingId,
      reference,
      booking.total_minor,
      booking.currency,
      input.phone ?? null,
      input.network ?? null,
    ],
  );
  return result.rows[0];
}

export async function completePayment(reference: string, provider = "simulated") {
  const outcome = await withTransaction(async (client) => {
    const paymentResult = await client.query<PaymentRow>(
      `SELECT p.id, p.booking_id, p.provider, p.provider_reference, p.amount_minor,
              p.currency, p.status, p.phone, p.network, p.created_at, p.updated_at
       FROM payments p
       WHERE p.provider = $1 AND p.provider_reference = $2
       FOR UPDATE`,
      [provider, reference],
    );
    const payment = paymentResult.rows[0];
    if (!payment) throw new AppError(404, "PAYMENT_NOT_FOUND", "Payment not found");
    if (payment.status === "succeeded") {
      return { bookingId: payment.booking_id, closed: false };
    }

    const booking = await client.query<{ status: string }>(
      "SELECT status FROM bookings WHERE id = $1 FOR UPDATE",
      [payment.booking_id],
    );
    const status = booking.rows[0]?.status;
    if (!status || status === "cancelled" || status === "expired") {
      await client.query(
        "UPDATE payments SET status = 'failed', updated_at = now() WHERE id = $1",
        [payment.id],
      );
      return { bookingId: payment.booking_id, closed: true };
    }

    await client.query(
      "UPDATE payments SET status = 'succeeded', updated_at = now() WHERE id = $1",
      [payment.id],
    );
    await client.query(
      "UPDATE bookings SET status = 'confirmed', expires_at = NULL, updated_at = now() WHERE id = $1",
      [payment.booking_id],
    );
    return { bookingId: payment.booking_id, closed: false };
  });

  if (outcome.closed) {
    throw new AppError(409, "BOOKING_CLOSED", "This booking is no longer payable");
  }
  return (await getBookingView(pool, outcome.bookingId))!;
}

export async function recordWebhookEvent(
  provider: string,
  providerEventId: string,
  payload: unknown,
): Promise<boolean> {
  const result = await pool.query(
    `INSERT INTO webhook_events (provider, provider_event_id, payload)
     VALUES ($1, $2, $3)
     ON CONFLICT (provider, provider_event_id) DO NOTHING
     RETURNING id`,
    [provider, providerEventId, payload],
  );
  return (result.rowCount ?? 0) > 0;
}

export async function markWebhookProcessed(provider: string, providerEventId: string) {
  await pool.query(
    `UPDATE webhook_events SET processed_at = now()
     WHERE provider = $1 AND provider_event_id = $2`,
    [provider, providerEventId],
  );
}
