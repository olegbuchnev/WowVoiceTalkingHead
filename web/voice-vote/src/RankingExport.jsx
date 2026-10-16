import React,{useRef,useState} from 'react';
import './ranking-export.css';

export function RankingExport() {
  const dialog=useRef(null),field=useRef(null);
  const [bundle,setBundle]=useState(null),[error,setError]=useState(''),[busy,setBusy]=useState(false),[copied,setCopied]=useState(false);
  async function load() {
    setBusy(true);setError('');setCopied(false);setBundle(null);
    try {
      const response=await fetch('/api/votes/ranking/export',{cache:'no-store',signal:AbortSignal.timeout(30000)});
      if(!response.ok) throw Error();
      const data=await response.json(),snapshot=JSON.parse(data.json);
      if(snapshot.schemaVersion!==1 || !Array.isArray(snapshot.groups) || !data.importString?.startsWith('THR1:')) throw Error();
      setBundle({...data,snapshot});
    } catch {setError('Не удалось получить рейтинг. Попробуйте ещё раз.');}
    finally {setBusy(false);}
  }
  function open() {dialog.current.showModal();load();}
  async function copy() {
    try {await navigator.clipboard.writeText(bundle.importString);setCopied(true);}
    catch {field.current.focus();field.current.select();setError('Строка выделена. Скопируйте её вручную: Ctrl+C или меню копирования.');}
  }
  function download() {
    const url=URL.createObjectURL(new Blob([bundle.json],{type:'application/json;charset=utf-8'}));
    const link=document.createElement('a');link.href=url;link.download='addon-voice-ranking.json';link.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  }
  return <>
    <button className="ranking-open" onClick={open}>Рейтинг для аддона</button>
    <dialog className="ranking-dialog" ref={dialog} aria-labelledby="ranking-heading" onClick={event=>{if(event.target===dialog.current)dialog.current.close();}}>
      <div className="ranking-content">
        <div className="ranking-heading"><h2 id="ranking-heading">Рейтинг сообщества</h2><button aria-label="Закрыть рейтинг" onClick={()=>dialog.current.close()}>×</button></div>
        <p>Готовый порядок библиотек для каждой группы раса–пол. Если первой озвучки нет, аддон сможет выбрать следующую.</p>
        <p className="ranking-note">Импорт строки появится в будущей версии аддона. Сейчас можно сохранить результаты.</p>
        {busy && <p role="status">Рассчитываем рейтинг…</p>}
        {error && <p role="alert">{error}</p>}
        {bundle && <>
          <p>Снимок: <time dateTime={bundle.snapshot.generatedAt}>{new Date(bundle.snapshot.generatedAt).toLocaleString('ru-RU')}</time> · Групп: {bundle.snapshot.groups.length}</p>
          <p>С оценками: {bundle.snapshot.groups.filter(g=>g.status!=='no_data').length}. Для групп без оценок используется фиксированный порядок: WowVoice, CatQuest, Wayfarer.</p>
          <div className="ranking-actions"><button onClick={copy}>{copied?'Скопировано':'Скопировать строку'}</button><button onClick={download}>Скачать JSON</button></div>
          <label htmlFor="ranking-string">Строка рейтинга</label>
          <textarea id="ranking-string" ref={field} readOnly value={bundle.importString} spellCheck={false}/>
          {copied && <p role="status">Строка скопирована.</p>}
        </>}
        <button className="ranking-refresh" onClick={load} disabled={busy}>Обновить данные</button>
      </div>
    </dialog>
  </>;
}
