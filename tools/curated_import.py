"""Hand-curated Florida listings (organizer-provided). One row failure never
kills the batch. Usage: python3 tools/curated_import.py"""
import sys
import calendar
from datetime import date, datetime

sys.path.insert(0, "tools")
from meetup_import import geocode, sql_str, load_cache, in_state

cache = load_cache()
FALLBACKS = {
    # venue address -> (lat, lon, zip) when the geocoder has no record
    "7215 Corner Drive, Orlando, FL 32827": (28.3916, -81.3390, "32827"),
    "500 South Orange Avenue, Orlando, FL 32801": (28.5420, -81.3790, "32801"),
}


def locate(addr, city, state):
    if addr in FALLBACKS:
        lat, lon, zipc = FALLBACKS[addr]
        if in_state(lat, lon, state):
            return lat, lon, zipc
    g = geocode(addr, cache)
    if g and in_state(g["lat"], g["lon"], state):
        return g["lat"], g["lon"], g.get("zip") or ""
    g = geocode(f"{city}, {state}", cache)
    if g and in_state(g["lat"], g["lon"], state):
        return g["lat"], g["lon"], g.get("zip") or ""
    raise ValueError(f"unlocatable: {addr}")


def nth_weekday(year, month, weekday, n):
    days = [w[weekday] for w in calendar.monthcalendar(year, month) if w[weekday] != 0]
    return date(year, month, days[n - 1]) if n <= len(days) else None


def occurrences(weekday, weeks, hour, minute, count, start):
    out, y, m = [], start.year, start.month
    while len(out) < count:
        for n in weeks:
            d = nth_weekday(y, m, weekday, n)
            if d and d >= start:
                out.append(datetime(d.year, d.month, d.day, hour, minute))
                if len(out) == count:
                    break
        m += 1
        if m > 12:
            m, y = 1, y + 1
    return out


rows, skipped = [], []


def add(title, group, host, contact, venue, address, city, state, starts, cost, desc):
    try:
        lat, lon, zipc = locate(address, city, state)
    except Exception as e:
        print(f"  SKIP {title[:50]}: {e}")
        skipped.append(title)
        return
    tagline = desc[:140].rsplit(" ", 1)[0] if len(desc) > 140 else desc
    rows.append(
        "INSERT INTO public.meetings (title, group_name, category, tagline, description, starts_at,"
        " venue, address, city, state, zip_code, latitude, longitude, host_name, attendee_count,"
        " is_virtual, cost_description, status, source, last_verified_at) VALUES ("
        + ", ".join([sql_str(title), sql_str(group), "'Business Networking'",
            sql_str(tagline), sql_str(desc + f" More info: {group}"), sql_str(starts),
            sql_str(venue), sql_str(address), sql_str(city), sql_str(state),
            sql_str(zipc), str(lat), str(lon), sql_str(host),
            "1", "false", sql_str(cost), "'live'", "'curated'", "now()"])
        + ");"
    )


def main():
    today = date(2026, 10, 14)
    for dt in occurrences(1, [1, 3], 8, 30, 6, today):
        add("Crema at Nona", "Crema at Nona", "Julio Aviles",
            "Contact: Julio Aviles · 407-289-8999 · Meets 1st & 3rd Tuesdays 8:30-10:00 AM. ALWAYS FREE.",
            "Nona Blue Restaurant", "9685 Narcoossee Rd, Orlando, FL 32832",
            "Orlando", "FL", dt.strftime("%Y-%m-%dT%H:%M:%S-04:00"), "Free",
            "Morning networking over coffee at Nona Blue. 1st & 3rd Tuesdays 8:30-10:00 AM. ALWAYS FREE. Contact: Julio Aviles · 407-289-8999.")
    for dt in occurrences(1, [2, 4], 9, 0, 6, today):
        add("Crema West", "Crema West", "Darnell Mahomes",
            "Contact: Darnell Mahomes · 407-394-0343 · Meets 2nd & 4th Tuesdays 9:00-10:30 AM.",
            "Golden Pond Assisted Living", "402 Lakeview Road, Winter Garden, FL",
            "Winter Garden", "FL", dt.strftime("%Y-%m-%dT%H:%M:%S-04:00"), "Free",
            "Morning networking in Winter Garden. 2nd & 4th Tuesdays 9:00-10:30 AM. Contact: Darnell Mahomes · 407-394-0343.")
    add("Rockstar Connect / MK Alliance Networking Event", "Rockstar Connect", "Rockstar Connect",
        "Free event, RSVP required.",
        "Bar Louie - Orlando Gateway", "7015 South Semoran Boulevard, Orlando, FL 32822",
        "Orlando", "FL", "2026-10-27T18:00:00-04:00", "Free",
        "Evening networking mixer, Tuesday Oct 27 6:00-8:00 PM. Free, RSVP required.")
    add("CEO Mixer for Professionals (NetWorth Events Group)", "NetWorth Events Group", "NetWorth Events Group",
        "$36 admission.",
        "Aloft by Marriott Orlando Downtown", "500 South Orange Avenue, Orlando, FL 32801",
        "Orlando", "FL", "2026-10-21T17:30:00-04:00", "$36",
        "Business networking mixer for professionals, Wednesday Oct 21 5:30 PM. $36.")
    add("Amp Your Life Now Summit", "Amp Your Life Now", "Amp Your Life Now",
        "$172 admission. Annual growth and leadership summit.",
        "Aloft by Marriott Orlando Lake Nona", "7215 Corner Drive, Orlando, FL 32827",
        "Orlando", "FL", "2026-10-24T08:30:00-04:00", "$172",
        "Annual growth and leadership summit with local entrepreneur networking, Saturday Oct 24 8:30 AM. $172.")
    add("3rd Annual Fall Fest Networking Breakfast (Orlando Business Network)", "Orlando Business Network", "Orlando Business Network",
        "Free to attend.",
        "4 Rivers Smokehouse", "1600 West Fairbanks Avenue, Winter Park, FL 32789",
        "Winter Park", "FL", "2026-11-10T07:30:00-05:00", "Free",
        "Fall Fest networking breakfast, Tuesday Nov 10 7:30 AM. Free to attend.")

    with open("tools/seed_curated_fl.sql", "w") as f:
        f.write("-- Hand-curated Florida listings (organizer-provided). Review, then apply.\n")
        f.write("\n".join(rows) + "\n")
    print(f"DONE rows={len(rows)} skipped={len(skipped)}")
    print("wrote tools/seed_curated_fl.sql")


if __name__ == "__main__":
    main()
