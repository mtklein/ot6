-- probe_world3.lua -- prototype the world walker end to end: BFS the WoB
-- from the Narshe spawn (84,34) to the Figaro Castle gate trigger (64,76)
-- on the verified 1-bit passability rule, walking with per-step landing
-- verification.  Doubles as the remaining live probes:
--   * does the paced shuttle of probe_world run 1 actually accrue danger
--     (20 logged shuttle cycles first), or was that pacing broken?
--   * the first real encounter en route: formation, the reload the doc
--     claims (fade + re-init), position/facing survival, frames back to
--     control -- the numbers worldNavTo's battle branch needs
--   * whether the whole Narshe->Figaro leg is BFS-walkable, de-risking
--     the gen_figaro route before it is written
-- Stops at the Figaro trigger WITHOUT stepping on it (target one tile
-- short), so the probe never leaves the world map.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/worldmap_narshe.mss.lua"

local function P(fmt, ...) print("[probe] " .. string.format(fmt, ...)) end
local function wx() return H.readByte(0x00e0) end
local function wy() return H.readByte(0x00e2) end
local function wAligned()
  return H.readByte(0x00df) == 0 and H.readByte(0x00e1) == 0
end

-- verified world passability: dest tile prop bit4 clear (probe_world run 1
-- matched predictions to movement).  WorldTileProp $EE9B14 -> rom file
-- $2E9B14; index = worldId*512 + tiletype*2.
local PROP = 0x2E9B14
local propCache = nil
local function worldPass(x, y)
  if not propCache then
    propCache = {}
    local world = H.readWord(0x1f64) & 0xFF
    for t = 0, 255 do
      propCache[t] = H.readRomWord(PROP + world * 512 + t * 2)
    end
  end
  local t = H.readByte(0x7F0000 + (y & 0xFF) * 256 + (x & 0xFF))
  return (propCache[t] & 0x0010) == 0
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }
local DIRS = { "up", "right", "down", "left" }

