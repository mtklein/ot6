-- @manual
-- lab_nerapa_template.lua -- the Nerapa strategy lab, experiment half.
--
-- Boots nerapalab_doorstep.mss (lab_nerapa_bake.lua: Nerapa's doorstep at
-- (106,15) on the escape map 393, CELES dressed, ~3:43 on the 6:00 master
-- clock), stands still IDLE frames to shift the battle-RNG phase ($021e,
-- period 60; the seed a battle draws is phase*4 -- lib/ot6.lua "battle rng
-- seed"), talks to Nerapa (face right, A -> battle 81, formation 451,
-- monster 280), fights it under ONE declared policy with the lib's fight
-- driver, and reports one machine-readable [result] line, PASSing either
-- way -- this file measures, it does not assert.  A win, a wipe, the
-- clock's expiry and the frame cap are all measurements.
--
-- The batch runner (nerapalab_batch.sh) substitutes the @TOKEN@ defaults
-- below (sed).  Tokens:
--   POLICY  one of POLICIES below
--   IDLE    frames to stand still before the talk (only IDLE mod 60 matters)
--
-- Per attempt the log carries, read-only: the seed Nerapa's InitBattle
-- drew ($be), every change to Nerapa's HP and shield count with the battle
-- frame it landed on, every party death (with the Condemned count at the
-- time, so Doom and damage are told apart), every raise, Condemned's onset
-- per slot, and the 300-frame status line the driver already prints.
--
-- ---- Nerapa, decoded (not recalled) ---------------------------------------
-- monster_prop.dat row $118 (32 bytes at +$2300): speed 48, attack 11,
-- hit 100, evade 0, mblock 0, defense 105, m.def 150, m.pow 10, HP 2800,
-- MP 280, level 26; absorb $01 FIRE; null $D8 (poison|wind|earth|water);
-- weak $26 = ICE|BOLT|HOLY.  Ot6ShieldTbl (ot6_hud.asm:1837): 5 shields,
-- class-weak SLASH|PIERCE.  AI (ai_script.asm:5237-5266): on its first
-- turn Condemned on all four slots (once: monster switch 0), then the loop
-- Battle/Battle/Fire2 . Battle/Fireball/Fire3 . Battle/Battle/Fire2; a
-- Fight command against it is countered with a Battle and counted -- the
-- 7th Fight draws Roulette.  Condemned's count (battle_main.asm:1531-1545)
-- is 20 + max(0, 60 - (26 + rand(0..25))) = 29..54 ticks, one tick per ATB
-- overflow of that character; at 1 it casts Doom (:15296-15303).
-- ----------------------------------------------------------------------------
local H = dofile("tools/tests/lib/ot6.lua")

local POLICY = "@POLICY@"
local IDLE = tonumber("@IDLE@") or 0
if POLICY:find("@") then POLICY = "control" end

local TERRA, LOCKE, EDGAR, CELES = 0x00, 0x01, 0x04, 0x06
local BOLT, ICE = 0x02, 0x01
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local CAP = 14000                    -- fight frames; the clock is ~13,300
local CLOCK_MARGIN = 900             -- gen_fc_escape's: a kill under this is the escape lost

-- The policies.  Every one is a set of the lib's fight-driver options --
-- the same controller the gen uses, steered differently -- so a policy
-- here is one a person can execute through the menus.  None reads hidden
-- HP or future RNG.  (The driver's absorb guard consults the species'
-- absorb byte; no policy here casts fire, so it never fires against
-- Nerapa.)
local POLICIES = {
  -- gen_fc_escape's FIGHT_ESCAPE: the current driver, unchanged
  control = { tactical = true, boost = true, bank = 0, items = true,
              healPercent = 40, nuke = { BOLT },
              summon = { [TERRA] = { mp = 30 }, [EDGAR] = { mp = 27 } } },
  -- break-first: chip unboosted (BP regenerates) until the bank holds 2,
  -- then spend -- a 2-BP Bolt folds to Bolt3, a 2-BP Fight is three
  -- swings -- into a gauge the earlier chips have thinned or broken
  breakfirst = { tactical = true, boost = true, bank = 2, items = true,
                 healPercent = 40, nuke = { BOLT, ICE },
                 summon = { [TERRA] = { mp = 30 } } },
  -- Condemned-aware all-in: every turn is damage from turn 1.  No item
  -- line, no cure line, no raises; Bolt where known, Ice otherwise
  -- (Nerapa is weak to both), Shiva once, the crossbow, boosted Fight.
  allin = { tactical = true, boost = true, bank = 0, items = false,
            cure = false, nuke = { BOLT, ICE },
            summon = { [TERRA] = { mp = 30 } } },
  -- all-in with the break-first cadence
  allin_bank2 = { tactical = true, boost = true, bank = 2, items = false,
                  cure = false, nuke = { BOLT, ICE },
                  summon = { [TERRA] = { mp = 30 } } },
  -- raise discipline, approximated: the driver has no per-target raise
  -- rule, so the bag reserve caps the fight at ONE Fenix Down (27 in the
  -- bag, floor 26); Potions and cures as the control
  raise1 = { tactical = true, boost = true, bank = 0, items = true,
             healPercent = 40, nuke = { BOLT, ICE },
             summon = { [TERRA] = { mp = 30 } },
             reserve = { [FENIX_DOWN] = 26 } },
  -- no raises at all, care only for a member inside one round of death
  -- (healPercent 0: the fraction rule never fires, the lethal-next-round
  -- rule still does), damage otherwise
  noraise = { tactical = true, boost = true, bank = 0, items = true,
              healPercent = 0, nuke = { BOLT, ICE },
              summon = { [TERRA] = { mp = 30 } },
              reserve = { [FENIX_DOWN] = 27 } },
}
local opts = assert(POLICIES[POLICY], "unknown POLICY " .. POLICY)

