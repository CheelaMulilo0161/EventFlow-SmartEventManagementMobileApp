import request from "supertest";
import { app } from "../src/app";
import { pool } from "../src/db";
import { releaseExpiredBookings } from "../src/services/bookings";
import {
  bookTickets,
  createEvent,
  migrateOnce,
  publishEvent,
  registerUser,
  resetDatabase,
} from "./helpers";

beforeAll(async () => {
  await migrateOnce();
});

beforeEach(async () => {
  await resetDatabase();
});

afterAll(async () => {
  await pool.end();
});

describe("booking engine", () => {
  test("20 parallel requests for the last ticket produce exactly one booking", async () => {
    const organizer = await registerUser("organizer");
    const event = await createEvent(organizer.token, {
      ticketTypes: [{ name: "Last Seat", price_minor: 10_000, capacity: 1 }],
    });
    await publishEvent(organizer.token, event.id);
    const ticketTypeId = event.ticket_types[0].id;

    const attendees = await Promise.all(
      Array.from({ length: 20 }, () => registerUser("attendee")),
    );

    const responses = await Promise.all(
      attendees.map((attendee) => bookTickets(attendee.token, event.id, ticketTypeId, 1)),
    );

    const successes = responses.filter((response) => response.status === 201);
    const soldOut = responses.filter(
      (response) => response.status === 409 && response.body.error?.code === "SOLD_OUT",
    );

    expect(successes).toHaveLength(1);
    expect(soldOut).toHaveLength(19);

    const state = await pool.query<{ sold_count: number; bookings: string }>(
      `SELECT tt.sold_count,
              (SELECT COUNT(*)::text FROM bookings WHERE event_id = $1) AS bookings
       FROM ticket_types tt WHERE tt.id = $2`,
      [event.id, ticketTypeId],
    );
    expect(state.rows[0].sold_count).toBe(1);
    expect(Number(state.rows[0].bookings)).toBe(1);
  });

  test("a retried booking request with the same idempotency key is not duplicated", async () => {
    const organizer = await registerUser("organizer");
    const attendee = await registerUser("attendee");
    const event = await createEvent(organizer.token, {
      ticketTypes: [{ name: "General", price_minor: 10_000, capacity: 5 }],
    });
    await publishEvent(organizer.token, event.id);
    const ticketTypeId = event.ticket_types[0].id;
    const key = "retry-key-123456";

    const first = await bookTickets(attendee.token, event.id, ticketTypeId, 2, key);
    const second = await bookTickets(attendee.token, event.id, ticketTypeId, 2, key);

    expect(first.status).toBe(201);
    expect(second.status).toBe(201);
    expect(second.body.data.booking.id).toBe(first.body.data.booking.id);

    const state = await pool.query<{ sold_count: number; bookings: string; tickets: string }>(
      `SELECT tt.sold_count,
              (SELECT COUNT(*)::text FROM bookings WHERE event_id = $1) AS bookings,
              (SELECT COUNT(*)::text FROM tickets t
                 JOIN bookings b ON b.id = t.booking_id WHERE b.event_id = $1) AS tickets
       FROM ticket_types tt WHERE tt.id = $2`,
      [event.id, ticketTypeId],
    );
    expect(state.rows[0].sold_count).toBe(2);
    expect(Number(state.rows[0].bookings)).toBe(1);
    expect(Number(state.rows[0].tickets)).toBe(2);
  });

  test("a booking hold that expires releases capacity", async () => {
    const organizer = await registerUser("organizer");
    const attendee = await registerUser("attendee");
    const event = await createEvent(organizer.token, {
      ticketTypes: [{ name: "General", price_minor: 5_000, capacity: 3 }],
    });
    await publishEvent(organizer.token, event.id);
    const ticketTypeId = event.ticket_types[0].id;

    const booking = await bookTickets(attendee.token, event.id, ticketTypeId, 2);
    expect(booking.status).toBe(201);

    await pool.query(
      "UPDATE bookings SET expires_at = now() - interval '1 minute' WHERE id = $1",
      [booking.body.data.booking.id],
    );

    const released = await releaseExpiredBookings();
    expect(released).toBe(1);

    const state = await pool.query<{ sold_count: number; status: string }>(
      `SELECT tt.sold_count, b.status
       FROM ticket_types tt JOIN bookings b ON b.event_id = tt.event_id
       WHERE tt.id = $1 AND b.id = $2`,
      [ticketTypeId, booking.body.data.booking.id],
    );
    expect(state.rows[0].sold_count).toBe(0);
    expect(state.rows[0].status).toBe("expired");
  });
});

describe("ticket scanning", () => {
  test("a valid ticket can only be checked in once", async () => {
    const organizer = await registerUser("organizer");
    const attendee = await registerUser("attendee");
    const event = await createEvent(organizer.token, {
      ticketTypes: [{ name: "General", price_minor: 10_000, capacity: 5 }],
    });
    await publishEvent(organizer.token, event.id);
    const ticketTypeId = event.ticket_types[0].id;

    const bookingResponse = await bookTickets(attendee.token, event.id, ticketTypeId, 1);
    expect(bookingResponse.status).toBe(201);
    const bookingId = bookingResponse.body.data.booking.id;

    const payment = await request(app)
      .post(`/api/bookings/${bookingId}/pay`)
      .set("Authorization", `Bearer ${attendee.token}`)
      .send({ phone: "+260971000000", network: "MTN" });
    expect(payment.status).toBe(201);
    const reference = payment.body.data.payment.provider_reference;

    const confirmation = await request(app)
      .post(`/api/payments/${reference}/simulate`)
      .set("Authorization", `Bearer ${attendee.token}`);
    expect(confirmation.status).toBe(200);

    const token = confirmation.body.data.booking.tickets[0].token as string;

    const firstScan = await request(app)
      .post("/api/tickets/scan")
      .set("Authorization", `Bearer ${organizer.token}`)
      .send({ token, event_id: event.id });
    expect(firstScan.status).toBe(200);
    expect(firstScan.body.data.result.status).toBe("valid");

    const secondScan = await request(app)
      .post("/api/tickets/scan")
      .set("Authorization", `Bearer ${organizer.token}`)
      .send({ token, event_id: event.id });
    expect(secondScan.status).toBe(200);
    expect(secondScan.body.data.result.status).toBe("already_used");

    const ticket = await pool.query<{ status: string; used_at: Date | null }>(
      "SELECT status, used_at FROM tickets WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
      [token],
    );
    expect(ticket.rows[0].status).toBe("used");
    expect(ticket.rows[0].used_at).not.toBeNull();
  });

  test("a garbage token is rejected", async () => {
    const organizer = await registerUser("organizer");
    const response = await request(app)
      .post("/api/tickets/scan")
      .set("Authorization", `Bearer ${organizer.token}`)
      .send({ token: "definitely-not-a-real-ticket-token" });

    expect(response.status).toBe(200);
    expect(response.body.data.result.status).toBe("invalid");
  });
});
