-- gen_fc_escape.lua -- from the Floating Continent's save alcove
-- (checkpoint Q, `fc-alcove-v1`) to the World of Ruin's first ground:
-- AtmaWeapon, the statues, the 6:00 escape past Nerapa, Shadow's wait,
-- and the airship's flight into the RUIN cutscene.  Generates
-- wor_landing.mss (no battery cut: nothing between the alcove and the
-- WoR landing is a save point, and the escape clock forbids the menu).
--
-- The step: cold-Continue `fc-alcove-v1` at map 358 (8,10), assert its
-- contract, top up, walk out onto 394 and up to AtmaWeapon's doorstep
-- (60,16) below his NPC at (60,15), talk with the clean gesture (face,
-- release, A while stationary), FIGHT him with the tactical driver until
-- switch $035F clears, heal back on 394, climb the stair spine onto the
-- (60,11) statue trigger, absorb the scene onto the escape map 393 at
-- (67,16) -- the 6:00 master clock and the 5:55 Shadow clock start at
-- Shadow's "Get outta here" and run through menus and battles, so no
-- field menu from here -- east to Nerapa at (108,15) (face right, A ->
-- battle 81), past (112,15) to the ledge (115,17), answer "Wait!!" (the
-- last choice row) and hold until Shadow arrives ($037D), then absorb the
-- exit flow as far as it goes and bank the landing.  Every fight is real;
-- nothing is written.
--
-- Technique sources (read-only probes): probe_fc_atma4/atma5 (doorstep
-- and talk), probe_fc_statues (the spine), probe_fc_escape (the route,
-- Nerapa, the wait).  Party: TERRA (RAMUH: Bolt -- Atma and Nerapa are
-- bolt-weak; Nerapa ABSORBS fire, and the driver's absorb guard keeps
-- Fire2 off him), LOCKE, EDGAR, SHADOW.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

-- Q's contract, registered here until the lib's table takes it (see
-- gen_fc_alcove.lua); this gen consumes it as its entry contract.
H.contracts["fc-alcove-v1"] = {
  slot = 3,
  field = { map = 358, x = 8, y = 10 },
  switches = {},
  party = {
    size = 4,
    members = { { 0x00, "TERRA" }, { 0x01, "LOCKE" }, { 0x03, "SHADOW" }, { 0x04, "EDGAR" } },
  },
  ram = { { 0x1A69, 0x07, 0x07, "RAMUH+IFRIT+SHIVA magicite still owned" } },
  items = {},
  sram = {},
}

local TERRA = 0x00
local function map() return H.mapId() & 0x3ff end
local function mapIs(m) return map() == m end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function atmaUp() return (H.readByte(0x1EEB) >> 7) & 1 == 1 end      -- $035F
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361
local function shadowSaved() return (H.readByte(0x1EEF) >> 5) & 1 == 1 end -- $037D

