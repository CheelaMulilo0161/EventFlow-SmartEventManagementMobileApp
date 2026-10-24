import { Router } from "express";
import { z } from "zod";
import { pool, withTransaction } from "../db";
import { requireAuth, requireRole } from "../auth/jwt";
import { PLATFORM_ADMIN_ROLES, isPlatformAdmin } from "../auth/roles";
import { writeAuditLog } from "../admin/audit";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";
import { UserRole } from "../types/express";
import { param } from "../http/params";
import { cancelEventAndRelease } from "../services/events";

const router = Router();

const ticketTypeInput = z.object({
  name: z.string().trim().min(2).max(80),
  price_minor: z.number().int().min(0),
  capacity: z.number().int().positive(),
});

const eventInput = z
  .object({
    title: z.string().trim().min(3).max(160),
    description: z.string().trim().max(5000).default(""),
    venue: z.string().trim().min(2).max(200),
    starts_at: z.coerce.date(),
    ends_at: z.coerce.date(),
    image_url: z.string().trim().url().max(1000).optional().nullable(),
    ticket_types: z.array(ticketTypeInput).max(20).default([]),
  })
  .refine((value) => value.ends_at > value.starts_at, {
    message: "The event must end after it starts",
    path: ["ends_at"],
  });

const eventUpdateInput = z.object({
  title: z.string().trim().min(3).max(160).optional(),
  description: z.string().trim().max(5000).optional(),
  venue: z.string().trim().min(2).max(200).optional(),
  starts_at: z.coerce.date().optional(),
  ends_at: z.coerce.date().optional(),
  image_url: z.string().trim().url().max(1000).optional().nullable(),
});

const ticketTypeUpdateInput = z.object({
  name: z.string().trim().min(2).max(80).optional(),
  price_minor: z.number().int().min(0).optional(),
  capacity: z.number().int().positive().optional(),
});

type EventRow = {
  id: string;
  organizer_id: string;
  organizer_name: string;
  title: string;
  description: string;
  venue: string;
  starts_at: Date;
  ends_at: Date;
  status: "draft" | "published" | "cancelled";
  image_url: string | null;
  created_at: Date;
  updated_at: Date;
  ticket_types?: TicketTypeRow[];
};

type TicketTypeRow = {
  id: string;
  event_id: string;
  name: string;
  price_minor: number;
  currency: string;
  capacity: number;
  sold_count: number;
  remaining: number;
};

const eventSelect = `
  SELECT e.id, e.organizer_id, u.full_name AS organizer_name, e.title, e.description,
         e.venue, e.starts_at, e.ends_at, e.status, e.image_url, e.created_at, e.updated_at
  FROM events e
  JOIN users u ON u.id = e.organizer_id
`;

async function getTicketTypes(eventId: string): Promise<TicketTypeRow[]> {
  const result = await pool.query<TicketTypeRow>(
    `SELECT id, event_id, name, price_minor, currency, capacity, sold_count,
            (capacity - sold_count) AS remaining
     FROM ticket_types WHERE event_id = $1 ORDER BY price_minor ASC, name ASC`,
    [eventId],
  );
  return result.rows;
}

async function getEventWithTypes(eventId: string): Promise<EventRow | null> {
  const result = await pool.query<EventRow>(`${eventSelect} WHERE e.id = $1`, [eventId]);
  const event = result.rows[0];
  if (!event) return null;
  event.ticket_types = await getTicketTypes(eventId);
  return event;
}

async function requireOwner(eventId: string, userId: string, role: UserRole) {
  const result = await pool.query<{ organizer_id: string; status: string }>(
    "SELECT organizer_id, status FROM events WHERE id = $1",
    [eventId],
  );
  const event = result.rows[0];
  if (!event) throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");
  if (!isPlatformAdmin(role) && event.organizer_id !== userId) {
    throw new AppError(403, "FORBIDDEN", "This event belongs to another organizer");
  }
  return event;
}

