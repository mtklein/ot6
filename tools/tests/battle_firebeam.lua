-- battle_firebeam.lua -- enter the first guard battle FRESH (no mid-battle
-- savestate load) and fire the first MagiTek command (Fire Beam) at a guard.
--
--   tools/tests/run.sh tools/tests/battle_firebeam.lua
--
-- Loads build/states/battle_doorstep.mss (a FIELD state), walks north into
-- the scripted guard battle, waits for the battle to come up, then presses
-- A (command: MagiTek) / A (Fire Beam) / A (confirm target) and watches the
-- action resolve.  Screenshots before/during/after plus break-system RAM:
--   $7E3E44/$7E3E46  guard shield current (monster slots 2/3)
--   $7E3C00/$7E3C02  guard HP words
--   $7E3E95/$7E3E97  revealed masks
--
-- This doubles as the key input experiment: driving the battle with buttons
-- when NO savestate was loaded mid-battle (the doorstep load happens in the
-- field, long before battle init).
--
-- Exit codes: 0 = battle came up, input drove the menus, and the action
-- visibly resolved; 1 = any stage failed (each is asserted loudly).

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function ramReport(tag)
  return H.call(function()
    H.log(string.format("%s shields[$3E44,$3E46]=%02X,%02X hp[$3C00,$3C02]=%04X,%04X " ..
        "revealed[$3E95,$3E97]=%02X,%02X",
      tag, H.readByte(0x3E44), H.readByte(0x3E46),
      H.readWord(0x3C00), H.readWord(0x3C02),
      H.readByte(0x3E95), H.readByte(0x3E97)))
  end)
end

local shots = {}
local function snap(name)
  return H.call(function()
    local ok, png = pcall(emu.takeScreenshot)
    assert(ok and type(png) == "string" and #png > 0, "screenshot failed at " .. name)
    shots[name] = png
    H.log(string.format("shot %s: %d bytes", name, #png))
    H.emitBlob("fb_" .. name .. ".png", png)
  end)
end

local hpBefore = {}

H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- 1. Walk into the battle fresh (field input post-load).
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  ramReport("load+0"),

  -- 2. Battle must actually come up (this is where broken builds die).
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle to become active (screen rendering)", 30),
  -- let the ATB fill and the first command menu open
  H.waitFrames(240),
  ramReport("menu"),
  snap("menu"),

  -- 3. A: confirm MagiTek command -> submenu.
  H.pressButtons({ "a" }, 6),
  H.waitFrames(24),
  snap("submenu"),
  H.call(function()
    H.assertEq(shots.menu ~= shots.submenu, true,
      "A #1 changed the screen (MagiTek submenu opened)")
    hpBefore[1] = H.readWord(0x3C00)
    hpBefore[2] = H.readWord(0x3C02)
  end),

  -- 4. A: pick Fire Beam (cursor starts on it) -> target cursor.
  H.pressButtons({ "a" }, 6),
  H.waitFrames(24),
  snap("target"),
  H.call(function()
    H.assertEq(shots.submenu ~= shots.target, true,
      "A #2 changed the screen (target cursor up)")
  end),

  -- 5. A: confirm target -> beam fires.
  H.pressButtons({ "a" }, 6),
  H.waitFrames(40),
  snap("firing"),
  ramReport("firing"),
  H.waitFrames(260),
  snap("after"),
  ramReport("after"),

  -- 6. The action must have visibly resolved: a guard's HP dropped and/or
  --    its shield ticked down (Fire Beam is one of the break weaknesses).
  H.call(function()
    local hp1, hp2 = H.readWord(0x3C00), H.readWord(0x3C02)
    local delta = (hpBefore[1] - hp1) + (hpBefore[2] - hp2)
    H.log(string.format("guard hp before=%04X,%04X after=%04X,%04X (total delta %d)",
      hpBefore[1], hpBefore[2], hp1, hp2, delta))
    H.assertEq(shots.firing ~= shots.after, true,
      "screen changed between firing and resolution")
    H.assertEq(delta > 0, true, "Fire Beam dealt damage to a guard")
  end),
})
