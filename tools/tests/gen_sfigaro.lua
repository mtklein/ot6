-- gen_sfigaro.lua -- from locke_scenario.mss (LOCKE alone, one step past the
-- three-way hub, map 75 at (47,43)) through occupied South Figaro to the
-- entry point of the rich man's secret passage.  The first link of the v0.3
-- Locke chain.
-- Generates two states:
--   sfigaro_town.mss     map 75, LOCKE past the gate soldier (via the
--                        servant's-house basement) with the merchant's
--                        clothes and the old man's cider
--   sfigaro_passage.mss  map 86 (7,51), inside the secret passage the
--                        grandson's password opens
--
-- The whole leg is a DISGUISE infiltration -- two Steal fights on the
-- Merchant enemy (formation 43) and NO other battle.  The gate soldier
-- (battle 11, HeavyArmor) is bypassed underground, never fought; #244 / #145.
-- The route, in order:
--   * re-equip LOCKE from his bag (STEP 0)
--   * item shop (map 85): buy Tonics, then STEAL the merchant's clothes
--     -> $0104, the merchant disguise (STEP 1 / BEAT 0)
--   * old man's house (37,40) -> basement: the grandson steps aside for a
--     merchant ($0104) and LOCKE crosses west underground, past the gate
--     soldier (BEAT 1)
--   * cider cafe (map 78): STEAL the cider -> $01D0 (BEAT 2); save sfigaro_town
--   * re-enter the basement from the west; the grandson respawns blocking
--     (his step-aside is an obj_script, not a spawn slot, and $01F0 clears on
--     map reload), so talk to him again to re-open the corridor, then warp to
--     the old man; cider -> $0107 (BEAT 3)
--   * the grandson's password "Courage" -> $01F1, the passage opens (BEAT 4);
--     enter it -> map 86 (7,51); save sfigaro_passage
--
-- Things this script had to measure, each of which broke a first attempt:
--
-- * The merchant's clothes are required, not decoration.  Map 86's grandson
--   (obj 20 at {6,10}) is the gate: `if_switch $0104=1, _ca7bf8` else "Only
--   people dressed as merchants may pass through" (event_main.asm:18794-96).
--
-- * The old man wants his cider first.  _ca7b88 sets $0107 (and names the
--   passage) only on the $01D0 branch; the grandson's password prompt
--   (_ca7c03) is in turn gated on $0107.  So the errands are ORDERED:
--   clothes -> basement -> cider -> old man -> password.
--
-- * The basement is one-way across a MAP RELOAD, not within one.  See BEAT 3.
--
-- * A destination coordinate is not an arrival test.  `go` used to treat
--   "standing on (dx,dy)" as arrival for every crossing; map 78's front room
--   contains a walkable (22,44), the same tile the town door lands on, so the
--   walk to the exit registered arrival twenty tiles early on the wrong map
--   and the settle then waited 12000 frames for a map id that never came.
--   Only a same-map warp has no map change to watch.

local H = dofile("tools/tests/lib/ot6.lua")
local L = H.newSeedSweep("cider steal")
local DOOR = "build/states/locke_scenario.mss.lua"

-- map compares stay masked: loaders leave flag bits in $1F64's high byte
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
-- event switch id -> live bit (event bitfield base $1E80, bit = id & 7)
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
-- a bare step list cannot be spliced into a step list (Lua truncates a
-- non-final table.unpack to one value); H.cond with an always-true
-- predicate is the library's public way to wrap a list into a single step
local function seq(steps) return H.cond(function() return true end, steps) end

-- all eight for door staging: a door at the head of a stair can only be
-- entered diagonally (gen_edgar's finding), and a diagonal candidate has to
-- clear one extra test, that the engine produces that move there
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}

local WATCH = { 0x0103, 0x0104, 0x0105, 0x0107, 0x001C, 0x001D, 0x001E,
                0x0317, 0x01D0, 0x01F0, 0x01F1 }
local function where(tag)
  local out = {}
  for _, s in ipairs(WATCH) do out[#out + 1] = string.format("%04X=%d", s, sw(s)) end
  H.log(string.format("[%s] f%d map=%d (%d,%d) bright=%d ctl=%s | %s",
    tag, H.frame, map(), H.fieldX(), H.fieldY(), bright(),
    tostring(H.hasControl()), table.concat(out, " ")))
end

-- Settle after a map load: a fully lit screen plus whatever else the caller
-- names, held for 20 consecutive frames, then the 30-frame margin every
-- field fixture uses.  Both halves are needed (gen_kolts's header): a
-- cutscene can report control on a black screen, and a single-sample gate
-- passes mid-load while the field module still holds the old map's state.
-- It drives rather than waits so a dialog on the arrival tile cannot stall
-- it; on a quiet field advanceStory holds the pad empty.
local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(dstMap, maxF)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), maxF or 12000, { playBattles = true }),
    H.waitFrames(30),
  })
