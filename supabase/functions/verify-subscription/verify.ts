// App Store JWS verification (StoreKit 2 signed transactions).
//
// A signed transaction is a compact JWS whose header carries an x5c chain:
// [leaf, Apple intermediate, Apple Root CA - G3]. We accept it only if
//   - the root is byte-for-byte Apple Root CA - G3 (pinned SHA-256),
//   - each certificate is signed by the next,
//   - the intermediate and leaf carry Apple's marker extensions,
//   - the chain was valid when Apple signed the payload (signedDate), and
//   - the JWS signature verifies with the leaf key (ES256).
// No App Store Server API keys are needed for this.

import * as x509 from "npm:@peculiar/x509@1.12.3";

x509.cryptoProvider.set(crypto);

/** SHA-256 of Apple Root CA - G3 (https://www.apple.com/certificateauthority/). */
export const APPLE_ROOT_CA_G3_SHA256 =
  "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const OID_APPLE_WWDR_INTERMEDIATE = "1.2.840.113635.100.6.2.1";
const OID_APPLE_RECEIPT_SIGNING = "1.2.840.113635.100.6.11.1";

export class JWSError extends Error {}

export interface SignedTransaction {
  bundleId: string;
  productId: string;
  originalTransactionId: string;
  transactionId: string;
  expiresDate?: number;
  revocationDate?: number;
  signedDate: number;
  environment: string;
  type: string;
  appAccountToken?: string;
}

function bytes(bin: string): ArrayBuffer {
  const out = new ArrayBuffer(bin.length);
  const view = new Uint8Array(out);
  for (let i = 0; i < bin.length; i++) view[i] = bin.charCodeAt(i);
  return out;
}

function base64UrlDecode(input: string): ArrayBuffer {
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(input.length / 4) * 4, "=");
  return bytes(atob(b64));
}

function base64Decode(input: string): ArrayBuffer {
  return bytes(atob(input));
}

async function sha256Hex(bytes: ArrayBuffer): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function verifySignedTransaction(
  jws: string,
  rootFingerprint: string = APPLE_ROOT_CA_G3_SHA256,
): Promise<SignedTransaction> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new JWSError("malformed JWS");
  const [headerPart, payloadPart, signaturePart] = parts;

  let header: { alg?: string; x5c?: string[] };
  try {
    header = JSON.parse(new TextDecoder().decode(base64UrlDecode(headerPart)));
  } catch {
    throw new JWSError("unreadable header");
  }
  if (header.alg !== "ES256") throw new JWSError("unexpected algorithm");
  if (!Array.isArray(header.x5c) || header.x5c.length !== 3) throw new JWSError("missing certificate chain");

  let leaf: x509.X509Certificate, intermediate: x509.X509Certificate, root: x509.X509Certificate;
  try {
    [leaf, intermediate, root] = header.x5c.map((der) => new x509.X509Certificate(base64Decode(der)));
  } catch {
    throw new JWSError("unreadable certificate");
  }

  if ((await sha256Hex(root.rawData)) !== rootFingerprint) throw new JWSError("untrusted root");
  if (!(await intermediate.verify({ publicKey: root, signatureOnly: true }))) {
    throw new JWSError("intermediate not signed by root");
  }
  if (!(await leaf.verify({ publicKey: intermediate, signatureOnly: true }))) {
    throw new JWSError("leaf not signed by intermediate");
  }
  if (!intermediate.getExtension(OID_APPLE_WWDR_INTERMEDIATE)) throw new JWSError("not an Apple intermediate");
  if (!leaf.getExtension(OID_APPLE_RECEIPT_SIGNING)) throw new JWSError("not an App Store signing certificate");

  let payload: SignedTransaction;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadPart)));
  } catch {
    throw new JWSError("unreadable payload");
  }

  const signedAt = new Date(payload.signedDate);
  if (Number.isNaN(signedAt.getTime())) throw new JWSError("missing signedDate");
  for (const cert of [leaf, intermediate, root]) {
    if (signedAt < cert.notBefore || signedAt > cert.notAfter) throw new JWSError("certificate not valid at signing time");
  }

  const key = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"]);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    base64UrlDecode(signaturePart),
    new TextEncoder().encode(`${headerPart}.${payloadPart}`),
  );
  if (!valid) throw new JWSError("bad signature");

  return payload;
}