router.get(
  "/",
  asyncHandler(async (req, res) => {
    const page = Math.max(1, Number(req.query.page ?? 1) || 1);
    const limit = Math.min(50, Math.max(1, Number(req.query.limit ?? 20) || 20));
    const offset = (page - 1) * limit;
    const search = String(req.query.search ?? "").trim();
    const venue = String(req.query.venue ?? "").trim();

    const conditions = ["e.status = 'published'"];
    const params: unknown[] = [];

    if (search) {
      params.push(`%${search}%`);
      conditions.push(`(e.title ILIKE $${params.length} OR e.description ILIKE $${params.length} OR e.venue ILIKE $${params.length})`);
    }
    if (venue) {
      params.push(`%${venue}%`);
      conditions.push(`e.venue ILIKE $${params.length}`);
    }

    const where = conditions.join(" AND ");
    const count = await pool.query<{ count: string }>(
      `SELECT COUNT(*)::text AS count FROM events e WHERE ${where}`,
      params,
    );

    const rows = await pool.query<EventRow>(
      `${eventSelect}
       WHERE ${where}
       ORDER BY e.starts_at ASC
       LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
      [...params, limit, offset],
    );

    const events = await Promise.all(
      rows.rows.map(async (event) => ({
        ...event,
        ticket_types: await getTicketTypes(event.id),
      })),
    );

    res.json({
      data: {
        events,
        pagination: {
          page,
          limit,
          total: Number(count.rows[0].count),
          pages: Math.ceil(Number(count.rows[0].count) / limit),
        },
      },
    });
  }),
);

router.get(
  "/:id",
  asyncHandler(async (req, res) => {
    const event = await getEventWithTypes(param(req, "id"));
    if (!event || event.status !== "published") {
      throw new AppError(404, "EVENT_NOT_FOUND", "Event not found or not published");
    }
    res.json({ data: { event } });
  }),
);

router.post(
  "/",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    const body = eventInput.parse(req.body);

    const eventId = await withTransaction(async (client) => {
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO events (organizer_id, title, description, venue, starts_at, ends_at, image_url)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id`,
        [
          req.user!.id,
          body.title,
          body.description,
          body.venue,
          body.starts_at,
          body.ends_at,
          body.image_url ?? null,
        ],
      );
      const id = inserted.rows[0].id;

      for (const type of body.ticket_types) {
        await client.query(
          `INSERT INTO ticket_types (event_id, name, price_minor, capacity)
           VALUES ($1, $2, $3, $4)`,
          [id, type.name, type.price_minor, type.capacity],
        );
      }
      return id;
    });

    const event = await getEventWithTypes(eventId);
    res.status(201).json({ data: { event } });
  }),
);

router.patch(
  "/:id",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);
    const body = eventUpdateInput.parse(req.body);

    const current = await pool.query<EventRow>(
      "SELECT starts_at, ends_at FROM events WHERE id = $1",
      [param(req, "id")],
    );
    if (!current.rows[0]) throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");

    const startsAt = body.starts_at ?? current.rows[0].starts_at;
    const endsAt = body.ends_at ?? current.rows[0].ends_at;
    if (endsAt <= startsAt) {
      throw new AppError(400, "INVALID_TIME_RANGE", "The event must end after it starts");
    }

    await pool.query(
      `UPDATE events
       SET title = COALESCE($1, title),
           description = COALESCE($2, description),
           venue = COALESCE($3, venue),
           starts_at = COALESCE($4, starts_at),
           ends_at = COALESCE($5, ends_at),
           image_url = CASE WHEN $6::boolean THEN $7 ELSE image_url END,
           updated_at = now()
       WHERE id = $8`,
      [
        body.title ?? null,
        body.description ?? null,
        body.venue ?? null,
        body.starts_at ?? null,
        body.ends_at ?? null,
        Object.prototype.hasOwnProperty.call(body, "image_url"),
        body.image_url ?? null,
        param(req, "id"),
      ],
    );

    const event = await getEventWithTypes(param(req, "id"));
    res.json({ data: { event } });
  }),
);

router.post(
  "/:id/publish",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);

    const types = await pool.query<{ count: string }>(
      "SELECT COUNT(*)::text AS count FROM ticket_types WHERE event_id = $1",
      [param(req, "id")],
    );
    if (Number(types.rows[0].count) === 0) {
      throw new AppError(
        409,
        "NO_TICKET_TYPES",
        "Add at least one ticket type before publishing",
      );
    }

    const result = await pool.query(
      `UPDATE events SET status = 'published', updated_at = now()
       WHERE id = $1 AND status <> 'cancelled' RETURNING id`,
      [param(req, "id")],
    );
    if (result.rowCount === 0) {
      throw new AppError(409, "EVENT_CANCELLED", "A cancelled event cannot be published");
    }

    res.json({ data: { event: await getEventWithTypes(param(req, "id")) } });
  }),
);

router.post(
  "/:id/cancel",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);

    const eventId = param(req, "id");
    const cancelled = await cancelEventAndRelease(eventId);
    const event = await getEventWithTypes(eventId);
    if (cancelled) {
      await writeAuditLog({
        actorId: req.user!.id,
        actorEmail: req.user!.email,
        actorRole: req.user!.role,
        action: "event.cancelled",
        targetType: "event",
        targetId: eventId,
        details: { title: event?.title ?? null, source: "events_api" },
        ip: req.ip,
      });
    }

    res.json({ data: { event } });
  }),
);

