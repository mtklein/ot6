-- probe_tent_summit.lua -- what the field looks like after a Tent (#231).
--
-- The care kernel's Tent arm saw the Mt Kolts summit give control back 414
-- frames after the confirm and take it again 30 frames later, and then a
-- landing that waited for twenty quiet frames never got them inside a
-- 24000-frame budget.  So: walk vargas_entry back onto the summit save
-- point (map 103 (57,8)), stage a Tent into the bag (the fixture holds
-- none; a declared instrument write), pitch it by hand through the item
-- list the way gen_narshe_mission's useTent does, and then log every cell
-- a control predicate reads for 1500 frames: menu state, the control
-- gates ($1EB9.7, $84, $59), the party's movement type, the event PC, the
-- dialog cells, position, and the two predicates themselves.
local H = dofile("tools/tests/lib/ot6.lua")

local SUMMIT = "build/states/vargas_entry.mss.lua"
local TENT = 0xF7

local function pobj() return H.readWord(0x0803) end
local function cells()
  return string.format("f%d map=%d (%d,%d) $26=%02X $59=%02X $84=%02X $1EB9=%02X " ..
    "move=%02X ev=%02X:%02X%02X $BA=%02X $D3=%02X hasControl=%s aligned=%s " ..
    "event=%s dialog=%s $01BF=%d",
    H.frame, H.mapId() & 0x1ff, H.fieldX(), H.fieldY(), H.readByte(0x26),
    H.readByte(0x59), H.readByte(0x84), H.readByte(0x1EB9),
    H.readByte(0x087c + pobj()), H.readByte(0xE7), H.readByte(0xE6), H.readByte(0xE5),
    H.readByte(0xBA), H.readByte(0xD3), tostring(H.hasControl()),
    tostring(H.tileAligned()), tostring(H.eventRunning()),
    tostring(H.dialogWaiting()),
    (H.readByte(0x1E80 + (0x1BF >> 3)) >> (0x1BF & 7)) & 1)
end

local function stage(item, n)
  for s = 0, 255 do
    if H.readByte(0x1869 + s) == 0xFF then
      H.writeByte(0x1869 + s, item)
      H.writeByte(0x1969 + s, n)
      return s
    end
  end
end

local before, usedAt = nil, nil
local ph = 0
H.run({ maxFrames = 60000 }, {
  H.loadState(SUMMIT),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() end, 600, "control", 5),
  H.navTo(10, 10, { maxFrames = 8000, playBattles = "tactical",
    arrive = function() return (H.mapId() & 0x1ff) == 103 end }),
  H.waitUntil(function()
    return (H.mapId() & 0x1ff) == 103 and H.hasControl() and H.tileAligned()
  end, 1800, "the summit", 5),
  H.navTo(57, 8, { maxFrames = 8000, playBattles = "tactical" }),
  H.release(), H.waitFrames(30),
  H.call(function()
    H.log("on the save point: " .. cells())
    local s = stage(TENT, 1)
    H.log(string.format("staged a Tent into slot %d", s))
    before = H.invCountOf(TENT)
  end),
  -- pitch it by hand: X -> $05 Item -> $08 the slot -> A ($19) -> A
  H.driveUntil(function() return H.invCountOf(TENT) < before end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local st, cur = H.readByte(0x26), H.readByte(0x4b)
      local slot = H.invSlotOf(TENT)
      if H.readByte(0x59) == 0 and st ~= 0x05 and st ~= 0x08 and st ~= 0x19 then
        H.setPad(ph < 4 and { "x" } or {}); return
      end
      if st == 0x05 then
        H.setPad(cur == 0 and (ph < 4 and { "a" } or {}) or { up = true }); return
      end
      if st == 0x08 then
        if cur == slot then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({ [cur < slot and "down" or "up"] = true }) end
        return
      end
      if st == 0x19 then
        H.setPad(cur == slot and (ph < 4 and { "a" } or {}) or (ph < 4 and { "b" } or {}))
        return
      end
      H.setPad({})
    end),
  }, "the Tent leaves the bag"),
  H.release(),
  H.call(function()
    usedAt = H.frame
    H.log("Tent consumed: " .. cells())
  end),
  (function()
    local n = 0
    return H.driveUntil(function() return n >= 1500 end, 1600, {
      H.call(function()
        n = n + 1
        if n % 30 == 0 then H.log(string.format("+%d ", n) .. cells()) end
        H.setPad({})
      end),
    }, "1500 quiet frames after the Tent")
  end)(),
  H.call(function()
    H.log("end: " .. cells())
    for _, c in ipairs(H.partyMembers()) do
      H.log(string.format("char %d %d/%d hp %d/%d mp", c, H.charHp(c),
        H.charMaxHp(c), H.charMp(c), H.charMaxMp(c)))
    end
    H.screenshot("tent_summit_after")
  end),
})
