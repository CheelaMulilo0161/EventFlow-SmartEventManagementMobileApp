import { NextFunction, Request, Response, Router } from "express";
import bcrypt from "bcryptjs";
import { pool, withTransaction } from "../db";
import { AppError } from "../http/errors";
import { cancelEventAndRelease } from "../services/events";
import { writeAuditLog } from "../admin/audit";
import {
  AdminUser,
  clearAdminSessionCookie,
  readAdminSession,
  requireCsrf,
  requireSuperAdmin,
  setAdminSessionCookie,
} from "../admin/session";

const router = Router();

const ROLES = ["attendee", "organizer", "admin", "super_admin"] as const;
const EVENT_STATUSES = ["draft", "published", "cancelled"] as const;
const BOOKING_STATUSES = ["pending", "confirmed", "cancelled", "expired"] as const;
const ROLE_LABELS: Record<string, string> = {
  attendee: "Attendee",
  organizer: "Organizer",
  admin: "Admin",
  super_admin: "Super admin",
};
const NOTICES: Record<string, string> = {
  "role-updated": "The user's role was updated.",
  "event-cancelled": "The event was cancelled and its active bookings were released.",
  "event-already-cancelled": "That event was already cancelled. No further changes were made.",
};
const ERRORS: Record<string, string> = {
  "invalid-role": "That role is not valid.",
  "invalid-request": "The request was invalid. Reload the page and try again.",
  "self-demote": "You cannot remove your own super admin access. Ask another super admin to do it.",
  "last-super-admin": "At least one super admin must remain on the platform.",
  "user-not-found": "That user no longer exists.",
  "event-not-found": "That event no longer exists.",
  "event-already-cancelled": "That event is already cancelled.",
};

const LOGIN_WINDOW_MS = 15 * 60 * 1000;
const LOGIN_MAX_ATTEMPTS = 8;
const loginAttempts = new Map<string, { count: number; resetAt: number }>();

function text(value: unknown, maxLength = 200): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value,
  );
}

function formatDate(value: unknown): string {
  if (!value) return "—";
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: "Africa/Lusaka",
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatMoney(value: unknown, currency = "ZMW"): string {
  const amount = Number(value ?? 0) / 100;
  return `${currency} ${amount.toLocaleString("en-ZM", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`;
}

function formatNumber(value: unknown): string {
  return Number(value ?? 0).toLocaleString("en-ZM");
}

function renderErrorPage(res: Response, status: number, message: string): void {
  res.status(status).render("admin/error", {
    title: status === 404 ? "Not found" : "Something went wrong",
    message,
    admin: res.locals.admin ?? null,
    csrf: res.locals.csrf ?? "",
    active: "",
  });
}

function webAsync(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      await handler(req, res, next);
    } catch (error) {
      if (res.headersSent) {
        next(error);
        return;
      }
      console.error(error);
      if (error instanceof AppError) {
        renderErrorPage(res, error.statusCode, error.message);
        return;
      }
      renderErrorPage(res, 500, "An unexpected error occurred. Please try again.");
    }
  };
}

function adminActor(res: Response): AdminUser {
  return res.locals.admin as AdminUser;
}

function loginKey(req: Request, email: string): string {
  return `${req.ip ?? "unknown"}|${email}`;
}

function loginBlocked(key: string): boolean {
  const attempt = loginAttempts.get(key);
  if (!attempt) return false;
  if (attempt.resetAt <= Date.now()) {
    loginAttempts.delete(key);
    return false;
  }
  return attempt.count >= LOGIN_MAX_ATTEMPTS;
}

function recordLoginFailure(key: string): void {
  if (loginAttempts.size > 5000) {
    for (const [entryKey, attempt] of loginAttempts) {
      if (attempt.resetAt <= Date.now()) loginAttempts.delete(entryKey);
    }
  }
  const current = loginAttempts.get(key);
  if (!current || current.resetAt <= Date.now()) {
    loginAttempts.set(key, { count: 1, resetAt: Date.now() + LOGIN_WINDOW_MS });
    return;
  }
  current.count += 1;
}

