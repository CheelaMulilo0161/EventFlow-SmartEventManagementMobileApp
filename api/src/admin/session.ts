import crypto from "crypto";
import { NextFunction, Request, Response } from "express";
import { pool } from "../db";
import { config } from "../config";

const COOKIE_NAME = "eventflow_admin";
const COOKIE_PATH = "/admin";

export interface AdminSession {
  userId: string;
  csrf: string;
  exp: number;
}

export interface AdminUser {
  id: string;
  email: string;
  full_name: string;
  role: string;
}

function base64url(input: Buffer | string): string {
  return Buffer.from(input).toString("base64url");
}

function sign(value: string): string {
  return crypto.createHmac("sha256", config.adminSessionSecret).update(value).digest("base64url");
}

function secureEqual(left: string, right: string): boolean {
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function parseCookies(header: string | undefined): Record<string, string> {
  const cookies: Record<string, string> = {};
  if (!header) return cookies;
  for (const part of header.split(";")) {
    const separator = part.indexOf("=");
    if (separator < 0) continue;
    const key = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (key) cookies[key] = decodeURIComponent(value);
  }
  return cookies;
}

export function readAdminSession(req: Request): AdminSession | null {
  const token = parseCookies(req.headers.cookie)[COOKIE_NAME];
  if (!token) return null;

  const separator = token.lastIndexOf(".");
  if (separator < 1) return null;
  const payload = token.slice(0, separator);
  const signature = token.slice(separator + 1);
  if (!secureEqual(sign(payload), signature)) return null;

  try {
    const parsed = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as AdminSession;
    if (
      typeof parsed.userId !== "string" ||
      typeof parsed.csrf !== "string" ||
      typeof parsed.exp !== "number" ||
      parsed.exp <= Date.now()
    ) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export function setAdminSessionCookie(req: Request, res: Response, userId: string): AdminSession {
  const session: AdminSession = {
    userId,
    csrf: crypto.randomBytes(24).toString("hex"),
    exp: Date.now() + config.adminSessionHours * 60 * 60 * 1000,
  };
  const payload = base64url(JSON.stringify(session));
  const token = `${payload}.${sign(payload)}`;
  res.cookie(COOKIE_NAME, token, {
    httpOnly: true,
    sameSite: "lax",
    secure: req.secure || config.nodeEnv === "production",
    path: COOKIE_PATH,
    maxAge: config.adminSessionHours * 60 * 60 * 1000,
  });
  return session;
}

export function clearAdminSessionCookie(res: Response): void {
  res.clearCookie(COOKIE_NAME, { path: COOKIE_PATH, sameSite: "lax" });
}

export async function requireSuperAdmin(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  const session = readAdminSession(req);
  if (!session) {
    res.redirect("/admin/login");
    return;
  }

  try {
    const result = await pool.query<AdminUser>(
      "SELECT id, email, full_name, role FROM users WHERE id = $1",
      [session.userId],
    );
    const admin = result.rows[0];
    if (!admin || admin.role !== "super_admin") {
      clearAdminSessionCookie(res);
      res.redirect("/admin/login");
      return;
    }

    res.locals.admin = admin;
    res.locals.csrf = session.csrf;
    res.locals.currentPath = req.path;
    next();
  } catch (error) {
    next(error);
  }
}

export function requireCsrf(req: Request, res: Response, next: NextFunction): void {
  const expected = typeof res.locals.csrf === "string" ? res.locals.csrf : "";
  const actual = typeof req.body?._csrf === "string" ? req.body._csrf : "";
  const origin = req.get("origin");

  let sameOrigin = true;
  if (origin) {
    try {
      sameOrigin = new URL(origin).host === req.get("host");
    } catch {
      sameOrigin = false;
    }
  }

  if (
    !expected ||
    !secureEqual(expected, actual) ||
    !sameOrigin
  ) {
    res.status(403).render("admin/error", {
      title: "Request rejected",
      message: "Your form session expired or the request came from an unexpected origin. Go back, reload the page and try again.",
      admin: res.locals.admin ?? null,
      csrf: res.locals.csrf ?? "",
      active: "",
    });
    return;
  }

  next();
}
