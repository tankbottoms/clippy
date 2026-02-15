export interface HistoryItem {
  id: number;
  preview: string;
  contentLength: number;
  createdAt: string;
  accessedAt: string;
}

export interface StateUpdate {
  type: "state";
  countdown: number | null;
  paused: boolean;
  history: HistoryItem[];
  entryCount: number;
}

export interface HelloMessage {
  type: "hello";
  version: string;
}

export interface CommandMessage {
  type: "command";
  action:
    | "clear_clipboard"
    | "pause_countdown"
    | "resume_countdown"
    | "delete_entry"
    | "copy_entry"
    | "clear_history"
    | "get_config"
    | "update_config"
    | "quit";
  id?: number;
  config?: Record<string, unknown>;
}

export interface ConfigResponse {
  type: "config";
  config: Record<string, unknown>;
}

export interface ErrorMessage {
  type: "error";
  message: string;
}

export type IpcMessage =
  | StateUpdate
  | HelloMessage
  | CommandMessage
  | ConfigResponse
  | ErrorMessage;

export class MessageFramer {
  private buffer = "";

  push(data: string): IpcMessage[] {
    this.buffer += data;
    const messages: IpcMessage[] = [];
    let newlineIdx: number;

    while ((newlineIdx = this.buffer.indexOf("\n")) !== -1) {
      const line = this.buffer.slice(0, newlineIdx).trim();
      this.buffer = this.buffer.slice(newlineIdx + 1);
      if (line.length === 0) continue;
      try {
        messages.push(JSON.parse(line) as IpcMessage);
      } catch {
        // skip malformed lines
      }
    }

    return messages;
  }

  reset(): void {
    this.buffer = "";
  }
}

export function sendMessage(socket: { write(data: string | Uint8Array): number }, msg: IpcMessage): void {
  socket.write(JSON.stringify(msg) + "\n");
}
