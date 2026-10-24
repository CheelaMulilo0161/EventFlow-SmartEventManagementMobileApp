import { withTransaction } from "../db";
import { AppError } from "../http/errors";

export async function cancelEventAndRelease(eventId: string): Promise<boolean> {
  return withTransaction(async (client) => {
    const updated = await client.query<{ id: string }>(
      `UPDATE events SET status = 'cancelled', updated_at = now()
       WHERE id = $1 AND status <> 'cancelled' RETURNING id`,
      [eventId],
    );

    if (!updated.rows[0]) {
      const existing = await client.query<{ status: string }>(
        "SELECT status FROM events WHERE id = $1",
        [eventId],
      );
      if (!existing.rows[0]) {
        throw new AppError(404, "EVENT_NOT_FOUND", "Event not found");
      }
      return false;
    }

    const items = await client.query<{ ticket_type_id: string; quantity: number }>(
      `SELECT bi.ticket_type_id, SUM(bi.quantity)::int AS quantity
       FROM booking_items bi
       JOIN bookings b ON b.id = bi.booking_id
       WHERE b.event_id = $1 AND b.status IN ('pending', 'confirmed')
       GROUP BY bi.ticket_type_id`,
      [eventId],
    );
    for (const item of items.rows) {
      await client.query(
        `UPDATE ticket_types
         SET sold_count = GREATEST(0, sold_count - $1)
         WHERE id = $2`,
        [item.quantity, item.ticket_type_id],
      );
    }
    await client.query(
      `UPDATE tickets SET status = 'cancelled'
       WHERE booking_id IN (SELECT id FROM bookings WHERE event_id = $1)`,
      [eventId],
    );
    await client.query(
      `UPDATE bookings SET status = 'cancelled', updated_at = now()
       WHERE event_id = $1 AND status IN ('pending', 'confirmed')`,
      [eventId],
    );
    await client.query(
      `UPDATE payments SET status = 'failed', updated_at = now()
       WHERE booking_id IN (SELECT id FROM bookings WHERE event_id = $1)
         AND status = 'pending'`,
      [eventId],
    );

    return true;
  });
}
