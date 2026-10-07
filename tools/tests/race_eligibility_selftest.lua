-- @manual standalone: lua tools/tests/race_eligibility_selftest.lua [library]
-- Read-only observation arithmetic and real-driver wiring; no play claim.
emu={eventType={inputPolled=1},callbackType={exec=1},addEventCallback=function() return 1 end,
  addMemoryCallback=function() return 1 end}
local H=dofile(arg[1] or 'tools/tests/lib/ot6.lua')
local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
local function party(st,hp,left)
 return {[0]={char=6,hp=hp or 500,st1=st or 0,left=left or false}}
end
local seats={[0]={actor=6,off=222},[1]={actor=0,off=0}}
for _,st in ipairs({0,2,0x40,0x80,0xC2}) do
 for _,hp in ipairs({0,500,0xFFFF}) do
  for _,left in ipairs({false,true}) do
   check(H.raceRewardEligible({hp=hp,st1=st,left=left})==(hp==500 and st==0 and not left),
     'HP, status and removal observations remain distinct')
  end
 end
end
local events={}
local L=H.newRaceEligibility({[0]=seats[0]},function(e) events[#events+1]=e end)
local p=party();L.observe(p,1,65530);p[0].hp=100
check(L.history[1].hp==500,'initial sample is copied')
L.observe(party(2,500),2,65535)
check(#L.history==2 and not L.history[2].eligible and L.history[2].hp==500,'positive HP Zombie transition retained')
L.observe(party(2,0),3,0)
check(#L.history==3 and L.history[3].st1==2,'zero HP distinct from status-only ineligibility')
L.observe(party(0,500),4,1)
check(#L.history==4 and L.history[4].eligible,'Revivify can restore eligibility before rewards')
-- Two members, pool101 XP. If one is excluded, other gets101 rather
-- than their all-seated equal-share50. Foregone reference is explicitly
-- counterfactual allocation, not the engine's actual due amount.
local function reward(mask,st)
 return {party={[0]={char=6,hp=500,st1=st,left=false},[1]={char=0,hp=500,st1=0,left=false}},
   xp={[0]=101},st1={[0]=0x80},hp={[0]=0},aliveMask=mask,alive=mask==3 and 2 or 1,
   random=false,egg={},left=0,gone=1,seated={[0]=true,[1]=true},filled={[0]=true}}
end
local function finish(ledger,raw,paid)
 local o=H.battleOutcome(raw)
 return ledger.finish(o,paid,raw,10,2,true)
end
L=H.newRaceEligibility(seats)
local raw=reward(3,0);local terminal=finish(L,raw,{[0]=50,[1]=50})
check(terminal.atEnd and terminal.observation_source=='UpdateSRAM' and terminal.frame==10 and terminal.atb_tick==2,'terminal retains authoritative source and sample time')
check(terminal.members[0].left==false,'matched reward preserves observed not-left boolean')
check(terminal.members[0].eligible and terminal.members[0].foregone_equal_share==0,'cured before victory loses no share')
L=H.newRaceEligibility(seats);raw=reward(2,2);terminal=finish(L,raw,{[0]=0,[1]=101})
check(not terminal.members[0].eligible and terminal.members[0].due==0 and terminal.members[0].paid==0,'reward alive mask is authority')
check(terminal.members[0].equal_share_reference==50 and terminal.members[0].foregone_equal_share==50,
 'reference share does not confuse redistributed survivor XP with every seated share')
check(terminal.members[1].due==101 and terminal.members[1].paid==101 and terminal.members[1].char==0,'survivor redistribution and stable identities retained')
local mismatch=reward(2,0)
local masked=finish(H.newRaceEligibility(seats),mismatch,{[0]=0,[1]=101})
check(not masked.members[0].eligible,'reward mask overrides transient positive HP and clear status')
L.observe({[0]={char=6,hp=500,st1=0,left=false}},11,3)
raw.party[0].st1=0
check(terminal.members[0].st1==2 and terminal.members[0].foregone_equal_share==50,'field cure cannot rewrite reward-boundary XP record')
check(finish(L,reward(3,0),{[0]=50,[1]=50})==terminal,'reward boundary finalized once')
L=H.newRaceEligibility(seats);L.observe(party(0,500,true),1,0)
check(not L.history[1].eligible and L.history[1].left,'removal distinct from HP death')
L.observe({[0]={char=1,hp=1,st1=0,left=false}},2,1)
check(#L.history==1,'changed entity identity cannot attach to seated character')
for _,missing in ipairs({false,true}) do
 raw=reward(3,0)
 if missing then raw.party[0]=nil else raw.party[0].char=1 end
 L=H.newRaceEligibility(seats);terminal=finish(L,raw,{[0]=7,[1]=50})
 local m=terminal.members[0]
 check(not m.identity_match and m.char==6 and m.paid==7,'original XP identity survives missing or replaced entity')
 check(m.eligible==nil and m.due==nil and m.hp==nil and m.st1==nil and m.left==nil,
   'unknown reward identity cannot borrow replacement eligibility or status')
 check(m.equal_share_reference==nil and m.foregone_equal_share==nil,'unknown identity cannot invent XP debt')
end
raw=reward(2,2);raw.egg[0]=true;L=H.newRaceEligibility(seats);terminal=finish(L,raw,{[0]=0,[1]=101})
check(terminal.members[0].equal_share_reference==100,'Exp Egg applies to reference allocation separately')
raw=reward(0,0);raw.lost=true;L=H.newRaceEligibility(seats);terminal=finish(L,raw,{[0]=0,[1]=0})
check(terminal.kind=='lost' and terminal.members[0].foregone_equal_share==0,'lost battle does not invent victory equal-share reward')
-- Exercise watchLeavers and sayOutcome; default-off driver is untouched.
local ram={}
H.readByte=function(a) return ram[a] or 0 end
H.readWord=function(a) return (ram[a] or 0)|((ram[a+1] or 0)<<8) end
H.readRomWord=function() return 16 end;H.sym=function() return 0 end;H.log=function() end
H.CARE_RACE=false
ram[0x3BF4],ram[0x3C1C],ram[0x3AA0],ram[0x3A74],ram[0x3A76]=100,100,1,1,1
ram[0x1611]=10
for _,opt in ipairs({false,true}) do
 local d=H.newFightDriver('eligibility wiring',{raceEligibility=opt}).driver
 d.battleTick=6;H.frame=100
 d:watchLeavers()
 check((d.raceEligibility~=nil)==opt,'observer respects explicit opt-in and default off')
 if opt then
  ram[0x3EE4]=2 -- BATTLE.ST1 for actor0; validate source address below.
  ram[0x3A74],ram[0x3A76]=0,0
  d:watchLeavers();d:sayOutcome()
  local first=H.lastOutcome.eligibility
  check(not first.atEnd and first.observation_source=='last-watch' and first.frame==100,'fallback is identified with original sample time')
  check(first and first.members[0].char==0,'actual outcome contains stable reward observation')
  local old=d.raceEligibility
  d:idle()
  check(d.raceEligibility==nil,'battle cleanup drops finalized ledger')
  ram[0x3ED8],ram[0x3EE4],ram[0x3A74],ram[0x3A76]=6,0,1,1
  d.battleTick=6;H.frame=200;d:watchLeavers()
  check(d.raceEligibility~=old and d.raceEligibility.seats[0]==6,'reused driver seats next battle independently')
  d:sayOutcome()
  check(H.lastOutcome.eligibility~=first and H.lastOutcome.eligibility.members[0].char==6,
    'second battle gets its own terminal character and reward record')
  check(first.members[0].char==0 and first.members[0].st1==2,'next battle cannot rewrite first reward record')
 end
end
print(string.format('race_eligibility_selftest: PASS -- %d checks',n))
