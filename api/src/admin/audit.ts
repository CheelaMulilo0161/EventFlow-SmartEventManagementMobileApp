import { pool } from "../db";

export interface AuditInput {
  actorId: string | null;
  actorEmail: string;
  actorRole: string;
  action: string;
  targetType?: string;
  targetId?: string;
  details?: Record<string, unknown>;
  ip?: string;
}

export async function writeAuditLog(input: AuditInput): Promise<void> {
  await pool.query(
    `INSERT INTO audit_logs
       (actor_id, actor_email, actor_role, action, target_type, target_id, details, ip)
     VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8)`,
    [
      input.actorId,
      input.actorEmail,
      input.actorRole,
      input.action,
      input.targetType ?? null,
      input.targetId ?? null,
      JSON.stringify(input.details ?? {}),
      input.ip ?? null,
    ],
  );
}