local LOCKE = 0x01
local EDGAR = 0x04            -- Shiva's bearer on the escape (the summon table)
-- Bolt is Atma's and Nerapa's row (with slash + pierce: LOCKE's blades,
-- EDGAR's default crossbow); Nerapa ABSORBS fire, and the driver's absorb
-- guard keeps TERRA's Fire2 off him.  Party-wide Bolt as attack magic.
local FIGHT = { tactical = true, boost = true, bank = 2, items = true,
                healPercent = 60, magic = { [TERRA] = { spell = 2 }, [LOCKE] = { spell = 2 } },
                nuke = { 2 } }
local FA = H.newFightDriver("fc", FIGHT)
-- The escape runs under the 6:00 master clock (21600 frames; the run that
-- measured it had 16752 left at first control and met four randoms of
-- ~3000 frames each on the way to Nerapa -- the clock expired before he
-- was even engaged).  A person on that countdown RUNS from what the game
-- lets them run from and fights the rest flat out: the engine's own L+R
-- (a refusal is detected within 60 frames; the cap is short), no BP
-- banking, physical damage only on the walks (a 12-frame cadence was
-- tried and it breaks the magic-list steer -- Bolt plans oscillated and
-- were dropped 32 times in one unrunnable fight, which is what actually
-- burned the clock; the 30-frame cadence steers Bolt fine).  This is the
-- one place the run mechanic is the honest play; the no-flee directive
-- is about not skipping the leveling the story asks for.
-- Nerapa (2800 HP, 5 pips, weak ice|bolt|holy + slash|pierce, absorbs fire,
-- Condemned on the whole party at the open): a damage race of about two
-- rounds.  The party's divines are both his weaknesses -- TERRA's Ramuh
-- (bolt) and EDGAR's Shiva (ice); LOCKE's Ifrit is fire and the driver's
-- absorb guard keeps it holstered -- and the crossbow pierces.  The first
-- cuts arrived at three-quarters HP with no Potions and revived each
-- other under Condemned until the wipe.
-- opts.summon = { [charId] = { mp = cost } }: Shiva's Diamond Dust is 27
-- MP (battle_magicite measures it); Ramuh's divine is listed at 30 as a
-- conservative affordability check (TERRA carries 228).
local FIGHT_ESCAPE = { tactical = true, boost = true, bank = 0, items = true,
                       healPercent = 40, nuke = { 2 },
                       summon = { [TERRA] = { mp = 30 }, [EDGAR] = { mp = 27 } } }
local FE = H.newFightDriver("escape", FIGHT_ESCAPE)
local ESCAPE_WALK = { playBattles = "mustflee", fleeCap = 600, bank = 0,
                      healPercent = 60, care = false }
-- Timer data (field-ram.txt:684-692): 4 records of 6 bytes at $1188 --
-- byte 0 flags "pfrm----" (p = pauses in menu and battle), +1 the frame
-- counter (word), +3 the event pointer.  Timer 0 is the master clock
-- (counts DOWN from 21600), timer 2 Shadow's arrival.
local function clock(tag)
  return H.call(function()
    local f0, c0 = H.readByte(0x1188), H.readWord(0x1189)
    local f2, c2 = H.readByte(0x1188 + 12), H.readWord(0x1189 + 12)
    H.log(string.format("[escape clock] %s: master=%d frames (%d:%02d) flags=%02X%s | shadow=%d flags=%02X | at (%d,%d) f%d",
      tag, c0, c0 // 3600, (c0 % 3600) // 60, f0, (f0 & 0x80) ~= 0 and " (pauses in menu/battle)" or " (runs in menu/battle)",
      c2, f2, H.fieldX(), H.fieldY(), H.frame))
  end)
end

-- ride a stretch: fights with the driver, dialogs A-tapped, choice boxes
-- steered to `row` (a function of the choice count), until pred()
local function absorb(pred, cap, tag, row, driver)
  local t = 0
  driver = driver or FA
  return H.driveUntil(function()
    t = t + 1
    if (H.gameOverFired or 0) > 0 then
      error(string.format("%s: the party was LOST (game over) -- a lab, not a retry", tag), 0)
    end
    return t >= cap or pred()
  end, cap + 500, {
    H.call(function()
      if t % 2400 == 0 then
        H.log(string.format("  [%s] t=%d map=%d (%d,%d) dlg=%s ctrl=%s", tag, t,
          map(), H.fieldX(), H.fieldY(), tostring(H.dialogWaiting()), tostring(H.hasControl())))
      end
      if H.battleLoadStarted() or H.battleActive() then driver.frame(); return end
      local mx = H.readByte(0x056F)
      if mx > 0 then
        local want, sel, ph = (row and row(mx) or (mx - 1)), H.readByte(0x056E), t % 24
        if sel < want then H.setPad(ph < 3 and { down = true } or {})
        elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
        else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
        return
      end
      if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {})
      else H.setPad({}) end
    end),
  }, tag)
end

-- the clean talk gesture: tap `face` to turn, release, tap A while
-- stationary; retried on a cadence until a battle loads
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

