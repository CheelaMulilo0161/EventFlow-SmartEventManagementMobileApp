import express from "express";
import cors from "cors";
import authRoutes from "./routes/auth";
import eventRoutes from "./routes/events";
import bookingRoutes from "./routes/bookings";
import paymentRoutes from "./routes/payments";
import ticketRoutes from "./routes/tickets";
import organizerRoutes from "./routes/organizer";
import adminRoutes from "./routes/admin";
import { pool } from "./db";
import { errorHandler, notFound } from "./http/errors";

export const app = express();

app.use(cors());
app.use(express.json({ limit: "256kb" }));

app.get("/health", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", db: "up" });
  } catch {
    res.status(500).json({ status: "error", db: "down" });
  }
});

app.use("/api/auth", authRoutes);
app.use("/api/events", eventRoutes);
app.use("/api", bookingRoutes);
app.use("/api", paymentRoutes);
app.use("/api", ticketRoutes);
app.use("/api/organizer", organizerRoutes);
app.use("/api/admin", adminRoutes);

app.use(notFound);
app.use(errorHandler);
