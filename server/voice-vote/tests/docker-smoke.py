"""Verify the built Linux image using an isolated Compose project and database."""
import http.cookiejar
import json
import os
from pathlib import Path
import socket
import time
import subprocess
import urllib.request
import urllib.parse
import urllib.error
import uuid

server = Path(__file__).resolve().parents[1]
repo = server.parents[1]
project = "vote-smoke-" + uuid.uuid4().hex[:10]
work = repo / "artifacts" / project
work.mkdir(parents=True)
catalogue = json.loads((repo / "data/voice-vote/catalogue.json").read_text(encoding="utf-8"))
(work / "catalogue.json").write_text(json.dumps(catalogue), encoding="utf-8")
(work / "admin-password.txt").write_text(uuid.uuid4().hex, encoding="utf-8")
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
env = {**os.environ, "VOICE_VOTE_CATALOGUE_DIR": str(work), "VOICE_VOTE_HOST_PORT": str(port),
       "VOICE_VOTE_SECURE_COOKIE": "false", "VOICE_VOTE_IMAGE": "talkinghead-vote-server:local",
       "VOICE_VOTE_ADMIN_PASSWORD_FILE": str(work / "admin-password.txt")}
compose = ["docker", "compose", "-p", project, "-f", str(server / "compose.yaml")]

def run(*args):
    result = subprocess.run([*compose, *args], env=env, capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout.strip()

base = f"http://127.0.0.1:{port}"
browser = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

def request(path, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(base + path, data=data, headers={"Origin": base, "Content-Type": "application/json"})
    with browser.open(req, timeout=10) as response:
        return json.load(response)

try:
    run("up", "-d", "--no-build", "--wait", "--wait-timeout", "90")
    assert request("/api/votes/summary")["total"] == 0
    with browser.open(base + "/admin/") as response:
        assert b'<div id="root"' in response.read()
    try:
        request("/api/admin/dashboard")
        raise AssertionError("Admin statistics must require authentication")
    except urllib.error.HTTPError as error:
        assert error.code == 401
    session = request("/api/admin/session")
    login = urllib.request.Request(base + "/api/admin/login", data=urllib.parse.urlencode({
        "username": "admin", "password": (work / "admin-password.txt").read_text()
    }).encode(), headers={"Content-Type": "application/x-www-form-urlencoded", session["csrfHeader"]: session["csrf"], "Origin": base})
    with browser.open(login) as response:
        assert json.load(response)["authenticated"]
    assert request("/api/admin/dashboard")["votes"]["total"] == 0
    quest = catalogue["quests"][0]
    vote = {"questID": quest["questID"], "selectedId": quest["variants"][0]["id"],
            "variantIds": [v["id"] for v in quest["variants"]], "visitID": str(uuid.uuid4())}
    assert request("/api/votes/submit", vote)["state"] == "queued"
    deadline=time.monotonic()+15
    while request("/api/votes/summary")["total"] != 1:
        assert time.monotonic()<deadline, "Queued vote did not commit"
        time.sleep(.05)
    assert request("/api/admin/dashboard")["traffic"]["pageViews"] == 1
    run("up", "-d", "--no-build", "--force-recreate", "--wait", "--wait-timeout", "90")
    assert request("/api/votes/summary")["total"] == 1
    assert run("exec", "-T", "api", "id", "-u") == "10001"
    run("exec", "-T", "api", "java", "--enable-native-access=ALL-UNNAMED", "-jar", "/app/server.jar", "export-results")
    run("cp", "api:/data/exports", str(work / "exports"))
    result = json.loads(next((work / "exports").rglob("results.json")).read_text(encoding="utf-8"))
    assert result["summary"]["votes"] == 1
    assert result["summary"]["currentVotes"] == 1
    assert result["comparisons"][0]["questID"] == quest["questID"]
    assert request("/api/votes/summary")["total"] == 1
    print("PASS: Linux image health, non-root user, volume persistence after recreation, live JSON/CSV export.")
    print("Smoke-test artifacts:", work)
finally:
    # This randomly named project owns only disposable test volumes.
    run("down", "--volumes")
