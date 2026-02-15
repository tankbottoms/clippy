import { describe, test, expect } from "bun:test";
import { MessageFramer, type IpcMessage } from "../src/ipc-protocol";

describe("MessageFramer", () => {
  test("parses single complete message", () => {
    const framer = new MessageFramer();
    const msg: IpcMessage = { type: "hello", version: "0.1.0" };
    const result = framer.push(JSON.stringify(msg) + "\n");

    expect(result.length).toBe(1);
    expect(result[0]).toEqual(msg);
  });

  test("buffers partial messages", () => {
    const framer = new MessageFramer();
    const msg = JSON.stringify({ type: "hello", version: "0.1.0" });

    // Send first half
    const r1 = framer.push(msg.slice(0, 10));
    expect(r1.length).toBe(0);

    // Send rest + newline
    const r2 = framer.push(msg.slice(10) + "\n");
    expect(r2.length).toBe(1);
    expect(r2[0].type).toBe("hello");
  });

  test("parses multiple messages in one chunk", () => {
    const framer = new MessageFramer();
    const msg1 = JSON.stringify({ type: "hello", version: "0.1.0" });
    const msg2 = JSON.stringify({ type: "state", countdown: 5, paused: false, history: [], entryCount: 0 });

    const result = framer.push(msg1 + "\n" + msg2 + "\n");
    expect(result.length).toBe(2);
    expect(result[0].type).toBe("hello");
    expect(result[1].type).toBe("state");
  });

  test("skips malformed lines", () => {
    const framer = new MessageFramer();
    const result = framer.push("not json\n" + JSON.stringify({ type: "hello", version: "0.1.0" }) + "\n");

    expect(result.length).toBe(1);
    expect(result[0].type).toBe("hello");
  });

  test("skips empty lines", () => {
    const framer = new MessageFramer();
    const msg = JSON.stringify({ type: "hello", version: "0.1.0" });
    const result = framer.push("\n\n" + msg + "\n\n");

    expect(result.length).toBe(1);
  });

  test("reset clears buffer", () => {
    const framer = new MessageFramer();
    framer.push('{"type":"hel');
    framer.reset();

    const msg = JSON.stringify({ type: "hello", version: "0.1.0" });
    const result = framer.push(msg + "\n");

    expect(result.length).toBe(1);
    expect(result[0].type).toBe("hello");
  });
});
