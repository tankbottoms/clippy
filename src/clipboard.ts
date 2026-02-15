export class ClipboardMonitor {
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastHash: string | null = null;
  private expectedHash: string | null = null;
  private onChange: (content: string, hash: string) => void;
  private pollInterval: number;

  constructor(
    pollInterval: number,
    onChange: (content: string, hash: string) => void,
  ) {
    this.pollInterval = pollInterval;
    this.onChange = onChange;
  }

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => this.poll(), this.pollInterval);
    this.poll();
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  setExpectedHash(hash: string): void {
    this.expectedHash = hash;
  }

  private async poll(): Promise<void> {
    try {
      const content = await readClipboard();
      if (!content || content.length === 0) {
        this.lastHash = null;
        return;
      }

      const hash = await hashContent(content);

      if (hash === this.lastHash) return;
      this.lastHash = hash;

      if (hash === this.expectedHash) {
        this.expectedHash = null;
        return;
      }

      this.onChange(content, hash);
    } catch {
      // pbpaste failed, skip this cycle
    }
  }
}

async function readClipboard(): Promise<string> {
  const proc = Bun.spawn(["pbpaste"], { stdout: "pipe", stderr: "pipe" });
  await proc.exited;
  return new Response(proc.stdout).text();
}

export async function clearClipboard(): Promise<void> {
  const proc = Bun.spawn(["pbcopy"], {
    stdin: new Blob([""]),
    stdout: "pipe",
    stderr: "pipe",
  });
  await proc.exited;
}

export async function setClipboard(content: string): Promise<void> {
  const proc = Bun.spawn(["pbcopy"], {
    stdin: new Blob([content]),
    stdout: "pipe",
    stderr: "pipe",
  });
  await proc.exited;
}

export async function hashContent(content: string): Promise<string> {
  const encoded = new TextEncoder().encode(content);
  const buffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(buffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
