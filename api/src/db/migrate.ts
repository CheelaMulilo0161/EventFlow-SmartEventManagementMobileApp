import { Pool, PoolClient } from "pg";
import { migrations } from "./migrations";

export async function runMigrations(db: Pool | PoolClient): Promise<string[]> {
  await db.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  const applied = new Set(
    (await db.query<{ id: string }>("SELECT id FROM schema_migrations")).rows.map(
      (row) => row.id,
    ),
  );
  const newlyApplied: string[] = [];

  for (const migration of migrations) {
    if (applied.has(migration.id)) continue;

    await db.query("BEGIN");
    try {
      await db.query(migration.sql);
      await db.query("INSERT INTO schema_migrations (id) VALUES ($1)", [migration.id]);
      await db.query("COMMIT");
      newlyApplied.push(migration.id);
    } catch (error) {
      await db.query("ROLLBACK");
      throw error;
    }
  }

  return newlyApplied;
}