router.use((req, res, next) => {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "same-origin");
  res.setHeader("X-Robots-Tag", "noindex, nofollow");
  res.setHeader(
    "Content-Security-Policy",
    "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'none'; form-action 'self'; frame-ancestors 'none'; base-uri 'self'",
  );
  res.locals.formatDate = formatDate;
  res.locals.formatMoney = formatMoney;
  res.locals.formatNumber = formatNumber;
  res.locals.roleLabel = (role: string) => ROLE_LABELS[role] ?? role;
  res.locals.notice = NOTICES[text(req.query.notice, 50)] ?? null;
  res.locals.errorMessage = ERRORS[text(req.query.error, 50)] ?? null;
  res.locals.roles = ROLES;
  next();
});

router.get("/login", (req, res) => {
  if (readAdminSession(req)) {
    res.redirect("/admin");
    return;
  }
  res.render("admin/login", {
    title: "Sign in",
    email: "",
    loginError: null,
  });
});

router.post(
  "/login",
  webAsync(async (req, res) => {
    const email = text(req.body?.email, 254).toLowerCase();
    const password = typeof req.body?.password === "string" ? req.body.password : "";
    const key = loginKey(req, email);

    if (!email || !password) {
      res.status(400).render("admin/login", {
        title: "Sign in",
        email,
        loginError: "Enter your email address and password.",
      });
      return;
    }

    if (loginBlocked(key)) {
      res.status(429).render("admin/login", {
        title: "Sign in",
        email,
        loginError: "Too many sign-in attempts. Wait 15 minutes before trying again.",
      });
      return;
    }

    const result = await pool.query<{
      id: string;
      email: string;
      full_name: string;
      role: string;
      password_hash: string;
    }>(
      "SELECT id, email, full_name, role, password_hash FROM users WHERE email = $1",
      [email],
    );
    const user = result.rows[0];
    const passwordMatches = user ? await bcrypt.compare(password, user.password_hash) : false;

    if (!user || !passwordMatches) {
      recordLoginFailure(key);
      await writeAuditLog({
        actorId: null,
        actorEmail: email,
        actorRole: "anonymous",
        action: "auth.login_failed",
        targetType: "admin_dashboard",
        details: { reason: "invalid_credentials" },
        ip: req.ip,
      });
      res.status(401).render("admin/login", {
        title: "Sign in",
        email,
        loginError: "Email or password is incorrect.",
      });
      return;
    }

    if (user.role !== "super_admin") {
      recordLoginFailure(key);
      await writeAuditLog({
        actorId: user.id,
        actorEmail: user.email,
        actorRole: user.role,
        action: "auth.login_denied",
        targetType: "admin_dashboard",
        details: { reason: "not_super_admin" },
        ip: req.ip,
      });
      res.status(403).render("admin/login", {
        title: "Sign in",
        email,
        loginError: "This account cannot access the super admin dashboard.",
      });
      return;
    }

    loginAttempts.delete(key);
    setAdminSessionCookie(req, res, user.id);
    await writeAuditLog({
      actorId: user.id,
      actorEmail: user.email,
      actorRole: user.role,
      action: "auth.login",
      targetType: "admin_dashboard",
      ip: req.ip,
    });
    res.redirect("/admin");
  }),
);

router.use(requireSuperAdmin);

router.post(
  "/logout",
  requireCsrf,
  webAsync(async (_req, res) => {
    const admin = adminActor(res);
    await writeAuditLog({
      actorId: admin.id,
      actorEmail: admin.email,
      actorRole: admin.role,
      action: "auth.logout",
      targetType: "admin_dashboard",
      ip: _req.ip,
    });
    clearAdminSessionCookie(res);
    res.redirect("/admin/login");
  }),
);

