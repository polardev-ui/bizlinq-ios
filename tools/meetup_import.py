"""Import networking events from public Meetup group pages into Supabase.

Reads candidate group URLs, fetches each page politely, extracts the embedded
NEXT_DATA event feed, geocodes venues (US Census, cached), and writes a
parameter-safe SQL seed file for review + apply. Facts only (title, time,
venue, RSVPs) with source links back to every event.

Usage:
  python3 tools/meetup_import.py --in /tmp/mu-cands.pkl --limit 100 --offset 0 \\
      --out tools/seed_meetings_01.sql --groups-out tools/seed_groups_01.sql
"""
import argparse
import html
import json
import os
import pickle
import re
import sys
import time
import urllib.request

UA = "BizLinq-Curator/1.0 (+https://bizlinq.app/support)"
DELAY = 1.5
CACHE = os.path.join(os.path.dirname(__file__), "geocode_cache.json")

METROS = [
    "new-york", "nyc", "los-angeles", "chicago", "houston", "miami",
    "atlanta", "dallas", "austin", "denver", "boulder", "seattle",
    "boston", "san-francisco", "sf", "san-jose", "phoenix", "nashville",
    "charlotte", "raleigh", "durham", "tampa", "orlando", "portland",
    "las-vegas", "vegas", "minneapolis", "st-louis", "kansas-city",
    "detroit", "philadelphia", "philly", "pittsburgh", "baltimore",
    "washington", "dc", "san-diego", "sacramento", "salt-lake", "columbus",
    "cleveland", "cincinnati", "indianapolis", "milwaukee", "memphis",
    "louisville", "new-orleans", "birmingham", "jacksonville", "richmond",
    "hartford", "providence", "albany", "buffalo", "albuquerque", "tucson",
    "honolulu", "omaha", "des-moines", "oklahoma", "tulsa", "little-rock",
    "charleston", "knoxville", "lexington", "grand-rapids", "reno", "boise",
    "fresno", "spokane", "tacoma", "anchorage", "fresno", "bakersfield",
    "fresno", "santa-monica", "orange-county", "silicon-valley",
    "raleigh-durham", "triangle", "twin-cities", "bay-area",
]

TOPIC_CATEGORY = [
    (("real estate", "real-estate", "realtor", "property"), "Real Estate & Investing"),
    (("founder", "startup", "entrepreneur", "pitch", "venture"), "Business Networking"),
    (("tech", "software", "developer", "coding", "data science", "ai ", "artificial intelligence", "cyber"), "Technology & Innovation"),
    (("market", "sales", "seo", "social media", "advertising", "branding", "mlm", "multi-level"), "Business Networking"),
    (("finance", "invest", "stock", "crypto", "trading", "wealth", "women", "career", "young professional", "millennial", "job"), "Business & Professional Networking"),
]

# Slug/name tokens that mark a group as social-not-professional. Whole-token
# match only, so "artstechsf" (one token) survives while "art-and-culture" goes.
EXCLUDE_TOKENS = {
    "travel", "traveling", "travelling", "adventure", "vacation", "tourism",
    "hiking", "hike", "outdoors", "camping", "kayak", "ski", "snowboard",
    "surf", "climb", "cycling", "bike", "running", "marathon", "dining",
    "foodie", "restaurant", "wine", "beer", "whiskey", "singles", "dating",
    "relationship", "moms", "dads", "parenting", "baby", "kids", "book",
    "books", "bookclub", "movies", "film", "films", "sports", "soccer",
    "basketball", "football", "baseball", "tennis", "fitness", "gym",
    "yoga", "pilates", "dance", "salsa", "music", "concert", "gaming",
    "gamers", "dogs", "cats", "pets", "church", "bible", "hikers",
    "volleyball", "softball", "pickleball", "golf", "bowling", "swimming",
    "cricket", "rugby", "surfing", "bird", "birds", "audubon",
    "wildlife", "meditation", "mindfulness", "spiritual",
    "crokinole", "boardgame", "board-game", "chess", "poker", "trivia",
    "karaoke", "board", "shaman", "reiki", "breathwork", "cacao",
    "tarot", "astrology", "psychic",
    "martial", "karate", "kungfu", "jitsu", "judo", "taekwondo",
    "aikido", "muay", "kickbox", "kickboxing", "boxing", "wrestling",
    "fencing", "eskrima", "kali", "arnis", "qigong", "taiji",
    "taichi", "krav", "maga", "samurai", "ninja", "dojo",
    "english", "esl", "tutoring", "homework", "math", "algebra",
    "piano", "guitar", "violin", "drums", "cooking", "baking",
    "knitting", "sewing", "gardening", "photowalk",
}

