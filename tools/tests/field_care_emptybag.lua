-- @suite savestate=crescent_landing
-- field_care_emptybag.lua -- #184: field care once the Tonics are gone.
--
-- The fixture is crescent_landing, a played state that arrives with 0
-- Tonics, 36 Potions and 27 Fenix Downs in the bag (gen_voyage drank the
-- Tonics on the way), standing on the world map at (232,150) with TERRA
-- (who knows Cure), LOCKE and SHADOW.  Nobody is hurt at boot, so every
-- case earns its patient the way a player does: world-map legs with the
-- battles fought (care switched off on the walk), until somebody is under
-- the threshold.  Reads and pad presses only; no inventory or HP writes.
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
local function leg(stop)
  legN = legN + 1
  local t = (legN % 2 == 1) and NORTH or SOUTH
  if H.worldX() == t[1] and H.worldY() == t[2] then
    t = (t == NORTH) and SOUTH or NORTH
  end
  return {
    H.logStep(string.format("[emptybag] leg %d -> (%d,%d), battles fought, no care on the walk",
      legN, t[1], t[2])),
    H.worldNavTo(t[1], t[2],
      { maxFrames = 20000, playBattles = "tactical", care = false,
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

H.run({ maxFrames = 400000 }, {
  H.loadState(FIX),
  H.waitFrames(60),
  H.waitUntil(settled, 1200, "world control at the landing", 5),
  H.call(function()
    roster("at boot")
    H.assertEq(H.invCountOf(TONIC), 0, "the fixture arrives with no Tonics")
    H.assertEq(H.invCountOf(POTION) > 4, true, "and Potions above the care floor")
    H.assertEq(H.knowsSpell(0, CURE), true, "TERRA knows Cure (case 5's caster)")
    H.assertEq(H.worldX() == 232 and H.worldY() == 150, true, "at the landing (232,150)")
  end),

  -- ---- 1. a battle opens under the driver-form care stop -------------------
  walkUntilHurt(12),
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
  walkUntilHurt(12),
  H.call(function() snap(); forget(); roster("case 2: before the driver-form care") end),
  H.careStop("care with no Tonics (driver form)", { threshold = THRESH }),
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
  walkUntilHurt(12),
  H.call(function() snap(); forget(); roster("case 3: before the step-form care") end),
  H.fieldCare({ tag = "care with no Tonics (step form)", threshold = THRESH, magic = false }),
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
  walkUntilHurt(12),
  H.call(function() snap(); forget(); roster("case 4: before the bagless driver-form care") end),
  H.careStop("care with nothing spendable (driver form)",
    { threshold = THRESH, reserve = { [TONIC] = 4, [POTION] = 99 } }),
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
    threshold = THRESH, reserve = { [TONIC] = 4, [POTION] = 99 } }),
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
