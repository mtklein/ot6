-- @suite savestate=south_figaro
-- shop_buyitem.lua -- #191: H.buyItem resolves its row from the ROM shop
-- table for the shop the counter opened ($0201), checks the drawn list,
-- and refuses a wrong row before any money moves.
--
-- Boots south_figaro (map 75 (1,28), TERRA + LOCKE + EDGAR, gil 2788) and
-- walks into shop 5, the weapon shop, the way probe_sfigshops measured it:
-- doormat (29,19), hold UP into the $F7 door at (29,17) -> map 77
-- (103,16); the merchant stands at (103,9) behind a counter, talked to
-- from two tiles below.  Buys a MithrilBlade ($0A, 450 gil) twice: once
-- with no row given (resolved: row 2), once with the old signature's row 2
-- (verified).  Between the two, a buy asked for on the wrong row and a buy
-- of something the shop does not stock are shown to fail on their first
-- frame with the table quoted, before a button is pressed.
--
-- The dry lookups at the top mirror the row asserts the generators used to
-- carry by hand (gen_narshe_mission, gen_sabin_trench, gen_vector_entry,
-- gen_voyage, gen_zozo1_submerge, probe_nikeah_town): the lib reads the
-- same bytes, so those callers can drop theirs.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function seq(steps) return H.cond(function() return true end, steps) end
local TONIC, POTION, FENIX, TENT = 0xE8, 0xE9, 0xF0, 0xF7
local MITHRIL_BLADE, HEAVY_SHLD = 0x0A, 0x5B

-- map 75's walk-onto transitions to avoid (probe_sfigshops)
local M75_AVOID = {
  { 8, 32 }, { 9, 32 }, { 10, 32 },        -- -> map 80
  { 18, 55 }, { 19, 55 }, { 20, 55 },      -- -> map 91
  { 48, 37 }, { 34, 35 }, { 22, 14 },      -- -> map 86
}

local function settled(n, extra)
  local cnt = 0
  return function()
    local ok = bright() >= 15 and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end
local function settleField(what, dstMap)
  return seq({
    H.waitFrames(60),
    H.advanceStory(settled(20, function()
      return not H.worldMode() and H.tileAligned()
         and not H.battleLoadStarted() and not H.dialogWaiting()
         and (dstMap == nil or map() == dstMap)
    end), 12000, { playBattles = "tactical" }),
    H.waitFrames(30),
  })
end

