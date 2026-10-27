-- gen_wor_thamasa_plain.lua -- a branch beside the Gogo arc's third leg (docs/design/route-wor-gogo.md section
-- 10, #484): Continue the `wor-gogo-v1` battery (STRAGO, RELM, GOGO and TERRA on foot on the Falcon's tile by
-- Thamasa, before Ebot's Rock), Thamasa's item counter when the bag is under its band, then the plain around
-- Thamasa on foot until each of its four formations has been won: the shore (world group 56: GloomShell x3 334,
-- Prussian and GloomShell 333) and the plain inside it (group 55: Harpy 331, Harpy and Prussian 332), and back
-- to the Falcon's tile.  No leg boots what it leaves (the state `wor_thamasa_plain`); gen_wor_ebot goes on from
-- the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, STRAGO, RELM, GOGO = 0, 7, 8, 12
local POTION, FENIX, REMEDY, TINCTURE = 0xE9, 0xF0, 0xF5, 0xEB
local NAMES = { [TERRA] = "TERRA", [STRAGO] = "STRAGO", [RELM] = "RELM", [GOGO] = "GOGO" }
local FOUR = { STRAGO, RELM, GOGO, TERRA }
local MAP_THAMASA, MAP_THAMASA_ITEMS, SHOP_ITEMS = 344, 347, 74
local FIGHT = {}
H.NAV_REFIRE_HOLD = true

-- the World of Ruin legs' helpers (lib/ot6_field.lua, H.worLegKit)
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, lv, settled, say, kitLine, watches = K.map, K.lv, K.settled, K.say, K.kitLine, K.watches

