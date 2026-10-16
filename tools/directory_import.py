"""Import the BizLinq Florida Networking Directory PDF into meetings rows.

Reads /Users/joshclark/Downloads/BizLinq_Florida_Networking_Directory_Rebuilt.pdf,
parses the 539 records, generates upcoming occurrences from their schedules,
geocodes venues, and writes a SQL seed file. Weekly patterns get
recurrence='weekly' so the Monday sync rolls them forward forever.

Skips (reported, not imported): undated/unconfirmed schedules, past dates,
historical/404 leads, and pure company-recruiting presentations.

Usage: python3 tools/directory_import.py  (writes tools/seed_directory.sql)
"""
import calendar
import re
import sys
from datetime import date, datetime, timedelta

sys.path.insert(0, "tools")
from meetup_import import (  # noqa: E402
    geocode, sql_str, load_cache, in_state, plain,
    categorize, tokens, EXCLUDE_TOKENS, PHRASE_EXCLUDE, CITY_STATE,
)

PDF = "/Users/joshclark/Downloads/BizLinq_Florida_Networking_Directory_Rebuilt.pdf"
OUT = "tools/seed_directory.sql"

WEEKDAYS = {
    "monday": 0, "mon": 0, "tuesday": 1, "tue": 1, "tues": 1,
    "wednesday": 2, "wed": 2, "thursday": 3, "thu": 3, "thur": 3, "thurs": 3,
    "friday": 4, "fri": 4, "saturday": 5, "sat": 5, "sunday": 6, "sun": 6,
}
ORDINAL = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
           "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5}
MONTHS = {m.lower(): i + 1 for i, m in enumerate(
    ["January", "February", "March", "April", "May", "June", "July",
     "August", "September", "October", "November", "December"])}
MONTHS.update({m[:3]: i for m, i in MONTHS.items()})

PURPOSE_CATEGORY = [
    (("real estate", "realtor", "property", "rei "), "Real Estate Meetings"),
    (("tech", "software", "developer", "coding", "data", "cyber", "ai "), "Technology Meetings"),
    (("founder", "startup", "entrepreneur", "pitch"), "Business Networking"),
    (("market", "sales", "mlm", "multi-level", "branding"), "Business Networking"),
    (("referral", "network", "chamber", "business", "professional", "executive",
      "leadership", "finance", "invest", "women", "career", "young professional",
      "summit", "expo", "conference", "mixer", "entrepreneur"), "Business Networking"),
]

SKIP_PURPOSE = ("company introduction", "company presentation")


def is_excluded(title, group):
    toks = tokens(title) | tokens(group)
    if not toks.isdisjoint(EXCLUDE_TOKENS):
        return True
    blob = (title + " " + group).lower()
    if any(s in blob for s in ("adventure", "hiking", "yoga", "singles", "dating",
                               "church", "casino", "pubcrawl", "barcrawl", "nightclub")):
        return True
    return any(p in blob for p in PHRASE_EXCLUDE)


def parse_time_token(tok):
    tok = tok.strip().lower().replace(".", "")
    if tok == "noon":
        return (12, 0, "pm")
    m = re.match(r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)?", tok)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2) or 0), m.group(3))


def to_24(hour, minute, meridiem):
    if meridiem == "pm" and hour != 12:
        hour += 12
    if meridiem == "am" and hour == 12:
        hour = 0
    return hour, minute


def parse_start_time(text):
    """First start time found in a schedule string -> (hour, minute)."""
    text = text.lower().replace("–", "-").replace("—", "-")
    m = re.search(r"(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*(?:-|to)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm))", text)
    if m:
        end = parse_time_token(m.group(2))
        start = parse_time_token(m.group(1))
        if start and end:
            mer = start[2] or end[2] or "am"
            return to_24(start[0], start[1], mer)
    m = re.search(r"(\d{1,2}(?::\d{2})?\s*(?:am|pm))", text)
    if m:
        start = parse_time_token(m.group(1))
        if start:
            return to_24(start[0], start[1], start[2] or "am")
    return None