router.post(
  "/:id/ticket-types",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);
    const body = ticketTypeInput.parse(req.body);
    const result = await pool.query<TicketTypeRow>(
      `INSERT INTO ticket_types (event_id, name, price_minor, capacity)
       VALUES ($1, $2, $3, $4)
       RETURNING id, event_id, name, price_minor, currency, capacity, sold_count,
                 (capacity - sold_count) AS remaining`,
      [param(req, "id"), body.name, body.price_minor, body.capacity],
    );
    res.status(201).json({ data: { ticket_type: result.rows[0] } });
  }),
);

router.patch(
  "/:id/ticket-types/:ticketTypeId",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);
    const body = ticketTypeUpdateInput.parse(req.body);

    const result = await pool.query<TicketTypeRow>(
      `UPDATE ticket_types
       SET name = COALESCE($1, name),
           price_minor = COALESCE($2, price_minor),
           capacity = COALESCE($3, capacity)
       WHERE id = $4 AND event_id = $5
       RETURNING id, event_id, name, price_minor, currency, capacity, sold_count,
                 (capacity - sold_count) AS remaining`,
      [
        body.name ?? null,
        body.price_minor ?? null,
        body.capacity ?? null,
        param(req, "ticketTypeId"),
        param(req, "id"),
      ],
    );

    if (!result.rows[0]) throw new AppError(404, "TICKET_TYPE_NOT_FOUND", "Ticket type not found");
    res.json({ data: { ticket_type: result.rows[0] } });
  }),
);

router.get(
  "/:id/sales",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);

    const sales = await pool.query(
      `SELECT tt.id, tt.name, tt.capacity, tt.sold_count,
              COALESCE(SUM(bi.quantity) FILTER (WHERE b.status = 'confirmed'), 0)::int AS confirmed_quantity,
              COALESCE(SUM(bi.quantity * bi.unit_price_minor) FILTER (WHERE b.status = 'confirmed'), 0)::int AS revenue_minor
       FROM ticket_types tt
       LEFT JOIN booking_items bi ON bi.ticket_type_id = tt.id
       LEFT JOIN bookings b ON b.id = bi.booking_id
       WHERE tt.event_id = $1
       GROUP BY tt.id
       ORDER BY tt.price_minor ASC`,
      [param(req, "id")],
    );

    const totals = await pool.query(
      `SELECT
         COALESCE(SUM(b.total_minor) FILTER (WHERE b.status = 'confirmed'), 0)::int AS revenue_minor,
         COUNT(*) FILTER (WHERE b.status = 'confirmed')::int AS confirmed_bookings,
         COUNT(*) FILTER (WHERE b.status = 'pending')::int AS pending_bookings,
         COUNT(*)::int AS total_bookings
       FROM bookings b WHERE b.event_id = $1`,
      [param(req, "id")],
    );

    const checkins = await pool.query<{ checked_in: string; valid: string }>(
      `SELECT
         COUNT(*) FILTER (WHERE t.status = 'used')::text AS checked_in,
         COUNT(*) FILTER (WHERE t.status = 'valid')::text AS valid
       FROM tickets t
       JOIN bookings b ON b.id = t.booking_id
       WHERE b.event_id = $1 AND b.status = 'confirmed'`,
      [param(req, "id")],
    );

    res.json({
      data: {
        ticket_types: sales.rows,
        totals: totals.rows[0],
        checkins: {
          checked_in: Number(checkins.rows[0]?.checked_in ?? 0),
          valid: Number(checkins.rows[0]?.valid ?? 0),
        },
      },
    });
  }),
);

router.get(
  "/:id/attendees",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);
    const result = await pool.query(
      `SELECT t.id, t.short_code, t.attendee_name, t.status, t.used_at,
              tt.name AS ticket_type_name, b.id AS booking_id,
              u.full_name, u.email, u.phone
       FROM tickets t
       JOIN bookings b ON b.id = t.booking_id
       JOIN users u ON u.id = b.user_id
       JOIN ticket_types tt ON tt.id = t.ticket_type_id
       WHERE b.event_id = $1 AND b.status = 'confirmed'
       ORDER BY t.created_at ASC`,
      [param(req, "id")],
    );
    res.json({ data: { attendees: result.rows } });
  }),
);

router.get(
  "/:id/scan-manifest",
  requireAuth,
  requireRole("organizer", ...PLATFORM_ADMIN_ROLES),
  asyncHandler(async (req, res) => {
    await requireOwner(param(req, "id"), req.user!.id, req.user!.role);
    const result = await pool.query(
      `SELECT t.id, t.token_hash, t.short_code, t.attendee_name, t.status,
              tt.name AS ticket_type_name
       FROM tickets t
       JOIN bookings b ON b.id = t.booking_id
       JOIN ticket_types tt ON tt.id = t.ticket_type_id
       WHERE b.event_id = $1 AND b.status = 'confirmed'`,
      [param(req, "id")],
    );
    res.json({
      data: {
        event_id: param(req, "id"),
        generated_at: new Date().toISOString(),
        tickets: result.rows,
      },
    });
  }),
);

export default router;
