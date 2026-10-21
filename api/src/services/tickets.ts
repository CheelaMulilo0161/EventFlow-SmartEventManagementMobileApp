import { withTransaction } from "../db";
import { AppError } from "../http/errors";
import { sha256, verifyTicketToken } from "../utils/crypto";

type ScanResult =
  | {
      status: "valid";
      message: string;
      ticket: {
        id: string;
        short_code: string;
        attendee_name: string | null;
        ticket_type_name: string;
        event_id: string;
        event_title: string;
      };
    }
  | {
      status: "already_used";
      message: string;
      ticket: {
        id: string;
        short_code: string;
        attendee_name: string | null;
        ticket_type_name: string;
        used_at: Date | null;
        event_id: string;
        event_title: string;
      };
    }
  | {
      status: "invalid";
      message: string;
    };

type ScanRow = {
  id: string;
  short_code: string;
  attendee_name: string | null;
  status: "valid" | "used" | "cancelled";
  used_at: Date | null;
  ticket_type_name: string;
  booking_status: string;
  event_id: string;
  event_title: string;
  organizer_id: string;
};

async function performScan(
  mode: "token" | "code",
  value: string,
  organizerId: string,
  organizerRole: string,
  eventId?: string,
): Promise<ScanResult> {
  if (!value.trim()) return { status: "invalid", message: "No ticket code supplied" };

  if (mode === "token" && !verifyTicketToken(value)) {
    return { status: "invalid", message: "This is not a valid EventFlow ticket" };
  }

  return withTransaction(async (client) => {
    const where = mode === "token" ? "t.token_hash = $1" : "upper(t.short_code) = upper($1)";
    const lookupValue = mode === "token" ? sha256(value) : value.trim();

    const result = await client.query<ScanRow>(
      `SELECT t.id, t.short_code, t.attendee_name, t.status, t.used_at,
              tt.name AS ticket_type_name, b.status AS booking_status,
              e.id AS event_id, e.title AS event_title, e.organizer_id
       FROM tickets t
       JOIN bookings b ON b.id = t.booking_id
       JOIN ticket_types tt ON tt.id = t.ticket_type_id
       JOIN events e ON e.id = b.event_id
       WHERE ${where}
       FOR UPDATE OF t`,
      [lookupValue],
    );

    const ticket = result.rows[0];
    if (!ticket) return { status: "invalid", message: "Ticket not found" };

    if (organizerRole !== "admin" && ticket.organizer_id !== organizerId) {
      throw new AppError(403, "FORBIDDEN", "This ticket belongs to another organizer's event");
    }
    if (eventId && ticket.event_id !== eventId) {
      return { status: "invalid", message: "This ticket is for a different event" };
    }
    if (ticket.booking_status !== "confirmed") {
      return { status: "invalid", message: "This booking has not been paid or was cancelled" };
    }
    if (ticket.status === "cancelled") {
      return { status: "invalid", message: "This ticket was cancelled" };
    }
    if (ticket.status === "used") {
      return {
        status: "already_used",
        message: "This ticket was already checked in",
        ticket: {
          id: ticket.id,
          short_code: ticket.short_code,
          attendee_name: ticket.attendee_name,
          ticket_type_name: ticket.ticket_type_name,
          used_at: ticket.used_at,
          event_id: ticket.event_id,
          event_title: ticket.event_title,
        },
      };
    }

    await client.query(
      `UPDATE tickets
       SET status = 'used', used_at = now(), checked_in_by = $1
       WHERE id = $2`,
      [organizerId, ticket.id],
    );

    return {
      status: "valid",
      message: "Valid ticket - welcome in",
      ticket: {
        id: ticket.id,
        short_code: ticket.short_code,
        attendee_name: ticket.attendee_name,
        ticket_type_name: ticket.ticket_type_name,
        event_id: ticket.event_id,
        event_title: ticket.event_title,
      },
    };
  });
}

export async function scanTicket(
  token: string,
  organizerId: string,
  organizerRole: string,
  eventId?: string,
) {
  return performScan("token", token, organizerId, organizerRole, eventId);
}

export async function scanShortCode(
  shortCode: string,
  organizerId: string,
  organizerRole: string,
  eventId?: string,
) {
  return performScan("code", shortCode, organizerId, organizerRole, eventId);
}
