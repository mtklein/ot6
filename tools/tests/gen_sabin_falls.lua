-- gen_sabin_falls.lua -- step 9 of SABIN's scenario: Baren Falls.  Generates:
--   falls_done.mss   map 159 (the Veldt shore), SABIN+CYAN, $003C/$003F set
--                    SHADOW left at the overlook, GAU named but not
--                    joined (he takes nothing and runs; recruitment is the
--                    next step's Veldt work).

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/train_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local CH_SEL, CH_MAX, NAME_MENU = 0x056E, 0x056F, 0x0200
local RIZOPAS = 0x0155
local function inBattle()
  for i = 0, 3 do
    local hp = H.readWord(0x3bf4 + i * 2)
    if hp == 0xFFFF or hp == 0 then
    elseif hp < 10000 then return true
    else return false end
  end
  return false
end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local rizo = { seen = false, species = 0, shields = 0, smax = 0, wkc = 0,
               mask0 = nil }

local fightTier = 1
local lost = nil
local wipeN = 0
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(0x3bf4 + e * 2),
      H.readWord(0x3c1c + e * 2))
  end
  return table.concat(p, " ")
end
-- THE FIGHT (3rd pass, the #162 lab -- docs/design/bosses-wob.md §9,
-- tools/tests/lab_rizopas_template.lua): the lib's fight driver, steered
-- the way the lab's `bankboss` policy plays and a person does.  Battle
-- 18 is a fixed-length Piranha wave (~4,500 frames: the school restores
-- itself until its timer passes 60, then Rizopas surfaces) and then a
-- 775-HP, 4-shield boss whose El Nino takes ~230 from BOTH members in one
-- action about 1,100 frames after it surfaces.  A Piranha has 10 HP and
-- one shield, so a boosted swing on one is waste: the party Fights the
-- school UNBOOSTED (bank 99: BP regenerates one a turn, to the cap of 5)
-- and, the moment slot 5 surfaces -- a thing the player sees on screen --
-- the bank flips to 0 and both unload: a 3-BP Fight is 7 slashing swings
-- into a SLASH|BLUDG row, the break lands inside the first swing or two
-- and the surplus lands x4.  Lab, 10 distinct seeds including #162's
-- wipe seed: 10 wins, no deaths, no Fenix, one Potion, the boss dead a
-- mean 860 frames after surfacing (the old boost-every-turn fighter on
-- the same ten: 9 wins and the wipe, a death, a Potion a win, 1,740).
-- Care is the driver's own: Potions before Tonics, Fenix for the fallen.
local FALLS_OPTS = { tactical = false, boost = true, bank = 99, items = true,
                     healPercent = 40 }
local F = nil
local function fightPulse(_)
  if rizo.seen and FALLS_OPTS.bank ~= 0 then
    FALLS_OPTS.bank = 0
    H.log(string.format("[falls] f%d Rizopas is up -- bank 99 -> 0, spend "
      .. "everything [%s]", H.frame, partyLine()))
  end
  F.frame()
end
-- one driver per attempt (its round-cost and item memories belong to the
-- fight that spent them), with the bank re-armed for the school
local function newFighter()
  FALLS_OPTS.bank = 99
  F = H.newFightDriver("falls", FALLS_OPTS)