-- the shop lines the lib logs, for assertions on what it said
local lines = {}
local rawLog = H.log
H.log = function(msg)
  lines[#lines + 1] = tostring(msg)
  return rawLog(msg)
end
local function said(pat)
  for _, l in ipairs(lines) do if l:find(pat, 1, true) then return true end end
  return false
end

local gil0, blades0 = nil, nil

H.run({ maxFrames = 120000 }, {
  H.loadState("build/states/south_figaro.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 75, "booted on map 75, SOUTH FIGARO")
    H.assertEq(H.hasControl(), true, "controllable")
    gil0, blades0 = H.gil(), H.invCountOf(MITHRIL_BLADE)
    H.log(string.format("[shop suite] boot: (%d,%d) gil=%d mithrilblade=%d",
      H.fieldX(), H.fieldY(), gil0, blades0))

    -- the table, read dry: what the generators asserted by hand
    local t, tn = H.shopType(5)
    H.assertEq(tn, "Weapon", "shop 5 is the Weapon shop (type " .. t .. ")")
    t, tn = H.shopType(6)
    H.assertEq(tn, "Armor", "shop 6 is the Armor shop (type " .. t .. ")")
    t, tn = H.shopType(7)
    H.assertEq(tn, "Relics", "shop 7 is the Relics shop (type " .. t .. ")")
    t, tn = H.shopType(22)
    H.assertEq(tn, "Item", "shop 22 (Jidoor) is an Item shop (type " .. t .. ")")
    H.assertEq(H.shopRowOf(5, MITHRIL_BLADE), 2, "shop 5 sells MithrilBlade on row 2")
    H.assertEq(H.shopRowOf(6, HEAVY_SHLD), 1, "shop 6 sells Heavy Shld on row 1")
    H.assertEq(H.shopRowOf(22, POTION), 0, "shop 22 row 0 is Potion")
    H.assertEq(H.shopRowOf(22, FENIX), 5, "shop 22 row 5 is Fenix Down")
    H.assertEq(H.shopRowOf(22, TENT), 7, "shop 22 row 7 is Tent")
    H.assertEq(H.shopRowOf(15, TONIC), 0, "shop 15 row 0 is Tonic")
    H.assertEq(H.shopRowOf(15, POTION), 1, "shop 15 row 1 is Potion")
    H.assertEq(H.shopRowOf(15, FENIX), 5, "shop 15 row 5 is Fenix Down")
    H.assertEq(H.shopRowOf(3, TONIC), 0, "shop 3 row 0 is Tonic")
    H.assertEq(H.shopRowOf(3, POTION), 1, "shop 3 row 1 is Potion")
    H.assertEq(H.shopRowOf(3, FENIX), 4, "shop 3 row 4 is Fenix Down")
    H.assertEq(H.shopRowOf(24, POTION), 0, "shop 24 row 0 is Potion")
    H.assertEq(H.shopRowOf(24, FENIX), 5, "shop 24 row 5 is Fenix Down")
    H.assertEq(H.shopRowOf(5, TONIC), nil, "shop 5 does not sell Tonics")
    local rows = {}
    for r = 0, 7 do
      local id = H.shopStock(5)[r]
      rows[#rows + 1] = id and string.format("$%02X", id) or "--"
    end
    H.log("[shop suite] shop 5 stock from the ROM table: " .. table.concat(rows, " "))
  end),

  -- ---- into shop 5 -----------------------------------------------------
  H.navTo(29, 19, { maxFrames = 30000, playBattles = "tactical", avoid = M75_AVOID }),
  H.release(), H.waitFrames(20),
  H.call(function()
    H.assertEq(H.fieldX() == 29 and H.fieldY() == 19, true, "on the weapon shop's doormat (29,19)")
  end),
  H.driveUntil(function() return map() == 77 end, 1800, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "hold UP into the weapon shop door"),
  H.release(),
  settleField("inside the weapon shop", 77),
  H.call(function() H.assertEq(map(), 77, "inside map 77") end),
  H.shopTalk(103, 9, "shop 5 (weapon)"),
  H.call(function()
    H.assertEq(H.readByte(0x0026), 0x25, "the shop's options window is up")
    H.assertEq(H.shopId(), 5, "the counter opened shop 5 ($0201)")

    -- the refusals, on their first frame, with nothing pressed
    local wrong = H.buyItem(MITHRIL_BLADE, 0, 1, "MithrilBlade on row 0 (wrong)")
    local ok, err = pcall(wrong.tick)
    H.log("[shop suite] wrong row: " .. tostring(err))
    H.assertEq(ok, false, "a wrong row is refused")
    H.assertEq(tostring(err):find("row 0 was asked for, but shop 5 (Weapon) sells $0A on row 2", 1, true) ~= nil,
      true, "and the refusal names the asked row, the shop and the real row")
    local none = H.buyItem(TONIC, 1, "Tonic at the weapon shop")
    ok, err = pcall(none.tick)
    H.log("[shop suite] not stocked: " .. tostring(err))
    H.assertEq(ok, false, "an item the shop does not stock is refused")
    H.assertEq(tostring(err):find("shop 5 (Weapon) does not sell item $E8", 1, true) ~= nil,
      true, "and the refusal says so with the rows")
    H.assertEq(H.readByte(0x0026), 0x25, "still on the options window: nothing was pressed")
    H.assertEq(H.gil(), gil0, "and no gil moved")
  end),

  -- ---- the two purchases ------------------------------------------------
  H.buyItem(MITHRIL_BLADE, function() return 1 end, "MithrilBlade (row resolved)"),
  H.buyItem(MITHRIL_BLADE, 2, 1, "MithrilBlade (row 2, as asked)"),
  H.shopClose("shop 5 (weapon)"),
  H.call(function()
    H.log(string.format("[shop suite] after the shop: gil=%d mithrilblade=%d", H.gil(),
      H.invCountOf(MITHRIL_BLADE)))
    H.assertEq(H.invCountOf(MITHRIL_BLADE), blades0 + 2, "two MithrilBlades in the bag")
    H.assertEq(gil0 - H.gil(), 900, "and 2 x 450 gil paid")
    H.assertEq(said("MithrilBlade (row resolved): shop 5 (Weapon) row 2 = $0A on the ROM table; buying 1"),
      true, "the resolved purchase line names shop, type, row and id")
    H.assertEq(said("MithrilBlade (row 2, as asked): shop 5 (Weapon) row 2 = $0A on the ROM table, as asked; buying 1"),
      true, "the verified purchase line says the row was asked for")
    H.assertEq(said("MithrilBlade (row resolved): the drawn list's row 2 shows $0A too"),
      true, "the drawn list was checked")
    H.assertEq(said("MithrilBlade (row resolved): bought 1 x $0A from shop 5 (Weapon) row 2"),
      true, "and the purchase was logged with both")
  end),
})
