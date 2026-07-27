-- @suite
-- Regression for #24.  M.battleLoadStarted() is the harness's "is a battle
-- up?" gate, and worldHasControl()/worldNavTo both hang off it.  It used to
-- read ONLY party slot 0 and reject a 0, which conflates three states:
--
--   * battle module not loaded   -- all four words read $FFFF
--   * party slot 0 is EMPTY      -- that word reads 0000
--   * slot 0's character is DEAD -- that word reads 0000
--
-- Measured on battle_doorstep: field = FFFF FFFF FFFF FFFF, live battle =
-- 003F 0044 003D 0000 (slot 3 empty).  So a dead or absent first character
-- made the gate say "no battle" while the battle was still running -- and
-- worldNavTo then stopped tapping A and pressed directions into it forever.
--
-- This test drives a real battle and then forces the table into each shape.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/project-setup-dependencies-4933ac/tools/tests/lib/ot6.lua")
local STATE = "battle_doorstep.mss.lua"
local HP = 0x3BF4

local function tbl()
  local w = {}
  for i = 0, 3 do w[#w+1] = string.format("%04X", H.readWord(HP + i*2)) end
  return table.concat(w, " ")
end
local function setTbl(a, b, c, d)
  local v = { a, b, c, d }
  for i = 0, 3 do H.writeWord(HP + i*2, v[i+1]) end
end

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  -- 1. field: nothing loaded
  H.call(function()
    H.assertEq(tbl(), "FFFF FFFF FFFF FFFF", "field: table is all $FFFF")
    H.assertEq(H.battleLoadStarted(), false, "field: gate is closed")
  end),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    -- 2. live battle, healthy party
    H.assertEq(H.battleLoadStarted(), true, "live battle: gate is open")
    local saved = { H.readWord(HP), H.readWord(HP+2), H.readWord(HP+4), H.readWord(HP+6) }
    H.log("[ot6] live table: " .. tbl())

    -- 3. slot 0 dead.  THE REGRESSION: the old gate returned false here.
    setTbl(0x0000, saved[2], saved[3], saved[4])
    H.assertEq(H.battleLoadStarted(), true,
      "slot 0 at 0 HP (dead/empty) is still a live battle")

    -- 4. whole party down -- a game-over screen is still the battle module
    setTbl(0x0000, 0x0000, 0x0000, 0x0000)
    H.assertEq(H.battleLoadStarted(), true,
      "party wiped is still a live battle")

    -- 5. POSITIVE CONTROL: the gate must still be able to say NO.  Without
    --    this the test would pass against a gate hardcoded to true.
    setTbl(0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF)
    H.assertEq(H.battleLoadStarted(), false,
      "control: an all-$FFFF table still reads as no battle")

    -- restore so nothing downstream inherits a mangled table
    setTbl(saved[1], saved[2], saved[3], saved[4])
    H.assertEq(H.battleLoadStarted(), true, "restored: gate is open again")
  end),
  H.logStep("battle load gate verified"),
})