PHRASE_EXCLUDE = {
    "language exchange", "learn english", "learn spanish", "english class",
    "spanish class", "conversation club", "drum circle", "sound bath",
    "make friends", "new friends", "meet friends",
    "martial arts", "tai chi", "qi gong", "chi kung", "filipino martial",
}


def tokens(text):
    return set(re.split(r"[^a-z0-9]+", (text or "").lower()))


def is_excluded(slug, name):
    toks = tokens(slug) | tokens(name)
    if not toks.isdisjoint(EXCLUDE_TOKENS):
        return True
    blob = slug.lower() + " " + name.lower()
    if any(s in blob for s in (
        "adventure", "hiking", "yoga", "singles", "dating", "church",
        "casino", "pubcrawl", "barcrawl", "nightclub",
    )):
        return True
    return any(p in blob for p in PHRASE_EXCLUDE)


def categorize(topics, title, group_name=""):
    """Title-first categorization with whole-phrase matching.

    Fixes the old bug where a broad group topic (e.g. a generic networking
    group tagged "Real Estate" on Meetup) forced every event to
    "Real Estate Meetings" — e.g. "Monday Multipliers" by
    Profitable Networking Philadelphia. Real Estate now requires an
    explicit RE phrase in the title or group name; group topics only apply
    when the title itself is generic.
    """
    import re as _re
    title_l = (title or "").lower()
    group_l = (group_name or "").lower()
    topics_l = (" ".join(topics or [])).lower()
    tg = f"{title_l} {group_l}"

    RE_PATTERNS = [
        r"real[ -]?estate", r"realtor", r"realty", r"\breia?\b",
        r"multifamily", r"multi[ -]?family", r"apartment", r"landlord",
        r"house[ -]?flip", r"fix[ -]?and[ -]?flip", r"fix\s*&\s*flip",
        r"buy[ -]?and[ -]?hold", r"buy\s*&\s*hold", r"foreclosure",
        r"wholesal", r"rental", r"commercial[ -]?real", r"\bcre\b",
        r"airbnb", r"tax[ -]?lien", r"tax[ -]?deed", r"house[ -]?hack",
        r"cashflow| cash[ -]?flow.{0,20}rei|rei.{0,20}cash[ -]?flow",
        r"note[ -]?invest", r"short[ -]?term[ -]?rental",
    ]
    TECH_PATTERNS = [
        r"\bai\b", r"artificial intelligence", r"machine learning",
        r"\bml\b", r"deeptech", r"tech", r"software", r"developer",
        r"coding", r"data science", r"cyber", r"saas", r"cloud",
        r"blockchain", r"biotech", r"fintech",
    ]
    STARTUP_PATTERNS = [
        r"founder", r"startup", r"entrepreneur", r"\bpitch\b", r"venture",
    ]
    MARKETING_PATTERNS = [
        r"mlm", r"multi[ -]?level", r"\bseo\b", r"social media",
        r"advertising", r"branding", r"linkedin", r"content creator",
        r"sales", r"marketing",
    ]

    def _any(patterns, text):
        return any(_re.search(p, text) for p in patterns)

    # 1. Explicit Real Estate in title or group always wins.
    if _any(RE_PATTERNS, tg):
        return "Real Estate & Investing"
    # 2. Title signals outrank group topics.
    # NOTE: startup/founder content merges into Business Networking (no separate tab).
    if _any(TECH_PATTERNS, title_l):
        return "Technology & Innovation"
    if _any(STARTUP_PATTERNS, title_l):
        return "Explore All Groups"
    if _any(MARKETING_PATTERNS, title_l):
        return "Explore All Groups"
    # 3. Group-name signals.
    if _any(TECH_PATTERNS, group_l):
        return "Technology & Innovation"
    if _any(STARTUP_PATTERNS, group_l):
        return "Explore All Groups"
    if _any(MARKETING_PATTERNS, group_l):
        return "Explore All Groups"
    # 4. Topics only as a last resort, and only for explicit RE.
    if _any(RE_PATTERNS, topics_l):
        return "Real Estate & Investing"
    for patterns, cat in (
        (TECH_PATTERNS, "Technology & Innovation"),
        (STARTUP_PATTERNS, "Business Networking"),
        (MARKETING_PATTERNS, "Network Marketing"),
    ):
        if _any(patterns, topics_l):
            return cat
    return "Explore All Groups"


