-- @manual
-- lab_sfigaro_gate.lua -- the South Figaro gate-soldier lab (issue #193):
-- solo LOCKE vs HeavyArmor, battle 11, the fight the v0.17 qualification
-- lost on attempt 1 ("no-progress ... F:75.30.43.82", LOCKE at 0 HP).
--
-- THE FIGHT, DECODED (monster_prop.dat / ai_script.asm / battle_prop.dat)
--
--   Map 75 rolls NO random encounters (tools/audit_encounters.py 75:
--   map_prop +5 bit 7 clear).  The HeavyArmor is not a random: it is the
--   gate soldier, map 75 npc 10 / obj 26 at (30,42), event _ca854f ->
--   `battle 11, TOWN_EXT` -> formation 64 = HeavyArmor $09F x1
--   (battle_monsters.dat[64] = 00 01 9f ff ff ff ff ff ...).  He is the
--   only tile joining the starting pocket to the town, so the fight is
--   mandatory, three times per gen_sfigaro (B1, R1, R2).
--
--   $09F HeavyArmor  L13  HP 495  MP 150  speed 40  atk 53  hit 100
--                    def 150  mdef 110  mpow 11  weak $84 (bolt|water)
--                    special status 2 (+19) = $00: bit 3 CLEAR, so the
--                    fight CAN be run from (battle_main.asm:7647 copies
--                    +19 to $3c80,y; UpdateMonsterGfxBuf :15631-15635
--                    `lda $3c80+8,y / lsr / bit #$04 / tsb $b1` sets the
--                    can't-run flag from its bit 3).  Measured: L+R
--                    escapes in ~560 frames on 3/3 seeds -- and the
--                    soldier stays on his post, the lane stays closed.
--                    shields 3, SLASH|PIERCE (Ot6ShieldTbl ot6_hud.asm:1645;
--                    LOCKE's Dirk is pierce, so every Fight chips)
--   battle_prop.dat[64] = 43 00 00 00: $2f48 = $0043 ^ $00f0 = $00b3, no
--   pincer bit (bit 6 clear); $2f4b = 0.
--   AI (ai_script.asm:341 "heavyarmor"), with fewer than 4 characters:
--       attack BATTLE ; wait ; attack BATTLE, TEK_LASER, SPECIAL
--   so every second turn is one of Battle / TekLaser / Special.
--   TEK_LASER = $B5 (const.inc:778): magic_prop power 20, bolt, single
--   target; SPECIAL = the species' special byte (+31 = $20).  Battle is
--   the plain Fight: measured 52-58 on LOCKE in the BACK row (Dirk,
--   Leather Hat, LeatherArmor, L? -- the fixture's own kit, 279 max HP).
--
-- THE LAB
--
--   Fixture: build/states/locke_scenario.mss -- gen_sfigaro's own boot
--   state (map 75 (47,43), LOCKE alone, one step past the hub), so the
--   attempt is exactly the generator's opening beat: the kit equipped, the
--   back row set, the walk to (30,43) and the talk that opens battle 11.
--
--   Per attempt: load the fixture, the generator's equip + row drives,
--   hold the pad neutral until wGameTimeFrames ($021e, period 60) has
--   advanced SEED phases (the battle seed is $021e*4 at InitBattle), then
--   H.talkToObj(26) and the fight under the policy.  The hold-to-battle
--   latency is quantized to 4 frames, so the declared spread is seeds
--   0..56 step 4: 15 distinct battle seeds, the whole $021e cycle.
--   Policies that change nothing on the field share the exact pre-battle
--   state per seed (a paired A/B); `front` skips the row drive and draws
--   its own 15.
--
--   POLICY (the one variable, @POLICY@ substituted by sfigarolab_batch.sh):
--     control     H.rideOut's driver as it ships (lib/ot6_field.lua):
--                 tactical, boost, bank 3, items, healPercent 60,
--                 cadence 12; LOCKE in the back row (the generator's row)
--     boostfight  the same with keyed = false: the plain boost-Fight
--                 default (bank 3, spend at the shield) with no keyed
--                 chip line
--     breakfirst  bank = 0: every pip is spent as it exists
--     heal75      healPercent 75: a Potion whenever the window opens
--                 under 75%
--     heal75b0    heal75 + bank 0
--     tonics      control with every Potion reserved (opts.reserve), so
--                 the in-combat heal is the Tonic
--     front       control, LOCKE in the FRONT row (the contrast)
--     run         L+R held from the first battle frame (the run mechanic)
--     stealrun    Steal (row 1) once, then L+R held
--     endgame     control, plus a Potion steered by the lab when LOCKE is
--                 under ENDGAME_FLOOR HP inside the driver's finisher
--                 window (monsters' total HP <= 200, where the lib's care
--                 block is closed); see the policy block below
--     endgameb0   endgame + bank 0
--
--   Privileged-information label: none of these reads hidden state.  The
--   lab's CPU observers (ExecCmd / _writedamage / SaveForMimic exec
--   callbacks, the seed store) are read-only measurement; the [hit] lines'
--   `raw` field is the engine's own damage word before it is clamped to
--   HP, i.e. the roll a kill really made.
--
--   A wipe is the measurement, not a retry (allowGameOver).  After a wipe
--   the lab thaws the canary's pad freeze and presses A through the
--   Annihilated screen, then reports where the game put LOCKE: battle 11's
--   loss is scripted (event_main.asm _ca85ba, the scenario reset), not a
--   game over, and the [after] line is the proof either way.  One
--   machine-readable [result] line per run.
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY  = "@POLICY@"
local SEED    = tonumber("@SEED@") or 0
if POLICY:find("@") then POLICY = "control" end

local LOCKE = 1
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local HEAVYARMOR = 0x009F
local SPECIES = { [0x009F] = "HeavyArmor" }
local ATTACK = { [0xB5] = "TekLaser", [0xBF] = "TekBarrier", [0xDD] = "Missile",
                 [0xEE] = "Battle", [0xEF] = "Special", [0xFF] = "Fight",
                 [0xE8] = "Tonic", [0xE9] = "Potion", [0xF0] = "FenixDown" }
local function atkName(id) return ATTACK[id] or string.format("$%02X", id) end
local CMDNAME = { [0x00] = "Fight", [0x01] = "Item", [0x02] = "Magic", [0x05] = "Steal" }

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD = 0x05
local BCHP, BCMAXHP = 0x3BF4, 0x3C1C
local BP = 0x3E9C
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function charLevel(c) return H.readByte(0x1600 + 37 * c + 8) end
local function isBack(c) return (H.readByte(0x1850 + c) & 0x20) ~= 0 end
local function slotChar(s) return H.readByte(BCHID + s * 2) end
local function monSpecies(i) return H.readWord(0x57C0 + i * 2) end
local function monHp(i) return H.readWord(0x3BFC + i * 2) end
local function monShields(i) return H.readByte(0x3E40 + i * 2) end
local function monPresent(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function partyHp()
  local p = {}
  for e = 0, 3 do p[e + 1] = H.readWord(BCHP + e * 2) end
  return p
end
local function partyLine()
  return string.format("%d/%d bp%d", H.readWord(BCHP), H.readWord(BCMAXHP), H.readByte(BP))
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("s%d:%s:%d/sh%d", i, SPECIES[monSpecies(i)] or
        string.format("$%04X", monSpecies(i)), monHp(i), monShields(i))
    end
  end
  return table.concat(m, " ")
end
local function formationName()
  local n = {}
  for i = 0, 5 do
    local w = H.readWord(0x57C0 + i * 2)
    if w ~= 0xFFFF and w ~= 0 then n[#n + 1] = SPECIES[w] or string.format("$%04X", w) end
  end
  return #n > 0 and table.concat(n, "+") or "none"
end

-- ------------------------------------------------------ the observers --
-- Read-only CPU exec callbacks (lab_zozo_street.lua's, unchanged in shape).
local pending, events = {}, {}
local lastSeed = nil
local monsterHits = {}       -- { atk, kills, raw }
local partyActs = {}         -- { char, cmd, atk }
local maxHit, maxHitAtk, maxRaw = 0, nil, 0
local death = nil            -- { atk, raw, from, bp, frame }
local function hookObservers()
  emu.addMemoryCallback(function()
    lastSeed = emu.getState()["cpu.a"] & 0xFF
  end, emu.callbackType.exec, H.seedStoreAddr(), H.seedStoreAddr())
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x % 2 ~= 0 or x > 0x12 then return end
    pending[x] = { frame = H.frame, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
      tgt = H.readWord(0xB8), hp = partyHp(), bp = H.readByte(BP),
      mhp = { monHp(0), monHp(1), monHp(2), monHp(3), monHp(4), monHp(5) },
      msh = { monShields(0), monShields(1), monShields(2), monShields(3), monShields(4), monShields(5) } }
  end, emu.callbackType.exec, H.sym("ExecCmd@battle_code"), H.sym("ExecCmd@battle_code"))
  emu.addMemoryCallback(function()
    local mx = nil
    for x = 8, 0x12, 2 do if pending[x] then mx = x end end
    if not mx then return end
    local raw = {}
    for e = 1, 4 do
      local w = H.readWord(0x33D0 + (e - 1) * 2)
      raw[e] = (w == 0xFFFF) and 0x3FFF or (w & 0x3FFF)
    end
    pending[mx].raw = raw
  end, emu.callbackType.exec, H.sym("_writedamage"), H.sym("_writedamage"))
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    local p = pending[x]
    if not p then return end
    pending[x] = nil
    local after = partyHp()
    if x >= 8 then
      local slot = (x - 8) // 2
      local dmg = p.hp[1] - after[1]
      local raw = (p.raw and p.raw[1]) or 0x3FFF
      local kills = (p.hp[1] > 0 and after[1] == 0) and 1 or 0
      if dmg > maxHit then maxHit, maxHitAtk = dmg, p.atk end
      if raw ~= 0x3FFF and raw > maxRaw then maxRaw = raw end
      monsterHits[#monsterHits + 1] = { atk = p.atk, kills = kills, raw = raw, dmg = dmg }
      if kills == 1 and death == nil then
        death = { atk = p.atk, raw = raw, from = p.hp[1], bp = p.bp, frame = H.frame }
      end
      events[#events + 1] = string.format(
        "[hit] f%d %s(s%d) cmd=%02X atk=%s tgt=%04X dmg=%d raw=%d kills=%d locke=%d/%d bp%d",
        H.frame, SPECIES[monSpecies(slot)] or "?", slot, p.cmd, atkName(p.atk), p.tgt,
        dmg, raw, kills, after[1], H.readWord(BCMAXHP), p.bp)
    else
      local slot = x // 2
      local md = {}
      for i = 0, 5 do
        if monPresent(i) or p.mhp[i + 1] > 0 then
          md[#md + 1] = string.format("s%d:%d->%d/sh%d->%d", i, p.mhp[i + 1], monHp(i),
            p.msh[i + 1], monShields(i))
        end
      end
      partyActs[#partyActs + 1] = { char = slotChar(slot), cmd = p.cmd, atk = p.atk, bp = p.bp }
      events[#events + 1] = string.format(
        "[act] f%d c%d(slot%d) cmd=%s atk=%s tgt=%04X bp%d mon=%s locke=%d/%d",
        H.frame, slotChar(slot), slot, CMDNAME[p.cmd] or string.format("$%02X", p.cmd),
        atkName(p.atk), p.tgt, p.bp, table.concat(md, " "), after[1], H.readWord(BCMAXHP))
    end
  end, emu.callbackType.exec, H.sym("SaveForMimic"), H.sym("SaveForMimic"))
end
local function flushEvents()
  for _, e in ipairs(events) do H.log("[gatelab] " .. e) end
  events = {}
end

-- ------------------------------------------------------ the policies --
-- H.rideOut's driver, verbatim (lib/ot6_field.lua rideOut)
local function controlOpts()
  return { tactical = true, boost = true, bank = 3, items = true,
           healPercent = 60, cadence = 12 }
end
local driverOpts = controlOpts()
local rowBack = true
if POLICY == "control" then
elseif POLICY == "boostfight" then
  driverOpts.keyed = false
elseif POLICY == "breakfirst" then
  driverOpts.bank = 0
elseif POLICY == "heal75" then
  driverOpts.healPercent = 75
elseif POLICY == "heal75b0" then
  driverOpts.healPercent = 75
  driverOpts.bank = 0
elseif POLICY == "tonics" then
  driverOpts.reserve = { [POTION] = 99 }
elseif POLICY == "front" then
  rowBack = false
elseif POLICY == "run" or POLICY == "stealrun" then
  -- no driver: the pad is the policy
elseif POLICY == "endgame" or POLICY == "endgameb0" then
  if POLICY == "endgameb0" then driverOpts.bank = 0 end
  -- control, plus the one thing the driver cannot do: a Potion inside the
  -- finisher window.  The lib's care block (press rule, spend, raise,
  -- heals) is gated on the monsters' total HP > 200 (lib/ot6.lua makePlan,
  -- `totalMon > 200`: the fight is "one break from over", so attack), and
  -- HeavyArmor's shields re-seed to 3 in exactly that window while LOCKE
  -- is still taking a 55 Battle or a ~150 TekLaser a turn.  Every baseline
  -- loss died there (build/attempts/locke-solo-lab/sweep-baseline: seeds
  -- 0/2/3 at 132-137/279, seed 1's R1 at 22/279 after "item $E9 saves").
  -- A person at 130 HP who has seen the laser drinks.  ENDGAME_FLOOR is
  -- that person's rule: under it, with a Potion in the bag, the window is
  -- steered to Item -> Potion by the lab instead of handed to the driver.
else
  error("unknown POLICY " .. POLICY, 0)
end
local ENDGAME_FLOOR = 175            -- TekLaser measured up to 168 raw; a margin over it
local ENDGAME_TOTALMON = 200         -- the lib's finisher gate

local F = H.newFightDriver("gatelab " .. POLICY, driverOpts)

-- The endgame Potion steer (the lib's item steer in shape: the absolute
-- row is scroll + cursor, ITEMSCR/ITEMROW per actor; BATTINV is the
-- battle bag, 5 bytes an entry, +0 id, +3 count).
local ITEMSCR, ITEMROW, BATTINV = 0x8947, 0x894F, 0x2686
local ST_ITEM, ST_TGT = 0x0A, 0x38
local egPlan, egPulse, egSaid, egPotions = nil, 0, false, 0
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function totalMon()
  local t = 0
  for s = 0, 5 do t = t + H.readWord(0x3BFC + s * 2) end
  return t
end
-- returns true when it owned the frame
local function endgameFrame()
  if H.readByte(MENU) == 0 then
    if egPlan then
      -- the window closed: the Potion was confirmed (an [act] with the
      -- Item command follows), or the engine took the window away
      egPlan, egPulse = nil, 0
    end
    return false
  end
  local actor = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if egPlan == nil then
    if st ~= ST_CMD then return false end
    local hp = H.readWord(BCHP + actor * 2)
    if hp == 0 or hp >= ENDGAME_FLOOR or totalMon() > ENDGAME_TOTALMON then return false end
    local idx = battInvIdx(POTION)
    if idx == nil then return false end
    egPlan = { idx = idx, hp = hp, at = H.frame }
    egPulse = 0
    egPotions = egPotions + 1
    H.log(string.format("[gatelab endgame] f%d LOCKE %d/%d under the floor (%d) with the monsters at %d HP (<= %d, the lib's finisher gate): Item -> Potion (bag row %d) instead of the driver's turn",
      H.frame, hp, H.readWord(BCMAXHP + actor * 2), ENDGAME_FLOOR, totalMon(), ENDGAME_TOTALMON, idx))
  end
  egPulse = egPulse + 1
  if egPulse > 900 then
    H.log(string.format("[gatelab endgame] f%d the Potion steer did not land in 900 frames (state %02X); handing the window back", H.frame, st))
    egPlan = nil
    return false
  end
  local on = egPulse % 8 < 4
  if st == ST_CMD then
    local cur = H.readByte(CMDROW + actor) & 3
    if cur == 3 then H.setPad(on and { "a" } or {})
    else H.setPad(on and { cur < 3 and "down" or "up" } or {}) end
  elseif st == ST_ITEM then
    local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
    if cur < egPlan.idx then H.setPad(on and { "down" } or {})
    elseif cur > egPlan.idx then H.setPad(on and { "up" } or {})
    else H.setPad(on and { "a" } or {}) end
  elseif st == ST_TGT then
    H.setPad(on and { "a" } or {})
  else
    H.setPad(on and { "b" } or {})
  end
  return true
end

-- The run policies.  L+R is the run mechanic; the escape cells are $2f45
-- (characters running), $3a38/$3a39 (just escaped), the run counters
-- $3d70,x; $b1 bit 1 is the engine's can't-run flag and $3a28 the pending
-- battle message word ($0902 = "can't run away!!").
local runTick, runSaid = 0, false
local stealSeq, stealIdx, stealSub, stealStreak, stealTries, stole = nil, 1, 0, 0, 0, false
local function runFrame()
  runTick = runTick + 1
  H.setPad({ l = true, r = true })
  if runTick % 120 == 1 then
    H.log(string.format("[gatelab run] f%d $2f45=%02X $3a38=%02X $3a39=%02X $3d70=%02X $b1=%02X $2f4b=%02X $3c88=%02X msg=%04X",
      H.frame, H.readByte(0x2F45), H.readByte(0x3A38), H.readByte(0x3A39),
      H.readByte(0x3D70), H.readByte(0x00B1), H.readByte(0x2F4B), H.readByte(0x3C88),
      H.readWord(0x3A28)))
  end
end
-- gen_sfigaro.lua's stealDriver, in shape: presses start after the menu
-- flag holds 4 pulses, a sequence is built only at the command window
-- (state $05), and the cursor rows are cmds=00,05,FF,01 (Fight, Steal, -,
-- Item) so Steal is one DOWN from the resting cursor.
local function stealFrame()
  if stole then return runFrame() end
  if H.readByte(MENU) == 0 then
    stealStreak, stealSeq, stealIdx, stealSub = 0, nil, 1, 0
    H.setPad({})
    return
  end
  stealStreak = stealStreak + 1
  if stealStreak < 4 then H.setPad({}); return end
  if stealSeq == nil then
    if H.readByte(MSTATE) ~= ST_CMD then
      H.setPad(stealStreak % 8 < 4 and { "b" } or {})
      return
    end
    stealTries = stealTries + 1
    stealSeq = { "down", "a", "a", "a" }
    stealIdx, stealSub = 1, 0
    H.log(string.format("[gatelab steal] attempt %d f%d bank=%d mp=%d",
      stealTries, H.frame, H.readByte(BP), H.readWord(0x3C08)))
  end
  if stealIdx <= #stealSeq then
    H.setPad(stealSub < 6 and { stealSeq[stealIdx] } or {})
    stealSub = stealSub + 1
    if stealSub >= 16 then
      stealSub = 0
      stealIdx = stealIdx + 1
      if stealIdx > #stealSeq then stealSeq = nil end
    end
  end
end
local function policyFrame()
  if POLICY == "run" then return runFrame() end
  if POLICY == "stealrun" then
    -- one Steal resolved (an [act] with the Steal command) -> run
    if not stole then
      for _, a in ipairs(partyActs) do
        if a.cmd == 0x05 then stole = true; H.log(string.format("[gatelab steal] resolved at f%d; holding L+R from here", H.frame)) end
      end
    end
    return stealFrame()
  end
  if (POLICY == "endgame" or POLICY == "endgameb0") and endgameFrame() then return end
  F.frame()
end

-- ------------------------------------------------------ the attempt --
local phaseSum, phasePrev = 0, nil
local battle = { started = nil, over = nil, wiped = false, form = nil, seed = nil,
                 potion0 = 0, tonic0 = 0, fenix0 = 0 }
local wipeN, offN = 0, 0
local after = nil

local function heldUntilPhase()
  return H.driveUntil(function()
    local ph = H.readByte(0x021E)
    if phasePrev ~= nil then
      local d = ph - phasePrev
      if d < 0 then d = d + 60 end
      phaseSum = phaseSum + d
    end
    phasePrev = ph
    return phaseSum >= SEED
  end, 60 * 70 + 200, { H.call(function() H.setPad({}) end) }, "seed hold")
end

local function fightStep()
  return H.driveUntil(function()
    if battle.over then return true end
    -- A solo wipe zeroes the only battle-HP word, which battleLoadStarted
    -- reads as "no battle" (gen_sfigaro.lua, #163); the seat-based verdict
    -- (H.partyWipedInBattle: present seats all 0 HP, or LoseBattle's $3ebc
    -- bit 0) is what says wiped.  Read it first.
    if battle.started ~= nil and H.partyWipedInBattle() then
      wipeN = wipeN + 1
      if wipeN >= 120 then
        battle.wiped = true
        battle.over = H.frame
        H.log(string.format("[gatelab] WIPED f%d (%d frames in) $3ebc=%02X locke=%s vs %s",
          H.frame, H.frame - battle.started, H.readByte(0x3EBC), partyLine(), monsterLine()))
        return true
      end
      return false
    end
    wipeN = 0
    if H.battleLoadStarted() then
      offN = 0
      if battle.started == nil then
        battle.started = H.frame
        battle.seed = lastSeed
      end
      if battle.form == nil and formationName() ~= "none" then
        battle.form = formationName()
        H.log(string.format("[gatelab] battle up f%d (+%d) form=%s bseed=%s phase=%d L%d row=%s locke=%s vs %s $b1=%02X $2f48=%04X $2f4b=%02X $3c88=%02X",
          H.frame, H.frame - battle.started, battle.form,
          battle.seed and string.format("%02X", battle.seed) or "?",
          H.readByte(0x021E), charLevel(LOCKE), isBack(LOCKE) and "back" or "front",
          partyLine(), monsterLine(), H.readByte(0x00B1), H.readWord(0x2F48),
          H.readByte(0x2F4B), H.readByte(0x3C88)))
      end
      battle.party = partyLine()
      if (H.frame - battle.started) % 300 == 0 then
        H.log(string.format("[gatelab] f+%d locke=%s vs %s", H.frame - battle.started,
          partyLine(), monsterLine()))
      end
      return false
    end
    if battle.started ~= nil then
      offN = offN + 1
      if offN >= 30 then
        battle.over = H.frame
        F.idle()
        H.log(string.format("[gatelab] battle over f%d (%d frames) locke=%s",
          H.frame, battle.over - battle.started, battle.party or "-"))
        return true
      end
    end
    return false
  end, 30000, {
    H.call(function()
      flushEvents()
      if H.battleLoadStarted() then policyFrame() else H.setPad({}) end
    end),
  }, "the fight")
end

local function settled()
  return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
     and not H.battleLoadStarted() and bright() >= 15
end

-- The aftermath of a loss: the run canary counts a wipe held 300 frames as
-- a game over and freezes the pad (its design, #166).  This ride thaws it
-- every time it freezes, presses A the way a person does at the
-- Annihilated screen, and reports where the game put LOCKE.  Its own
-- read-only watches say whether the GameOver event script was entered or
-- TitleScreen executed (a real game over) -- the canary's counter cannot,
-- since its wipe count feeds the same number.
local goRead, titleExec, thaws = 0, 0, 0
local function hookGameOverWatch()
  local ok, addr = pcall(function() return H.sym("GameOver") end)
  if ok then
    emu.addMemoryCallback(function()
      local pc = H.readByte(0x00e5) | (H.readByte(0x00e6) << 8) | (H.readByte(0x00e7) << 16)
      if pc == addr or pc == addr + 1 then goRead = goRead + 1 end
    end, emu.callbackType.read, addr, addr)
  end
  local ok2, addr2 = pcall(function() return H.sym("TitleScreen") end)
  if ok2 then
    emu.addMemoryCallback(function() titleExec = titleExec + 1 end,
      emu.callbackType.exec, addr2, addr2)
  end
end
local function aftermath()
  local ph, calm, t = 0, 0, 0
  return H.driveUntil(function()
    if goRead > 0 or titleExec > 0 then return true end
    local ok = H.hasControl() and H.tileAligned() and bright() >= 15
           and not H.battleLoadStarted() and not H.dialogWaiting()
           and not H.eventRunning()
    calm = ok and calm + 1 or 0
    return calm >= 30
  end, 4000, {
    H.call(function()
      t = t + 1
      ph = (ph + 1) % 8
      if H.padFrozen then thaws = thaws + 1; H.thawPad() end
      if t % 120 == 1 then
        H.log(string.format("[gatelab after] +%d map=%d (%d,%d) ctl=%s bright=%d $3ebc=%02X msg=%04X bhp=%d event=%s go=%d title=%d thaws=%d 1DD1=%02X",
          t, map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), bright(),
          H.readByte(0x3EBC), H.readWord(0x3A28), H.readWord(BCHP), tostring(H.eventRunning()),
          goRead, titleExec, thaws, H.readByte(0x1DD1)))
      end
      if H.hasControl() and not H.dialogWaiting() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "aftermath of the loss")
end

local function result(note)
  local acts = {}
  for _, a in ipairs(partyActs) do
    acts[#acts + 1] = string.format("%s%s:bp%d", CMDNAME[a.cmd] or string.format("$%02X", a.cmd),
      a.cmd == 0x01 and ("(" .. atkName(a.atk) .. ")") or "", a.bp)
  end
  local hits, lasers = {}, 0
  for _, h in ipairs(monsterHits) do
    hits[#hits + 1] = string.format("%s:%d%s", atkName(h.atk), h.dmg, h.kills > 0 and "!" or "")
    if h.atk == 0xB5 then lasers = lasers + 1 end
  end
  local outcome = battle.wiped and "wiped" or (battle.started and "won" or "nobattle")
  if battle.started and not battle.wiped and (POLICY == "run" or POLICY == "stealrun") then
    outcome = "ended"      -- decided by the [after] line (a run ends with no win flag)
  end
  H.log(string.format(
    "[result] policy=%s seed=%d form=%s bseed=%s frames=%s outcome=%s hp_end=%s " ..
    "potions=%d tonics=%d fenix=%d maxhit=%d(%s) maxraw=%d lasers=%d death=%s hits=%s acts=%s after=%s note=%s",
    POLICY, SEED, battle.form or "none",
    battle.seed and string.format("%02X", battle.seed) or "-",
    battle.started and tostring((battle.over or H.frame) - battle.started) or "-",
    outcome, battle.party or "-",
    battle.potion0 - H.invCountOf(POTION), battle.tonic0 - H.invCountOf(TONIC),
    battle.fenix0 - H.invCountOf(FENIX_DOWN),
    maxHit, maxHitAtk and atkName(maxHitAtk) or "-", maxRaw, lasers,
    death and string.format("%s:raw%d:from%d:bp%d", atkName(death.atk), death.raw, death.from, death.bp) or "-",
    table.concat(hits, ","), table.concat(acts, ","), after or "-", note or ""))
end

H.run({ maxFrames = 45000, allowGameOver = true }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    hookObservers()
    hookGameOverWatch()
    H.assertEq(map(), 75, "the lab fixture is on map 75")
    H.assertEq(H.hasControl(), true, "controllable")
    battle.potion0, battle.tonic0, battle.fenix0 =
      H.invCountOf(POTION), H.invCountOf(TONIC), H.invCountOf(FENIX_DOWN)
    H.log(string.format("[gatelab] POLICY=%s SEED=%d at (%d,%d) map %d f%d phase=%d L%d hp=%d/%d potion=%d tonic=%d fenix=%d",
      POLICY, SEED, H.fieldX(), H.fieldY(), map(), H.frame, H.readByte(0x021E),
      charLevel(LOCKE), H.readWord(0x1600 + 37 * LOCKE + 9), H.readWord(0x1600 + 37 * LOCKE + 11),
      battle.potion0, battle.tonic0, battle.fenix0))
  end),
  -- gen_sfigaro.lua's kit and row, verbatim
  H.equipLoadout(1, {
    { 0, 0x00 }, -- Dirk
    { 2, 0x69 }, -- Leather Hat
    { 3, 0x84 }, -- LeatherArmor
  }, { tag = "LOCKE occupied-town kit" }),
  H.cond(function() return rowBack end, {
    H.setRows({ [1] = true }, { tag = "locke solo rows" }),
  }, {}),
  H.call(function()
    H.log(string.format("[gatelab] row=%s before the hold", isBack(LOCKE) and "back" or "front"))
  end),
  H.waitUntil(settled, 1200, "settled before the seed hold", 5),
  heldUntilPhase(),
  H.call(function()
    H.log(string.format("[gatelab] seed hold done: phase=%d after %d phases f%d",
      H.readByte(0x021E), phaseSum, H.frame))
    H.assertEq(H.objX(26) == 30 and H.objY(26) == 42, true, "the gate soldier is on his post (30,42)")
  end),
  H.talkToObj(26, "the gate soldier (battle 11)"),
  -- ride "Halt!" into the fight: the dialog wants A, and rideOut's own
  -- drive is what taps it in the generator (H.clearGateSoldier)
  (function()
    local ph = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(ph < 4 and { "a" } or {})
      end),
    }, "battle 11 up")
  end)(),
  H.release(),
  fightStep(),
  H.call(flushEvents),
  H.cond(function() return battle.wiped end, {
    H.call(function()
      H.log(string.format("[gatelab] wipe: gameOverFired=%d padFrozen=%s -- pressing through the Annihilated screen (thawing the canary's freeze as it comes)",
        H.gameOverFired or 0, tostring(H.padFrozen)))
    end),
    aftermath(),
    H.waitFrames(30),
    H.call(function()
      after = string.format("map%d(%d,%d):ctl=%s:1DD1=%02X:goScript=%d:title=%d:thaws=%d:0103=%d:0104=%d:hp=%d/%d:wipe2field=%d",
        map(), H.fieldX(), H.fieldY(), tostring(H.hasControl()), H.readByte(0x1DD1),
        goRead, titleExec, thaws, sw(0x0103), sw(0x0104),
        H.readWord(0x1600 + 37 * LOCKE + 9), H.readWord(0x1600 + 37 * LOCKE + 11),
        H.frame - (battle.over or H.frame))
      H.log("[gatelab] [after] the loss: " .. after)
      result("wiped")
    end),
  }, {
    H.waitUntilSoft(settled, 3000, "settled after the fight", 5),
    H.waitFrames(30),
    H.call(function()
      after = string.format("map%d(%d,%d):1DD1=%02X:obj26=(%d,%d):probe=%s:hp=%d/%d",
        map(), H.fieldX(), H.fieldY(), H.readByte(0x1DD1), H.objX(26), H.objY(26),
        tostring(H.bfsPath(22, 43) ~= nil),
        H.readWord(0x1600 + 37 * LOCKE + 9), H.readWord(0x1600 + 37 * LOCKE + 11))
      H.log("[gatelab] [after] the fight: " .. after)
      result(battle.started and "fought" or "no battle")
    end),
  }),
})
