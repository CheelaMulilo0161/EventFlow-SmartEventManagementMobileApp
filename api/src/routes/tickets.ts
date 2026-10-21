import { Router } from "express";
import { z } from "zod";
import { requireAuth, requireRole } from "../auth/jwt";
import { asyncHandler } from "../http/asyncHandler";
import { param } from "../http/params";
import { scanShortCode, scanTicket } from "../services/tickets";

const router = Router();

const scanInput = z.object({
  token: z.string().trim().min(10),
  event_id: z.string().uuid().optional(),
});

const codeScanInput = z.object({
  short_code: z.string().trim().min(6).max(12),
  event_id: z.string().uuid().optional(),
});

const offlineInput = z.object({
  scans: z
    .array(
      z.object({
        token: z.string().trim().min(10),
        scanned_at: z.string().trim().optional(),
      }),
    )
    .min(1)
    .max(500),
});

router.post(
  "/tickets/scan",
  requireAuth,
  requireRole("organizer", "admin"),
  asyncHandler(async (req, res) => {
    const body = scanInput.parse(req.body);
    const result = await scanTicket(
      body.token,
      req.user!.id,
      req.user!.role,
      body.event_id,
    );
    res.json({ data: { result } });
  }),
);

router.post(
  "/tickets/scan-code",
  requireAuth,
  requireRole("organizer", "admin"),
  asyncHandler(async (req, res) => {
    const body = codeScanInput.parse(req.body);
    const result = await scanShortCode(
      body.short_code,
      req.user!.id,
      req.user!.role,
      body.event_id,
    );
    res.json({ data: { result } });
  }),
);

router.post(
  "/events/:eventId/checkins",
  requireAuth,
  requireRole("organizer", "admin"),
  asyncHandler(async (req, res) => {
    const body = offlineInput.parse(req.body);
    const results = [];
    for (const scan of body.scans) {
      const result = await scanTicket(
        scan.token,
        req.user!.id,
        req.user!.role,
        param(req, "eventId"),
      );
      results.push({ token: scan.token, scanned_at: scan.scanned_at ?? null, result });
    }
    res.json({ data: { results } });
  }),
);

export default router;
