import { Router } from "express";
import { z } from "zod";
import { requireAuth } from "../auth/jwt";
import { asyncHandler } from "../http/asyncHandler";
import { AppError } from "../http/errors";
import { param } from "../http/params";
import {
  cancelBooking,
  createBooking,
  getBookingForUser,
  initiatePayment,
  listBookingsForUser,
} from "../services/bookings";

const router = Router();

const bookingInput = z.object({
  items: z
    .array(
      z.object({
        ticket_type_id: z.string().uuid(),
        quantity: z.number().int().min(1).max(20),
      }),
    )
    .min(1),
  attendee_name: z.string().trim().min(2).max(120).optional(),
});

const payInput = z.object({
  phone: z.string().trim().min(9).max(20).optional(),
  network: z.enum(["MTN", "AIRTEL", "ZAMTEL"]).optional(),
});

router.get(
  "/bookings",
  requireAuth,
  asyncHandler(async (req, res) => {
    const bookings = await listBookingsForUser(req.user!.id);
    res.json({ data: { bookings } });
  }),
);

router.get(
  "/bookings/:id",
  requireAuth,
  asyncHandler(async (req, res) => {
    const booking = await getBookingForUser(param(req, "id"), req.user!.id, req.user!.role);
    res.json({ data: { booking } });
  }),
);

router.post(
  "/events/:eventId/bookings",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = bookingInput.parse(req.body);
    const idempotencyKey =
      req.header("Idempotency-Key")?.trim() || (req.body.idempotency_key as string | undefined);
    if (!idempotencyKey || idempotencyKey.length < 8 || idempotencyKey.length > 120) {
      throw new AppError(
        400,
        "IDEMPOTENCY_KEY_REQUIRED",
        "Send an Idempotency-Key header with at least 8 characters",
      );
    }

    const booking = await createBooking({
      userId: req.user!.id,
      eventId: param(req, "eventId"),
      idempotencyKey,
      items: body.items,
      attendeeName: body.attendee_name,
    });
    res.status(201).json({ data: { booking } });
  }),
);

router.post(
  "/bookings/:id/cancel",
  requireAuth,
  asyncHandler(async (req, res) => {
    const booking = await cancelBooking(param(req, "id"), req.user!.id, req.user!.role);
    res.json({ data: { booking } });
  }),
);

router.post(
  "/bookings/:id/pay",
  requireAuth,
  asyncHandler(async (req, res) => {
    const body = payInput.parse(req.body ?? {});
    const payment = await initiatePayment({
      bookingId: param(req, "id"),
      userId: req.user!.id,
      role: req.user!.role,
      phone: body.phone,
      network: body.network,
    });
    res.status(201).json({
      data: {
        payment,
        instructions:
          "Simulated mobile money payment created. Approve it in the app to confirm the booking.",
      },
    });
  }),
);

export default router;
