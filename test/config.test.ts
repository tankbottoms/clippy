import { describe, test, expect } from "bun:test";
import { mergeConfig, type ClippyConfig } from "../src/config";

// Override CLIPPY_DIR for tests by manipulating env
describe("config", () => {
  test("mergeConfig fills defaults", () => {
    const partial = { wipeDelay: 10 };
    const config = mergeConfig(partial);

    expect(config.wipeDelay).toBe(10);
    expect(config.maxContentLength).toBe(10000);
    expect(config.maxHistoryEntries).toBe(1000);
    expect(config.maxHistoryAge).toBe(30);
    expect(config.pollInterval).toBe(500);
    expect(config.historyDisplayCount).toBe(20);
    expect(config.previewLength).toBe(50);
  });

  test("mergeConfig with empty object returns all defaults", () => {
    const config = mergeConfig({});

    expect(config.wipeDelay).toBe(5);
    expect(config.maxContentLength).toBe(10000);
  });

  test("mergeConfig overrides all fields", () => {
    const full: ClippyConfig = {
      wipeDelay: 10,
      maxContentLength: 5000,
      maxHistoryEntries: 500,
      maxHistoryAge: 7,
      pollInterval: 250,
      historyDisplayCount: 10,
      previewLength: 30,
    };
    const config = mergeConfig(full);

    expect(config).toEqual(full);
  });
});