def fetch(url, tries=3):
    last = None
    for _ in range(int(tries)):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except Exception as e:
            last = e
            time.sleep(3)
    raise last


def extract_next_data(html_text):
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html_text, re.S)
    return json.loads(m.group(1)) if m else None


def walk(node):
    if isinstance(node, dict):
        yield node
        for v in node.values():
            yield from walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from walk(v)


def plain(text, limit):
    text = re.sub(r"<[^>]+>", " ", text or "")
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:limit].rsplit(" ", 1)[0] if len(text) > limit else text


def load_cache():
    try:
        return json.load(open(CACHE))
    except Exception:
        return {}


def save_cache(cache):
    json.dump(cache, open(CACHE, "w"))


def geocode(address, cache):
    if address in cache:
        return cache[address]
    import urllib.parse
    q = urllib.parse.urlencode({
        "address": address,
        "benchmark": "Public_AR_Current",
        "format": "json",
    })
    try:
        req = urllib.request.Request(
            "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress?" + q,
            headers={"User-Agent": UA},
        )
        with urllib.request.urlopen(req, timeout=20) as r:
            d = json.load(r)
        matches = d.get("result", {}).get("addressMatches", [])
        if matches:
            m = matches[0]
            out = {
                "lat": m["coordinates"]["y"],
                "lon": m["coordinates"]["x"],
                "zip": m["addressComponents"].get("zip"),
            }
            cache[address] = out
            save_cache(cache)
            time.sleep(1.2)
            return out
    except Exception as e:
        print(f"    geocode miss: {address[:60]} ({e})")
    cache[address] = None
    save_cache(cache)
    time.sleep(1.2)
    return None


