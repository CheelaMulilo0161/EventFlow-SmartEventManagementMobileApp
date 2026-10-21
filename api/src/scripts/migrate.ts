import { pool } from "../db";
import { runMigrations } from "../db/migrate";

async function main() {
  const applied = await runMigrations(pool);
  if (applied.length === 0) {
    console.log("Database is already up to date.");
  } else {
    console.log(`Applied migrations: ${applied.join(", ")}`);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
