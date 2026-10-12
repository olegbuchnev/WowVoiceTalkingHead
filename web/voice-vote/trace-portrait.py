"""Run on the host over SSH: python3 trace-portrait.py p-a81f3c92d640."""
import argparse
import gzip
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description="Find one browser portrait load and its asset requests.")
parser.add_argument("load_id")
parser.add_argument("--since", default="24h")
args = parser.parse_args()
if not re.fullmatch(r"p-[a-f0-9]{12}", args.load_id):
    parser.error("Expected a portrait load ID such as p-a81f3c92d640")

result = subprocess.run(
    ["docker", "logs", "--since", args.since, "talkinghead-vote-web-1"],
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=True,
)

def records(lines):
    for line in lines:
        try:
            row = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(row, dict):
            yield row

web = list(records(result.stdout.splitlines()))
portraits = [r for r in web if r.get("event") == "portrait_client" and r.get("loadID") == args.load_id]
if not portraits:
    raise SystemExit("Load ID not found. The browser report may not have arrived, or logs may have rotated/restarted.")
request_ids = {r["requestID"] for p in portraits for r in p.get("resources", []) if r.get("requestID")}
output = portraits + [r for r in web if r.get("requestID") in request_ids]
for file in Path("/var/log/nginx").glob("talkinghead-assets.jsonl*"):
    opener = gzip.open if file.suffix == ".gz" else open
    with opener(file, "rt", encoding="utf-8", errors="replace") as stream:
        output.extend(r for r in records(stream) if r.get("requestID") in request_ids)
for row in sorted(output, key=lambda r: r.get("time", "")):
    print(json.dumps(row, ensure_ascii=False))
