-- gen_sabin_gau.lua -- leg 10 of SABIN's scenario: GAU.  Mints:
--   gau_joined.mss   world (214,147), Crescent Mountain's doorstep, party
--                    SABIN+CYAN+GAU -- the trench leg steps in from here.
--
-- Every Crescent Mountain helmet-scene variant gates on $01AB (GAU in the
-- party), so the trench cannot open without him.  The route: off the shore
-- (159's y=14 edge row -- its "map 0" long-entrance records return to the
-- PARENT slot, which this chain last pushed at DOMA, so the landing is
-- (240,16), not the record's coords), Mobliz (world (220,115) -> map 157;
-- the item shop 164 via (26,21); keeper (29,48) talked across his counter
-- from (29,50); shop 12 row 0 = DRIED MEAT), then the Veldt grind.
--
-- THE APPEARANCE, measured at battle_main.asm:11940-11960: GAU shows up at
-- the END of a veldt battle -- after every monster dies -- with 3/8 odds
-- (Rand cmp #$a0), party < 4, GAU not yet in the roster ($1EDF bit 3).
-- $2f49/$2f4a arm his character-ai on EVERY veldt battle; $2f4e going
-- nonzero is the appearance itself.
--
-- THE JOIN, and the one concession this leg makes: the first-visit feed --
-- Dried Meat through the battle ITEM menu onto GAU himself -- could not be
-- driven honestly.  Measured across a dozen instrumented runs (probe_gau):
-- the target cursor cycles $01<->$02 and can never land on his $04 because
-- the target-group cells ($7B79..$7B7C) were built before GauAppears and
-- are never rebuilt; aim/cursor/group pokes all still committed the item
-- onto a party slot ($3D48's per-entity last-item cells never showed $FE
-- against him), on the OT6 rom and on the VANILLA base image alike (the
-- A/B run.sh's OT6_ROM override exists for).  So the generator sets $3EBD
-- bit 1 -- the gau-obtained battle switch the feed's reaction would have
-- set (set_battle_switch 13,1; GauAppears branches on it at :11957) -- and
-- lets his RETURN-VISIT script do the join itself: recruit_gau + "I'm Gau!
-- I'm your friend!" + end_veldt, his own AI, no menus.  A meat is still
-- bought so the inventory reads like the playthrough that fed him.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/falls_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local DRIED_MEAT = 0xFE
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end
local function mstateMenu() return H.readByte(0x0026) end
local function inState(s) return function() return mstateMenu() == s end end
local function invSlot(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return i end
  end
  return nil
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[gau] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

local function tapUntil(btn, pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 1500, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { btn } or {})
    end),
  }, what)
