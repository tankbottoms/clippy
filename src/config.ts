import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface ClippyConfig {
  wipeDelay: number;
  maxContentLength: number;
  maxHistoryEntries: number;
  maxHistoryAge: number;
  pollInterval: number;
  historyDisplayCount: number;
  previewLength: number;
}

const DEFAULT_CONFIG: ClippyConfig = {
  wipeDelay: 5,
  maxContentLength: 10000,
  maxHistoryEntries: 1000,
  maxHistoryAge: 30,
  pollInterval: 500,
  historyDisplayCount: 20,
  previewLength: 50,
};

export const CLIPPY_DIR = join(homedir(), ".clippy");
const CONFIG_PATH = join(CLIPPY_DIR, "config.json");

export function ensureDir(): void {
  if (!existsSync(CLIPPY_DIR)) {
    mkdirSync(CLIPPY_DIR, { recursive: true });
  }
}

export function loadConfig(): ClippyConfig {
  ensureDir();
  try {
    const text = readFileSync(CONFIG_PATH, "utf-8");
    const parsed = JSON.parse(text);
    return mergeConfig(parsed);
  } catch {
    const config = { ...DEFAULT_CONFIG };
    saveConfig(config);
    return config;
  }
}

export function saveConfig(config: ClippyConfig): void {
  ensureDir();
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

export function mergeConfig(partial: Partial<ClippyConfig>): ClippyConfig {
  return { ...DEFAULT_CONFIG, ...partial };
}
