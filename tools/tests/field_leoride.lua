-- @suite savestate=wor_leo
-- field_leoride.lua -- the revealed Leo on a chocobo or Magitek armor never shows the riding frames his sheet
-- lacks (#552, docs/design/leo-reveal.md).
--
-- Leo's map sprite sheet (graphics $10) is $1560 bytes, the main cast's $16A0: it has no riding frames (poses
-- $2E/$2F, tiles $1560-$169F), so the field's vehicle table (ObjVehicleTileTbl: $2E/$2F facing left, $6E/$6F
-- right) would draw the first tiles of the next sheet (Banon's).  UpdateObjFrame (field obj.asm, Ot6LeoRide)
-- gives a rider with graphics $10 the walking frames instead.  The World of Ruin seats the party leader on a
-- chocobo at its stables and in Magitek armor in Cyan's dream (map 320).
-- Played from gen_wor_leo's save (LEO leading): Thamasa's street, then -- the declared expedient
-- (tools/state_write_waivers.txt) -- the party object's vehicle bits set to a chocobo with its rider shown
-- (what `vehicle SLOT_1, {CHOCOBO, SHOW_RIDER}` writes, EventCmd_44), and the party walked left and right
-- by the pad.  Asserted: every frame's rider pose ($0877, the object's graphics position) is one of the
-- walking frames ($07/$08 left, $47/$48 right) and never a riding one ($2E/$2F/$6E/$6F).  A mechanism test
-- of the frame choice, not a claim about play.  Screenshots: facing left and right.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 12
local MAP_THAMASA = 344
local poses, bad = {}, {}
local function pobj() return H.readWord(0x0803) end
H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.worldNavTo(251, 230, { maxFrames = 6000, playBattles = "tactical",
    arrive = function() return (H.mapId() & 0x1FF) == MAP_THAMASA and not H.worldMode() end }),
  H.waitUntil(function() return (H.mapId() & 0x1FF) == MAP_THAMASA and H.hasControl() end, 2400, "Thamasa", 1),
  H.navTo(26, 44, { maxFrames = 6000 }),
  H.call(function()
    H.assertEq(pobj(), 41 * GOGO, "LEO leads (the party object is object 12)")
    H.assertEq(H.readByte(0x0879 + pobj()), 0x10, "the party object wears Leo's sprite")
    local o = 0x0868 + pobj()
    H.writeByte(o, (H.readByte(o) & 0x1F) | 0xA0)   -- chocobo ($20), rider shown ($80): EventCmd_44's write
    H.log(string.format("[leoride] the party object's vehicle bits := $%02X (a chocobo, rider shown; declared)",
      H.readByte(o) & 0xE0))
    emu.addEventCallback(function()
      local p = H.readByte(0x0877 + pobj())
      poses[p] = (poses[p] or 0) + 1
      if p & 0x3F == 0x2E or p & 0x3F == 0x2F then bad[#bad + 1] = H.frame end
    end, emu.eventType.endFrame)
  end),
  H.hold({ "left" }), H.waitFrames(40), H.release(), H.waitFrames(10),
  H.call(function() H.screenshot("field_leoride_left") end),
  H.hold({ "right" }), H.waitFrames(40), H.release(), H.waitFrames(10),
  H.call(function() H.screenshot("field_leoride_right") end),
  H.hold({ "left" }), H.waitFrames(40), H.release(), H.waitFrames(10),
  H.call(function()
    local t = {}
    for p, n in pairs(poses) do t[#t + 1] = string.format("$%02X x%d", p, n) end
    table.sort(t)
    H.log("[leoride] rider poses drawn: " .. table.concat(t, ", "))
    H.assertEq(#bad, 0, "no riding frame ($2E/$2F/$6E/$6F) drawn for Leo's sheet")
    local walked = 0
    for _, p in ipairs({ 0x07, 0x08, 0x47, 0x48 }) do walked = walked + (poses[p] or 0) end
    H.assertEq(walked > 0, true, "the sideways rides drew his walking frames")
    H.log("[leoride] PASS: on a chocobo, Leo's sheet shows his walking frames, never the frames it lacks")
  end),
})
