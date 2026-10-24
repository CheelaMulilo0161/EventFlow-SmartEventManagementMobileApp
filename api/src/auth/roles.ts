import { UserRole } from "../types/express";

export const PLATFORM_ADMIN_ROLES: UserRole[] = ["admin", "super_admin"];

export function isPlatformAdmin(role: string | undefined): boolean {
  return role === "admin" || role === "super_admin";
}