STATE_BBOX = {
"AL": (30.1, 35.0, -88.5, -84.9), "AK": (51.0, 71.5, -180.0, -129.0),
"AZ": (31.3, 37.0, -114.9, -109.0), "AR": (33.0, 36.5, -94.7, -89.6),
"CA": (32.5, 42.0, -124.5, -114.0), "CO": (37.0, 41.0, -109.1, -102.0),
"CT": (40.9, 42.1, -73.8, -71.8), "DE": (38.4, 39.9, -75.8, -75.0),
"FL": (24.4, 31.1, -87.7, -79.9), "GA": (30.2, 35.0, -85.7, -80.8),
"HI": (18.9, 22.3, -160.3, -154.8), "ID": (42.0, 49.0, -117.3, -111.0),
"IL": (36.9, 42.6, -91.6, -87.4), "IN": (37.7, 41.8, -88.2, -84.7),
"IA": (40.3, 43.6, -96.5, -90.1), "KS": (36.9, 40.1, -102.1, -94.6),
"KY": (36.5, 39.2, -89.6, -81.9), "LA": (28.8, 33.1, -94.1, -88.8),
"ME": (42.9, 47.5, -71.1, -66.9), "MD": (37.9, 39.8, -79.5, -75.0),
"MA": (41.2, 42.9, -73.5, -69.9), "MI": (41.7, 48.3, -90.5, -82.3),
"MN": (43.4, 49.4, -97.3, -89.5), "MS": (30.1, 35.0, -91.7, -88.0),
"MO": (35.9, 40.7, -95.8, -89.0), "MT": (44.3, 49.0, -116.1, -104.0),
"NE": (39.9, 43.0, -104.1, -95.3), "NV": (34.9, 42.0, -120.0, -114.0),
"NH": (42.7, 45.4, -72.6, -70.6), "NJ": (38.8, 41.4, -75.7, -73.9),
"NM": (31.3, 37.0, -109.1, -103.0), "NY": (40.4, 45.1, -79.9, -71.7),
"NC": (33.7, 36.7, -84.4, -75.4), "ND": (45.9, 49.0, -104.1, -96.8),
"OH": (38.4, 42.0, -84.9, -80.5), "OK": (33.6, 37.0, -103.0, -94.4),
"OR": (41.9, 46.3, -124.6, -116.9), "PA": (39.7, 42.3, -80.6, -74.6),
"RI": (41.1, 42.1, -71.9, -71.1), "SC": (32.0, 35.3, -83.4, -78.5),
"SD": (42.4, 45.9, -104.1, -96.4), "TN": (34.9, 36.7, -90.4, -81.6),
"TX": (25.8, 36.6, -106.5, -93.4), "UT": (36.9, 42.0, -114.1, -109.0),
"VT": (42.7, 45.1, -73.5, -71.4), "VA": (36.5, 39.5, -83.7, -75.2),
"WA": (45.5, 49.0, -124.8, -116.9), "WV": (37.1, 39.8, -82.7, -77.7),
"WI": (42.4, 47.1, -92.9, -86.9), "WY": (40.9, 45.0, -111.1, -104.0),
"DC": (38.8, 39.0, -77.2, -76.9),
}

