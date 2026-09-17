-- @suite savestate=reunion_ready
-- field_partyselect.lua -- #190: H.partySelect seats characters through the
-- real party menu by reading its cells, not by replaying cell numbers.
--
-- reunion_ready is the Narshe staging (gen_narshe_battle's boot): BANON's
-- "Prepared?" opens party_menu 3 with the reunion's seven in the pool
-- (TERRA LOCKE CYAN EDGAR SABIN CELES GAU at cells 0-6).  One snapshot with
-- the menu up, two branches from it:
--   A. the route's split, P1 TERRA EDGAR CELES / P2 CYAN SABIN / P3 LOCKE
--      GAU, committed with START: every seat cell holds its member, and once
--      the menu has closed each member's $1850 group bits name its group;
--   B. a different split, members in a different order (P1 GAU SABIN / P2
--      LOCKE / P3 CELES CYAN TERRA EDGAR), then the same call again: the
--      seats follow the arguments, and a second pass over members already
--      seated moves nothing.
-- Reads and presses only; the snapshot is a complete machine state.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function mst() return H.readByte(0x0026) end
local function cell(c) return H.readByte(0x7E9D89 + c) end
local function partyOf(c) return H.readByte(0x1850 + c) & 0x07 end
local function census()
  local t = {}
  for c = 0x00, 0x1F do t[#t + 1] = string.format("%02X", cell(c)) end
  return table.concat(t, " ")
end

local TERRA, LOCKE, CYAN, EDGAR, SABIN, CELES, GAU =
  0x00, 0x01, 0x02, 0x04, 0x05, 0x06, 0x0B
local ROUTE = { { TERRA, EDGAR, CELES }, { CYAN, SABIN }, { LOCKE, GAU } }
local OTHER = { { GAU, SABIN }, { LOCKE }, { CELES, CYAN, TERRA, EDGAR } }

local function seatsHold(groups, what)
  return H.call(function()
    H.log(string.format("[%s] cells $00-$1F: %s", what, census()))
    for g, ids in ipairs(groups) do
      for s, id in ipairs(ids) do
        H.assertEq(cell(0x10 + 4 * (g - 1) + (s - 1)), id,
          string.format("%s: group %d seat %d holds $%02X", what, g, s - 1, id))
      end
    end
  end)
end

local blob, req, before
H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/reunion_ready.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 22, "booted on map 22, the reunion staging")
    H.assertEq(H.hasControl(), true, "controllable")
  end),
  -- gen_narshe_battle's approach: stand under BANON, face him, edge-A
  -- through "Prepared?" (row 0 is Yes) to the party menu
  H.navTo(20, 8, { maxFrames = 6000, playBattles = true }),
  H.hold({ "up" }), H.waitFrames(8), H.release(), H.waitFrames(6),
  (function()
    local aPh = 0
    return H.driveUntil(function() return H.readByte(0x0059) ~= 0 end, 8000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "Banon -> Prepared? -> party menu")
  end)(),
  H.waitUntil(function() return mst() == 0x2d end, 900, "menu at $2d", 5),
  H.waitFrames(20),
  H.call(function()
    for i, want in ipairs({ TERRA, LOCKE, CYAN, EDGAR, SABIN, CELES, GAU }) do
      H.assertEq(cell(i - 1), want, string.format("pool cell %d is $%02X", i - 1, want))
    end
    req = H.requestSaveState()
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(req, "party menu snapshot"); blob = req.blob end),

  -- A
  H.partySelect(ROUTE, { tag = "A", commit = false }),
  seatsHold(ROUTE, "A"),
  H.waitUntil(function() return mst() == 0x2d end, 600, "A: menu at $2d for commit", 5),
  H.pressButtons({ "start" }, 6),
  H.waitUntil(function() return H.readByte(0x0059) == 0 end, 1200, "A: menu closed", 5),
  H.waitFrames(60),
  H.call(function()
    for g, ids in ipairs(ROUTE) do
      for _, id in ipairs(ids) do
        H.assertEq(partyOf(id), g, string.format("A: $%02X committed to party %d", id, g))
      end
    end
  end),

  -- B
  H.call(function() req = H.requestLoadState(blob) end),
  H.waitFrames(2),
  H.call(function() H.checkReq(req, "party menu snapshot reload") end),
  H.waitUntil(function() return mst() == 0x2d end, 900, "B: menu at $2d", 5),
  H.partySelect(OTHER, { tag = "B", commit = false }),
  seatsHold(OTHER, "B"),
  H.call(function() before = census() end),
  H.partySelect(OTHER, { tag = "B again", commit = false }),
  H.call(function()
    H.assertEq(census(), before, "B again: members already seated stay put")
  end),
})
