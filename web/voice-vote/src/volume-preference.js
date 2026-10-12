const cookieName='thru_vote_volume';
const previousCookieName='thru_vote_previous_volume';

function readCookieVolume(name,fallback=100) {
  try {
    const value=document.cookie.split(';').map(part=>part.trim()).find(part=>part.startsWith(`${name}=`))?.slice(name.length+1);
    if(value == null || value.trim()==='') return fallback;
    const number=Number(value);
    return Number.isFinite(number) && number>=0 && number<=100 ? Math.round(number) : fallback;
  } catch {return fallback;}
}

export function readVolume() {return readCookieVolume(cookieName);}
export function readPreviousVolume() {return readVolume() || readCookieVolume(previousCookieName) || 100;}

export function saveVolume(value,previous=value) {
  try {
    const options=`Max-Age=31536000; Path=/; SameSite=Lax${location.protocol==='https:' ? '; Secure' : ''}`;
    document.cookie=`${cookieName}=${value}; ${options}`;
    if(previous>0) document.cookie=`${previousCookieName}=${previous}; ${options}`;
  } catch { /* Playback remains adjustable when cookies are unavailable. */ }
}
