import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { createPortrait, isPortraitLoaded, setTalking, framePortrait, portraitStatus } from './model.js';
import { useQuestScroll } from './use-quest-scroll.js';
import { libraries } from './vote-history.js';
import {loadSummary, loadQueue, migrateLocalVotes} from './vote-api.js';
import {sessionSummary} from './session-votes.js';
import { createComparisonBatch } from './comparison-queue.js';
import {createCompletionMessages} from './completion-messages.js';
import {createParticipationTracker} from './participation.js';
import {createVoteDelivery} from './vote-delivery.js';
import {createCatalogueClient,comparisonKey,questKey,refreshComparisons,withLocalRatings} from './catalogue-refresh.js';
import {watchPortraitReadiness} from './portrait-readiness.js';
import {createAudioPreloader} from './audio-preload.js';
import {observePortrait} from './portrait-diagnostics.js';
import {readVolume,readPreviousVolume,saveVolume} from './volume-preference.js';
import './style.css';

// A reload starts a fresh, silent sample. Browser scroll restoration must not
// restore an old position inside its asynchronously mounted quest text.
history.scrollRestoration = 'manual';

const letters = ['А','Б','В'];
function Icon({stop=false}) { return <svg viewBox="0 0 24 24" aria-hidden="true">{stop ? <rect x="6" y="6" width="12" height="12" rx="1"/> : <path d="M8 4.5v15l12-7.5z"/>}</svg>; }

function VolumeControl({value,onChange,onToggleMute}) {
  const panel=useRef(null),current=useRef({value,onChange});
  current.current={value,onChange};
  useEffect(()=>{
    const element=panel.current;
    const adjust=event=>{
      if(event.ctrlKey || event.metaKey || !event.deltaY) return;
      event.preventDefault();
      const next=Math.max(0,Math.min(100,current.current.value-Math.sign(event.deltaY)*5));
      current.current.value=next;
      current.current.onChange(next);
    };
    // React's delegated wheel listener is passive; cancel page scrolling here.
    element.addEventListener('wheel',adjust,{passive:false});
    return ()=>element.removeEventListener('wheel',adjust);
  },[]);
  return <div className="volume-control" ref={panel}>
    <button type="button" className="volume-mute" aria-label={value>0 ? 'Выключить звук' : 'Включить звук'} title={value>0 ? 'Выключить звук' : 'Включить звук'} onClick={onToggleMute}>
      <svg viewBox="0 0 24 24" aria-hidden="true">
        <path d="M11 5 6 9H3v6h3l5 4Z"/>
        {value>0 && <>
          <path d="M12.83 8.79A5 5 0 0 1 12.83 15.21"/>
          <path className={value<=33 ? 'volume-wave-inactive' : undefined} d="M15.13 6.86A8 8 0 0 1 15.13 17.14"/>
          <path className={value<=66 ? 'volume-wave-inactive' : undefined} d="M17.43 4.93A11 11 0 0 1 17.43 19.07"/>
        </>}
        {value===0 && <path d="m16 9 6 6m0-6-6 6"/>}
      </svg>
    </button>
    <input id="voice-volume" aria-label="Громкость" type="range" min="0" max="100" step="1" value={value} data-muted={value===0} aria-valuetext={`${value}%`} onChange={event=>onChange(Number(event.target.value))}/>
    <output htmlFor="voice-volume">{value}%</output>
  </div>;
}

function PlaybackProgress({audio, duration, position, playing}) {
  const fill = useRef(null);
  useEffect(() => {
    let frame;
    const draw = () => {
      const elapsed = audio.current?.currentTime ?? position;
      const ratio = Number.isFinite(duration) && duration > 0
        ? Math.max(0, Math.min(1, elapsed / duration)) : 0;
      fill.current.style.transform = `scaleX(${ratio})`;
      if (playing) frame = requestAnimationFrame(draw);
    };
    // Read the audio clock every frame; timeupdate alone arrives too sparsely.
    // Update only this transform, without rendering the whole app every frame.
    draw();
    return () => cancelAnimationFrame(frame);
  }, [audio, duration, position, playing]);
  return <div className="progress" aria-hidden="true"><div ref={fill}/></div>;
}

