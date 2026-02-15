import { Database } from "bun:sqlite";
import { join } from "path";
import { CLIPPY_DIR } from "./config";

export interface DbEntry {
  id: number;
  content_hash: string;
  ciphertext: Uint8Array;
  iv: Uint8Array;
  content_type: string;
  content_len: number;
  created_at: string;
  accessed_at: string;
}

export class ClippyDb {
  private db: Database;
  private stmtInsert!: ReturnType<Database["prepare"]>;
  private stmtTouch!: ReturnType<Database["prepare"]>;
  private stmtFindByHash!: ReturnType<Database["prepare"]>;
  private stmtGetRecent!: ReturnType<Database["prepare"]>;
  private stmtGetById!: ReturnType<Database["prepare"]>;
  private stmtDeleteById!: ReturnType<Database["prepare"]>;
  private stmtDeleteAll!: ReturnType<Database["prepare"]>;
  private stmtCount!: ReturnType<Database["prepare"]>;
  private stmtPruneByCount!: ReturnType<Database["prepare"]>;
  private stmtPruneByAge!: ReturnType<Database["prepare"]>;

  constructor(dbPath?: string) {
    const path = dbPath ?? join(CLIPPY_DIR, "clippy.db");
    this.db = new Database(path);
    this.init();
  }

  private init(): void {
    this.db.run("PRAGMA journal_mode = WAL");
    this.db.run("PRAGMA foreign_keys = ON");

    this.db.run(`
      CREATE TABLE IF NOT EXISTS entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content_hash TEXT UNIQUE NOT NULL,
        ciphertext BLOB NOT NULL,
        iv BLOB NOT NULL,
        content_type TEXT NOT NULL DEFAULT 'text',
        content_len INTEGER NOT NULL,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        accessed_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    `);

    this.db.run(`
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    `);

    this.prepareStatements();
  }

  private prepareStatements(): void {
    this.stmtInsert = this.db.prepare(`
      INSERT INTO entries (content_hash, ciphertext, iv, content_type, content_len)
      VALUES (?, ?, ?, ?, ?)
    `);

    this.stmtTouch = this.db.prepare(`
      UPDATE entries SET accessed_at = datetime('now') WHERE content_hash = ?
    `);

    this.stmtFindByHash = this.db.prepare(`
      SELECT id FROM entries WHERE content_hash = ?
    `);

    this.stmtGetRecent = this.db.prepare(`
      SELECT * FROM entries ORDER BY accessed_at DESC LIMIT ?
    `);

    this.stmtGetById = this.db.prepare(`
      SELECT * FROM entries WHERE id = ?
    `);

    this.stmtDeleteById = this.db.prepare(`
      DELETE FROM entries WHERE id = ?
    `);

    this.stmtDeleteAll = this.db.prepare(`DELETE FROM entries`);

    this.stmtCount = this.db.prepare(`SELECT COUNT(*) as count FROM entries`);

    this.stmtPruneByCount = this.db.prepare(`
      DELETE FROM entries WHERE id NOT IN (
        SELECT id FROM entries ORDER BY accessed_at DESC LIMIT ?
      )
    `);

    this.stmtPruneByAge = this.db.prepare(`
      DELETE FROM entries WHERE created_at < datetime('now', '-' || ? || ' days')
    `);
  }

  insertOrTouch(
    hash: string,
    ciphertext: Uint8Array,
    iv: Uint8Array,
    type: string,
    len: number,
  ): { id: number; isNew: boolean } {
    const existing = this.stmtFindByHash.get(hash) as
      | { id: number }
      | undefined;
    if (existing) {
      this.stmtTouch.run(hash);
      return { id: existing.id, isNew: false };
    }
    const result = this.stmtInsert.run(hash, ciphertext, iv, type, len);
    return { id: Number(result.lastInsertRowid), isNew: true };
  }

  getRecent(limit: number): DbEntry[] {
    return this.stmtGetRecent.all(limit) as DbEntry[];
  }

  getById(id: number): DbEntry | null {
    return (this.stmtGetById.get(id) as DbEntry | null) ?? null;
  }

  deleteEntry(id: number): void {
    this.stmtDeleteById.run(id);
  }

  deleteAll(): void {
    this.stmtDeleteAll.run();
  }

  pruneByCount(max: number): number {
    const result = this.stmtPruneByCount.run(max);
    return result.changes;
  }

  pruneByAge(days: number): number {
    const result = this.stmtPruneByAge.run(days);
    return result.changes;
  }

  getCount(): number {
    const row = this.stmtCount.get() as { count: number };
    return row.count;
  }

  checkIntegrity(): boolean {
    const result = this.db.prepare("PRAGMA integrity_check").get() as {
      integrity_check: string;
    };
    return result.integrity_check === "ok";
  }

  close(): void {
    this.db.close();
  }
}
