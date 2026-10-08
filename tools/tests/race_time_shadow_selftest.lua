-- @manual standalone: lua tools/tests/race_time_shadow_selftest.lua [library]
-- Synthetic real-driver observation wiring; no play claim or state writes.
local callbacks={}
emu={eventType={inputPolled=1},callbackType={exec=1},addEventCallback=function()return 1 end,
 addMemoryCallback=function(f,_,a) callbacks[a]=f;return 1 end}
local H=dofile(arg[1] or 'tools/tests/lib/ot6.lua')
local n=0
local function check(ok,msg)assert(ok,msg);n=n+1 end
local ram={};local function word(a,v)ram[a]=v&255;ram[a+1]=(v>>8)&255 end
H.readByte=function(a)return ram[a] or 0 end
H.readWord=function(a)return (ram[a] or 0)|((ram[a+1] or 0)<<8) end
H.readRomWord=function()return 16 end
H.sym=function(name)return name=='UpdateSRAM' and 12345 or 54321 end
local logs={};H.log=function(s)logs[#logs+1]=s end
H.frame=100;H.CARE_RACE=false
word(0x3BF4,1000);word(0x3C1C,1000);ram[0x3AA0]=1;ram[0x3A74]=1;ram[0x3A76]=1
local function state()
 return {actor=0,samples=0,horizon=3,contCare=false,boost=false,
 party={[0]={hp=1000,maxhp=1000,eta=0,period=100,bp=0,lines={[0]={per=0,hits=1,chips=0}}}},
 enemies={[0]={hp=1000,sh=0,eta=0,period=100,act={aim=0,hit=1,dmg={[0]=10}}}}}
end
local function candidate(st)return {kind='attack',boost=0,delay=0,line=st.party[0].lines[0]}end
local function rp()
 local st=state();return {st=st,raceCandidate=candidate(st),rulesCandidate=candidate(st)}
end
local function driver()return H.newFightDriver('shadow wiring',{}).driver end
local plan={kind='fight',boostLeft=0}
local function traceLifecycle(x)
 local events={}
 local T=H.newRecoveryTrace('production shadow lifecycle',function(e)events[#events+1]=e end,
   function(e)x:raceObserve(e)end,function()return H.readWord(0x3A3E)end)
 x.recovery=T;T.plan(0,plan,H.frame);x:raceTimeBind(0,plan)
 local id=T.pending[0].id
 T.submit(0,H.frame+1,0,255,256,0)
 T.queueStore(0,244,0,255,H.frame+2,256)
 local scope=T.start(0,H.frame+3,0,255,256,{1000,0,0,0},0,0,
   {queue_index=244,queued_command=0,queued_attack=255})
 T.resolve(0,H.frame+4,{1000,0,0,0},0,0)
 return events,id,scope
end
local d=driver();local pred=rp()
d:raceTimePush(0,pred,'rules',plan)
check(d.raceTimeActive==nil,'default off does not create observer')
H.RACE_TIME_DIAGNOSTIC=true
local pair=H.raceTimePair(pred.st,pred.raceCandidate,pred.rulesCandidate)
check(pair.budget==200 and pair.race.elapsed==200 and pair.rules.elapsed==200,'both original candidates share one predecision budget')
check(pred.st.timeHorizon==nil and pred.st.party[0].hp==1000,'shadow copies preserve source state/resources')
check(pair.race.actualDown==0 and pair.race.nearFatal==0,'actual down distinct from fractional near-fatal ranking')
local fractional=rp();fractional.st.party[0].hp=100
local low=H.raceTimePair(fractional.st,fractional.raceCandidate,fractional.rulesCandidate)
check(low.race.actualDown==0 and low.race.nearFatal==1 and low.race.deaths==H.RACE_NEAR_FATAL,
 'HP-down remains zero while ranking retains fractional near-fatal penalty')
local unsupported=rp();unsupported.st.party[0].lines[0].latencyKnown=false
check(H.raceTimePair(unsupported.st,unsupported.raceCandidate,unsupported.rulesCandidate)==nil,
 'unsupported continuation declines instead of claiming a truncated prediction')
check(H.raceTimePair(pred.st,nil,pred.rulesCandidate)==nil,'missing alternative declines comparison')
local pending=candidate(pred.st);pending.delay=201
check(H.raceTimePair(pred.st,pending,pred.rulesCandidate)==nil,'pending first action declines prediction')
local bad=candidate(pred.st);bad.mp=1;pred.st.party[0].mp=0
check(H.raceTimePair(pred.st,bad,pred.rulesCandidate)==nil,'unaffordable or unsupported prediction is declined')
pred=rp();word(0x3A3E,65530);d:raceTimePush(0,pred,'rules',plan)
local c=d.raceTimeActive[1]
d:raceTimeEvent({actor=0,event='submit'});d:raceTimeEvent({actor=0,event='resolve'})
check(not c.lifecycle.accepted and not c.lifecycle.resolved,'missing trace ID cannot advance unbound first action')
check(c.scope=='selected-policy' and not c.calibration and c.lifecycle.stage=='selected','selection does not invent accepted or resolved ownership')
d.recovery={pending={[0]={id=7}}};d:raceTimeBind(0,{kind='fight'})
check(c.lifecycle.id==nil,'a different plan table cannot bind ownership')
d:raceTimeEvent({actor=0,id=8,event='resolve'})
check(not c.lifecycle.resolved,'different trace cannot resolve selected first action')
local realEvents,realId=traceLifecycle(d)
check(realEvents[#realEvents].event=='resolve' and realEvents[#realEvents].valid==nil and c.lifecycle.valid,
 'production resolver has no validity flag; strict queue/context identity establishes ownership')
check(c.lifecycle.accepted and c.lifecycle.started and c.lifecycle.resolved,'acceptance start and resolution separately observed for bound trace')
d:raceTimeTick(H.raceTimeSample(),false,'watch')
check(c.clock.elapsed==0 and #c.history==1,'paused menus consume no clock/history interval')
word(0x3A3E,194);H.frame=500;d.monActN=4;d:raceTimeTick(H.raceTimeSample(),false,'watch')
local terminal=d.raceTimeRecords[1]
check(terminal.elapsed==200 and terminal.reason=='deadline' and not terminal.censored,'wrapped exact deadline records supported selected trajectory')
check(terminal.closedLedgerUnits==4 and terminal.actualDown==0 and terminal.scope=='selected-policy' and not terminal.calibration,'ledger count is distinct and record disclaims calibration')
check(terminal.endpoint.tick==194 and terminal.endpoint.frame==500,'endpoint clock/frame belong to same sample')
check(terminal.history[#terminal.history]==terminal.endpoint,'final endpoint retained even when HP/status unchanged')
check(terminal.actor==0 and terminal.selection_frame==100 and terminal.start_tick==65530 and terminal.lifecycle.id==realId,
 'summary retains decision origin and trace attribution')
check(logs[#logs]:find('trace_id='..realId) and logs[#logs]:find('race%-opportunities=3.00') and logs[#logs]:find('rules%-unsuppressed=3.00'),
 'raw summary includes ownership and separate model opportunity units')
check(logs[#logs]:find('first_valid=true') and logs[#logs]:find('queue_index=244') and logs[#logs]:find('queue_generation=1'),
 'summary exposes derived strict ownership and original queue/context identity')
local function push()
 local x=driver();word(0x3A3E,100);H.frame=1000;x:raceTimePush(0,rp(),'rules',plan);return x
end
local function bindValid(x) return traceLifecycle(x) end
local function finish(x,t,ended,source)
 word(0x3A3E,t);H.frame=1100;x:raceTimeTick(H.raceTimeSample(),ended,source or 'watch');return x.raceTimeRecords[1]
end
-- Fault injection copies production events; never invent resolver fields.
for _,key in ipairs({'context_id','queue_index','queue_generation','command','attack','queued_command','queued_attack','targets'}) do
 local badDriver=push();local events=traceLifecycle(badDriver)
 local corrupted={};for k,v in pairs(events[#events])do corrupted[k]=v end
 corrupted[key]=corrupted[key]+1;badDriver:raceTimeEvent(corrupted)
 local badTerminal=finish(badDriver,300,false)
 check(badTerminal.censored and not badTerminal.lifecycle.valid,
   'resolve must preserve strict started identity '..key)
end
local noAccept=push();local productionEvents=traceLifecycle(driver())
local before=H.newRecoveryTrace('no accepted command',function()end)
noAccept.recovery=before;before.plan(0,plan,H.frame);noAccept:raceTimeBind(0,plan)
local pendingId=before.pending[0].id
for _,event in ipairs(productionEvents)do
 if event.event=='start' or event.event=='resolve' then
  local copied={};for k,v in pairs(event)do copied[k]=v end
  copied.id=pendingId;noAccept:raceTimeEvent(copied)
 end
end
terminal=finish(noAccept,300,false)
check(terminal.censored and not terminal.lifecycle.accepted and not terminal.lifecycle.valid,
 'matching copied context cannot establish an unaccepted first action')
local counterDriver=push();local counterEvents=traceLifecycle(counterDriver)
for _,event in ipairs(counterEvents)do
 if event.event=='start' or event.event=='resolve' then
  local copied={};for k,v in pairs(event)do copied[k]=v end
  if copied.event=='start' then copied.counter=true end
  counterDriver:raceTimeEvent(copied)
 end
end
terminal=finish(counterDriver,300,false)
check(terminal.censored and not terminal.lifecycle.valid,'counter scope cannot verify selected controller action')
local wrongActor=push();local actorEvents=traceLifecycle(wrongActor)
local foreign={};for k,v in pairs(actorEvents[#actorEvents])do foreign[k]=v end
foreign.actor=1;foreign.queue_generation=999;wrongActor:raceTimeEvent(foreign)
check(wrongActor.raceTimeActive[1].lifecycle.valid,'same trace ID from another actor cannot overwrite valid owned resolution')
local legacyDriver=push();local legacy=H.newRecoveryTrace('legacy arithmetic',function()end,
 function(e)legacyDriver:raceObserve(e)end,function()return H.readWord(0x3A3E)end)
legacyDriver.recovery=legacy;legacy.plan(0,plan,H.frame);legacyDriver:raceTimeBind(0,plan)
legacy.submit(0,H.frame+1,0,255,256,0)
legacy.legacyStart(0,H.frame+2,0,255,256,{1000,0,0,0},0,0)
legacy.resolve(0,H.frame+3,{1000,0,0,0},0,0)
terminal=finish(legacyDriver,300,false)
check(terminal.censored and terminal.lifecycle.resolved and not terminal.lifecycle.valid,
 'arithmetic legacy trace without real queue provenance stays censored')
local unverified=push();terminal=finish(unverified,300,false)
check(terminal.censored and table.concat(terminal.censorReasons,','):find('first%-action%-unverified'),
 'unbound selected action remains censored at an otherwise exact endpoint')
local early=rp();early.st.party[0].lines[0].per=2000
local earlyDriver=driver();word(0x3A3E,100);H.frame=1000;earlyDriver:raceTimePush(0,early,'rules',plan)
traceLifecycle(earlyDriver)
terminal=finish(earlyDriver,300,false)
check(terminal.censored and table.concat(terminal.censorReasons,','):find('prediction%-terminated'),
 'early simulated victory cannot become a full-window prediction')
local x=push();terminal=finish(x,301,false)
check(terminal.censored and terminal.reason=='overshoot' and terminal.overshoot==1,'overshoot is never an exact deadline claim')
x=push();terminal=finish(x,150,true,'UpdateSRAM')
check(terminal.censored and terminal.reason=='early-end' and terminal.source=='UpdateSRAM','early end retains authoritative source and censorship')
x=push();terminal=finish(x,90,false)
check(terminal.censored and terminal.reason=='clock-discontinuity','reset/backwards jump is censored')
x=push();x:raceTimeBind(0,plan);x:raceTimeEvent({actor=0,id=7,event='unresolved',reason='battle_ended'})
-- No pending trace in this new driver: canceled ownership is tested bound below.
x.recovery={pending={[0]={id=19}}};x:raceTimeBind(0,plan);x:raceTimeEvent({actor=0,id=19,event='submit'});x:raceTimeEvent({actor=0,id=19,event='unresolved',reason='battle_ended'})
terminal=finish(x,300,false)
check(terminal.censored and terminal.lifecycle.accepted and terminal.lifecycle.canceled=='battle_ended' and not terminal.lifecycle.resolved,'accepted canceled action cannot claim resolved calibration')
x=push();bindValid(x);ram[0x3EE4]=2;word(0x3BF4,543);terminal=finish(x,300,false)
check(terminal.censored and terminal.endpoint.party[0].st1==2 and terminal.endpoint.party[0].hp==543 and terminal.actualDown==0,'positive HP status change retained separately and censored')
ram[0x3EE4]=0;word(0x3BF4,1000)
x=push();bindValid(x);ram[0x3ED8]=6;terminal=finish(x,300,false)
check(terminal.censored and not terminal.identityKnown and terminal.initial[0].char==0 and terminal.actualDown==0,'changed identity is unknown rather than replacement HP')
ram[0x3ED8]=0
x=push();ram[0x3ED8]=6;word(0x3A3E,110);x:raceTimeTick(H.raceTimeSample(),false,'watch')
word(0x3A3E,120);x:raceTimeTick(H.raceTimeSample(),false,'watch')
check(#x.raceTimeActive[1].history==2,'unchanged missing identities do not grow sampled transition history')
ram[0x3ED8]=0
x=push();bindValid(x);ram[0x3A39]=1;terminal=finish(x,300,false)
check(terminal.censored and terminal.actualRemoved==1 and terminal.actualDown==0,
 'positive HP removal is separate and comparison censored')
ram[0x3A39]=0
-- Default-off real selection performs no shadow sampling or evaluation.
H.RACE_TIME_DIAGNOSTIC=false;H.CARE_RACE='log'
local off=driver();off.makePlanRules=function(self)self._race={actor=0};return plan end
local evalCalls=0;off.raceLog=function(self)self._racePred=rp();return nil end
local realPair=H.raceTimePair;H.raceTimePair=function(...)evalCalls=evalCalls+1;return realPair(...)end
check(off:makePlan(0)==plan and evalCalls==0 and off.raceTimeActive==nil,'default-off production selection does no shadow evaluation')
H.RACE_TIME_DIAGNOSTIC=true;H.raceTimePair=function()error('injected shadow failure')end
check(off:makePlan(0)==plan and logs[#logs]:find('declined error:'),'shadow failures are visible without altering ordinary selected plan')
H.raceTimePair=realPair
-- Real makePlan leaves its selected controller plan unchanged.
H.CARE_RACE='log';x=driver();local originalPlan={kind='fight',boostLeft=0}
x.makePlanRules=function(self)self._race={actor=0};return originalPlan end
x.raceLog=function(self)self._racePred=rp();return nil end
H.CARE_RACE='log';word(0x3A3E,100)
check(x:makePlan(0)==originalPlan and x.raceTimeActive[1].selected=='rules','production selection wires shadow without changing plan')
-- Actual button planning registers trace ownership for the selected plan.
ram[0x7BCA],ram[0x7BC2]=1,5;originalPlan.row=0
x:button(0)
check(x.raceTimeActive[#x.raceTimeActive].lifecycle.id==x.recovery.pending[0].id,
 'production button binds new selected plan to real recovery trace')
H.CARE_RACE=false;ram[0x7BCA],ram[0x7BC2]=0,0
-- Real watch/end hook: one coherent UpdateSRAM snapshot before reset.
x=push();x.battleTick=6;x:watchLeavers();word(0x3A3E,150);word(0x3BF4,800);H.frame=1200
x:watchLeavers();callbacks[12345]()
local outcome=H.lastOutcome
check(outcome.atEnd and outcome.timeShadows and outcome.timeShadows[1].source=='UpdateSRAM' and outcome.timeShadows[1].tick==150,'end hook flushes pre-reset clock into outcome')
check(outcome.timeShadows[1].endpoint.party[0].hp==800 and outcome.timeShadows[1].frame==1200,'end snapshot pairs HP/status with its clock/frame')
local old=outcome.timeShadows
x:idle();check(x.raceTimeActive==nil and x.raceTimeRecords==nil and old[1].tick==150,'battle cleanup resets observer while outcome retains terminal record')
-- Use new battle well outside stale-tail window, then fallback last-watch.
word(0x3BF4,1000);word(0x3A3E,100);H.frame=2000;x.battleTick=1;x:watchLeavers();x:raceTimePush(0,rp(),'rules',plan)
H.frame=2100;word(0x3A3E,120);x.battleTick=6;x:watchLeavers();x:sayOutcome()
check(not H.lastOutcome.atEnd and H.lastOutcome.timeShadows[1].source=='last-watch' and H.lastOutcome.timeShadows[1].censored,'fallback is explicitly last-watch and censored')
check(H.lastOutcome.timeShadows~=old and old[1].tick==150,'reused driver cannot rewrite prior battle record')
check(logs[#logs]:find('outcome')~=nil,'existing outcome log still emitted')
print(string.format('race_time_shadow_selftest: PASS -- %d checks',n))
