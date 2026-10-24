import { Router } from "express";
import { pool } from "../db";
import { requireAuth, requireRole } from "../auth/jwt";
import { PLATFORM_ADMIN_ROLES, isPlatformAdmin } from "../auth/roles";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";

const router = Router();

router.use(requireAuth, requireRole("organizer", ...PLATFORM_ADMIN_ROLES));

router.get(
  "/events",
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT e.id, e.title, e.venue, e.starts_at, e.ends_at, e.status,
              e.image_url, e.created_at,
              COALESCE(SUM(b.total_minor) FILTER (WHERE b.status = 'confirmed'), 0)::int AS revenue_minor,
              COUNT(DISTINCT b.id) FILTER (WHERE b.status = 'confirmed')::int AS confirmed_bookings,
              (SELECT COALESCE(SUM(tt.capacity), 0)::int FROM ticket_types tt WHERE tt.event_id = e.id) AS capacity,
              (SELECT COALESCE(SUM(tt.sold_count), 0)::int FROM ticket_types tt WHERE tt.event_id = e.id) AS sold_count
       FROM events e
       LEFT JOIN bookings b ON b.event_id = e.id
       WHERE ($1::boolean OR e.organizer_id = $2)
       GROUP BY e.id
       ORDER BY e.starts_at DESC`,
      [isPlatformAdmin(req.user!.role), req.user!.id],
    );
    res.json({ data: { events: result.rows } });
  }),
);

router.get(
  "/events/:id",
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT e.id, e.organizer_id, e.title, e.description, e.venue,
              e.starts_at, e.ends_at, e.status, e.image_url, e.created_at, e.updated_at
       FROM events e WHERE e.id = $1`,
      [req.params.id],
    );
    const event = result.rows[0];
    if (!event) throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");
    if (!isPlatformAdmin(req.user!.role) && event.organizer_id !== req.user!.id) {
      throw new AppError(403, "FORBIDDEN", "This event belongs to another organizer");
    }

    const types = await pool.query(
      `SELECT id, event_id, name, price_minor, currency, capacity, sold_count,
              (capacity - sold_count) AS remaining
       FROM ticket_types WHERE event_id = $1 ORDER BY price_minor ASC`,
      [req.params.id],
    );
    res.json({ data: { event: { ...event, ticket_types: types.rows } } });
  }),
);

router.get(
  "/dashboard",
  asyncHandler(async (req, res) => {
    const result = await pool.query(
      `SELECT
         (SELECT COUNT(*)::int FROM events e WHERE ($1::boolean OR e.organizer_id = $2)) AS events,
         (SELECT COUNT(*)::int FROM events e WHERE e.status = 'published' AND ($1::boolean OR e.organizer_id = $2)) AS published_events,
         (SELECT COALESCE(SUM(b.total_minor), 0)::int
            FROM bookings b JOIN events e ON e.id = b.event_id
           WHERE b.status = 'confirmed' AND ($1::boolean OR e.organizer_id = $2)) AS revenue_minor,
         (SELECT COUNT(DISTINCT b.id)::int
            FROM bookings b JOIN events e ON e.id = b.event_id
           WHERE b.status = 'confirmed' AND ($1::boolean OR e.organizer_id = $2)) AS confirmed_bookings,
         (SELECT COUNT(*)::int
            FROM tickets t
            JOIN bookings b ON b.id = t.booking_id
            JOIN events e ON e.id = b.event_id
           WHERE t.status = 'used' AND ($1::boolean OR e.organizer_id = $2)) AS checked_in`,
      [isPlatformAdmin(req.user!.role), req.user!.id],
    );
    res.json({ data: { dashboard: result.rows[0] } });
  }),
);

export default router;
