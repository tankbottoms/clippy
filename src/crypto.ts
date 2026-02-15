const SERVICE_NAME = "com.clippy.encryption";
const ACCOUNT_NAME = "clippy-aes-key";

export async function getOrCreateKey(): Promise<CryptoKey> {
  const existing = await readKeyFromKeychain();
  if (existing) {
    return importKey(existing);
  }

  const rawKey = crypto.getRandomValues(new Uint8Array(32));
  await storeKeyInKeychain(rawKey);
  return importKey(rawKey);
}

async function readKeyFromKeychain(): Promise<Uint8Array | null> {
  try {
    const proc = Bun.spawn(
      [
        "security",
        "find-generic-password",
        "-s",
        SERVICE_NAME,
        "-a",
        ACCOUNT_NAME,
        "-w",
      ],
      { stdout: "pipe", stderr: "pipe" },
    );

    const exitCode = await proc.exited;
    if (exitCode !== 0) return null;

    const hex = (await new Response(proc.stdout).text()).trim();
    if (!hex || hex.length !== 64) return null;
    return hexToBytes(hex);
  } catch {
    return null;
  }
}

async function storeKeyInKeychain(key: Uint8Array): Promise<void> {
  const hex = bytesToHex(key);
  const proc = Bun.spawn(
    [
      "security",
      "add-generic-password",
      "-s",
      SERVICE_NAME,
      "-a",
      ACCOUNT_NAME,
      "-w",
      hex,
      "-U",
    ],
    { stdout: "pipe", stderr: "pipe" },
  );

  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    throw new Error(`Failed to store key in Keychain: ${stderr}`);
  }
}

async function importKey(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength) as ArrayBuffer,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encrypt(
  key: CryptoKey,
  plaintext: string,
): Promise<{ ciphertext: Uint8Array; iv: Uint8Array }> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    encoded,
  );
  return { ciphertext: new Uint8Array(encrypted), iv };
}

export async function decrypt(
  key: CryptoKey,
  ciphertext: Uint8Array,
  iv: Uint8Array,
): Promise<string> {
  const buf = ciphertext.buffer.slice(
    ciphertext.byteOffset,
    ciphertext.byteOffset + ciphertext.byteLength,
  ) as ArrayBuffer;
  const ivBuf = iv.buffer.slice(
    iv.byteOffset,
    iv.byteOffset + iv.byteLength,
  ) as ArrayBuffer;
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: ivBuf },
    key,
    buf,
  );
  return new TextDecoder().decode(decrypted);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}
