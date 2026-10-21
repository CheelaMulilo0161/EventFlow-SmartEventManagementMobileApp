import { NextFunction, Request, Response } from "express";
import { ZodError } from "zod";

export class AppError extends Error {
  constructor(
    public statusCode: number,
    public code: string,
    message: string,
    public details?: unknown,
  ) {
    super(message);
    this.name = "AppError";
  }
}

export function notFound(_req: Request, _res: Response, next: NextFunction) {
  next(new AppError(404, "NOT_FOUND", "Route not found"));
}

export function errorHandler(
  error: unknown,
  _req: Request,
  res: Response,
  _next: NextFunction,
) {
  if (error instanceof AppError) {
    res.status(error.statusCode).json({
      error: { code: error.code, message: error.message, details: error.details },
    });
    return;
  }

  if (error instanceof ZodError) {
    res.status(400).json({
      error: {
        code: "VALIDATION_ERROR",
        message: "The request body is invalid",
        details: error.issues,
      },
    });
    return;
  }

  const pgError = error as { code?: string; constraint?: string; detail?: string };
  if (pgError?.code === "23505") {
    res.status(409).json({
      error: {
        code: "CONFLICT",
        message: "That record already exists",
        details: pgError.constraint ?? pgError.detail,
      },
    });
    return;
  }
  if (pgError?.code === "23514") {
    res.status(409).json({
      error: {
        code: "CONSTRAINT_VIOLATION",
        message: "That change would break a business rule",
        details: pgError.constraint ?? pgError.detail,
      },
    });
    return;
  }

  console.error(error);
  res.status(500).json({
    error: { code: "INTERNAL_ERROR", message: "Something went wrong on the server" },
  });
}
