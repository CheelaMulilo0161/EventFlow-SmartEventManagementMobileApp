import "dotenv/config";
import { app } from "./app";
import { config } from "./config";
import { pool } from "./db";
import { runMigrations } from "./db/migrate";
import { startExpiryJob, stopExpiryJob } from "./jobs/expiry";

async function main() {
  const applied = await runMigrations(pool);
  if (applied.length > 0) {
    console.log(`Applied database migrations: ${applied.join(", ")}`);
  }

  const server = app.listen(config.port, "0.0.0.0", () => {
    console.log(`EventFlow API listening on http://0.0.0.0:${config.port}`);
    console.log(`Health check: http://localhost:${config.port}/health`);
  });

  startExpiryJob();

  const shutdown = async (signal: string) => {
    console.log(`${signal} received, shutting down`);
    stopExpiryJob();
    server.close(async () => {
      await pool.end();
      process.exit(0);
    });
  };

  process.on("SIGINT", () => void shutdown("SIGINT"));
  process.on("SIGTERM", () => void shutdown("SIGTERM"));
}

main().catch((error) => {
  console.error("Failed to start EventFlow API", error);
  process.exit(1);
});
