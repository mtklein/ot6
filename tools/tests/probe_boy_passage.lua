-- probe_boy_passage.lua -- #244/#145.  DRIVE (not BFS) the disguise-gated
-- interior bypass the owner describes: with the MERCHANT disguise, the little
-- boy in the old man's house steps aside (grandson event _ca7bcd -> _ca7bf8,
-- obj_script NPC_5, switch $01F0), opening a passage.  Inject $0104 for the
-- exploration; log the map/pos as we drive old-man-house -> boy.  @manual
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function setsw(id, v)
  local a = 0x1e80 + (id >> 3); local b = 1 << (id & 7)
  H.writeByte(a, v == 1 and (H.readByte(a) | b) or (H.readByte(a) & ~b))
end
local function seq(steps) return H.cond(function() return true end, steps) end
local function hop(tx, ty, what)
  return seq({ H.navTo(tx, ty, { maxFrames = 12000, playBattles = true }), H.release(),
    H.call(function() H.log(string.format("  %s -> (%d,%d) map=%d", what, H.fieldX(), H.fieldY(), map())) end) })
end

H.run({ maxFrames = 80000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.BFS_CAP = 20000
    setsw(0x0104, 1)  -- exploration: put on the merchant disguise
    H.log(string.format("[boy] boot map=%d (%d,%d) 0104(merchant)=%d 0107=%d 0105=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0104), sw(0x0107), sw(0x0105)))
  end),
  -- into the old man's house (town door (37,40) -> map 86 (36,22)), the same
  -- door the shipped route uses for the old man
  hop(37, 41, "approach old-man door"),
  H.driveUntil(function() return map() == 86 end, 3000, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "into the old man's house"),
  H.release(),
  H.waitFrames(90),
  H.call(function()
    H.log(string.format("[boy] inside: map=%d at (%d,%d); (32,11)warp reach=%s",
      map(), H.fieldX(), H.fieldY(), H.bfsPath(32, 11) and "yes" or "no"))
  end),
  -- walk onto the same-map warp at (32,11) -> lands at (9,8), near the boy.
  -- arrive when we warp west (x drops below 15), not when we stand on (32,11).
  H.navTo(32, 11, { maxFrames = 12000, playBattles = true,
                    arrive = function() return H.fieldX() < 15 end }),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[boy] after warp: at (%d,%d) map=%d; boy(6,10) reach=%s "
      .. "passage-stairs(4,15) reach=%s", H.fieldX(), H.fieldY(), map(),
      H.bfsPath(6, 10) and "yes" or "no", H.bfsPath(4, 15) and "yes" or "no"))
  end),
  hop(6, 11, "approach the boy (grandson) at (6,10)"),
  -- talk to the boy: which obj? the grandson is _ca7bcd; find it by proximity
  H.call(function()
    for o = 16, 31 do
      if math.abs(H.objX(o) - 6) <= 2 and math.abs(H.objY(o) - 10) <= 2 then
        H.log(string.format("[boy] candidate obj %d at (%d,%d)", o, H.objX(o), H.objY(o)))
      end
    end
  end),
  H.talkToObj(20, "the boy (grandson, merchant gate)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, {
      H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
    }, "ride the boy's dialog")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[boy] AFTER talking (merchant): 01F0(passed)=%d at (%d,%d) map=%d; "
      .. "passage-stairs(4,15) reach=%s (7,51) reach=%s",
      sw(0x01F0), H.fieldX(), H.fieldY(), map(),
      H.bfsPath(4, 15) and "yes" or "no", H.bfsPath(7, 51) and "yes" or "no"))
  end),
})
