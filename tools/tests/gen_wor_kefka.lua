-- gen_wor_kefka.lua -- Kefka and the ending (docs/design/route-wor-the-end.md): Continue the `wor-kt-plates-v1`
-- battery (party 2 on 412's save point, (82,47); parties 1 and 3 on 411's right and left plates), then
--   the care: each party in turn (H.splitCare), as a player does before the last step;
--   party 2 down from 412 (82,45) to 411 and onto the middle plate (109,40): with all three plates held it starts
--     FinalBattle (event_main.asm FinalBattle), the climb to Kefka;
--   the order menu (order_menu, menu type $08, final_order.asm): the twelve members of the three parties in the
--     order they join the fight, the first four starting it (ORDER below);
--   battle 101: four formations in one battle (battle_main.asm FinalBattleIDTbl: 471 the arms and the face, 512
--     the four figures, 513 the lady and the sleeper, 514 Kefka); between formations the fallen leave and the next
--     members of the order take their places (the end-of-battle special event $06), and a party that falls whole
--     inside one is a game over (_ca5ea9: the runner retries from the save);
--   the ending (GameEnding): its cinematics (event command $ba, EndingCutscene_ext: each character's scene, then
--     the staff roll over the Falcon's flight), the last airship scene ($bf, EndingAirshipScene2_ext), the last
--     cinematic (ending 32) and "The End" ($bb, TheEnd_ext): asserted in that order, and the line's last state
--     saved there.
-- No save point follows Kefka, so the line ends on a savestate rather than a battery.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = H.SPLIT_NAMES
local KEFKA = 0x12A
local TIERS = { [0x01D7] = "the arms and the face", [0x0200] = "the four figures", [0x0201] = "the lady and the "
  .. "sleeper", [0x0202] = "Kefka" }
local GIRL = 0x15E
local FENIX_FLOOR = 10
local FIGHT = {}
-- the fight's options (a lab's KEFKA_FIGHT overrides them): in the third tier the Girl is killed first, as a player
-- who knows the fight does.  Her Pearl Wind heals the Sleep back to full (lab g_k0_s8, the stock policy:
-- "s3:40000/40000" again and again while the party hit it, and the tier lost), and alone she only revives it with
-- Life 2 (AIScript::_350).  Elsewhere the driver's own kill order (focusList: the formation's parts) stands.
-- route-wor-the-end.md section 5: the stock policy won 17 of 24 runs of the grid, this one 20 of 24
local BOSS_FIGHT = KEFKA_FIGHT or {}
if not KEFKA_STOCK then
  BOSS_FIGHT.focus = function()
    -- (the formation in play, $11E0: the formation words keep the earlier tiers' bodies in their slots)
    if H.battleLoadStarted() and H.readWord(0x11E0) == 0x0201 then return { { species = GIRL } } end
    return nil
  end
end
-- Kefka's Fallen One opens his tier and leaves every member at 1 HP, and his Goner, HyperDrive and Ultima follow
-- (route-wor-the-end.md 5.2): the party revives its fallen with Life at one point (Life 2: full HP, where a Fenix Down
-- gives an eighth) and heals the member in danger with Cure at one or two points (Cure 2, Cure 3) outside a break
-- window, as a player who knows the fight does.  The grid: 18 of 24 runs with neither, 23 of 24 with both and the
-- stones below (lab lrbs)
if not KEFKA_FIGHT and not KEFKA_STOCK then
  BOSS_FIGHT.lifeRaise = true
  BOSS_FIGHT.boostCure = { below = 0.4, notBroken = true }
end
-- KEFKA_RUIN (an arm): the driver's ruin rule (opts.ruin): with three or more members inside their round (Kefka's
-- Fallen One), every actor may care, a party cure ahead of a raise
if KEFKA_RUIN then BOSS_FIGHT.ruin = true end
-- KEFKA_CARESUMMON (an arm): the driver's opts.careSummon (a summon as care: Starlet's party heal, Phoenix's Rebirth)
if KEFKA_CARESUMMON then BOSS_FIGHT.careSummon = KEFKA_CARESUMMON end
-- KEFKA_RESERVE (an arm): the driver's opts.reserveBank (the curers keep a point through Kefka's break)
if KEFKA_RESERVE then BOSS_FIGHT.reserveBank = KEFKA_RESERVE end
-- KEFKA_TO_ONE_OUT (an arm): Fallen One (special effect $40, HP to 1) kept out of the hit ledger (H.TO_ONE_OUT)
if KEFKA_TO_ONE_OUT then H.TO_ONE_OUT = true end
-- KEFKA_TIER_CARE (an arm): a tier's last body below a quarter of its HP, the party heals up before it dies: HP
-- carries into the next tier (the third tier lost twice on a party a long second tier had worn down, f_k4_s8 and
-- f_k4_s13).  The heal threshold rises to 90% and the press rule (attack when a break would end it) holds off
local function tierEnding()
  if not H.battleLoadStarted() then return false end
  local f = H.readWord(0x11E0)
  if f ~= 0x01D7 and f ~= 0x0200 and f ~= 0x0201 then return false end
  local n, last = 0, nil
  for s = 0, 5 do
    local hp = H.readWord(0x3BFC + 2 * s)
    if hp > 0 and hp ~= 0xFFFF then n, last = n + 1, s end
  end
  return n == 1 and H.readWord(0x3BFC + 2 * last) * 4 <= H.readWord(0x3C24 + 2 * last)