H.run({ maxFrames = 400000 }, {
  -- ---- 0. cold Continue of Q -----------------------------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return mapIs(358) and H.hasControl() end, 3000,
    "cold Continue to the alcove (358)", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("fc-alcove-v1")
    H.assertEq(sw(0x01B5), 1, "$01B5 set: the (70,29) return prompt is dead (its event self-gates on it)")
    H.log(string.format("[escape] Q at 358 (%d,%d); atma=%s nerapa=%s",
      H.fieldX(), H.fieldY(), tostring(atmaUp()), tostring(nerapaUp())))
  end),
  H.fieldCare({ tag = "top-up at the alcove", threshold = 0.95 }),

  -- ---- 1. out onto 394 and up to AtmaWeapon's doorstep ---------------------
  -- the alcove's exit puts the party back on 394 beside the (90,43) reveal;
  -- the stairs revealed on the descent stay revealed (event bits), so the
  -- BFS walker climbs to the doorstep directly, avoiding the statue
  -- trigger (60,11) that only the post-Atma leg may step.
  -- the exit trigger is 358 (8,8), NORTH of the SavePoint (8,10)
  -- (event_trigger.asm:1753-1754: the party arrives at (8,7), walks down
  -- past it to save); the first cut held DOWN and never left
  H.navTo(8, 9, { maxFrames = 3000, playBattles = "tactical", healer = TERRA }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return mapIs(394) end, 1800, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "alcove (8,9) -> up through (8,8) -> 394")
  end)(),
  H.call(function()
    H.assertEq(mapIs(394), true, "back on the continent (394)")
    H.log(string.format("[escape] on 394 at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  -- The reveals do NOT persist across a map load (measured, probe_fc_exit.lua
  -- on the R seed: (89,25) reads F7 until (82,30) is stepped again; the
  -- reveal event then takes control for a moment and the tiles change).
  -- So the approach is hop by hop: step a reveal, let its event settle,
  -- then walk what it opened.  The plateau (x56-64, y3-25) is entered only
  -- by the (63,28) reveal's ladder (63,25-27).  (70,29) -- the "return?"
  -- prompt whose Yes branch would be Shadow's scripted removal -- is DEAD
  -- on this seed: its event self-gates on $01B5, which the alcove's own
  -- entry (90,43) set (event_trigger.asm:1962); the link from the tunnel's
  -- (70,25) landing to (63,28) runs through it, so it is walked, not
  -- avoided (the boot log below records the switch).
  H.waitUntil(function() return H.hasControl() and H.tileAligned() and bright() >= 15 end, 900, "control back on 394", 10),
  H.waitFrames(30),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] on 394 at (%d,%d) $b2=%02X: (82,30) %s (89,25) %s (63,28) %s",
      H.fieldX(), H.fieldY(), H.readByte(0x00b2), v(82, 30), v(89, 25), v(63, 28)))
  end),
  H.navTo(82, 30, { maxFrames = 20000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    arrive = function() return H.fieldX() == 82 and H.fieldY() == 30 end }),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 1800, "the (82,30) reveal settles", 10),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the (82,30) reveal: (89,25) %s", v(89, 25)))
  end),
  H.navTo(89, 25, { maxFrames = 20000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    arrive = function() return H.fieldX() < 80 or (H.fieldX() == 89 and H.fieldY() == 25) end }),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return H.hasControl() and H.tileAligned() and H.fieldX() < 80 end, 3000, {
      H.call(function()
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        H.setPad({})
      end),
    }, "the (89,25) tunnel lands west")
  end)(),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the tunnel at (%d,%d): (63,28) %s (63,33) %s (60,16) %s", H.fieldX(), H.fieldY(), v(63, 28), v(63, 33), v(60, 16)))
  end),
  H.navTo(63, 28, { maxFrames = 40000, playBattles = "tactical", healer = TERRA, magic = FIGHT.magic,
    nuke = FIGHT.nuke, bank = FIGHT.bank, items = true, healPercent = FIGHT.healPercent,
    avoid = { { 60, 11 } }, arrive = function() return H.fieldX() == 63 and H.fieldY() == 28 end }),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 1800, "the (63,28) reveal settles", 10),
  H.waitFrames(60),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] after the (63,28) reveal at (%d,%d): (63,25) %s (60,16) %s (60,14) %s", H.fieldX(), H.fieldY(), v(63, 25), v(60, 16), v(60, 14)))
  end),
  -- the ladder (63,27..25): climb by holding UP (ladder tiles "always face
  -- up"); the BFS's verdict on (63,25) above says whether it could path it
  (function()
    local t = 0
    return H.driveUntil(function()
      t = t + 1
      return H.hasControl() and H.fieldX() == 63 and H.fieldY() <= 25
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "climb the (63,25-27) ladder onto the plateau")
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    local function v(x, y) return H.bfsPath(x, y) and "path" or "no path" end
    H.log(string.format("[escape] on the plateau at (%d,%d): (60,16) %s, (60,14) %s", H.fieldX(), H.fieldY(), v(60, 16), v(60, 14)))
  end),
  -- the doorstep: (60,16) below the NPC at (60,15) (face UP), else (60,14)
  -- above it (face DOWN); (60,11) is the POST-Atma statue trigger, avoided
  H.cond(function() return H.bfsPath(60, 16, nil, nil) ~= nil end, {
    H.navTo(60, 16, { maxFrames = 40000, playBattles = "tactical", magic = FIGHT.magic,
      bank = FIGHT.bank, healPercent = FIGHT.healPercent, avoid = { { 60, 11 } },
      arrive = function() return H.fieldX() == 60 and H.fieldY() == 16 end }),
  }, {
    H.navTo(60, 14, { maxFrames = 40000, playBattles = "tactical", magic = FIGHT.magic,
      bank = FIGHT.bank, healPercent = FIGHT.healPercent, avoid = { { 60, 11 } },
      arrive = function() return H.fieldX() == 60 and H.fieldY() == 14 end }),
  }),
  H.fieldCare({ tag = "before AtmaWeapon", threshold = 0.95 }),
  H.call(function()
    H.assertEq(atmaUp(), true, "$035F set -- AtmaWeapon stands at (60,15)")
    H.screenshot("atma_doorstep")
  end),

  -- ---- 2. AtmaWeapon --------------------------------------------------------
  (function()
    return H.cond(function() return H.fieldY() == 16 end,
      { talk("up", 4000, "AtmaWeapon engaged (from the south)") },
      { talk("down", 4000, "AtmaWeapon engaged (from the north)") })
  end)(),
  absorb(function()
    return not atmaUp() and not H.battleActive() and not H.battleLoadStarted()
  end, 60000, "AtmaWeapon falls ($035F clears)"),
  H.call(function()
    H.assertEq(atmaUp(), false, "$035F cleared -- AtmaWeapon defeated")
    H.log(string.format("[escape] post-Atma at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("atma_down")
  end),
  -- The win hands straight into a scripted stretch (Shadow's departure
  -- _cad9fc, then the statue scene); ride it -- dialogs A-tapped, any
  -- battle fought -- until the field hands control back, and only then
  -- heal (a scene that never does is exempt: the care is conditional).
  absorb(function() return H.hasControl() and not H.dialogWaiting() end, 6000,
    "post-Atma: the field hands control back"),
  H.cond(function() return H.hasControl() and not H.dialogWaiting() end, {
    H.fieldCare({ tag = "post-atma", threshold = 0.95 }),
    -- TERRA's Blizzard ($0E) is ICE, and the escape map's pool has an
    -- ice-absorber (species $0169: the lib's absorb guard failed the first
    -- run at its first 393 encounter).  The spare MithrilBlade ($0A,
    -- non-elemental) is hers for the escape; her Fight is not her damage.
    H.equipKit(TERRA, { { 0, 0x0A } }, { tag = "TERRA: MithrilBlade for the escape" }),
  }, {
    H.logStep(function() return "[escape] post-Atma: no field control (scripted); care skipped" end),
  }),
  H.release(),
  H.waitFrames(30),

  -- ---- 3. the statue spine onto (60,11) -> map 393 --------------------------
  (function()
    local wps = { { 60, 14 }, { 60, 12 }, { 60, 11 } }
    local wi, t, wt, lastK, lastT = 1, 0, 0, -1, 0
    return H.driveUntil(function() t = t + 1; return mapIs(393) end, 60000, {
      H.call(function()
        local mx = H.readByte(0x056F)
        if mx > 0 then H.setPad(t % 24 < 3 and { "a" } or {}); return end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        if not H.hasControl() then H.setPad({}); return end
        local wp = wps[wi]
        if not wp then H.setPad({}); return end
        local dx, dy = wp[1] - H.fieldX(), wp[2] - H.fieldY()
        wt = wt + 1
        if (dx == 0 and dy == 0) or wt > 700 then wi, wt = wi + 1, 0; H.setPad({}); return end
        local px = dx > 0 and "right" or "left"
        local py = dy > 0 and "down" or "up"
        local k = H.fieldX() * 256 + H.fieldY()
        if k ~= lastK then lastK, lastT = k, t end
        if t - lastT > 240 then
          -- the y12-14 stairs are prop-3 tiles that only move on diagonal input
          local alts = dy ~= 0
            and { { [py] = true, left = true }, { [py] = true, right = true },
                  { [py] = true }, { left = true }, { right = true } }
            or { { [px] = true, up = true }, { [px] = true, down = true },
                  { [px] = true }, { up = true }, { down = true } }
          H.setPad(alts[(math.floor(t / 36) % #alts) + 1])
          return
        end
        H.setPad(math.abs(dx) >= math.abs(dy) and { [px] = true } or { [py] = true })
      end),
    }, "statue scene -> map 393")
  end)(),
  (function()
    local calm = 0
    return H.driveUntil(function()
      if H.hasControl() and not H.dialogWaiting() then calm = calm + 1 else calm = 0 end
      return calm >= 30
    end, 20000, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "escape start settled")
  end)(),
  H.call(function()
    H.assertEq(mapIs(393), true, "on the escape map (393)")
    H.log(string.format("[escape] clocks running: t0=%d t2=%d at (%d,%d)",
      H.readWord(0x1188), H.readWord(0x118C), H.fieldX(), H.fieldY()))
    H.screenshot("escape_start")
  end),

  -- ---- 4. Nerapa, the ledge, the wait ---------------------------------------
  clock("out of the statue scene"),
  H.navTo(106, 15, { maxFrames = 20000, playBattles = ESCAPE_WALK.playBattles, fleeCap = ESCAPE_WALK.fleeCap,
    bank = ESCAPE_WALK.bank, healPercent = ESCAPE_WALK.healPercent, care = false }),
  clock("at Nerapa's doorstep"),
  -- (no doorstep care: the field care refuses under a live event timer,
  -- rightly -- the clock runs in menus -- so healing is the fight's own,
  -- in battle)
  H.release(),
  H.waitFrames(30),
  talk("right", 4000, "Nerapa engaged"),
  absorb(function()
    return not nerapaUp() and not H.battleActive() and not H.battleLoadStarted()
  end, 30000, "Nerapa falls ($0361 clears)", nil, FE),
  H.call(function()
    H.assertEq(nerapaUp(), false, "Nerapa defeated")
    H.log(string.format("[escape] post-Nerapa: (%d,%d) t0=%d", H.fieldX(), H.fieldY(), H.readWord(0x1188)))
  end),
  clock("post-Nerapa"),
  H.navTo(112, 15, { maxFrames = 8000, playBattles = ESCAPE_WALK.playBattles, fleeCap = ESCAPE_WALK.fleeCap,
    bank = ESCAPE_WALK.bank, care = false }),
  (function()
    local near = false
    return H.navTo(115, 17, { maxFrames = 8000, playBattles = ESCAPE_WALK.playBattles, fleeCap = ESCAPE_WALK.fleeCap,
      bank = ESCAPE_WALK.bank, care = false,
      arrive = function()
        if H.fieldX() == 115 and H.fieldY() == 17 then near = true end
        return near
      end })
  end)(),
  (function()
    local t = 0
    return H.driveUntil(function() t = t + 1; return t >= 26000 or shadowSaved() end, 26500, {
      H.call(function()
        if t % 2400 == 0 then
          H.log(string.format("  [wait] t=%d map=%d (%d,%d) dlg=%s t0=%d t2=%d", t,
            map(), H.fieldX(), H.fieldY(), tostring(H.dialogWaiting()),
            H.readWord(0x1188), H.readWord(0x118C)))
        end
        if H.battleLoadStarted() or H.battleActive() then FE.frame(); return end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local want, sel, ph = mx - 1, H.readByte(0x056E), t % 24
          if sel < want then H.setPad(ph < 3 and { down = true } or {})
          elseif sel > want then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if x == 115 and y == 17 then H.setPad({}); return end
        local ph = t % 24
        if ph >= 3 then H.setPad({}); return end
        if x < 115 then H.setPad({ right = true })
        elseif x > 115 then H.setPad({ left = true })
        elseif y < 17 then H.setPad({ down = true })
        else H.setPad({ up = true }) end
      end),
    }, "the humane wait ($037D)")
  end)(),
  H.call(function()
    H.assertEq(shadowSaved(), true, "$037D set -- Shadow saved")
  end),

  -- ---- 5. the exit flow and the landing ---------------------------------------
  -- the landing: control never came back at the bedside on the first
  -- clean run (ctrl=false for 14400+ frames at (99,38), no dialog up), so
  -- the wait logs every control component while on 397 and keeps a
  -- savestate of the first island frame for a probe
  (function()
    local t, saved = 0, false
    return H.driveUntil(function()
      t = t + 1
      if (H.gameOverFired or 0) > 0 then error("the landing was LOST (game over)", 0) end
      return t >= 60000 or (mapIs(397) and H.hasControl() and not H.dialogWaiting())
    end, 60500, {
      H.call(function()
        if mapIs(397) and not saved then saved = true; H.saveState("wor_probe.mss"); H.log("[escape] first island frame saved as wor_probe.mss") end
        if mapIs(397) and t % 1200 == 0 then
          local pobj = H.readWord(0x0803)
          H.log(string.format("[landing] t=%d (%d,%d) $1eb9=%02X $0084=%02X $0059=%02X pobj=%04X mvtype=%02X event=%s battle=%s dlg=%s ctrl=%s $ba=%02X $d3=%02X evpc=%02X%02X%02X",
            t, H.fieldX(), H.fieldY(), H.readByte(0x1eb9), H.readByte(0x0084), H.readByte(0x0059), pobj,
            H.readByte(0x087c + pobj) & 0x0F, tostring(H.eventRunning()), tostring(H.battleLoadStarted()),
            tostring(H.dialogWaiting()), tostring(H.hasControl()), H.readByte(0x00ba), H.readByte(0x00d3),
            H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5)))
        end
        if H.battleLoadStarted() or H.battleActive() then FA.frame(); return end
        local mx = H.readByte(0x056F)
        if mx > 0 then
          local sel, ph = H.readByte(0x056E), t % 24
          if sel > 0 then H.setPad(ph < 3 and { up = true } or {})
          else H.setPad((ph >= 12 and ph < 15) and { "a" } or {}) end
          return
        end
        if H.dialogWaiting() then H.setPad(t % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "the airship flees, the RUIN cutscene, the Solitary Island (397)")
  end)(),
  (function()
    local calm = 0
    return H.driveUntil(function()
      if H.hasControl() and not H.dialogWaiting() and mapIs(397) then calm = calm + 1 else calm = 0 end
      return calm >= 60
    end, 20000, {
      H.call(function()
        if H.dialogWaiting() then H.setPad(H.frame % 16 < 4 and { "a" } or {}) else H.setPad({}) end
      end),
    }, "landing settled")
  end)(),
  H.call(function()
    local hp = {}
    for _, c in ipairs(H.partyMembers()) do hp[#hp + 1] = tostring(H.charHp(c)) end
    H.log(string.format("landing: map=%d (%d,%d) party=%d hp=%s $00A4=%d $037D=%d",
      map(), H.fieldX(), H.fieldY(), #H.partyMembers(), table.concat(hp, "/"),
      (H.readByte(0x1E94) >> 4) & 1, (H.readByte(0x1EEF) >> 5) & 1))
    -- route doc s6: the WoR opening lands solo CELES at the Solitary
    -- Island bedside, map 397 {100,38}, WoR flag $00A4=1, after Cid's
    -- fish request hands control back -- the World of Balance's stop line
    H.assertEq(mapIs(397), true, "solo Celes at the Solitary Island bedside (map 397)")
    H.assertEq((H.readByte(0x1E94) >> 4) & 1, 1, "$00A4 set -- the World of Ruin")
    H.assertEq(#H.partyMembers(), 1, "the party is Celes alone")
    H.screenshot("wor_landing")
  end),
  H.saveState("wor_landing.mss"),
  H.logStep(function() return "wor_landing generated: the World of Balance is played through" end),
})
