-- @suite savestate=crescent_landing
-- field_care_emptybag.lua -- #184: field care once the Tonics are gone.
--
-- The fixture is crescent_landing, a played state standing on the world
-- map at (232,150) with TERRA (who knows Cure), LOCKE and SHADOW.  Since
-- #213's Tonic stops it no longer arrives with an empty Tonic bag (the
-- #214 cut carries 61), so the suite empties it the way a player does:
-- corridor legs with the battles fought, and after each wound the field
-- menu's own Tonic, drunk to full (Potions held back, no casting), until
-- none are left.  A fixture that already arrives with 0 skips the drain.
-- Nobody is hurt at boot, so every case earns its patient the same way:
-- world-map legs with the battles fought (care switched off on the walk),
-- until somebody is under the threshold.  Reads and pad presses only; no
-- inventory or HP writes.
--
-- What #184's log actually shows (gen_zozo2_arrival attempt 1, lap 52,
-- copied under build/attempts/zozo-grind/): the "refusals" were not the
-- item menu's.  A random opened on the world map under the care's X
-- presses; the battle module keeps ZMENUSTATE at 05, which the "menu open"
-- wait accepted; DP $B5, which the kernel reads as the menu's mosaic
-- refusal byte, is battle RAM, so the Potion plan was "REFUSED" one frame
-- after it was made; the cast plan's presses walked the battle's Item
-- list; and the close drive's B's went into the fight for 2400 frames.
-- Potions with 0 Tonics had worked three laps earlier ("used $E9 on char
-- 5: 490 -> 568 hp, ..., 15 left").
--
-- Cases:
--   1. A battle opens under the driver-form care stop (M.careStop, the
--      form the navigators run between battles, which had no battle
--      guard): the stop yields within a few frames, spends nothing, and
--      the fight is then played.  The timing is the race's shape, driven
--      deterministically: the walk ends on the frame the battle load
--      starts and the care stop is asked for right there.
--   2. Driver form with 0 Tonics: the Potion is what heals.
--   3. Step form (M.fieldCare, magic off) with 0 Tonics: the Potion again.
--   4. Driver form with the Potions reserved away as well: nothing can be
--      done, the roster line says why, no menu opens, control stays.
--   5. Step form, default policy, with the Potions reserved away: TERRA
--      casts Cure out of her own MP, the bag untouched.
--
-- Cases 2-5 test the HP heal's fallbacks, so each switches the MP side's
-- two arms off (opts.tent = false, opts.tincture = false).  The landing
-- is on the world map, where the item list offers a Tent, and the care
-- pitches one ahead of any heal whenever the heals the bag would spend on
-- the party's HP hole cost at least the Tent's 1200 gil, or anybody is
-- under the MP band (docs/design/supply.md; field_tenthp).  A walk that
-- leaves that big a hole makes the Tent the right call, so with the arm
-- on, "the Potion heals" held only for draws that left less (the
-- 2026-09-28 chain's case 2: 1296 HP short, a Tent pitched, no Potion).
-- With no Tent on offer the Potion is what heals under any draw, and with
-- the Tincture arm off only a cast can move TERRA's MP.
local H = dofile("tools/tests/lib/ot6.lua")

local FIX = "build/states/crescent_landing.mss.lua"
local TONIC, POTION, FENIX, CURE = 0xE8, 0xE9, 0xF0, 0x2D
local THRESH = 0.95
local NORTH, SOUTH = { 232, 144 }, { 232, 150 }   -- the landing's corridor

-- every care line the lib logs, for assertions on what it said
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end
local function forget() lines = {} end

local battles, inBattle = 0, false
emu.addEventCallback(function()
  local live = H.battleLoadStarted()
  if live and not inBattle then inBattle = true; battles = battles + 1 end
  if not live and inBattle then inBattle = false end
end, emu.eventType.startFrame)

local function alive()
  for _, c in ipairs(H.partyMembers()) do
    if H.charHp(c) > 0 then return true end
  end
  return false
end
local function worst()
  local w, r = nil, 1.0
  for _, c in ipairs(H.partyMembers()) do
    local f = H.charHp(c) / H.charMaxHp(c)
    if H.charHp(c) > 0 and f < r then w, r = c, f end
  end
  return w, r
end
local function hurt()
  local _, r = worst()
  return r < THRESH
end
local function settled()
  return H.worldMode() and H.worldHasControl() and H.worldAligned()
     and not H.battleLoadStarted()
end
local function roster(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  H.log(string.format("[emptybag] %s: %s | tonic=%d potion=%d fenix=%d battles=%d f%d",
    tag, table.concat(out, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX), battles, H.frame))
end

-- A step rebuilt from scratch every time it runs.  Step objects close
-- over their state (a navigator keeps its plan, a driveUntil its frame
-- count, a seqStep its index), so a leg placed in a repeatN body would
-- run once and report itself done on every later iteration; `build`
-- makes a new one each time.
local function fresh(build)
  local inner = nil
  return {
    tick = function()
      inner = inner or H.seqStep(build())
      local r = inner:tick()
      if r == "done" then inner = nil end
      return r
    end,
    reset = function() inner = nil end,
  }
end

-- One leg of the corridor with its battles fought and NO care on the walk,
-- ending early when `stop` says so.
local legN = 0
local function leg(stop, fight)
  legN = legN + 1
  local t = (legN % 2 == 1) and NORTH or SOUTH
  if H.worldX() == t[1] and H.worldY() == t[2] then
    t = (t == NORTH) and SOUTH or NORTH
  end
  return {
    H.logStep(string.format("[emptybag] leg %d -> (%d,%d), battles fought, no care on the walk",
      legN, t[1], t[2])),
    H.worldNavTo(t[1], t[2],
      { maxFrames = 20000, playBattles = "tactical", care = false, fight = fight,
        arrive = stop }),
    H.release(),
  }
end
-- walk legs until somebody is under the threshold (with at least one
-- battle behind it), at most n legs
local function walkUntilHurt(n)
  local function stop() return battles >= 1 and hurt() and settled() end
  return H.seqStep({
    H.repeatN(n, {
      H.cond(function() return not stop() end,
        { fresh(function() return leg(stop) end) }, {}),
    }),
    H.call(function()
      H.assertEq(stop(), true, string.format(
        "somebody is under %.0f%% after %d battle(s) (the walk's doing)",
        THRESH * 100, battles))
    end),
  })
end

-- The drain: while the bag holds a Tonic, walk one leg that stops once a
-- battle has left anybody short of full, then drink Tonics through the
-- field menu (M.fieldCare, threshold 1.0, magic off, every Potion held
-- back) until the party is whole or the Tonics are gone.  A Tonic is
-- refused at max HP (CheckCanUseItem), so each one needs a real wound.
local function missing()
  for _, c in ipairs(H.partyMembers()) do
    if H.charHp(c) < H.charMaxHp(c) then return true end
  end
  return false
end
-- The drain (#252: it was 200 legs, a bare number; a care stop after a
-- leg that met no battle, or one that hurt nobody, drinks nothing, and on
-- this corridor 52 legs drank 23 Tonics in 7 stops (wt/v026-suites s252), so
-- a band of 99 needs ~220 legs).  Now each round walks legs until a battle
-- leaves somebody short of max HP -- at most LEGS_PER_STOP legs, the bound
-- walkUntilHurt uses on the same corridor -- and then takes the care stop,
-- which drinks at least one Tonic (asserted), so the Tonics in the bag at
-- the start bound the rounds.
local LEGS_PER_STOP = 48
local drinkN = 0
-- A drain battle takes its hits before it ends (#536): the party Defends
-- (the fight driver's opts.holdFor, battle_ragedriver's and battle_doom's
-- staging) while every member standing in the battle is at max HP, and
-- the fight goes on as the driver plays it once somebody is short.  Fought
-- out at once, a battle often wounds nobody: the #533 landing's replay
-- (wt/polish-driver-3) met six such in a row in round 13 and its 48 legs
-- ran out ("a battle left somebody short of max HP within 48 legs: got
-- false"), where rounds before it took 1 to 4 battles.  So the round's
-- precondition is made by play and the 48-leg bound is left as it was.
-- The fight table's functions are live options (H.fightDriverFor calls each
-- as fn(tag, memo) every frame and stores what it returns, memo emptied as
-- each battle ends), so holdFor returns the predicate.
-- The hold is bounded (#533 review): a formation that cannot wound the
-- party would be Defended against forever.  The bound is one enemy round
-- in the party's turns, read off the engine's clock when the battle's
-- first hold is asked: in the time the slowest standing monster's gauge
-- takes to fill (65536 / its ATB constant, $3AC8,x), each standing member
-- takes const_m / const_slowest turns, so the party takes their sum
-- (rounded up) before every monster has had its turn.  Past that many held
-- turns with nobody short, the fight is played out as the driver plays it
-- and the round goes on to its 48-leg assert.
local function wholeInBattle()
  for e = 0, 3 do
    local hp, mx = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
    if mx > 0 and hp > 0 and hp ~= 0xFFFF and hp < mx then return false end
  end
  return true
end
-- party turns in one enemy round (above); nil when no gauge can be read
local function roundTurns()
  local slowest = nil
  for s = 0, 5 do
    local x = 8 + s * 2
    local c = H.readWord(0x3AC8 + x)
    if H.readWord(0x3BFC + s * 2) > 0 and (H.readByte(0x3AA8 + s * 2) & 1) ~= 0 and c > 0
       and (slowest == nil or c < slowest) then
      slowest = c
    end
  end
  if slowest == nil then return nil end
  local sum = 0
  for e = 0, 3 do
    local hp = H.readWord(0x3BF4 + e * 2)
    if hp > 0 and hp ~= 0xFFFF and H.readWord(0x3C1C + e * 2) > 0 then sum = sum + H.readWord(0x3AC8 + e * 2) / slowest end
  end
  return math.ceil(sum)
end
local DRAIN_FIGHT = { holdFor = function(_, memo)
  return function()
    if not wholeInBattle() then return false end
    if memo.bound == nil then
      memo.bound, memo.held = roundTurns() or 0, 0
      H.log(string.format("[drain] the party holds (Defends) until somebody is short of max HP, for at most %d of its "
        .. "turns (one enemy round on the engine's clock)", memo.bound))
    end
    if memo.held >= memo.bound then
      if not memo.said then
        memo.said = true
        H.log(string.format("[drain] %d held turns and nobody is short: the hold ends, the fight is played out",
          memo.held))
      end
      return false
    end
    memo.held = memo.held + 1
    return true
  end
end }
local function drainTonics()
  local legB, before, budget = 0, 0, nil
  local function stop() return battles > legB and missing() and settled() end
  local round = fresh(function()
    drinkN = drinkN + 1
    legB = battles
    before = H.invCountOf(TONIC)
    return {
      H.repeatN(LEGS_PER_STOP, {
        H.cond(function() return not stop() end, { fresh(function() return leg(stop, DRAIN_FIGHT) end) }, {}),
      }),
      H.call(function()
        H.assertEq(stop(), true, string.format("drain round %d: a battle left somebody short "
          .. "of max HP within %d legs", drinkN, LEGS_PER_STOP))
      end),
      -- the Tent and Tincture arms off: the drain's job is the Tonics, and
      -- with one Tonic left and the Potions held back the care pitches a
      -- Tent instead (the bag cannot lift everyone: "pitch a Tent (the
      -- party 240 hp and 0 mp short, ... (1 tonic + 0 potion = 50 gil))",
      -- build/attempts/wt/v026-field/final2/emptybag.log), which is the
      -- right call in play and no drink here
      -- (EMPTYBAG_DRAIN_CARE_OFF, a global a negative sets: the round takes
      -- no care stop, and the suite's property below must go red)
      EMPTYBAG_DRAIN_CARE_OFF and H.call(function() H.log("[drain] NEGATIVE: no care stop this round") end)
        or H.fieldCare({ tag = "drinking the Tonics down " .. drinkN,
          threshold = 1.0, magic = false, reserve = { [POTION] = 99 },
          tent = false, tincture = false }),
      H.call(function()
        roster("drain " .. drinkN)
        H.assertEq(H.invCountOf(TONIC) < before, true, string.format("drain round %d "
          .. "drank a Tonic (%d -> %d): the bound counts on it", drinkN, before,
          H.invCountOf(TONIC)))
      end),
    }
  end)
  return H.seqStep({
    H.call(function()
      budget = H.invCountOf(TONIC)
      H.log(string.format("[drain] %d Tonics in the bag: at most %d rounds of at most %d legs",
        budget, budget, LEGS_PER_STOP))
    end),
    H.repeatN(99, {
      H.cond(function() return H.invCountOf(TONIC) > 0 and drinkN < budget end, { round }, {}),
    }),
    H.call(function()
      roster("drained")
      H.assertEq(H.invCountOf(TONIC), 0, string.format(
        "the party drank its Tonics down to none through the field menu (%d rounds)", drinkN))
    end),
  })
end

local b0, mark = {}, {}
local function snap()
  b0.tonic, b0.potion, b0.fenix = H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX)
  b0.mp = H.charMp(0)
  b0.w, b0.r = worst()
  b0.hp = H.charHp(b0.w)
  b0.frame = H.frame
  b0.battles = battles
end

H.run({ maxFrames = 1200000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(settled, 1200, "world control at the landing", 5),
  H.call(function()
    roster("at boot")
    H.assertEq(H.knowsSpell(0, CURE), true, "TERRA knows Cure (case 5's caster)")
    H.assertEq(H.worldX() == 232 and H.worldY() == 150, true, "at the landing (232,150)")
  end),

  -- ---- 0. the Tonics are drunk down to none, through the field menu --------
  drainTonics(),
  H.call(function()
    H.assertEq(H.invCountOf(TONIC), 0, "the bag holds no Tonics")
    H.assertEq(H.invCountOf(POTION) > 4, true, "and Potions above the care floor")
    battles = 0                         -- the cases count their own battles
  end),

  -- ---- 1. a battle opens under the driver-form care stop -------------------
  walkUntilHurt(48),
  H.call(function() roster("hurt, before the race") end),
  -- walk on until the next battle's load starts, and stop the walk THERE
  H.repeatN(24, {
    H.cond(function() return not H.battleLoadStarted() end,
      { fresh(function() return leg(function() return H.battleLoadStarted() end) end) }, {}),
  }),
  H.call(function()
    H.assertEq(H.battleLoadStarted(), true, "a battle is up as the care stop is asked for")
    H.assertEq(hurt(), true, "and somebody still needs care, so the stop has work")
    snap()
    forget()
    H.log(string.format("[emptybag] race: battle %d loading at f%d, care stop starts now",
      battles, H.frame))
  end),
  H.careStop("care under a battle (driver form)", { threshold = THRESH }),
  H.call(function()
    local spent = H.frame - b0.frame
    H.log(string.format("[emptybag] race: the care stop returned after %d frames", spent))
    H.assertEq(spent <= 30, true,
      string.format("the care stop yielded at once (%d frames, not the 2400-frame B mash)", spent))
    H.assertEq(said("yielding to the fight"), true, "and said it was yielding to the fight")
    H.assertEq(said("REFUSED"), false, "nothing was reported REFUSED (the battle's $B5 is not a refusal)")
    H.assertEq(said("the menu never closed"), false, "and no B's were mashed at a fight")
    H.assertEq(H.invCountOf(POTION), b0.potion, "no Potion was spent into the battle")
    H.assertEq(H.battleLoadStarted(), true, "the battle is still up for the fight to be played")
  end),
  -- play the fight the way a walker does, then its own care stop after
  (function()
    local W
    return H.seqStep({
      H.call(function() W = H.newWalkFighter("the battle under the care", { care = false }) end),
      H.driveUntil(function() return not W.frame() end, 40000, {},
        "the battle under the care, fought"),
      H.release(),
      H.waitUntil(settled, 1800, "the world back after the battle under the care", 5),
    })
  end)(),
  H.call(function()
    H.assertEq(alive(), true, "the party stands after the battle under the care")
    roster("after the battle under the care")
  end),

  -- ---- 2. driver form, 0 Tonics: the Potion heals -------------------------
  walkUntilHurt(48),
  H.call(function() snap(); forget(); roster("case 2: before the driver-form care") end),
  H.careStop("care with no Tonics (driver form)",
    { threshold = THRESH, tent = false, tincture = false }),
  H.call(function()
    roster("case 2: after")
    H.assertEq(H.invCountOf(TONIC), 0, "still no Tonics")
    H.assertEq(H.invCountOf(POTION) < b0.potion, true,
      string.format("a Potion was drunk (%d -> %d)", b0.potion, H.invCountOf(POTION)))
    H.assertEq(said("used $E9 on char"), true, "and the log says which Potion landed")
    H.assertEq(said("REFUSED"), false, "nothing was refused")
    H.assertEq(H.charMp(0), b0.mp, "TERRA cast nothing (the driver form never casts)")
    local _, r = worst()
    H.assertEq(r >= THRESH, true, string.format("the worst member is back above the threshold (%.2f)", r))
    H.assertEq(settled(), true, "the menu is closed and the party has world control")
  end),

  -- ---- 3. step form, magic off, 0 Tonics: the Potion again -----------------
  walkUntilHurt(48),
  H.call(function() snap(); forget(); roster("case 3: before the step-form care") end),
  H.fieldCare({ tag = "care with no Tonics (step form)", threshold = THRESH, magic = false,
    tent = false, tincture = false }),
  H.call(function()
    roster("case 3: after")
    H.assertEq(H.invCountOf(POTION) < b0.potion, true,
      string.format("a Potion was drunk (%d -> %d)", b0.potion, H.invCountOf(POTION)))
    H.assertEq(said("used $E9 on char"), true, "and the log says so")
    H.assertEq(said("REFUSED"), false, "nothing was refused")
    H.assertEq(H.charMp(0), b0.mp, "no MP spent")
    H.assertEq(settled(), true, "the menu is closed and the party has world control")
  end),

  -- ---- 4. driver form, Potions reserved away too: says why, no menu -------
  walkUntilHurt(48),
  H.call(function() snap(); forget(); roster("case 4: before the bagless driver-form care") end),
  H.careStop("care with nothing spendable (driver form)",
    { threshold = THRESH, reserve = { [TONIC] = 4, [POTION] = 99 },
      tent = false, tincture = false }),
  H.call(function()
    local spent = H.frame - b0.frame
    roster("case 4: after")
    H.assertEq(spent <= 30, true,
      string.format("the stop returned at once (%d frames): no menu was opened", spent))
    H.assertEq(said("nothing to do"), true, "it reported nothing to do")
    H.assertEq(said("nothing more can be done"), true, "and said why")
    H.assertEq(said("potion " .. H.invCountOf(POTION) .. " in the bag, floor 99"), true,
      "naming the Potion floor that pins the bag")
    H.assertEq(said("casting off"), true, "and that the driver form does not cast")
    H.assertEq(H.invCountOf(POTION), b0.potion, "no Potion moved")
    H.assertEq(H.charHp(b0.w), b0.hp, "the patient is exactly as hurt as before")
    H.assertEq(settled(), true, "and the party still has control")
  end),

  -- ---- 5. step form, default policy, Potions reserved: TERRA casts ---------
  H.call(function() snap(); forget() end),
  H.fieldCare({ tag = "care with nothing spendable (step form, casting allowed)",
    threshold = THRESH, reserve = { [TONIC] = 4, [POTION] = 99 },
    tent = false, tincture = false }),
  H.call(function()
    roster("case 5: after")
    H.assertEq(H.charMp(0) < b0.mp, true,
      string.format("TERRA cast out of her own MP (%d -> %d)", b0.mp, H.charMp(0)))
    H.assertEq(said("cast $2D on char"), true, "and the log names the Cure")
    H.assertEq(H.invCountOf(POTION), b0.potion, "the bag was not opened")
    H.assertEq(said("REFUSED"), false, "nothing was refused")
    local _, r = worst()
    H.assertEq(r >= THRESH, true, string.format("the worst member is back above the threshold (%.2f)", r))
    H.assertEq(settled(), true, "the menu is closed and the party has world control")
  end),
})