router.get(
  "/",
  webAsync(async (_req, res) => {
    const [statsResult, eventsResult, usersResult, auditResult] = await Promise.all([
      pool.query(
        `SELECT
           (SELECT COUNT(*) FROM users)::int AS users,
           (SELECT COUNT(*) FROM users WHERE role = 'organizer')::int AS organizers,
           (SELECT COUNT(*) FROM events)::int AS events,
           (SELECT COUNT(*) FROM events WHERE status = 'published')::int AS published_events,
           (SELECT COUNT(*) FROM bookings)::int AS bookings,
           (SELECT COUNT(*) FROM bookings WHERE status = 'confirmed')::int AS confirmed_bookings,
           (SELECT COUNT(*) FROM tickets WHERE status = 'valid')::int AS valid_tickets,
           (SELECT COALESCE(SUM(amount_minor), 0) FROM payments WHERE status = 'succeeded')::bigint AS gross_minor`,
      ),
      pool.query(
        `SELECT e.id, e.title, e.status, e.starts_at, e.venue, e.created_at,
                u.full_name AS organizer_name,
                (SELECT COALESCE(SUM(bi.quantity), 0)
                   FROM booking_items bi
                   JOIN bookings b ON b.id = bi.booking_id
                  WHERE b.event_id = e.id AND b.status IN ('pending', 'confirmed'))::int AS tickets_sold,
                (SELECT COALESCE(SUM(p.amount_minor), 0)
                   FROM payments p
                   JOIN bookings b ON b.id = p.booking_id
                  WHERE b.event_id = e.id AND p.status = 'succeeded')::bigint AS revenue_minor
           FROM events e
           JOIN users u ON u.id = e.organizer_id
          ORDER BY e.created_at DESC
          LIMIT 6`,
      ),
      pool.query(
        `SELECT id, full_name, email, role, created_at
           FROM users
          ORDER BY created_at DESC
          LIMIT 5`,
      ),
      pool.query(
        `SELECT id, actor_email, actor_role, action, target_type, target_id, created_at
           FROM audit_logs
          ORDER BY created_at DESC
          LIMIT 6`,
      ),
    ]);

    res.render("admin/dashboard", {
      title: "Overview",
      subtitle: "Platform health, activity and the latest commercial signals.",
      active: "dashboard",
      stats: statsResult.rows[0],
      recentEvents: eventsResult.rows,
      recentUsers: usersResult.rows,
      recentAudit: auditResult.rows,
    });
  }),
);

router.get(
  "/users",
  webAsync(async (req, res) => {
    const q = text(req.query.q, 120);
    const role = ROLES.includes(text(req.query.role, 30) as (typeof ROLES)[number])
      ? text(req.query.role, 30)
      : "";

    const result = await pool.query(
      `SELECT u.id, u.full_name, u.email, u.phone, u.role, u.created_at,
              (SELECT COUNT(*) FROM events e WHERE e.organizer_id = u.id)::int AS events_count,
              (SELECT COUNT(*) FROM bookings b WHERE b.user_id = u.id)::int AS bookings_count
         FROM users u
        WHERE ($1 = '' OR u.email ILIKE '%' || $1 || '%'
               OR u.full_name ILIKE '%' || $1 || '%'
               OR COALESCE(u.phone, '') ILIKE '%' || $1 || '%')
          AND ($2 = '' OR u.role::text = $2)
        ORDER BY u.created_at DESC
        LIMIT 100`,
      [q, role],
    );

    res.render("admin/users", {
      title: "Users",
      subtitle: "Manage platform access and review account activity.",
      active: "users",
      users: result.rows,
      q,
      roleFilter: role,
      admin: res.locals.admin,
    });
  }),
);

router.post(
  "/users/:id/role",
  requireCsrf,
  webAsync(async (req, res) => {
    const id = text(req.params.id, 50);
    const role = text(req.body?.role, 30);
    if (!isUuid(id) || !ROLES.includes(role as (typeof ROLES)[number])) {
      res.redirect("/admin/users?error=invalid-role");
      return;
    }

    const actor = adminActor(res);
    if (id === actor.id && role !== "super_admin") {
      res.redirect("/admin/users?error=self-demote");
      return;
    }

    type RoleUpdateResult =
      | { status: "missing" }
      | { status: "last-super-admin" }
      | { status: "updated"; target: { id: string; email: string; role: string } };

    const result: RoleUpdateResult = await withTransaction(async (client) => {
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext('eventflow_super_admin_roles'))",
      );
      const targetResult = await client.query<{
        id: string;
        email: string;
        role: string;
      }>("SELECT id, email, role FROM users WHERE id = $1 FOR UPDATE", [id]);
      const target = targetResult.rows[0];
      if (!target) return { status: "missing" };

      if (target.role === "super_admin" && role !== "super_admin") {
        const countResult = await client.query<{ count: number }>(
          "SELECT COUNT(*)::int AS count FROM users WHERE role = 'super_admin'",
        );
        if (Number(countResult.rows[0].count) <= 1) {
          return { status: "last-super-admin" };
        }
      }

      await client.query("UPDATE users SET role = $1 WHERE id = $2", [role, id]);
      return { status: "updated", target };
    });

    if (result.status === "missing") {
      res.redirect("/admin/users?error=user-not-found");
      return;
    }
    if (result.status === "last-super-admin") {
      res.redirect("/admin/users?error=last-super-admin");
      return;
    }

    await writeAuditLog({
      actorId: actor.id,
      actorEmail: actor.email,
      actorRole: actor.role,
      action: "user.role_changed",
      targetType: "user",
      targetId: result.target.id,
      details: { email: result.target.email, from: result.target.role, to: role },
      ip: req.ip,
    });
    res.redirect("/admin/users?notice=role-updated");
  }),
);