end
-- #159: runs EVERY frame of a real ride, not behind the inBattle() gate.
-- A wipe zeroes every battle-HP word, which inBattle() and
-- battleLoadStarted() both read as "no battle", so the old gate hid the
-- one state the watch existed for: the v0.16 qualification's attempt 1
-- sat on the annihilated screen (event PC parked at $CBC0C1, the byte
-- after `battle 18`; the battle module waits for a press that a
-- no-control ride never gives) from f18833 to the 39000-frame deadline
-- (probe_falls_wedge.lua: 2 wipes in 24 varied entries, seed $EE, both
-- caught 90 frames after the last HP word hit 0).  The lib's canary now
-- counts the same wipe as a game over at 300 frames and freezes the pad;
-- allowGameOver below keeps the run alive for the reload, and the counter
-- is a loss here too.
local function wipeWatch(tag)
  local wiped = H.partyWipedInBattle()
  wipeN = wiped and wipeN + 1 or 0
  if (H.gameOverFired or 0) > 0 and not lost then
    lost = string.format("%s: GAME OVER counted by the canary at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
  end
  if wipeN >= 90 and not lost then
    lost = string.format("%s: PARTY WIPED at f%d (tier %d) [%s]",
      tag, H.frame, fightTier, partyLine())
    H.log("[falls] LOST -- " .. lost)
    H.screenshot("falls_lost")
  end
end

-- ride/walk driver: choices steered by CH_SEL, name menu by menu state,
-- battles per fightMode ("real": the boost-and-Fight episode machine plus
-- the wipe watch -- the win bit is EARNED; default: none can open, see
-- the branch),
-- dialogs tap-A, else hold `dir` (or hands-off when dir is nil).
local function ride(dir, pred, what, budget, fightMode, choiceWant)
  local phase, hb, quiet, wasIn = 0, -900, 0, false
  -- a choice window: H.newChoice (lib/ot6_field.lua), owning the pad only
  -- while the dialog waits, the landed row asserted when the window closes
  local C = H.newChoice(choiceWant or 0, { ready = "pass", tag = what })
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format(
          "ride[%s] f%d map=%d (%d,%d) ctl=%s dlg=%s b=%s ch=%d/%d",
          what, H.frame, mapIdx(), H.fieldX(), H.fieldY(),
          tostring(H.hasControl()), tostring(H.dialogWaiting()),
          tostring(inBattle()), H.readByte(CH_SEL), H.readByte(CH_MAX)))
      end

      if fightMode == "real" then
        wipeWatch(what)
        if lost then H.setPad({}); return end
      end

      if inBattle() or H.battleLoadStarted() then
        if fightMode == "real" then
          -- the rizopas watch: record the seed row THE FRAME IT SURFACES
          if not rizo.mask0 and H.battleLoadStarted() then
            local m = 0
            for s = 0, 5 do if monPresent(s) then m = m | (1 << s) end end
            rizo.mask0 = m
            H.log(string.format("[falls] battle-up present mask=$%02X", m))
          end
          if not rizo.seen and monPresent(5) then
            rizo.seen = true
            rizo.species = H.readWord(0x57C0 + 10)
            rizo.shields = H.readByte(0x3E38 + 8 + 10)
            rizo.smax    = H.readByte(0x3E39 + 8 + 10)
            rizo.wkc     = H.readByte(0x3E9C + 8 + 10)
            H.log(string.format(
              "[falls] slot 5 SURFACED: species=$%04X shields=%d/%d wkc=$%02X",
              rizo.species, rizo.shields, rizo.smax, rizo.wkc))
          end
          wasIn = true
          fightPulse(phase)
        else
          -- #183: no L+R here.  The default rides walk maps 166/155/156,
          -- which roll no encounters (tools/audit_encounters.py 166 155
          -- 156); the jump's battle 18 rides in "real" mode above.
          H.setPad({})
        end
        return
      end
      if wasIn then
        -- the falling edge: the driver forgets the fight it just played
        wasIn = false
        if F then F.idle() end
      end

      -- choice prompts: steer to choiceWant then confirm
      if C.frame(phase) then return end

      -- the name menu, on the menu module's own state (gen_sabin_camp)
      if H.readByte(NAME_MENU) == 1 and H.readByte(0x0059) ~= 0
         and (H.readByte(0x0026) == 0x5F or H.readByte(0x0027) == 0x5F) then
        quiet = quiet + 1
        if quiet >= 30 then
          if quiet == 30 then
            H.log(string.format("[falls] NAME MENU at f%d -- START", H.frame))
          end
          H.setPad(phase < 4 and { "start" } or {})
          return
        end
        H.setPad({})
        return
      end
      quiet = 0

      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[falls] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

-- world walk: the lib's verified-step walker (write-clears trash inline and
-- stalls out the post-battle world reload); the entrance firing mid-plan
-- is the arrival
local function worldToMap(tx, ty, what, budget)
  return H.worldNavTo(tx, ty, { maxFrames = budget or 30000,
    playBattles = "tactical",
    arrive = function() return not H.worldMode() end })
end

local function seq(steps) return H.cond(function() return true end, steps) end

local function walkToFalls()
  return seq({
    worldToMap(185, 93, "falls cave (185,93)", 20000),
    settle(166, "cave 166"),
    H.navTo(7, 5, { maxFrames = 6000, playBattles = "tactical" }),
    ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
    settle(155, "overlook 155"),
    H.navTo(10, 5, { maxFrames = 6000, playBattles = "tactical" }),
    ride("up", function() return mapIdx() == 156 end, "-> 156", 3000),
    settle(156, "falls top 156"),
    ride("up", function()
      return sw(0x3C) == 1 and H.hasControl() and H.tileAligned()
    end, "arrival scene ($003C)", 15000),
    H.call(function()
      H.assertEq(sw(0x3C), 1, "$003C -- Baren Falls named")
      H.assertEq(inParty(3), false, "SHADOW left at the overlook")
      H.log(string.format("[falls] post-arrival at (%d,%d)", H.fieldX(),
        H.fieldY()))
    end),
  })
