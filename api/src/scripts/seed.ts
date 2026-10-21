import "dotenv/config";
import bcrypt from "bcryptjs";
import crypto from "crypto";
import { config } from "../config";
import { pool, withTransaction } from "../db";
import { runMigrations } from "../db/migrate";
import { createShortCode, createTicketToken, sha256 } from "../utils/crypto";

const DEMO_PASSWORD = "Password123!";

async function upsertUser(
  email: string,
  fullName: string,
  phone: string,
  role: "attendee" | "organizer" | "admin",
) {
  const hash = await bcrypt.hash(DEMO_PASSWORD, config.bcryptRounds);
  const result = await pool.query<{ id: string }>(
    `INSERT INTO users (email, phone, full_name, password_hash, role)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (email) DO UPDATE
       SET full_name = EXCLUDED.full_name,
           phone = EXCLUDED.phone,
           role = EXCLUDED.role
     RETURNING id`,
    [email, phone, fullName, hash, role],
  );
  return result.rows[0].id;
}

async function ensureEvent(input: {
  organizerId: string;
  title: string;
  description: string;
  venue: string;
  daysFromNow: number;
  durationHours: number;
  types: Array<{ name: string; price: number; capacity: number }>;
}) {
  const existing = await pool.query<{ id: string }>(
    "SELECT id FROM events WHERE organizer_id = $1 AND title = $2 LIMIT 1",
    [input.organizerId, input.title],
  );
  if (existing.rows[0]) return existing.rows[0].id;

  return withTransaction(async (client) => {
    const startsAt = new Date(Date.now() + input.daysFromNow * 86_400_000);
    startsAt.setHours(18, 0, 0, 0);
    const endsAt = new Date(startsAt.getTime() + input.durationHours * 3_600_000);

    const event = await client.query<{ id: string }>(
      `INSERT INTO events (organizer_id, title, description, venue, starts_at, ends_at, status)
       VALUES ($1, $2, $3, $4, $5, $6, 'published')
       RETURNING id`,
      [
        input.organizerId,
        input.title,
        input.description,
        input.venue,
        startsAt,
        endsAt,
      ],
    );
    for (const type of input.types) {
      await client.query(
        `INSERT INTO ticket_types (event_id, name, price_minor, capacity)
         VALUES ($1, $2, $3, $4)`,
        [event.rows[0].id, type.name, type.price, type.capacity],
      );
    }
    return event.rows[0].id;
  });
}

async function createDemoBooking(attendeeId: string, eventId: string, ticketTypeId: string) {
  const exists = await pool.query(
    "SELECT id FROM bookings WHERE user_id = $1 AND idempotency_key = 'seed-demo-tickets'",
    [attendeeId],
  );
  if (exists.rows[0]) return;

  await withTransaction(async (client) => {
    const reserved = await client.query<{ price_minor: number }>(
      `UPDATE ticket_types SET sold_count = sold_count + 2
       WHERE id = $1 AND sold_count + 2 <= capacity
       RETURNING price_minor`,
      [ticketTypeId],
    );
    if (!reserved.rows[0]) return;

    const booking = await client.query<{ id: string }>(
      `INSERT INTO bookings (user_id, event_id, status, total_minor, currency, idempotency_key, expires_at)
       VALUES ($1, $2, 'confirmed', $3, 'ZMW', 'seed-demo-tickets', NULL)
       RETURNING id`,
      [attendeeId, eventId, reserved.rows[0].price_minor * 2],
    );
    const bookingId = booking.rows[0].id;

    await client.query(
      `INSERT INTO booking_items (booking_id, ticket_type_id, quantity, unit_price_minor)
       VALUES ($1, $2, 2, $3)`,
      [bookingId, ticketTypeId, reserved.rows[0].price_minor],
    );
    await client.query(
      `INSERT INTO payments (booking_id, provider, provider_reference, amount_minor, currency, status)
       VALUES ($1, 'simulated', $2, $3, 'ZMW', 'succeeded')`,
      [bookingId, `SEED-${crypto.randomUUID()}`, reserved.rows[0].price_minor * 2],
    );

    for (let i = 0; i < 2; i += 1) {
      const ticketId = crypto.randomUUID();
      await client.query(
        `INSERT INTO tickets
           (id, booking_id, ticket_type_id, token_hash, short_code, attendee_name)
         VALUES ($1, $2, $3, $4, $5, 'Demo Attendee')`,
        [
          ticketId,
          bookingId,
          ticketTypeId,
          sha256(createTicketToken(ticketId)),
          createShortCode(),
        ],
      );
    }
  });
}

async function main() {
  await runMigrations(pool);

  const organizerId = await upsertUser(
    "organizer@eventflow.zm",
    "Mwila Organizer",
    "+260971000001",
    "organizer",
  );
  const attendeeId = await upsertUser(
    "attendee@eventflow.zm",
    "Demo Attendee",
    "+260971000002",
    "attendee",
  );
  await upsertUser("admin@eventflow.zm", "Platform Admin", "+260971000003", "admin");

  const concertId = await ensureEvent({
    organizerId,
    title: "Lusaka Live Concert",
    description:
      "A night of Zambian music, food and culture. Bring your friends and enjoy live performances from top local artists.",
    venue: "Mulungushi International Conference Centre, Lusaka",
    daysFromNow: 14,
    durationHours: 5,
    types: [
      { name: "Early Bird", price: 7_500, capacity: 20 },
      { name: "General", price: 10_000, capacity: 200 },
      { name: "VIP", price: 25_000, capacity: 50 },
    ],
  });

  await ensureEvent({
    organizerId,
    title: "Lusaka Startup Mixer",
    description:
      "Meet founders, developers and investors building the next generation of Zambian companies.",
    venue: "BongoHive, Lusaka",
    daysFromNow: 21,
    durationHours: 3,
    types: [
      { name: "General", price: 0, capacity: 100 },
      { name: "Founder", price: 15_000, capacity: 30 },
    ],
  });

  const general = await pool.query<{ id: string }>(
    "SELECT id FROM ticket_types WHERE event_id = $1 AND name = 'General'",
    [concertId],
  );
  if (general.rows[0]) {
    await createDemoBooking(attendeeId, concertId, general.rows[0].id);
  }

  console.log("Seed complete. Demo accounts (password: Password123!):");
  console.log("  attendee@eventflow.zm");
  console.log("  organizer@eventflow.zm");
  console.log("  admin@eventflow.zm");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
