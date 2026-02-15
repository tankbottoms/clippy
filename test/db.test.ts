import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { ClippyDb } from "../src/db";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

describe("ClippyDb", () => {
  let db: ClippyDb;
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "clippy-test-"));
    db = new ClippyDb(join(tmpDir, "test.db"));
  });

  afterEach(() => {
    db.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  test("insert and retrieve entry", () => {
    const ct = new Uint8Array([1, 2, 3]);
    const iv = new Uint8Array([4, 5, 6]);

    const result = db.insertOrTouch("hash1", ct, iv, "text", 10);
    expect(result.isNew).toBe(true);
    expect(result.id).toBeGreaterThan(0);

    const entry = db.getById(result.id);
    expect(entry).toBeDefined();
    expect(entry!.content_hash).toBe("hash1");
    expect(entry!.content_len).toBe(10);
    expect(entry!.content_type).toBe("text");
  });

  test("dedup by hash - touch existing", () => {
    const ct = new Uint8Array([1, 2, 3]);
    const iv = new Uint8Array([4, 5, 6]);

    const first = db.insertOrTouch("hash1", ct, iv, "text", 10);
    expect(first.isNew).toBe(true);

    const second = db.insertOrTouch("hash1", ct, iv, "text", 10);
    expect(second.isNew).toBe(false);
    expect(second.id).toBe(first.id);
    expect(db.getCount()).toBe(1);
  });

  test("getRecent returns entries in order", () => {
    for (let i = 0; i < 5; i++) {
      db.insertOrTouch(`hash${i}`, new Uint8Array([i]), new Uint8Array([i]), "text", i);
    }

    const recent = db.getRecent(3);
    expect(recent.length).toBe(3);
  });

  test("deleteEntry removes entry", () => {
    const { id } = db.insertOrTouch("hash1", new Uint8Array([1]), new Uint8Array([1]), "text", 1);
    expect(db.getCount()).toBe(1);

    db.deleteEntry(id);
    expect(db.getCount()).toBe(0);
    expect(db.getById(id)).toBeNull();
  });

  test("deleteAll clears all entries", () => {
    for (let i = 0; i < 5; i++) {
      db.insertOrTouch(`hash${i}`, new Uint8Array([i]), new Uint8Array([i]), "text", i);
    }
    expect(db.getCount()).toBe(5);

    db.deleteAll();
    expect(db.getCount()).toBe(0);
  });

  test("pruneByCount removes oldest entries", () => {
    for (let i = 0; i < 10; i++) {
      db.insertOrTouch(`hash${i}`, new Uint8Array([i]), new Uint8Array([i]), "text", i);
    }
    expect(db.getCount()).toBe(10);

    const pruned = db.pruneByCount(5);
    expect(pruned).toBe(5);
    expect(db.getCount()).toBe(5);
  });

  test("checkIntegrity returns true for valid db", () => {
    expect(db.checkIntegrity()).toBe(true);
  });
});
