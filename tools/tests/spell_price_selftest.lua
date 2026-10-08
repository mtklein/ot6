-- @manual standalone: lua tools/tests/spell_price_selftest.lua
-- Synthetic arithmetic contracts, not play: ROM/RAM reads are stubbed.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile(arg[1] or "tools/tests/lib/ot6.lua")
assert(loadfile("tools/tests/lib/ot6_field.lua"))(H)
local ram, rom, n = {}, {}, 0
H.readByte = function(a) return ram[a] or 0 end
H.readRomByte = function(a) return assert(rom[a], string.format("unexpected ROM read $%X", a)) end
H.sym = function(s)
  if s == "Ot6FoldTbl" then return 0x1000 end
  if s == "MagicProp" then return 0x2000 end
  error("unexpected symbol " .. s)
end
local function check(ok, why) assert(ok, why); n = n + 1 end
local families = {
  {0,5,9}, {1,6,10}, {2,7,11}, {3,8,8},
  {45,46,47}, {48,49,53}, {25,40,40}, {31,39,39},
}
for r, ids in ipairs(families) do
  for i, id in ipairs(ids) do rom[0x1000+(r-1)*3+i-1] = id end
end
local costs = {[0]=4,[5]=20,[9]=51,[16]=8,[0x36]=110}
for id=0,255 do rom[0x2000+14*id+5] = costs[id] or 60 end
-- The expected prices below are independent ROM examples, not computed
-- by the library under test. Odd costs distinguish rounding direction.
local expected = {
  [0] = {[0]={4,20,51,51}, [0x20]={2,10,26,26}, [0x40]={1,1,1,1}, [0x60]={1,1,1,1}},
  [9] = {[0]={51,51,51,51}, [0x20]={26,26,26,26}, [0x40]={1,1,1,1}, [0x60]={1,1,1,1}},
  [16] = {[0]={8,20,50,99}, [0x20]={4,10,25,63}, [0x40]={1,3,6,16}, [0x60]={1,3,6,16}},
  [0x36] = {[0]={110,110,110,110}, [0x20]={55,99,99,99}, [0x40]={1,3,6,16}, [0x60]={1,3,6,16}},
}
for actor=0,3 do
  for id, byRelic in pairs(expected) do
    for relic, prices in pairs(byRelic) do
      -- Other actors have different relics: catches actor-offset mistakes.
      for e=0,3 do ram[0x3C45+e*2] = e==actor and relic or (relic ~ 0x60) end
      for b=0,3 do
        local price, resolved = H.battleSpellPrice(actor,id,b)
        check(price==prices[b+1], string.format("caster%d spell$%02X relic$%02X boost%d price got%d want%d",actor,id,relic,b,price,prices[b+1]))
        check(resolved==(id==0 and ({0,5,9,9})[b+1] or id), "fold resolves once; owned tier and nonfamily retain identity")
      end
    end
  end
end
-- A pending-one nonfamily list displays 20; repricing from raw8 still
-- costs20 at TOTAL boost1. No menu price is read or invertibly assumed.
ram[0x3C45]=0
check(H.battleSpellPrice(0,16,1)==20, "pending menu price cannot be boosted twice")
check(H.casterSpellMp(255,0x20)==0, "eight-bit INC wraps before hairpin LSR")
check(H.casterSpellMp(0,0x40)==1, "Economizer sets even a zero raw cost to one")
for _,args in ipairs({{-1,0,0},{4,0,0},{0,-1,0},{0,256,0},{0,0,-1},{0,0,4},{0,0,1.5}}) do
  check(not pcall(H.battleSpellPrice,table.unpack(args)), "malformed catalogue price rejected")
end
print(string.format("spell_price_selftest: PASS -- %d checks", n))
