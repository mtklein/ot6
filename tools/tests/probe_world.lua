-- probe_world.lua -- the live-probe checklist from
-- docs/research/world-map-nav.md:178-191, run against worldmap_narshe.mss
-- (the party on foot on the WoB, fresh from the Narshe south gate).  This
-- is the measurement instrument behind the worldPos/worldCanStep/worldBfs
-- additions to lib/ot6.lua: every mechanism claim the doc's audit flagged
-- as inferred-not-read gets an empirical answer here, logged with frames
-- and RAM values, before any executor is built on it.
--
-- Answers produced (each tagged [probe] for grepping):
--   1. $1F64 live value on the world + the working mode mask
--   2. position bytes: tile $E0/$E2, fraction $DF/$E1, saved $1F60/$1F61,
--      facing $F6/$1F68; per-frame trace of one full step (latch timing,
--      tile-flip skew, what a 4-frame tap does after release)
--   3. WorldTileProp bit4 vs reality: predict passability of the four
--      neighbors from ROM ($EE9B14 + world*512 + tile*2), then try to
--      step each way and compare
--   4. random-encounter aftermath: walk until one fires, kill-bit it,
--      measure the reload (position/facing survival, frames to control,
--      $E8 flags)
--   5. misc flags: $20 world type, $11FA vehicle, $11F3, $E7/$E8/$E9
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/worldmap_narshe.mss.lua"

local function P(fmt, ...) print("[probe] " .. string.format(fmt, ...)) end

-- raw world position reads (zero page; world module keeps DP=$0000 --
-- world_start.asm has no phd/pld, and the menu path reads $e0 plain)
local function wx() return H.readByte(0x00e0) end
local function wy() return H.readByte(0x00e2) end
local function wfx() return H.readByte(0x00df) end   -- x fraction
local function wfy() return H.readByte(0x00e1) end   -- y fraction
local function aligned() return wfx() == 0 and wfy() == 0 end

-- WorldTileProp = $EE9B14 (world/tile_prop.asm:4) -> rom file $2E9B14;
-- index = ($1F64 low byte)*512 + tiletype*2 (move.asm GetWorldTileProp)
local PROP = 0x2E9B14
local function tileType(x, y)
  return H.readByte(0x7F0000 + (y & 0xFF) * 256 + (x & 0xFF))
end
local function tileProp(x, y)
  local world = H.readByte(0x1f64) & 0xFF
  return H.readRomWord(PROP + world * 512 + tileType(x, y) * 2)
end

local function dumpFlags(tag)
  P("%s: $1F64=%04X $E0/$E2=(%d,%d) $DF/$E1=(%d,%d) $1F60/61=(%d,%d)",
    tag, H.readWord(0x1f64), wx(), wy(), wfx(), wfy(),
    H.readByte(0x1f60), H.readByte(0x1f61))
  P("%s: $F6=%d $1F68=%02X $20=%02X $11FA=%02X $11F3=%02X $E7=%02X $E8=%02X $E9=%02X $19=%02X",
    tag, H.readByte(0x00f6), H.readByte(0x1f68), H.readByte(0x0020),
    H.readByte(0x11fa), H.readByte(0x11f3), H.readByte(0x00e7),
    H.readByte(0x00e8), H.readByte(0x00e9), H.readByte(0x0019))
end

-- one per-frame trace row
local function traceRow(i)
  P("t%02d E0=%3d E2=%3d DF=%3d E1=%3d E3=%04X E5=%04X",
    i, wx(), wy(), wfx(), wfy(), H.readWord(0x00e3), H.readWord(0x00e5))
end

local trace = { n = 0, active = false }