CITY_STATE = {
"Waterford Lakes": "FL", "Winter Garden": "FL", "Apopka": "FL",
"Ocoee": "FL", "Windermere": "FL", "Oviedo": "FL", "Winter Springs": "FL",
"Altamonte Springs": "FL", "Casselberry": "FL", "Longwood": "FL",
"Winter Park": "FL", "Lake Mary": "FL", "Heathrow": "FL",
"Sanford": "FL", "Deltona": "FL", "Orange City": "FL", "Lake Helen": "FL",
"DeBary": "FL", "DeLand": "FL", "New Smyrna Beach": "FL", "Edgewood": "FL",
"Clermont": "FL", "Celebration": "FL", "Davenport": "FL",
"Haines City": "FL", "St. Cloud": "FL", "Titusville": "FL", "Cocoa": "FL",
"Cocoa Beach": "FL", "Melbourne": "FL", "Palm Bay": "FL",
"Daytona Beach": "FL", "Ormond Beach": "FL", "Palm Coast": "FL",
"Flagler Beach": "FL", "Ocala": "FL", "Leesburg": "FL", "Tavares": "FL",
"Eustis": "FL", "Mount Dora": "FL", "Wildwood": "FL", "Groveland": "FL",
"Minneola": "FL", "Lake Buena Vista": "FL", "Bay Lake": "FL",
"Gotha": "FL", "Oakland": "FL", "Montverde": "FL", "Alafaya": "FL",
"Bithlo": "FL", "Christmas": "FL", "Chuluota": "FL", "Geneva": "FL",
"Union Park": "FL", "Azalea Park": "FL", "Pine Hills": "FL",
"Lockhart": "FL", "Fairview Shores": "FL", "Eatonville": "FL",
"Belle Isle": "FL", "Doctor Phillips": "FL", "Hunters Creek": "FL",
"Southchase": "FL", "Taft": "FL", "Pine Castle": "FL", "Sky Lake": "FL",
"Oak Ridge": "FL", "Williamsburg": "FL", "Narcoossee": "FL",
"Moss Park": "FL", "Wedgefield": "FL", "Bay Hill": "FL",
"Lake Nona": "FL", "Avalon Park": "FL", "Stoneybrook": "FL",
"Lake Hart": "FL", "Heathrow": "FL", "Geneva": "FL",
"Orlando": "FL", "Tampa": "FL", "Miami": "FL", "Fort Lauderdale": "FL",
"Jacksonville": "FL", "Winter Park": "FL", "Lake Mary": "FL", "Kissimmee": "FL",
"Sanford": "FL", "Altamonte Springs": "FL", "Oviedo": "FL", "Maitland": "FL",
"St. Petersburg": "FL", "Clearwater": "FL", "Sarasota": "FL", "Naples": "FL",
"Fort Myers": "FL", "West Palm Beach": "FL", "Boca Raton": "FL",
"Tallahassee": "FL", "Gainesville": "FL", "Pensacola": "FL",
"Daytona Beach": "FL", "Melbourne": "FL", "Delray Beach": "FL",
"New York": "NY", "Brooklyn": "NY", "Queens": "NY", "Albany": "NY",
"Buffalo": "NY", "Rochester": "NY", "Los Angeles": "CA", "San Francisco": "CA",
"San Jose": "CA", "San Diego": "CA", "Sacramento": "CA", "Oakland": "CA",
"Long Beach": "CA", "Fresno": "CA", "Bakersfield": "CA", "Santa Monica": "CA",
"Chicago": "IL", "Houston": "TX", "Dallas": "TX", "Austin": "TX",
"Fort Worth": "TX", "Arlington": "TX", "Plano": "TX", "Irving": "TX",
"El Paso": "TX", "San Antonio": "TX", "Denver": "CO", "Boulder": "CO",
"Seattle": "WA", "Tacoma": "WA", "Spokane": "WA", "Bellevue": "WA",
"Boston": "MA", "Cambridge": "MA", "Phoenix": "AZ", "Tucson": "AZ",
"Scottsdale": "AZ", "Nashville": "TN", "Memphis": "TN", "Knoxville": "TN",
"Charlotte": "NC", "Raleigh": "NC", "Durham": "NC", "Portland": "OR",
"Las Vegas": "NV", "Reno": "NV", "Minneapolis": "MN", "Saint Paul": "MN",
"St. Louis": "MO", "Kansas City": "MO", "Detroit": "MI", "Grand Rapids": "MI",
"Philadelphia": "PA", "Pittsburgh": "PA", "Baltimore": "MD",
"Washington": "DC", "Salt Lake City": "UT", "Columbus": "OH",
"Cleveland": "OH", "Cincinnati": "OH", "Indianapolis": "IN",
"Milwaukee": "WI", "Louisville": "KY", "Lexington": "KY",
"New Orleans": "LA", "Birmingham": "AL", "Richmond": "VA",
"Arlington": "VA", "Hartford": "CT", "Stamford": "CT", "Providence": "RI",
"Albuquerque": "NM", "Honolulu": "HI", "Omaha": "NE", "Des Moines": "IA",
"Oklahoma City": "OK", "Tulsa": "OK", "Little Rock": "AR",
"Charleston": "SC", "Columbia": "SC", "Atlanta": "GA", "Newark": "NJ",
"Jersey City": "NJ", "Hoboken": "NJ", "Boise": "ID", "Anchorage": "AK",
"Portland": "ME", "Burlington": "VT", "Manchester": "NH",
"Wilmington": "DE", "Cheyenne": "WY", "Billings": "MT", "Fargo": "ND",
"Sioux Falls": "SD", "Portland": "OR", "Vancouver": "WA",
}


def in_state(lat, lon, state):
    box = STATE_BBOX.get(state)
    if not box:
        return False
    lo_la, hi_la, lo_lo, hi_lo = box
    return lo_la <= lat <= hi_la and lo_lo <= lon <= hi_lo


def sql_str(s):
    if s is None:
        return "NULL"
    return "'" + str(s).replace("'", "''") + "'"


