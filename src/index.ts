import { existsSync, readFileSync, writeFileSync, unlinkSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { ensureDir, CLIPPY_DIR } from "./config";
import { Daemon } from "./daemon";

const PID_PATH = join(CLIPPY_DIR, "clippy.pid");

function isBundled(): boolean {
  return process.execPath.includes(".app/Contents/MacOS/");
}

function getSwiftBinaryPath(): string {
  if (isBundled()) {
    return join(dirname(process.execPath), "ClippyBar");
  }
  return join(CLIPPY_DIR, "ClippyBar");
}

function getSwiftSourcePath(): string {
  return join(import.meta.dir, "..", "swift", "ClippyBar.swift");
}

function checkPidLock(): void {
  if (!existsSync(PID_PATH)) return;

  const pid = parseInt(readFileSync(PID_PATH, "utf-8").trim(), 10);
  if (isNaN(pid)) {
    unlinkSync(PID_PATH);
    return;
  }

  try {
    process.kill(pid, 0);
    console.error(`[clippy] already running (pid ${pid}). Exiting.`);
    process.exit(1);
  } catch {
    unlinkSync(PID_PATH);
  }
}

function writePid(): void {
  writeFileSync(PID_PATH, String(process.pid));
}

function cleanupPid(): void {
  try {
    unlinkSync(PID_PATH);
  } catch {}
}

async function compileSwift(): Promise<void> {
  if (isBundled()) {
    console.log("[clippy] running from app bundle, skipping compilation");
    return;
  }

  const source = getSwiftSourcePath();
  const binary = getSwiftBinaryPath();

  if (!existsSync(source)) {
    console.warn("[clippy] Swift source not found, skipping UI compilation");
    return;
  }

  const needsCompile =
    !existsSync(binary) ||
    statSync(source).mtimeMs > statSync(binary).mtimeMs;

  if (!needsCompile) {
    console.log("[clippy] Swift binary up to date");
    return;
  }

  console.log("[clippy] compiling Swift status bar app...");
  const proc = Bun.spawn(
    [
      "swiftc",
      "-O",
      "-o",
      binary,
      source,
      "-framework",
      "AppKit",
      "-target",
      "arm64-apple-macosx14.0",
    ],
    { stdout: "inherit", stderr: "inherit" },
  );

  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    console.error("[clippy] Swift compilation failed");
    process.exit(1);
  }
  console.log("[clippy] Swift binary compiled");
}

function spawnSwiftUI(): ReturnType<typeof Bun.spawn> | null {
  const binary = getSwiftBinaryPath();

  if (!existsSync(binary)) {
    console.warn("[clippy] no Swift binary, running without UI");
    return null;
  }

  console.log("[clippy] launching status bar app...");
  const proc = Bun.spawn([binary, CLIPPY_DIR], {
    stdout: "inherit",
    stderr: "inherit",
  });

  return proc;
}

async function main(): Promise<void> {
  ensureDir();
  checkPidLock();
  writePid();

  await compileSwift();

  const daemon = new Daemon();
  await daemon.start();

  let swiftProc = spawnSwiftUI();
  let respawnTimer: ReturnType<typeof setInterval> | null = null;

  if (swiftProc) {
    const monitorSwift = () => {
      swiftProc!.exited.then((code) => {
        if (code !== 0 && code !== null) {
          console.warn(`[clippy] Swift UI exited with code ${code}, respawning in 2s...`);
          respawnTimer = setTimeout(() => {
            swiftProc = spawnSwiftUI();
            if (swiftProc) monitorSwift();
          }, 2000);
        }
      });
    };
    monitorSwift();
  }

  const shutdown = () => {
    console.log("\n[clippy] shutting down...");
    if (respawnTimer) clearTimeout(respawnTimer);
    swiftProc?.kill();
    daemon.stop();
    cleanupPid();
    process.exit(0);
  };

  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main().catch((err) => {
  console.error("[clippy] fatal error:", err);
  cleanupPid();
  process.exit(1);
});