router.get(
  "/events",
  webAsync(async (req, res) => {
    const q = text(req.query.q, 120);
    const status = EVENT_STATUSES.includes(
      text(req.query.status, 30) as (typeof EVENT_STATUSES)[number],
    )
      ? text(req.query.status, 30)
      : "";

    const result = await pool.query(
      `SELECT e.id, e.title, e.status, e.starts_at, e.ends_at, e.venue,
              e.created_at, u.full_name AS organizer_name, u.email AS organizer_email,
              tt.capacity, tt.sold_count,
              (SELECT COUNT(*) FROM bookings b
                WHERE b.event_id = e.id AND b.status IN ('pending', 'confirmed'))::int AS bookings_count,
              (SELECT COALESCE(SUM(p.amount_minor), 0)
                 FROM payments p
                 JOIN bookings b ON b.id = p.booking_id
                WHERE b.event_id = e.id AND p.status = 'succeeded')::bigint AS revenue_minor
         FROM events e
         JOIN users u ON u.id = e.organizer_id
         LEFT JOIN (
           SELECT event_id, SUM(capacity)::int AS capacity, SUM(sold_count)::int AS sold_count
             FROM ticket_types
            GROUP BY event_id
         ) tt ON tt.event_id = e.id
        WHERE ($1 = '' OR e.title ILIKE '%' || $1 || '%'
               OR e.venue ILIKE '%' || $1 || '%'
               OR e.id::text ILIKE '%' || $1 || '%'
               OR u.full_name ILIKE '%' || $1 || '%'
               OR u.email ILIKE '%' || $1 || '%')
          AND ($2 = '' OR e.status::text = $2)
        ORDER BY e.starts_at DESC NULLS LAST, e.created_at DESC
        LIMIT 100`,
      [q, status],
    );

    res.render("admin/events", {
      title: "Events",
      subtitle: "Review listings across the platform and intervene when needed.",
      active: "events",
      events: result.rows,
      q,
      statusFilter: status,
    });
  }),
);

router.get(
  "/events/:id/cancel",
  webAsync(async (req, res) => {
    const id = text(req.params.id, 50);
    if (!isUuid(id)) {
      renderErrorPage(res, 404, "That event could not be found.");
      return;
    }
    const result = await pool.query(
      `SELECT e.id, e.title, e.status, e.starts_at, e.venue,
              u.full_name AS organizer_name, u.email AS organizer_email,
              (SELECT COUNT(*) FROM bookings b
                WHERE b.event_id = e.id AND b.status IN ('pending', 'confirmed'))::int AS active_bookings
         FROM events e
         JOIN users u ON u.id = e.organizer_id
        WHERE e.id = $1`,
      [id],
    );
    const event = result.rows[0];
    if (!event) {
      renderErrorPage(res, 404, "That event could not be found.");
      return;
    }
    if (event.status === "cancelled") {
      res.redirect("/admin/events?error=event-already-cancelled");
      return;
    }

    res.render("admin/event-cancel", {
      title: "Cancel event",
      subtitle: "This action immediately invalidates active tickets.",
      active: "events",
      event,
    });
  }),
);