end
if KEFKA_TIER_CARE then
  BOSS_FIGHT.healPercent = function() return tierEnding() and 90 or 55 end
  BOSS_FIGHT.press = function() if tierEnding() then return false end return nil end
end
-- Two stones the line carries unworn go on party 2 before the climb: Phoenix (Life) on STRAGO, in Palidor's place
-- (Float, Slow), and Kirin (Cure, Regen) on LOCKE, in Shiva's (Ice, Osmose, Shell): two more members who can raise
-- the fallen at full HP and cure at a boost (TERRA, CELES and SHADOW the others).  Lab lrbs: Kefka's tier lost 1 of
-- 24 with them against 3 of 24 without (lrbc), the members who fell in it 21 against 42
local STRAGO, LOCKE, PHOENIX, KIRIN = 7, 1, 26, 17
local STONES = { { STRAGO, PHOENIX }, { LOCKE, KIRIN } }
H.NAV_REFIRE_HOLD = true
H.careThreshold = 1.0
H.careMagic, H.careCastFirst = true, true

local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, sw, settled, say, watches = K.map, K.sw, K.settled, K.say, K.watches
local T = H.kefkaTowerKit(K, FIGHT)
local walk, door = T.walk, T.door

local function lv(ch) return H.readByte(0x1600 + 37 * ch + 8) end
local function hpMax(ch) return H.charMaxHp(ch) end

