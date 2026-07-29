-- probe_banquet_exit.lua -- I->J leg development (issue #31): the
-- MESSENGER, the castle exit, and the anchor-J doorstep, from the staged
-- banquet_postqa savestate (probe_banquet_qa.lua) -- control on 251 as
-- TERRA+LOCKE, var0==93, $007D=1.
--
-- Measures the one open exit-topology question: the 250 {22,29} door was
-- opened by a TRANSIENT mod_bg_tiles on first entry (map-init _cc839e is
-- $013B-latched dead afterwards), and the post-banquet exit crosses 250
-- on a FRESH load.  If the corridor is unreachable this probe fails at
-- the navTo with a live census in the log.
--
-- Route: 251 (79..81,27) -> 250 (53,11) [a stood-on trigger: stepOff] ->
-- the (23,12) messenger (walk-on at rest; $0276/77/78, Tintinabar $E5,
-- Charm Bangle $DF, var0 -> 0, $0238=1) -> corridor -> (22..24,34) door
-- -> 243 (15,10) -> south rows (11-19,31) -> 253 (29,2) -> the (30,63)
-- world exit -> world (120,188) -> world menu save-legality ($0201.7).
--
--   tools/tests/run.sh tools/tests/probe_banquet_exit.lua
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function var0() return H.readWord(0x1fc2) end
local function killBitAll()
  for s = 0, 5 do
    if H.readByte(0x3aa8 + s * 2) % 2 == 1 then
      H.writeByte(0x3eec + s * 2, H.readByte(0x3eec + s * 2) | 0x80)
    end
  end
end
local function hasItem(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id and H.readByte(0x1969 + i) > 0 then
      return true
    end
  end
  return false
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

local function landed(m, n)
  local cnt, hb = 0, -600
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    if not ok and H.frame - hb >= 600 then
      hb = H.frame
      H.log(string.format("landed(%d) f%d: map=%d ctl=%s dlg=%s (%d,%d)",
        m, H.frame, map(), tostring(H.hasControl()),
        tostring(H.dialogWaiting()), H.fieldX(), H.fieldY()))
    end
    return cnt >= (n or 20)
  end
end

H.run({ maxFrames = 90000 }, {
  H.loadState("build/states/banquet_postqa.mss.lua"),
  H.waitFrames(90),
  H.call(function()
    H.assertEq(map(), 251, "boot: the dinner hall")
    H.assertEq(sw(0x007D), 1, "boot: $007D set")
    H.assertEq(var0(), 93, "boot: var0 == 93")
  end),

  -- out of 251: the (79..81,27) door row -> 250 (53,11)
  H.navTo(80, 26, { maxFrames = 9000 }),
  pressWalk("down", function() return map() == 250 end, 900,
    "251 door row -> 250 (53,11)"),
  H.waitFrames(30),
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the (53,11) trigger tile"),
  H.call(function()
    H.log(string.format("[250] off the door at (%d,%d)", H.fieldX(), H.fieldY()))
  end),

  -- the messenger: walk onto (23,12) at rest, ride to $0238=1
  H.navTo(23, 12, { maxFrames = 20000, calmFrames = 4 }),
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x0238) == 1 end, 9000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
      end),
    }, "the messenger scene -> $0238=1")
  end)(),
  (function() local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad(H.dialogWaiting() and (ph < 4 and { "a" } or {}) or {})
      end),
    }, "messenger tail settles")
  end)(),
  H.call(function()
    H.assertEq(sw(0x0238), 1, "$0238 -- the rewards paid")
    H.assertEq(sw(0x0276), 1, "$0276 -- South Figaro withdrawal")
    H.assertEq(sw(0x0277), 1, "$0277 -- Doma withdrawal (>=50)")
    H.assertEq(sw(0x0278), 1, "$0278 -- base weapons unlock (>=67)")
    H.assertEq(sw(0x0512), 0, "$0512 cleared with the Doma withdrawal")
    H.assertEq(hasItem(0xE5), true, "Tintinabar in inventory (>=77)")
    H.assertEq(hasItem(0xDF), true, "Charm Bangle in inventory (>=90)")
    H.assertEq(var0(), 0, "var0 zeroed by the messenger")
    H.screenshot("bq_messenger_paid")
  end),

  -- the exit: down to the corridor, the (22..24,34) door -> 243 (15,10)
  -- ((23,12) is a stood-on trigger after $0238 latches: step off first)
  H.stepOff({ "down", "left", "right" }, 2400,
    "off the messenger trigger tile"),
  H.navTo(23, 33, { maxFrames = 20000 }),
  pressWalk("down", function() return map() == 243 end, 1200,
    "door 250 (22..24,34) -> 243 (15,10)"),
  H.waitUntil(landed(243, 10), 2400, "243 antechamber", 1),

  -- south rows (11-19,31) -> 253 (29,2)
  H.navTo(15, 30, { maxFrames = 12000 }),
  pressWalk("down", function() return map() == 253 end, 1200,
    "south rows -> 253 (29,2)"),
  H.waitUntil(landed(253, 10), 2400, "Vector 253", 1),

  -- 253 (30,63) world exit -> world (120,188)
  H.navTo(30, 62, { maxFrames = 30000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "253 world exit -> world (120,188)"),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
       and bright() >= 15
  end, 3600, "world control outside Vector", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[world] (%d,%d) $1F60/61=(%d,%d) f%d",
      H.worldX(), H.worldY(), H.readByte(0x1F60), H.readByte(0x1F61),
      H.frame))
    H.assertEq(H.worldX(), 120, "anchor-J doorstep x")
    H.assertEq(H.worldY(), 188, "anchor-J doorstep y")
    H.screenshot("bq_anchor_j_tile")
  end),

  -- world menu: save legality at the J tile (the gen saves for real)
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
    }, "world menu opens at the J tile")
  end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq((H.readByte(0x0201) & 0x80) ~= 0, true,
      "menu-flags $0201 bit7 SET -- world save legal at (120,188)")
  end),
  H.logStep(function()
    return string.format("exit probe done at frame %d", H.frame)
  end),
})