end

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    H.assertEq(sw(0x3F), 1, "$003F set -- GAU met at the falls")
    H.assertEq(inParty(11), false, "GAU not yet in the party")
  end),

  -- off the shore, to Mobliz, buy a Dried Meat
  H.navTo(8, 14, { maxFrames = 6000, arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  H.worldNavTo(220, 115, { maxFrames = 40000,
    arrive = function() return not H.worldMode() end }),
  settle(157, "Mobliz"),
  H.navTo(26, 22, { maxFrames = 10000, arrive = function()
    return mapIdx() == 164 end }),
  H.cond(function() return mapIdx() ~= 164 end, {
    H.navTo(26, 21, { maxFrames = 3000, arrive = function()
      return mapIdx() == 164 end }),
  }, {}),
  settle(164, "item shop"),
  H.navTo(29, 50, { maxFrames = 6000 }),
  (function()
    local phase = 0
    return H.driveUntil(function() return mstateMenu() == 0x25 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "shop options open")
  end)(),
  tapUntil("a", inState(0x26), "buy list"),
  H.call(function()
    H.assertEq(H.readByte(0x9d89), DRIED_MEAT, "shop 12 row 0 is Dried Meat")
  end),
  tapUntil("a", inState(0x27), "quantity"),
  tapUntil("a", function()
    return invSlot(DRIED_MEAT) ~= nil and mstateMenu() == 0x26
  end, "bought", 2400),
  tapUntil("b", inState(0x25), "options again"),
  tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
  H.call(function()
    H.assertEq(invSlot(DRIED_MEAT) ~= nil, true, "Dried Meat in the bag")
  end),

  -- out of town; settle the world fully (a stray press during the init
  -- transient walks back in -- measured), then clear of the entrance
  H.navTo(29, 53, { maxFrames = 4000, arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  H.navTo(18, 41, { maxFrames = 8000, arrive = function()
    return H.worldMode() end }),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live again", 5),
  H.worldNavTo(215, 119, { maxFrames = 20000 }),

  -- the grind: kill-bit the trash, keep the gau-obtained bit set, and the
  -- 3/8 end-of-battle roll eventually plays his return visit
  (function()
    local phase, hb, fights, decided = 0, -600, 0, false
    local dirFlip = false
    return H.driveUntil(function() return inParty(11) end, 150000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.frame - hb >= 1800 then
          hb = H.frame
          H.log(string.format("[gau] grind f%d fights=%d 2f4e=%02X",
            H.frame, fights, H.readByte(0x2f4e)))
        end
        if H.battleLoadStarted() then
          pinParty()
          H.writeByte(0x3EBD, H.readByte(0x3EBD) | 0x02)
          if not decided then
            decided = true
            fights = fights + 1
          end
          if H.readByte(0x2f4e) == 0 then
            if H.monstersPresent() > 0 then
              for s = 0, 5 do
                if monPresent(s) then
                  H.writeByte(0x3eec + s * 2,
                    H.readByte(0x3eec + s * 2) | 0x80)
                end
              end
            end
          end
          H.setPad(phase < 4 and { "a" } or {})
          return
        end
        decided = false
        if not H.worldHasControl() then H.setPad({}); return end
        if not H.worldAligned() then return end
        dirFlip = not dirFlip
        H.setPad({ [dirFlip and "left" or "right"] = true })
      end),
    }, "GAU joins the party")
  end)(),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, "world after the join", 5),
  H.waitFrames(120),

  -- park on Crescent Mountain's doorstep (one short of the (214,148)
  -- entrance) and mint; two hops -- the first plan right after the join
  -- scene saw a stale map once (a no-path against measured-open ground)
  H.worldNavTo(216, 128, { maxFrames = 20000 }),
  -- Crescent Mountain's (214,148) entrance sits in a pocket behind the
  -- x=215-219 fence; the route is an S-curve around the south (measured
  -- from a LIVE region dump -- the shore-side dump read a stale $7F
  -- tilemap and drew open sea over these mountains).  Waypoints keep each
  -- BFS disc small: the full search from the plain exhausts worldBfs's
  -- 20000-node cap before it rounds the fence.
  H.worldNavTo(218, 140, { maxFrames = 15000 }),
  H.worldNavTo(220, 149, { maxFrames = 15000 }),
  H.worldNavTo(219, 153, { maxFrames = 8000 }),
  H.worldNavTo(217, 155, { maxFrames = 8000 }),
  H.worldNavTo(212, 156, { maxFrames = 8000 }),
  H.worldNavTo(205, 153, { maxFrames = 8000 }),
  H.worldNavTo(207, 151, { maxFrames = 8000 }),
  H.worldNavTo(214, 149, { maxFrames = 10000 }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world")
    H.assertEq(H.worldX(), 214, "x=214")
    H.assertEq(H.worldY(), 149, "y=149 -- one short of the Crescent entrance")
    H.assertEq(inParty(11), true, "GAU in the party")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq((H.readByte(0x1EDF) & 0x08) ~= 0, true,
      "GAU in the available-characters roster")
    H.log(string.format("[gau_joined] f%d world (%d,%d)", H.frame,
      H.worldX(), H.worldY()))
    H.screenshot("gau_joined")
  end),
  H.saveState("gau_joined.mss"),
  H.logStep(function()
    return string.format("gau_joined minted at frame %d world (%d,%d)",
      H.frame, H.worldX(), H.worldY())
  end),
})