def eastern_offset(dt):
    # EDT (-04:00) before Nov 1 2026, EST (-05:00) after. Good through 2027.
    return "-04:00" if dt < datetime(2026, 11, 1) else "-05:00"


def central_offset(dt):
    return "-05:00" if dt < datetime(2026, 11, 1) else "-06:00"


def iso(dt, central=False):
    off = central_offset(dt) if central else eastern_offset(dt)
    return dt.strftime("%Y-%m-%dT%H:%M:%S") + off


def nth_weekday(year, month, weekday, n):
    days = [w[weekday] for w in calendar.monthcalendar(year, month) if w[weekday] != 0]
    return date(year, month, days[n - 1]) if n <= len(days) else None


def upcoming_weekday(weekday, hour, minute, today, count):
    out = []
    d = today
    while len(out) < count and (d - today).days < 90:
        if d.weekday() == weekday and d >= today:
            out.append(datetime(d.year, d.month, d.day, hour, minute))
        d += timedelta(days=1)
    return out


def upcoming_nth(pattern_ns, weekday, hour, minute, today, count):
    out, y, m = [], today.year, today.month
    while len(out) < count and (date(y, m, 1) - today).days < 400:
        for n in pattern_ns:
            d = nth_weekday(y, m, weekday, n)
            if d and d >= today:
                out.append(datetime(d.year, d.month, d.day, hour, minute))
                if len(out) == count:
                    break
        m += 1
        if m > 12:
            m, y = 1, y + 1
    return sorted(out)


def parse_explicit_dates(text, today):
    out = []
    for m in re.finditer(r"(January|February|March|April|May|June|July|August|September|October|November|December|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)\s+(\d{1,2}),?\s+(\d{4})", text, re.I):
        try:
            d = date(int(m.group(3)), MONTHS[m.group(1).lower()], int(m.group(2)))
        except ValueError:
            continue
        t = parse_start_time(text)
        hh, mm = t if t else (9, 0)
        if d >= today:
            out.append(datetime(d.year, d.month, d.day, hh, mm))
    return sorted(set(out))


def schedule_occurrences(schedule, today):
    """Returns (occurrences, recurrence) or (None, skip_reason)."""
    slow = schedule.lower()
    if any(k in slow for k in ("coming soon", "not published", "requires confirmation",
                               "time varies", "conflicting", "tbd", "to be announced")):
        return None, "unconfirmed schedule"
    if any(k in slow for k in ("historical", "404", "no longer", "discontinued", "closed")):
        return None, "historical/closed"
    central = "central" in slow and "central florida" not in slow
    every_other = "every other week" in slow or slow.startswith("biweekly")
    nth_ns, weekday, t = [], None, parse_start_time(schedule)
    for wname, wnum in WEEKDAYS.items():
        if re.search(r"\b" + wname + r"s?\b", slow):
            weekday = wnum
            break
    for oname, onum in ORDINAL.items():
        if re.search(r"\b" + oname + r"\b", slow):
            nth_ns.append(onum)
    nth_ns = sorted(set(nth_ns))
    if t is None:
        dated = parse_explicit_dates(schedule, today)
        if dated:
            return [(d, None) for d in dated], None
        return None, "no parseable time"
    hh, mm = t
    if every_other:
        anchors = parse_explicit_dates(schedule, date(2000, 1, 1))
        if not anchors:
            return None, "biweekly without anchor"
        anchor = max(a for a in anchors if a.date() <= today + timedelta(days=60))
        out = []
        d = anchor
        while len(out) < 4:
            if d.date() >= today:
                out.append(d)
            d += timedelta(days=14)
        return [(d, None) for d in out], None
    if nth_ns and weekday is not None:
        return [(d, None) for d in upcoming_nth(nth_ns, weekday, hh, mm, today, 4)], None
    if "month" in slow and weekday is None:
        return None, "monthly without weekday"
    if weekday is not None:
        return [(d, "weekly") for d in upcoming_weekday(weekday, hh, mm, today, 4)], "weekly"
    dated = parse_explicit_dates(schedule, today)
    if dated:
        return [(d, None) for d in dated], None
    return None, "no parseable pattern"


