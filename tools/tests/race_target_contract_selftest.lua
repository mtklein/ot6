-- @manual standalone: lua tools/tests/race_target_contract_selftest.lua [case] [library]
-- Read-only synthetic controller reads: production button decisions, not play.
emu={eventType={inputPolled=1},addEventCallback=function() return 1 end}
local H=dofile(arg[2] or 'tools/tests/lib/ot6.lua')
local ram={}
H.readByte=function(a) return ram[a] or 0 end
H.readWord=function(a) return (ram[a] or 0)|((ram[a+1] or 0)<<8) end
H.log=function() end
H.itemProps=function() return 0 end;H.itemPower=function() return 50 end
local function driver()
  ram={};ram[0x7bca]=1;ram[0x3bf4]=100
  ram[0x3bfc],ram[0x3bfe],ram[0x3aa8],ram[0x3aaa]=100,100,1,1
  -- Real command-table stride, Item at row 1; inventory lookup isolated.
  ram[0x202e]=1;ram[0x202f]=0;ram[0x302c]=0;ram[0x302d]=0x21;ram[0x2103]=1
  local d=H.newFightDriver('target contract',{}).driver
  d.battInvIdx=function() return 0 end;d.steerWatch=function() end
  d.focusList=function() return {{slot=0,mask=1}} end
  d.focusReachable=function() return true end
  return d
end
local function attack(d) return assert(d:racePlan(0,{kind='attack',target=1,boost=0,line={plan={kind='fight',row=0}}})) end
local function item(d,raise) return assert(d:racePlan(0,{kind=raise and 'raise' or 'heal',target=1,id=0xe9,restore=50})) end
local function target(d,p,chars,mons)
  d.plan,d.planActor=p,0;d.tgtSpin=40
  ram[0x7bc2],ram[0x7b7d],ram[0x7b7e]=0x38,chars,mons
end
local cases={}
cases.physical=function()
  local d=driver();local p=attack(d);target(d,p,0,1)
  local b=d:button(0);assert(b and b[1]=='b' and not d.plan,'unreachable scored Fight must back out, never confirm another body')
end
cases.item=function()
  for _,raise in ipairs({false,true}) do
    local d=driver();local p=item(d,raise);target(d,p,1,0);d.steerDead={down=2}
    local b=d:button(0);assert(b and b[1]=='b' and not d.plan,'unreachable scored heal/raise must back out')
  end
end
cases.zero=function()
  for _,raise in ipairs({false,true}) do for pending=0,3 do
    local d=driver();local p=item(d,raise);d.plan,d.planActor=p,0
    ram[0x7bc2],ram[0x3e9c],ram[0x3e9d],ram[0x7bd8]=5,3,pending,1
    local b=d:button(0);assert(b and b[1]==(pending>0 and 'l' or 'a'),'item/raise must acknowledge exact zero before opening list')
  end end
end
cases.matched=function()
  for _,kind in ipairs({'fight','item','raise'}) do
    local d=driver();local p=kind=='fight' and attack(d) or item(d,kind=='raise')
    target(d,p,kind=='fight' and 0 or 2,kind=='fight' and 2 or 0)
    H.itemProps=function() return 0 end;H.itemPower=function() return 50 end
    local b=d:button(0);assert(b and b[1]=='a' and not d.plan,'matched scored mask confirms through common bookkeeping')
  end
