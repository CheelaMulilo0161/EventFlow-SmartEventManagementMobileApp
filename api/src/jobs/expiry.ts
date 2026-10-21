import { releaseExpiredBookings } from "../services/bookings";

let timer: NodeJS.Timeout | null = null;

export function startExpiryJob(intervalMs = 60_000) {
  if (timer) return;
  timer = setInterval(async () => {
    try {
      const released = await releaseExpiredBookings();
      if (released > 0) {
        console.log(`Released ${released} expired booking hold(s)`);
      }
    } catch (error) {
      console.error("Failed to release expired bookings", error);
    }
  }, intervalMs);
  timer.unref();
}

export function stopExpiryJob() {
  if (timer) {
    clearInterval(timer);
    timer = null;
  }
}
