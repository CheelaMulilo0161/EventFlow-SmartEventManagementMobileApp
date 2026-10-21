import { Router } from "express";
import { z } from "zod";
import { pool } from "../db";
import { config } from "../config";
import { requireAuth } from "../auth/jwt";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";
import { param } from "../http/params";
import {
  completePayment,
  markWebhookProcessed,
  recordWebhookEvent,
} from "../services/bookings";

const router = Router();

const webhookInput = z.object({
  event_id: z.string().min(1),
  reference: z.string().min(1),
  status: z.enum(["succeeded", "failed"]),
});

router.post(
  "/payments/:reference/simulate",
  requireAuth,
  asyncHandler(async (req, res) => {
    if (config.nodeEnv === "production") {
      throw new AppError(403, "SIMULATION_DISABLED", "Simulated payments are disabled in production");
    }

    const payment = await pool.query<{ user_id: string }>(
      `SELECT b.user_id
       FROM payments p JOIN bookings b ON b.id = p.booking_id
       WHERE p.provider = 'simulated' AND p.provider_reference = $1`,
      [param(req, "reference")],
    );
    if (!payment.rows[0]) throw new AppError(404, "PAYMENT_NOT_FOUND", "Payment not found");
    if (payment.rows[0].user_id !== req.user!.id && req.user!.role !== "admin") {
      throw new AppError(403, "FORBIDDEN", "This payment belongs to another user");
    }

    const booking = await completePayment(param(req, "reference"), "simulated");
    res.json({ data: { booking } });
  }),
);

router.post(
  "/payments/webhook/:provider",
  asyncHandler(async (req, res) => {
    const provider = req.params.provider;
    if (provider !== "simulated") {
      throw new AppError(
        501,
        "PROVIDER_NOT_CONFIGURED",
        "This payment provider is not configured yet",
      );
    }

    const body = webhookInput.parse(req.body);
    const isNew = await recordWebhookEvent(provider, body.event_id, req.body);
    if (!isNew) {
      res.json({ data: { received: true, duplicate: true } });
      return;
    }

    if (body.status === "succeeded") {
      await completePayment(body.reference, provider);
    } else {
      await pool.query(
        `UPDATE payments SET status = 'failed', updated_at = now()
         WHERE provider = $1 AND provider_reference = $2 AND status = 'pending'`,
        [provider, body.reference],
      );
    }

    await markWebhookProcessed(provider, body.event_id);
    res.json({ data: { received: true, duplicate: false } });
  }),
);

export default router;
