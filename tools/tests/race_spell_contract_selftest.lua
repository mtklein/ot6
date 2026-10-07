-- @manual standalone: lua tools/tests/race_spell_contract_selftest.lua [case] [library]
-- Synthetic compiler/controller contracts, not play. Read-only RAM/ROM stubs.
emu={eventType={inputPolled=1},addEventCallback=function() return 1 end}
local H=dofile(arg[2] or 'tools/tests/lib/ot6.lua')
assert(loadfile('tools/tests/lib/ot6_field.lua'))(H)
local ram,rom={},{}
H.readByte=function(a) return ram[a] or 0 end
H.readWord=function(a) return (ram[a] or 0)|((ram[a+1] or 0)<<8) end
H.readRomByte=function(a) return rom[a] or 0 end
H.sym=function(s) if s=='MagicProp' then return 0x1000 elseif s=='Ot6FoldTbl' then return 0x2000 end error(s) end
H.log=function() end
for i=0,23 do rom[0x2000+i]=255 end
rom[0x2000],rom[0x2001],rom[0x2002]=0,5,9
rom[0x1000+14*0+5],rom[0x1000+14*5+5],rom[0x1000+14*9+5]=4,20,51
rom[0x1000+14*45+5]=5
ram[0x202e],ram[0x202f]=2,0
ram[0x302c],ram[0x302d]=0,0x21
for n=1,54 do ram[0x2100+n*4]=255 end
ram[0x2104],ram[0x2107],ram[0x2108],ram[0x210b]=0,4,45,5
ram[0x3c08],ram[0x3e9c]=100,3
local function candidate()
  return {kind='magic',spell=0,target=4,boost=2,all=true,
    controller={kind='magic',effectRole='damage',targetContract={chars=0,monsters=3,all=true}}}
end
local function driver()
  local d=H.newFightDriver('spell contract',{}).driver
  d.steerWatch=function() end; d.castVetoed=function(_,id) d.vetoId=id;return false end
  d.focusList=function() return {{slot=1,mask=2}} end
  d.focusReachable=function() return true end
  return d
end
local cases={}
cases.compile=function()
  local p=assert(driver():racePlan(0,candidate()))
  assert(p.kind=='magic' and p.spell==0 and p.executionSpell==9,'retain offensive menu and folded execution identity')
  assert(p.exactBoost and p.boostWant==2 and p.raceBoost==2 and p.all,'retain total boost and group intent')
  assert(p.targetContract.monsters==3,'retain exact scored target mask')
end
cases.reject=function()
  local d=driver();local c=candidate();c.controller=nil
  assert(d:racePlan(0,c)==nil,'incomplete offensive spell cannot masquerade as cure')
  c=candidate();c.controller.kind='heal';c.controller.effectRole='heal'
  c.target=0;c.all=false;c.controller.targetContract={chars=1,monsters=0,all=false}
  assert(d:racePlan(0,c)==nil,'candidate effect role cannot disagree with its controller')
  c=candidate();ram[0x3e9c]=1;assert(d:racePlan(0,c)==nil,'short bank cannot compile exact boosted spell');ram[0x3e9c]=3
  ram[0x2f47]=1;assert(d:racePlan(0,candidate())==nil,'unmodeled special layout rejected');ram[0x2f47]=0
end
cases.cure=function()
  local p=assert(driver():racePlan(0,{kind='heal',spell=45,target=1,restore=50,mp=5}))
  assert(p.kind=='heal' and p.exactBoost and p.boostWant==0,'existing cure explicitly clears pending boost')
  assert(p.targetContract.chars==2 and p.targetContract.monsters==0 and not p.targetContract.all,'existing cure binds one ally')
end
local function target(p,chars,mons,all)
  local d=driver(); d.plan,d.planActor=p,0;d.planPulses=0;d.tgtSpin=39
  ram[0x7bc2],ram[0x7bca]=0x38,1
  ram[0x7b7d],ram[0x7b7e],ram[0x7b7f]=chars,mons,all
  ram[0x3e9d]=p.boostWant or 0
  ram[p.spell==0 and 0x2107 or 0x210b]=p.spellCost or 5
  return d
end
-- Find production MSTATE from source-independent known engine address.
cases.group=function()
  local p=assert(driver():racePlan(0,candidate()))
  local d=target(p,0,3,1);local b=d:button(0)
  assert(b and b[1]=='a' and d.plan==nil,'matched group passes common confirmation')
  assert(d.vetoId==9,'offensive guard checks folded execution record')
end
cases.ally_fallback=function()
  local p=assert(driver():racePlan(0,{kind='heal',spell=45,target=1,restore=50,mp=5}))
  local d=target(p,1,0,0);d.steerDead={down=2};local b=d:button(0)
  assert(b and b[1]=='b' and d.plan==nil,'wrong ally fallback must back out without confirmation')
end
cases.group_fallback=function()
  local c=candidate();c.kind='heal';c.controller.kind='heal';c.controller.effectRole='heal';c.controller.targetContract={chars=3,monsters=0,all=true};c.target=0;c.spell=45
  local p=assert(driver():racePlan(0,c));local d=target(p,1,0,0);local b=d:button(0)
  assert(b and b[1]=='b' and d.plan==nil,'failed group latch cannot become single cast')
