import { Router } from "express";
import { pool } from "../db";
import { requireAuth, requireRole } from "../auth/jwt";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";

const router = Router();

router.use(requireAuth, requireRole("admin"));

router.get(
  "/stats",
  asyncHandler(async (_req, res) => {
    const result = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM users) AS users,
         (SELECT COUNT(*)::int FROM users WHERE role = 'organizer') AS organizers,
         (SELECT COUNT(*)::int FROM events) AS events,
         (SELECT COUNT(*)::int FROM events WHERE status = 'published') AS published_events,
         (SELECT COUNT(*)::int FROM bookings) AS bookings,
         (SELECT COUNT(*)::int FROM bookings WHERE status = 'confirmed') AS confirmed_bookings,
         (SELECT COALESCE(SUM(amount_minor), 0)::int FROM payments WHERE status = 'succeeded') AS gross_revenue_minor,
         (SELECT COUNT(*)::int FROM tickets WHERE status = 'used') AS checked_in_tickets,
         (SELECT COUNT(*)::int FROM tickets) AS tickets`,
    );
    res.json({ data: { stats: result.rows[0] } });
  }),
);

router.get(
  "/users",
  asyncHandler(async (req, res) => {
    const page = Math.max(1, Number(req.query.page ?? 1) || 1);
    const limit = Math.min(100, Math.max(1, Number(req.query.limit ?? 50) || 50));
    const search = String(req.query.search ?? "").trim();

    const result = await pool.query(
      `SELECT id, email, phone, full_name, role, created_at
       FROM users
       WHERE ($1 = '' OR email ILIKE '%' || $1 || '%' OR full_name ILIKE '%' || $1 || '%')
       ORDER BY created_at DESC
       LIMIT $2 OFFSET $3`,
      [search, limit, (page - 1) * limit],
    );
    res.json({ data: { users: result.rows, pagination: { page, limit } } });
  }),
);

router.get(
  "/events",
  asyncHandler(async (req, res) => {
    const search = String(req.query.search ?? "").trim();
    const result = await pool.query(
      `SELECT e.id, e.title, e.venue, e.starts_at, e.status,
              u.full_name AS organizer_name, u.email AS organizer_email
       FROM events e JOIN users u ON u.id = e.organizer_id
       WHERE ($1 = '' OR e.title ILIKE '%' || $1 || '%' OR u.full_name ILIKE '%' || $1 || '%')
       ORDER BY e.created_at DESC
       LIMIT 100`,
      [search],
    );
    res.json({ data: { events: result.rows } });
  }),
);

router.post(
  "/events/:id/cancel",
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `UPDATE events SET status = 'cancelled', updated_at = now()
       WHERE id = $1 RETURNING id`,
      [req.params.id],
    );
    if (!result.rows[0]) throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");
    res.json({ data: { cancelled: true } });
  }),
);

router.post(
  "/users/:id/role",
  asyncHandler(async (req, res) => {
    const role = req.body?.role;
    if (!["attendee", "organizer", "admin"].includes(role)) {
      throw new AppError(400, "INVALID_ROLE", "Role must be attendee, organizer or admin");
    }
    const result = await pool.query(
      `UPDATE users SET role = $1 WHERE id = $2
       RETURNING id, email, full_name, role`,
      [role, req.params.id],
    );
    if (!result.rows[0]) throw new AppError(404, "USER_NOT_FOUND", "User not found");
    res.json({ data: { user: result.rows[0] } });
  }),
);

export default router;