end

-- One jump attempt: (attempt 2+) reload the pre-jump checkpoint with a
-- stagger and the fighter escalated, walk onto the jump row, and ride the
-- fall + battle 18 + the shore cinematic to map 159.  `lost`
-- short-circuits the ride so the next attempt starts promptly.
local jumpWon = false

local function jumpAttempt(n)
  return H.cond(function() return not jumpWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[falls] ATTEMPT %d -- reloading the boot " ..
          "fixture and re-walking to the falls after a loss (%s)", n,
          tostring(lost))
      end),
      H.loadState(DOOR),
      -- the restored snapshot restarts the experiment: the canary's count
      -- (and its pad freeze, which loadState thaws) belong to the lost one
      H.call(function() H.gameOverFired = 0 end),
      H.waitFrames(30 + (n - 1) * 17),
      walkToFalls(),
    }, {}),
    H.call(function()
      lost, fightTier, wipeN = nil, n, 0
      H.gameOverFired = 0
      rizo.seen, rizo.mask0 = false, nil
      newFighter()
    end),
    H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
    (function()
      local frames = 0
      return ride("up", function()
        frames = frames + 1
        if frames > 39000 and lost == nil then
          lost = string.format("attempt %d deadline (39000 frames) with " ..
            "no win and no wipe seen -- a genuine stall, see #159 [%s]", n,
            partyLine())
          H.log("[falls] LOST -- " .. lost)
        end
        return lost ~= nil
            or (mapIdx() == 159 and sw(0x3F) == 1 and H.hasControl()
                and H.tileAligned() and bright() >= 15)
      end, "jump + battle 18 + the shore (attempt " .. n .. ")", 40000,
        "real", 0)
    end)(),
    H.release(),
    H.waitFrames(30),
    H.call(function()
      if lost == nil then
        jumpWon = true
        H.log(string.format("[falls] attempt %d WON battle 18", n))
      end
    end),
  }, {})
end

-- allowGameOver: the retry sweep above deliberately survives a lost
-- battle 18 (#159); the ride reads H.gameOverFired as a loss and reloads.
H.run({ maxFrames = 250000, allowGameOver = true }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance")
    H.assertEq(sw(0x3B), 1, "$003B set -- the train is behind us")
    H.log(string.format("[falls] start world (%d,%d)", H.worldX(), H.worldY()))
  end),

  walkToFalls(),

  jumpAttempt(1),
  jumpAttempt(2),
  jumpAttempt(3),
  H.call(function()
    if not jumpWon then
      error(string.format("falls: battle 18 was lost on all 3 " ..
        "attempts -- last loss: %s -- the per-attempt numbers above are " ..
        "the balance finding (#74-style); do not rig this segment",
        tostring(lost)), 0)
    end
  end),

  H.call(function()
    H.assertEq(mapIdx(), 159, "washed ashore on map 159")
    H.assertEq(sw(0x3F), 1, "$003F -- GAU met and named")
    H.assertEq(rizo.seen, true, "RIZOPAS surfaced in slot 5 (the piranhas' "..
      "death script ran)")
    H.assertEq(rizo.species, RIZOPAS, "slot 5 was RIZOPAS ($0155)")
    H.assertEq(rizo.shields, 4,
      "RIZOPAS seeds 4 shields (Ot6ShieldTbl; #139 took the fifth pip -- "
      .. "the 1W/8L real-attempt ledger at the routed curve)")
    H.assertEq(rizo.wkc, 0x05, "RIZOPAS class row SLASH|BLUDG ($05)")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq(inParty(3), false, "SHADOW gone")
    H.assertEq(inParty(11), false, "GAU did NOT join here")
    H.log(string.format("[falls_done] f%d map=%d (%d,%d) mask0=$%02X",
      H.frame, mapIdx(), H.fieldX(), H.fieldY(), rizo.mask0 or -1))
    H.screenshot("falls_done")
  end),
  H.saveState("falls_done.mss"),
  H.logStep(function()
    return string.format("falls_done generated at frame %d map 159 (%d,%d)",
      H.frame, H.fieldX(), H.fieldY())
  end),
})
