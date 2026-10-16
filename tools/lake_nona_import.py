"""Lake Nona (32827 / 32832) meeting hunt — October 16, 2026.

Builds tools/seed_lake_nona.sql from three sources:
  1. Hand-verified listings: recurring groups and dated events checked on the
     organizer's own page on 2026-10-16 (URL cited on every row).
  2. Eventbrite / Meetup import output (tools/eventbrite_import.py and
     tools/meetup_import.py), filtered to RADIUS_MI of Lake Nona and to
     events not already in the database.
  3. More upcoming dates for weekly groups already listed near Lake Nona,
     appended in SQL so the daily roll-forward keeps them going.

Every insert is ON CONFLICT (source_url) DO NOTHING, so re-running is safe.

Usage:
  python3 tools/lake_nona_import.py --existing existing_urls.json \\
      --import eb.sql --import mu.sql --out tools/seed_lake_nona.sql --report report.csv
"""
import argparse
import csv
import json
import math
import re
import sys
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

sys.path.insert(0, "tools")
from meetup_import import geocode, load_cache, save_cache, sql_str  # noqa: E402

ET = ZoneInfo("America/New_York")
CENTER = (28.385, -81.265)  # between Lake Nona Town Center and Narcoossee Rd
RADIUS_MI = 15.0
CHECKED = "Oct 16, 2026"
NOW = datetime(2026, 10, 16, 20, 0, tzinfo=ET)

# Geocoder fallbacks for venues the Census geocoder may not resolve.
KNOWN = {
    "6820 Marwick Ln, Suite 100, Orlando, FL 32827": (28.3707, -81.2777, "32827"),
    "10002 Eagle Creek Sanctuary Blvd, Orlando, FL 32832": (28.4134, -81.2328, "32832"),
    "13495 Veterans Way, Orlando, FL 32827": (28.3702, -81.2766, "32827"),
    "7004 Tavistock Lakes Blvd, Suite 132, Orlando, FL 32827": (28.3720, -81.2720, "32827"),
    "9161 Narcoossee Rd, Suite 203, Orlando, FL 32827": (28.4240, -81.2470, "32827"),
    "9161 Narcoossee Rd, Orlando, FL 32832": (28.4240, -81.2470, "32832"),
    "6555 Sanger Rd, Orlando, FL 32827": (28.3683, -81.2840, "32827"),
    "7215 Corner Dr, Orlando, FL 32827": (28.3916, -81.3390, "32827"),
    "6877 Tavistock Lakes Blvd, Orlando, FL 32827": (28.3712, -81.2716, "32827"),
    "14219 Nona North Rd, Orlando, FL 32824": (28.3613, -81.3062, "32824"),
    "10000 USTA Blvd, Orlando, FL 32827": (28.3995, -81.2510, "32827"),
    "9685 Narcoossee Rd, Orlando, FL 32832": (28.4260, -81.2526, "32832"),
    "13052 Narcoossee Rd, Orlando, FL 32832": (28.3810, -81.2440, "32832"),
    "1200 New York Ave, St. Cloud, FL 34769": (28.2486, -81.2810, "34769"),
    "915 New York Ave, St. Cloud, FL 34769": (28.2545, -81.2810, "34769"),
    "14383 Narcoossee Rd, Orlando, FL 32832": (28.3720, -81.2440, "32832"),
    "Lake Nona, Orlando, FL 32827": (28.3713, -81.2716, "32827"),
}

rows = []
report = []


def miles(lat, lon):
    r = 3958.8
    p1, p2 = math.radians(CENTER[0]), math.radians(lat)
    dp, dl = p2 - p1, math.radians(lon - CENTER[1])
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def locate(address, cache):
    if address in KNOWN:
        return KNOWN[address]
    g = geocode(address, cache)
    if not g:
        raise ValueError(f"unlocatable: {address}")
    return g["lat"], g["lon"], g.get("zip") or ""