end
cases.early_group=function()
  local c=candidate();c.kind='heal';c.controller.kind='heal';c.controller.effectRole='heal';c.controller.targetContract={chars=3,monsters=0,all=true};c.target=0;c.spell=45
  local p=assert(driver():racePlan(0,c));p.all=true -- isolate existing early-A controller path too
  local d=target(p,3,0,1);local b=d:button(0)
  assert(b and b[1]=='a' and d.plan==nil and d.confirmed,'strict ally group uses common bookkeeping')
end
cases.live_price=function()
  local p=assert(driver():racePlan(0,candidate()));local d=target(p,0,3,1)
  ram[0x2107]=1;local b=d:button(0)
  assert(b and b[1]=='b' and d.plan==nil,'changed live list price cannot confirm scored cast')
end
cases.enemy_mask=function()
  local p=assert(driver():racePlan(0,candidate()));local d=target(p,0,7,1);local b=d:button(0)
  assert(b and b[1]=='b' and d.plan==nil,'enemy group containing extra body cannot confirm scored cast')
end
cases.focus_override=function()
  local c=candidate();c.all=false;c.target=0;c.controller.targetContract={chars=0,monsters=1,all=false}
  local p=assert(driver():racePlan(0,c));local d=target(p,0,1,0)
  d.tgtSpin=0
  ram[0x3bfc],ram[0x3bfe],ram[0x3aa8],ram[0x3aaa]=100,100,1,1
  d.steer=function() error('authored focus must not move an exact scored target') end
  local b=d:button(0)
  assert(b and b[1]=='a' and d.plan==nil,'exact spell target overrides authored focus on another live enemy')
end
cases.queue_ack=function()
  local p=assert(driver():racePlan(0,candidate()))
  local ev={};local T=H.newRecoveryTrace('ack',function(e) ev[#ev+1]=e end)
  T.plan(0,p,0);T.submit(0,1,2,0,0x100,2)
  assert(ev[#ev].reason=='race_submission_mismatch' and T.pending[0]==nil,'actual submitted mask must match scored mask')
  assert(ev[#ev].event=='unresolved' and ev[#ev-1].event=='submit'
    and ev[#ev-1].targets==0x100 and ev[#ev-1].accepted_boost==2,
    'a consumed mismatched action records actual submission then unresolved contract')
  T.plan(0,p,2);T.submit(0,3,2,0,0x300,1)
  assert(ev[#ev].reason=='race_submission_mismatch','accepted boost must match scored total')
  T.plan(0,p,4);T.submit(0,5,2,0,0x300,2);T.queueStore(0,2,2,5,6,0x300)
  assert(ev[#ev].reason=='race_queue_identity_mismatch' and T.bindings[2].trace_id==nil,'wrong folded queue tier cannot acquire scored ownership')
  assert(ev[#ev].stored_attack==5 and ev[#ev].expected_attack==9
    and ev[#ev].stored_targets==0x300,'queue mismatch retains actual and expected record')
  T.plan(0,p,7);T.submit(0,8,2,0,0x300,2);T.queueStore(0,2,2,9,9,0x100)
  assert(ev[#ev].reason=='race_queue_identity_mismatch','target change between user submission and actual queue store is rejected')
  T.plan(0,p,7);T.submit(0,8,2,0,0x300,2);T.queueStore(0,2,2,9,9,0x300)
  local s=T.start(0,10,2,9,0x300,{100,100,100,100},49,1,{queue_index=2,queued_command=2,queued_attack=9})
  assert(s and s.trace_id,'matched initial targets, boost and folded tier acquire execution ownership')
  T.hpEffect(0,11,6,100,0,2,9,{context=s,queued_command=2,queued_attack=9})
  assert(ev[#ev].event=='hp_effect','engine carry may affect a body outside initial mask without invalidating ownership')
end
cases.ordinary=function()
  local p={kind='heal',spell=45,target=1,row=0,restore=50}
  local d=target(p,1,0,0);d.steerDead={down=2};local b=d:button(0)
  assert(b and b[1]=='a' and d.plan==nil,'ordinary ally fallback retains existing confirm behavior')
  p={kind='heal',spell=45,target=0,row=0,all=true}
  d=target(p,3,0,1);b=d:button(0)
  assert(b and b[1]=='a' and d.plan==p,'ordinary all-ally latch retains existing early confirm behavior')
end
local names={'compile','reject','cure','group','ally_fallback','group_fallback','early_group','live_price','enemy_mask','focus_override','queue_ack','ordinary','boosted_heal_ledger'}
cases.boosted_heal_ledger=function()
  -- Nonfamily cure fixture: five raw MP becomes31 at total boost2.
  -- Its boosted result must never teach the ordinary unboosted ledger.
  ram[0x210b]=31;ram[0x3e9d]=2
  local c={kind='heal',spell=45,target=1,boost=2,restore=500,
    controller={kind='heal',effectRole='heal',targetContract={chars=2,monsters=0,all=false}}}
  local p=assert(driver():racePlan(0,c));local d=target(p,2,0,0)
  d.castRestoreOf=function() error('boosted single heal must not learn as unboosted menu spell') end
  local b=d:button(0)
  assert(b and b[1]=='a' and not d.healWatch,'strict boosted heal skips legacy unboosted restore learning')
  ram[0x210b]=5;ram[0x3e9d]=0
end
if arg[1] then assert(cases[arg[1]])() else for _,name in ipairs(names) do cases[name]() end end
print('race_spell_contract_selftest: PASS '..(arg[1] or 'all'))
