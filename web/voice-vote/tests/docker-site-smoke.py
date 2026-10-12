"""Exercise the complete site through Nginx on an isolated Docker network."""
import http.cookiejar
import json
import os
from pathlib import Path
import socket
import subprocess
import time
import urllib.request
import urllib.error
import urllib.parse
import uuid

repo=Path(__file__).resolve().parents[3]
work=repo/'artifacts'/('site-smoke-'+uuid.uuid4().hex[:10]);work.mkdir()
password=uuid.uuid4().hex
(work/'admin-password.txt').write_text(password)
libraries=subprocess.check_output(['node','--input-type=module','-e',"import {addonsDirectory} from './web/voice-vote/server.mjs'; console.log(addonsDirectory())"],cwd=repo,text=True).strip()
with socket.socket() as listener:
    listener.bind(('127.0.0.1',0));port=listener.getsockname()[1]
env={**os.environ,'VOICE_VOTE_WEB_PORT':str(port),'VOICE_VOTE_CATALOGUE_DIR':str(repo/'artifacts/voice-vote-deploy/catalogue'),
    'VOICE_VOTE_LIBRARIES_DIR':libraries,'VOICE_VOTE_SECURE_COOKIE':'false','VOICE_VOTE_ADMIN_PASSWORD_FILE':str(work/'admin-password.txt')}
compose=['docker','compose','-p',work.name,'-f',str(repo/'web/voice-vote/compose.yaml')]
def run(*args):
    result=subprocess.run([*compose,*args],env=env,capture_output=True,text=True,timeout=180)
    if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    return result.stdout.strip()
base=f'http://127.0.0.1:{port}'
browser=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
def get(path,headers=None,body=None):
    return browser.open(urllib.request.Request(base+path,data=body,headers=headers or {}),timeout=45)
def js(path,body=None):
    with get(path,{'Origin':base,'Content-Type':'application/json','Sec-Fetch-Site':'same-origin'},None if body is None else json.dumps(body).encode()) as r:return json.load(r)
try:
    run('up','-d','--no-build','--wait','--wait-timeout','150')
    api_container=run('ps','-q','api')
    bindings=json.loads(subprocess.check_output(['docker','inspect',api_container],text=True))[0]['HostConfig']['PortBindings']
    assert not bindings, 'Java must have no published port'
    with get('/') as r: assert b'TalkingHead Ru' in r.read()
    catalogue=js('/api/catalogue');assert len(catalogue['quests'])>3000
    quest=catalogue['quests'][0];variant=quest['variants'][0]
    with get(variant['url'],{'Range':'bytes=0-63'}) as r:
        assert r.status==206 and len(r.read())==64
    with get('/api/portrait-camera/878772') as r: assert json.load(r)['profile']['key']=='dwarf'
    with get('/modelviewer/live/viewer/viewer.min.js') as r: assert b'1.0 / 2.2' in r.read()
    for headers in [{'Origin':'https://foreign.example'}, {'Sec-Fetch-Site':'cross-site'}, {'Sec-Fetch-Site':'same-site'}]:
        try:get('/api/votes/summary',headers);raise AssertionError('Foreign request was accepted')
        except urllib.error.HTTPError as e:assert e.code==403
    req=urllib.request.Request(base+'/api/votes/submit',method='OPTIONS',headers={'Origin':'https://foreign.example','Access-Control-Request-Method':'POST'})
    try:browser.open(req);raise AssertionError('Foreign preflight was accepted')
    except urllib.error.HTTPError as e:assert e.code==403 and not e.headers.get('Access-Control-Allow-Origin')
    assert js('/api/votes/summary')['total']==0
    ballot={'questID':quest['questID'],'selectedId':variant['id'],'variantIds':[v['id'] for v in quest['variants']],'visitID':str(uuid.uuid4())}
    assert js('/api/votes/submit',ballot)['state']=='queued'
    deadline=time.monotonic()+15
    while js('/api/votes/summary')['total']!=1:
        assert time.monotonic()<deadline;time.sleep(.1)
    try:get('/api/admin/export/results.json');raise AssertionError('Export must require login')
    except urllib.error.HTTPError as e:assert e.code==401
    session=js('/api/admin/session')
    with get('/api/admin/login',{'Content-Type':'application/x-www-form-urlencoded',session['csrfHeader']:session['csrf'],'Origin':base},urllib.parse.urlencode({'username':'admin','password':password}).encode()) as r:assert json.load(r)['authenticated']
    with get('/api/admin/export/results.json') as r:assert json.load(r)['summary']['votes']==1
    with get('/api/admin/export/results.zip') as r:assert r.read().startswith(b'PK')
    print('PASS: React, Nginx, catalogue, external audio ranges, camera, viewer, same-origin protection, private API, voting and protected downloads.')
finally:
    (work/'containers.log').write_text(run('logs','--no-color'),encoding='utf-8')
    run('down','--volumes')
