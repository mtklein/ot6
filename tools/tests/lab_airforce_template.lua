-- @manual
-- lab_airforce_template.lua -- the Air Force strategy lab, experiment half
-- (#201: the IAF Air Force wiped 2 of 3 attempts in the v0.17 fc_landing
-- regeneration, members dying with 3 BP banked).
--
-- Boots airforcelab_doorstep.mss (lab_airforce_bake.lua: gen_fc_landing's
-- route to the first input-gated moment after Ultros IV + Chupon, the
-- Air Force's doorstep), stands still IDLE frames to shift the battle-RNG
-- phase ($021e, period 60; the seed a battle draws is phase*4 --
-- lib/ot6.lua "battle rng seed"), taps A through what waits, and fights
-- the Air Force (formation $1CB: AirForce $113 slot 0, Laser Gun $145
-- slot 2, MissileBay $147 slot 4; the Speck $146 is slot 3, launched by
-- the body's script) under ONE declared policy with the lib's fight
-- driver, and reports one machine-readable [result] line, PASSing either
-- way -- this file measures, it does not assert.  If the doorstep fixture
-- is the Ultros teaser instead (the bake found no window after Ultros),
-- Ultros IV + Chupon is fought first under the gen's own driver, the same
-- for every policy, so the Air Force entry stays paired per seed.
--
-- The batch runner (airforcelab_batch.sh) substitutes the @TOKEN@ defaults
-- below (sed).  Tokens: POLICY (a POLICIES key), IDLE (frames to stand).
--
-- ---- the Air Force, decoded (not recalled) --------------------------------
-- monster_prop.dat (32 bytes at id*32): AirForce $113 speed 35, atk 10,
-- def 150, mdef 120, mpow 12, HP 8000, L25; Laser Gun $145 speed 30, def
-- 130, mdef 140, mpow 9, HP 3300, L24; MissileBay $147 speed 20, def 135,
-- mdef 150, mpow 8, HP 3000, L25; Speck $146 speed 15, def 230, mdef 160,
-- HP 420, L25.  All four: absorb $00, null $00, weak $84 = bolt|water.
-- Ot6ShieldTbl (ot6_hud.asm): AirForce 8 PIERCE, Laser Gun 3 PIERCE,
-- MissileBay 3 PIERCE, Speck 1 any-class.  battle_monsters.dat $1CB:
-- present mask $15 (slots 0, 2, 4), species 113 -- 145 146 147 --.
-- AI (ai_script.asm): laser gun _325: HP >= 1536 -> ATOMIC_RAY $B4 (fire,
-- pow 80, all party) / TEK_LASER $B5 x2; HP < 1536 -> DIFFUSER $B6 (bolt,
-- pow 62, all party) x2 / TEK_LASER, twice; on death with 2 monsters left
-- it sets battle switch 0 (the body's countdown).  missilebay _327: HP >=
-- 1536 -> MISSILE $DD (single, pow 4, hit 126, status 2 $40 = Seizure)
-- every turn; HP < 1536 -> MISSILE / LAUNCHER $CD + MISSILE x2 / LAUNCHER.
-- airforce _275: with switch 0 set, battle var 1 counts 6 turns (Speck
-- restored + HASTE at count 6, then 5..1), then kills the Speck and fires
-- WAVECANNON $B7 (bolt, pow 110, all party) and restarts the count; with
-- the switch clear: TEK_LASER + DIFFUSER when 2 monsters stand, TEK_LASER
-- x2 otherwise.  So the kill order decides the fight's shape.  Measured
-- (control_i0/i6/i12): the gun dying while the bay stands leaves 2
-- monsters (body + bay) -> the switch is set, and the body's next turns
-- run restore_monsters slot 3 (cmd $24 atk $03: the Speck), HASTE (cmd
-- $30), dialog $22, then one Count dialog ($38..$3C, $45) per turn to the
-- cannon; the bay dying first leaves 3 standing (no switch), and the gun
-- dying second leaves 1 (no switch): no Speck, no cannon, a body that
-- only TEK_LASERs.
-- ----------------------------------------------------------------------------
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY = "@POLICY@"
local IDLE = tonumber("@IDLE@") or 0
if POLICY:find("@") then POLICY = "control" end
-- the fixture is a literal below (compose.py inlines only string literals);
-- the batch runner substitutes both.  The bake banked only the teaser:
-- the Air Force loads 169 frames after Ultros tears down with no input
-- between (bake.log), so there is no later doorstep to stand on.
local FIXTURE = "@FIXTURE@"
if FIXTURE:find("@") then FIXTURE = "airforcelab_teaser" end

local TERRA, LOCKE, EDGAR = 0x00, 0x01, 0x04
local BOLT = 0x02
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local AF, LASER, SPECK, BAY = 0x0113, 0x0145, 0x0146, 0x0147
local ULTROS4, CHUPON = 0x0168, 0x012F
local CAP = 24000                    -- Air Force battle frames (the regen's losses ran ~12k)

-- gen_fc_landing's FIGHT: the current driver, the control, and the
-- driver every policy fights Ultros with when the fixture is the teaser
local BASE = { tactical = true, boost = true, bank = 2, items = true,
               healPercent = 50, magic = { [TERRA] = { spell = BOLT }, [LOCKE] = { spell = BOLT } },
               nuke = { BOLT } }
local function with(over)
  local o = {}
  for k, v in pairs(BASE) do o[k] = v end
  for k, v in pairs(over) do o[k] = v end
  return o
end
-- Focus masks: opts.focus names a slot (liveness) and the $7B7E bit that
-- puts the cursor on it.  Measured from the control batch's [act] lines
-- (tgt = the $B8 target word at ExecCmd, monster bits in the high byte)
-- against which slot's HP moved: see docs/design/airforce.md.
local M0, M2, M4 = 0x01, 0x04, 0x10
local FOCUS_PODS = { { slot = 2, mask = M2 }, { slot = 4, mask = M4 }, { slot = 0, mask = M0 } }
local FOCUS_BAY  = { { slot = 4, mask = M4 }, { slot = 2, mask = M2 }, { slot = 0, mask = M0 } }
local FOCUS_BODY = { { slot = 0, mask = M0 }, { slot = 2, mask = M2 }, { slot = 4, mask = M4 } }
-- gun first (the default cursor, and it silences Atomic Ray), then the
-- body: the gun's death starts the body's countdown and only the body's
-- boss_death stops it; the bay last (its death is not needed)
local FOCUS_GUNBODY = { { slot = 2, mask = M2 }, { slot = 0, mask = M0 }, { slot = 4, mask = M4 } }

-- The policies.  Every one is a set of the lib's fight-driver options --
-- the same controller the gen uses, steered differently -- so a policy
-- here is one a person can execute through the menus.  None reads hidden
-- HP or future RNG.
local POLICIES = {
  control  = with({}),
  -- the bank: spend pips as they come / hold to 3
  bank0    = with({ bank = 0 }),
  bank3    = with({ bank = 3 }),
  -- the keyed line spends the bank's boost instead of the smallest break
  keyboost = with({ keyBoost = true }),
  -- kill order (#189): pods first (gun, then bay, then body: no countdown),
  -- bay first (bay, gun: the countdown), body first
  pods     = with({ focus = FOCUS_PODS }),
  bay      = with({ focus = FOCUS_BAY }),
  body     = with({ focus = FOCUS_BODY }),
  gunbody  = with({ focus = FOCUS_GUNBODY }),
  -- the once-a-battle summon: EDGAR's Shiva (the stone he wears at the
  -- deck; ice, unweak, but unreflectable and unabsorbed, all parts).
  -- TERRA wears no esper at the teaser (bake: esper=$FF), so the escape
  -- config's Ramuh line has nobody to fire from here.
  summon   = with({ summon = { [EDGAR] = { mp = 27 } } }),
  pods_summon = with({ focus = FOCUS_PODS, summon = { [EDGAR] = { mp = 27 } } }),
  pods_bank0  = with({ focus = FOCUS_PODS, bank = 0 }),
  -- care threshold: heal earlier
  heal70   = with({ healPercent = 70 }),
  -- bay with a per-frame target-window trace (TGTWATCH below): the focus
  -- steer's presses and what the window shows after each, for the #189
  -- steer finding.  Observation only; the policy is bay's.
  bay_trace = with({ focus = FOCUS_BAY }),
  -- TERRA's attack line: she knows no Bolt (bake: spells 00,04,05,2D,30,
  -- 32 = Fire, Drain, Fire2, Cure, Life, Antdot), so the gen's Bolt line
  -- never fires for her and her free turns are bare Fights; Fire2 ($05)
  -- is the strongest cast she holds (unweak: the 1x tier, 2x broken)
  terrafire = with({ magic = { [TERRA] = { spell = 0x05 }, [LOCKE] = { spell = BOLT } } }),
  pods_terrafire = with({ focus = FOCUS_PODS, magic = { [TERRA] = { spell = 0x05 }, [LOCKE] = { spell = BOLT } } }),
}
local opts = assert(POLICIES[POLICY], "unknown POLICY " .. POLICY)
opts.traceTgt = true                 -- log every target confirm (chars/mons masks); observation only

local function map() return H.mapId() & 0x3ff end

-- The field bag ($1969) syncs from the battle module only at teardown, so
-- mid-fight the count comes from the battle inventory: $2686, records of 5
-- bytes, +0 item, +3 quantity (battle-ram.txt:456-475).
local function bagNow(id, baseline)
  if H.battleActive() then
    for i = 0, 255 do
      if H.readByte(0x2686 + i * 5) == id then return H.readByte(0x2689 + i * 5) end
    end
    return baseline
  end
  if H.battleLoadStarted() then return baseline end
  return H.invCountOf(id)
end

local function monHp(s) return H.readWord(0x3BFC + s * 2) end
local function monSh(s) return H.readByte(0x3E40 + s * 2) end
local function pHp(e) return H.readWord(0x3BF4 + e * 2) end
local function pBp(e) return H.readByte(0x3E9C + e * 2) end
local function pMp(e) return H.readWord(0x3C08 + e * 2) end
local function pSt2(e) return H.readByte(0x3EE5 + e * 2) end       -- status 2: $40 Seizure
local function monLine()
  return string.format("af=%d/sh%d gun=%d/sh%d speck=%d/sh%d bay=%d/sh%d",
    monHp(0), monSh(0), monHp(2), monSh(2), monHp(3), monSh(3), monHp(4), monSh(4))
end
local function partyLine()
  return string.format("hp=%d,%d,%d bp=%d,%d,%d st2=%02X,%02X,%02X",
    pHp(0), pHp(1), pHp(2), pBp(0), pBp(1), pBp(2), pSt2(0), pSt2(1), pSt2(2))
end
local function isAF() return H.formationHas({ [AF] = true }) end
-- TGTWATCH (policy names ending _trace): every frame the battle menu sits
-- in target select ($7BC2 = $38), log the change of the monster mask
-- ($7B7E), the party mask ($7B7D), the target group ($7ACE) or the pad the
-- engine latched ($4218/$4219 read side-effect-free off snesDebug).
local TGTWATCH = POLICY:sub(-6) == "_trace"
local tgtLast = nil
local function tgtWatch(t)
  if not TGTWATCH then return end
  local st = H.readByte(0x7BC2)
  if st ~= 0x38 then tgtLast = nil; return end
  local pad = emu.read(0x4218, emu.memType.snesDebug) | (emu.read(0x4219, emu.memType.snesDebug) << 8)
  local sig = string.format("mons=%02X chars=%02X grp=%02X pad=%04X actor=%d",
    H.readByte(0x7B7E), H.readByte(0x7B7D), H.readByte(0x7ACE), pad, H.readByte(0x62CA) & 3)
  if sig ~= tgtLast then
    H.log(string.format("[tgtwatch] t=%d %s", t, sig))
    tgtLast = sig
  end
end
local function isUltros() return H.formationHas({ [ULTROS4] = true, [CHUPON] = true }) end

-- the seed every InitBattle draws, read off the `sta $be` store the way
-- H.newSeedSweep reads it (lib/ot6.lua "battle rng seed")
local seeds, seedN = {}, 0
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    seedN = seedN + 1
    local seed = emu.getState()["cpu.a"] & 0xff
    seeds[seedN] = seed
    H.log(string.format("[lab] battle %d seeded $be=$%02X from $021e=%d at f%d",
      seedN, seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

-- Per-action attribution (lab_nerapa_template's hooks): ExecCmd runs with
-- X = the acting entity offset and $b5/$b6 the command/attack after
-- queue-time folding, $b8 the target word; SaveForMimic right after the
-- normal-action path returns; ExecRetal for counters.  Observers only.
local actT, inAF = 0, false
local stats = { wavecannon = 0, missile = 0, launcher = 0, diffuser = 0, atomic = 0, teklaser = 0,
                acts = {}, maxhit = 0, maxhitWho = "" }
local function armActionWatch()
  local function hook(addr, fn)
    emu.addMemoryCallback(function() fn(emu.getState()) end, emu.callbackType.exec, addr, addr)
  end
  hook(H.sym("ExecCmd@battle_code"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 20 and x % 2 == 0 and inAF then
      local e, cmd, atk = x // 2, H.readByte(0xB5), H.readByte(0xB6)
      if e >= 4 then
        -- the body's script turns (control_i6, decoded): cmd $24 atk $03 =
        -- restore_monsters slot 3 (the Speck launch); cmd $21 = a dialog,
        -- atk $38..$3C then $45 = Count 6..1
        if e == 4 and cmd == 0x24 and atk == 0x03 and res.speckT == nil then res.speckT = actT end
        if e == 4 and cmd == 0x21 and ((atk >= 0x38 and atk <= 0x3C) or atk == 0x45) then
          stats.count = (stats.count or 0) + 1
        end
        if atk == 0xB7 then stats.wavecannon = stats.wavecannon + 1 end
        if atk == 0xDD then stats.missile = stats.missile + 1 end
        if atk == 0xCD then stats.launcher = stats.launcher + 1 end
        if atk == 0xB6 then stats.diffuser = stats.diffuser + 1 end
        if atk == 0xB4 then stats.atomic = stats.atomic + 1 end
        if atk == 0xB5 then stats.teklaser = stats.teklaser + 1 end
      end
      H.log(string.format("[act] t=%d start e%d cmd=$%02X atk=$%02X tgt=$%04X %s %s",
        actT, e, cmd, atk, H.readWord(0xB8), monLine(), partyLine()))
    end
  end)
  hook(H.sym("ExecRetal"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    if inAF then
      H.log(string.format("[retal] t=%d e%d counters %s %s", actT, x // 2, monLine(), partyLine()))
    end
  end)
  hook(H.sym("SaveForMimic"), function(cpu)
    local x = cpu["cpu.x"] & 0xffff
    if x < 20 and x % 2 == 0 and inAF then
      H.log(string.format("[act] t=%d end   e%d %s %s", actT, x // 2, monLine(), partyLine()))
    end
  end)
end

local FU = H.newFightDriver("Ultros", BASE)
local F = H.newFightDriver("AF", opts)
local res = { deaths = {}, raises = 0, kills = {}, speckT = nil, hits = 0 }
local t, lost, why, wipedN = 0, false, nil, 0
local afSeen, afDone, afStartF, afEndF = false, false, nil, nil
local fenix0, potion0, tonic0
local fenixLive, potionLive, tonicLive
local monLast, hpLast, presentLast = {}, {}, {}
local sapSeen = {}
local lastMon, lastMp, lastBp = "none", "none", "none"     -- the last live battle-RAM samples (teardown reads $FFFF)

local function fight()
  return H.driveUntil(function()
    if (H.gameOverFired or 0) > 0 then lost, why = true, "gameover"; return true end
    local active, loading = H.battleActive(), H.battleLoadStarted()
    if active and isAF() then
      if not afSeen then
        afSeen, afStartF = true, H.frame
        H.log(string.format("[lab] the Air Force is up at f%d: %s %s", H.frame, monLine(), partyLine()))
      end
      inAF = true
      t = t + 1
      actT = t
      if H.partyWipedInBattle() then wipedN = wipedN + 1 else wipedN = 0 end
      if wipedN >= 300 then lost, why = true, "wiped"; return true end
      if t >= CAP then lost, why = true, "cap"; return true end
      tgtWatch(t)
      lastMon, lastMp, lastBp = monLine(), string.format("%d,%d,%d", pMp(0), pMp(1), pMp(2)),
                                string.format("%d,%d,%d", pBp(0), pBp(1), pBp(2))
      fenixLive = bagNow(FENIX_DOWN, fenixLive or fenix0)
      potionLive = bagNow(POTION, potionLive or potion0)
      tonicLive = bagNow(TONIC, tonicLive or tonic0)
      local ids = H.monsterIds()
      for s = 0, 5 do
        -- present: the battle's own per-slot bit ($3AA8 + s*2 bit 0, the
        -- driver's MON_PRESENT); the stage mask $3F45 is not rewritten by
        -- restore_monsters (control_i6: the Speck fought at 198/42 HP with
        -- no [stage] line)
        local present = (H.readByte(0x3AA8 + s * 2) & 1) == 1
        if presentLast[s] ~= nil and present ~= presentLast[s] then
          H.log(string.format("[stage] t=%d slot %d %s (id $%03X) %s", t, s,
            present and "APPEARS" or "leaves", ids[s + 1] ~= 0xFFFF and ids[s + 1] or 0, monLine()))
          if present and s == 3 and res.speckT == nil then res.speckT = t end
        end
        presentLast[s] = present
        local hp, sh = monHp(s), monSh(s)
        if monLast[s] ~= nil and present and (hp ~= monLast[s].hp or sh ~= monLast[s].sh) then
          res.hits = res.hits + 1
          H.log(string.format("[hit] t=%d slot %d hp=%d (%+d) sh=%d (%+d) bp=%d,%d,%d",
            t, s, hp, hp - monLast[s].hp, sh, sh - monLast[s].sh, pBp(0), pBp(1), pBp(2)))
          if monLast[s].hp > 0 and hp == 0 then
            res.kills[#res.kills + 1] = string.format("s%d@%d", s, t)
            H.log(string.format("[kill] t=%d slot %d (id $%03X) down; order so far %s", t, s,
              ids[s + 1], table.concat(res.kills, ",")))
          end
        end
        if present then monLast[s] = { hp = hp, sh = sh } end
      end
      for e = 0, 2 do
        local php = pHp(e)
        if hpLast[e] ~= nil and php ~= hpLast[e] then
          H.log(string.format("[hp] t=%d entity %d %d -> %d (%+d) bp=%d st2=%02X", t, e, hpLast[e], php, php - hpLast[e], pBp(e), pSt2(e)))
          if php < hpLast[e] and hpLast[e] - php > stats.maxhit then
            stats.maxhit, stats.maxhitWho = hpLast[e] - php, string.format("e%d@%d", e, t)
          end
          if hpLast[e] > 0 and php == 0 then
            local bp = pBp(e)
            res.deaths[#res.deaths + 1] = string.format("e%d@%d:bp%d", e, t, bp)
            H.log(string.format("[death] t=%d entity %d from %d bp=%d party_bp=%d,%d,%d st2=%02X", t, e, hpLast[e], bp, pBp(0), pBp(1), pBp(2), pSt2(e)))
          elseif hpLast[e] == 0 and php > 0 then
            res.raises = res.raises + 1
            H.log(string.format("[raise] t=%d entity %d to %d hp", t, e, php))
          end
        end
        hpLast[e] = php
        if (pSt2(e) & 0x40) ~= 0 and not sapSeen[e] then
          sapSeen[e] = true
          H.log(string.format("[sap] t=%d entity %d is Seized (status 2 $%02X) at %d hp", t, e, pSt2(e), php))
        elseif (pSt2(e) & 0x40) == 0 then sapSeen[e] = nil end
      end
    elseif afSeen and not active and not loading then
      inAF = false
      if not afDone then
        afDone, afEndF = true, H.frame
        H.log(string.format("[lab] the Air Force battle tore down at f%d (t=%d) %s", H.frame, t, partyLine()))
      end
      -- settle: the FC landing cutscene follows a win; a loss is the game over above
      if H.frame - afEndF >= 600 then return true end
    end
    return false
  end, CAP + 40000, {
    H.call(function()
      if lost then H.setPad({}); return end
      if H.battleLoadStarted() or H.battleActive() then
        if isAF() then F.frame() else FU.frame() end
        return
      end
      if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}) else H.setPad({}) end
    end),
  }, "the Air Force falls or the party does")
end

H.run({ maxFrames = 80000, allowGameOver = true }, {
  H.loadState("build/states/@FIXTURE@.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map() == 10 or map() == 6, true, "the doorstep fixture is on the Blackjack deck (map 10/6)")
    armSeedWatch()
    armActionWatch()
    fenix0, potion0, tonic0 = H.invCountOf(FENIX_DOWN), H.invCountOf(POTION), H.invCountOf(TONIC)
    H.log(string.format("[lab] set-off policy=%s idle=%d fixture=%s phase=%d dialog=%s control=%s bag f/p/t=%d/%d/%d at f%d",
      POLICY, IDLE, FIXTURE, H.readByte(0x021E), tostring(H.dialogWaiting()), tostring(H.hasControl()),
      fenix0, potion0, tonic0, H.frame))
  end),
  -- the seed knob: stand still IDLE frames ($021e ticks once a frame, period 60)
  H.waitFrames(IDLE),
  H.call(function()
    H.log(string.format("[lab] stood %d frames; phase now %d, f%d", IDLE, H.readByte(0x021E), H.frame))
  end),
  H.cond(function() return FIXTURE == "airforcelab_teaser" end, {
    -- the teaser fixture: the arming walk, exactly the gen's
    H.navTo(22, 6, { maxFrames = 6000, playBattles = "tactical", healer = TERRA, magic = BASE.magic,
                     nuke = BASE.nuke, items = true, bank = BASE.bank, healPercent = BASE.healPercent,
                     care = false, arrive = function() return not H.hasControl() or H.fieldX() == 22 end }),
  }, {}),
  fight(),
  H.call(function()
    H.setPad({})
    if F.idle then F.idle() end
    -- the end frame, kept with the log (a wipe's annihilated screen, or the
    -- landing cutscene): the "look at the screen" evidence per attempt
    H.screenshot(string.format("airforcelab_%s_i%d_end", POLICY, IDLE))
    local fenix1, potion1, tonic1 = fenixLive or fenix0, potionLive or potion0, tonicLive or tonic0
    local outcome
    if not lost and afSeen and afDone then outcome = "won"
    elseif not afSeen then outcome = "lost_before_af_" .. (why or "unknown")
    else outcome = "lost_" .. (why or "unknown") end
    local afSeed = "none"
    for i = 1, seedN do afSeed = string.format("$%02X", seeds[i]) end   -- the last battle seeded is the Air Force's
    H.log(string.format(
      "[result] policy=%s idle=%d fixture=%s seed=%s nseeds=%d outcome=%s t=%d fenix=%d potion=%d tonic=%d " ..
      "deaths=%s raises=%d kills=%s speck=%s count=%d wavecannon=%d missile=%d launcher=%d diffuser=%d atomic=%d teklaser=%d " ..
      "maxhit=%d@%s hits=%d mon=%s mp=%s bp=%s",
      POLICY, IDLE, FIXTURE, afSeed, seedN, outcome, t,
      fenix0 - fenix1, potion0 - potion1, tonic0 - tonic1,
      #res.deaths > 0 and table.concat(res.deaths, ";") or "none", res.raises,
      #res.kills > 0 and table.concat(res.kills, ",") or "none",
      res.speckT and tostring(res.speckT) or "none", stats.count or 0,
      stats.wavecannon, stats.missile, stats.launcher, stats.diffuser, stats.atomic, stats.teklaser,
      stats.maxhit, stats.maxhitWho, res.hits, lastMon, lastMp, lastBp))
  end),
})
