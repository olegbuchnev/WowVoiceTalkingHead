import React, {useEffect,useRef,useState} from 'react';
import {libraries} from './vote-history.js';
import './community-results.css';

const integer=new Intl.NumberFormat('ru-RU');
const percent=new Intl.NumberFormat('ru-RU',{style:'percent',maximumFractionDigits:1});
function sector(start,fraction) {
  const point=angle=>[180+146*Math.sin(angle),180-146*Math.cos(angle)];
  const [x1,y1]=point(start*2*Math.PI),[x2,y2]=point((start+fraction)*2*Math.PI);
  return `M180 180 L${x1} ${y1} A146 146 0 ${fraction>0.5?1:0} 1 ${x2} ${y2} Z`;
}

export default function CommunityResults() {
  const [hovered,setHovered]=useState(null),[focused,setFocused]=useState(null),[pinned,setPinned]=useState(null);
  const selected=hovered ?? focused ?? pinned;
  const pointerType=useRef(null);
  const pointerDown=event=>{
    pointerType.current=event.pointerType;
    if(event.pointerType!=='touch') {
      // Mouse clicks must not leave focus or a pinned tooltip behind.
      event.preventDefault();event.currentTarget.blur();setFocused(null);setPinned(null);
    }
  };
  const activate=(event,index)=>{
    if(pointerType.current!=='touch' || event.detail===0) return;
    setPinned(pinned===index?null:index);
    setFocused(null);event.currentTarget.blur();
  };
  const [summary,setSummary]=useState(null),[failed,setFailed]=useState(false),[attempt,setAttempt]=useState(0);
  useEffect(()=>{
    const restored=event=>{if(event.persisted)setAttempt(value=>value+1);};
    window.addEventListener('pageshow',restored);
    return ()=>window.removeEventListener('pageshow',restored);
  },[]);
  useEffect(()=>{
    const controller=new AbortController();setFailed(false);
    fetch('/api/votes/community',{cache:'no-store',credentials:'omit',signal:AbortSignal.any([controller.signal,AbortSignal.timeout(15000)])})
      .then(async response=>{
        if(!response.ok) throw Error('Community results unavailable');
        const data=await response.json();
        if(!Number.isSafeInteger(data.total) || data.total<0 || !libraries.every(name=>Number.isSafeInteger(data.counts?.[name]) && data.counts[name]>=0)
          || libraries.reduce((sum,name)=>sum+data.counts[name],0)!==data.total) throw Error('Invalid community results');
        if(!controller.signal.aborted) setSummary(data);
      }).catch(()=>{if(!controller.signal.aborted)setFailed(true);});
    return ()=>controller.abort();
  },[attempt]);
  let offset=0;
  return <section className="community-results" aria-label="Результаты сравнений">
    <p className="community-subtitle">Всё ещё собираем достаточно данных. Спасибо, что голосуете!</p>
    {failed ? <div className="community-message" role="status">Не удалось загрузить результаты.
      <button type="button" onClick={()=>setAttempt(value=>value+1)}>Попробовать ещё раз</button></div>
      : !summary ? <p className="community-message" role="status">Загружаем результаты…</p>
      : summary.total===0 ? <p className="community-message">Пока нет результатов. Начните сравнение и сделайте первый выбор.</p>
      : <div className="community-body" onPointerLeave={()=>setHovered(null)} onKeyDown={event=>{
        if(event.key==='Escape') {setHovered(null);setPinned(null);event.currentTarget.querySelector(':focus')?.blur();}
      }}>
        <svg className="community-pie" viewBox="0 0 360 360" role="group" aria-label="Результаты по библиотекам. Выберите сектор, чтобы узнать подробности.">
          {libraries.map((name,i)=>{
            const fraction=summary.counts[name]/summary.total,start=offset;offset+=fraction;
            if(fraction===0) return null;
            const angle=(start+fraction/2)*2*Math.PI,active=selected===i;
            const x=Math.sin(angle),y=-Math.cos(angle);
            // Place the label at the area centroid, rather than on a fixed ring.
            const labelRadius=2*146*Math.sin(Math.PI*fraction)/(3*Math.PI*fraction);
            const shape=fraction===1?<circle cx="180" cy="180" r="146"/>:<path d={sector(start,fraction)}/>;
            return <g key={name} className={`community-sector library-${i}${active?' is-selected':''}`}
              role="button" tabIndex="0" aria-pressed={active} aria-label={`${name}: выиграно сравнений — ${integer.format(summary.counts[name])}, ${percent.format(fraction)} от всех сравнений`}
              onPointerEnter={event=>{if(event.pointerType!=='touch') {setHovered(i);setPinned(null);}}}
              onPointerLeave={event=>{if(event.pointerType!=='touch')setHovered(null);}}
              onPointerDown={pointerDown}
              onFocus={()=>setFocused(i)} onBlur={()=>setFocused(null)}
              onClick={event=>activate(event,i)}
              onKeyDown={event=>{if(event.key==='Enter'||event.key===' ') {event.preventDefault();setFocused(i);}}}>
              <g className="community-sector-hit">{shape}</g>
              <g className="community-sector-visual" style={{'--sector-x':`${x*9}px`,'--sector-y':`${y*9}px`}}>
                {shape}
                {fraction>=0.12 && <text x={180+x*labelRadius} y={180+y*labelRadius} className="community-sector-label" textAnchor="middle" dominantBaseline="central">{name}</text>}
              </g>
            </g>;
          })}
        </svg>
        {libraries.some(name=>summary.counts[name]/summary.total<0.12) && <div className="community-small-sectors">
          {libraries.map((name,i)=>summary.counts[name]/summary.total<0.12 && <button type="button" key={name}
            className={`library-${i}`} aria-pressed={selected===i} onPointerEnter={event=>{if(event.pointerType!=='touch') {setHovered(i);setPinned(null);}}}
            onPointerLeave={event=>{if(event.pointerType!=='touch')setHovered(null);}} onPointerDown={pointerDown}
            onFocus={()=>setFocused(i)} onBlur={()=>setFocused(null)} onClick={event=>activate(event,i)}>{name}</button>)}
        </div>}
        <div className={`community-detail-slot${selected!==null?' is-visible':''}`} aria-live="polite" aria-atomic="true">
          {selected!==null && <div className={`community-detail library-${selected}`}>
            <h3>{libraries[selected]}</h3>
            <p className="community-share">{percent.format(summary.counts[libraries[selected]]/summary.total)}</p>
            <p className="community-share-caption">от всех сравнений</p>
            <p className="community-selected-count">Выиграно сравнений: {integer.format(summary.counts[libraries[selected]])}</p>
            <p className="community-base">Всего сравнений: {integer.format(summary.total)}</p>
          </div>}
        </div>
      </div>}

  </section>;
}
