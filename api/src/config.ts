import "dotenv/config";

function env(name: string, fallback?: string): string {
  const value = process.env[name] ?? fallback;
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: env("DATABASE_URL", "postgres://postgres@localhost:5433/eventflow"),
  jwtSecret: env("JWT_SECRET", "dev-only-jwt-secret-change-me"),
  ticketSecret: env("TICKET_SECRET", "dev-only-ticket-secret-change-me"),
  bookingHoldMinutes: Number(process.env.BOOKING_HOLD_MINUTES ?? 15),
  bcryptRounds: Number(process.env.BCRYPT_ROUNDS ?? 12),
  nodeEnv: process.env.NODE_ENV ?? "development",
};

export const CURRENCY = "ZMW";
