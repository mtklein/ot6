-- @manual
-- probe_jidoor.lua -- DIAGNOSTIC probe for the Narshe-mission grind's supply
-- fix: from a plains-grind snapshot (leg 2 of lab_narshe_grind_snap), walk
-- to the Jidoor approach (27,129), enter Jidoor (map 198), enter the item
-- shop (198 (27,41) -> map 201, keeper NPC at (34,15), shop 22), buy a few
-- Potions and Tents, walk back out to the world map, and use a Tent from
-- the world menu.  Every coordinate here is measured, not assumed; the log
-- is the evidence for the generator change.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local TONIC, POTION, FENIX, TENT = 0xE8, 0xE9, 0xF0, 0xF7
local function gil()
  return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16)
end
local function roster(tag)
  local t = {}
  for _, c in ipairs(H.partyMembers()) do
    t[#t + 1] = string.format("c%d %d/%d hp %d/%d mp", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c))
  end
  H.log(string.format("[%s] %s | tonic=%d potion=%d fenix=%d tent=%d gil=%d",
    tag, table.concat(t, "  "), H.invCountOf(TONIC), H.invCountOf(POTION),
    H.invCountOf(FENIX), H.invCountOf(TENT), gil()))
end

local function worldGrind(tx, ty, what)
  local plan, idx = nil, 1
  return H.driveUntil(function()
    return (not H.worldMode()) or (H.worldX() == tx and H.worldY() == ty
      and H.worldHasControl() and H.worldAligned())
  end, 30000, {
    H.call(function()
      if H.battleLoadStarted() then
        plan = nil; H.setPad({ l = true, r = true }); return
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
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

-- Use a Tent from the world menu: X -> main ($05, Item is row 0) -> item
-- list ($08, DP $4B is the bag slot) -> A picks the slot up ($19) -> A on
-- the same slot uses it; the item menu answers a Tent with return code $02,
-- terminates after its fade, and the world module runs the tent event
-- (world_start.asm @02db: VehicleEvent_01), which restores the party.
local function useTent(tag)
  local ph, calm, before, tentAt = 0, 0, nil, nil
  return H.driveUntil(function()
    if before == nil then return false end
    local used = H.invCountOf(TENT) < before
    local back = H.worldMode() and H.readByte(0x59) == 0 and H.worldHasControl()
      and H.worldAligned() and bright() >= 15
    calm = (used and back) and calm + 1 or 0
    return calm >= 20
  end, 4000, {
    H.call(function()
      ph = (ph + 1) % 8
      if before == nil then
        before = H.invCountOf(TENT)
        H.log(string.format("[%s] tents in the bag: %d; opening the world menu at f%d",
          tag, before, H.frame))
      end
      if H.invCountOf(TENT) < before then
        if tentAt == nil then
          tentAt = H.frame
          H.log(string.format("[%s] Tent consumed at f%d (menu state %02X)",
            tag, H.frame, H.readByte(0x26)))
        end
        H.setPad({}); return
      end
      if H.readByte(0x59) == 0 then H.setPad(ph < 4 and { "x" } or {}); return end
      local st, cur = H.readByte(0x26), H.readByte(0x4b)
      if st == 0x05 then
        H.setPad(cur == 0 and (ph < 4 and { "a" } or {}) or { up = true }); return
      end
      local slot = H.invSlotOf(TENT)
      if st == 0x08 then
        if slot == nil then H.setPad({}); return end
        if cur == slot then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({ [cur < slot and "down" or "up"] = true }) end
        return
      end
      if st == 0x19 then
        H.setPad((slot and cur == slot) and (ph < 4 and { "a" } or {}) or (ph < 4 and { "b" } or {}))
        return
      end
      H.setPad({})
    end),
  }, tag)
end

H.run({ maxFrames = 150000 }, {
  H.loadState("build/states/narshe_grind_leg02.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] booted at world (%d,%d) f%d", H.worldX(), H.worldY(), H.frame))
    roster("start")
  end),
  worldGrind(27, 129, "world walk -> the Jidoor approach (27,129)"),
  H.call(function()
    H.log(string.format("[probe] at (%d,%d); stepping DOWN into Jidoor", H.worldX(), H.worldY()))
  end),
  pressWalk("down", function() return not H.worldMode() and map() == 198 end,
    1200, "held DOWN into Jidoor (map 198)"),
  H.waitUntil(function()
    return map() == 198 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "Jidoor control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] Jidoor map %d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    H.screenshot("probe_jidoor_arrive")
  end),
  H.navTo(27, 42, { playBattles = "tactical", maxFrames = 12000,
    arrive = function() return map() == 201 end }),
  pressWalk("up", function() return map() == 201 end, 1200,
    "held UP into the item shop door 198 (27,41) -> map 201"),
  H.waitUntil(function()
    return map() == 201 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "item shop interior control", 5),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] shop interior map %d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    H.screenshot("probe_jidoor_shop")
    roster("before buying")
  end),
  H.shopTalk(34, 15, "Jidoor item shop"),
  H.buyItem(POTION, 0, function() return 5 - H.invCountOf(POTION) end, "POTION to 5 (probe)"),
  H.buyItem(FENIX, 5, function() return 15 - H.invCountOf(FENIX) end, "FENIX DOWN to 15 (probe)"),
  H.buyItem(TENT, 7, function() return 6 - H.invCountOf(TENT) end, "TENT to 6 (probe)"),
  H.call(function() roster("after buying (shop still open)") end),
  H.shopClose("Jidoor item shop"),
  H.call(function() roster("after the shop closed") end),
  H.navTo(34, 20, { playBattles = "tactical", maxFrames = 6000,
    arrive = function() return map() == 198 end }),
  pressWalk("down", function() return map() == 198 end, 1200,
    "held DOWN out of the shop 201 (34,21) -> map 198"),
  H.waitUntil(function()
    return map() == 198 and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 1800, "Jidoor control again", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] back on map %d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),
  H.navTo(15, 62, { playBattles = "tactical", maxFrames = 20000,
    arrive = function() return H.worldMode() end }),
  pressWalk("down", function() return H.worldMode() end, 1200,
    "held DOWN off Jidoor's south edge -> the world"),
  H.waitUntil(function()
    return H.worldHasControl() and H.worldAligned() and bright() >= 15
  end, 2400, "world control", 5),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[probe] back on the world at (%d,%d) f%d", H.worldX(), H.worldY(), H.frame))
    roster("before the Tent")
  end),
  useTent("tent on the world map"),
  H.call(function()
    roster("after the Tent")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c), H.charMaxHp(c), string.format("char %d at full HP after the Tent", c))
    end
    H.screenshot("probe_jidoor_tent")
  end),
  H.logStep(function()
    return string.format("probe_jidoor: shop + Tent measured; world (%d,%d) f%d",
      H.worldX(), H.worldY(), H.frame)
  end),
})
