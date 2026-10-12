import React,{useState,useEffect} from 'react';
import {createRoot} from 'react-dom/client';
import './style.css';

const date=value=>value ? new Date(value).toLocaleString('ru-RU') : '—';
const number=value=>Number(value || 0).toLocaleString('ru-RU');
const libraryClass=name=>({WowVoice:'wow',CatQuest:'cat',Wayfarer:'way'}[name] || '');
const sexes={male:'мужчина',female:'женщина'};
const races={human:'Человек',dwarf:'Дворф',gnome:'Гном',goblin:'Гоблин',orc:'Орк',tauren:'Таурен',troll:'Тролль',nightelf:'Ночной эльф',bloodelf:'Эльф крови',scourge:'Нежить',child:'Ребёнок',skyborne:'Небеснорождённый'};
function InboxStatus({inbox}) {
  if(!inbox) return null;
  return <section className="inbox-status"><h2>Сохранение голосов</h2>
    <p><strong>{inbox.pending}</strong> в очереди · <strong>{inbox.processed}</strong> записано после запуска сервера · <strong>{inbox.failures}</strong> ошибок записи · <strong>{inbox.admissionFailures || 0}</strong> ошибок приёма</p>
    <p className="note">Последняя успешная запись: {date(inbox.lastSuccess)}. Самый ранний ожидающий голос: {date(inbox.oldestAt)}.</p>
    {inbox.lastError && <p role="status">Последняя ошибка ({date(inbox.lastFailure)}): {inbox.lastError}{inbox.retrying ? ' · Повторная попытка запланирована.' : ''}</p>}
    {inbox.admissionError && <p role="status">Ошибка приёма ({date(inbox.admissionErrorAt)}): {inbox.admissionError}</p>}
    {!!inbox.quarantined && <p role="status">Требуют проверки: {inbox.quarantined}. Конфликтующие запросы сохранены отдельно и не задерживают остальные голоса.</p>}
    {!!inbox.items.length && <div className="table-wrap"><table><thead><tr><th>Участник</th><th>Задание</th><th>Принято сервером</th></tr></thead><tbody>{inbox.items.map((item,i)=><tr key={i}><td>{item.visitor.slice(0,12)}</td><td>{item.questID}</td><td>{date(item.receivedAt)}</td></tr>)}</tbody></table></div>}
    <p className="note">Принятые голоса хранятся на диске до записи в БД. Здесь показано текущее состояние, независимо от выбранного периода. Запросы, не дошедшие до сервера, неизвестны. Счётчики обработки сбрасываются при перезапуске, очередь сохраняется.</p>
  </section>;
}
function ExportResults() {
  const [busy,setBusy]=useState(''),[error,setError]=useState('');
  async function download(file) {
    setBusy(file);setError('');
    try {
      const response=await fetch(`/api/admin/export/${file}`,{credentials:'same-origin'});
      if(!response.ok) throw Error(response.status===401 ? 'Войдите в админку повторно.' : response.status===429 ? 'Выгрузка уже выполняется. Повторите немного позже.' : 'Не удалось сформировать выгрузку.');
      const url=URL.createObjectURL(await response.blob()),link=document.createElement('a');
      link.href=url;link.download=file;document.body.append(link);link.click();link.remove();
      setTimeout(()=>URL.revokeObjectURL(url),10000);
    } catch(e) {setError(e.message);} finally {setBusy('');}
  }
  return <section className="exports"><h2>Выгрузка результатов</h2><div className="export-buttons">
    {[['results.zip','Всё в ZIP'],['results.json','JSON'],['quests.csv','CSV: задания'],['race-sex.csv','CSV: раса и пол'],['pairwise.csv','CSV: сравнения библиотек']].map(([file,label])=><button key={file} disabled={!!busy} onClick={()=>download(file)}>{busy===file ? 'Подготавливаем…' : label}</button>)}
    </div><p className="note">Все сохранённые голоса за всё время, без ID участников. Фильтр периода не применяется. Голоса в очереди войдут в выгрузку после записи в БД.</p>{error && <p role="alert">{error}</p>}</section>;
}
function App() {
  const [session,setSession]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false);
  const [days,setDays]=useState(30),[offset,setOffset]=useState(0),[search,setSearch]=useState('');
  const [dashboard,setDashboard]=useState(null),[visitors,setVisitors]=useState(null);
  const [selected,setSelected]=useState(null),[detail,setDetail]=useState(null),[voteOffset,setVoteOffset]=useState(0);
  const [revision,setRevision]=useState(0);
  async function api(path,options={}) {
    const response=await fetch('/api/admin'+path,{credentials:'same-origin',...options});
    if(response.status===401) {setSession(null);setDashboard(null);setVisitors(null);setDetail(null);setSelected(null);}
    if(!response.ok) throw Error(response.status===401 ? 'Неверный пароль или сессия истекла.' : response.status===429 ? 'Слишком много попыток. Повторите через минуту.' : 'Не удалось получить данные. Попробуйте ещё раз.');
    return response.json();
  }
  const refreshSession=()=>api('/session').then(setSession).catch(e=>setError(e.message));
  useEffect(()=>{refreshSession();},[]);
  useEffect(()=>{
    if(!session?.authenticated) return;
    let cancelled=false;
    const timer=setInterval(()=>{
      api('/inbox').then(inbox=>{if(!cancelled)setDashboard(old=>old ? {...old,inbox} : old);}).catch(()=>{});
    },5000);
    return ()=>{cancelled=true;clearInterval(timer);};
  },[session?.authenticated]);
  useEffect(()=>{
    if(!session?.authenticated) return;
    let cancelled=false;setBusy(true);setError('');
    Promise.all([api(`/dashboard?days=${days}`),api(`/visitors?days=${days}&offset=${offset}&search=${search}`)])
      .then(([d,v])=>{if(!cancelled){setDashboard(d);setVisitors(v);}}).catch(e=>{if(!cancelled)setError(e.message);})
      .finally(()=>{if(!cancelled)setBusy(false);});
    return ()=>{cancelled=true;};
  },[session?.authenticated,days,offset,search,revision]);
  useEffect(()=>{
    if(!selected || !session?.authenticated) return;
    let cancelled=false;setDetail(null);
    api(`/visitors/${selected}?offset=${voteOffset}`).then(d=>{if(!cancelled)setDetail(d);}).catch(e=>setError(e.message));
    return ()=>{cancelled=true;};
  },[selected,voteOffset,revision,session?.authenticated]);
  async function login(event) {
    event.preventDefault();setBusy(true);setError('');
    const password=new FormData(event.currentTarget).get('password');
    try {
      const fresh=await api('/session');
      await api('/login',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',[fresh.csrfHeader]:fresh.csrf},body:new URLSearchParams({username:'admin',password})});
      await refreshSession();
    } catch(e) {setError(e.message);} finally {setBusy(false);}
  }
  async function logout() {
    try {await api('/logout',{method:'POST',headers:{[session.csrfHeader]:session.csrf}});setDashboard(null);setVisitors(null);setDetail(null);setSelected(null);await refreshSession();}
    catch(e) {setError(e.message);}
  }
  const pagination=(start,total,update)=><div className="pagination"><span>{total ? `${start+1}–${Math.min(start+30,total)} из ${number(total)}` : 'Нет записей'}</span><button disabled={start===0} onClick={()=>update(Math.max(0,start-30))}>Назад</button><button disabled={start+30>=total} onClick={()=>update(start+30)}>Далее</button></div>;
  return <div className="app"><header><a href="/admin/">TalkingHead <span>Ru</span></a><span className="badge">Статистика участия</span>{session?.authenticated && <button onClick={logout}>Выйти</button>}</header>
    {!session?.authenticated ? <main className="login"><div className="eyebrow">ТОЛЬКО ДЛЯ АДМИНИСТРАТОРА</div><h1>Вход в статистику</h1><p>Посетители, голосования и выбор озвучек.</p><form onSubmit={login}><label htmlFor="password">Пароль</label><input id="password" name="password" type="password" autoComplete="current-password" required autoFocus/><button className="primary" disabled={busy}>Войти</button></form>{error && <p role="alert">{error}</p>}</main> :
    <main><div className="title"><div><div className="eyebrow">ОБЗОР</div><h1>Как голосуют посетители</h1></div><div className="controls"><select aria-label="Период" value={days} onChange={e=>{setDays(+e.target.value);setOffset(0);}}><option value={7}>7 дней</option><option value={30}>30 дней</option><option value={90}>90 дней</option><option value={0}>Всё время</option></select><button onClick={()=>setRevision(r=>r+1)} disabled={busy}>Обновить</button></div></div>
      <p className="note">Участник — уникальная cookie хотя бы с одним голосом. Заход с голосом — отдельная сессия, в которой был сохранён выбор: один участник может вернуться несколько раз. Открытие страницы без голосования не учитывается. Дни считаются по UTC.</p>
      {error && <p role="alert">{error}</p>}
      {!dashboard ? <p>Загружаем статистику…</p> : <>
        <div className="metrics">{[['Участников',dashboard.votes.voters],['Заходов с голосом',dashboard.traffic.pageViews],['Сохранённых голосов',dashboard.votes.total],['Голосов на участника',dashboard.votes.voters ? (dashboard.votes.total/dashboard.votes.voters).toFixed(1) : 0]].map(([label,value])=><article key={label}><span>{label}</span><strong>{value}</strong></article>)}</div>
        <InboxStatus inbox={dashboard.inbox}/>
        <ExportResults/>
        <div className="overview"><section><h2>Активность по дням</h2><div className="legend"><span>● Голоса</span><span>○ Заходы с голосом</span></div>{dashboard.daily.length ? <div className="chart">{dashboard.daily.map(d=><div className="day" key={d.day} tabIndex={0} title={`${d.day}: ${d.votes} голосов, ${d.pageViews} заходов`}><div className="bars"><i style={{height:`${Math.max(2,100*d.votes/Math.max(1,...dashboard.daily.map(x=>Math.max(x.votes,x.pageViews))))}%`}}/><b style={{height:`${Math.max(2,100*d.pageViews/Math.max(1,...dashboard.daily.map(x=>Math.max(x.votes,x.pageViews))))}%`}}/></div><small>{d.day.slice(5)}</small></div>)}</div> : <p className="empty">За этот период ещё нет данных.</p>}</section>
        <section><h2>Выбор библиотек</h2>{['WowVoice','CatQuest','Wayfarer'].map(name=>{const count=dashboard.libraries.find(x=>x.source===name)?.votes || 0;return <div className={`library ${libraryClass(name)}`} key={name}><div><span>{name}</span><b>{number(count)}</b></div><div className="track"><i style={{width:`${100*count/Math.max(1,dashboard.votes.total)}%`}}/></div></div>;})}<p className="note">Это сохранённые выборы, включая старые версии записей, а не рейтинг качества.</p></section></div>
        <section><div className="section-heading"><h2>Участники</h2><input aria-label="Поиск по ID" placeholder="Поиск по ID" value={search} onChange={e=>{setSearch(e.target.value.toLowerCase().replace(/[^a-f0-9]/g,'').slice(0,64));setOffset(0);}}/></div><div className="table-wrap"><table><thead><tr><th>ID cookie</th><th>Последнее действие</th><th>Заходы</th><th>Прослушивания</th><th>Голоса за период</th><th>За всё время</th></tr></thead><tbody>{visitors?.items.map(v=><tr key={v.id}><td><button className="link" onClick={()=>{setSelected(v.id);setVoteOffset(0);}}>{v.id.slice(0,12)}</button></td><td>{date(v.lastSeen)}</td><td>{v.visits}</td><td>{v.plays}</td><td>{v.votes}</td><td>{v.lifetimeVotes}</td></tr>)}</tbody></table></div>{visitors && pagination(offset,visitors.total,setOffset)}</section>
        <p className="note">Аналитика заходов включена {date(dashboard.analyticsSince)}. Старые голоса сохранены; посещения для них не восстанавливаются. Повторный выбор в том же сравнении заменяет предыдущий голос.</p>
      </>}
      {selected && <div className="modal-backdrop" onClick={()=>setSelected(null)}><section className="detail" role="dialog" aria-modal="true" aria-label="Карточка участника" onClick={e=>e.stopPropagation()}><div className="section-heading"><div><div className="eyebrow">УЧАСТНИК</div><h2>{selected.slice(0,12)}</h2></div><button onClick={()=>setSelected(null)} autoFocus>Закрыть</button></div>{!detail ? <p>Загружаем…</p> : <><p>Сохранено голосов: <strong>{detail.summary.total}</strong></p><div className="detail-libraries">{Object.entries(detail.summary.counts).map(([name,count])=><span key={name} className={libraryClass(name)}>{name}: {count}</span>)}</div><h3>Последние 30 заходов с голосом</h3><div className="table-wrap"><table><thead><tr><th>Первый голос в заходе</th><th>Последнее действие</th><th>Записи</th><th>Голоса</th></tr></thead><tbody>{detail.visits.map(v=><tr key={v.id}><td>{date(v.openedAt)}</td><td>{date(v.lastSeen)}</td><td>{v.plays}</td><td>{v.votes}</td></tr>)}</tbody></table></div><h3>Выборы по заданиям</h3><div className="table-wrap"><table><thead><tr><th>Задание</th><th>Говорящий</th><th>Выбор</th><th>Последнее изменение</th></tr></thead><tbody>{detail.votes.map((v,i)=><tr key={i}><td>{v.questID}</td><td>{races[v.race] || v.race || 'Неизвестно'} · {sexes[v.sex] || '—'}</td><td className={libraryClass(v.source)} title={`SHA-256: ${v.sha256}`}>{v.source} <small>{v.version}</small></td><td>{date(v.updatedAt)}</td></tr>)}</tbody></table></div>{pagination(voteOffset,detail.summary.total,setVoteOffset)}<p className="note">Прослушивание — запуск отдельной записи. Повторные запуски той же записи в одном заходе не увеличивают счётчик. Дослушивание до конца не измеряется.</p></>}</section></div>}
    </main>}
  </div>;
}
createRoot(document.getElementById('root')).render(<App/>);
