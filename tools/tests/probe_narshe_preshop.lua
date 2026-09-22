-- @manual
-- probe_narshe_preshop.lua -- can the Terra party reach Narshe's item shop
-- (map 26 via map 20's (41,22) door) between the clifftop arrival and the
-- reunion trigger at Arvis's (66,35)?  (#176: the reunion staging on map 22
-- boxes the party -- navTo's survey from (20,9) is one tile -- so the only
-- pre-battle window for the shop is before _ccb3fa fires.)  Boots
-- terra_clifftop, walks the back door into Arvis's house, and reports the
-- bfs paths to the front door (55,35) and whether they cross the trigger;
-- if the front door is reachable it walks out and surveys the streets.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function pathReport(tx, ty)
  local p = H.bfsPath(tx, ty)
  if not p then
    H.log(string.format("[probe] path to (%d,%d): none", tx, ty))
    return nil
  end
  local crosses = false
  for _, s in ipairs(p) do
    if s[1] == 66 and s[2] == 35 then crosses = true end
  end
  H.log(string.format("[probe] path to (%d,%d): %d steps, crosses (66,35)=%s",
    tx, ty, #p, tostring(crosses)))
  return p
end

H.run({ maxFrames = 30000 }, {
  H.loadState("build/states/terra_clifftop.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] boot map=%d (%d,%d) $0021=%d $00A4=%d $006B=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0021), sw(0x00A4), sw(0x006B)))
    pathReport(41, 22)   -- the item shop door, if the clifftop joins the town
  end),
  H.navTo(53, 9, { maxFrames = 20000, playBattles = true,
    arrive = function() return map() ~= 20 end }),
  H.release(),
  H.waitUntil(function()
    return map() == 30 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 6000, "Arvis's house", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] house map=%d (%d,%d) $0021=%d", map(),
      H.fieldX(), H.fieldY(), sw(0x0021)))
    for _, t in ipairs({ { 55, 34 }, { 55, 35 }, { 55, 36 }, { 60, 37 }, { 66, 35 } }) do
      pathReport(t[1], t[2])
    end
    H.screenshot("probe_terra_house")
  end),
  H.cond(function()
    local p = H.bfsPath(55, 35)
    if not p then return false end
    for _, s in ipairs(p) do if s[1] == 66 and s[2] == 35 then return false end end
    return true
  end, {
    -- (55,35) is the short entrance itself (map 30 (55,35) -> 20 (49,14));
    -- walking onto it fires it, so the navTo's arrive is the map change.
    H.navTo(55, 35, { maxFrames = 12000, playBattles = true, avoid = { { 66, 35 } },
      arrive = function() return map() == 20 end }),
    H.release(),
    H.waitUntil(function()
      return map() == 20 and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 3000, "the streets", 5),
    H.waitFrames(90),
    H.call(function()
      H.log(string.format("[probe] streets map=%d (%d,%d) $0021=%d ctl=%s", map(),
        H.fieldX(), H.fieldY(), sw(0x0021), tostring(H.hasControl())))
      pathReport(41, 22)
      pathReport(41, 23)
      pathReport(49, 12)   -- Arvis's front door from the streets side (map 20 (49,12) -> 30 (55,34))
      H.screenshot("probe_terra_streets")
    end),
    -- and back in through the front door, to show the round trip closes
    H.navTo(49, 13, { maxFrames = 12000, playBattles = true }),
    H.driveUntil(function() return map() == 30 end, 900, {
      H.hold({ "up" }), H.waitFrames(4),
    }, "back in through Arvis's front door"),
    H.release(),
    H.waitUntil(function()
      return map() == 30 and H.hasControl() and H.tileAligned() and bright() >= 15
    end, 3000, "the house again", 5),
    H.waitFrames(60),
    H.call(function()
      H.log(string.format("[probe] house again map=%d (%d,%d) $0021=%d", map(),
        H.fieldX(), H.fieldY(), sw(0x0021)))
      pathReport(66, 35)
    end),
  }, {
    H.logStep("[probe] the front door is not reachable without the trigger; no pre-reunion shop"),
  }),
})