end
cases.queue=function()
  local d=driver();local p=attack(d);local ev={}
  local T=H.newRecoveryTrace('target ack',function(e) ev[#ev+1]=e end)
  T.plan(0,p,0);T.submit(0,1,0,0,0x100,0)
  assert(ev[#ev].reason=='race_submission_mismatch','wrong physical submitted mask rejected')
  T.plan(0,p,2);T.submit(0,3,0,0,0x200,0);T.queueStore(0,2,0,0,4,0x100)
  assert(ev[#ev].reason=='race_queue_identity_mismatch','changed queued initial mask rejected')
  T.plan(0,p,5);T.submit(0,6,0,0,0x200,0);T.queueStore(0,2,0,0,7,0x200)
  local s=T.start(0,8,0,0,0x200,{100,100,100,100},10,1,{queue_index=2,queued_command=0,queued_attack=0})
  assert(s and s.trace_id,'matched physical ownership acquired')
  T.hpEffect(0,9,4,100,0,0,0,{context=s,queued_command=0,queued_attack=0})
  assert(ev[#ev].event=='hp_effect','engine retarget after initial acceptance remains legal')
end
cases.unsupported=function()
  local d=driver();assert(not d:racePlan(0,{kind='attack',target=1,line={plan={kind='skill',cmd=10,skill=0x5d}}}),'no-target Blitz stays ordinary until enforceable recipe exists')
end
cases.tools=function()
  for _,all in ipairs({false,true}) do
    local d=driver();local p=assert(d:racePlan(0,{kind='attack',target=1,boost=0,
      line={aoe=all,plan={kind='skill',cmd=9,skill=all and 0xaa or 0xab,row=0}}}))
    assert(p.targetContract.monsters==(all and 3 or 2),'Tools binds its single body or whole standing group')
    target(d,p,0,all and 3 or 2);ram[0x7b7f]=all and 1 or 0
    local b=d:button(0);assert(b and b[1]=='a','matched Tools confirms')
    d=driver();p=assert(d:racePlan(0,{kind='attack',target=1,line={aoe=all,plan={kind='skill',cmd=9,skill=0xaa,row=0}}}))
    target(d,p,0,1);ram[0x7b7f]=all and 1 or 0;b=d:button(0)
    assert(b and b[1]=='b','changed Tools initial mask never confirms')
  end
end
cases.ordinary=function()
  local d=driver();target(d,{kind='fight',row=0,aim=1},0,1)
  local b=d:button(0);assert(b and b[1]=='a','ordinary target fallback remains')
end
cases.repeated=function()
  local d=driver();local old=H.CARE_RACE;H.CARE_RACE='act'
  local rules={kind='fight',row=0,aim=0};local selections=0
  d.makePlanRules=function(self,actor) self._race={actor=actor};return rules end
  d.raceLog=function() selections=selections+1;return {kind='attack',target=1,boost=0,
    line={aoe=true,plan={kind='skill',cmd=9,skill=0xaa,row=0}}} end
  local p=d:makePlan(0);assert(p.targetContract,'first choice can use ACT')
  target(d,p,0,1);local b=d:button(0);assert(b and b[1]=='b','first mismatch backs out')
  for turn=1,3 do
    p=d:makePlan(0);assert(p==rules and not p.targetContract,'repeated replans must keep ordinary fallback')
    target(d,p,0,1);b=d:button(0);assert(b and b[1]=='a','ordinary fallback commits and progresses')
  end
  assert(selections==1,'failed scored choice is not repeatedly reconsidered')
  d:idle();p=d:makePlan(0);assert(p.targetContract and selections==2,'new battle restores ACT eligibility')
  d.plan,d.planActor=p,0;ram[0x7bc2],ram[0x3e9d]=5,4
  b=d:button(0);assert(not b and d.raceActDeclined,'actual unavailable boost acknowledgment also falls back')
  d:idle();assert(not d.raceActDeclined,'driver boundary reset clears fallback')
  H.CARE_RACE=old
end
cases.candidate_keys=function()
  local d=driver();d.opts.boost=true
  local function line(target,boost,skill)
    return {target=target,boost=boost or 0,plan={kind='skill',cmd=9,skill=skill or 0xaa}}
  end
  local targets={{1},1,{1,2},{2,1},{1,3},{}}
  local actions={}
  for _,t in ipairs(targets) do actions[#actions+1]=line(t) end
  actions[#actions+1]=line(nil)
  actions[#actions+1]=line({1,2}) -- independently allocated equivalent list
  actions[#actions+1]=line({1,2},1)
  actions[#actions+1]=line({1,2},0,0xab)
  local st={party={[0]={bp=3,hp=100,noCare=true,actions=actions}}}
  local c=d:raceCandidates(0,st)
  assert(#c==9,'keys distinguish scalar/list, order, contents, absent/empty, boost and skill; equivalent lists deduplicate')
  for i,t in ipairs(targets) do assert(c[i].target==t,'candidate targets retain original ordered contents') end
  assert(c[7].target==nil and c[8].boost==1 and c[9].line.plan.skill==0xab,'other action identity remains distinct')
end
local names={'physical','item','zero','matched','queue','unsupported','tools','ordinary','repeated','candidate_keys'}
if arg[1] then assert(cases[arg[1]])() else for _,name in ipairs(names) do cases[name]() end end
print('race_target_contract_selftest: PASS '..(arg[1] or 'all'))
