-- probe_objsweep.lua -- which battle OBJ tiles are genuinely unused?
--
-- Written because the boost-mark tiles were picked by exactly the check
-- that CANNOT see this bug: ot6.asm:2032-2036 claims tiles 200/202/204
-- were "verified blank + unreferenced by any oam entry ... idle and
-- through attack effects".  Blankness and OAM references are both
-- SNAPSHOT properties.  Vanilla's damage numerals pick their vram
-- destination at run time from a rotating counter (GfxCmd_0b,
-- btlgfx_main.asm:24697), so unless a numeral happened to fire on
-- counter phase 2 or 3 while the probe looked, the tiles read blank and
-- unreferenced -- and they are neither.  probe_objarrow.lua measures the
-- consequence directly.
--
-- So this probe tracks CHANGE, not content: every tile's bytes are
-- fingerprinted periodically and any tile whose bytes ever move is
-- marked used, plus any tile any OAM entry ever names (16x16 sprites
-- claim tile, +1, +16, +17).  A tile is a candidate only if it never
-- moved AND was never referenced AND is blank.
--
-- OBJ chr base is word $2000 (obsel $61), 4bpp, 32 bytes/tile: tile n
-- lives at vram word $2000 + n*$10, i.e. byte $4000 + n*$20.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")

local STATE = ARG_STATE or
  "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local NT = 512                      -- tiles reachable at obj base $2000
local fp, moved, refd, nonblank = {}, {}, {}, {}
local frames, samples = 0, 0

local function tileByte(t, i)
  return emu.read(0x4000 + t*32 + i, emu.memType.snesVideoRam)
end

local function fingerprint(t)
  local s = 0
  for i = 0, 31, 4 do s = (s * 31 + tileByte(t, i)) & 0xffffff end
  return s
end

local function sweep()
  samples = samples + 1
  for t = 0, NT-1 do
    local f = fingerprint(t)
    if fp[t] ~= nil and fp[t] ~= f then moved[t] = true end
    fp[t] = f
    if f ~= 0 then nonblank[t] = true end
  end
end

-- OAM: 128 entries of 4 bytes at $0300 (shadow), tile in byte 2 plus the
-- name bit in byte 3.  Sprite size comes from the high table at $0420,
-- 2 bits/sprite; obsel $61 = sizes 16x16 / 32x32, so EVERY battle sprite
-- claims at least a 2x2 tile quad.
local function oamSweep()
  for e = 0, 127 do
    local o = 0x0300 + e*4
    local y = H.readByte(o+1)
    if y < 0xe0 then                       -- parked sprites sit at y=$e0
      local tile = H.readByte(o+2) + ((H.readByte(o+3) & 0x01) << 8)
      local hi = H.readByte(0x0420 + (e >> 2))
      local big = (hi >> ((e & 3) * 2 + 1)) & 1
      local span = big and 4 or 2          -- 32x32 vs 16x16, in tiles
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
  H.waitFrames(150),
  H.call(function()
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
      H.writeByte(0x3e9c + s*2, 3)
    end
    sweep()
  end),
  H.driveUntil(function()
    frames = frames + 1
    oamSweep()
    if frames % 8 == 0 then sweep() end
    return frames >= 2600
  end, 30000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then
        if (frames // 111) % 3 == 0 then H.setPad({ "r" }) else H.setPad({ "a" }) end
      else H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(12),
  }, "obj sweep"),
  H.call(function()
    H.log(string.format("frames %d, sweeps %d", frames, samples))
    local free, runs = {}, {}
    for t = 0, NT-1 do
      if not moved[t] and not refd[t] and not nonblank[t] then free[#free+1] = t end
    end
    -- compress to runs for readability
    local i = 1
    while i <= #free do
      local s = free[i]; local e = s
      while i < #free and free[i+1] == e + 1 do i = i + 1; e = free[i] end
      runs[#runs+1] = (s == e) and string.format("%d", s)
                                or string.format("%d-%d", s, e)
      i = i + 1
    end
    H.log("never-moved, never-referenced, blank tiles: " .. table.concat(runs, ", "))
    -- explicit report on the tiles OT6 currently claims and their block
    local function say(t)
      return string.format("tile %d: moved=%s refd=%s nonblank=%s", t,
        tostring(moved[t] or false), tostring(refd[t] or false),
        tostring(nonblank[t] or false))
    end
    for _, t in ipairs({ 200,201,202,203,204,205,216,217,218,219,220,221 }) do
      H.log("OT6 CURRENT " .. say(t))
    end
    H.assertEq(samples > 10, true, "positive control: sweeps actually ran")
  end),
})
