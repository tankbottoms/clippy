import { join } from "node:path";
import {
  loadConfig,
  saveConfig,
  mergeConfig,
  CLIPPY_DIR,
  type ClippyConfig,
} from "./config";
import { ClippyDb } from "./db";
import { getOrCreateKey, encrypt, decrypt } from "./crypto";
import { ClipboardMonitor, clearClipboard, setClipboard, hashContent } from "./clipboard";
import { Wiper } from "./wiper";
import { Cleanup } from "./cleanup";
import { IpcServer } from "./ipc-server";
import type { CommandMessage, HistoryItem, StateUpdate } from "./ipc-protocol";

export class Daemon {
  private config: ClippyConfig;
  private db: ClippyDb;
  private key!: CryptoKey;
  private clipboard!: ClipboardMonitor;
  private wiper!: Wiper;
  private cleanup!: Cleanup;
  private ipc!: IpcServer;

  constructor() {
    this.config = loadConfig();
    this.db = new ClippyDb();
  }

  async start(): Promise<void> {
    console.log("[daemon] starting...");

    this.key = await getOrCreateKey();
    console.log("[daemon] encryption key ready");

    this.wiper = new Wiper(
      this.config.wipeDelay,
      () => this.handleWipe(),
      () => this.pushState(),
    );

    this.clipboard = new ClipboardMonitor(
      this.config.pollInterval,
      (content, hash) => this.handleClipboardChange(content, hash),
    );

    this.ipc = new IpcServer(
      join(CLIPPY_DIR, "clippy.sock"),
      (cmd, socket) => this.handleCommand(cmd, socket),
    );

    this.cleanup = new Cleanup(this.db, this.config);

    this.ipc.start();
    console.log("[daemon] ipc server listening");

    this.clipboard.start();
    console.log("[daemon] clipboard monitor started");

    this.cleanup.start();
    console.log("[daemon] cleanup scheduler started");

    console.log("[daemon] ready");
  }

  stop(): void {
    console.log("[daemon] shutting down...");
    this.clipboard?.stop();
    this.wiper?.stopCountdown();
    this.cleanup?.stop();
    this.ipc?.stop();
    this.db?.close();
    console.log("[daemon] stopped");
  }

  private async handleClipboardChange(
    content: string,
    hash: string,
  ): Promise<void> {
    const truncated =
      content.length > this.config.maxContentLength
        ? content.slice(0, this.config.maxContentLength)
        : content;

    const { ciphertext, iv } = await encrypt(this.key, truncated);

    this.db.insertOrTouch(hash, ciphertext, iv, "text", truncated.length);

    this.wiper.startCountdown();
    this.pushState();
  }

  private async handleWipe(): Promise<void> {
    await clearClipboard();
    console.log("[daemon] clipboard wiped");
    this.pushState();
  }

  private async handleCommand(cmd: CommandMessage, socket: any): Promise<void> {
    switch (cmd.action) {
      case "clear_clipboard":
        await clearClipboard();
        this.wiper.stopCountdown();
        this.pushState();
        break;

      case "pause_countdown":
        this.wiper.pause();
        break;

      case "resume_countdown":
        this.wiper.resume();
        break;

      case "delete_entry":
        if (cmd.id !== undefined) {
          this.db.deleteEntry(cmd.id);
          this.pushState();
        }
        break;

      case "copy_entry":
        if (cmd.id !== undefined) {
          const entry = this.db.getById(cmd.id);
          if (entry) {
            const plaintext = await decrypt(
              this.key,
              new Uint8Array(entry.ciphertext),
              new Uint8Array(entry.iv),
            );
            const hash = await hashContent(plaintext);
            this.clipboard.setExpectedHash(hash);
            await setClipboard(plaintext);
            this.wiper.startCountdown();
            this.pushState();
          }
        }
        break;

      case "clear_history":
        this.db.deleteAll();
        this.pushState();
        break;

      case "get_config":
        socket.write(
          JSON.stringify({ type: "config", config: this.config }) + "\n",
        );
        break;

      case "update_config":
        if (cmd.config) {
          this.config = mergeConfig(cmd.config as Partial<ClippyConfig>);
          saveConfig(this.config);
          this.wiper.updateDelay(this.config.wipeDelay);
          this.cleanup.updateConfig(this.config);
          this.pushState();
        }
        break;

      case "quit":
        this.stop();
        process.exit(0);
    }
  }

  private async pushState(): Promise<void> {
    const entries = this.db.getRecent(this.config.historyDisplayCount);
    const history: HistoryItem[] = [];

    for (const entry of entries) {
      try {
        const plaintext = await decrypt(
          this.key,
          new Uint8Array(entry.ciphertext),
          new Uint8Array(entry.iv),
        );
        history.push({
          id: entry.id,
          preview: plaintext.slice(0, this.config.previewLength).replace(/\n/g, " "),
          contentLength: entry.content_len,
          createdAt: entry.created_at,
          accessedAt: entry.accessed_at,
        });
      } catch {
        history.push({
          id: entry.id,
          preview: "[decryption failed]",
          contentLength: entry.content_len,
          createdAt: entry.created_at,
          accessedAt: entry.accessed_at,
        });
      }
    }

    const wiperState = this.wiper.getState();
    const state: StateUpdate = {
      type: "state",
      countdown: wiperState.countdown,
      paused: wiperState.paused,
      history,
      entryCount: this.db.getCount(),
    };

    this.ipc.broadcast(state);
  }
}
