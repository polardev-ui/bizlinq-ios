"""Import the supplied research PDF without inventing dates or verified venues.
Usage: python3 tools/import_florida_directory.py /path/to/directory.pdf
Requires pdfplumber. Keeps original IDs, page references, all fields and link targets.
"""
import collections
import hashlib
import json
from pathlib import Path
import re
import sys
import pdfplumber

ROOT = Path(__file__).resolve().parents[1]

def extract(path):
    records, audit = [], []
    city = None
    current = None
    field = None
    aliases = {'Location': 'location', 'Meets': 'schedule', 'Cost': 'cost',
               'Host': 'host', 'Contact': 'contact', 'Review': 'review',
               'Source': 'sourceDescription', 'Sources': 'sourceLabels', 'Update October 13': 'update'}
    with pdfplumber.open(path) as pdf:
        assert len(pdf.pages) == 143
        for number, page in enumerate(pdf.pages, 1):
            lines = [l for l in page.extract_text_lines() if l['top'] < 800]
            audit.append({'page': number, 'text': '\n'.join(l['text'] for l in lines), 'ids': []})
            if number == 1 or number >= 142:
                continue
            for line in lines:
                text = line['text']
                size = max(c['size'] for c in line['chars'])
                if size > 17:
                    city = text
                    current = None
                    field = None
                    continue
                match = re.match(r'^(\d{3}) (.*)', text)
                if match and size > 11:
                    current = dict(id=int(match[1]), name=match[2], city=city, page=number,
                                   host='', contact='', review='', update='', sourceDescription='', sourceLabels='', sources=[])
                    records.append(current)
                    audit[-1]['ids'].append(current['id'])
                    field = 'name'
                    continue
                assert current is not None, (number, text)
                # Wrapped titles in this PDF are sometimes printed in body font
                # on the same line as their format. Keep the entire title.
                fmt = re.match(r'^(.*?)(In person|Virtual|Hybrid|Confirm format)\s*\|\s*(.*)$', text)
                if fmt:
                    if fmt[1].strip():
                        current['name'] += ' ' + fmt[1].strip()
                    current['format'], current['category'] = fmt[2], fmt[3]
                    field = 'category'
                    continue
                label = next((key for key in aliases if text.startswith(key + ':')), None)
                if label:
                    field = aliases[label]
                    current[field] = text[len(label)+1:].strip()
                else:
                    assert field, (number, text)
                    current[field] += ' ' + text
                if field == 'sourceLabels':
                    for link in page.hyperlinks:
                        if abs(link['top'] - line['top']) < 12 and link.get('uri'):
                            if link['uri'] not in current['sources']:
                                current['sources'].append(link['uri'])
        cover = audit[0]['text']
        appendix = '\n'.join(x['text'] for x in audit[-2:])
        contact_lines = appendix.split('Official Florida representative locator\n')[1].split('Additional historical')[0]
        cities = [c.strip() for c in re.split(r'\||\n', contact_lines) if c.strip()]
        historical = appendix.split('Additional historical / restricted meeting evidence\n')[1].split('\nOrganizer meeting guide')[0]
        locator = pdf.pages[141].hyperlinks[0]['uri']
        historical_url = pdf.pages[142].hyperlinks[0]['uri']
    assert len(records) == 539
    assert sorted(r['id'] for r in records) == list(range(1,540))
    for r in records:
        for key in ['name','city','format','category','location','schedule','cost','sources']:
            assert r.get(key), (r['id'], key)
        assert r['format'] in ['In person','Virtual','Hybrid','Confirm format']
        assert all(u.startswith(('https://','http://')) for u in r['sources'])
        cost = r['cost'].lower()
        r['costKind'] = ('paid' if cost.startswith('paid') else 'free' if (cost.startswith('free') or cost.startswith('complimentary') or cost in {'no membership fee / contract published', 'all group events free published', 'no attendance charge published', 'no dues published', 'no joining or attendance cost published', '$0 attendance published', 'no dues or fees published', 'always-free admission published'}) else 'unknown')
    return dict(updated='October 13, 2026', sourceSHA256=hashlib.sha256(Path(path).read_bytes()).hexdigest(),
                pageCount=143, publicationNotes=cover, listings=records, contactCities=cities,
                contactLocatorURL=locator, historicalNote=historical, historicalSourceURL=historical_url), audit

if __name__ == '__main__':
    data, audit = extract(sys.argv[1])
    output = ROOT / 'BizLinq/Data/FloridaDirectory.json'
    output.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'tmp/pdfs').mkdir(parents=True, exist_ok=True)
    (ROOT/'tmp/pdfs/page-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    print(f"Imported {len(data['listings'])} records, {len(data['contactCities'])} contact cities; audited {len(audit)} pages.")
    print('Formats:',dict(collections.Counter(r['format'] for r in data['listings'])))
    print('Costs:',dict(collections.Counter(r['costKind'] for r in data['listings'])))
    for r in data['listings']:
        print(f"p{r['page']:03} #{r['id']:03} {r['city']} | {r['name']}")
        if 'CLG' in r['name'] or 'CREMA' in r['name'] or r['id']>530:
            print(json.dumps(r,ensure_ascii=False))