-- Thamasa (gen_wor_gogo's): the Falcon on (250,229), the town's door (251,230), kept off on the laps
local THAMASA_DOOR, FALCON = { 251, 230 }, { 250, 229 }

-- ---- Thamasa's item counter, when the bag is under its band ------------------------------------------------
-- gen_wor_gogo's own targets (the counter it stops at before this save): what each buy would add
local function wants()
  local top = H.activeTopLevel()
  return {
    { POTION, math.max(0, H.careStockPotions(top, { spend = 40 }) - H.invCountOf(POTION)), "POTION to the band" },
    { FENIX, math.max(0, math.min(20, top) - H.invCountOf(FENIX)), "FENIX DOWN to the level, capped at 20" },
    { TINCTURE, math.max(0, -(-top // 4) - H.invCountOf(TINCTURE)), "TINCTURE to the band" },
    { REMEDY, math.max(0, 10 - H.invCountOf(REMEDY)), "REMEDY to 10" },
  }
end
local function short()
  for _, w in ipairs(wants()) do if w[2] > 0 then return true end end
  return false
end
local function counter()
  local buys = {}
  for i, w in ipairs(wants()) do
    buys[#buys + 1] = H.buyItem(w[1], function() return wants()[i][2] end, w[3])
  end
  return H.seqStep({
    H.worldNavTo(THAMASA_DOOR[1], THAMASA_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
      arrive = function() return map() == MAP_THAMASA and not H.worldMode() end }),
    H.waitUntil(function() return map() == MAP_THAMASA and settled() end, 2400, "Thamasa: map 344", 1),
    H.crossDoor(26, 37, MAP_THAMASA_ITEMS, 36, 44, "Thamasa's item shop door 344 (26,37) -> 347",
      { fight = FIGHT, avoid = { { 22, 39 }, { 23, 39 } } }),
    H.shopTalk(36, 39, "Thamasa's item shop", { fight = FIGHT }),
    H.call(function() H.assertEq(H.shopId(), SHOP_ITEMS, "the counter opened shop 74 ($0201)") end),
    H.seqStep(buys),
    H.shopClose("Thamasa's item shop"),
    H.bagArrange({ POTION, FENIX, REMEDY, TINCTURE }, { tag = "bag: combat items on top (Thamasa)" }),
    H.call(function() say("shop", "Thamasa") end),
    H.crossDoor(36, 45, MAP_THAMASA, 26, 39, "Thamasa's item shop -> the street", { fight = FIGHT }),
    H.navTo(22, 47, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.driveUntil(function() return H.worldMode() end, 6000, { H.hold({ "down" }), H.waitFrames(4) },
      "off Thamasa's edge"),
    H.release(),
    H.waitWorldSettled("out of Thamasa", 1800, 30),
  })
end

-- ---- the plain ----------------------------------------------------------------------------------------------
-- A world tile's group comes from its sector and its tile kind (WorldBattleGroup); the plain around Thamasa is
-- all sector (7,7), its shore tiles group 56 and the grass and forest inside group 55 (route-wor-gogo.md section
-- 10: the map, from the ROM).  Each lap is a straight run of seven tiles of one group, so its pool is the group's
-- alone, walked until each formation it is there for has been won (the pool's odds: 37.5% or 62.5% a battle),
-- bounded by `budget`: a miss of a 37.5% formation in 20 battles is one draw in 12,000.
local LAPS = {
  { what = "the shore by Thamasa (group 56)", lap = { { 250, 229 }, { 250, 235 } },
    forms = { [333] = "Prussian, GloomShell", [334] = "GloomShell x3" }, budget = 20 },
  { what = "the plain west of Thamasa (group 55)", lap = { { 237, 232 }, { 243, 232 } },
    forms = { [331] = "Harpy", [332] = "Harpy, Prussian" }, budget = 20 },
}
local won = {}
local function wonLine()
  local t = {}
  for _, p in ipairs(LAPS) do
    for f, name in pairs(p.forms) do t[#t + 1] = string.format("%d %s %s", f, name, won[f] and "won" or "-") end
  end
  table.sort(t)
  return table.concat(t, "; ")
end
local function lowest()
  local m = 99
  for _, ch in ipairs(FOUR) do m = math.min(m, lv(ch)) end
  return m
end
-- every outcome since the boot, each read once: a win of any formation counts toward whichever lap wants it
local seen = nil
local function scan(what)
  while seen < #H.outcomes do
    seen = seen + 1
    local o = H.outcomes[seen]
    local f = o.form & 0x1FF
    if o.kind == "won" then won[f] = true end
    H.log(string.format("[plain] %s: formation %d %s after %d ticks; lowest L%d", what, f, o.kind, o.tick or -1,
      lowest()))
  end
end
local function lap(p)
  local wp, n0 = 1, nil
  local function done()
    for f in pairs(p.forms) do if not won[f] then return false end end
    return true
  end
  return H.withReset(H.seqStep({
    H.call(function()
      scan("on the way to " .. p.what)
      n0, wp = #H.outcomes, 1
      say("plain", string.format("%s: lap (%d,%d) <-> (%d,%d); lowest L%d; %s", p.what, p.lap[1][1], p.lap[1][2],
        p.lap[2][1], p.lap[2][2], lowest(), wonLine()))
    end),
    H.driveUntil(function()
      scan(p.what)
      if done() then return not H.battleLoadStarted() and H.worldSettled() end
      H.assertEq(#H.outcomes - n0 < p.budget, true, string.format("%s: every formation it is walked for won within %d "
        .. "battles (%s)", p.what, p.budget, wonLine()))
      return false
    end, 1500000, {
      H.worldNavTo(function() return p.lap[wp][1] end, function() return p.lap[wp][2] end,
        { maxFrames = 20000, playBattles = "tactical", fight = FIGHT, avoid = { THAMASA_DOOR } }),
      H.call(function() wp = wp % 2 + 1 end),
      H.cond(function() return not H.battleLoadStarted() end, { H.fieldCare({ tag = "care on the plain" }) }, {}),
    }, p.what),
    H.call(function() say("plain", string.format("%s: done after %d battles; %s", p.what, #H.outcomes - n0,
      wonLine())) end),
  }), function() wp, n0 = 1, nil end)
end
local function plain()
  local steps = { H.call(function() say("plain", "Thamasa's plain: " .. wonLine()) end) }
  for _, p in ipairs(LAPS) do steps[#steps + 1] = lap(p) end
  steps[#steps + 1] = H.call(function()
    scan("after the laps")
    for _, p in ipairs(LAPS) do
      for f, name in pairs(p.forms) do
        H.assertEq(won[f] == true, true, string.format("Thamasa's plain: formation %d (%s) won", f, name))
      end
    end
  end)
  return H.seqStep(steps)
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("wor-gogo-v1"),
  watches(),
  H.call(function()
    seen = #H.outcomes
    say("wor", "boot")
    H.log("[kit] " .. kitLine(FOUR))
    -- the laps are walked from gen_wor_gogo's save by the Falcon: every lap tile on foot from here, by the
    -- world's own passability
    for _, p in ipairs(LAPS) do
      for _, t in ipairs(p.lap) do
        H.assertEq(H.worldBfs(t[1], t[2]) ~= nil, true, string.format("%s: (%d,%d) on foot from the boot tile "
          .. "(%d,%d), gen_wor_gogo's save by the Falcon", p.what, t[1], t[2], H.worldX(), H.worldY()))
      end
    end
  end),
  -- @@setup-end

  -- ---- 1. Thamasa's counter, the plain -------------------------------------------------------------------
  -- @@stage plain
  H.fieldCare({ threshold = 1.0, tag = "before the plain" }),
  H.cond(short, { counter() }, { H.call(function() say("shop", "the bag at its band: no stop at Thamasa") end) }),
  plain(),

  -- ---- 2. back to the Falcon -----------------------------------------------------------------------------
  -- @@stage back
  H.worldNavTo(FALCON[1], FALCON[2], { maxFrames = 12000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.waitFrames(90),
  H.worldNavTo(FALCON[1], FALCON[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { THAMASA_DOOR } }),
  H.fieldCare({ threshold = 1.0, tag = "by the Falcon" }),
  H.waitUntil(function() return H.worldSettled() and H.worldAligned() end, 1200, "settled by the Falcon", 5),
  H.call(function()
    scan("on the way back")
    say("wor", "by the Falcon")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wor_thamasa_plain.mss"),
  H.logStep(function()
    return string.format("wor_thamasa_plain generated: STRAGO L%d, RELM L%d, GOGO L%d and TERRA L%d by the Falcon "
      .. "at Thamasa, world (%d,%d), Thamasa's plain: %s", lv(STRAGO), lv(RELM), lv(GOGO), lv(TERRA), H.worldX(),
      H.worldY(), wonLine())
  end),
})
