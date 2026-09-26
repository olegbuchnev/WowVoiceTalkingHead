event('ADDON_LOADED')
local WV=WowVoice
assert(WV:ApplyHeadSettings({width=470,height=164,scale=1,x=0,y=0,enabled=true}))
local rows={}
for i=1,32 do rows[i]='aaaa bbbb' end
local function show(text,duration)
    WV:StartTalkingHead({questId=179,section='a',title='Test',text=text},now+(duration or 180),duration)
    return frames.WowVoiceTalkingHead
end
local head=show(table.concat(rows,'\n'),96)
local started=now
assert(head.TextScroll.height==104) -- Native quest font: 13px, eight whole lines
assert(#head.scrollPlan==4)
local first,last=head.scrollPlan[1],head.scrollPlan[4]
assert(first.start>17 and first.finish<19,'eight visible lines must stay still for about 18 seconds')
assert(last.finish>72 and last.finish<74,'last eight lines must be visible before their estimated reading')
local firstFinish,lastFinish=first.finish,last.finish
for _,move in ipairs(head.scrollPlan) do
    assert(move.finish-move.start<=.651)
    now=started+move.start-.01; head.scripts.OnUpdate()
    assert(head.TextScroll.scroll==move.from)
    now=started+(move.start+move.finish)/2; head.scripts.OnUpdate()
    assert(head.TextScroll.scroll>move.from and head.TextScroll.scroll<move.to)
    now=started+move.finish+.01; head.scripts.OnUpdate()
    assert(head.TextScroll.scroll==move.to)
end
now=started+95; head.scripts.OnUpdate()
assert(head.TextScroll.scroll==head.textRange)
-- Cyrillic counts characters, not its two-byte UTF-8 encoding.
for i=1,32 do rows[i]='аааа бббб' end
head=show(table.concat(rows,'\n'),96)
assert(math.abs(head.scrollPlan[1].finish-firstFinish)<.001)
assert(math.abs(head.scrollPlan[4].finish-lastFinish)<.001)
-- Punctuation and paragraph pauses affect timing of the next block.
for i=1,6 do rows[i]=rows[i]..'.' end
head=show(table.concat(rows,'\n'),96)
assert(head.scrollPlan[1].finish>firstFinish+2)
-- Increasing viewport height delays the first shift and increases final hold.
assert(WV:ApplyHeadSettings({width=470,height=216,scale=1,x=0,y=0,enabled=true}))
local largerFirst=head.scrollPlan[1].finish
assert(largerFirst>firstFinish)
assert(head.scrollPlan[#head.scrollPlan].finish<lastFinish)
-- Width changes actual wrapped blocks, without changing audio playback.
local continuous=string.rep('word ',240)
head=show(continuous,96)
local narrowFirst=head.scrollPlan[1].finish
assert(WV:ApplyHeadSettings({width=800,height=216,scale=1,x=0,y=0,enabled=true}))
assert(head.scrollPlan[1].finish>narrowFirst)
-- A small overflow must scroll late, not erase the first line at the start.
assert(WV:ApplyHeadSettings({width=470,height=164,scale=1,x=0,y=0,enabled=true}))
head=show(string.rep('aaaa bbbb\n',8)..'aaaa bbbb',27)
assert(#head.scrollPlan==1 and head.scrollPlan[1].start>2)
-- No duration or a short text: no invented timing and no stale plan.
head=show(continuous,nil); assert(#head.scrollPlan==0 and head.TextScroll.scroll==0)
head=show('Short text.',96); assert(#head.scrollPlan==0 and head.TextScroll.scroll==0)
WV:StopTalkingHead()
assert(#plays==0 and #stops==0)
print('PASS: long stable blocks, overlapping transitions, early final block, UTF-8/punctuation weights, resize/rewrap, small overflow, no duration')