def add(*, title, group, category, about, when, venue, address, city, host, cost, url,
        unique_url=None, virtual=False, recurrence=None, schedule=None, cache=None):
    """One dated occurrence. `when` is a naive local (Eastern) datetime."""
    starts = when.replace(tzinfo=ET)
    if starts <= NOW:
        return
    if virtual:
        lat, lon, zipc = KNOWN["Lake Nona, Orlando, FL 32827"]
    else:
        lat, lon, zipc = locate(address, cache)
    tagline = about if len(about) <= 140 else about[:140].rsplit(" ", 1)[0]
    bits = [about]
    if schedule:
        bits.append(f"Schedule: {schedule}.")
    bits.append(f"Checked on the organizer's page {CHECKED}; confirm before attending. More info: {url}")
    rows.append({
        "title": title, "group": group, "category": category, "tagline": tagline,
        "description": " ".join(bits), "starts_at": starts.isoformat(), "venue": venue,
        "address": address, "city": city, "state": "FL", "zip": zipc, "lat": lat, "lon": lon,
        "host": host, "virtual": virtual, "cost": cost,
        "source_url": unique_url or f"{url}#{starts.date().isoformat()}",
        "recurrence": recurrence, "source": "curated",
    })


def nth_weekday(year, month, weekday, n):
    d = date(year, month, 1)
    d += timedelta(days=(weekday - d.weekday()) % 7)
    d += timedelta(weeks=n - 1)
    return d if d.month == month else None


