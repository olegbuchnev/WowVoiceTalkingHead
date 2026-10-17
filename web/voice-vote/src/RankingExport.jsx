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
  return <>
    <button className="ranking-open" onClick={open}>Импорт в аддон</button>
    <dialog className="ranking-dialog" ref={dialog} aria-labelledby="ranking-heading" onClick={event=>{if(event.target===dialog.current)dialog.current.close();}}>
      <div className="ranking-content">
        <div className="ranking-heading"><h2 id="ranking-heading">Импорт рейтинга в аддон</h2><button aria-label="Закрыть рейтинг" onClick={()=>dialog.current.close()}>×</button></div>
        <p>Скопируйте строку и вставьте её в аддоне: Опции → Выбор озвучки → Озвучка по расе и полу → Импортировать строку.</p>
        <p className="ranking-note">Нужна версия аддона с импортом рейтинга. Личный порядок для отдельных сочетаний сохранится. При равных оценках используется ваш порядок библиотек.</p>
        {busy && <p role="status">Рассчитываем рейтинг…</p>}
        {error && <p role="alert">{error}</p>}
        {bundle && <>
          <p>Снимок: <time dateTime={bundle.snapshot.generatedAt}>{new Date(bundle.snapshot.generatedAt).toLocaleString('ru-RU')}</time> · Групп: {bundle.snapshot.groups.length}</p>
          <p>С оценками: {bundle.snapshot.groups.filter(g=>g.status!=='no_data').length}. Для групп без оценок используется ваш порядок библиотек из настроек аддона.</p>
          <div className="ranking-actions"><button className="ranking-copy" onClick={copy} aria-live="polite">
            <span style={{visibility:copied?'hidden':'visible'}} aria-hidden={copied}>Скопировать строку</span>
            <span style={{visibility:copied?'visible':'hidden'}} aria-hidden={!copied}>Скопировано</span>
          </button></div>
          <label htmlFor="ranking-string">Строка рейтинга</label>
          <textarea id="ranking-string" ref={field} readOnly value={bundle.importString} spellCheck={false}/>
        </>}
        <button className="ranking-refresh" onClick={load} disabled={busy}>Обновить данные</button>
      </div>
    </dialog>
  </>;
}
