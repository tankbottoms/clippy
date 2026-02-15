import { describe, test, expect, beforeEach, afterEach } from "bun:test";
import { Cleanup } from "../src/cleanup";
import { ClippyDb } from "../src/db";
import { mergeConfig } from "../src/config";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

describe("Cleanup", () => {
  let db: ClippyDb;
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), "clippy-cleanup-test-"));
    db = new ClippyDb(join(tmpDir, "test.db"));
  });

  afterEach(() => {
    db.close();
    rmSync(tmpDir, { recursive: true, force: true });
  });

  test("prunes entries exceeding maxHistoryEntries", () => {
    const config = mergeConfig({ maxHistoryEntries: 5, maxHistoryAge: 30 });
    const cleanup = new Cleanup(db, config);

    for (let i = 0; i < 10; i++) {
      db.insertOrTouch(`hash${i}`, new Uint8Array([i]), new Uint8Array([i]), "text", i);
    }
    expect(db.getCount()).toBe(10);

    cleanup.run();
    expect(db.getCount()).toBe(5);

    cleanup.stop();
  });

  test("updateConfig updates cleanup parameters", () => {
    const config = mergeConfig({ maxHistoryEntries: 10, maxHistoryAge: 30 });
    const cleanup = new Cleanup(db, config);

    for (let i = 0; i < 10; i++) {
      db.insertOrTouch(`hash${i}`, new Uint8Array([i]), new Uint8Array([i]), "text", i);
    }

    cleanup.updateConfig(mergeConfig({ maxHistoryEntries: 3, maxHistoryAge: 30 }));
    cleanup.run();
    expect(db.getCount()).toBe(3);

    cleanup.stop();
  });
});
