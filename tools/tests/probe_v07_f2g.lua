-- probe_v07_f2g.lua -- v0.7 leg F->G route recon (issue #31).  NOT a suite
-- test.  Findings from run 1 + probe_v07_fly (2026-07-28), all measured:
--   * cold Continue restores the party ON the parked ship tile (24,121);
--     one A tap boards AND lifts off (screen fades, then the mode-7
--     flight view; $E0/$E2 read 0 while airborne).
--   * bare d-pad in flight ROTATES ($29/$2E ang. vel, $30 heading) and
--     never translates; Y+direction STRAFES (the gen_terra_returned_anchor
--     landing idiom).  Ship tile = word($34)>>4, word($38)>>4.
--   * X in flight exits to the Blackjack DECK, map 6 (16,6) -- the swap
--     room door is the G->H leg's business, not this one's.
--   * B over a landable tile ($c2 bit1 clear) grounds the ship; the party
--     is then back in the parked-tile state (walk off = on foot).
-- This run: fly F->Narshe, land (84,36), enter, drive the mission meeting
-- to $0076=1, walk out, and exercise the world-save flow at the exit spawn
-- (84,34) -- the proposed anchor-G tile.  Mints v07p_*.mss waypoints.
-- OT6_ANCHOR_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local ZMENUSTATE = 0x26
local SAVE_SELECT_INIT = 0x13
local SAVE_SELECT = 0x14

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end

local function st(tag)
  return H.call(function()
    H.log(string.format(
      "[%s] $1f64=%04X 11FA=%02X 11F3=%02X world=(%d,%d) ship=(%d,%d) "
      .. "wctl=%s $c2=%02X $19=%02X $e8=%02X",
      tag, H.readWord(0x1f64), H.readByte(0x11FA), H.readByte(0x11F3),
      H.worldX(), H.worldY(), shipX(), shipY(),
      tostring(H.worldHasControl()), H.readByte(0xc2), H.readByte(0x19),
      H.readByte(0xe8)))
    H.screenshot("v07p_" .. tag)
  end)
end

local function worldGrind(tx, ty, what)
  local plan, idx, ph = nil, 1, 0
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        killBitAll(); plan = nil; H.setPad(ph < 4 and { "a" } or {}); return
      end
      if not H.worldMode() then H.setPad({}); return end
      if not H.worldHasControl() then plan = nil; H.setPad({}); return end
      if not H.worldAligned() then return end
      if not plan or idx > #plan then plan = H.worldBfs(tx, ty); idx = 1 end
      if not plan then H.setPad({}); return end
      local dir = plan[idx]; idx = idx + 1
      H.setPad({ [dir] = true })
    end),
  }, what or string.format("worldGrind (%d,%d)", tx, ty))
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then killBitAll(); H.setPad(ph < 4 and { "a" } or {}); return end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- strafe-fly the ship to hover tile (tx,ty): Y + axis directions, then a
-- settle re-check (velocity decays after release and can carry a tile)
local function flyTo(tx, ty)
  local calm, hb = 0, -300
  return H.driveUntil(function()
    local on = shipX() == tx and shipY() == ty
    calm = on and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      if H.frame - hb >= 300 then
        hb = H.frame
        H.log(string.format("[fly] f%d ship=(%d,%d) $c2=%02X",
          H.frame, shipX(), shipY(), H.readByte(0xc2)))
      end
      local dx, dy = tx - shipX(), ty - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, string.format("strafe-fly to (%d,%d)", tx, ty))
end

