"""Read the deployed ranking CLI over SSH and atomically save its public JSON."""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

REMOTE = '''import json, pathlib, subprocess, sys
app = pathlib.Path(sys.argv[1])
compose = ['docker','compose','--project-directory',str(app),'-f',str(app/'compose.yaml'),'-f',str(app/'compose.production.yaml')]
container = subprocess.check_output(compose + ['ps','-q','api'], text=True).strip()
if not container or '\\n' in container:
    raise RuntimeError('Expected one running API container')
subprocess.run(['docker','exec',container,'java','--enable-native-access=ALL-UNNAMED','-jar','/app/server.jar','export-addon-ranking'],check=True)
'''


def validate(data):
    sources = {'WowVoice', 'CatQuest', 'Wayfarer'}
    if data.get('schemaVersion') != 1 or not isinstance(data.get('groups'), list):
        raise ValueError('Unsupported ranking format')
    seen = set()
    for group in data['groups']:
        key = (group['speakerType'], group['race'], group['sex'])
        if key in seen:
            raise ValueError('Duplicate ranking group')
        seen.add(key)
        ranking = group['ranking']
        if [entry['rank'] for entry in ranking] != [1, 2, 3] or {entry['source'] for entry in ranking} != sources:
            raise ValueError('Invalid library order')
    return data


def main():
    root = Path(__file__).resolve().parent.parent
    names = ['TALKINGHEAD_SITE_SSH_HOST', 'TALKINGHEAD_SITE_SSH_KEY', 'TALKINGHEAD_SITE_REMOTE_DIR']
    missing = [name for name in names if not os.environ.get(name, '').strip()]
    if missing:
        raise ValueError('Set in config/build.env.local.ps1: ' + ', '.join(missing))
    host, key, app = [os.environ[name] for name in names]
    if not re.fullmatch(r'[A-Za-z0-9_.@-]+', host) or host.startswith('-'):
        raise ValueError('Invalid SSH destination')
    if not re.fullmatch(r'/[A-Za-z0-9_./-]+', app):
        raise ValueError('Invalid remote application directory')
    key = Path(key).expanduser()
    if not key.is_absolute():
        key = root / key
    if not key.is_file():
        raise ValueError('Configured SSH key does not exist')
    command = ['ssh', '-i', str(key), '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
               '-o', 'ConnectTimeout=15', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4',
               host, 'python3 - ' + shlex.quote(app)]
    result = subprocess.run(command, input=REMOTE, text=True, encoding='utf-8',
                            stdout=subprocess.PIPE, check=True, timeout=120)
    data = validate(json.loads(result.stdout))
    target = root / 'artifacts/voice-ranking/addon-voice-ranking.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.json.' + str(os.getpid()) + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temporary.replace(target)
    print(f"Ranking exported: {target}\nSnapshot: {data['generatedAt']}\nGroups: {len(data['groups'])}")


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'Ranking export failed: {error}', file=sys.stderr)
        sys.exit(1)
