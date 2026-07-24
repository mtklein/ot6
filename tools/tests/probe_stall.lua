-- probe_stall.lua -- drive the beam climb to (29,41), then instrument that
-- tile exhaustively: canStep for all 8 moves, object-map bytes around
-- (30,41), the facing byte, and a 400-frame right-hold trace. Read-only.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function key(x, y) return y * 256 + x end
local function prop1(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function prop2(x, y) return H.readByte(0x7E7700 + H.maptile(x, y)) end
local function objb(x, y) return H.readByte(0x7E2000 + (y & 0xFF) * 256 + (x & 0xFF)) end
local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
                upright = { 1, -1 }, downright = { 1, 1 },
                downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES = { "up", "right", "down", "left",
                "upright", "downright", "downleft", "upleft" }
-- reuse the gen's beam table to walk up to (29,41)
local BRIDGE2 = {}
do
  local seq = {
    { 30, 61, "up" }, { 30, 60, "up" }, { 30, 59, "left" }, { 29, 59, "up" },
    { 29, 58, "up" }, { 29, 57, "right" }, { 30, 57, "upright" }, { 31, 56, "upright" },
    { 32, 55, "upright" }, { 33, 54, "upright" }, { 34, 53, "upright" }, { 35, 52, "upright" },
    { 36, 51, "right" }, { 37, 51, "up" }, { 37, 50, "up" }, { 37, 49, "left" },
    { 36, 49, "upleft" }, { 35, 48, "upleft" }, { 34, 47, "upleft" }, { 33, 46, "upleft" },
    { 32, 45, "upleft" }, { 31, 44, "upleft" }, { 30, 43, "left" }, { 29, 43, "up" },
    { 29, 42, "up" },
  }
  for _, s in ipairs(seq) do BRIDGE2[key(s[1], s[2])] = s[3] end
end
local PRESS = { up = "up", right = "right", down = "down", left = "left",
                upright = "right", downright = "right",
                downleft = "left", upleft = "left" }

H.run({ maxFrames = 8000 }, {
  H.loadState("/Users/mtklein/ot6/build/states/bridge_checkpoint.mss.lua"),
  H.waitFrames(120),
  -- walk to (29,41)
  (function()
    local hb = 0
    return H.driveUntil(function()
      return H.fieldX() == 29 and H.fieldY() == 41 and H.tileAligned()
        and H.hasControl()
    end, 4000, {
      H.call(function()
        hb = hb + 1
        if not H.hasControl() or H.eventRunning() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local dir = BRIDGE2[key(H.fieldX(), H.fieldY())]
        if dir and H.canStep(H.fieldX(), H.fieldY(), dir) then
          H.setPad({ [PRESS[dir]] = true })
        else H.setPad({}) end
      end),
    }, "walk to (29,41)")
  end)(),
  H.waitFrames(30),
  H.call(function()
    local x, y = H.fieldX(), H.fieldY()
    local z = H.readByte(0x00b2) & 3
    H.log(string.format("=== AT (%d,%d) z%d map=%d ===", x, y, z, map()))
    H.log(string.format("facing $b0=%02X $b1=%02X $1eb6=%02X",
      H.readByte(0x00b0), H.readByte(0x00b1), H.readByte(0x1EB6)))
    -- prop + object map around (30,41)
    for _, t in ipairs({ {29,41},{30,41},{31,40},{30,40},{30,42},{31,41} }) do
      H.log(string.format("  tile (%d,%d): p1=%02X p2=%02X obj=%02X",
        t[1], t[2], prop1(t[1],t[2]), prop2(t[1],t[2]), objb(t[1],t[2])))
    end
    H.log("  canStep from (29,41):")
    for _, mv in ipairs(MOVES) do
      H.log(string.format("    %-9s = %s", mv, tostring(H.canStep(29,41,mv))))
    end
  end),
  -- hold RIGHT for 200 frames, trace position + z each 10 frames
  (function()
    local hb = 0
    return H.driveUntil(function() return hb >= 220 end, 400, {
      H.call(function()
        hb = hb + 1
        if hb % 10 == 0 or map() ~= 225 then
          H.log(string.format("  [hold right f%d] map=%d (%d,%d) z%d PC=%02X%02X%02X aligned=%s ev=%s",
            hb, map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3,
            H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5),
            tostring(H.tileAligned()), tostring(H.eventRunning())))
        end
        H.setPad({ right = true })
      end),
    }, "hold right trace")
  end)(),
  H.call(function()
    H.log(string.format("[after right-hold] map=%d (%d,%d) z%d",
      map(), H.fieldX(), H.fieldY(), H.readByte(0x00b2)&3))
  end),
})
