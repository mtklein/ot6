-- probe_v07_384.lua -- BASEMENT 3 (map 384) live census, part 1 of leg
-- G->H's tail (issue #31).  NOT a suite test.  Boots v07q_384_entry.mss
-- (the 385 crossing's park at (26,8)) and answers what the recon says is
-- not statically derivable (sealed-gate-recon.md §1 leg 3: "mod_bg_tiles
-- at ten+ sites, the static tilemap does not describe the live map"):
--   * the live reachable set from the entry -- is the save-room door
--     (64,10) reachable WITHOUT any switch work, and which of the seven
--     face+A switches / trigger tiles lie on the route;
--   * whether the (46,11) bridge-retract scene (_cb2f00,
--     event_main.asm:44996 -- ~500 frames of sfx loop + shake, sets
--     $01F9/$01FB, retracts (41..45,11) BEHIND the party) fires on the way
--     east and what it leaves;
--   * the save room chain 384 (64,10) -> 386 (73,58) -> the SavePoint
--     trigger (74,53) (event_trigger.asm:1888).
-- Mints v07q_386_save.mss, parked one tile short of the save point.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function prop(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local function dumpRegion(tag, x0, x1, y0, y1)
  for y = y0, y1 do
    local r = {}
    for x = x0, x1 do r[#r + 1] = string.format("%02X", prop(x, y)) end
    H.log(string.format("[%s p1 y=%02d x=%d..%d] %s", tag, y, x0, x1,
      table.concat(r, " ")))
  end
end

-- flood the live model from the party tile (budget-capped) and report
-- whether the named goals are inside
local function reach(tag, goals)
  local sx, sy = H.fieldX(), H.fieldY()
  local seen = { [sy * 256 + sx] = true }
  local q, qi = { { sx, sy } }, 1
  local D = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 },
              left = { -1, 0 } }
  while qi <= #q and #q < 20000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for m, d in pairs(D) do
      if H.canStep(x, y, m) then
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < 128 and ny >= 0 and ny < 64
           and not seen[ny * 256 + nx] then
          seen[ny * 256 + nx] = true
          q[#q + 1] = { nx, ny }
        end
      end
    end
  end
  H.log(string.format("[%s] flood from (%d,%d): %d tiles", tag, sx, sy, #q))
  for _, g in ipairs(goals) do
    H.log(string.format("[%s] %s (%d,%d): %s", tag, g[3], g[1], g[2],
      seen[g[2] * 256 + g[1]] and "REACHABLE" or "no"))
  end
  return seen
end

local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/v07q_384_entry.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 384, "booted on BASEMENT 3 (map 384)")
    H.log(string.format("[boot] (%d,%d) masks $86=%02X $87=%02X "
      .. "$01F9=%d $01FA=%d $0173=%d $0174=%d $0175=%d",
      H.fieldX(), H.fieldY(), H.readByte(0x86), H.readByte(0x87),
      sw(0x01F9), sw(0x01FA), sw(0x0173), sw(0x0174), sw(0x0175)))
  end),
  H.call(function()
    dumpRegion("384w", 24, 71, 5, 20)
    reach("384-entry", {
      { 40, 11, "the (40,11) trigger" },
      { 46, 11, "the (46,11) retract-scene trigger" },
      { 58, 18, "the (58,18) face+A switch" },
      { 62, 11, "the (62,11) face+A switch" },
      { 66, 11, "the (66,11) trap switch" },
      { 64, 10, "the save-room door (64,10)" },
      { 9, 27, "the gate door (9,27)" },
      { 5, 43, "the post-gate shortcut trigger (5,43)" },
    })
  end),

  -- MEASURED (this probe, run 1): the (41..45,11) bridge span is OUT on a
  -- fresh entry -- (46,11) and everything across it are unreachable, so
  -- the retract scene never fires on this route -- and the save-room door
  -- (64,10) is CLOSED until the (62,11) face-UP+A switch runs _cb3062
  -- (event_main.asm:45148): its _cb303e patch rewrites {62,10} and
  -- {63,9}x{3,3}, which IS the door, latching persistent $0173.  The
  -- reachable set from the entry is the SOUTH loop: 263 tiles containing
  -- (40,11), (58,18), (62,11) and (66,11).
  H.navTo(62, 11, { maxFrames = 30000 }),
  H.call(function()
    H.log(string.format("[on switch] (%d,%d) $0173=%d p(64,10)=%02X",
      H.fieldX(), H.fieldY(), sw(0x0173), prop(64, 10)))
  end),
  -- the lever/valve idiom (gen_sabin_train upA): stand ON the trigger,
  -- hold UP into the wall to set facing, edge-A ($01B0/$01B4)
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x0173) == 1 end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad(ph < 4 and { "up", "a" } or { "up" })
      end),
    }, "face-UP+A on (62,11) -> $0173 (the save-room door)")
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[door open] $0173=%d p(64,10)=%02X p(64,11)=%02X",
      sw(0x0173), prop(64, 10), prop(64, 11)))
    dumpRegion("384-dooropen", 60, 68, 8, 13)
    H.screenshot("v07_384_switch")
  end),
  H.navTo(64, 11, { maxFrames = 9000 }),
  H.call(function()
    H.log(string.format("[below door] (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("v07_384_door")
  end),
  pressWalk("up", function() return map() == 386 end, 1200,
    "held UP onto the save-room door (64,10) -> map 386"),
  H.waitUntil(function()
    return map() == 386 and H.hasControl() and H.tileAligned()
       and bright() >= 15
  end, 2400, "386 control", 5),
  H.waitFrames(45),
  H.call(function()
    H.log(string.format("[386] landed at (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("v07_386_entry")
  end),
  H.navTo(74, 54, { maxFrames = 9000 }),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[386 save doorstep] (%d,%d) $01BF=%d $0632=%d",
      H.fieldX(), H.fieldY(), sw(0x01BF), sw(0x0632)))
    -- the sparkle NPC and the trigger live at (74,53); park one south
    H.assertEq(map(), 386, "map 386")
    H.assertEq(H.fieldX(), 74, "doorstep x")
    H.assertEq(H.fieldY(), 54, "doorstep y")
    H.screenshot("v07_386_savept")
  end),
  H.saveState("v07q_386_save.mss"),

  -- positive control: step ONTO the save tile and watch $01BF set.
  -- MEASURED (probe_v07_386tile): a HELD press walks the party straight
  -- THROUGH (74,53) to (74,51) without the trigger ever firing --
  -- CheckEventTriggers (field/event.asm:5740) demands exact sub-pixel
  -- alignment and under a held press the step chain never rests on the
  -- tile.  gen_n024_save_anchor's tapInto (tap 8 frames, release, settle)
  -- is the idiom that stops ON the tile.
  (function()
    local phase, n, ph, calm = 0, 0, 0, 0
    local function calmPred()
      return H.tileAligned() and not H.dialogWaiting()
         and not H.battleLoadStarted()
    end
    local function pred()
      return H.fieldX() == 74 and H.fieldY() == 53 and sw(0x01BF) == 1
    end
    return H.driveUntil(function()
      calm = (pred() and calmPred()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          killBitAll(); H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
        end
        if H.dialogWaiting() then
          H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
        end
        if phase == 0 then
          H.setPad({})
          if pred() then return end
          if calmPred() then phase, n = 1, 0 end
          return
        end
        if phase == 1 then
          n = n + 1
          H.setPad({ up = true })
          if n >= 8 then phase, n = 2, 0 end
          return
        end
        H.setPad({})
        n = n + 1
        if n >= 24 then phase = 0 end
      end),
    }, "tap UP onto the save point (74,53) -> $01BF")
  end)(),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the SavePoint script ran")
    H.log(string.format("[save tile] (%d,%d)", H.fieldX(), H.fieldY()))
    H.screenshot("v07_386_ontile")
  end),
  H.logStep(function()
    return string.format("384 census + 386 save-point drive complete at "
      .. "frame %d", H.frame)
  end),
})
