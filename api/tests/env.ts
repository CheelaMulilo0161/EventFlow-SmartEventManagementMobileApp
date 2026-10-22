process.env.NODE_ENV = "test";
process.env.DATABASE_URL =
  process.env.TEST_DATABASE_URL ??
  "postgres://postgres@localhost:5433/eventflow_test";
process.env.JWT_SECRET = "test-jwt-secret-not-for-production";
process.env.TICKET_SECRET = "test-ticket-secret-not-for-production";
process.env.BCRYPT_ROUNDS = "4";
process.env.BOOKING_HOLD_MINUTES = "15";