local function map() return H.mapId() & 0x3ff end
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361
local function master() return H.readWord(0x1189) end

-- The field bag ($1969) syncs from the battle module only at teardown, so
-- mid-fight the count comes from the battle inventory: $2686, records of 5
-- bytes, +0 item, +3 quantity (battle-ram.txt:456-475).  Not populated
-- during battle load: hand back the baseline then.
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

-- the seed Nerapa's InitBattle draws, read off the `sta $be` store the
-- way H.newSeedLadder reads it (lib/ot6.lua "battle rng seed")
local seedDrawn, seedN = nil, 0
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    seedN = seedN + 1
    local seed = emu.getState()["cpu.a"] & 0xff
    if seedDrawn == nil then seedDrawn = seed end
    H.log(string.format("[lab] battle %d seeded $be=$%02X from $021e=%d at f%d",
      seedN, seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

local function talk(face, cap, tag)
  local t = 0
  return H.driveUntil(function()
    t = t + 1
    return t >= cap or H.battleActive() or H.battleLoadStarted()
  end, cap + 300, {
    H.call(function()
      local c = t % 48
      if c < 4 then H.setPad({ [face] = true })
      elseif c >= 24 and c < 28 then H.setPad({ a = true })
      else H.setPad({}) end
    end),
  }, tag)
end

local F = H.newFightDriver("Nerapa", opts)
local res = { deaths = {}, raises = 0, cond = {}, hits = 0 }
local t, lost, why, wipedN = 0, false, nil, 0
local fenix0, potion0, tonic0
-- sampled from the battle inventory every active frame: a wipe tears
-- down into the Game Over without syncing the field bag, so a post-fight
-- bag read says 0 spent on every loss (control i15, 2026-09-07)
local fenixLive, potionLive, tonicLive
local monHp, monSh = nil, nil
local hpLast, condLast, condSeen = {}, {}, {}

local function fight()
  return H.driveUntil(function()
    t = t + 1
    if (H.gameOverFired or 0) > 0 then lost, why = true, "gameover"; return true end
    if H.partyWipedInBattle() then wipedN = wipedN + 1 else wipedN = 0 end
    if wipedN >= 300 then lost, why = true, "wiped"; return true end
    if master() == 0 then lost, why = true, "clock"; return true end
    if t >= CAP then lost, why = true, "cap"; return true end
    if H.battleActive() then
      fenixLive = bagNow(FENIX_DOWN, fenixLive or fenix0)
      potionLive = bagNow(POTION, potionLive or potion0)
      tonicLive = bagNow(TONIC, tonicLive or tonic0)
      -- Nerapa: HP $3BFC (slot 0), shields $3E40 (ot6 hud); log every change
      local hp, sh = H.readWord(0x3BFC), H.readByte(0x3E40)
      if monHp ~= nil and (hp ~= monHp or sh ~= monSh) then
        res.hits = res.hits + 1
        H.log(string.format("[hit] t=%d nerapa hp=%d (%+d) sh=%d (%+d) bp=%d,%d,%d,%d master=%d",
          t, hp, hp - monHp, sh, sh - monSh,
          H.readByte(0x3E9C), H.readByte(0x3E9E), H.readByte(0x3EA0), H.readByte(0x3EA2), master()))
      end
      if monHp == nil and hp > 0 then
        H.log(string.format("[hit] t=%d nerapa up: hp=%d sh=%d", t, hp, sh))
      end
      if hp > 0 or monHp ~= nil then monHp, monSh = hp, sh end
      for e = 0, 3 do
        local php = H.readWord(0x3BF4 + e * 2)
        local cbit = (H.readByte(0x3EE5 + e * 2) & 1) == 1
        local cnt = H.readByte(0x3B05 + e * 2)
        if cbit and not condSeen[e] and cnt > 0 then
          condSeen[e] = true
          res.cond[e] = { t = t, n = cnt }
          H.log(string.format("[condemned] t=%d entity %d count %d", t, e, cnt))
        end
        if hpLast[e] ~= nil then
          if hpLast[e] > 0 and php == 0 then
            local cause = (condLast[e] ~= nil and condLast[e] > 0 and condLast[e] <= 2) and "doom" or "dmg"
            res.deaths[#res.deaths + 1] = string.format("e%d@%d:%s", e, t, cause)
            H.log(string.format("[death] t=%d entity %d (%s; last condemned count %s) master=%d",
              t, e, cause, tostring(condLast[e]), master()))
          elseif hpLast[e] == 0 and php > 0 then
            res.raises = res.raises + 1
            H.log(string.format("[raise] t=%d entity %d to %d hp", t, e, php))
          end
        end
        hpLast[e] = php
        if cbit and cnt > 0 then condLast[e] = cnt end
      end
    end
    return not nerapaUp() and not H.battleActive() and not H.battleLoadStarted()
  end, CAP + 500, {
    H.call(function()
      if lost then H.setPad({}); return end
      if H.battleLoadStarted() or H.battleActive() then F.frame(); return end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) else H.setPad({}) end
    end),
  }, "Nerapa falls ($0361 clears) or the party does")
end

H.run({ maxFrames = 40000, allowGameOver = true }, {
  H.loadState("build/states/nerapalab_doorstep.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 393, "the doorstep fixture is on the escape map (393)")
    H.assertEq(H.fieldX() == 106 and H.fieldY() == 15, true, "standing at (106,15)")
    H.assertEq(nerapaUp(), true, "$0361 set -- Nerapa stands")
    armSeedWatch()
    fenix0, potion0, tonic0 = H.invCountOf(FENIX_DOWN), H.invCountOf(POTION), H.invCountOf(TONIC)
    H.log(string.format("[lab] set-off policy=%s idle=%d phase=%d master=%d bag f/p/t=%d/%d/%d at f%d",
      POLICY, IDLE, H.readByte(0x021E), master(), fenix0, potion0, tonic0, H.frame))
  end),
  -- the seed knob: stand still IDLE frames ($021e ticks once a frame, period 60)
  H.waitFrames(IDLE),
  H.call(function()
    H.log(string.format("[lab] stood %d frames; phase now %d, master %d, f%d", IDLE, H.readByte(0x021E), master(), H.frame))
  end),
  talk("right", 4000, "Nerapa engaged"),
  fight(),
  H.call(function()
    H.setPad({})
    if F.idle then F.idle() end
    local clockLeft = master()
    -- the last live battle-inventory sample (see fenixLive); the field bag
    -- is only trusted after a win's teardown, and even then the live
    -- sample is what the fight itself spent
    local fenix1, potion1, tonic1 = fenixLive or fenix0, potionLive or potion0, tonicLive or tonic0
    local outcome
    if not lost and not nerapaUp() then
      outcome = clockLeft >= CLOCK_MARGIN and "won" or "won_late"
    else
      outcome = "lost_" .. (why or "unknown")
    end
    local cond = {}
    for e = 0, 3 do
      local c = res.cond[e]
      cond[#cond + 1] = c and string.format("e%d@%d:%d", e, c.t, c.n) or string.format("e%d:none", e)
    end
    H.log(string.format(
      "[result] policy=%s idle=%d seed=%s outcome=%s t=%d clock_left=%d fenix=%d potion=%d tonic=%d " ..
      "deaths=%s raises=%d condemned=%s hits=%d mon_hp=%s mon_sh=%s nseeds=%d",
      POLICY, IDLE, seedDrawn and string.format("$%02X", seedDrawn) or "none", outcome, t, clockLeft,
      fenix0 - fenix1, potion0 - potion1, tonic0 - tonic1,
      #res.deaths > 0 and table.concat(res.deaths, ";") or "none", res.raises,
      table.concat(cond, ";"), res.hits, tostring(monHp), tostring(monSh), seedN))
  end),
})
