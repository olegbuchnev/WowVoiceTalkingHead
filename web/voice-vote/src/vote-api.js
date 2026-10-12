import {readVotes, voteStorageKey} from './vote-history.js';

async function request(path,body) {
  const response=await fetch(`/api/votes${path}`, {
    method:body ? 'POST' : 'GET', credentials:'same-origin',
    headers:body ? {'Content-Type':'application/json'} : {},
    body:body ? JSON.stringify(body) : undefined, signal:AbortSignal.timeout(15000),
  });
  const data=await response.json().catch(()=>({}));
  if (!response.ok) {
    const messages={400:'Не удалось отправить оценку. Обновите страницу.',
      401:'Разрешите cookie сайта и обновите страницу.',403:'Откройте сравнение на странице сайта.',
      404:'Сравнение больше недоступно. Обновите страницу.',
      409:'Записи обновились. Обновите каталог и страницу сравнения.'};
    const error=Error(messages[response.status] || 'Сервер оценок недоступен. Попробуйте ещё раз.');
    error.status=response.status; throw error;
  }
  return data;
}
export const loadSummary=()=>request('/summary');
export const loadQueue=()=>request('/queue');
export const submitVote=(questID,selectedId,variantIds,visitID)=>request('',{questID,selectedId,variantIds,...(visitID ? {visitID} : {})});
export const enqueueVote=ballot=>request('/submit',ballot);

// Sequential acknowledgement: a failed request never removes a local vote.
// Repeating migration after a crash is safe because the server upserts votes.
export async function migrateLocalVotes() {
  let records;
  try {records=readVotes();} catch {return;}
  for (const record of [...records]) {
    if (!record || !Number.isSafeInteger(record.questID) || !Array.isArray(record.candidates)) continue;
    try {
      await submitVote(record.questID,record.selected,record.candidates?.map(v=>v.id));
    } catch (error) {
      if ([400,404,409].includes(error.status)) continue; // Keep obsolete/unverifiable records.
      throw error;
    }
    records=records.filter(item=>item!==record);
    localStorage.setItem(voteStorageKey,JSON.stringify(records));
  }
  if (!records.length) localStorage.removeItem(voteStorageKey);
}
