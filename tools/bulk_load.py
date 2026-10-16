"""Bulk-load a seed SQL file (one statement per line) via the temporary
_bulk_load RPC. Usage: python3 tools/bulk_load.py tools/seed_orlando.sql"""
import json
import re
import sys
import urllib.request

REF = "qzmtchjjmcdlzwwfvrwd"
SECRET = "x7Kq2mZ9vB4nF8wQ1eR5tY3uI6oP0aS_dL2"


def anon_key():
    src = open("BizLinq/Backend/Config.swift").read()
    m = re.search(r'anonKey = "([^"]+)"', src)
    assert m, "anon key not found"
    return m.group(1)


def call(fn, payload, key):
    req = urllib.request.Request(
        f"https://{REF}.supabase.co/rest/v1/rpc/{fn}",
        data=json.dumps(payload).encode(),
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode()


def main(path):
    key = anon_key()
    ok, fail = 0, []
    with open(path) as f:
        stmts = [l.strip() for l in f if l.strip() and not l.strip().startswith("--")]
    for i, stmt in enumerate(stmts):
        try:
            call("_bulk_load", {"secret": SECRET, "q": stmt}, key)
            ok += 1
        except Exception as e:
            body = e.read().decode()[:160] if hasattr(e, "read") else str(e)[:160]
            fail.append((i, body))
    print(f"{path}: ok={ok} failed={len(fail)}")
    for i, body in fail[:5]:
        print(f"  stmt {i}: {body}")


if __name__ == "__main__":
    main(sys.argv[1])