function Portrait({npc, questID, playing, current}) {
  const element = useRef(), viewer = useRef(), playback = useRef(playing);
  const recovery = useRef({displayID:npc.displayID,attempts:0});
  const [state, setState] = useState('loading');
  const [cameraRevision, setCameraRevision] = useState(0);
  playback.current = playing;
  useEffect(() => {
    if (!import.meta.hot) return;
    const refresh = () => setCameraRevision(value=>value+1);
    import.meta.hot.on('portrait-camera-changed',refresh);
    return () => import.meta.hot.off('portrait-camera-changed',refresh);
  }, []);
  useEffect(() => {
    let cancelled = false, contextLost = false, recoveryTimer, stopWatching=()=>{};
    if (!npc.displayID) {setState('unavailable');return;}
    if(recovery.current.displayID!==npc.displayID) recovery.current={displayID:npc.displayID,attempts:0};
    const diagnostics=observePortrait({questID,npc});
    element.current.dataset.loadId=diagnostics.loadID;
    const controller=new AbortController();
    const container=element.current;
    const lost=event=>{
      if(cancelled || contextLost) return;
      event.preventDefault();
      contextLost=true;
      stopWatching();controller.abort();
      setState('error');diagnostics.report('context-lost',portraitStatus(viewer.current));
      // Rebuild only the portrait; preserve audio, the comparison and votes.
      // A persistent GPU failure must not create an endless remount loop.
      if(recovery.current.attempts<2) {
        recovery.current.attempts++;
        recoveryTimer=setTimeout(()=>{if(!cancelled) setCameraRevision(value=>value+1);},1000);
      }
    };
    container.addEventListener('webglcontextlost',lost,true);
    setState('loading');
    createPortrait(element.current, npc).then(instance => {
      if (cancelled || contextLost) { instance.destroy(); return; }
      viewer.current = instance;
      diagnostics.mark('viewerMs');
      // Wait for model data, not merely creation of the WebGL canvas.
      stopWatching=watchPortraitReadiness({
        isReady:()=>isPortraitLoaded(instance),
        onError:error=>{setState('error');diagnostics.report(error ? 'assets-error' : 'timeout',portraitStatus(instance));},
        onReady:()=>{
          diagnostics.mark('assetsReadyMs');
          framePortrait(instance,controller.signal).then(()=>{
            if(cancelled || contextLost) return;
            diagnostics.mark('cameraMs');
            setTalking(instance, playback.current);
            // Let the renderer draw the configured camera/light/pose before
            // revealing the canvas. The scroll covers all intermediate views.
            requestAnimationFrame(()=>requestAnimationFrame(()=>{
              if (!cancelled && !contextLost) {setState('ready');diagnostics.mark('visibleMs');diagnostics.ready();}
            }));
          }).catch(()=>{if(!cancelled && !contextLost) {setState('error');diagnostics.report('camera-error',portraitStatus(instance));}});
        },
      });
    }).catch(() => { if (!cancelled) {setState('error');diagnostics.report('viewer-error');} });
    return () => { cancelled = true; clearTimeout(recoveryTimer); container.removeEventListener('webglcontextlost',lost,true); controller.abort(); stopWatching(); diagnostics.stop(); viewer.current?.destroy(); viewer.current = null; };
  }, [npc.displayID, cameraRevision]);
  useEffect(()=>{
    if(!current) return;
    const debug=document.getElementById('portrait-debug');
    if(!debug) return;
    debug.textContent=JSON.stringify({questID,npcID:npc.id || 0,displayID:npc.displayID || 0,
      modelFileID:npc.modelFileID || 0,state,loadID:element.current?.dataset.loadId || ''});
  },[current,questID,npc.displayID,state,cameraRevision]);
  useEffect(() => { setTalking(viewer.current, playing); }, [playing]);
  return <div className="portrait"><div className="portrait-well"/><div className="model-clip"><div ref={element} className="model" data-model-state={state}/></div><div className="portrait-frame"/>
    {state !== 'ready' && <div className="portrait-placeholder" role="img" aria-label={state === 'loading' ? 'Загрузка портрета' : 'Портрет недоступен'} title={state === 'error' ? 'Модель недоступна' : undefined}><img src="/portrait-placeholder.png" alt=""/></div>}</div>;
}

