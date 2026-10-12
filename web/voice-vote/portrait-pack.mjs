// Offline, lossless portrait subset of the cached MD21 format. Source files
// remain immutable. Unsupported layouts fail closed, never producing a pack.
import {createHash} from 'node:crypto';

const ARRAY_FIELDS = [[8,1],[20,4],[28,64],[36,2],[44,88],[52,2],[60,48],
  [72,40],[80,16],[88,20],[96,60],[104,2],[112,4],[120,2],[128,2],
  [136,2],[144,2],[152,2],[216,2],[224,12],[232,12],[240,40],[248,2],
  [256,36],[264,156],[272,116],[280,2],[288,176],[296,476]];

export function chunksOf(bytes) {
  const result=[];
  for(let pos=0;pos<bytes.length;) {
    if(pos+8>bytes.length) throw Error('Truncated chunk header');
    const tag=bytes.toString('ascii',pos,pos+4), size=bytes.readUInt32LE(pos+4);
    if(pos+8+size>bytes.length) throw Error(`Truncated ${tag} chunk`);
    result.push({tag,bytes:bytes.subarray(pos+8,pos+8+size)}); pos+=8+size;
  }
  return result;
}

function joinChunks(chunks) {
  return Buffer.concat(chunks.map(({tag,bytes})=>{
    const head=Buffer.alloc(8);head.write(tag,0,'ascii');head.writeUInt32LE(bytes.length,4);
    return Buffer.concat([head,bytes]);
  }));
}

class Writer {
  constructor(source,headerSize) {
    this.source=source;this.parts=[Buffer.from(source.subarray(0,headerSize))];
    this.size=headerSize;this.copies=new Map();
  }
  range(offset,size) {
    if(!Number.isSafeInteger(size)||offset<0||size<0||offset+size>this.source.length)
      throw Error(`Invalid data range ${offset}:${size}`);
  }
  add(bytes) {
    const padding=(16-this.size%16)%16;
    if(padding){this.parts.push(Buffer.alloc(padding));this.size+=padding;}
    const offset=this.size;this.parts.push(bytes);this.size+=bytes.length;return offset;
  }
  copy(offset,size) {
    if(!size)return 0;
    this.range(offset,size);
    const key=`${offset}:${size}`;
    if(!this.copies.has(key))this.copies.set(key,this.add(Buffer.from(this.source.subarray(offset,offset+size))));
    return this.copies.get(key);
  }
  array(target,at,sourceAt,stride,visit) {
    const count=this.source.readUInt32LE(sourceAt),offset=this.source.readUInt32LE(sourceAt+4);
    this.range(offset,count*stride);
    if(!count){target.fill(0,at,at+8);return;}
    if(!visit){target.writeUInt32LE(count,at);target.writeUInt32LE(this.copy(offset,count*stride),at+4);return;}
    const records=Buffer.from(this.source.subarray(offset,offset+count*stride));
    const dest=this.add(records);
    for(let i=0;i<count;i++)visit(records,i*stride,offset+i*stride,i);
    target.writeUInt32LE(count,at);target.writeUInt32LE(dest,at+4);
  }
  finish(){return Buffer.concat(this.parts);}
}

function animationSelection(data) {
  const count=data.readUInt32LE(28),offset=data.readUInt32LE(32);
  if(offset+count*64>data.length)throw Error('Invalid sequence table');
  const sequences=Array.from({length:count},(_,i)=>({
    index:i,id:data.readUInt16LE(offset+i*64),variation:data.readUInt16LE(offset+i*64+2),
    flags:data.readUInt32LE(offset+i*64+12),next:data.readInt16LE(offset+i*64+60),
    alias:data.readUInt16LE(offset+i*64+62),
  }));
  const stand=sequences.find(s=>s.id===0&&s.variation===0);
  if(count&&!stand)throw Error('Animated model without a base Stand sequence');
  // Match src/model.js: EmoteTalk, another Talk animation, or Stand.
  const talkIDs=[60,64,65,208,289,293,294,437,600,601,614,615,778,779,792,793,
    796,797,1166,1167,1186,1187,1206,1207,1258,1259,1266,1267,1350,1351,
    1352,1353,1368,1369,1370,1371,1398,1399,1410,1411,1428,1429,1480,1481,
    1492,1493,1732,1733,1774,1775];
  const talk=sequences.find(s=>s.id===60)||sequences.find(s=>talkIDs.includes(s.id));
  const selected=new Set();
  if(stand)selected.add(stand.index);
  if(talk)for(const s of sequences)if(s.id===talk.id)selected.add(s.index);
  if(!selected.size&&count)throw Error('No supported portrait animation');
  const visit=index=>{
    const s=sequences[index];if(!s)throw Error('Invalid animation dependency');
    if((s.flags&0x40)&&!selected.has(s.alias)){selected.add(s.alias);visit(s.alias);}
    if(s.id!==0&&s.next>=0&&!selected.has(s.next)){selected.add(s.next);visit(s.next);}
  };
  for(const index of selected)visit(index);
  return {selected,sequences,stand};
}

