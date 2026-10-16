// supabase/functions/sync-meetings/index.ts
// Weekly curator: re-syncs watched Meetup groups, expires past one-offs,
// rolls weekly recurrings forward, logs every run to public.sync_runs.
//
// Trigger: pg_cron every Monday 06:00 UTC, or POST {"limit_groups": N}.
// Auth: called with the anon key (JWT verification only); all writes use
// the function's own SUPABASE_SERVICE_ROLE_KEY. Never expose that key.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const UA = "BizLinq-Curator/1.0 (+https://bizlinq.app/support)";
const GROUPS_PER_RUN = 60;

const TOPIC_CATEGORY: Array<[string[], string]> = [
  [["real estate", "real-estate", "realtor", "property"], "Real Estate Meetings"],
  [["founder", "startup", "entrepreneur", "pitch", "venture"], "Business Networking"],
  [["tech", "software", "developer", "coding", "data science", "artificial intelligence", "cyber"], "Technology Meetings"],
  [["market", "sales", "seo", "social media", "advertising", "branding", "mlm", "multi-level"], "Business Networking"],
  [["finance", "invest", "stock", "crypto", "trading", "wealth", "women", "career", "young professional", "millennial", "job"], "Business Networking"],
];

const PHRASE_EXCLUDE = ["language exchange", "learn english", "learn spanish", "english class", "spanish class", "conversation club", "drum circle", "sound bath", "make friends", "new friends", "meet friends"];

const EXCLUDE = new Set(
  "travel traveling travelling adventure vacation tourism hiking hike outdoors camping kayak ski snowboard surf climb cycling bike running marathon dining foodie restaurant wine beer whiskey singles dating relationship moms dads parenting baby kids book books bookclub movies film films sports soccer basketball football baseball tennis fitness gym yoga pilates dance salsa music concert gaming gamers dogs cats pets church bible hikers volleyball softball pickleball golf bowling swimming cricket rugby surfing bird birds audubon wildlife meditation mindfulness spiritual english esl tutoring homework math algebra piano guitar violin drums cooking baking knitting sewing gardening photowalk crokinole boardgame board-game chess poker trivia karaoke board shaman reiki breathwork cacao tarot astrology psychic".split(" "),
);


function tokens(s: string): Set<string> {
  return new Set((s || "").toLowerCase().split(/[^a-z0-9]+/).filter(Boolean));
}

function excluded(slug: string, name: string): boolean {
  const t = new Set([...tokens(slug), ...tokens(name)]);
  for (const x of t) if (EXCLUDE.has(x)) return true;
  // Concatenated slugs dodge token matching; catch the worst by substring.
  const blob = `${slug} ${name}`.toLowerCase();
  if (["adventure", "hiking", "yoga", "singles", "dating", "church", "casino", "pubcrawl", "barcrawl", "nightclub"]
    .some((s) => blob.includes(s))) return true;
  return PHRASE_EXCLUDE.some((p) => blob.includes(p));
}

function categorize(topics: string[], title: string, group: string): string {
  const hay = [...topics, title, group].join(" ").toLowerCase();
  for (const [keys, cat] of TOPIC_CATEGORY) {
    if (keys.some((k) => hay.includes(k))) return cat;
  }
  return "Business Networking";
}

function plain(s: string, limit: number): string {
  let t = (s || "").replace(/<[^>]+>/g, " ");
  t = t.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ");
  t = t.replace(/\s+/g, " ").trim();
  if (t.length <= limit) return t;
  const cut = t.slice(0, limit).split(" ");
  cut.pop();
  return cut.join(" ");
}

function walk(node: unknown, out: Array<Record<string, unknown>>): void {
  if (Array.isArray(node)) {
    for (const v of node) walk(v, out);
  } else if (node && typeof node === "object") {
    out.push(node as Record<string, unknown>);
    for (const v of Object.values(node)) walk(v, out);
  }
}

interface NormEvent {
  title: string; description: string; starts_at: string; url: string;
  is_online: boolean; going: number; cost: string;
  venue_name: string; address: string; city: string; state: string;
}