def map_category(purpose, title, group):
    hay = f"{purpose} {title} {group}".lower()
    for keys, cat in PURPOSE_CATEGORY:
        if any(k in hay for k in keys):
            return cat
    return "Business Networking"


def split_records(full):
    lines = full.split("\n")
    records, cur = [], []
    for line in lines:
        s = line.strip()
        if re.match(r"^\d{3} .+", s) and len(s) > 8:
            if cur:
                records.append(cur)
            cur = [s]
        elif cur is not None and s:
            if s.startswith("BizLinq | Updated") or re.match(r"^\d{1,3}$", s):
                continue
            cur.append(s)
    if cur:
        records.append(cur)
    return ["\n".join(r) for r in records]


def parse_record(block):
    m = re.match(r"^(\d{3}) (.+)$", block.split("\n")[0].strip())
    if not m:
        return None
    rec_id, title = m.group(1), m.group(2).strip()
    fields = {"id": rec_id, "title": title, "format": "", "purpose": "",
              "location": "", "meets": "", "cost": "", "contact": "",
              "host": "", "review": "", "sources": ""}
    current = None
    for line in block.split("\n")[1:]:
        s = line.strip()
        for key in ("Location:", "Meets:", "Cost:", "Contact:", "Host:",
                    "Review:", "Source:", "Sources:"):
            if s.startswith(key):
                current = "sources" if key == "Source:" else key.rstrip(":").lower()
                s = s[len(key):].strip()
                break
        else:
            if current and s:
                fields[current] = (fields[current] + " " + s).strip()
                continue
        if current and s:
            fields[current] = s if not fields[current] else fields[current]
    fmt = fields["format"]
    if "|" in fields.get("title", ""):
        pass
    # First line after title may be "In person | purpose"
    for line in block.split("\n")[1:4]:
        s = line.strip()
        if "|" in s and not s.startswith(("Location", "Meets", "Cost")):
            parts = [p.strip() for p in s.split("|")]
            fields["format"] = parts[0]
            if len(parts) > 1:
                fields["purpose"] = parts[1]
            break
    return fields