/** Retains exact base-skin vertices and required animation keys. No decimation. */
export function packPortraitModel(input,skin) {
  const chunks=chunksOf(input),md=chunks.find(c=>c.tag==='MD21');
  if(!md)throw Error('Only chunked MD21 models are supported');
  if(chunks.some(c=>c.tag==='SKID'))throw Error('External skeleton requires a separate skeleton pack');
  const data=md.bytes,version=data.readUInt32LE(4);
  if(data.toString('ascii',0,4)!=='MD20'||![272,274].includes(version))throw Error('Unsupported MD21 version');
  if(data.readUInt32LE(288)||data.readUInt32LE(296))throw Error('Emitter layout requires a separate compatibility check');
  if(skin.toString('ascii',0,4)!=='SKIN')throw Error('Invalid base skin');
  const skinCount=skin.readUInt32LE(4),skinOffset=skin.readUInt32LE(8);
  if(skinOffset+skinCount*2>skin.length)throw Error('Invalid skin vertex lookup');
  let maxVertex=-1;
  for(let i=0;i<skinCount;i++)maxVertex=Math.max(maxVertex,skin.readUInt16LE(skinOffset+2*i));
  const originalVertices=data.readUInt32LE(60),vertices=maxVertex+1;
  if(vertices>originalVertices)throw Error('Skin references missing vertices');
  const {selected,sequences,stand}=animationSelection(data);
  const writer=new Writer(data,(data.readUInt32LE(16)&8)?312:304),header=writer.parts[0];

  function track(target,at,sourceAt,valueSize,{bone=false,all=false}={}) {
    // The full table keeps original sequence indices and alias references.
    // Unused slots have zero counts; their keys are never copied to the pack.
    for(const [relative,stride] of [[4,4],[12,valueSize]]) {
      const tableCount=data.readUInt32LE(sourceAt+relative);
      writer.array(target,at+relative,sourceAt+relative,8,(records,dest,src,index)=>{
        // The viewer falls back to slot zero when a track has fewer slots than
        // the selected sequence index. Global and material tracks use it too.
        const fallback=index===0&&(all||!selected.size||[...selected].some(i=>i>=tableCount));
        if(!all&&!selected.has(index)&&!fallback){records.fill(0,dest,dest+8);return;}
        const count=data.readUInt32LE(src),offset=data.readUInt32LE(src+4);
        // These offsets belong to the separate .anim stream, not MD21.
        // Retain its descriptor; AFID below keeps only required .anim files.
        if(count&&bone&&!(sequences[index]?.flags&0x20))return;
        records.writeUInt32LE(count,dest);
        records.writeUInt32LE(writer.copy(offset,count*stride),dest+4);
      });
    }
  }
  const callbacks={
    28:(out,dst,src,index)=>{
      if(stand?.index===index)out.writeInt16LE(-1,dst+60);
    },
    44:(out,dst,src)=>{track(out,dst+16,src+16,12,{bone:true});track(out,dst+36,src+36,8,{bone:true});track(out,dst+56,src+56,12,{bone:true});},
    72:(out,dst,src)=>{track(out,dst,src,12);track(out,dst+20,src+20,2);},
    80:(out,dst,src)=>writer.array(out,dst+8,src+8,1),
    88:(out,dst,src)=>track(out,dst,src,2),
    96:(out,dst,src)=>{track(out,dst,src,12);track(out,dst+20,src+20,16);track(out,dst+40,src+40,12);},
    240:(out,dst,src)=>track(out,dst+20,src+20,1),
    // Event timelines are not used by the renderer; retain them unchanged.
    256:(out,dst,src)=>writer.array(out,dst+28,src+28,8,(r,d,s)=>writer.array(r,d,s,4)),
    264:(out,dst,src)=>[12,4,12,4,4,4,1].forEach((size,i)=>track(out,dst+16+20*i,src+16+20*i,size)),
    // Keep all authored camera keys, including sequence zero calibration.
    272:(out,dst,src)=>{track(out,dst+12,src+12,36,{all:true});track(out,dst+44,src+44,36,{all:true});track(out,dst+76,src+76,12,{all:true});track(out,dst+96,src+96,12,{all:true});},
  };
  for(const [at,stride] of ARRAY_FIELDS){
    if(at===60){header.writeUInt32LE(vertices,60);header.writeUInt32LE(writer.copy(data.readUInt32LE(64),vertices*48),64);}
    else writer.array(header,at,at,stride,callbacks[at]);
  }
  if(header.length===312)writer.array(header,304,304,2);
  const result=joinChunks(chunks.map(chunk=>{
    if(chunk.tag==='MD21')return {tag:chunk.tag,bytes:writer.finish()};
    // Only the first skin is consumed by this portrait renderer.
    if(chunk.tag==='SFID')return {tag:chunk.tag,bytes:chunk.bytes.subarray(0,4)};
    if(chunk.tag==='AFID'){
      const kept=[];
      for(let i=0;i<chunk.bytes.length;i+=8){
        const id=chunk.bytes.readUInt16LE(i),variation=chunk.bytes.readUInt16LE(i+2);
        if([...selected].some(index=>sequences[index].id===id&&sequences[index].variation===variation))kept.push(chunk.bytes.subarray(i,i+8));
      }
      return {tag:chunk.tag,bytes:Buffer.concat(kept)};
    }
    return chunk;
  }));
  return {bytes:result,stats:{sourceBytes:input.length,packedBytes:result.length,
    sourceVertices:originalVertices,vertices,sourceSequences:sequences.length,
    retainedSequences:[...selected].map(i=>({index:i,id:sequences[i].id,variation:sequences[i].variation})),
    sha256:createHash('sha256').update(result).digest('hex')}};
}