function parseGroup(url: string, htmlText: string): { group: { name: string; city: string; lat: number | null; lon: number | null; topics: string[] }; events: NormEvent[] } | null {
  const m = htmlText.match(/<script id="__NEXT_DATA__" type="application\/json">(.*?)<\/script>/s);
  if (!m) return null;
  const data = JSON.parse(m[1]);
  const nodes: Array<Record<string, unknown>> = [];
  walk(data, nodes);
  const venues = new Map<string, Record<string, unknown>>();
  const topicsById = new Map<string, string>();
  let group: Record<string, unknown> | null = null;
  const events: Array<Record<string, unknown>> = [];
  for (const n of nodes) {
    const t = n["__typename"];
    if (t === "Venue" && n["id"] != null) venues.set(String(n["id"]), n);
    else if (t === "Topic" && n["id"] != null && n["name"]) topicsById.set(String(n["id"]), String(n["name"]));
    else if (t === "Group" && !group && n["name"]) group = n;
    else if (t === "Event" && n["status"] === "ACTIVE" && n["dateTime"]) events.push(n);
  }
  if (!group) return null;
  const topics: string[] = [];
  const at = group["activeTopics"];
  if (Array.isArray(at)) {
    for (const x of at) {
      if (x && typeof x === "object") {
        const r = x as Record<string, unknown>;
        if (typeof r["name"] === "string") topics.push(r["name"]);
        else if (typeof r["__ref"] === "string" && (r["__ref"] as string).startsWith("Topic:")) {
          const name = topicsById.get((r["__ref"] as string).split(":")[1]);
          if (name) topics.push(name);
        }
      }
    }
  }
  const slug = url.replace(/\/$/, "").split("/").pop() || "";
  const out: NormEvent[] = events.map((e) => {
    const vref = ((e["venue"] as Record<string, unknown> | null)?.["__ref"] as string) || "";
    const venue = vref.startsWith("Venue:") ? venues.get(vref.split(":")[1]) : undefined;
    const going = ((e["going"] as Record<string, unknown> | null)?.["totalCount"] as number) || 0;
    const fee = (e["feeSettings"] as Record<string, unknown> | null) || {};
    const amount = (fee["amount"] as number) || 0;
    const id = String(e["id"] ?? "");
    return {
      title: plain(String(e["title"] ?? ""), 140),
      description: plain(String(e["description"] ?? ""), 500),
      starts_at: String(e["dateTime"] ?? ""),
      url: (e["eventUrl"] as string) || `https://www.meetup.com/${slug}/events/${id}/`,
      is_online: Boolean(e["isOnline"]),
      going,
      cost: amount ? `$${amount}` : "Free",
      venue_name: String((venue?.["name"] as string) || ""),
      address: String((venue?.["address"] as string) || ""),
      city: String((venue?.["city"] as string) || (group?.["city"] as string) || ""),
      state: String((venue?.["state"] as string) || ""),
    };
  }).filter((e) => e.starts_at);
  return {
    group: {
      name: plain(String(group["name"] ?? slug), 120),
      city: String(group["city"] ?? ""),
      lat: (group["lat"] as number) ?? null,
      lon: (group["lon"] as number) ?? null,
      topics,
    },
    events: out,
  };
}

