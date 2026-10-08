-- @manual standalone: lua tools/tests/race_time_selftest.lua [library]
-- Synthetic event-window arithmetic; no play or acting-policy claim.
emu={eventType={inputPolled=1},addEventCallback=function() return 1 end}
local H=dofile(arg[1] or 'tools/tests/lib/ot6.lua')
local n=0
local function check(ok,msg) assert(ok,msg);n=n+1 end
local function state(broken)
 return {actor=0,horizon=3,contCare=false,boost=false,
  party={[0]={hp=1000,maxhp=1000,eta=0,period=100,bp=0,
    lines={[0]={per=0,hits=1,chips=0}}}},
  enemies={[0]={hp=1000,sh=0,eta=0,period=100,brokenLeft=broken,
    act={aim=0,hit=1,dmg={[0]=10}}}}}
end
local function sim(st,delay)
 return H.raceSim(st,{kind='attack',boost=0,delay=delay or 0,line=st.party[0].lines[0]},nil)
end
local st=state();local budget=H.raceTimeBudget(st)
check(budget==200,'predecision third enemy opportunity sets one elapsed budget')
st.timeHorizon=budget
local r=sim(st)
check(r.timeCutoff and r.elapsed==200 and r.opportunities==3 and r.unsuppressedTurns==3,
 'inclusive deadline processes events at deadline but none beyond')
check(r.resources.party[0].hp==970,'fixed deadline HP includes exactly its three hits')
local broken=state(150);broken.timeHorizon=budget;r=sim(broken)
check(r.opportunities==3 and r.breakSkips==2 and r.unsuppressedTurns==1,
 'suppressed opportunities and completed attacks are separate')
check(r.resources.party[0].hp==990 and r.elapsed==budget,'break gets same elapsed comparison window')
local extended=state(450);extended.timeHorizon=500;r=sim(extended)
check(r.elapsed==500 and r.opportunities==6 and r.breakSkips==5 and r.unsuppressedTurns==1,'shadow elapsed deadline is independent of legacy opportunity cap')
local expiry=state(150);expiry.timeHorizon=200;expiry.enemies[0].shMax=3;expiry.enemies[0].period=1000;expiry.party[0].period=1000;r=sim(expiry)
check(r.resources.enemies[0].sh==3 and r.resources.enemies[0].breakUntil==nil,'break recovers at cutoff even with no event at that instant')
local delayed=state();delayed.timeHorizon=budget;r=sim(delayed,201)
check(r.pending and not r.firstExecuted and r.elapsed==budget,'command past deadline stays pending, never fabricated as executed')
local legacy=state();r=sim(legacy)
check(r.acts==4 and r.opportunities==3 and r.unsuppressedTurns==3 and not r.timeCutoff,
 'legacy opportunity horizon behavior is retained separately')
st=state();st.enemies[1]={hp=1000,sh=0,eta=20,period=100,act={}}
check(H.raceTimeBudget(st)==100,'interleaved enemies choose budget before candidate effects')
st.horizon=1
check(H.raceTimeBudget(st)==1,'zero-time full gauge budget gets one observable ATB tick')
st.horizon=3
st.enemies[0].period=0
check(H.raceTimeBudget(st)==nil,'invalid zero period declines time-window comparison')
st=state();st.enemies[0].period=0/0
check(H.raceTimeBudget(st)==nil,'nonfinite period declines time-window comparison')
st=state();st.horizon=1;st.enemies[0].eta=32767.5
check(H.raceTimeBudget(st)==nil,'rounded budget must still fit the half-range clock bound')
st=state();st.enemies[0].eta=32768
check(H.raceTimeBudget(st)==nil,'unbounded clock window is declined')
st=state();st.enemies={}
check(H.raceTimeBudget(st)==nil,'no enemy opportunity cannot invent a window')
st=state();st.timeHorizon=200;st.party[0].lines[0].per=2000
r=sim(st)
check(r.kill==0 and r.elapsed==0 and not r.timeCutoff,'early victory remains early, not a full-window observation')
st=state();st.timeHorizon=200;st.party[0].hp=5;r=sim(st)
check(r.wipe and r.elapsed==0 and r.unsuppressedTurns==1,'enemy tie and early wipe retain their terminal time')
local L=H.newRaceTimeObservation(65530,10)
check(L.observe(65530)==nil and L.elapsed==0,'menu pause consumes no elapsed ATB budget')
check(L.observe(2)==nil and L.elapsed==8,'16-bit wrap preserves elapsed ATB ticks')
local finish=L.observe(4)
check(finish.reason=='deadline' and not finish.censored and finish.elapsed==10 and finish.overshoot==0,
 'observed deadline is independent of enemy completed-action count')
check(L.observe(50,true)==finish,'observation is finalized once')
L=H.newRaceTimeObservation(100,10);finish=L.observe(113)
check(finish.censored and finish.reason=='overshoot' and finish.elapsed==13 and finish.overshoot==3,'sampling overshoot is explicit rather than exact-cutoff claim')
L=H.newRaceTimeObservation(100,10);finish=L.observe(104,true)
check(finish.censored and finish.reason=='early-end' and finish.elapsed==4,'early battle end is censored at actual duration')
L=H.newRaceTimeObservation(100,10);finish=L.observe(90)
check(finish.censored and finish.reason=='clock-discontinuity','counter reset is unknown rather than a huge elapsed interval')
for _,bad in ipairs({-1,32768,math.huge,0/0}) do
 check(not pcall(H.newRaceTimeObservation,0,bad),'bad live budget is rejected')
 local badst=state();badst.timeHorizon=bad
 check(not pcall(sim,badst),'bad simulation budget is rejected')
end
print(string.format('race_time_selftest: PASS -- %d checks',n))