end

local aPhase = 0

-- One crossing, all three kinds in one step:
--   * ordinary walkable entrance tile    -> navTo straight onto it
--   * door tile (a wall until CheckDoor)  -> stage on a neighbour, hold in
--   * same-map warp (maps 78/83/86 are built out of them)
-- CheckDoor (field/player.asm:958-1010) only opens a tile whose tilemap
-- byte is $15/$17/$1C, and only for a party standing directly above or
-- below it; anything else stays a wall however long the button is held.
local function go(sx, sy, dm, dx, dy, what)
  local pick, startMap
  local function arrived()                       -- see note 5
    if dm ~= startMap then return map() ~= startMap end
    return H.fieldX() == dx and H.fieldY() == dy
  end
  local pickAt = -1000
  local function stage()
    if pick == nil or (H.frame - pickAt >= 90 and not arrived()) then
      pickAt = H.frame
      local fresh
      if H.bfsPath(sx, sy) then
        fresh = { sx, sy, nil }                  -- walkable: stand on it
      else
        for _, c in ipairs(DIAGSTAGE) do
          local cx, cy, move = sx + c[1], sy + c[2], c[3]
          local press = H.movePress(move)
          if H.bfsPath(cx, cy)
             and (press == move or H.canStep(cx, cy, move)) then
            fresh = { cx, cy, press }; break
          end
        end
      end
      fresh = fresh or pick or { sx, sy + 1, "up" }
      if pick == nil or fresh[1] ~= pick[1] or fresh[2] ~= pick[2]
         or fresh[3] ~= pick[3] then
        pick = fresh
        H.log(string.format("%s: staging (%d,%d)%s at f%d", what,
          pick[1], pick[2],
          pick[3] and (", hold " .. pick[3] .. " into (" .. sx .. "," .. sy .. ")")
                  or " (walk straight onto the entrance tile)", H.frame))
      end
    end
    return pick
  end
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 20000, arrive = arrived, playBattles = true }),
    H.cond(function() return stage()[3] ~= nil end, {
      H.driveUntil(arrived, 1800, {
        H.call(function()
          aPhase = (aPhase + 1) % 8
          if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
          local hold = stage()[3]
          H.setPad(hold and { [hold] = true } or {})
        end),
      }, what .. ": hold into the door"),
    }, {}),
    H.release(),
    settleField(dm),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on map " .. dm)
      H.log(string.format("%s: DONE map=%d (%d,%d) f%d", what,
        map(), H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- gen_scenario.lua's choice-steering idiom, unchanged in shape.  $056F is
-- the option count and is only final once dialogWaiting() is true (it is
-- built up as the text types out, and it is meaningless during a battle);
-- $056E is the 0-based selection; the steering presses are edges because
-- $056D latches a held direction to exactly one row (field/text.asm:368-425).
local function rideUntil(pred, what, budget, choices)
  local phase, dlgN = 0, 0
  -- `choices` ({ want, max, what } per prompt, in order) through
  -- H.newChoice (lib/ot6_field.lua): steered only once the dialog waits,
  -- each landed row asserted when its window closes
  local C = H.newChoice(choices or {}, { tag = what,
    onUp = function(n, max, c)
      H.log(string.format("%s: CHOICE #%d up (%d options) -- taking %d :: %s",
        what, n, max, c.want, c.what))
    end })
  return H.driveUntil(pred, budget or 20000, {
    H.call(function()
      phase = (phase + 1) % 8
      dlgN = H.dialogWaiting() and dlgN + 1 or 0
      if C.frame(phase) then return end
      if dlgN >= 3 then H.setPad(phase < 4 and { "a" } or {}); return end
      H.setPad({})
    end),
  }, what)
end

-- talk to `obj`, then ride what it says (steering `choices`) back to a
-- settled, controllable field
local function talkThrough(obj, what, choices, budget)
  local calm = 0
  return seq({
    H.talkToObj(obj, what),
    rideUntil(function()
      local ok = H.hasControl() and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.eventRunning()
             and not H.battleLoadStarted()
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, what, budget or 20000, choices),
    H.release(),
  })
end

-- The boost is banked with real input.  Steal is the shipped boost-tiered
-- chance verb (Ot6StealBoostLevel): 0 bp rolls raw vanilla odds, and 3 bp
-- clamps the level term so vanilla's own `bcs` guarantees the steal.  LOCKE
-- opens the fight with 1 bp (Ot6InitBP) and regens +1 per unboosted action
-- (Ot6ActionEnd), and a steal attempt is itself an action, so the driver
-- steals unboosted while the bank grows (attempts 1-2 may land on their own
-- dice, and each pays Ot6StealCost's 4 MP); once the bank reads >= 3 it
-- presses R-R-R first and takes the guaranteed steal.  Worst case is three
-- attempts, 12 MP, against the pool the fixture logs.  The merchant's
-- reaction script (`if_cmd STEAL`, AIScript::_314) sets b_switch $4C and
-- ends the fight; the caller asserts $1DD2 bit 4.

-- The menu machine is armr-style: presses start only after the menu flag
-- holds 4 consecutive pulses, a new sequence is only built while the menu
-- is the command window (state $05, because a stray A from any other state
-- could queue FIGHT and kill the merchant, which this fight must never
-- produce), and any other state without a running sequence is backed out
-- with B.
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD = 0x05
local B_SWITCH_LIVE = 0x3EBD          -- $3EB4 + ($4C >> 3); bit4 = $4C
-- What a Steal costs this attempt (#219).  Two ROM facts, neither of
-- them written out here as a number: the base is Ot6StealCost's own
-- immediate (`lda #imm / rtl`, the single authority for Steal's price),
-- and the boost ladder is H.boostPrice, the library's transcription of
-- Ot6BoostPriceFor.  Measured on this build: 4 MP unboosted, 63 at the
-- guaranteed tier, against the mp 70 LOCKE reaches his third attempt
-- with (build/attempts/boost-price-driver/lab/sfigaro-lane/diag-1.log:
-- `STEAL attempt 3 ... mp=70 (boost 3 -- guaranteed, 63 MP)` then
-- `attempt 4 ... mp=7`).  That is a seven-MP margin on a segment whose
-- ladder ends in "stolen within 3 attempts", so the ladder asks whether
-- he can pay before pressing R three times into a row the engine would
-- grey and a turn the MP gate would fizzle.
--
-- The gate is written against the rule, not against a number.  The canon
-- is "a price escalates exactly when Ot6BoostDmg multiplies the action",
-- and Ot6BoostDmg refuses cmd $05, so Steal is FLAT at every boost level
-- (the owner's chance-verb exemption, 2026-09-17): boost buys it the
-- rare/guarantee ladder, which is certainty rather than magnitude, and
-- the BP is what pays for it.  H.boostEscalates is the library's copy of
-- that gate, so this call follows the rule wherever it goes next rather
-- than having to be found and edited again.  The ladder keeps working
-- either way, because a cheaper guaranteed tier only ever passes a gate
-- it already passed -- the 63 quoted above was the escalating price, and
-- the gate now reads 4.
local STEAL_CMD = 0x05
local stealBase = nil
local function stealPrice(boost)
  if stealBase == nil then
    local ofs = H.sym("Ot6StealCost") & 0x3FFFFF
    H.assertEq(H.readRomByte(ofs), 0xA9,
      "Ot6StealCost still opens with LDA #imm -- the +1 read is Steal's price")
    stealBase = H.readRomByte(ofs + 1)
  end
  if not H.boostEscalates(STEAL_CMD) then return stealBase end
  return H.boostPrice(stealBase, boost)
end

local function stealDriver(what, maxF)
  local mStreak, mSeq, mIdx, mSub, mNoMenu, tries = 0, nil, 1, 0, 0, 0
  return H.driveUntil(function() return not H.battleLoadStarted() end,
    maxF or 30000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          mStreak, mSeq, mIdx, mSub = 0, nil, 1, 0
          mNoMenu = mNoMenu + 1
          H.setPad(mNoMenu % 2 == 0 and { "a" } or {})
          return
        end
        mNoMenu = 0
        mStreak = mStreak + 1
        if mStreak < 4 then H.setPad({}); return end
        if mSeq == nil then
          if H.readByte(MSTATE) ~= ST_CMD then
            H.setPad(mStreak % 8 < 4 and { "b" } or {})  -- unwind to the window
            return
          end
          local actor = H.readByte(ACTOR)
          local bank = H.readByte(0x3E9C + actor * 2)
          local mp = H.readWord(0x3C08 + actor * 2)
          tries = tries + 1
          local top = stealPrice(3)
          local guaranteed = bank >= 3 and mp >= top
          if guaranteed then
            mSeq = { "r", "r", "r", "down", "a", "a", "a" }  -- guaranteed tier
          else
            mSeq = { "down", "a", "a", "a" }                 -- vanilla odds; bank grows
          end
          mIdx, mSub = 1, 0
          H.log(string.format(
            "%s: STEAL attempt %d f%d actor=%d bank=%d mp=%d %s $3EBD=%02X",
            what, tries, H.frame, actor, bank, mp,
            guaranteed and string.format("(boost 3 -- guaranteed, %d MP)", top)
              or (bank >= 3
                  and string.format("(unboosted %d MP: the guaranteed tier is %d, "
                        .. "over the pool)", stealPrice(0), top)
                  or string.format("(unboosted, %d MP)", stealPrice(0))),
            H.readByte(B_SWITCH_LIVE)))
        end
        if mIdx <= #mSeq then
          H.setPad(mSub < 6 and { mSeq[mIdx] } or {})
          mSub = mSub + 1
          if mSub >= 16 then
            mSub = 0
            mIdx = mIdx + 1
            if mIdx > #mSeq then mSeq = nil end
          end
          return
        end
      end),
    }, what .. ": steal the clothes")
end

-- The gate soldier (battle 11, HeavyArmor $09F, formation 64) is NOT fought.
-- His post at map 75 (30,42) blocks only the SOUTHERN corridor; the merchant
-- disguise ($0104) opens the servant's-house basement, which crosses to the
-- west of town underground (BEAT 1), so LOCKE never engages him.  The whole
-- leg is two Steal fights on the Merchant enemy (formation 43) and no other
-- battle -- proven by the generated battle log and an 8-seed retries-off
-- sweep (8/8, 8 distinct first-battle samples).  The prior gate-soldier fight
-- driver (bank-0 boosted Fights + an endgame Potion steer, ~290 lines) came
-- out with this route; its measurements live in the history and in
-- docs/design/sfigaro-gate.md.  #244 / #145.

-- A Steal fight on the Merchant enemy (battle 10, formation 43): talk into
-- the fight, Steal (stealDriver R-R-R for the guaranteed tier), ride the
-- aftermath, and assert the flag the steal's reaction script sets.  Retries
-- up to 3 with L.spread on a loss, reloading a pre-talk blob.  Used for both
-- of the leg's two fights: the Item Shop merchant (map 85 -> $0104, the
-- merchant disguise) and the cider runner (map 78 -> $01D0, the cider).
local function stealMerchant(obj, mapId, tag, stolenFlag)
  local blob, stolen = nil, false
  local function attempt(n)
    local loadReq, wipedN, lostEarly = nil, 0, nil
    return H.cond(function() return stolen end, {}, {
      H.logStep(function() return string.format("%s: steal attempt %d at f%d", tag, n, H.frame) end),
      n > 1 and seq({
        H.call(function() loadReq = H.requestLoadState(blob) end),
        H.waitFrames(2),
        H.call(function() H.checkReq(loadReq, tag .. ": pre-talk reload"); H.gameOverFired = 0 end),
        H.waitFrames(90),
      }) or seq({}),
      L.spread(n),
      H.talkToObj(obj, tag),
      (function()
        local ph = 0
        return H.driveUntil(function() return H.battleLoadStarted() end, 9000, {
          H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
        }, tag .. ": ride the scene into battle 10")
      end)(),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 6000, tag .. ": battle 10 up", 10),
      H.waitFrames(90),
      H.call(function()
        H.assertEq(H.formationHas({ [0x013A] = true }), true, tag .. ": formation 43 -- Merchant $13A")
      end),
      stealDriver(tag),
      (function()
        local ph, calm, waited = 0, 0, 0
        return H.driveUntil(function()
          wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
          if (H.gameOverFired or 0) > 0 and not lostEarly then
            lostEarly = string.format("GAME OVER at f%d", H.frame)
          elseif wipedN >= 90 and not lostEarly then
            lostEarly = string.format("PARTY WIPED at f%d", H.frame)
          end
          if lostEarly then return true end
          local ok = H.hasControl() and H.tileAligned() and bright() >= 15
                 and not H.battleLoadStarted() and not H.dialogWaiting() and map() == mapId
          calm = ok and calm + 1 or 0; waited = waited + 1
          return calm >= 20 or waited >= 20000
        end, 20500, {
          H.call(function()
            ph = (ph + 1) % 8
            if lostEarly or H.hasControl() then H.setPad({}); return end
            H.setPad(ph < 4 and { "a" } or {})
          end),
        }, tag .. ": ride the aftermath out")
      end)(),
      H.release(),
      H.waitFrames(30),
      H.call(function()
        stolen = lostEarly == nil and sw(stolenFlag) == 1 and map() == mapId and H.hasControl()
        H.log(string.format("%s attempt %d: %04X=%d $1DD2=%02X map=%d -> %s", tag, n,
          stolenFlag, sw(stolenFlag), H.readByte(0x1dd2), map(),
          stolen and "STOLEN" or (lostEarly and ("LOST: " .. lostEarly) or "no steal; retrying")))
      end),
    })
  end
  return seq({
    (function()
      local req
      return seq({
        H.call(function() req = H.requestSaveState() end),
        H.waitFrames(2),
        H.call(function() H.checkReq(req, tag .. ": retry blob"); blob = req.blob end),
      })
    end)(),
    attempt(1), attempt(2), attempt(3),
    H.call(function()
      H.assertEq(stolen, true, tag .. ": stolen within 3 attempts")
    end),
  })
end

-- allowGameOver: a lost steal survives as a counted loss and the next attempt
-- reloads (#163); allowGameOver keeps the run alive for that reload.
H.run({ maxFrames = 350000, allowGameOver = true }, {
  H.loadState(DOOR),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, occupied South Figaro")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(sw(0x0105), 1, "$0105 -- LOCKE's scenario is live")
    H.assertEq(sw(0x001E), 0, "$001E clear -- the scenario is not done")
  end),
  -- STEP 0 (#244/#145): re-equip LOCKE.  The scenario strips his gear on
  -- entry, but locke_scenario's bag still HOLDS his kit -- a MithrilBlade
  -- ($0A), a MithrilShield ($5C, mdef 18, his best shield) and a PlumedHat
  -- ($6B) -- so this puts it back on (all LOCKE-equippable per the item_prop
  -- masks).  The whole leg is now two minor Steal fights (a trivialised
  -- HeavyArmor is never fought), so this is about a clean, quick steal rather
  -- than surviving the gate soldier.
  H.equipLoadout(1, {
    { 0, 0x0A }, -- MithrilBlade
    { 1, 0x5C }, -- MithrilShield
    { 2, 0x6B }, -- PlumedHat
    { 3, 0x84 }, -- LeatherArmor (the only body armour he carries)
  }, { tag = "LOCKE re-equipped from his bag" }),
  H.setRows({ [1] = true }, { tag = "locke solo rows" }),
  L.watch(),   -- the two Steal fights share this seed sweep (retry spread)
  H.call(function()
    where("boot")
  end),

  -- ===================================================================== --
  -- BEAT 0 (#213): the item shop.  The shop's bump door (44,30) is in the
  -- starting pocket east of the gate soldier, and nowhere else: from the
  -- main street past the cafe the reachable set ends at x=37
  -- (probe_locke_tonic.lua, whose first version booted sfigaro_town and
  -- read no path).  The counter keeper, map 85 npc at {106,52} (spawn
  -- $0300), runs `_ca7884`: `shop_menu 8` while $00A4 is clear, which it is
  -- for the whole scenario -- Tonic row 0, Fenix Down, no Potion.  It is
  -- the scenario's only Tonic counter: the seeded chain walked in with 20
  -- and reached locke_done with 7 (sfigaro_passage 18, sfigaro_escape 7).
  -- TONIC to 78: the L13 band the scenario reaches (65) plus that
  -- measured spend (13).  Fenix Down stays at the 12 the common route
  -- carries (~level).  Probe: 58 Tonics, gil 10825 -> 7925.
  -- ===================================================================== --
  H.call(function()
    H.log(string.format("[shop] item shop stop begins: gil=%d tonic=%d potion=%d fenix=%d f%d",
      H.gil(), H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.frame))
  end),
  H.navTo(44, 32, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.driveUntil(function() return map() == 85 end, 1200, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "A0 into the item shop (the bump door at (44,30))"),
  H.release(),
  settleField(85),
  H.shopTalk(106, 52, "South Figaro item shop (occupied)"),
  H.call(function()
    H.assertEq(H.shopId(), 8, "the counter opened shop 8 ($0201) -- $00A4 clear")
    H.assertEq(H.shopRowOf(8, 0xE8) ~= nil, true, "shop 8 sells Tonics")
  end),
  H.buyItem(0xE8, function() return 78 - H.invCountOf(0xE8) end, "TONIC to 78"),
  H.shopClose("South Figaro item shop (occupied)"),
  H.bagArrange({ 0xE9, 0xF0, 0xE8, 0xF2, 0xF5 },
    { tag = "bag: combat items on top (South Figaro item shop)" }),
  H.call(function()
    H.assertEq(H.invCountOf(0xE8) >= 78, true,
      "LOCKE leaves the shop with 78 Tonics -- the L13 band plus the scenario's measured spend")
    H.log(string.format("[shop] item shop done: tonic=%d potion=%d fenix=%d gil=%d f%d",
      H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.gil(), H.frame))
  end),

  -- ===================================================================== --
  -- STEP 1 (#244): the mouthy merchant by the clock, map 85 obj 16 at
  -- {103,51}, _ca85e6 -> battle 10 (formation 43, Merchant $13A).  Steal his
  -- clothes -> $0104, the MERCHANT disguise that opens the grandson's basement
  -- passage.  The Item Shop is in the entrance pocket, so this needs no fight
  -- past the gate soldier.
  -- ===================================================================== --
  H.navTo(103, 53, { maxFrames = 12000, playBattles = true }),
  H.release(),
  stealMerchant(16, 85, "the Item Shop merchant", 0x0104),
  H.call(function()
    H.assertEq(sw(0x0104), 1, "$0104 -- wearing the merchant's clothes")
    where("merchant disguise")
  end),

  H.navTo(104, 57, { maxFrames = 20000, playBattles = true }),
  H.driveUntil(function() return map() == 75 end, 3000, {
    H.hold({ "down" }), H.waitFrames(8),
  }, "A1 out of the item shop"),
  H.release(),
  settleField(75),
  H.call(function() where("item shop done") end),

  -- ===================================================================== --
  -- BEAT 1 (#244/#145): the merchant-disguise bypass past the HeavyArmor.
  -- The old man's house door, town (37,40) -> map 86 (36,22), is in the
  -- reachable pocket.  Downstairs is the same-map warp (32,11) -> (9,8).
  -- The grandson, map 86 obj 20 at {6,10}, runs _ca7bcd: with $0104 (the
  -- merchant disguise, $0107 still clear) he takes _ca7bf8 -- "Merchant,
  -- you may proceed" -- sets $01F0 and STEPS ASIDE (obj_script NPC_5 moves
  -- him to (6,11)), opening the corridor WEST.  Walking out (4,4) -> town 75
  -- (34,34) lands LOCKE WEST of the gate soldier, who is never touched.
  -- (Measured in probe_boy_passage.lua.)
  -- ===================================================================== --
  go(37, 40, 86, 36, 22, "B1 into the old man's house (town 37,40 -> map 86)"),
  go(32, 11, 86, 9, 8, "B2 downstairs (same-map warp 32,11 -> 9,8)"),
  H.navTo(7, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.talkToObj(20, "the grandson (merchant gate -> steps aside)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, {
      H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
    }, "ride the grandson's merchant dialog")
  end)(),
  H.release(), H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 -- the grandson stepped aside (merchant)")
    where("grandson stepped aside")
  end),
  go(4, 4, 75, 34, 34, "B3 out the west passage (4,4 -> town 75 (34,34), WEST)"),
  H.call(function()
    H.assertEq(map(), 75, "out to the WEST town, past the gate soldier -- no fight")
    where("west town")
  end),

  -- ===================================================================== --
  -- BEAT 2: the cider runner (the leg's second and last Steal fight).  Map
  -- 78 obj 22 at {75,39}, behind the annex warp (33,46)->(74,43).  battle 10
  -- (formation 43, Merchant $13A) -> Steal -> $01D0 (the cider).  Reachable
  -- now that LOCKE is in the west town.
  -- ===================================================================== --
  go(22, 42, 78, 26, 52, "C1 town (22,42) -> map 78 (26,52) [CAFE]"),
  go(33, 46, 78, 74, 43, "C2 map 78 (33,46) -> (74,43) [annex warp]"),
  stealMerchant(22, 78, "the cider runner", 0x01D0),
  H.call(function()
    where("after the cider")
    H.assertEq(sw(0x01D0), 1, "$01D0 -- took the old man's cider")
    H.assertEq(sw(0x0104), 1, "$0104 -- still wearing the merchant's clothes")
  end),
  go(75, 42, 78, 34, 45, "C3 map 78 (75,42) -> (34,45) [annex warp back]"),
  go(26, 53, 75, 22, 44, "C4 map 78 (26,53) -> town (22,44)"),
  H.call(function()
    H.assertEq(map(), 75, "back in South Figaro (west)")
    where("sfigaro_town")
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11)))
      end
    end
    H.screenshot("sfigaro_town")
  end),
  H.saveState("sfigaro_town.mss"),
  H.logStep(function()
    return string.format("sfigaro_town generated at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- BEAT 3: give the old man his cider.  He is map 86 obj 17 at {28,17} in
  -- the old-man region; from the west town, re-enter the grandson region
  -- (town 34,35 -> map 86 (4,6)) and take the warp (10,7) -> (33,10) back into
  -- the old-man region.  _ca7b88's $01D0 branch names the passage, sets $0107.
  --
  -- The basement bypass is one-way ACROSS a map reload, not within one.  The
  -- grandson (NPC_5) steps aside at TALK time (obj_script, not a spawn slot),
  -- and re-entering map 86 respawns him at (6,10) with $01F0 cleared -- so the
  -- corridor from the NW pocket (4,6) east to the (10,7) warp is shut again on
  -- arrival.  MEASURED (probe_richman_return.lua): from (4,6) the warp (10,7),
  -- the downstairs (9,8) and (7,10) all read no path with the boy at (6,10);
  -- talking to him from the west (stand (5,10)) takes _ca7bf8 again (still
  -- $0104, and $01F0 re-cleared), he steps DOWN to (6,11), and the same three
  -- tiles then read a path.  Every step from here to the passage is a same-map
  -- warp, so $01F0 stays set and the corridor stays open the rest of the leg.
  -- ===================================================================== --
  go(34, 35, 86, 4, 6, "E1 town (34,35) -> map 86 (4,6) [grandson region]"),
  H.navTo(5, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.talkToObj(20, "the grandson (re-open the corridor -> steps aside)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, {
      H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
    }, "ride the grandson's merchant dialog (re-open)")
  end)(),
  H.release(), H.waitFrames(60),
  H.call(function()
    H.assertEq(sw(0x01F0), 1, "$01F0 -- the grandson stepped aside again (corridor open)")
    where("grandson re-stepped aside")
  end),
  go(10, 7, 86, 33, 10, "E2 warp (10,7) -> (33,10) [old-man region]"),
  talkThrough(17, "the old man (cider -> $0107)"),
  H.call(function()
    where("after the old man")
    H.assertEq(sw(0x0107), 1, "$0107 -- he named the secret passage")
  end),

  -- ===================================================================== --
  -- BEAT 4: the grandson and the password.  Back down the warp (32,11)->(9,8)
  -- to obj 20; with $0107 set, _ca7bcd goes straight to the password prompt.
  -- Pick 1 = "Courage"; 0/2 jump to _ca7c28 "Imperial spy!" -> the scenario
  -- reset.  Sets $01F1 and rewrites (4,15) from wall to the passage stair.
  -- ===================================================================== --
  go(32, 11, 86, 9, 8, "E3 back downstairs (warp 32,11 -> 9,8)"),
  H.navTo(7, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  talkThrough(20, "the grandson (the password)", {
    { want = 1, max = 3, what = 'dlg $00E0 "The password is..." -- 1 = ' ..
      '"Courage".  Options 0 ("Rose bud") and 2 ("Failure") BOTH jump to ' ..
      '_ca7c28, "You are an Imperial spy!", which fades out and calls ' ..
      '_ca85ba -- the scenario reset (event_main.asm:18754-18762)' },
  }),
  H.call(function()
    where("after the password")
    H.assertEq(sw(0x01F1), 1, "$01F1 -- the secret entrance is open")
    -- _ca7c11 -> _caed21 rewrites BG1 at (4,15) (event_main.asm:100170):
    -- the staircase tile that read $E0/p1=$F7 (solid wall) is now floor
    H.log(string.format("(4,15) map byte=$%02X p1=$%02X",
      H.maptile(4, 15), H.readByte(0x7E7600 + H.maptile(4, 15))))
  end),

  H.openChest{ stand = { 15, 11 }, face = "up", bit = 30, what = "Tonic",
               item = 0xE8,
               nav = { playBattles = true } },

  H.fieldCare({ tag = "care before the secret passage", threshold = 0.85 }),

  go(4, 15, 86, 7, 51, "E4 map 86 (4,15) -> (7,51) [the secret passage]"),
  H.call(function()
    H.assertEq(map(), 86, "still map 86 -- the passage is a same-map warp")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    where("sfigaro_passage")
    -- The casualty contract (see the care stop above): this fixture is what
    -- gen_celes boots from, and gen_celes performs zero state writes of its
    -- own, so a party member down or near fatal here is a loss shipped
    -- straight through to celes_freed, not a state of the story getting
    -- somewhere.
    H.assertPartyStanding("sfigaro_passage")
    H.screenshot("sfigaro_passage")
  end),
  H.saveState("sfigaro_passage.mss"),
  H.logStep(function()
    return string.format("sfigaro_passage generated at frame %d", H.frame)
  end),
  L.report(),
})
