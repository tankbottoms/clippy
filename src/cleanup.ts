import type { ClippyDb } from "./db";
import type { ClippyConfig } from "./config";

export class Cleanup {
  private timer: ReturnType<typeof setInterval> | null = null;
  private db: ClippyDb;
  private config: ClippyConfig;

  constructor(db: ClippyDb, config: ClippyConfig) {
    this.db = db;
    this.config = config;
  }

  start(): void {
    this.run();
    this.timer = setInterval(() => this.run(), 60_000);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  run(): void {
    const aged = this.db.pruneByAge(this.config.maxHistoryAge);
    const counted = this.db.pruneByCount(this.config.maxHistoryEntries);
    if (aged > 0 || counted > 0) {
      console.log(
        `[cleanup] pruned ${aged} by age, ${counted} by count`,
      );
    }
  }

  updateConfig(config: ClippyConfig): void {
    this.config = config;
  }
}