def curated(cache):
    common = dict(cache=cache)

    # Lake Nona Toastmasters — weekly, Tuesdays 6:30 PM (toastmasters.org).
    tm = "https://www.toastmasters.org/Find-a-Club/00695848-lake-nona-toastmasters-club"
    d = datetime(2026, 10, 20, 18, 30)
    for _ in range(WEEKS_AHEAD):
        add(title="Lake Nona Toastmasters", group="Lake Nona Toastmasters Club", category="Business Networking",
            about="Weekly public-speaking and leadership practice for Lake Nona professionals. Guests are welcome to visit for free; online attendance is also offered.",
            when=d, venue="Northwestern Mutual Lake Nona (KPMG Building)",
            address="6820 Marwick Ln, Suite 100, Orlando, FL 32827", city="Orlando",
            host="Lake Nona Toastmasters Club", cost="Free", url=tm, recurrence="weekly",
            schedule="every Tuesday, 6:30 PM", **common)
        d += timedelta(weeks=1)

    # BNI Momentum Orlando — weekly Tuesdays 8:00 AM at Curious Cork (Planwise Partners listing).
    bni = "https://www.eventbrite.com/e/bni-momentum-orlando-weekly-business-networking-referral-meeting-tickets-2002106152397"
    d = datetime(2026, 10, 20, 8, 0)
    for _ in range(WEEKS_AHEAD):
        add(title="BNI Momentum Orlando", group="BNI Momentum Orlando", category="Business Networking",
            about="Weekly BNI referral-networking breakfast in Lake Nona: one member per profession, short pitches, and referral exchange. Visitors welcome; BNI visitor fees may apply.",
            when=d, venue="Curious Cork Kitchen & Bar", address="14383 Narcoossee Rd, Orlando, FL 32832",
            city="Orlando", host="Planwise Partners", cost="See event page", url=bni, recurrence="weekly",
            schedule="weekly, Tuesdays 8:00 AM (per the organizer's listing; confirm with the chapter)", **common)
        d += timedelta(weeks=1)

    # Rotary Club of Lake Nona — 2nd & 4th Tuesdays, 11:45 AM; no meeting Nov 24 / Dec 22.
    rot = "https://www.rotarycluboflakenona.com/"
    for y, m, day in [(2026, 10, 27), (2026, 11, 10), (2026, 12, 8), (2027, 1, 12), (2027, 1, 26),
                      (2027, 2, 9), (2027, 2, 23), (2027, 3, 9), (2027, 3, 23), (2027, 4, 13), (2027, 4, 27),
                      (2027, 5, 11), (2027, 5, 25), (2027, 6, 8), (2027, 6, 22)]:
        add(title="Rotary Club of Lake Nona Lunch Meeting", group="Rotary Club of Lake Nona", category="Business Networking",
            about="Lunch meeting of Lake Nona's Rotary club: networking and fellowship, then a guest speaker and club business. Visitors are welcome.",
            when=datetime(y, m, day, 11, 45), venue="Home2 Suites by Hilton Orlando Southeast Nona",
            address="10002 Eagle Creek Sanctuary Blvd, Orlando, FL 32832", city="Orlando",
            host="Rotary Club of Lake Nona", cost="Lunch fee (see club site)", url=rot,
            schedule="2nd and 4th Tuesdays, 11:45 AM-1:00 PM", **common)

    # Lake Nona Regional Chamber of Commerce — dated events, each with its own page.
    base = "https://business.lakenonacc.org/events/Details/"
    hampton = ("Hampton Inn & Home2 Suites by Hilton Orlando Southeast Nona", "10002 Eagle Creek Sanctuary Blvd, Orlando, FL 32832")
    starbucks = ("Starbucks Lake Nona", "13495 Veterans Way, Orlando, FL 32827")
    tba = ("Venue to be announced (Lake Nona)", "Lake Nona, Orlando, FL 32827")
    chamber = [
        # (title, slug, (y,m,d,h,min), venue tuple, cost, category, about)
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1550790", (2026, 10, 28, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer: coffee, breakfast, member spotlights, and structured networking for local business owners and newcomers."),
        ("SGS Lake Nona MedTech Regulatory Innovation Symposium", "sgs-lake-nona-medtech-regulatory-innovation-symposium-1900775", (2026, 10, 29, 8, 0), ("GuideWell Innovation Center", "6555 Sanger Rd, Orlando, FL 32827"), "See event page", "Technology Meetings",
         "Full-day symposium for medtech leaders, clinicians, and regulators on AI, cybersecurity, and FDA priorities. Chamber members can request a discount code."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1904884", (2026, 11, 10, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("Fifth Third Bank Lake Nona Ribbon Cutting", "fifth-third-bank-lake-nona-ribbon-cutting-ceremony-1953641", (2026, 11, 10, 10, 0), ("Fifth Third Bank, Nona West", "14219 Nona North Rd, Orlando, FL 32824"), "Free", "Special Events",
         "Community ribbon cutting for Fifth Third Bank's Lake Nona branch, with refreshments and a chance to meet local business leaders. Ribbon cutting at 11 AM."),
        ("NPL Ladies Night Out Social", "npl-annual-ladies-night-out-social-1904689", (2026, 11, 18, 17, 0), ("Aloft Lake Nona (W XYZ Bar)", "7215 Corner Dr, Orlando, FL 32827"), "Free", "Business Networking",
         "Nona Professional Ladies' annual evening social: casual networking for women in the Lake Nona community. Bring a friend or coworker."),
        ("Jingle Mingle Member Celebration", "jingle-mingle-annual-member-celebration-1734551", (2026, 12, 10, 17, 30), ("The Pavilion at Boxi Park", "6877 Tavistock Lakes Blvd, Orlando, FL 32827"), "See event page", "Special Events",
         "The Chamber's holiday networking evening with food, drinks, games, and prizes. Ugly sweaters encouraged."),
        ("Business After Hours", "business-after-hours-hosted-by-lake-nona-chamber-of-commerce-sponsored-by-lime-fresh-mexican-grill-1899657", (2027, 1, 5, 17, 30), ("MS2 Lake Nona Accelerator (Lake Nona Chamber)", "7004 Tavistock Lakes Blvd, Suite 132, Orlando, FL 32827"), "See event page", "Business Networking",
         "First Business After Hours of 2027: evening networking with food and drinks for the Lake Nona business community."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1899667", (2027, 1, 12, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1899662", (2027, 1, 27, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer: coffee, breakfast, member spotlights, and structured networking."),
        ("Illumination Awards Gala", "illumination-awards-presented-by-adventhealth-1733462", (2027, 1, 29, 19, 0), ("Aloft Lake Nona", "7215 Corner Dr, Orlando, FL 32827"), "See event page", "Special Events",
         "The Lake Nona Chamber's annual gala honoring local leaders and businesses, with dinner, entertainment, and networking."),
        ("Business After Hours", "business-after-hours-1899658", (2027, 2, 2, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber. Venue to be announced on the Chamber page."),
        ("NPL Luncheon", "npl-luncheon-coming-soon-1904911", (2027, 2, 8, 12, 30), tba, "See event page", "Business Networking",
         "Nona Professional Ladies networking and speaker luncheon for women in the Lake Nona community. Venue and speaker to be announced."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1899668", (2027, 2, 9, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1899663", (2027, 2, 24, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer: coffee, breakfast, member spotlights, and structured networking."),
        ("Business After Hours (hosted by Keller Williams Advantage III)", "business-after-hours-hosted-by-keller-williams-advantage-iii-realty-1899659", (2027, 3, 2, 17, 30), ("Keller Williams Advantage III Realty", "9161 Narcoossee Rd, Suite 203, Orlando, FL 32827"), "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber, hosted by Keller Williams Advantage III Realty (address as listed; confirm on the Chamber page)."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1899669", (2027, 3, 9, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1899664", (2027, 3, 31, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer: coffee, breakfast, member spotlights, and structured networking."),
        ("Business After Hours (hosted by Plug and Play)", "business-after-hours-hosted-by-plug-and-play-1899660", (2027, 4, 6, 17, 30), ("GuideWell Innovation Center", "6555 Sanger Rd, Orlando, FL 32827"), "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber, hosted by Plug and Play at the GuideWell Innovation Center."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1903003", (2027, 4, 13, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("Nona Fest", "nona-fest-presented-by-adventhealth-1733497", (2027, 4, 17, 10, 0), ("USTA National Campus", "10000 USTA Blvd, Orlando, FL 32827"), "See event page", "Special Events",
         "The Lake Nona Chamber's community festival at the USTA National Campus, with local businesses and organizations."),
        ("State of Lake Nona Summit", "state-of-lake-nona-summit-presented-by-kpmg-1733556", (2027, 4, 23, 8, 0), ("GuideWell Innovation Theatre", "6555 Sanger Rd, Orlando, FL 32827"), "See event page", "Special Events",
         "Signature Chamber summit where business and community leaders share what's next for Lake Nona, followed by networking."),
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1899665", (2027, 4, 28, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer: coffee, breakfast, member spotlights, and structured networking. Venue as listed for the series; confirm on the Chamber page."),
        ("Business After Hours", "business-after-hours-1899661", (2027, 5, 4, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber. Venue to be announced on the Chamber page."),
        ("Coffee with the Chamber", "coffee-with-the-chamber-1899671", (2027, 5, 11, 9, 0), starbucks, "Free", "Business Networking",
         "Relaxed, no-presentation coffee meetup for Lake Nona professionals. Members and non-members welcome."),
        ("NPL Luncheon", "npl-luncheon-coming-soon-1904913", (2027, 5, 17, 12, 30), tba, "See event page", "Business Networking",
         "Nona Professional Ladies networking and speaker luncheon. Venue and speaker to be announced."),
        ("Chamber Connections Morning Mixer", "chamber-connections-presented-by-adventhealth-1899666", (2027, 5, 26, 8, 30), hampton, "See event page", "Business Networking",
         "Lake Nona Chamber's morning mixer. Venue as listed for the series; confirm on the Chamber page."),
        ("Business After Hours (hosted by Expedia Cruises)", "business-after-hours-hosted-by-expedia-cruises-1921055", (2027, 6, 1, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber, hosted by Expedia Cruises. Venue to be announced."),
        ("Business After Hours", "business-after-hours-1921056", (2027, 7, 6, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber. Venue to be announced."),
        ("Business After Hours", "business-after-hours-1921057", (2027, 8, 3, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber. Venue to be announced."),
        ("NPL Luncheon", "npl-luncheon-coming-soon-1904914", (2027, 8, 23, 12, 30), tba, "See event page", "Business Networking",
         "Nona Professional Ladies networking and speaker luncheon. Venue and speaker to be announced."),
        ("Business After Hours (hosted by AdventHealth ER)", "business-after-hours-hosted-by-adventhealth-er-1921060", (2027, 9, 7, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber, hosted by AdventHealth ER. Venue to be announced."),
        ("Business After Hours (hosted by Eleve Title Co)", "business-after-hours-hosted-by-eleve-title-co-1921064", (2027, 10, 5, 17, 30), tba, "See event page", "Business Networking",
         "Monthly evening networking from the Lake Nona Chamber, hosted by Eleve Title Co. Venue to be announced."),
    ]
    for title, slug, (y, m, dd, h, mi), (venue, address), cost, cat, about in chamber:
        url = base + slug
        add(title=title, group="Lake Nona Regional Chamber of Commerce", category=cat, about=about,
            when=datetime(y, m, dd, h, mi), venue=venue, address=address, city="Orlando",
            host="Lake Nona Regional Chamber of Commerce", cost=cost, url=url, unique_url=url, **common)

    # Crema at Nona — 1st & 3rd Tuesdays, 8:30 AM (dates beyond those already listed).
    crema = "https://www.eventbrite.com/e/crema-at-nonas-networking-event-tickets-1996112825194"
    for y, m in [(2027, 1), (2027, 2), (2027, 3), (2027, 4), (2027, 5)]:
        for n in (1, 3):
            d = nth_weekday(y, m, 1, n)
            if d and d > date(2027, 1, 5):
                add(title="Crema at Nona", group="Crema at Nona", category="Business Networking",
                    about="Free morning networking over coffee at Nona Blue, open to every industry. Hosted by Julio Aviles.",
                    when=datetime(d.year, d.month, d.day, 8, 30), venue="Nona Blue Modern Tavern",
                    address="9685 Narcoossee Rd, Orlando, FL 32832", city="Orlando", host="Julio Aviles",
                    cost="Free", url=crema, schedule="1st and 3rd Tuesdays, 8:30-10:00 AM", **common)

    # Nona Legacy Circle Business Mixer — one-off.
    nlc = "https://www.eventbrite.com/e/nona-legacy-circle-business-mixer-tickets-2002628671265"
    add(title="Nona Legacy Circle Business Mixer", group="Nona Legacy Circle", category="Business Networking",
        about="Afternoon mixer for Nona-area business owners to meet, share what they do, and swap referrals. Includes a raffle.",
        when=datetime(2026, 10, 22, 16, 0), venue="Lime Fresh Mexican Grill",
        address="13052 Narcoossee Rd, Orlando, FL 32832", city="Orlando", host="Nona Legacy Circle",
        cost="See event page", url=nlc, unique_url=nlc, **common)

    # Keller Williams Lake Nona — Breakthrough 120 (5-day course, two remaining weeks).
    kw = "https://www.eventbrite.com/e/breakthrough-120-at-kw-lake-nona-tickets-1999289856781"
    for i in range(5):
        add(title="Breakthrough 120 (Zoom) — KW Lake Nona", group="Keller Williams Lake Nona", category="Real Estate Meetings",
            about="Five-evening productivity and lead-generation course from Keller Williams Lake Nona, held on Zoom this week.",
            when=datetime(2026, 10, 19 + i, 18, 0), venue="Online (Zoom)", address="Online event", city="Orlando",
            host="Keller Williams Lake Nona", cost="See event page", url=kw, virtual=True,
            schedule="Mon-Fri, Oct 19-23, 6:00-8:00 PM", **common)
        add(title="Breakthrough 120 (en español) — KW Lake Nona", group="Keller Williams Lake Nona", category="Real Estate Meetings",
            about="Five-morning productivity and lead-generation course at the Keller Williams Lake Nona office, taught in Spanish.",
            when=datetime(2026, 10, 26 + i, 9, 0), venue="Keller Williams Lake Nona",
            address="9161 Narcoossee Rd, Orlando, FL 32832", city="Orlando",
            host="Keller Williams Lake Nona", cost="See event page", url=kw,
            schedule="Mon-Fri, Oct 26-30, 9:00 AM-12:00 PM", **common)

    # St. Cloud Chamber (Narcoossee corridor, ~11 mi).
    stc = "https://business.stcloudflchamber.com/events/details/"
    chamber_hq = ("St. Cloud Chamber of Commerce", "1200 New York Ave, St. Cloud, FL 34769")
    for title, slug, when, (venue, address), about in [
        ("Coffee Co-Op (sponsored by First Choice Business Brokers Lake Nona)", "2026-coffee-co-op-sponsored-by-first-choice-business-brokers-lake-nona-16477",
         datetime(2026, 10, 20, 8, 30), chamber_hq,
         "Monthly coffee where attendees take turns giving a quick business pitch, then network. Members and non-members welcome; bring marketing materials."),
        ("Osceola Business Partners Leads Group — Visitor Day Lunch", "osceola-business-partners-leads-group-visitor-day-lunch-17035",
         datetime(2026, 10, 21, 12, 0), chamber_hq,
         "Free visitor-day lunch hosted by the Osceola Business Partners leads group at the St. Cloud Chamber. RSVP on the event page."),
        ("CHamber CHat over Coffee", "chamber-chat-coffee-11-05-2026-16909",
         datetime(2026, 11, 5, 8, 30), chamber_hq,
         "Free morning coffee at the St. Cloud Chamber of Commerce."),
    ]:
        url = stc + slug
        add(title=title, group="St. Cloud Greater Osceola Chamber of Commerce", category="Business Networking",
            about=about, when=when, venue=venue, address=address, city="St. Cloud",
            host="St. Cloud Chamber of Commerce", cost="Free", url=url, unique_url=url, **common)
    bwp = stc + "breakfast-with-the-pros-11-10-2026-16835"
    for y, m, dd in [(2026, 11, 10), (2026, 12, 8), (2027, 1, 12), (2027, 2, 9), (2027, 3, 9)]:
        add(title="Breakfast with the Pros", group="St. Cloud Greater Osceola Chamber of Commerce", category="Business Networking",
            about="Free monthly business-education breakfast where local experts share practical advice. Open to the public; breakfast for the first 30 guests.",
            when=datetime(y, m, dd, 8, 0), venue="VFW Post 3227", address="915 New York Ave, St. Cloud, FL 34769",
            city="St. Cloud", host="St. Cloud Chamber of Commerce", cost="Free", url=bwp,
            schedule="monthly Sept-March, 8:00-9:00 AM", **common)


# --- Import-file parsing ---------------------------------------------------

COLS_RE = re.compile(r"INSERT INTO public\.meetings \(([^)]*)\) VALUES \(", re.S)


def parse_values(s, i):
    """Parse a SQL VALUES tuple starting just after '('. Returns (values, end)."""
    vals, n = [], len(s)
    while i < n:
        while s[i] in " \n\t,":
            i += 1
        if s[i] == ")":
            return vals, i + 1
        if s[i] == "'":
            j, buf = i + 1, []
            while True:
                if s[j] == "'" and j + 1 < n and s[j + 1] == "'":
                    buf.append("'")
                    j += 2
                elif s[j] == "'":
                    break
                else:
                    buf.append(s[j])
                    j += 1
            vals.append("".join(buf))
            i = j + 1
        else:
            m = re.match(r"(now\(\)|NULL|true|false|-?\d+(?:\.\d+)?)", s[i:], re.I)
            if not m:
                raise ValueError(f"cannot parse at {s[i:i+40]!r}")
            tok = m.group(1)
            low = tok.lower()
            if low in ("null", "true", "false"):
                vals.append({"null": None, "true": True, "false": False}[low])
            elif low == "now()":
                vals.append(tok)
            else:
                vals.append(float(tok) if "." in tok else int(tok))
            i += len(tok)
    raise ValueError("unterminated tuple")


# Social, support, hobby, and trading-course groups the keyword search pulled
# in. BizLinq lists business networking, so these are dropped by name.
BLOCK_GROUPS = [
    "evolving mind", "freethought", "learn-to-trade", "euchre", "mambemb", "anxiety", "shyness",
    "social club", "prana house", "gender misfits", "photography community", "human compassion",
    "female friends", "nihilism", "stoics", "fun, young", "sanctuary for mind", "retro computing",
    "sound club", "side hustle", "behavioral center", "restaurant equipment",
    "amazing women collective", "video & post production", "manageengine",
]


# Specific listings that are not open business events.
BLOCK_TITLES = [
    "launch lake nona",  # AdventHealth employee onboarding
    "trading card",
    # Other Eventbrite listings for sessions already curated above.
    "breakthrough 120 at kw lake nona",
    "bni momentum orlando",
]


def blocked(group):
    g = (group or "").lower()
    return any(b in g for b in BLOCK_GROUPS)


CROSSPOSTS = set()


def imported(path, existing):
    text = open(path).read()
    out, skipped = [], {"far": 0, "past": 0, "existing": 0, "off-topic": 0}
    for m in COLS_RE.finditer(text):
        cols = [c.strip() for c in m.group(1).split(",")]
        vals, _ = parse_values(text, m.end())
        r = dict(zip(cols, vals))
        url = r.get("source_url")
        if not url or url in existing:
            skipped["existing"] += 1
            continue
        if blocked(r.get("group_name")) or blocked(r.get("host_name")) or any(
                t in str(r.get("title", "")).lower() for t in BLOCK_TITLES):
            skipped["off-topic"] += 1
            continue
        # Online events sometimes arrive marked in-person ("Zoom, Orlando, FL").
        where = f"{r.get('venue', '')} {r.get('address', '')}".lower()
        if re.search(r"\b(zoom|online|webinar|virtual)\b", where):
            r["is_virtual"] = True
        # In person needs a geocoded venue; rows without a ZIP carry the
        # group's fallback city coordinates, so their distance is unknown.
        if not r.get("is_virtual") and not str(r.get("zip_code") or "").strip():
            skipped["far"] += 1
            continue
        if r.get("category") == "Network Marketing":
            r["category"] = "Business Networking"
        start = datetime.fromisoformat(str(r["starts_at"]).replace("Z", "+00:00"))
        if start <= NOW:
            skipped["past"] += 1
            continue
        if r.get("is_virtual"):
            # Online events count only from Orlando-area organizers.
            if miles(float(r["latitude"]), float(r["longitude"])) > 25:
                skipped["far"] += 1
                continue
        elif miles(float(r["latitude"]), float(r["longitude"])) > RADIUS_MI:
            skipped["far"] += 1
            continue
        # The same webinar is often cross-posted to several Meetup groups.
        key = (str(r["title"]).strip().lower(), str(r["starts_at"])[:16], str(r["venue"]).strip().lower())
        if key in CROSSPOSTS:
            skipped["existing"] += 1
            continue
        CROSSPOSTS.add(key)
        existing.add(url)
        out.append({
            "title": r["title"], "group": r["group_name"], "category": r["category"], "tagline": r["tagline"],
            "description": r["description"], "starts_at": r["starts_at"], "venue": r["venue"],
            "address": r["address"], "city": r["city"], "state": r["state"], "zip": r["zip_code"],
            "lat": float(r["latitude"]), "lon": float(r["longitude"]), "host": r["host_name"],
            "virtual": bool(r["is_virtual"]), "cost": r["cost_description"], "source_url": url,
            "recurrence": None, "source": r.get("source") or ("meetup" if "meetup.com" in url else "eventbrite"),
            "count": int(r.get("attendee_count") or 0),
        })
    print(f"  {path.split('/')[-1]}: kept {len(out)}, skipped {skipped}")
    return out


def to_sql(r):
    return (
        "INSERT INTO public.meetings (title, group_name, category, tagline, description, starts_at, venue, address,"
        " city, state, zip_code, latitude, longitude, host_name, attendee_count, is_virtual, cost_description,"
        " status, source, source_url, recurrence, last_verified_at) VALUES ("
        + ", ".join([
            sql_str(r["title"]), sql_str(r["group"]), sql_str(r["category"]), sql_str(r["tagline"]),
            sql_str(r["description"]), sql_str(r["starts_at"]), sql_str(r["venue"]), sql_str(r["address"]),
            sql_str(r["city"]), sql_str(r["state"]), sql_str(r["zip"]), f"{r['lat']:.6f}", f"{r['lon']:.6f}",
            sql_str(r["host"]), str(r.get("count", 0)), "true" if r["virtual"] else "false", sql_str(r["cost"]),
            "'live'", sql_str(r["source"]), sql_str(r["source_url"]),
            sql_str(r["recurrence"]) if r["recurrence"] else "NULL", "now()",
        ])
        + ") ON CONFLICT (source_url) WHERE source_url IS NOT NULL DO NOTHING;"
    )


# More dates for weekly in-person groups already listed within RADIUS_MI:
# copy each series' latest row forward week by week until WEEKS_AHEAD out.
EXTEND_SQL = """
-- Extend weekly in-person groups within {radius} mi of Lake Nona to a {weeks}-week window.
-- The daily roll_weekly_meetings() job then keeps that window going.
INSERT INTO public.meetings (title, group_name, category, tagline, description, starts_at, venue, address,
  city, state, zip_code, latitude, longitude, host_name, attendee_count, is_virtual, cost_description,
  status, source, source_url, recurrence, last_verified_at)
SELECT m.title, m.group_name, m.category, m.tagline, m.description,
       ((m.starts_at AT TIME ZONE 'America/New_York') + make_interval(weeks => k)) AT TIME ZONE 'America/New_York',
       m.venue, m.address, m.city, m.state, m.zip_code, m.latitude, m.longitude, m.host_name, 0, m.is_virtual,
       m.cost_description, 'live', m.source,
       regexp_replace(m.source_url, '@\\d{{4}}-\\d{{2}}-\\d{{2}}$', '') || '@' ||
         to_char((m.starts_at AT TIME ZONE 'America/New_York') + make_interval(weeks => k), 'YYYY-MM-DD'),
       'weekly', m.last_verified_at
FROM (
  SELECT DISTINCT ON (group_name, title, address) *
  FROM public.meetings
  WHERE status = 'live' AND recurrence = 'weekly' AND source_url IS NOT NULL
    AND NOT is_virtual
    AND 3958.8 * 2 * asin(sqrt(
          power(sin(radians(latitude - {lat}) / 2), 2)
          + cos(radians({lat})) * cos(radians(latitude)) * power(sin(radians(longitude - ({lon})) / 2), 2)
        )) <= {radius}
  ORDER BY group_name, title, address, starts_at DESC
) m
CROSS JOIN generate_series(1, {weeks}) AS k
WHERE ((m.starts_at AT TIME ZONE 'America/New_York') + make_interval(weeks => k)) AT TIME ZONE 'America/New_York'
      <= timestamptz '{until}'
ON CONFLICT (source_url) WHERE source_url IS NOT NULL DO NOTHING;
"""
WEEKS_AHEAD = 16


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--existing", required=True, help="JSON list of source_urls already in the database")
    ap.add_argument("--import", dest="imports", action="append", default=[])
    ap.add_argument("--out", required=True)
    ap.add_argument("--report", required=True)
    args = ap.parse_args()

    existing = set(json.load(open(args.existing)))
    cache = load_cache()
    curated(cache)
    save_cache(cache)
    print(f"curated rows: {len(rows)}")
    for r in rows:
        # Curated series use "<page>#<date>"; drop the plain page from imports.
        existing.add(r["source_url"])
        existing.add(r["source_url"].split("#", 1)[0])
    for path in args.imports:
        rows.extend(imported(path, existing))

    until = (NOW + timedelta(weeks=WEEKS_AHEAD)).isoformat()
    with open(args.out, "w") as f:
        f.write("-- Lake Nona (32827/32832) meeting hunt, checked 2026-10-16. Review, then apply.\n")
        f.write("-- Generated by tools/lake_nona_import.py. Safe to re-run (ON CONFLICT DO NOTHING).\n")
        for r in sorted(rows, key=lambda r: r["starts_at"]):
            f.write(to_sql(r) + "\n")
        f.write(EXTEND_SQL.format(
            weeks=WEEKS_AHEAD, until=until, lat=CENTER[0], lon=CENTER[1], radius=RADIUS_MI,
        ))

    with open(args.report, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["starts_at", "title", "group", "venue", "city", "miles", "virtual", "cost", "source", "url"])
        for r in sorted(rows, key=lambda r: r["starts_at"]):
            w.writerow([r["starts_at"], r["title"], r["group"], r["venue"], r["city"],
                        f"{miles(r['lat'], r['lon']):.1f}", r["virtual"], r["cost"], r["source"], r["source_url"]])

    inperson = sum(1 for r in rows if not r["virtual"])
    print(f"TOTAL rows={len(rows)} in-person={inperson} virtual={len(rows) - inperson}")
    bands = {"<=5": 0, "5-10": 0, "10-15": 0}
    for r in rows:
        if r["virtual"]:
            continue
        d = miles(r["lat"], r["lon"])
        bands["<=5" if d <= 5 else "5-10" if d <= 10 else "10-15"] += 1
    print("in-person by distance:", bands)


if __name__ == "__main__":
    main()
