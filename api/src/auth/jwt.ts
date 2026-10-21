import { NextFunction, Request, Response } from "express";
import jwt from "jsonwebtoken";
import { config } from "../config";
import { AppError } from "../http/errors";
import { UserRole } from "../types/express";

type TokenPayload = {
  sub: string;
  role: UserRole;
  email: string;
};

export function signToken(payload: TokenPayload): string {
  return jwt.sign(payload, config.jwtSecret, { expiresIn: "7d" });
}

export function verifyToken(token: string): TokenPayload {
  const decoded = jwt.verify(token, config.jwtSecret);
  if (typeof decoded === "string") {
    throw new AppError(401, "INVALID_TOKEN", "Invalid session token");
  }
  const payload = decoded as jwt.JwtPayload & Partial<TokenPayload>;
  if (!payload.sub || !payload.role || !payload.email) {
    throw new AppError(401, "INVALID_TOKEN", "Invalid session token");
  }
  return { sub: payload.sub, role: payload.role, email: payload.email };
}

export function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header?.startsWith("Bearer ")) {
    next(new AppError(401, "AUTH_REQUIRED", "Please log in to continue"));
    return;
  }

  try {
    const payload = verifyToken(header.slice("Bearer ".length));
    req.user = { id: payload.sub, role: payload.role, email: payload.email };
    next();
  } catch (error) {
    if (error instanceof AppError) {
      next(error);
      return;
    }
    next(new AppError(401, "INVALID_TOKEN", "Your session has expired. Log in again."));
  }
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) {
      next(new AppError(401, "AUTH_REQUIRED", "Please log in to continue"));
      return;
    }
    if (!roles.includes(req.user.role)) {
      next(new AppError(403, "FORBIDDEN", "You do not have permission to do that"));
      return;
    }
    next();
  };
}
