import { unlinkSync, existsSync } from "node:fs";
import {
  MessageFramer,
  sendMessage,
  type CommandMessage,
  type IpcMessage,
} from "./ipc-protocol";

interface ClientData {
  framer: MessageFramer;
}

export class IpcServer {
  private server: ReturnType<typeof Bun.listen<ClientData>> | null = null;
  private clients = new Set<any>();
  private socketPath: string;
  private onCommand: (cmd: CommandMessage, socket: any) => void;

  constructor(
    socketPath: string,
    onCommand: (cmd: CommandMessage, socket: any) => void,
  ) {
    this.socketPath = socketPath;
    this.onCommand = onCommand;
  }

  start(): void {
    if (existsSync(this.socketPath)) {
      unlinkSync(this.socketPath);
    }

    this.server = Bun.listen<ClientData>({
      unix: this.socketPath,
      socket: {
        open: (socket) => {
          socket.data = { framer: new MessageFramer() };
          this.clients.add(socket);
          sendMessage(socket, { type: "hello", version: "0.1.0" });
        },
        data: (socket, data) => {
          const text =
            typeof data === "string"
              ? data
              : new TextDecoder().decode(data);
          const messages = socket.data.framer.push(text);
          for (const msg of messages) {
            if (msg.type === "command") {
              this.onCommand(msg, socket);
            }
          }
        },
        close: (socket) => {
          this.clients.delete(socket);
        },
        error: (_socket, error) => {
          console.error("[ipc] socket error:", error.message);
        },
      },
    });
  }

  broadcast(msg: IpcMessage): void {
    for (const client of this.clients) {
      sendMessage(client, msg);
    }
  }

  stop(): void {
    for (const client of this.clients) {
      client.end();
    }
    this.clients.clear();
    this.server?.stop();
    this.server = null;
    if (existsSync(this.socketPath)) {
      unlinkSync(this.socketPath);
    }
  }

  get clientCount(): number {
    return this.clients.size;
  }
}