function VoteStats({summary}) {
  if (!summary) return null;
  const {counts,total}=summary;
  return <section className="vote-stats" aria-labelledby="vote-stats-title">
    <div className="stats-heading"><h2 id="vote-stats-title">Ваши предпочтения</h2><span>Всего выборов: {total}</span></div>
    <div className="stats-bars">{libraries.map((name,i)=>{
      const percent=total ? counts[name]/total*100 : 0;
      return <div className={`stats-row library-${i}`} key={name}>
        <span className="stats-name">{name}</span><div className="stats-track" aria-hidden="true"><div style={{width:`${percent}%`}}/></div>
        <span className="stats-value">{counts[name]} <span>· {Math.round(percent)}%</span></span>
      </div>;
    })}</div>
    {!total && <p>Выберите голос — здесь появится ваша статистика.</p>}
  </section>;
}

function App() {
  const [participation]=useState(()=>createParticipationTracker());
  const localRated=useRef(new Set());
  const refreshAction=useRef(null),mounted=useRef(true),navigation=useRef(false);
  const [catalogueClient]=useState(()=>createCatalogueClient());
  const [delivery]=useState(()=>createVoteDelivery({
    onAccepted:()=>participation.confirmed(),
    onObsolete:ballot=>{
      localRated.current.delete(comparisonKey(ballot.questID,ballot.variantIds));
      return refreshAction.current?.();
    },
  }));
  useEffect(()=>{
    const refresh=()=>{if(!document.hidden) refreshAction.current?.().catch(()=>{});};
    const retry=()=>{delivery.retry();refresh();};
    window.addEventListener('online',retry);
    window.addEventListener('focus',refresh);
    document.addEventListener('visibilitychange',refresh);
    const timer=setInterval(refresh,60000);
    return ()=>{
      mounted.current=false;clearInterval(timer);
      window.removeEventListener('online',retry);window.removeEventListener('focus',refresh);
      document.removeEventListener('visibilitychange',refresh);delivery.stop();participation.stop();
    };
  },[delivery]);
  const [started, setStarted] = useState(false);
  const [finished, setFinished] = useState(false), [preparing,setPreparing]=useState(false);
  const [batchIndex,setBatchIndex]=useState(0), [ratedQuestIDs,setRatedQuestIDs]=useState([]);
  const [thankYou,setThankYou]=useState('');
  const [messages]=useState(()=>createCompletionMessages());
  const comparisonTitle = useRef(null);
  useEffect(() => { if(started) window.scrollTo(0,0); }, [started]);
  useEffect(() => {
    if (started) {
      comparisonTitle.current?.focus({preventScroll:true});
    }
  }, [started,finished]);
  useEffect(() => {
    const preventSelectAll = event => {
      if ((event.ctrlKey || event.metaKey) && event.code === 'KeyA') event.preventDefault();
    };
    window.getSelection()?.removeAllRanges();
    document.addEventListener('keydown', preventSelectAll);
    return () => document.removeEventListener('keydown', preventSelectAll);
  }, []);
  const [catalogue, setCatalogue] = useState(null), [error, setError] = useState('');
  const [comparisons, setComparisons] = useState([]);
  const [preparedBatch,setPreparedBatch]=useState(null);
  const portraitSequence=useRef(0), preparation=useRef(null),currentIndex=useRef(batchIndex),previousCatalogue=useRef(null);
  currentIndex.current=batchIndex;
  const [advancing,setAdvancing]=useState(false);
  const reserveBatch=(data,priorities,options)=>createComparisonBatch(data.quests,priorities,options)
    .map(entry=>({...entry,key:++portraitSequence.current}));
  async function refreshCatalogue() {
    const data=await catalogueClient.load();
    if(mounted.current) setCatalogue(data);
    return data;
  }
  refreshAction.current=refreshCatalogue;
  useEffect(()=>{
    if(!catalogue) return;
    const previous=previousCatalogue.current;
    previousCatalogue.current=catalogue;
    if(!previous) return;
    const oldKeys=new Map(previous.quests.map(q=>[q.questID,questKey(q)]));
    const unchanged=new Set(catalogue.quests.filter(q=>oldKeys.get(q.questID)===questKey(q)).map(q=>q.questID));
    setRatedQuestIDs(old=>old.filter(id=>unchanged.has(id)));
    setComparisons(old=>refreshComparisons(old,catalogue.quests,started ? currentIndex.current+1 : 0));
    setPreparedBatch(old=>old && refreshComparisons(old,catalogue.quests));
  },[catalogue]);
  const quest=comparisons[batchIndex]?.quest, variants=comparisons[batchIndex]?.variants || [];
  // After reload an exhausted catalogue has no batch. Use its first quest only
  // to size the inert layout, without loading a portrait or starting a replay.
  const layoutQuest=quest || catalogue?.quests[0];
  const layoutVariants=quest ? variants : layoutQuest?.variants || [];
  const nextBatchSize=Math.min(5,catalogue?.quests.filter(q=>!ratedQuestIDs.includes(q.questID)).length || 0);
  const [active, setActive] = useState(null), [playing, setPlaying] = useState(false);
  const [position, setPosition] = useState(0), [length, setLength] = useState(0);
  const [heard, setHeard] = useState([]), [choice, setChoice] = useState(null);
  const [sessionVotes, setSessionVotes] = useState({});
  const summary=sessionSummary(sessionVotes);
  const submitting=useRef(false), initialized=useRef(null);
  const audio = useRef(null), sequence = useRef(0), scroll = useRef(null);
  const [volume,setVolume]=useState(readVolume);
  const [initialPreviousVolume]=useState(readPreviousVolume);
  const previousVolume=useRef(initialPreviousVolume);
  useEffect(()=>{if(audio.current) audio.current.volume=volume/100;},[volume]);
  function changeVolume(value) {
    if(value>0) previousVolume.current=value;
    if(audio.current) audio.current.volume=value/100;
    setVolume(value);saveVolume(value,previousVolume.current);
  }
  const [audioPreloader]=useState(()=>createAudioPreloader());
  useEffect(()=>{
    const entries=finished ? (preparedBatch || []).slice(0,1) : comparisons.slice(batchIndex,batchIndex+2);
    audioPreloader.retain(entries.flatMap(entry=>entry.variants));
  },[audioPreloader,comparisons,batchIndex,finished,preparedBatch]);
  useEffect(()=>()=>audioPreloader.dispose(),[audioPreloader]);
  const stop = () => { sequence.current++; if (audio.current) { audio.current.pause(); audio.current.removeAttribute('src'); audio.current.load(); } setPlaying(false); };
  useEffect(() => {
    const controller = new AbortController();
    initialized.current=loadSummary().then(()=>{void migrateLocalVotes().catch(()=>{});return loadQueue();});
    const history=initialized.current.catch(()=>{
      if(!controller.signal.aborted) setError('История оценок недоступна: возможны повторы квестов.');
      return [];
    });
    catalogueClient.load()
      .then(async data => {
        const rated=await history;
        if(controller.signal.aborted) return;
        setCatalogue(data);
        if (data.quests.length) {
          const batch=createComparisonBatch(data.quests,rated).map(entry=>({...entry,key:++portraitSequence.current}));
          setRatedQuestIDs(rated.filter(p=>p.rated).map(p=>p.questID));
          setComparisons(batch); setFinished(batch.length===0);
        } else setError('Для сравнения нужны хотя бы две установленные библиотеки с проверенными записями.');
      })
      .catch(e => {if (e.name !== 'AbortError') setError(e.message);});
    return () => { controller.abort(); audio.current?.pause(); };
  }, []);
  useEffect(()=>{
    if(finished && nextBatchSize>0) prepareBatch().catch(()=>{});
  },[finished,catalogue]);
  useQuestScroll(scroll, audio, quest?.questID, length, position, playing);
  async function play(variant) {
    if(finished || choice || submitting.current) return;
    if (active?.id === variant.id && playing) { stop(); return; }
    stop(); const token = sequence.current;
    setError(''); setActive(variant); setPosition(0); setLength(variant.duration);
    audio.current.src=audioPreloader.source(variant);
    try { await audio.current.play(); if (sequence.current === token) {setPlaying(true); setHeard(old => [...new Set([...old,variant.id])]);participation.played(quest.questID,variant.id);} }
    catch (e) { if (sequence.current === token && e.name !== 'AbortError') setError('Не удалось воспроизвести запись. Проверьте, что библиотека установлена.'); }
  }
  async function next() {
    if(!choice || finished || navigation.current) return;
    navigation.current=true;setAdvancing(true);
    try {
      const data=await refreshCatalogue();
      const updated=refreshComparisons(comparisons,data.quests,batchIndex+1);
      setComparisons(updated);
      if(batchIndex+1>=updated.length) {setThankYou(messages.next());setFinished(true);return;}
      submitting.current=false;stop(); setChoice(null); setActive(null); setPosition(0); setLength(0); setHeard([]); setError('');
      if(scroll.current) scroll.current.scrollTop=0;
      // Preserve the preloaded portrait and blind order if they are still valid.
      setBatchIndex(old=>old+1);
    } catch(error) {setError(error.message);}
    finally {navigation.current=false;setAdvancing(false);}
  }
  function prepareBatch(repeat=false) {
    if(preparation.current) return preparation.current;
    setPreparing(true);setError('');
    preparation.current=(async()=>{
      await loadSummary();
      await refreshCatalogue();
      const queue=await loadQueue();
      // A focus/poll refresh may finish while queue priorities are in flight.
      const data=catalogueClient.current();
      const priorities=withLocalRatings(queue,data.quests,localRated.current);
      const batch=reserveBatch(data,priorities,{repeat,previousQuestID:quest?.questID});
      setRatedQuestIDs(priorities.filter(p=>p.rated).map(p=>p.questID));
      setPreparedBatch(batch);
      return batch;
    })().catch(error=>{
      setError(error.message || 'Не удалось подготовить сравнения. Попробуйте ещё раз.');
      throw error;
    }).finally(()=>{preparation.current=null;setPreparing(false);});
    return preparation.current;
  }
  async function beginBatch(repeat=false) {
    if(navigation.current) return;
    navigation.current=true;setAdvancing(true);
    try {
      const data=await refreshCatalogue();
      const ready=preparedBatch && refreshComparisons(preparedBatch,data.quests);
      const batch=ready?.length ? ready : await prepareBatch(repeat);
      submitting.current=false;stop();setChoice(null);setActive(null);setPosition(0);setLength(0);setHeard([]);
      setComparisons(batch);setBatchIndex(0);setFinished(batch.length===0);
      setPreparedBatch(null);
    } catch(error) {setError(error.message);}
    finally {navigation.current=false;setAdvancing(false);}
  }
  function vote(variant) {
    if(finished || choice || submitting.current || heard.length<2 || !heard.includes(variant.id)) return;
    submitting.current=true;stop();setError('');
    // Feedback and navigation never wait for network or database completion.
    const key=comparisonKey(quest.questID,variants.map(v=>v.id));
    localRated.current.add(key);
    setSessionVotes(old=>({...old,[key]:variant.source}));
    setChoice(variant.source);setActive(null);
    setRatedQuestIDs(old=>[...new Set([...old,quest.questID])]);
    if(batchIndex+1===comparisons.length) {setThankYou(messages.next());setFinished(true);}
    delivery.enqueue({questID:quest.questID,selectedId:variant.id,variantIds:variants.map(v=>v.id),visitID:participation.visitID});
    void refreshCatalogue().catch(()=>{});
  }
  const completion=finished && <section className="batch-complete" aria-label="Серия завершена">
        {!choice && <h1 id="batch-complete-title" ref={comparisonTitle} tabIndex={-1}>Все доступные задания уже оценены</h1>}
        {comparisons.length>0 && <p className="completion-message">{thankYou}</p>}
        {!nextBatchSize && comparisons.length>0 && <p>Вы оценили все доступные задания.</p>}
        <button className="welcome-start continue-batch" disabled={preparing || advancing} aria-busy={preparing || advancing} onClick={()=>beginBatch(nextBatchSize===0)}>{nextBatchSize ? `Сравнить ещё ${nextBatchSize}` : 'Сравнить повторно'}</button>
      </section>;
  return <div className="app"><header><a className="brand" href="/" aria-label="TalkingHead Ru"><img className="brand-icon" src="/addon-icon-cutout.png" width="48" height="48" alt=""/><span className="brand-text"><span>TalkingHead <b>Ru</b></span><span className="brand-tagline">Озвучки на выбор</span></span></a><a className="curseforge-button" href="https://www.curseforge.com/wow/addons/talkinghead-ru" target="_blank" rel="noopener noreferrer"><span className="curseforge-button-label">Аддон на CurseForge</span><svg aria-hidden="true" focusable="false" viewBox="0 0 24 24" width="18" height="18"><path d="M6 18 18 6M6 6h12v12" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="square"/></svg></a></header>
    <main>
      {!started && <section className="welcome" aria-labelledby="welcome-title">
        <img className="welcome-art" src="/welcome-adventurers.png" width="346" height="290" alt="" draggable="false"/>
        <h1 id="welcome-title">Выбираем голоса для персонажей</h1>
        <p>Сравните озвучки заданий WoW Forever из библиотек <span className="library-name library-0">WowVoice</span>, <span className="library-name library-1">CatQuest</span> и <span className="library-name library-2">Wayfarer</span>. Мы собираем ваши оценки, чтобы выбрать самые популярные озвучки заданий и NPC для TalkingHead Ru.</p>
        <button className="welcome-start" onClick={()=>setStarted(true)}>Начать сравнение</button>
      </section>}
      <div className={`comparison-view${started ? '' : ' is-preloading'}`} inert={!started} aria-hidden={!started ? true : undefined}>
      <div className="comparison-stage">
      {finished && !choice && completion}
      {layoutQuest && <div className={`comparison-step${finished && !choice ? ' is-complete' : ''}`} inert={finished && !choice} aria-hidden={finished && !choice ? true : undefined}>
      <div className="intro"><h1 ref={finished && !choice ? null : comparisonTitle} tabIndex={-1}><span style={{visibility:finished && choice ? 'hidden' : undefined}} aria-hidden={finished && choice ? true : undefined}>Какой голос лучше подходит персонажу?</span>{finished && choice && <span className="completion-title">Готово!</span>}</h1><p className="batch-progress" style={{visibility:finished ? 'hidden' : undefined}} aria-hidden={finished ? true : undefined} role="status">Сравнение {batchIndex+1} из {comparisons.length}</p></div>
      <div className="head-shell"><section className="head-stage" aria-label="Говорящая голова"><div className="head-content" style={{visibility:choice ? 'hidden' : undefined}} aria-hidden={choice ? true : undefined}><div className="head-viewport"><div className="talking-head"><div className="head-background"/>{(finished ? (preparedBatch || []).slice(0,1) : comparisons.slice(batchIndex,batchIndex+2)).map((entry,i)=><div key={entry.key} className={`portrait-slot ${!finished && i===0 ? 'current' : 'upcoming'}`} data-quest-id={entry.quest.questID} aria-hidden={finished || i!==0 ? true : undefined}><Portrait npc={entry.quest.npc} questID={entry.quest.questID} current={!finished && i===0} playing={!finished && i===0 && playing}/></div>)}<div className="speech"><h2>{layoutQuest.npc.name}</h2><div className="quest-text" ref={scroll}><p>{layoutQuest.text}</p></div></div>
        <PlaybackProgress audio={audio} duration={length} position={position} playing={playing}/>
      </div></div>
        <div className="transport"><span className={playing ? 'signal playing' : 'signal'}><i/><i/><i/><i/></span><span>{active ? `Вариант ${letters[variants.findIndex(v=>v.id===active.id)]}` : 'Выберите запись ниже'}</span></div>
      </div>{choice && <div className={`choice-confirmation library-${libraries.indexOf(choice)}`}><div role="status"><span className="choice-check" aria-hidden="true">✓</span><p>Вы выбрали</p><strong>{choice}</strong></div><button className="next-sample" style={{visibility:finished ? 'hidden' : undefined}} disabled={finished || advancing} aria-busy={advancing} aria-hidden={finished ? true : undefined} tabIndex={finished ? -1 : undefined} onClick={next} autoFocus={!finished}>Следующая реплика <span aria-hidden="true">→</span></button></div>}
      </section><VolumeControl value={volume} onChange={changeVolume} onToggleMute={()=>changeVolume(volume>0 ? 0 : previousVolume.current)}/></div>
      <div className="options-stage">
      <div className={`options-content${finished ? ' is-complete' : ''}`} inert={finished} aria-hidden={finished ? true : undefined}>
      <div className="variants">{layoutVariants.map((variant,i)=><div className={`voice-card ${active?.id===variant.id ? 'active' : ''}`} key={variant.id}><div className="voice-label"><span>ВАРИАНТ {letters[i]}</span></div><button className="play-button" disabled={!!choice} onClick={()=>play(variant)} aria-label={`${playing && active?.id===variant.id ? 'Остановить' : 'Послушать'} вариант ${letters[i]}`}><span className="play-disc"><Icon stop={playing && active?.id===variant.id}/></span>{playing && active?.id===variant.id ? 'Играет' : 'Послушать'}</button><button className="vote-button" disabled={!!choice || heard.length < 2 || !heard.includes(variant.id)} onClick={()=>vote(variant)}><span>Выбрать этот голос</span><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="m5 12 4 4L19 6"/></svg></button></div>)}</div>
      <div className="below" style={{visibility:choice ? 'hidden' : undefined}}><span>{heard.length < 2 ? 'Послушайте хотя бы два варианта' : 'Какой из голосов больше подходит персонажу?'}</span></div>
      </div>
      {finished && choice && completion}
      </div>
      </div>}
      </div>
      {(quest || finished) && <VoteStats summary={summary}/>}
      {error && <p className="error" role="alert">{error}</p>}{!catalogue && !error && <p className="loading">Подготавливаем записи…</p>}
      </div>
    </main>
    <audio ref={audio} onTimeUpdate={()=>setPosition(audio.current.currentTime)} onLoadedMetadata={()=>setLength(audio.current.duration)} onEnded={()=>{setPlaying(false);setPosition(audio.current.duration);}} onPause={()=>setPlaying(false)} onPlaying={()=>setPlaying(true)} onError={()=>{setPlaying(false);if(audio.current?.getAttribute('src'))setError('Запись недоступна. Попробуйте другой вариант.');}}/>
  </div>;
}
createRoot(document.getElementById('root')).render(<App/>);