H.run({ maxFrames = 120000 }, {
  -- cold Continue ladder (probe_mpu_boot's, measured good on this anchor)
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntil(function() return H.worldMode() end, 3000, "world", 10),
  H.waitUntil(function() return bright() >= 15 end, 900, "fade-in", 10),
  H.waitFrames(60),
  st("boot"),

  -- board + liftoff: one A tap; airborne when $E0 reads 0 (flight view)
  H.pressButtons({ "a" }, 8),
  H.waitUntil(function() return H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0 end,
    600, "liftoff (E0/E2 zeroed in flight)", 5),
  H.waitFrames(240),
  st("airborne"),

  flyTo(84, 36),
  H.release(),
  H.waitFrames(60),
  st("hover"),
  H.call(function()
    H.assertEq(shipX(), 84, "hover x")
    H.assertEq(shipY(), 36, "hover y")
    H.assertEq(H.readByte(0xc2) & 0x02, 0, "tile under the ship is landable")
  end),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() ~= 0 or H.worldY() ~= 0 end,
    1200, "grounded (world position cells rewritten)", 10),
  H.waitFrames(120),
  st("grounded"),

  -- disembark UP toward the gate corridor
  (function() local ph = 0
    return H.driveUntil(function()
      return H.worldX() == 84 and H.worldY() == 35 and H.worldAligned()
    end, 1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ up = true }) end),
    }, "step off UP to (84,35)")
  end)(),
  H.release(), H.waitFrames(30),
  st("onfoot"),
  H.saveState("v07p_narshe_land.mss"),
  worldGrind(84, 34, "world walk -> the Narshe doorstep (84,34)"),
  (function() local ph = 0
    return H.driveUntil(function() return not H.worldMode() and map() == 20 end,
      1200, {
      H.call(function() ph = (ph + 1) % 8; H.setPad({ up = true }) end),
    }, "held UP onto (84,33) -> Narshe (map 20)")
  end)(),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "Narshe control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[narshe] map=%d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),

  -- north to the escort trigger row (y=51); ride the escort + meeting
  H.navTo(38, 53, { maxFrames = 12000 }),
  st("trigger_approach"),
  pressWalk("up", function() return map() == 30 or not H.hasControl() end, 2400,
    "held UP onto the escort trigger row"),
  H.advanceStory(function()
    return map() == 30 and sw(0x0076) == 1
  end, 60000),
  H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15
       and not H.dialogWaiting()
  end, 6000, "control after the meeting", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[meeting done] map=%d (%d,%d) $0076=%d $064E=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0076), sw(0x064E)))
    H.screenshot("v07p_meeting_done")
  end),
  H.saveState("v07p_meeting_done.mss"),

  -- out of Narshe: map 30 (110,26) door -> map 20 (18,24) -> row 62 -> world
  H.navTo(110, 25, { maxFrames = 12000 }),
  pressWalk("down", function() return map() == 20 end, 1200,
    "door 30 (110,26) -> map 20"),
  H.waitUntil(function()
    return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "map 20 control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[map20] at (%d,%d)", H.fieldX(), H.fieldY()))
  end),
  H.navTo(18, 61, { maxFrames = 15000 }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "row 62 -> the world map"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
       and H.worldX() ~= 0
  end, 2400, "world spawn after Narshe exit", 5),
  H.waitFrames(30),
  st("world_out"),
  H.saveState("v07p_world_out.mss"),

  -- the world-save flow at the anchor-G tile (the exit spawn itself)
  (function() local calm, ph = 0, 0
    return H.driveUntil(function()
      calm = (H.readByte(0x59) ~= 0) and calm + 1 or 0
      return calm >= 30
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if H.readByte(0x59) ~= 0 then H.setPad({}); return end
        H.setPad(ph < 6 and { "x" } or {})
      end),
    }, "world menu open on foot")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[menu] $0201=%02X (bit7 = save legal)", H.readByte(0x0201)))
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "world save legal at the anchor-G tile")
    emu.write(0x307ff0, 0x00, emu.memType.snesMemory)
    H.writeByte(ZMENUSTATE, SAVE_SELECT_INIT)
  end),
  H.waitUntil(function() return H.readByte(ZMENUSTATE) == SAVE_SELECT end,
    300, "save-slot selection", 5),
  H.call(function()
    H.writeByte(0x4b, 2)
    H.writeWord(0x95, 0)
  end),
  H.pressButtons({ "a" }, 4),
  H.driveUntil(function()
    return emu.read(0x307ff0, emu.memType.snesMemory) == 3
  end, 1800, {
    H.pressButtons({ "a" }, 4), H.waitFrames(20),
  }, "save confirmed at the G tile"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[saved] slot marker=%d world=(%d,%d) $1f60/61=(%d,%d) "
      .. "$1f65=%02X 11FA=%02X party1850=%02X %02X %02X %02X %02X %02X %02X "
      .. "%02X %02X %02X",
      emu.read(0x307ff0, emu.memType.snesMemory), H.worldX(), H.worldY(),
      H.readByte(0x1f60), H.readByte(0x1f61), H.readByte(0x1f65),
      H.readByte(0x11FA),
      H.readByte(0x1850), H.readByte(0x1851), H.readByte(0x1852),
      H.readByte(0x1853), H.readByte(0x1854), H.readByte(0x1855),
      H.readByte(0x1856), H.readByte(0x1857), H.readByte(0x1858),
      H.readByte(0x1859)))
    H.screenshot("v07p_saved_g")
  end),
  H.logStep(function()
    return string.format("F->G probe complete at frame %d", H.frame)
  end),
})
