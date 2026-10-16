"""Import networking events from Eventbrite discovery + event pages.

Facts only (title, time, venue, price) with source links back to every event.
Polite fetching: browser UA, 1.5s+ delays.

Usage:
  python3 tools/eventbrite_import.py --discover fl--orlando --pages 3 \\
      --out tools/seed_eb_orl.sql
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.request

sys.path.insert(0, "tools")
from meetup_import import (  # noqa: E402
    UA, DELAY, categorize, geocode, tokens, sql_str,
    EXCLUDE_TOKENS, PHRASE_EXCLUDE, CITY_STATE, STATE_BBOX, in_state,
    load_cache, plain,
)

EB_MATCH = [
    "networking", "network", "entrepreneur", "startup", "founder",
    "business", "professional", "mixer", "referral", "mastermind",
    "real-estate", "investor", "marketing", "leadership", "executive",
    "founders", "chamber", "small-business",
]


def fetch(url):
    last = None
    for _ in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            last = e
            time.sleep(3)
    raise last


def discover_urls(discover, pages):
    urls = []
    for p in range(1, pages + 1):
        url = f"https://www.eventbrite.com/d/{discover}/networking/"
        if p > 1:
            url += f"?page={p}"
        try:
            html_text = fetch(url)
        except Exception as e:
            print(f"  discover p{p} failed: {str(e)[:80]}")
            break
        found = sorted(set(re.findall(r"https://www\.eventbrite\.com/e/[\w\-]+-\d+", html_text)))
        print(f"  discover p{p}: {len(found)} links")
        if not found:
            break
        urls.extend(found)
        time.sleep(DELAY)
    seen, out = set(), []
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


def excluded_eb(title, desc):
    toks = tokens(title) | tokens(desc[:200])
    if not toks.isdisjoint(EXCLUDE_TOKENS):
        return True
    blob = (title + " " + desc[:300]).lower()
    if any(s in blob for s in ("speed dating", "singles mixer", "learn english", "language exchange")):
        return True
    if not any(k in slug_key(title, desc) for k in EB_MATCH):
        return True
    return False


def slug_key(title, desc):
    return (title + " " + desc[:200]).lower().replace(" ", "-")


def parse_event(url):
    html_text = fetch(url)
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html_text, re.S)
    if not m:
        return None, "no-data"
    try:
        data = json.loads(m.group(1))
        info = data["props"]["pageProps"]["context"]["basicInfo"]
    except (KeyError, TypeError, json.JSONDecodeError):
        return None, "no-basic-info"
    if info.get("status") != "live":
        return None, "not-live"
    start = info.get("startDate") or {}
    starts_at = start.get("utc") or start.get("local") or ""
    if not starts_at:
        return None, "no-date"
    venue = info.get("venue") or {}
    addr = venue.get("address") or {}
    lines = addr.get("localizedMultiLineAddressDisplay") or []
    address = ", ".join(lines)
    city = str(addr.get("city") or "")
    state = str(addr.get("region") or "")
    try:
        lat = float(addr.get("latitude")) if addr.get("latitude") else None
        lon = float(addr.get("longitude")) if addr.get("longitude") else None
    except (TypeError, ValueError):
        lat = lon = None
    org = info.get("organizer") or {}
    host = str(org.get("name") or "Eventbrite Organizer")
    ctx = data["props"]["pageProps"]["context"]
    description = ""
    for mod in (ctx.get("structuredContent") or {}).get("modules", []):
        if isinstance(mod, dict) and mod.get("type") == "text" and mod.get("text"):
            t = plain(mod["text"], 900)
            if len(t) > len(description):
                description = t
    if not description:
        description = plain(str(info.get("summary") or ""), 500)
    low = re.search(r'"lowPrice"\s*:\s*"([\d.]+)"', json.dumps(data))
    if info.get("isFree"):
        cost = "Free"
    elif low and float(low.group(1)) > 0:
        cost = f"${float(low.group(1)):g}+"
    else:
        cost = "Paid (see event page)"
    return {
        "title": plain(str(info.get("name") or "Networking Event"), 140),
        "description": (description + f" More info: {url}")[:900],
        "starts_at": starts_at,
        "url": url,
        "is_online": bool(info.get("isOnline")),
        "venue_name": str(venue.get("name") or ""),
        "address": address,
        "city": city,
        "state": state,
        "lat": lat,
        "lon": lon,
        "host": host,
        "cost": cost,
        "status": "ACTIVE",
    }, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--discover", required=True)
    ap.add_argument("--pages", type=int, default=3)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    urls = discover_urls(args.discover, args.pages)
    print(f"total unique events: {len(urls)}")
    cache = load_cache()
    rows, n_skip = [], 0
    for i, url in enumerate(urls):
        try:
            parsed, err = parse_event(url)
            time.sleep(DELAY)
            if not parsed or parsed["status"] != "ACTIVE" or not parsed["starts_at"]:
                n_skip += 1
                continue
            if excluded_eb(parsed["title"], parsed["description"]):
                n_skip += 1
                continue
            city = parsed["city"]
            state = parsed["state"] or CITY_STATE.get(city, "")
            if not city or not state:
                n_skip += 1
                continue
            m = re.search(r"\b(\d{5})(?:-\d{4})?\b", parsed["address"])
            regex_zip = m.group(1) if m else ""
            zip_code, lat, lon = "", None, None
            if parsed.get("lat") is not None and parsed.get("lon") is not None:
                try:
                    if in_state(float(parsed["lat"]), float(parsed["lon"]), state):
                        lat, lon = float(parsed["lat"]), float(parsed["lon"])
                        zip_code = regex_zip
                except (TypeError, ValueError):
                    pass
            if lat is None and parsed["address"] and not parsed["is_online"]:
                g = geocode(parsed["address"], cache)
                if g and in_state(g["lat"], g["lon"], state):
                    lat, lon, zip_code = g["lat"], g["lon"], g.get("zip") or regex_zip
            if lat is None:
                g = geocode(f"{city}, {state}", cache)
                if g and in_state(g["lat"], g["lon"], state):
                    lat, lon = g["lat"], g["lon"]
                    zip_code = zip_code or g.get("zip") or regex_zip
            if lat is None:
                n_skip += 1
                continue
            rows.append({
                "title": parsed["title"] or "Networking Event",
                "group": parsed["host"],
                "category": categorize([], parsed["title"], parsed["host"]),
                "tagline": (parsed["description"][:140].rsplit(" ", 1)[0] if parsed["description"] else f"Hosted by {parsed['host']}"),
                "description": parsed["description"],
                "starts_at": parsed["starts_at"],
                "venue": parsed["venue_name"] or ("Online" if parsed["is_online"] else "To be announced"),
                "address": parsed["address"] or ("Online event" if parsed["is_online"] else ""),
                "city": city, "state": state, "zip": zip_code,
                "lat": lat, "lon": lon,
                "host": parsed["host"],
                "count": 0,
                "cost": parsed["cost"],
                "virtual": parsed["is_online"],
                "url": parsed["url"],
            })
            if (i + 1) % 10 == 0:
                print(f"  [{i+1}/{len(urls)}] rows={len(rows)} skipped={n_skip}")
        except Exception as ex:
            n_skip += 1
            print(f"  [{i+1}] FAIL {url[-30:]}: {str(ex)[:90]}")
            time.sleep(DELAY)

    with open(args.out, "w") as f:
        f.write("-- Eventbrite curated import. Review, then apply via Supabase.\n")
        for r in rows:
            f.write(
                "INSERT INTO public.meetings (title, group_name, category, tagline, description, starts_at,"
                " venue, address, city, state, zip_code, latitude, longitude, host_name, attendee_count,"
                " is_virtual, cost_description, status, source, source_url, last_verified_at) VALUES ("
                + ", ".join([
                    sql_str(r["title"]), sql_str(r["group"]), sql_str(r["category"]),
                    sql_str(r["tagline"]), sql_str(r["description"]), sql_str(r["starts_at"]),
                    sql_str(r["venue"]), sql_str(r["address"]), sql_str(r["city"]), sql_str(r["state"]),
                    sql_str(r["zip"]), str(r["lat"]), str(r["lon"]), sql_str(r["host"]),
                    str(r["count"]), "true" if r["virtual"] else "false", sql_str(r["cost"]),
                    "'live'", "'eventbrite'", sql_str(r["url"]), "now()",
                ])
                + ") ON CONFLICT (source_url) WHERE source_url IS NOT NULL DO UPDATE SET "
                + "attendee_count=EXCLUDED.attendee_count, starts_at=EXCLUDED.starts_at,"
                + " status='live', last_verified_at=now();\n"
            )
    print(f"DONE rows={len(rows)} skipped={n_skip}")
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