async function geocode(supabase: any, address: string): Promise<{ lat: number; lon: number; zip: string | null } | null> {
  const { data: cachedRaw } = await supabase.from("geocode_cache").select("*").eq("address", address).limit(1).single();
  const cached = cachedRaw as { latitude: number; longitude: number; zip_code: string | null } | null;
  if (cached) return { lat: cached.latitude, lon: cached.longitude, zip: cached.zip_code };
  try {
    const q = new URLSearchParams({ address, benchmark: "Public_AR_Current", format: "json" });
    const res = await fetch(`https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?${q}`, { headers: { "User-Agent": UA } });
    const d = await res.json();
    const m = d?.result?.addressMatches?.[0];
    if (!m) return null;
    const row = { lat: m.coordinates.y, lon: m.coordinates.x, zip: m.addressComponents?.zip ?? null };
    await supabase.from("geocode_cache").insert({ address, latitude: row.lat, longitude: row.lon, zip_code: row.zip });
    return row;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  const supabase = createClient<any>(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  let limit = GROUPS_PER_RUN;
  try {
    const body = await req.json();
    if (typeof body?.limit_groups === "number") limit = Math.min(body.limit_groups, 200);
  } catch { /* GET or empty body */ }

  const runId = await supabase.from("sync_runs").insert({ source: "meetup-weekly" }).select("id").single()
    .then((r) => r.data?.id as number | undefined, () => undefined);

  let inserted = 0, updated = 0, expired = 0, groups = 0;
  let error: string | null = null;
  try {
    const { data: watch } = await supabase.from("source_groups")
      .select("*").eq("platform", "meetup").eq("active", true)
      .order("last_synced_at", { ascending: true, nullsFirst: true }).limit(limit);
    for (const g of watch ?? []) {
      try {
        const res = await fetch(g.group_url, { headers: { "User-Agent": UA } });
        if (!res.ok) continue;
        const parsed = parseGroup(g.group_url, await res.text());
        if (!parsed || excluded(g.group_url.split("/").filter(Boolean).pop() || "", parsed.group.name)) {
          await supabase.from("source_groups").update({ active: false }).eq("id", g.id);
          continue;
        }
        let count = 0;
        for (const e of parsed.events) {
          if (new Date(e.starts_at).getTime() < Date.now() - 2 * 3600_000) continue;
          // Event-level business-only filter (mirrors the importer).
          const eToks = tokens(e.title);
          let skip = false;
          for (const x of eToks) if (EXCLUDE.has(x)) { skip = true; break; }
          if (!skip) {
            const lower = e.title.toLowerCase();
            if (PHRASE_EXCLUDE.some((p) => lower.includes(p))) skip = true;
          }
          if (skip) continue;
          const zipM = e.address.match(/\b(\d{5})(?:-\d{4})?\b/);
          let zip = zipM ? zipM[1] : "";
          let lat: number | null = null, lon: number | null = null;
          if (e.address) {
            const geo = await geocode(supabase, e.address);
            if (geo) { lat = geo.lat; lon = geo.lon; zip = zip || geo.zip || ""; }
          }
          if ((lat == null || !zip) && e.city && e.state) {
            const geo = await geocode(supabase, `${e.city}, ${e.state}`);
            if (geo) { lat = lat ?? geo.lat; lon = lon ?? geo.lon; zip = zip || geo.zip || ""; }
          }
          if (lat == null && parsed.group.lat != null) { lat = parsed.group.lat; lon = parsed.group.lon; }
          if (lat == null || !e.city) continue;
          const category = categorize(parsed.group.topics, e.title, parsed.group.name);
          const row = {
            title: e.title || parsed.group.name,
            group_name: parsed.group.name,
            category,
            tagline: e.description ? e.description.slice(0, 140).split(" ").slice(0, -1).join(" ") : `Hosted by ${parsed.group.name}`,
            description: (e.description + ` More info: ${e.url}`).slice(0, 900),
            starts_at: e.starts_at,
            venue: e.venue_name || (e.is_online ? "Online" : "To be announced"),
            address: e.address || (e.is_online ? "Online event" : ""),
            city: e.city, state: e.state, zip_code: zip,
            latitude: lat, longitude: lon,
            host_name: parsed.group.name,
            attendee_count: e.going,
            is_virtual: e.is_online,
            cost_description: e.cost,
            status: "live",
            source: "meetup", source_url: e.url,
            last_verified_at: new Date().toISOString(),
          };
          const { error: upErr } = await supabase.from("meetings").upsert(row, { onConflict: "source_url" });
          if (!upErr) { count++; inserted++; }
          await new Promise((r) => setTimeout(r, 400));
        }
        updated++;
        await supabase.from("source_groups").update({ last_synced_at: new Date().toISOString(), last_event_count: count, group_name: parsed.group.name, metro: parsed.group.city }).eq("id", g.id);
        groups++;
        await new Promise((r) => setTimeout(r, 1500));
      } catch (e) {
        error = String(e).slice(0, 300);
      }
    }
    // Expire past one-offs.
    const { count: expCount } = await supabase.from("meetings")
      .update({ status: "expired" }, { count: "exact" })
      .eq("status", "live").is("recurrence", null)
      .lt("starts_at", new Date(Date.now() - 2 * 3600_000).toISOString());
    expired = expCount ?? 0;
    // Roll weekly recurrings forward.
    const { data: stale } = await supabase.from("meetings")
      .select("*").eq("status", "live").eq("recurrence", "weekly")
      .lt("starts_at", new Date().toISOString()).limit(50);
    for (const m of stale ?? []) {
      const next = { ...m };
      delete next.id; delete next.createdAt;
      delete next.created_at;
      next.starts_at = new Date(new Date(m.starts_at).getTime() + 7 * 86400_000).toISOString();
      next.last_verified_at = new Date().toISOString();
      const { error: insErr } = await supabase.from("meetings").insert(next);
      if (!insErr) {
        await supabase.from("meetings").update({ status: "expired" }).eq("id", m.id);
        inserted++;
      }
    }
  } catch (e) {
    error = String(e).slice(0, 300);
  }
  if (runId) {
    await supabase.from("sync_runs").update({ finished_at: new Date().toISOString(), inserted, updated, expired, error }).eq("id", runId);
  }
  return new Response(JSON.stringify({ groups, inserted, expired, error }), { headers: { "Content-Type": "application/json" } });
});
