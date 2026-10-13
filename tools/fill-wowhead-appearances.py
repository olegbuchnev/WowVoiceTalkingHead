"""Fill missing exact-NPC appearances from localized Wowhead Forever pages."""
import argparse
import datetime as dt
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import shutil
import subprocess
import time
import urllib.error
import urllib.request
from urllib.parse import urlparse
import re

ROOT = Path(__file__).resolve().parents[1]
SUPPLEMENTS = ROOT / 'docs/internal/npc-appearance-supplements.json'
CACHE = ROOT / 'artifacts/wowhead-appearances'


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.canonical = []
        self.models = []
        self.headings = []
        self.heading = None

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == 'link' and a.get('rel') == 'canonical':
            self.canonical.append(a.get('href', ''))
        if 'data-mv-type-id' in a:
            self.models.append((a.get('data-mv-type'), a['data-mv-type-id'], a.get('data-mv-display-id')))
        if tag == 'h1':
            self.heading = []

    def handle_data(self, value):
        if self.heading is not None:
            self.heading.append(value)

    def handle_endtag(self, tag):
        if tag == 'h1' and self.heading is not None:
            self.headings.append(''.join(self.heading))
            self.heading = None


def exact_url(url, npc_id):
    u = urlparse(url)
    return (u.scheme == 'https' and u.netloc == 'www.wowhead.com'
            and re.fullmatch(r'/forever/ru/npc=' + str(npc_id) + r'(?:/[^?#]*)?', u.path) is not None)


def parse_page(npc_id, body, url):
    page = Page()
    page.feed(body)
    if not exact_url(url, npc_id) or len(page.canonical) != 1 or not exact_url(page.canonical[0], npc_id):
        raise ValueError('Canonical or response URL does not confirm the exact Forever NPC')
    displays = {int(display) for kind, npc, display in page.models
                if kind == '1' and npc == str(npc_id) and display and display.isdigit() and int(display) > 0}
    scripts = {int(n) for n in re.findall(r'linksButton\.dataset\.displayId\s*=\s*(\d+)\s*;', body)}
    if len(displays) != 1 or displays != scripts:
        raise ValueError('Missing or conflicting exact-NPC display evidence')
    if len(page.headings) != 1:
        raise ValueError('Missing or ambiguous NPC heading')
    name = page.headings[0].split('<', 1)[0].strip()
    result = {'displayID': displays.pop(), 'source': f'https://www.wowhead.com/forever/ru/npc={npc_id}',
              'verifiedOn': dt.date.today().isoformat(),
              'evidence': 'Exact localized Forever NPC canonical URL; matching View in 3D NPC/display attributes and linksButton.dataset.displayId.'}
    if re.search(r'[А-Яа-яЁё]', name):
        result['nameRu'] = name
        result['evidence'] += ' Russian name comes from the NPC heading without its title.'
    return result


def candidates(scope):
    script = """
const {dataTable}=require('./tools/import-forever-audio');
const db=dataTable('src/Speakers.lua');
const scope=process.argv[1];
(async()=>{
 const quests=scope==='voting'?(await import('./web/voice-vote/server.mjs')).buildCatalogue().catalogue.quests:[];
 const ids=new Set(quests.map(q=>q.npc.id));
 console.log(JSON.stringify(Object.entries(db.npcs).filter(([id,n])=>Number(id)>0&&Number(id)<900000000&&!n.displayID&&(scope==='all'||ids.has(Number(id)))).map(([id,n])=>({npcID:Number(id),name:n.name,questIDs:quests.filter(q=>q.npc.id===Number(id)).map(q=>q.questID)}))));
})();
"""
    return json.loads(subprocess.check_output(['node', '-e', script, scope], cwd=ROOT, encoding='utf-8'))


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(path)


def run():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--scope', choices=['voting', 'all'], default='voting')
    ap.add_argument('--apply', action='store_true', help='Persist verified supplements and regenerate shared data')
    ap.add_argument('--refresh', action='store_true', help='Recheck cached negative results before their seven-day expiry')
    args = ap.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    selected = candidates(args.scope)
    report = {'startedAt': dt.datetime.now(dt.timezone.utc).isoformat(), 'scope': args.scope,
              'total': len(selected), 'results': [], 'completed': False, 'applied': []}
    report_path = CACHE / f'{args.scope}-report.json'
    consecutive_errors = 0
    for candidate in selected:
        npc_id = candidate['npcID']
        cached = CACHE / f'{npc_id}.json'
        entry = json.loads(cached.read_text(encoding='utf-8')) if cached.exists() else None
        fresh = entry and (entry['status'] == 'verified' or (not args.refresh and time.time() - entry['checkedAt'] < 7 * 86400))
        if not fresh:
            time.sleep(1)
            url = f'https://www.wowhead.com/forever/ru/npc={npc_id}'
            entry = {'checkedAt': time.time(), 'status': 'error'}
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'}), timeout=30) as response:
                    body = response.read().decode('utf-8')
                    resolved = response.url
                (CACHE / f'{npc_id}.html').write_text(body, encoding='utf-8')
                entry.update(bodySHA256=hashlib.sha256(body.encode()).hexdigest(), url=resolved)
                entry['supplement'] = parse_page(npc_id, body, resolved)
                entry['status'] = 'verified'
            except urllib.error.HTTPError as error:
                entry.update(status='blocked' if error.code in (403, 429) else 'error', error=f'HTTP {error.code}')
            except ValueError as error:
                entry.update(status='unresolved', error=str(error))
            except (OSError, UnicodeError) as error:
                entry.update(error=str(error))
            save(cached, entry)
        elif entry['status'] == 'verified':
            # Parse saved evidence again; never blindly trust a cached supplement.
            body = (CACHE / f'{npc_id}.html').read_text(encoding='utf-8')
            if hashlib.sha256(body.encode()).hexdigest() != entry['bodySHA256']:
                raise ValueError(f'Cached evidence changed for NPC {npc_id}')
            verified = parse_page(npc_id, body, entry['url'])
            verified['verifiedOn'] = entry['supplement']['verifiedOn']
            entry['supplement'] = verified
        report['results'].append({**candidate, **entry})
        consecutive_errors = consecutive_errors + 1 if entry['status'] in ('error', 'blocked') else 0
        print(f"[{len(report['results'])}/{len(selected)}] {npc_id}: {entry['status']}", flush=True)
        save(report_path, report)
        if entry['status'] == 'blocked' or consecutive_errors >= 3:
            report['stoppedReason'] = 'Remote blocking or repeated network errors; resume later without bypassing restrictions'
            break
    report['completed'] = not report.get('stoppedReason') and len(report['results']) == len(selected)
    if args.apply:
        backup = CACHE / ('before-' + dt.datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
        backup.mkdir()
        for file in [SUPPLEMENTS, ROOT / 'src/Speakers.lua', ROOT / 'docs/internal/speakers-manifest.json']:
            shutil.copy2(file, backup / file.name)
        data = json.loads(SUPPLEMENTS.read_text(encoding='utf-8'))
        for entry in report['results']:
            key = str(entry['npcID'])
            if entry['status'] == 'verified' and key not in data['npcs']:
                data['npcs'][key] = entry['supplement']
                report['applied'].append(entry['npcID'])
        save(SUPPLEMENTS, data)
        subprocess.run(['node', 'tools/generate-speakers.js'], cwd=ROOT, check=True)
    save(report_path, report)
    print(f"Applied {len(report['applied'])}; report: {report_path}")
    if not report['completed']:
        raise SystemExit(1)


if __name__ == '__main__':
    run()
