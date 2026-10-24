import request from "supertest";
import { app } from "../src/app";
import { pool } from "../src/db";
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

async function createSuperAdmin(email: string) {
  const account = await registerUser("attendee", email);
  await pool.query("UPDATE users SET role = 'super_admin' WHERE id = $1", [
    account.user.id,
  ]);
  return account;
}

async function loginAsSuperAdmin(email: string) {
  const agent = request.agent(app);
  const response = await agent
    .post("/admin/login")
    .type("form")
    .send({ email, password: "Password123!" });
  expect(response.status).toBe(302);
  expect(response.headers.location).toBe("/admin");
  return agent;
}

function csrfFrom(html: string): string {
  const match = /name="_csrf" value="([^"]+)"/.exec(html);
  if (!match) throw new Error("CSRF token missing from dashboard HTML");
  return match[1];
}

describe("super admin dashboard", () => {
  test("unauthenticated visitors are redirected and non-super admins are denied", async () => {
    const redirect = await request(app).get("/admin");
    expect(redirect.status).toBe(302);
    expect(redirect.headers.location).toBe("/admin/login");

    const admin = await registerUser("admin", "admin-dashboard@test.zm");
    await pool.query("UPDATE users SET role = 'admin' WHERE id = $1", [admin.user.id]);
    const denied = await request(app)
      .post("/admin/login")
      .type("form")
      .send({ email: "admin-dashboard@test.zm", password: "Password123!" });
    expect(denied.status).toBe(403);
  });

  test("a super admin can sign in and update a user role with CSRF protection", async () => {
    const superAdmin = await createSuperAdmin("super-dashboard@test.zm");
    const target = await registerUser("attendee", "target-dashboard@test.zm");
    const agent = await loginAsSuperAdmin(superAdmin.user.email);

    const dashboard = await agent.get("/admin");
    expect(dashboard.status).toBe(200);
    expect(dashboard.text).toContain("Latest events");
    const csrf = csrfFrom(dashboard.text);

    const missingCsrf = await agent
      .post(`/admin/users/${target.user.id}/role`)
      .type("form")
      .send({ role: "organizer" });
    expect(missingCsrf.status).toBe(403);

    const update = await agent
      .post(`/admin/users/${target.user.id}/role`)
      .type("form")
      .send({ _csrf: csrf, role: "organizer" });
    expect(update.status).toBe(302);
    expect(update.headers.location).toBe("/admin/users?notice=role-updated");

    const role = await pool.query<{ role: string }>(
      "SELECT role FROM users WHERE id = $1",
      [target.user.id],
    );
    expect(role.rows[0].role).toBe("organizer");

    const audit = await pool.query<{ action: string; actor_email: string }>(
      "SELECT action, actor_email FROM audit_logs WHERE action = 'user.role_changed'",
    );
    expect(audit.rows).toHaveLength(1);
    expect(audit.rows[0].actor_email).toBe(superAdmin.user.email);
  });

  test("cancelling an event releases capacity and writes an audit entry", async () => {
    const organizer = await registerUser("organizer");
    const attendee = await registerUser("attendee");
    const event = await createEvent(organizer.token, {
      ticketTypes: [{ name: "General", price_minor: 10_000, capacity: 4 }],
    });
    await publishEvent(organizer.token, event.id);
    const booking = await bookTickets(
      attendee.token,
      event.id,
      event.ticket_types[0].id,
      2,
    );
    expect(booking.status).toBe(201);

    const superAdmin = await createSuperAdmin("cancel-dashboard@test.zm");
    const agent = await loginAsSuperAdmin(superAdmin.user.email);
    const page = await agent.get(`/admin/events/${event.id}/cancel`);
    expect(page.status).toBe(200);
    const csrf = csrfFrom(page.text);

    const response = await agent
      .post(`/admin/events/${event.id}/cancel`)
      .type("form")
      .send({ _csrf: csrf, reason: "Venue unavailable" });
    expect(response.status).toBe(302);

    const state = await pool.query<{
      event_status: string;
      booking_status: string;
      sold_count: number;
    }>(
      `SELECT e.status AS event_status,
              b.status AS booking_status,
              tt.sold_count
         FROM events e
         JOIN bookings b ON b.event_id = e.id
         JOIN ticket_types tt ON tt.event_id = e.id
        WHERE e.id = $1 AND b.id = $2`,
      [event.id, booking.body.data.booking.id],
    );
    expect(state.rows[0].event_status).toBe("cancelled");
    expect(state.rows[0].booking_status).toBe("cancelled");
    expect(state.rows[0].sold_count).toBe(0);

    const audit = await pool.query<{ action: string; details: { reason: string } }>(
      "SELECT action, details FROM audit_logs WHERE target_id = $1",
      [event.id],
    );
    expect(audit.rows[0].action).toBe("event.cancelled");
    expect(audit.rows[0].details.reason).toBe("Venue unavailable");
  });
});
