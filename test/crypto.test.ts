import { describe, test, expect } from "bun:test";
import { encrypt, decrypt, getOrCreateKey } from "../src/crypto";

describe("crypto", () => {
  test("encrypt and decrypt round-trip", async () => {
    const key = await getOrCreateKey();
    const plaintext = "hello, clipboard!";

    const { ciphertext, iv } = await encrypt(key, plaintext);
    expect(ciphertext).toBeInstanceOf(Uint8Array);
    expect(iv).toBeInstanceOf(Uint8Array);
    expect(iv.length).toBe(12);
    expect(ciphertext.length).toBeGreaterThan(0);

    const decrypted = await decrypt(key, ciphertext, iv);
    expect(decrypted).toBe(plaintext);
  });

  test("different plaintexts produce different ciphertexts", async () => {
    const key = await getOrCreateKey();

    const a = await encrypt(key, "text A");
    const b = await encrypt(key, "text B");

    const aHex = Array.from(a.ciphertext).map((x) => x.toString(16)).join("");
    const bHex = Array.from(b.ciphertext).map((x) => x.toString(16)).join("");
    expect(aHex).not.toBe(bHex);
  });

  test("same plaintext produces different IVs", async () => {
    const key = await getOrCreateKey();
    const text = "same content";

    const a = await encrypt(key, text);
    const b = await encrypt(key, text);

    const aIv = Array.from(a.iv).join(",");
    const bIv = Array.from(b.iv).join(",");
    expect(aIv).not.toBe(bIv);
  });

  test("handles empty string", async () => {
    const key = await getOrCreateKey();
    const { ciphertext, iv } = await encrypt(key, "");
    const result = await decrypt(key, ciphertext, iv);
    expect(result).toBe("");
  });

  test("handles unicode content", async () => {
    const key = await getOrCreateKey();
    const text = "Hello 世界 🌍 café";
    const { ciphertext, iv } = await encrypt(key, text);
    const result = await decrypt(key, ciphertext, iv);
    expect(result).toBe(text);
  });
});
