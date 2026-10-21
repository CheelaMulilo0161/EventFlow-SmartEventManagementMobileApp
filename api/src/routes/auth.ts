import { Router } from "express";
import bcrypt from "bcryptjs";
import { z } from "zod";
import { pool } from "../db";
import { config } from "../config";
import { signToken, requireAuth } from "../auth/jwt";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";

const router = Router();

const registerSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(8, "Use at least 8 characters"),
  full_name: z.string().trim().min(2).max(120),
  phone: z.string().trim().min(9).max(20),
  role: z.enum(["attendee", "organizer"]).default("attendee"),
});

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1),
});

type UserRow = {
  id: string;
  email: string;
  phone: string;
  full_name: string;
  password_hash: string;
  role: "attendee" | "organizer" | "admin";
  created_at: Date;
};

function publicUser(user: UserRow) {
  return {
    id: user.id,
    email: user.email,
    phone: user.phone,
    full_name: user.full_name,
    role: user.role,
    created_at: user.created_at,
  };
}

router.post(
  "/register",
  asyncHandler(async (req, res) => {
    const body = registerSchema.parse(req.body);
    const passwordHash = await bcrypt.hash(body.password, config.bcryptRounds);

    const result = await pool.query<UserRow>(
      `INSERT INTO users (email, phone, full_name, password_hash, role)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, email, phone, full_name, password_hash, role, created_at`,
      [body.email, body.phone, body.full_name, passwordHash, body.role],
    );

    const user = result.rows[0];
    const token = signToken({ sub: user.id, role: user.role, email: user.email });
    res.status(201).json({ data: { token, user: publicUser(user) } });
  }),
);

router.post(
  "/login",
  asyncHandler(async (req, res) => {
    const body = loginSchema.parse(req.body);
    const result = await pool.query<UserRow>(
      `SELECT id, email, phone, full_name, password_hash, role, created_at
       FROM users WHERE email = $1`,
      [body.email],
    );

    const user = result.rows[0];
    if (!user || !(await bcrypt.compare(body.password, user.password_hash))) {
      throw new AppError(401, "INVALID_CREDENTIALS", "Email or password is incorrect");
    }

    const token = signToken({ sub: user.id, role: user.role, email: user.email });
    res.json({ data: { token, user: publicUser(user) } });
  }),
);

router.get(
  "/me",
  requireAuth,
  asyncHandler(async (req, res) => {
    const result = await pool.query<UserRow>(
      `SELECT id, email, phone, full_name, password_hash, role, created_at
       FROM users WHERE id = $1`,
      [req.user!.id],
    );
    const user = result.rows[0];
    if (!user) throw new AppError(401, "USER_NOT_FOUND", "This account no longer exists");
    res.json({ data: { user: publicUser(user) } });
  }),
);

export default router;
