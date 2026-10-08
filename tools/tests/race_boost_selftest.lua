-- @manual standalone: lua tools/tests/race_boost_selftest.lua
-- Synthetic controller contracts: stub reads only, no gameplay claim.
local mem = {}
emu = {
  eventType = { inputPolled = 1 }, memType = { snesWorkRam = 1 },
  addEventCallback = function() return 1 end,
  read = function(a) return mem[a] or 0 end,
  readWord = function(a) return (mem[a] or 0) | ((mem[a+1] or 0) << 8) end,
}
local H = dofile(arg[1] or "tools/tests/lib/ot6.lua")
H.log = function() end
local n = 0
local function check(ok,why) assert(ok,why); n=n+1 end
for actor=0,3 do
  for want=0,3 do
    for pending=0,3 do
      for bank=0,5 do
        for k in pairs(mem) do mem[k]=nil end
        mem[0x7BCA],mem[0x7BC2]=1,5
        mem[0x3E9C+2*actor],mem[0x3E9D+2*actor]=bank,pending
        mem[0x3BF4+2*actor]=100
        local d=H.newFightDriver("exact boost contract",{}).driver
        local c={kind="attack",boost=want,target=0,
          line={plan={kind="fight",row=0,boostLeft=want}}}
        local p=d:racePlan(actor,c)
        check(p.exactBoost and p.boostWant==want,"compiler owns exact total including zero")
        check(c.line.plan.exactBoost==nil,"compiler does not mutate cached line plan")
        d.plan,d.planActor=p,actor
        local got=d:button(actor)
        local expected=bank<want and "drop" or pending>want and "l" or pending<want and "r" or "a"
        check(expected=="drop" and d.plan==nil and got==nil or got and got[1]==expected,
          string.format("actor%d pending%d want%d bank%d expected%s got%s",actor,pending,want,bank,expected,got and got[1] or "nil"))
      end
    end
  end
end
-- Exact steering is acknowledged from live reads even when the old pulse
-- diagnostic lever is enabled. Missed R presses cannot become a commit.
for _,pulses in ipairs({false,true}) do
  H.BOOST_PULSES=pulses
  for k in pairs(mem) do mem[k]=nil end
  mem[0x7BCA],mem[0x7BC2],mem[0x3BF4],mem[0x3E9C],mem[0x3E9D]=1,5,100,3,1
  local d=H.newFightDriver("missing boost acknowledgment",{}).driver
  d.plan,d.planActor={kind="fight",row=0,boostLeft=2,exactBoost=true,boostWant=2},0
  local dropped=false
  for i=1,45 do
    local got=d:button(0)
    check(not got or got[1]~="a","unacknowledged R never confirms a different scored action")
    if d.plan==nil then dropped=true;break end
  end
  check(dropped,"existing watchdog bounds unanswered exact boost")
end
H.BOOST_PULSES=false
for _,args in ipairs({{0,4,5},{0,1.5,5},{4,0,5},{0,0,6}}) do
  check(H.exactBoostStep(table.unpack(args))=="drop","malformed exact boost rejected")
end
print(string.format("race_boost_selftest: PASS -- %d checks",n))