H.run({ maxFrames = 30000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    dumpFlags("boot")
    P("mode masks: raw=%04X and1FF=%03X and3FF=%03X andFF=%02X",
      H.readWord(0x1f64), H.readWord(0x1f64) & 0x1FF,
      H.readWord(0x1f64) & 0x3FF, H.readWord(0x1f64) & 0xFF)
  end),

  -- ------------------------------------------------------------------ --
  -- 3. passability predictions for the four neighbors, from ROM
  -- ------------------------------------------------------------------ --
  H.call(function()
    local x, y = wx(), wy()
    P("tile (%d,%d) type=%02X prop=%04X", x, y, tileType(x, y), tileProp(x, y))
    local n = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }
    for dir, d in pairs(n) do
      local px, py = x + d[1], y + d[2]
      local prop = tileProp(px, py)
      P("neighbor %-5s (%d,%d) type=%02X prop=%04X pass(bit4=0)=%s battles(bit6)=%s forest(bit5)=%s",
        dir, px, py, tileType(px, py), prop,
        tostring((prop & 0x0010) == 0), tostring((prop & 0x0040) ~= 0),
        tostring((prop & 0x0020) ~= 0))
    end
  end),

  -- ------------------------------------------------------------------ --
  -- 2. step mechanics: tap DOWN for exactly 4 frames, release, and trace
  -- 40 frames.  If movement is latched (move.asm:834-841 gates input on
  -- fraction==0), the step runs to the next boundary on its own; if the
  -- old strand-theory were right, the party would freeze mid-tile.
  -- ------------------------------------------------------------------ --
  H.call(function()
    P("== step-latch trace: 4-frame DOWN tap ==")
    trace.active = true
    trace.n = 0
    emu.addEventCallback(function()
      if trace.active and trace.n < 44 then
        trace.n = trace.n + 1
        traceRow(trace.n)
      end
    end, emu.eventType.startFrame)
  end),
  H.hold({ "down" }), H.waitFrames(4), H.release(),
  H.waitFrames(40),
  H.call(function()
    trace.active = false
    P("after tap: at (%d,%d) frac=(%d,%d) aligned=%s",
      wx(), wy(), wfx(), wfy(), tostring(aligned()))
  end),

  -- an up-step for the flip-skew comparison (down flips late, up should
  -- flip early if the world mirrors the field's pixel>>4 behavior --
  -- here the tile byte IS the high byte of the position word, so moving
  -- up borrows through it on the first frame)
  H.call(function()
    P("== flip-skew trace: held UP step ==")
    trace.active = true
    trace.n = 0
  end),
  H.hold({ "up" }), H.waitFrames(20), H.release(),
  H.waitFrames(20),
  H.call(function()
    trace.active = false
    P("after up-step: at (%d,%d) frac=(%d,%d)", wx(), wy(), wfx(), wfy())
  end),

  -- ------------------------------------------------------------------ --
  -- 4. random encounter: pace east-west over battle-enabled plains until
  -- one fires, kill-bit it, and measure the aftermath frame by frame.
  -- ------------------------------------------------------------------ --
  H.call(function() P("== pacing for a random encounter ==") end),
  H.call(function()
    trace.preBattle = nil
  end),
  H.driveUntil(function()
    if H.battleLoadStarted() and not trace.preBattle then
      trace.preBattle = { x = wx(), y = wy(), f = H.frame,
                          sx = H.readByte(0x1f60), sy = H.readByte(0x1f61),
                          face = H.readByte(0x00f6) }
      P("battle at f%d from (%d,%d) saved=(%d,%d) face=%d danger=$%04X",
        H.frame, trace.preBattle.x, trace.preBattle.y, trace.preBattle.sx,
        trace.preBattle.sy, trace.preBattle.face, H.readWord(0x1f6e))
      local w = H.formationWords()
      P("formation: %04X %04X %04X %04X %04X %04X",
        w[1], w[2], w[3], w[4], w[5], w[6])
    end
    return trace.preBattle ~= nil
  end, 12000, {
    -- 20-frame paced holds; alternate east/west so the probe stays local
    H.hold({ "right" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "left" }), H.waitFrames(24), H.release(), H.waitFrames(4),
  }, "random encounter fires"),

  H.clearBattle(9000),
  H.call(function()
    P("battle cleared at f%d; watching the reload", H.frame)
    dumpFlags("post-battle")
  end),
  H.waitUntil(function()
    return (H.readWord(0x1f64) & 0x3FF) < 3 and aligned()
       and (H.readByte(0x00e8) & 0x10) == 0
  end, 1200, "world reloaded", 5),
  H.call(function()
    dumpFlags("reloaded")
    local pb = trace.preBattle
    P("position survival: pre=(%d,%d) post=(%d,%d) same=%s facing pre=%d post=%d",
      pb.x, pb.y, wx(), wy(), tostring(pb.x == wx() and pb.y == wy()),
      pb.face, H.readByte(0x00f6))
  end),
  -- prove control is back: one deliberate step
  H.call(function() trace.stepFrom = { wx(), wy() } end),
  H.driveUntil(function()
    return wx() ~= trace.stepFrom[1] or wy() ~= trace.stepFrom[2]
  end, 300, { H.hold({ "right" }), H.waitFrames(8) }, "post-reload step"),
  H.release(),
  H.call(function()
    P("post-reload control ok: now at (%d,%d), frame %d", wx(), wy(), H.frame)
    H.screenshot("probe_world_done")
  end),
})