def main():
    from pypdf import PdfReader
    print("reading PDF (pip install pypdf if missing)...")
    r = PdfReader("/Users/joshclark/Downloads/BizLinq_Florida_Networking_Directory_Rebuilt.pdf")
    full = "\n".join([(p.extract_text() or "") for p in r.pages])
    records = split_records(full)
    print(f"records found: {len(records)}")
    cache = load_cache()
    today = date(2026, 10, 14)
    rows, stats = [], {"imported": 0, "skipped": {}}

    def skip(reason):
        stats["skipped"][reason] = stats["skipped"].get(reason, 0) + 1

    for block in records:
        f = parse_record(block)
        if not f:
            skip("unparseable")
            continue
        purpose = f["purpose"].lower()
        if any(k in purpose for k in SKIP_PURPOSE):
            skip("company presentation")
            continue
        if is_excluded(f["title"], ""):
            skip("excluded content")
            continue
        if "crema" in f["title"].lower():
            skip("already live (curated)")
            continue
        occ, recurrence = schedule_occurrences(f["meets"], today) if f["meets"] else (None, None)
        if not occ:
            skip(f"schedule: {recurrence}")
            continue
        is_virtual = f["format"].lower().startswith("virtual")
        loc = f["location"]
        vm = re.search(r"([^,]+),\s*FL\s*(\d{5})?", loc)
        city = vm.group(1).split(";")[-1].strip() if vm else ""
        city = re.sub(r"^.*;\s*", "", city).strip()
        zm = re.search(r"\bFL\s*(\d{5})\b", loc)
        zipc = zm.group(1) if zm else ""
        venue = loc.split(";")[0].strip()
        lat = lon = None
        central = "central" in f["meets"].lower() and "central florida" not in f["meets"].lower()
        for dt, _rec in occ:
            starts_at = iso(dt, central)
            if lat is None:
                g = geocode(loc if loc else f"{city}, FL", cache)
                if g and in_state(g["lat"], g["lon"], "FL"):
                    lat, lon = g["lat"], g["lon"]
                    zipc = zipc or g.get("zip") or ""
                if lat is None and city:
                    g = geocode(f"{city}, FL", cache)
                    if g and in_state(g["lat"], g["lon"], "FL"):
                        lat, lon = g["lat"], g["lon"]
                        zipc = zipc or g.get("zip") or ""
            if lat is None:
                skip("unlocatable")
                break
            contact = f["contact"] or f["host"]
            desc = (f["review"] + " " if f["review"] else "") + (f"Cost: {f['cost']}. " if f["cost"] else "")
            if contact:
                desc += f"Contact: {contact}. "
            desc += "Please confirm schedule with the organizer before attending."
            tagline = desc[:140].rsplit(" ", 1)[0] if len(desc) > 140 else desc
            rows.append({
                "title": f["title"][:140],
                "group": f["title"][:120],
                "category": map_category(f["purpose"], f["title"], ""),
                "tagline": tagline,
                "description": (desc + f" More info: BizLinq Florida Directory record {f['id']}.")[:900],
                "starts_at": starts_at,
                "venue": venue or ("Online" if is_virtual else "To be announced"),
                "address": loc[:200],
                "city": city or "Orlando", "state": "FL", "zip": zipc,
                "lat": lat, "lon": lon,
                "host": f["host"] or f["title"][:120],
                "count": 0,
                "cost": "Free" if f["cost"].lower().startswith("free") else (f["cost"][:60] or "See organizer"),
                "virtual": is_virtual,
                "url": f"bizlinq-directory:REC-{f['id']}@{starts_at[:10]}",
                "recurrence": recurrence,
            })
            stats["imported"] += 1

    with open("tools/seed_directory.sql", "w") as fh:
        fh.write("-- Florida Directory import (organizer research, Oct 2026). Review, then apply.\n")
        for r in rows:
            fh.write(
                "INSERT INTO public.meetings (title, group_name, category, tagline, description, starts_at,"
                " venue, address, city, state, zip_code, latitude, longitude, host_name, attendee_count,"
                " is_virtual, cost_description, status, source, source_url, recurrence, last_verified_at) VALUES ("
                + ", ".join([
                    sql_str(r["title"]), sql_str(r["group"]), sql_str(r["category"]),
                    sql_str(r["tagline"]), sql_str(r["description"]), sql_str(r["starts_at"]),
                    sql_str(r["venue"]), sql_str(r["address"]), sql_str(r["city"]), sql_str(r["state"]),
                    sql_str(r["zip"]), str(r["lat"]), str(r["lon"]), sql_str(r["host"]),
                    str(r["count"]), "true" if r["virtual"] else "false", sql_str(r["cost"]),
                    "'live'", "'directory'", sql_str(r["url"]),
                    sql_str(r["recurrence"]) if r["recurrence"] else "NULL", "now()",
                ])
                + ") ON CONFLICT (source_url) WHERE source_url IS NOT NULL DO UPDATE SET "
                + "attendee_count=EXCLUDED.attendee_count, starts_at=EXCLUDED.starts_at,"
                + " status='live', last_verified_at=now();\n"
            )
    print(f"DONE rows={len(rows)}")
    print("skipped:", dict(sorted(stats["skipped"].items(), key=lambda x: -x[1])))
    print("wrote tools/seed_directory.sql")


SKIP_PURPOSE = ("company introduction", "company presentation")


if __name__ == "__main__":
    main()