local function worldBfs(tx, ty)
  local sx, sy = wx(), wy()
  local function key(x, y) return (y & 0xFF) * 256 + (x & 0xFF) end
  local seen = { [key(sx, sy)] = true }
  local q, qi = { { sx, sy } }, 1
  local parent = {}
  while qi <= #q do
    local x, y = q[qi][1], q[qi][2]
    qi = qi + 1
    if x == tx and y == ty then
      local dirs, k = {}, key(x, y)
      while parent[k] do
        table.insert(dirs, 1, parent[k][2])
        k = parent[k][1]
      end
      return dirs
    end
    if qi > 20000 then return nil end
    for _, dir in ipairs(DIRS) do
      local d = DELTA[dir]
      local nx, ny = (x + d[1]) & 0xFF, (y + d[2]) & 0xFF
      local k = key(nx, ny)
      if not seen[k] and worldPass(nx, ny) then
        seen[k] = true
        parent[k] = { key(x, y), dir }
        q[#q + 1] = { nx, ny }
      end
    end
  end
  return nil
end

local battleSeen = nil

H.run({ maxFrames = 40000 }, {
  H.loadState(STATE),
  H.waitFrames(10),

  -- ------------------------------------------------------------------ --
  -- A. the shuttle danger question: 20 cycles of exactly probe_world
  -- run 1's pacing, with the danger word logged per cycle
  -- ------------------------------------------------------------------ --
  H.call(function()
    P("A. shuttle: 20 cycles of right/left 24f holds, danger logged")
  end),
  H.repeatN(20, {
    H.hold({ "right" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.hold({ "left" }), H.waitFrames(24), H.release(), H.waitFrames(4),
    H.call(function()
      P("shuttle at (%d,%d) danger=%04X", wx(), wy(), H.readWord(0x1f6e))
    end),
  }),

  -- ------------------------------------------------------------------ --
  -- B. BFS-walk toward one tile short of the Figaro gate (64,75 is on
  -- castle art; aim at (64,77)? -- live-verify: target the tile SOUTH of
  -- the trigger pair first, fall back to neighbors).  Walk with landing
  -- verification; on battle: record everything, kill-bit, then measure
  -- the reload.
  -- ------------------------------------------------------------------ --
  H.call(function()
    for _, c in ipairs({ { 64, 77 }, { 65, 77 }, { 63, 76 }, { 66, 76 },
                         { 64, 75 }, { 65, 75 } }) do
      local path = worldBfs(c[1], c[2])
      P("BFS (84,34)->(%d,%d): %s", c[1], c[2],
        path and (#path .. " steps") or "NO PATH")
    end
  end),
  H.call(function() P("B. walking to (64,77)...") end),
  H.driveUntil(function()
    return (wx() == 64 and wy() == 77) or battleSeen ~= nil
  end, 15000, {
    H.call(function()
      -- flat walker: plan once per call when aligned; hold the next dir
      if H.battleLoadStarted() then
        if not battleSeen then
          battleSeen = { f = H.frame, x = wx(), y = wy(),
                         sx = H.readByte(0x1f60), sy = H.readByte(0x1f61) }
          local w = H.formationWords()
          P("ENCOUNTER f%d at (%d,%d) saved=(%d,%d) danger-was; formation %04X %04X %04X %04X %04X %04X",
            battleSeen.f, battleSeen.x, battleSeen.y, battleSeen.sx,
            battleSeen.sy, w[1], w[2], w[3], w[4], w[5], w[6])
        end
        H.setPad({})
        return
      end
      if not wAligned() then return end      -- keep the current hold
      local plan = worldBfs(64, 77)
      if not plan or #plan == 0 then H.setPad({}); return end
      H.setPad({ [plan[1]] = true })
    end),
  }, "figaro doorstep or first battle"),

  -- if a battle interrupted: record the aftermath, then resume the walk
  H.cond(function() return battleSeen ~= nil end, {
    H.call(function() P("clearing the encounter (kill-bit)") end),
    H.clearBattle(9000),
    H.call(function()
      P("battle cleared at f%d (%d frames in); watching the reload",
        H.frame, H.frame - battleSeen.f)
      P("post-battle: $1F64=%04X $E8=%02X $19=%02X",
        H.readWord(0x1f64), H.readByte(0x00e8), H.readByte(0x0019))
    end),
    H.waitUntil(function()
      return (H.readWord(0x1f64) & 0x3FF) < 3 and wAligned()
         and (H.readByte(0x00e8) & 0x10) == 0
         and (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 1200, "world reloaded", 5),
    H.call(function()
      P("reloaded at f%d (%d frames after clear): at (%d,%d) facing=%d same-tile=%s",
        H.frame, H.frame, wx(), wy(), H.readByte(0x00f6),
        tostring(wx() == battleSeen.x and wy() == battleSeen.y))
      P("flags: $E7=%02X $E8=%02X $E9=%02X $19=%02X danger=%04X",
        H.readByte(0x00e7), H.readByte(0x00e8), H.readByte(0x00e9),
        H.readByte(0x0019), H.readWord(0x1f6e))
    end),
    -- resume: finish the leg (no second-battle bookkeeping; budget-bound)
    H.driveUntil(function()
      return wx() == 64 and wy() == 77
    end, 15000, {
      H.call(function()
        if H.battleLoadStarted() then
          if H.monstersPresent() > 0 then
            for slot = 0, 5 do
              if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
                H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
              end
            end
          end
          local ph = H.frame % 8
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        if (H.readWord(0x1f64) & 0x3FF) >= 3 or not wAligned() then return end
        local plan = worldBfs(64, 77)
        if not plan or #plan == 0 then H.setPad({}); return end
        H.setPad({ [plan[1]] = true })
      end),
    }, "figaro doorstep after battle"),
  }, {}),

  H.call(function()
    P("DONE at (%d,%d) frame %d danger=%04X; Figaro trigger tiles (64,76)/(65,76) one step north",
      wx(), wy(), H.frame, H.readWord(0x1f6e))
    H.screenshot("probe_world3_done")
  end),
})
