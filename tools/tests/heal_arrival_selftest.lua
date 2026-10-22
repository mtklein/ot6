-- @manual standalone: lua tools/tests/heal_arrival_selftest.lua  (after ninja build/ot6.sfc)
-- heal_arrival_selftest.lua -- when a heal lands (#459) and the Love Token
-- cover (#466).  Synthetic contracts: RAM is a stub table, the item and
-- spell records come from build/ot6.sfc at ff6/rom/ff6-en.dbg's symbols;
-- no emulator, no gameplay claim (the played evidence is cited in
-- lib/ot6.lua at M.healArrival and M.loveGuard).
--
--   1. M.healArrival: the enemy actions due before a heal lands, at their
--      typical price -- Tzen's Cure (#454) still goes, the queued hits on
--      the tower's White Dragon and on Wrexsoul beat theirs;
--   2. M.inTimeLift: the earliest heal that lands in time and lifts;
--   3. Driver:healArrivalTicks: the route's median, an item's walk from the
--      list cursor, this battle's own median once measured;
--   4. Driver:makePlanRules on a stubbed battle: #436's X-Potion from row 32
--      gives way to the Cure that lands first (the old rules drank it, as at
--      v0.30), a cure the queued hit beats is not cast on an ally, and the
--      spend rule no longer counts a self-heal that lands too late as saving;
--   5. M.loveGuard / Driver:coverPlan: a Fight on a body under Love Token is
--      re-aimed at a body without it, else cast, else stands.
-- M.HEAL_ARRIVAL_OFF and COVER_OFF are the driver before #459 and #466; the
-- old-driver arms below run with them.  Mutants: build/attempts/wt/
-- v036-driver/mut/ (mkmut.py there builds each from lib/ot6.lua).
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local symMemo = {}
H.sym = function(name)
  if symMemo[name] == nil then
    local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
    symMemo[name] = assert(tonumber(val, 16), name .. " in ff6-en.dbg")
  end
  return symMemo[name]
end
H.readRomByte = function(off) return rom:byte(off + 1) end
H.readRomWord = function(off) return rom:byte(off + 1) | (rom:byte(off + 2) << 8) end
local mem = {}
local function w8(a, v) mem[a] = v & 0xFF end
local function w16(a, v) mem[a] = v & 0xFF; mem[a + 1] = (v >> 8) & 0xFF end
H.readByte = function(a) return mem[a] or 0 end
H.readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end
local logs = {}
H.log = function(l) logs[#logs + 1] = l end
local function said(pat)
  for _, l in ipairs(logs) do if l:find(pat, 1, true) then return l end end
  return nil
end

local n = 0
local function check(ok, what) assert(ok, what); n = n + 1 end

-- the battle cells the stubs fill (lib/ot6.lua's BATTLE table)
local HP, MAXHP, ATB, ATBC, CURMP, MAXMP = 0x3BF4, 0x3C1C, 0x3218, 0x3AC8, 0x3C08, 0x3C30
local CMDTBL, MLISTPTR, BCHID, BATTINV, ITEMSCR, ITEMROW = 0x202E, 0x302C, 0x3ED8, 0x2686, 0x8947, 0x894F
local MON_HP, MON_PRESENT = 0x3BFC, 0x3AA8
local CURE, POTION, XPOTION = 0x2D, 0xE9, 0xEA
local function reset() mem, logs = {}, {}; w8(0x3403, 0xFF) end
-- a seated member: full gauge (deciding) unless eta; Fight, Magic, Item; Cure at 5 MP
local function member(e, hp, maxhp, period, o)
  o = o or {}
  w16(HP + e * 2, hp); w16(MAXHP + e * 2, maxhp)
  local const = math.ceil(0xFF00 / period)
  while math.ceil(0xFF00 / const) > period do const = const + 1 end
  w16(ATBC + e * 2, const)
  w16(ATB + e * 2, (o.eta or 0) == 0 and 0 or (0x10000 - o.eta * const))
  w16(CURMP + e * 2, o.mp or 300); w16(MAXMP + e * 2, o.mp or 300)
  w8(BCHID + e * 2, e)
  for r = 0, 3 do w8(CMDTBL + e * 12 + r * 3, (o.cmds or { 0x00, 0x02, 0x01, 0xFF })[r + 1]) end
  local base = 0x2100 + e * 0x100
  w16(MLISTPTR + e * 2, base)
  for c = 0, 53 do w8(base + (c + 1) * 4, 0xFF) end
  w8(base + 4, CURE); w8(base + 5, 0); w8(base + 7, 5)
end
local function monster(s, hp, eta, period)
  w16(MON_HP + s * 2, hp); w8(MON_PRESENT + s * 2, 1)
  local const = math.ceil(0xFF00 / period)
  while math.ceil(0xFF00 / const) > period do const = const + 1 end
  w16(ATBC + 8 + s * 2, const)
  w16(ATB + 8 + s * 2, eta == 0 and 0 or (0x10000 - eta * const))
end
local function bag(list)
  for i = 0, 251 do w8(BATTINV + i * 5, 0xFF) end
  for i, it in pairs(list) do w8(BATTINV + i * 5, it[1]); w8(BATTINV + i * 5 + 3, it[2]) end
end
local function driver(opts)
  local D = H.newFightDriver("sim", opts or { items = true, boost = true }).driver
  return D
end

-- 1. M.healArrival ----------------------------------------------------------
do
  -- Tzen (#454, build/attempts/qual-v033.ninja.log): CELES 82/1043, s2 118
  -- ticks from full (worst 123, typical 64), s0 294 (worst 122, typical 68);
  -- the Cure lands at 240: one action ahead at 64 typical -- it still goes
  local tzen = { { slot = 0, eta = 294, period = 303, worst = 122, typical = 68 },
                 { slot = 2, eta = 118, period = 272, worst = 123, typical = 64 } }
  local a = H.healArrival({ hp = 82, arrive = 240, enemies = tzen })
  check(a.n == 1 and a.cost == 64 and a.worst == 123 and not a.beaten,
    "Tzen: one action ahead of the Cure, 64 typical under 82 HP, not beaten; got " .. a.why)
  check(H.healArrival({ hp = 64, arrive = 240, enemies = tzen }).beaten, "at 64 HP the typical hit ahead takes it all")
  check(not H.healArrival({ hp = 65, arrive = 240, enemies = tzen }).beaten, "at 65 HP it does not")
  check(H.healArrival({ hp = 82, arrive = 117, enemies = tzen }).n == 0, "an action due after the heal is not ahead")
  check(H.healArrival({ hp = 82, arrive = 118, enemies = tzen }).n == 1, "one due on the heal's tick is")
  check(H.healArrival({ hp = 82, arrive = 400, enemies = tzen }).n == 3, "s2 twice inside 400 ticks (118, 390), s0 once")
  check(H.healArrival({ hp = 1, arrive = 400, enemies = {} }).beaten == false, "no enemy, nothing ahead")
  -- the tower's White Dragon (build/attempts/wt/v036-route/lab/tw2_k0_s0):
  -- entity 3 at 1321, s0's gauge full (its action queued), one action seen
  -- (1898): no typical yet, so its worst, twice inside 240 ticks
  local wd = H.healArrival({ hp = 1321, arrive = 240, enemies = { { slot = 0, eta = 0, period = 182, worst = 1898 } } })
  check(wd.beaten and wd.n == 2 and wd.cost == 3796, "the White Dragon's queued 1898 beats the Cure; got " .. wd.why)
  -- Wrexsoul (build/attempts/wt/v036-route/lab/sdo8_k1_s7): entity 3 at 200,
  -- both gauges full (207 and 194)
  check(H.healArrival({ hp = 200, arrive = 240, enemies = { { slot = 3, eta = 0, period = 389, worst = 207 },
    { slot = 4, eta = 0, period = 389, worst = 194 } } }).beaten, "Wrexsoul's two queued hits beat the self-cure")
  -- an unmeasured enemy at its ROM price, else the battle's worst
  check(H.healArrival({ hp = 300, arrive = 100, enemies = { { slot = 0, eta = 0, rom = 300 } } }).beaten,
    "a ROM-priced action ahead counts")
  check(H.healArrival({ hp = 300, arrive = 100, enemies = { { slot = 0, eta = 0 } }, fallback = 299 }).cost == 299,
    "nothing priced: the battle's worst")
  check(H.healArrival({ hp = 300, arrive = 100, enemies = { { slot = 0, eta = 0, worst = 50, typical = 80 } } }).cost == 50,
    "a typical never above the worst")
end

-- 2. M.inTimeLift -----------------------------------------------------------
do
  local hs = { { what = "late", restore = 900, arrive = 100, late = true },
               { what = "slow", restore = 400, arrive = 300, late = false },
               { what = "quick", restore = 400, arrive = 200, late = false },
               { what = "small", restore = 100, arrive = 50, late = false },
               { what = "unknown", restore = nil, arrive = 10, late = false } }
  check(H.inTimeLift(172, 468, hs).what == "quick", "the earliest in-time heal that lifts")
  check(H.inTimeLift(172, 572, hs) == nil, "none lifts 172 over 572 in time (the late one would)")
  check(H.inTimeLift(172, 270, hs).what == "small", "the small heal lifts a small round and lands first")
end

-- 3. Driver:healArrivalTicks -------------------------------------------------
do
  reset()
  bag({ [0] = { POTION, 50 }, [32] = { XPOTION, 9 } })
  local D = driver()
  check(D:healArrivalTicks(1, "heal", CURE) == H.HEAL_ARRIVAL.heal, "a cure: the route's median")
  check(D:healArrivalTicks(1, "item", POTION) == H.HEAL_ARRIVAL.item, "the Potion at the cursor: the median")
  check(D:healArrivalTicks(1, "item", XPOTION) == H.HEAL_ARRIVAL.item + 10 * H.HEAL_ARRIVAL_WALK,
    "the X-Potion 32 rows down: ten pulses of walking more")
  w8(ITEMSCR + 1, 28); w8(ITEMROW + 1, 2)
  check(D:healArrivalTicks(1, "item", XPOTION) == H.HEAL_ARRIVAL.item, "with the cursor at row 30, two rows away")
  D.raceEffectLatency = { ["1:heal:45:0"] = { { first = 300 }, { first = 100 }, { first = 200 } } }
  local t, src = D:healArrivalTicks(1, "heal", CURE)
  check(t == 200 and src == "measured this battle", "this battle's own median once measured, got " .. tostring(t))
  check(D:healArrivalTicks(0, "heal", CURE) == H.HEAL_ARRIVAL.heal, "another actor's measure is not this one's")
end

-- 4. Driver:makePlanRules ---------------------------------------------------
-- #436 at v0.30 (build/attempts/wt/v030-release-qualification/final-8efd9290/
-- ninja.log): CELES alone at 172/1043 under Slow (a 403-tick window), s0's
-- gauge full, s2 31 ticks off, s1 294; a round 468; Cure measured at 365, a
-- Potion 250, an X-Potion 871 thirty-two rows down the bag
local function x436()
  reset()
  member(0, 172, 1043, 403, { mp = 227 })
  monster(0, 850, 0, 303); monster(1, 777, 294, 303); monster(2, 458, 31, 272)
  bag({ [0] = { POTION, 82 }, [32] = { XPOTION, 9 } })
  local D = driver()
  D.hitLedger[0] = { max = 69, maxOn = { [0] = 69 }, actN = 3, actSum = 195 }
  D.hitLedger[1] = { max = 139, maxOn = { [0] = 139 }, actN = 1, actSum = 139 }
  D.hitLedger[2] = { max = 131, maxOn = { [0] = 131 }, actN = 3, actSum = 192 }
  D.castRestore[CURE] = 365
  D.itemRestore[POTION], D.itemRestore[XPOTION] = 250, 871
  return D:makePlanRules(0)
end
do
  H.HEAL_ARRIVAL_OFF = true
  local p = x436()
  check(said("a round costs 468 (5 enemy action(s) inside 403 ticks") ~= nil, "the v0.30 round, priced the same")
  check(p.kind == "item" and p.item == XPOTION, "the old rules drink the X-Potion, as at v0.30")
  H.HEAL_ARRIVAL_OFF = false
  p = x436()
  check(said("no item on entity 0 (172/1043) that lands after the target falls (#459): $EA in about 437 ticks") ~= nil,
    "the X-Potion is said to land too late")
  check(p.kind == "heal" and p.spell == CURE and p.target == 0, "the Cure that lands first, got " .. tostring(p.kind))
  check(said("the faster heal for the one that lands too late (#459)") ~= nil, "and why")
end
-- the White Dragon (tw2_k0_s0): actor 1 deciding, entity 3 at 1321/3219 with
-- s0's gauge full and its 1898 seen; Cure measured at 705
local function wd()
  reset()
  member(0, 3000, 3000, 202, { eta = 120 })
  member(1, 3595, 3595, 218)
  member(2, 3000, 3000, 202, { eta = 150 })
  member(3, 1321, 3219, 202, { eta = 65 })
  monster(0, 20000, 0, 182)
  bag({})
  local D = driver()
  D.hitLedger[0] = { max = 1898, maxOn = { [3] = 1898 }, actN = 1, actSum = 1898 }
  D.castRestore[CURE] = 705
  return D:makePlanRules(1)
end
do
  H.HEAL_ARRIVAL_OFF = true
  local p = wd()
  check(p.kind == "heal" and p.target == 3, "the old rules cure entity 3 under the queued 1898")
  H.HEAL_ARRIVAL_OFF = false
  p = wd()
  check(not (p.kind == "heal" and p.target == 3), "the cure the queued hit beats is not cast, got " .. tostring(p.kind))
  check(said("no cure on entity 3 (1321/3219): $2D lands in about 240 ticks") ~= nil, "and it is said why")
end
-- the spend rule: CELES at 82 with both gauges full ahead of her Cure (64
-- and 68 typical) holds 2 BP -- a self-heal that lands after she falls saves
-- nothing, so she spends; the old rules counted it as saving
local function selfLate()
  reset()
  member(0, 82, 1043, 396, { mp = 227 })
  monster(0, 850, 0, 303); monster(2, 458, 0, 272)
  bag({ [0] = { XPOTION, 9 } })
  w8(0x3E9C, 2)
  local D = driver({ items = true, boost = true })
  D.hitLedger[0] = { max = 122, maxOn = { [0] = 122 }, actN = 3, actSum = 204 }
  D.hitLedger[2] = { max = 123, maxOn = { [0] = 123 }, actN = 3, actSum = 192 }
  D.castRestore[CURE] = 377
  D.itemRestore[XPOTION] = 871
  return D:makePlanRules(0)
end
do
  H.HEAL_ARRIVAL_OFF = true
  local p = selfLate()
  check(said("no spend (care): cure $2D saves") ~= nil, "the old rules: the Cure saves, no spend")
  check(p.kind == "heal", "and she casts it")
  H.HEAL_ARRIVAL_OFF = false
  p = selfLate()
  check(said("cure $2D +377 = 459, it lands after") ~= nil, "the late Cure is listed as refused for the spend")
  check(said("item $EA +961 = 1043, it lands after") ~= nil, "and so is the late X-Potion")
  check(p.kind ~= "heal" and p.kind ~= "item", "she spends instead, got " .. tostring(p.kind))
end

-- 5. Love Token -------------------------------------------------------------
do
  local good = { guard = 0x02, present = true, controlling = false, seized = false, st = 0, st34 = 0 }
  local function with(k, v) local t = {} for a, b in pairs(good) do t[a] = b end t[k] = v return t end
  check(H.loveGuard(good) == 1, "RELM (entity offset 2) guards")
  check(H.loveGuard(with("guard", 0xFF)) == nil, "no token")
  check(H.loveGuard(with("guard", 0x0A)) == nil, "a monster guarding a monster is no party cover")
  check(H.loveGuard(with("present", false)) == nil, "an absent guard covers nothing")
  check(H.loveGuard(with("controlling", true)) == nil, "a controlling guard covers nothing")
  check(H.loveGuard(with("seized", true)) == nil, "a seized guard covers nothing")
  check(H.loveGuard(with("st", 0x0080)) == nil, "a fallen guard covers nothing")
  check(H.loveGuard(with("st", 0x8000)) == nil, "a sleeping guard covers nothing")
  check(H.loveGuard(with("st", 0x0020)) == 1, "an imp still covers (Imp is not in $A0D2)")
  check(H.loveGuard(with("st34", 0x0010)) == nil, "a stopped guard covers nothing")
end
local function barbe(o)
  reset()
  o = o or {}
  member(0, 2409, 3853, 188, { cmds = o.cmds })
  member(1, 4138, 4328, 185, { eta = 100 })
  monster(0, 2535, 100, 272)
  if o.second then monster(1, 1000, 150, 300) end
  w8(0x336C + 8, o.guard or 0x02)
  w8(0x336C + 10, 0xFF)
  w8(0x3AA0 + 2, 1); w8(0x32B9 + 2, 0x80); w8(0x3359 + 2, 0x80)
  local D = driver()
  D.magicOnlyLine = function() return { kind = "magic", spell = 0x00 } end
  return D, D:coverPlan(0, { kind = "fight", row = 0, boostLeft = 0 })
end
do
  local _, p = barbe({ guard = 0xFF })
  check(p.kind == "fight" and p.aim == nil, "no token: the Fight is left alone")
  _, p = barbe()
  check(p.kind == "magic", "a lone Barb-e under the token: a cast for the Fight, got " .. tostring(p.kind))
  check(said("every standing monster is under Love Token (slot 0's Fight lands on entity 1)") ~= nil, "and why")
  _, p = barbe({ second = true })
  check(p.kind == "fight" and p.aim == 1, "another body without the token: the Fight goes there")
  _, p = barbe({ cmds = { 0x00, 0x0B, 0x01, 0xFF } })
  check(p.kind == "fight" and said("the Fight stands (#466)") ~= nil, "no Magic row and no other body: the Fight stands")
  local D = barbe()
  check(D:coverPlan(0, { kind = "magic", spell = 0 }).kind == "magic", "a cast is not a Fight")
  check(D:coverPlan(0, { kind = "fight", ally = true, target = 1 }).ally, "an unmuddle hit on an ally is not re-aimed")
  COVER_OFF = true
  _, p = barbe()
  check(p.kind == "fight", "COVER_OFF: the driver before #466 swings into the bodyguard")
  COVER_OFF = nil
  -- the whole turn (Driver:makePlan): the rules' Fight on the lone Barb-e
  -- comes out a cast, the cover having run after them
  D = barbe()
  p = D:makePlan(0)
  check(p ~= nil and p.kind == "magic", "makePlan runs the cover: a cast, got " .. tostring(p and p.kind))
end

print(string.format("heal_arrival_selftest: PASS -- %d checks: the arrival's arithmetic on Tzen, the White "
  .. "Dragon and Wrexsoul, the in-time lift, the arrival's estimate, the X-Potion that gives way to the Cure, "
  .. "the queued hit that cancels a cure, the spend past a late self-heal, Love Token's guard and the Fight it turns", n))
