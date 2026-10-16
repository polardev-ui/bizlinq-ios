// deno test --allow-net=registry.npmjs.org supabase/functions/verify-subscription/verify_test.ts
// Builds a throwaway root → intermediate → leaf chain shaped like Apple's
// (same marker extensions) and pins its root, so every check runs for real.

import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import * as x509 from "npm:@peculiar/x509@1.12.3";
import { APPLE_ROOT_CA_G3_SHA256, JWSError, verifySignedTransaction } from "./verify.ts";

x509.cryptoProvider.set(crypto);

const ec = (curve: string) => ({ name: "ECDSA", namedCurve: curve, hash: curve === "P-384" ? "SHA-384" : "SHA-256" });
const marker = (oid: string) => new x509.Extension(oid, false, new Uint8Array([5, 0]));

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
const b64 = (buf: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(buf)));

async function fingerprint(cert: x509.X509Certificate): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", cert.rawData);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function makeChain(opts: { leafMarker?: boolean } = {}) {
  const notBefore = new Date(Date.now() - 86_400_000);
  const notAfter = new Date(Date.now() + 365 * 86_400_000);
  const rootKeys = await crypto.subtle.generateKey(ec("P-384"), true, ["sign", "verify"]) as CryptoKeyPair;
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Test Root", notBefore, notAfter, keys: rootKeys, signingAlgorithm: ec("P-384"),
  });
  const interKeys = await crypto.subtle.generateKey(ec("P-384"), true, ["sign", "verify"]) as CryptoKeyPair;
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Test Intermediate", issuer: root.subject, notBefore, notAfter,
    publicKey: interKeys.publicKey, signingKey: rootKeys.privateKey, signingAlgorithm: ec("P-384"),
    extensions: [marker("1.2.840.113635.100.6.2.1")],
  });
  const leafKeys = await crypto.subtle.generateKey(ec("P-256"), true, ["sign", "verify"]) as CryptoKeyPair;
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=Test Leaf", issuer: intermediate.subject, notBefore, notAfter,
    publicKey: leafKeys.publicKey, signingKey: interKeys.privateKey, signingAlgorithm: ec("P-384"),
    extensions: opts.leafMarker === false ? [] : [marker("1.2.840.113635.100.6.11.1")],
  });
  return { root, intermediate, leaf, leafKey: leafKeys.privateKey };
}

async function sign(chain: Awaited<ReturnType<typeof makeChain>>, payload: Record<string, unknown>) {
  const header = { alg: "ES256", x5c: [chain.leaf, chain.intermediate, chain.root].map((c) => b64(c.rawData)) };
  const enc = new TextEncoder();
  const h = b64url(enc.encode(JSON.stringify(header)));
  const p = b64url(enc.encode(JSON.stringify(payload)));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chain.leafKey, enc.encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(new Uint8Array(sig))}`;
}

const payload = {
  bundleId: "com.bizlinq.app",
  productId: "bizlinq.poster.monthly",
  originalTransactionId: "1000",
  transactionId: "1001",
  expiresDate: Date.now() + 30 * 86_400_000,
  signedDate: Date.now(),
  environment: "Sandbox",
  type: "Auto-Renewable Subscription",
};

Deno.test("accepts a correctly signed chain with the pinned root", async () => {
  const chain = await makeChain();
  const tx = await verifySignedTransaction(await sign(chain, payload), await fingerprint(chain.root));
  assertEquals(tx.productId, "bizlinq.poster.monthly");
});

Deno.test("rejects a valid chain whose root is not Apple's", async () => {
  const chain = await makeChain();
  await assertRejects(() => sign(chain, payload).then((j) => verifySignedTransaction(j, APPLE_ROOT_CA_G3_SHA256)), JWSError, "untrusted root");
});

Deno.test("rejects a tampered payload", async () => {
  const chain = await makeChain();
  const [h, , s] = (await sign(chain, payload)).split(".");
  const forged = b64url(new TextEncoder().encode(JSON.stringify({ ...payload, expiresDate: Date.now() + 9e12 })));
  await assertRejects(() => verifySignedTransaction(`${h}.${forged}.${s}`, "x"), JWSError);
  const fp = await fingerprint(chain.root);
  await assertRejects(() => verifySignedTransaction(`${h}.${forged}.${s}`, fp), JWSError, "bad signature");
});

Deno.test("rejects a leaf without Apple's signing marker", async () => {
  const chain = await makeChain({ leafMarker: false });
  await assertRejects(
    async () => verifySignedTransaction(await sign(chain, payload), await fingerprint(chain.root)),
    JWSError,
    "not an App Store signing certificate",
  );
});

Deno.test("rejects a chain swapped from another issuer", async () => {
  const a = await makeChain();
  const b = await makeChain();
  const mixed = { ...a, intermediate: b.intermediate };
  await assertRejects(
    async () => verifySignedTransaction(await sign(mixed, payload), await fingerprint(a.root)),
    JWSError,
    "intermediate not signed by root",
  );
});

Deno.test("rejects garbage", async () => {
  await assertRejects(() => verifySignedTransaction("not-a-jws"), JWSError, "malformed JWS");
});