-- The order (KEFKA_ORDER, a lab's, overrides it): the twelve members of the three parties, the highest level first
-- (the most HP first among equals), as a player puts the strongest in front: the first four start the fight, and
-- the rest come in, in this order, for the members who fall
-- A lab's KEFKA_ORDER is a list of ids, or "weak" (the same sort, weakest first) or "mix" (strongest, weakest,
-- second strongest, second weakest, ...: the strong carrying the bench, as the tower's parties)
local function orderFor()
  if type(KEFKA_ORDER) == "table" then return KEFKA_ORDER end
  local all = {}
  for _, p in ipairs({ 1, 2, 3 }) do
    for _, ch in ipairs(H.partyRoster(p)) do all[#all + 1] = ch end
  end
  table.sort(all, function(a, b)
    if lv(a) ~= lv(b) then return lv(a) > lv(b) end
    if hpMax(a) ~= hpMax(b) then return hpMax(a) > hpMax(b) end
    return a < b
  end)
  if KEFKA_ORDER == "weak" then
    local r = {}
    for i = #all, 1, -1 do r[#r + 1] = all[i] end
    return r
  elseif KEFKA_ORDER == "mix" then
    local r, i, j = {}, 1, #all
    while i <= j do
      r[#r + 1] = all[i]
      if j > i then r[#r + 1] = all[j] end
      i, j = i + 1, j - 1
    end
    return r
  end
  return all
end

-- what the run watches by the code it runs: the order menu's frame handler, each formation the battle loads after
-- the first, the ending's cinematics, the last airship scene and "The End"
local E = { menu = nil, falcon = nil, theEnd = nil, tiers = {}, endings = {} }
local function names(list)
  local t = {}
  for _, ch in ipairs(list) do t[#t + 1] = NAMES[ch] or string.format("$%02X", ch) end
  return table.concat(t, ", ")
end
local function seated()
  local t = {}
  for i = 0, 3 do
    local ch = H.readByte(0x3ED8 + 2 * i)
    if ch ~= 0xFF then
      t[#t + 1] = string.format("%s %d/%d", NAMES[ch] or string.format("$%02X", ch), H.readWord(0x3BF4 + 2 * i),
        H.readWord(0x3C1C + 2 * i))
    end
  end
  return table.concat(t, ", ")
end
local function observers()
  return H.call(function()
    local m74 = H.sym("MenuState_74")
    emu.addMemoryCallback(function() E.menu = H.frame end, emu.callbackType.exec, m74, m74)
    local ec = H.sym("EndingCutscene_ext")
    emu.addMemoryCallback(function()
      local n = H.readByte(0x0201)
      E.endings[#E.endings + 1] = { n = n, frame = H.frame, falcon = E.falcon ~= nil }
      H.log(string.format("[end] f%d ending cinematic %d", H.frame, n))
    end, emu.callbackType.exec, ec, ec)
    local fa = H.sym("EndingAirshipScene2_ext")
    emu.addMemoryCallback(function()
      if not E.falcon then E.falcon = H.frame; H.log(string.format("[end] f%d the last airship scene", H.frame)) end
    end, emu.callbackType.exec, fa, fa)
    local te = H.sym("TheEnd_ext")
    emu.addMemoryCallback(function()
      if not E.theEnd then E.theEnd = H.frame; H.log(string.format("[end] f%d The End", H.frame)) end
    end, emu.callbackType.exec, te, te)
    -- each formation's start: the battle's first, and each CheckFinalBattle chains to (RestartBattle)
    local rb = H.sym("RestartBattle")
    emu.addMemoryCallback(function()
      local f = H.readWord(0x11E0)
      if not TIERS[f] then return end
      E.tiers[#E.tiers + 1] = { f = f, frame = H.frame }
      -- the outcomes said before Kefka's formation loads (the driver names a tier's outcome by the formation the
      -- battle has already moved on to: "battle $202 WON ... killed s2:$15E s3:$15F" is the third tier's)
      if f == 0x0202 then E.kefkaN = #H.outcomes end
      H.log(string.format("[tier] f%d formation $%04X (%s) begins; standing: %s", H.frame, f, TIERS[f] or "?",
        seated()))
    end, emu.callbackType.exec, rb, rb)
  end)
end

-- The order menu (final_order.asm): $4B is the cursor (0 "reset", 1-12 the list, 13 "end"), $4A how many are
-- picked, $7E9D8A+i the list's characters, $0205+k the k-th pick.  Each pick walks the cursor to the member and
-- presses A; with every member picked, START closes the menu (FillFinalOrder adds nobody then).  A pick that went
-- wrong is taken back with B.  Reads and presses only.
local function orderMenu()
  local order, phase, committed = nil, 0, nil
  local function live() return E.menu ~= nil and H.frame - E.menu <= 2 end
  local function picks()
    local t = {}
    for k = 0, H.readByte(0x4A) - 1 do t[#t + 1] = H.readByte(0x0205 + k) end
    return t
  end
  return H.seqStep({
    H.waitUntil(live, 60000, "the order menu open"),
    H.call(function()
      order = orderFor()
      local list = {}
      for i = 0, 11 do
        local ch = H.readByte(0x7E9D8A + i)
        if ch ~= 0xFF then list[#list + 1] = ch end
      end
      H.log("[order] the menu lists: " .. names(list))
      H.log("[order] the order: " .. names(order))
      H.assertEq(#list, #order, "the order names every member the menu lists")
    end),
    H.driveUntil(function() return committed ~= nil and not live() end, 20000, {
      H.call(function()
        phase = (phase + 1) % 8
        local function tap(b) H.setPad(phase < 3 and { b } or {}) end
        if not live() or committed then H.setPad({}); return end
        local got = picks()
        for k, ch in ipairs(got) do
          if order[k] ~= ch then tap("b"); return end
        end
        if #got >= #order then committed = H.frame; H.setPad({ "start" }); return end
        local want, tgt = order[#got + 1], nil
        for i = 0, 11 do if H.readByte(0x7E9D8A + i) == want then tgt = i + 1 end end
        if not tgt then error("the order menu does not list " .. tostring(NAMES[want]), 0) end
        local cur = H.readByte(0x4B)
        if cur < tgt then tap("down") elseif cur > tgt then tap("up") else tap("a") end
      end),
    }, "the order picked"),
    H.call(function()
      local t = {}
      for k = 0, 11 do t[#t + 1] = H.readByte(0x0205 + k) end
      H.log("[order] committed: " .. names(t))
      for k, ch in ipairs(order) do
        H.assertEq(t[k], ch, string.format("the order's member %d", k))
      end
    end),
  })
end

-- the ending rides on its own: no input but the dialogs'.  Its cinematics change little of what the heartbeat
-- samples, so the event pointer ($E5-$E7) or the world module's script pointer ($EA-$ED) moving is said as
-- progress
local function ending(pred, frames, what)
  local last = nil
  return H.driveUntil(pred, frames, {
    H.call(function()
      local p = H.readByte(0xEA) | (H.readByte(0xEB) << 8) | (H.readByte(0xEC) << 16) | (H.readByte(0xED) << 24)
      local e = H.readByte(0xE5) | (H.readByte(0xE6) << 8) | (H.readByte(0xE7) << 16)
      local key = p * 16777216 + e
      if key ~= last then last = key; H.progress("ending") end
      H.setPad(H.dialogWaiting() and (H.frame % 8 < 3) and { "a" } or {})
    end),
  }, what)
end

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("wor-kt-plates-v1"),
  watches(),
  observers(),
  -- ---- 0. what the plan depends on (#480) -------------------------------------------------------------------
  -- The entry contract holds the story (the statues beaten, parties 1 and 3 on their plates, party 2 on 412's
  -- save point).  Asserted here: the three parties hold twelve members (the order menu lists those in a party),
  -- and Kefka not yet beaten (the plates still held).
  H.call(function()
    say("tower", "boot")
    local n = 0
    for _, p in ipairs({ 1, 2, 3 }) do n = n + #H.partyRoster(p) end
    H.assertEq(n, 12, "twelve members in the three parties (gen_wor_kt_factory's seating)")
    -- the bag (no shop past Kohlingen: gen_wor_kt_factory's stop stocks 40 Fenix Downs and 99 Potions for the tower
    -- and Kefka; the first play, which stocked 20, reached here with 6)
    H.assertEq(H.invCountOf(0xF0) >= FENIX_FLOOR and H.invCountOf(0xE9) >= 40, true, string.format(
      "the bag for Kefka: %d Fenix Downs (floor %d) and %d Potions (floor 40), stocked at Kohlingen by "
      .. "gen_wor_kt_factory", H.invCountOf(0xF0), FENIX_FLOOR, H.invCountOf(0xE9)))
    -- the stones for Kefka: each owned ($1A69 bits), worn by nobody else, its wearer in party 2
    for _, pe in ipairs(KEFKA_STONES or STONES) do
      local ch, e = pe[1], pe[2]
      local worn = nil
      for c = 0, 15 do
        if c ~= ch and H.readByte(0x1600 + 37 * c + 0x1E) == e then worn = c end
      end
      local inTwo = false
      for _, c in ipairs(H.partyRoster(2)) do if c == ch then inTwo = true end end
      H.assertEq((H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 and worn == nil and inTwo, true,
        string.format("stone %d for %s: owned, unworn (worn by %s), %s in party 2", e, NAMES[ch], tostring(worn),
          NAMES[ch]))
    end
    H.assertEq(string.format("%d %d %d", sw(0x02C6), sw(0x02CA), sw(0x02CE)), "1 0 1",
      "parties 1 and 3 hold their plates, party 2 not yet ($02C6, $02CA, $02CE; gen_wor_kt_plates)")
  end),
  -- @@setup-end

  -- @@stage care
  -- the stones for Kefka (STONES; a lab's KEFKA_STONES replaces them), party 2's, walking at the boot
  H.lazy(function()
    local steps = { H.call(function() end) }
    for _, pe in ipairs(KEFKA_STONES or STONES) do
      local ch, e = pe[1], pe[2]
      steps[#steps + 1] = H.equipEsper(function() return (H.readByte(0x1850 + ch) >> 3) & 3 end, e,
        { tag = string.format("stone %d -> %s (party 2)", e, NAMES[ch]) })
    end
    return H.seqStep(steps)
  end),
  -- KEFKA_UNRING (a lab's): { { char, relic slot, party }, ... } to take off (the Wall Rings); splitCare walks
  -- party 2 again after
  H.lazy(function()
    local steps = { H.call(function() end) }
    for _, u in ipairs(KEFKA_UNRING or {}) do
      steps[#steps + 1] = H.switchParty(u[3], { tag = "unring: party " .. u[3] })
      steps[#steps + 1] = H.unequipRelics(u[1], { u[2] }, { tag = "unring " .. NAMES[u[1]] })
    end
    return H.seqStep(steps)
  end),
  -- KEFKA_ESPERS (a lab's): { { party, char, esper }, ... } equipped in order, each party walked to (the stone's
  -- owner must stand in the walking party to free it: H.equipEsper); splitCare walks party 2 again after
  H.lazy(function()
    local steps = { H.call(function() end) }
    for _, u in ipairs(KEFKA_ESPERS or {}) do
      local p, ch, e = u[1], u[2], u[3]
      steps[#steps + 1] = H.switchParty(p, { tag = "stone: party " .. p })
      steps[#steps + 1] = H.equipEsper(function() return (H.readByte(0x1850 + ch) >> 3) & 3 end, e,
        { tag = string.format("stone %d -> %s (party %d)", e, NAMES[ch], p) })
    end
    return H.seqStep(steps)
  end),
  -- each party's care before the last step, party 2 walking again after
  H.splitCare({ threshold = 1.0, tag = "before Kefka", back = 2 }),
  T.standing("the three parties before Kefka", { 1, 2, 3 }),
  H.call(function() say("boss", "before Kefka: " .. H.partiesLine()) end),

  -- @@stage climb
  -- a lab's K (KEFKA_BURN): party 2 down to 334's north (412 and 411 deal no random battles) for K more battles
  -- first, its care, and back up, so the fight meets another encounter history; the line's own play has none
  H.cond(function() return (KEFKA_BURN or 0) > 0 end, {
    door(82, 50, 334, "party 2: 412 (82,50) -> 334 (a lab's K)"),
    H.lazy(function() return T.trainLap("party 2 on 334's north (a lab's K)", 0, { burn = KEFKA_BURN }) end),
    H.fieldCare({ threshold = 1.0, tag = "after the lab's K" }),
    door(30, 11, 412, "party 2: 334 (30,11) -> 412 (82,49)"),
    H.lazy(function() return H.splitCare({ threshold = 1.0, tag = "before Kefka, after the lab's K", back = 2 }) end),
  }, {}),
  door(82, 45, 411, "party 2: 412 (82,45) -> 411"),
  walk(109, 40, "party 2 onto 411's middle plate (109,40)", function()
    return map() ~= 411 or H.eventRunning() or (H.fieldX() == 109 and H.fieldY() == 40)
  end),
  H.advanceStory(function() return E.menu ~= nil and H.frame - E.menu <= 2 end, 60000, {}),
  orderMenu(),

  -- @@stage kefka
  -- the ride ends at Kefka's [outcome] line, a win with a kill said after his formation loaded (between two
  -- formations the driver says a won outcome with no kill: "battle $202 WON after 40 ticks (no end reading ...):
  -- killed none"): after it the ending rearranges the party (char_party), and the wipe watch would read its empty
  -- seats as a wipe (lab p1: "THE PARTY IS WIPED" 2,600 frames after Kefka's "battle $202 WON")
  H.advanceStory(function()
    local o = H.lastOutcome
    return E.kefkaN ~= nil and #H.outcomes > E.kefkaN and o.kind == "won" and #o.kills > 0
  end, 1200000, { playBattles = "tactical", fight = BOSS_FIGHT, care = false }),
  H.call(function()
    H.assertEq(#E.tiers >= 4 and E.tiers[#E.tiers].f == 0x0202, true, "the battle moved through the tiers to "
      .. "Kefka's ([tier] lines)")
    say("boss", "Kefka beaten")
  end),

  -- @@stage ending
  -- (KEFKA_UNTIL = "won", a lab's: the run ends at Kefka's [outcome] line instead of riding the ending)
  H.cond(function() return KEFKA_UNTIL == "won" end, {
    H.logStep("[lab] Kefka beaten; the run stops before the ending (KEFKA_UNTIL)"),
  }, {
    ending(function() return E.theEnd ~= nil end, 400000, "The End"),
    H.waitFrames(600),
    H.call(function()
      H.screenshot("the_end")
      -- the ending's own order (event_main.asm GameEnding): its cinematics, the last airship scene, ending 32, The
      -- End.  The cinematics before the airship scene are the characters' scenes and the staff roll's pages
      local before, last = 0, E.endings[#E.endings]
      for _, e in ipairs(E.endings) do if not e.falcon then before = before + 1 end end
      H.assertEq(before >= 10 and E.falcon ~= nil and last ~= nil and last.falcon and last.n == 32
        and E.theEnd > last.frame, true, string.format("the ending's cinematics (%d before the last airship scene), "
        .. "the airship scene, ending 32, then The End (event commands $ba, $bf, $ba, $bb)", before))
      H.log(string.format("[end] %d cinematics, the last airship scene at f%d, The End at f%d", #E.endings,
        E.falcon, E.theEnd))
    end),
    H.saveState("wor_kefka.mss"),
    H.logStep(function() return "wor_kefka generated: The End" end),
  }),
})
