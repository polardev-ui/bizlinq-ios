// supabase/functions/verify-subscription/index.ts
// Records a verified App Store subscription so can_post() lets the host post
// after the free trial. The app calls this with the user's session after a
// purchase, a restore, and on launch.
//
// Request:  POST {"jws": "<StoreKit 2 signed transaction>"} with the user's
//           Authorization: Bearer <access token>.
// Response: {"active": true, "expires_at": "..."} or {"active": false, ...}.
// Writes use SUPABASE_SERVICE_ROLE_KEY; users cannot write entitlements.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { JWSError, verifySignedTransaction } from "./verify.ts";

const BUNDLE_ID = "com.bizlinq.app";
const PRODUCTS = new Set(["bizlinq.poster.monthly", "bizlinq.poster.annual"]);
const ENVIRONMENTS = new Set(["Production", "Sandbox"]);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData?.user) return json({ error: "sign in required" }, 401);
  const userId = userData.user.id;

  let jws: string;
  try {
    jws = String((await req.json()).jws ?? "");
  } catch {
    return json({ error: "invalid body" }, 400);
  }
  if (!jws) return json({ error: "missing jws" }, 400);

  let tx;
  try {
    tx = await verifySignedTransaction(jws);
  } catch (e) {
    const reason = e instanceof JWSError ? e.message : "verification failed";
    return json({ error: reason }, 400);
  }

  if (tx.bundleId !== BUNDLE_ID) return json({ error: "wrong app" }, 400);
  if (!PRODUCTS.has(tx.productId)) return json({ error: "unknown product" }, 400);
  if (!ENVIRONMENTS.has(tx.environment)) return json({ error: "unsupported environment" }, 400);
  if (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    return json({ error: "subscription belongs to another account" }, 403);
  }

  // One App Store subscription unlocks one BizLinq account.
  const { data: existing } = await admin
    .from("poster_entitlements")
    .select("user_id")
    .eq("original_transaction_id", tx.originalTransactionId)
    .maybeSingle();
  if (existing && existing.user_id !== userId) {
    return json({ error: "subscription belongs to another account" }, 403);
  }

  const expires = tx.expiresDate ? new Date(tx.expiresDate) : null;
  const active = !tx.revocationDate && expires !== null && expires > new Date();
  if (!active) return json({ active: false, reason: tx.revocationDate ? "revoked" : "expired" });

  const { error } = await admin.from("poster_entitlements").upsert({
    user_id: userId,
    product_id: tx.productId,
    original_transaction_id: tx.originalTransactionId,
    expires_at: expires!.toISOString(),
    environment: tx.environment,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id" });
  if (error) return json({ error: "could not save entitlement" }, 500);

  return json({ active: true, expires_at: expires!.toISOString() });
});
