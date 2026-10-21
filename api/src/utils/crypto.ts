import crypto from "crypto";
import { config } from "../config";

const SHORT_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function createTicketToken(ticketId: string): string {
  const payload = Buffer.from(ticketId, "utf8").toString("base64url");
  const signature = crypto
    .createHmac("sha256", config.ticketSecret)
    .update(payload)
    .digest("base64url");
  return `${payload}.${signature}`;
}

export function verifyTicketToken(token: string): string | null {
  const [payload, signature] = token.split(".");
  if (!payload || !signature) return null;

  const expected = crypto
    .createHmac("sha256", config.ticketSecret)
    .update(payload)
    .digest("base64url");

  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  try {
    return Buffer.from(payload, "base64url").toString("utf8");
  } catch {
    return null;
  }
}

export function createShortCode(): string {
  let code = "";
  for (let i = 0; i < 8; i += 1) {
    code += SHORT_CODE_ALPHABET[crypto.randomInt(SHORT_CODE_ALPHABET.length)];
  }
  return code;
}