router.post(
  "/events/:id/cancel",
  requireCsrf,
  webAsync(async (req, res) => {
    const id = text(req.params.id, 50);
    if (!isUuid(id)) {
      res.redirect("/admin/events?error=event-not-found");
      return;
    }
    const eventResult = await pool.query<{ title: string; organizer_email: string }>(
      `SELECT e.title, u.email AS organizer_email
         FROM events e
         JOIN users u ON u.id = e.organizer_id
        WHERE e.id = $1`,
      [id],
    );
    const event = eventResult.rows[0];
    if (!event) {
      res.redirect("/admin/events?error=event-not-found");
      return;
    }

    const reason = text(req.body?.reason, 500);
    const cancelled = await cancelEventAndRelease(id);
    const actor = adminActor(res);
    await writeAuditLog({
      actorId: actor.id,
      actorEmail: actor.email,
      actorRole: actor.role,
      action: cancelled ? "event.cancelled" : "event.cancel_skipped",
      targetType: "event",
      targetId: id,
      details: { title: event.title, organizer_email: event.organizer_email, reason },
      ip: req.ip,
    });

    res.redirect(
      `/admin/events?notice=${cancelled ? "event-cancelled" : "event-already-cancelled"}`,
    );
  }),
);

router.get(
  "/bookings",
  webAsync(async (req, res) => {
    const q = text(req.query.q, 120);
    const status = BOOKING_STATUSES.includes(
      text(req.query.status, 30) as (typeof BOOKING_STATUSES)[number],
    )
      ? text(req.query.status, 30)
      : "";

    const result = await pool.query(
      `SELECT b.id, UPPER(LEFT(b.id::text, 8)) AS reference, b.status, b.total_minor, b.currency, b.created_at,
              u.full_name, u.email, e.title AS event_title, e.starts_at,
              (SELECT COALESCE(SUM(bi.quantity), 0)
                 FROM booking_items bi WHERE bi.booking_id = b.id)::int AS ticket_count
         FROM bookings b
         JOIN users u ON u.id = b.user_id
         JOIN events e ON e.id = b.event_id
        WHERE ($1 = '' OR b.id::text ILIKE '%' || $1 || '%'
               OR u.email ILIKE '%' || $1 || '%'
               OR u.full_name ILIKE '%' || $1 || '%'
               OR e.title ILIKE '%' || $1 || '%')
          AND ($2 = '' OR b.status::text = $2)
        ORDER BY b.created_at DESC
        LIMIT 100`,
      [q, status],
    );

    res.render("admin/bookings", {
      title: "Bookings",
      subtitle: "Track orders and the money moving through the platform.",
      active: "bookings",
      bookings: result.rows,
      q,
      statusFilter: status,
    });
  }),
);

router.get(
  "/audit",
  webAsync(async (req, res) => {
    const q = text(req.query.q, 120);
    const requestedPage = Math.max(1, Number.parseInt(text(req.query.page, 10), 10) || 1);
    const limit = 40;

    const countResult = await pool.query<{ count: number }>(
      `SELECT COUNT(*)::int AS count
         FROM audit_logs
        WHERE ($1 = '' OR actor_email ILIKE '%' || $1 || '%'
               OR action ILIKE '%' || $1 || '%'
               OR COALESCE(target_type, '') ILIKE '%' || $1 || '%'
               OR COALESCE(target_id, '') ILIKE '%' || $1 || '%')`,
      [q],
    );
    const total = Number(countResult.rows[0].count);
    const pages = Math.max(1, Math.ceil(total / limit));
    const page = Math.min(requestedPage, pages);
    const offset = (page - 1) * limit;

    const result = await pool.query(
      `SELECT id, actor_email, actor_role, action, target_type, target_id,
              details, ip, created_at
         FROM audit_logs
        WHERE ($1 = '' OR actor_email ILIKE '%' || $1 || '%'
               OR action ILIKE '%' || $1 || '%'
               OR COALESCE(target_type, '') ILIKE '%' || $1 || '%'
               OR COALESCE(target_id, '') ILIKE '%' || $1 || '%')
        ORDER BY created_at DESC
        LIMIT $2 OFFSET $3`,
      [q, limit, offset],
    );

    res.render("admin/audit", {
      title: "Audit log",
      subtitle: "A permanent trail of privileged actions on the platform.",
      active: "audit",
      logs: result.rows,
      q,
      page,
      pages,
      total,
    });
  }),
);

router.use((_req, res) => {
  renderErrorPage(res, 404, "That dashboard page does not exist.");
});

export default router;
