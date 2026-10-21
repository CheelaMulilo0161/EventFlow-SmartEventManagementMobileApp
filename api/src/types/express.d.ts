import "express";

export type UserRole = "attendee" | "organizer" | "admin";

declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        role: UserRole;
        email: string;
      };
    }
  }
}
