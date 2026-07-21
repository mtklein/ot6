-- probe_objtail.lua -- is there slack at the tail of the battle OBJ
-- region ($2E00-$3000, tiles 224-255)?
--
-- Narrowed to here by two earlier probes plus the vram map in
-- ff6/notes/battle-ram.txt:2206:
--   $2C00 damage numerals / $2CC0 "miss"  -- rewritten constantly (this
--         is where OT6's chevrons wrongly live; probe_objarrow proves it)
--   $2E00 hand pointer / $2E20 up-down page / $2E60 reflect /
--         $2EA0 shield  -- ONE $400-byte transfer at init
--         (btlgfx_main.asm:2347), never touched again
--         (probe_objsentinel: tiles 224-255 all survive a full battle)
--   $3000 monster graphics -- TfrMonsterGfx blankets $2000 bytes every
--         battle (btlgfx_main.asm:5410), so its apparent slack is just
--         this formation's art being small.  Not ours to take.
--
-- The label "$2EA0 shield graphics" runs to the next known address, so
-- some of that 22-tile span is probably padding rather than art.  A tile
-- is safe for OT6 if it is BLANK after init (nothing draws it) AND no
-- OAM entry ever names it.  Blankness is read after init rather than
-- guessed, and the OAM sweep runs the whole battle.
--
-- Caveat recorded rather than papered over: reflect and shield art are
-- referenced only when those statuses are actually on screen, which a
-- generic battle does not exercise -- so "never referenced here" is
-- weaker than "never referenced".  Blankness is the load-bearing signal;
-- a blank tile has no art to lose no matter who names it.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local LO, HI = 224, 255
local blank, refd = {}, {}
local frames = 0

local function scanBlank()
  local vr = emu.memType.snesVideoRam
  for t = LO, HI do
    local z = true
    for i = 0, 31 do
      if emu.read(0x4000 + t*32 + i, vr) ~= 0 then z = false; break end
    end
    blank[t] = z
  end
end

local function oamSweep()
  for e = 0, 127 do
    local o = 0x0300 + e*4
    if H.readByte(o+1) < 0xe0 then
      local tile = H.readByte(o+2) + ((H.readByte(o+3) & 0x01) << 8)
      local hi = H.readByte(0x0420 + (e >> 2))
      local big = (hi >> ((e & 3) * 2 + 1)) & 1
      local span = big and 4 or 2
      for dy = 0, span-1 do
        for dx = 0, span-1 do
          refd[(tile + dy*16 + dx) & 0x1ff] = true
        end
      end
    end
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(200),
  H.call(function()
    scanBlank()
    local n = 0
    for t = LO, HI do if blank[t] then n = n + 1 end end
    H.log(string.format("blank tiles in %d-%d after init: %d", LO, HI, n))
    H.assertEq(n < (HI-LO+1), true,
      "positive control: the region holds real art, so we are reading it")
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
      H.writeByte(0x3e9c + s*2, 3)
    end
  end),
  H.driveUntil(function()
    frames = frames + 1
    oamSweep()
    return frames >= 2600
  end, 30000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then
        if (frames // 97) % 3 == 0 then H.setPad({ "r" }) else H.setPad({ "a" }) end
      else H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(12),
  }, "oam references sampled"),
  H.call(function()
    local rows = {}
    for t = LO, HI do
      rows[#rows+1] = string.format("%d:%s%s", t,
        blank[t] and "blank" or "ART", refd[t] and "/REFD" or "")
    end
    H.log("tile map: " .. table.concat(rows, " "))
    local good = {}
    for t = LO, HI do
      if blank[t] and not refd[t] then good[#good+1] = t end
    end
    H.log("blank + never-referenced: " .. table.concat(good, ", "))
    local quads = {}
    for _, t in ipairs(good) do
      if blank[t] and blank[t+1] and blank[t+16] and blank[t+17]
         and not refd[t] and not refd[t+1] and not refd[t+16] and not refd[t+17]
         and (t % 16) < 15 and (t+17) <= HI then
        quads[#quads+1] = t
      end
    end
    H.log("safe 16x16 quad origins in the tail: " .. table.concat(quads, ", "))
  end),
})