def parse_group(url, cache):
    slug = url.rstrip("/").split("/")[-1]
    data = extract_next_data(fetch(url))
    if not data:
        return None, "no-next-data"
    venues = {}
    topics_by_id = {}
    group = None
    events = []
    for node in walk(data):
        if not isinstance(node, dict):
            continue
        t = node.get("__typename")
        if t == "Venue" and "id" in node:
            venues[str(node["id"])] = node
        elif t == "Topic" and "id" in node and node.get("name"):
            topics_by_id[str(node["id"])] = node["name"]
        elif t == "Group" and group is None and node.get("name"):
            group = node
        elif t == "Event" and node.get("status") == "ACTIVE" and node.get("dateTime"):
            events.append(node)
    if group is None:
        return None, "no-group"
    topics = []
    for t in group.get("activeTopics", []) or []:
        if isinstance(t, dict) and t.get("name"):
            topics.append(t["name"])
        elif isinstance(t, dict) and str(t.get("__ref", "")).startswith("Topic:"):
            name = topics_by_id.get(str(t["__ref"]).split(":", 1)[1])
            if name:
                topics.append(name)
    out_events = []
    for e in events:
        venue = None
        vref = (e.get("venue") or {}).get("__ref", "")
        if vref.startswith("Venue:"):
            venue = venues.get(vref.split(":", 1)[1])
        going = (e.get("going") or {}).get("totalCount", 0) or 0
        fee = e.get("feeSettings") or {}
        amount = fee.get("amount") or 0
        out_events.append({
            "id": str(e.get("id")),
            "title": plain(e.get("title", ""), 140),
            "description": plain(e.get("description", ""), 500),
            "starts_at": e.get("dateTime"),
            "url": e.get("eventUrl") or f"https://www.meetup.com/{slug}/events/{e.get('id')}/",
            "is_online": bool(e.get("isOnline")),
            "going": going,
            "cost": f"${amount:g}" if amount else "Free",
            "venue": venue,
        })
    return {
        "slug": slug,
        "name": plain(group.get("name", slug), 120),
        "city": group.get("city") or "",
        "lat": group.get("lat"),
        "lon": group.get("lon"),
        "topics": topics,
        "events": out_events,
    }, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--limit", type=int, default=100)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--metro-only", action="store_true")
    ap.add_argument("--out", required=True)
    ap.add_argument("--groups-out", required=True)
    ap.add_argument("--states", default="",
                    help="Comma-separated state codes; drop rows outside them (e.g. FL)")
    args = ap.parse_args()

    cands = pickle.load(open(args.inp, "rb"))
    if args.metro_only:
        cands = [u for u in cands if any(m in u for m in METROS)]
        print(f"metro-filtered candidates: {len(cands)}")
    batch = cands[args.offset:args.offset + args.limit]
    skipped_social = 0
    pre = []
    for u in batch:
        slug = u.rstrip("/").split("/")[-1]
        if tokens(slug) & EXCLUDE_TOKENS:
            skipped_social += 1
            continue
        pre.append(u)
    print(f"processing {len(pre)} groups (offset {args.offset}, skipped {skipped_social} social)")
    batch = pre

    cache = load_cache()
    rows, group_rows, stats = [], [], {"ok": 0, "empty": 0, "failed": 0, "non_us": 0}
    for i, url in enumerate(batch):
        try:
            parsed, err = parse_group(url, cache)
            time.sleep(DELAY)
            if not parsed:
                stats["failed"] += 1
                continue
            upcoming = [e for e in parsed["events"] if e["starts_at"]]
            if not upcoming:
                stats["empty"] += 1
                continue
            stats["ok"] += 1
            if is_excluded(parsed["slug"], parsed["name"]):
                stats["empty"] += 1
                continue
            category_fallback = categorize(parsed["topics"], "", parsed["name"])
            EVENT_EXCLUDE = EXCLUDE_TOKENS | {
                "trip", "trips", "vacation", "cruise", "bingo", "wedding",
                "birthday", "showers", "hike", "hikes", "yoga", "dating",
            }
            for e in upcoming:
                if tokens(e["title"]) & EVENT_EXCLUDE:
                    continue
                venue = e["venue"] or {}
                address = venue.get("address", "")
                city = venue.get("city") or parsed["city"]
                state = venue.get("state", "") or CITY_STATE.get(city, "")
                if not city or not state:
                    continue
                if args.states and state not in args.states.split(","):
                    continue
                m = re.search(r"\b(\d{5})(?:-\d{4})?\b", address)
                regex_zip = m.group(1) if m else ""
                zip_code = ""
                lat = lon = None
                if address and not e["is_online"]:
                    g = geocode(address, cache)
                    if g and in_state(g["lat"], g["lon"], state):
                        lat, lon = g["lat"], g["lon"]
                        # Census is authoritative: a street number can look like a ZIP.
                        zip_code = g.get("zip") or regex_zip
                if lat is None:
                    g = geocode(f"{city}, {state}", cache)
                    if g and in_state(g["lat"], g["lon"], state):
                        lat, lon = g["lat"], g["lon"]
                        zip_code = zip_code or g.get("zip") or regex_zip
                if lat is None and parsed["lat"] is not None and in_state(parsed["lat"], parsed["lon"] or 0, state):
                    lat, lon = parsed["lat"], parsed["lon"]
                if lat is None:
                    continue
                if lat is None or not city:
                    continue
                category = categorize(parsed["topics"], e["title"], parsed["name"]) if (parsed["topics"] or e["title"]) else category_fallback
                rows.append({
                    "title": e["title"] or parsed["name"],
                    "group": parsed["name"],
                    "category": category,
                    "tagline": (e["description"][:140].rsplit(" ", 1)[0] if e["description"] else f"Hosted by {parsed['name']}"),
                    "description": (e["description"] + f" More info: {e['url']}")[:900],
                    "starts_at": e["starts_at"],
                    "venue": venue.get("name") or ("Online" if e["is_online"] else "To be announced"),
                    "address": address or ("Online event" if e["is_online"] else ""),
                    "city": city, "state": state, "zip": zip_code,
                    "lat": lat, "lon": lon,
                    "host": parsed["name"],
                    "count": e["going"],
                    "cost": e["cost"],
                    "virtual": e["is_online"],
                    "url": e["url"],
                })
            group_rows.append((url, parsed["name"], parsed["city"], len(upcoming)))
            print(f"  [{i+1}] {parsed['slug']}: {len(upcoming)} events")
        except Exception as ex:
            stats["failed"] += 1
            print(f"  [{i+1}] FAIL {url}: {str(ex)[:100]}")
            time.sleep(DELAY)

    with open(args.out, "w") as f:
        f.write("-- Meetup curated import. Review, then apply via Supabase.\n")
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
                    "'live'", "'meetup'", sql_str(r["url"]), "now()",
                ])
                + ") ON CONFLICT (source_url) WHERE source_url IS NOT NULL DO UPDATE SET "
                + "attendee_count=EXCLUDED.attendee_count, starts_at=EXCLUDED.starts_at,"
                + " status='live', last_verified_at=now();\n"
            )
    with open(args.groups_out, "w") as f:
        f.write("-- Watchlist seed for the weekly sync.\n")
        for url, name, city, n in group_rows:
            f.write(
                "INSERT INTO public.source_groups (platform, group_url, group_name, metro, active, last_synced_at, last_event_count) VALUES ("
                + ", ".join(["'meetup'", sql_str(url), sql_str(name), sql_str(city), "true", "now()", str(n)])
                + ") ON CONFLICT (group_url) DO UPDATE SET last_synced_at=now(), last_event_count=EXCLUDED.last_event_count;\n"
            )
    print(f"DONE ok-groups={stats['ok']} empty={stats['empty']} failed={stats['failed']} rows={len(rows)}")
    print(f"wrote {args.out} + {args.groups_out}")


if __name__ == "__main__":
    main()
