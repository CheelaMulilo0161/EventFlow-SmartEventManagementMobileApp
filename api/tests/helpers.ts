import crypto from "crypto";
import request from "supertest";
import { app } from "../src/app";
import { pool } from "../src/db";
import { runMigrations } from "../src/db/migrate";

export type TestUser = {
  token: string;
  user: { id: string; email: string; full_name: string; role: string };
};

export async function migrateOnce() {
  await runMigrations(pool);
}

export async function resetDatabase() {
  await pool.query(
    `TRUNCATE TABLE webhook_events, tickets, payments, booking_items, bookings,
                    ticket_types, events, users CASCADE`,
  );
}

export async function registerUser(
  role: "attendee" | "organizer" | "admin" = "attendee",
  email = `user-${crypto.randomUUID()}@test.zm`,
): Promise<TestUser> {
  const response = await request(app).post("/api/auth/register").send({
    email,
    password: "Password123!",
    full_name: `Test ${role}`,
    phone: `+26097${Math.floor(Math.random() * 1_000_000).toString().padStart(6, "0")}`,
    role: role === "admin" ? "attendee" : role,
  });
  if (response.status !== 201) {
    throw new Error(`Registration failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.data;
}

export async function createEvent(
  organizerToken: string,
  options: {
    title?: string;
    daysFromNow?: number;
    ticketTypes?: Array<{ name: string; price_minor: number; capacity: number }>;
  } = {},
) {
  const starts = new Date(Date.now() + (options.daysFromNow ?? 10) * 86_400_000);
  const ends = new Date(starts.getTime() + 4 * 3_600_000);
  const response = await request(app)
    .post("/api/events")
    .set("Authorization", `Bearer ${organizerToken}`)
    .send({
      title: options.title ?? `Test Event ${crypto.randomUUID().slice(0, 8)}`,
      description: "A test event",
      venue: "Test Venue, Lusaka",
      starts_at: starts.toISOString(),
      ends_at: ends.toISOString(),
      ticket_types: options.ticketTypes ?? [
        { name: "General", price_minor: 10_000, capacity: 10 },
      ],
    });
  if (response.status !== 201) {
    throw new Error(`Event creation failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.data.event as {
    id: string;
    title: string;
    ticket_types: Array<{
      id: string;
      name: string;
      price_minor: number;
      capacity: number;
      sold_count: number;
      remaining: number;
    }>;
  };
}

export async function publishEvent(token: string, eventId: string) {
  const response = await request(app)
    .post(`/api/events/${eventId}/publish`)
    .set("Authorization", `Bearer ${token}`);
  if (response.status !== 200) {
    throw new Error(`Publish failed: ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.data.event;
}

export async function bookTickets(
  token: string,
  eventId: string,
  ticketTypeId: string,
  quantity = 1,
  idempotencyKey: string = crypto.randomUUID(),
) {
  return request(app)
    .post(`/api/events/${eventId}/bookings`)
    .set("Authorization", `Bearer ${token}`)
    .set("Idempotency-Key", idempotencyKey)
    .send({ items: [{ ticket_type_id: ticketTypeId, quantity }] });
}
