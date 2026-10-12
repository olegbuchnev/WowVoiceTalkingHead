"""Isolated HTTP baseline; never connects to the normal voting database."""
import concurrent.futures as futures
import json
import sqlite3
from pathlib import Path
import socket
import subprocess
import time
import urllib.request
import uuid

root=Path(__file__).resolve().parents[3]
work=root/'artifacts'/('vote-load-'+uuid.uuid4().hex[:10])
work.mkdir()
catalogue=root/'data/voice-vote/catalogue.json'
quests=json.loads(catalogue.read_text(encoding='utf-8'))['quests']
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0))
    port=sock.getsockname()[1]
base=f'http://127.0.0.1:{port}'
def request(path,token=None,payload=None):
    headers={'Origin':base,'Content-Type':'application/json'}
    if token: headers['Cookie']=token
    req=urllib.request.Request(base+path,headers=headers,data=None if payload is None else json.dumps(payload).encode())
    start=time.perf_counter()
    with urllib.request.urlopen(req,timeout=60) as response:
        body=json.load(response)
        cookie=response.headers.get('Set-Cookie','').split(';')[0]
    return time.perf_counter()-start,body,cookie

with (work/'server.log').open('w',encoding='utf-8') as log:
    process=subprocess.Popen(['java','-Xmx512m','--enable-native-access=ALL-UNNAMED','-jar',str(root/'server/voice-vote/target/voice-vote-server-0.1.0.jar'),
        f'--server.port={port}',f'--voice-vote.database={work / "votes.sqlite"}',f'--voice-vote.catalogue={catalogue}',
        '--voice-vote.admin-password-file='],stdout=log,stderr=log,creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        for attempt in range(100):
            try:
                request('/api/votes/health');break
            except Exception:
                if process.poll() is not None: raise RuntimeError('Test server exited; see '+str(work/'server.log'))
                time.sleep(.2)
        with futures.ThreadPoolExecutor(max_workers=100) as pool:
            cookies=list(pool.map(lambda _:request('/api/votes/summary')[2],range(100)))
            visits=[str(uuid.uuid4()) for _ in cookies]
            def ballot(i):
                q=quests[i%len(quests)]
                return request('/api/votes/submit',cookies[i],{'questID':q['questID'],'selectedId':q['variants'][0]['id'],
                    'variantIds':[v['id'] for v in q['variants']],'visitID':visits[i]})[0]
            def queue(i): return request('/api/votes/queue',cookies[i])[0]
            def playback(i):
                q=quests[i%len(quests)]
                return request('/api/votes/playback',cookies[i],{'questID':q['questID'],'recordingID':q['variants'][0]['id'],'visitID':visits[i]})[0]
            reports=[]
            for label,operation in [('votes-cold',ballot),('votes-warm',ballot),('queues',queue),('playback',playback),('mixed-votes-and-queues',lambda i:ballot(i) if i%2 else queue(i))]:
                start=time.perf_counter();timings=[];errors=[]
                jobs=[pool.submit(operation,i) for i in range(100)]
                for job in jobs:
                    try:timings.append(job.result())
                    except Exception as error:errors.append(str(error))
                timings.sort()
                report={'phase':label,'requests':100,'errors':len(errors),'seconds':round(time.perf_counter()-start,3),
                    'p50_ms':round(timings[len(timings)//2]*1000,1) if timings else None,
                    'p95_ms':round(timings[int(len(timings)*.95)-1]*1000,1) if timings else None,
                    'max_ms':round(max(timings)*1000,1) if timings else None}
                reports.append(report);print(json.dumps(report),flush=True)
                assert not errors, errors[:3]
                # Accepted requests may still be waiting on the server worker.
                deadline=time.monotonic()+30
                while any(Path(str(work/'votes.sqlite')+'.pending').glob('*.json')):
                    if time.monotonic()>deadline: raise AssertionError('Inbox did not drain')
                    time.sleep(.05)
            with sqlite3.connect('file:'+str(work/'votes.sqlite')+'?mode=ro',uri=True) as db:
                assert db.execute('select count(*) from votes').fetchone()[0]==100
                assert db.execute('select count(*) from visits').fetchone()[0]==100
                print('PASS: 100 visitors, durable async admission, mixed reads/writes, no duplicate votes.',flush=True)
            (work/'results.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
            print('Results:',work,flush=True)
    finally:
        process.terminate()
        try:process.wait(timeout=15)
        except subprocess.TimeoutExpired:process.kill();process.wait()
