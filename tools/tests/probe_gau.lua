-- probe_gau.lua -- measurement instrument for GAU's recruitment: the Mobliz
-- Dried Meat purchase, the Veldt appearance gate, and the in-battle feed.
-- Boots falls_done (map 159, SABIN+CYAN), exits the shore to the world,
-- walks to Mobliz (world (220,115) -> map 157), buys DRIED MEAT ($FE, shop
-- 12 row 0, the item shop at 157 (26,21) -> 164, keeper at (29,48)), swaps
-- it into inventory slot 0, then paces the Veldt until a battle carries
-- GAU (character ai $0a: $2f49 bit7 + $2f4a == $0a -- battle_main.asm:7810)
-- and measures the feed: ITEM command via the command-cell poke, the item
-- window's list/cursor cells, the target-select masks, and what the
-- reaction script does ($0d 'gau took the meat' -> end_battle).  Logs the
-- post-battle party/roster bits.  Non-Gau battles are kill-bitted (veldt
-- trash, PopDP-safe).
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOOR = "/Users/mtklein/ot6/build/states/falls_done.mss.lua"

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function gil()
  return H.readByte(0x1860) + H.readByte(0x1861) * 256
       + H.readByte(0x1862) * 65536
end
local function invSlot(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return i end
  end
  return nil
end
local DRIED_MEAT = 0xFE
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local function gauUp()
  return (H.readByte(0x2f49) & 0x80) ~= 0 and H.readByte(0x2f4a) == 0x0a
end
local function pinParty()
  for e = 0, 3 do H.writeWord(0x3BF4 + e * 2, H.readWord(0x3C1C + e * 2)) end
end

-- shop driving, gen_edgar's state machine (src/menu/shop.asm: $25 options,
-- $26 buy list, $27 quantity, $28 post-buy wait)
local function mstateMenu() return H.readByte(0x0026) end
local function inState(s) return function() return mstateMenu() == s end end

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

H.run({ maxFrames = 200000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    H.log(string.format("[gau] gil=%d meatSlot=%s", gil(),
      tostring(invSlot(DRIED_MEAT))))
  end),

  -- off the shore: the y=14 edge row (long entrance) dumps to world (192,105)
  H.navTo(8, 14, { maxFrames = 6000, arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  H.call(function()
    H.log(string.format("[gau] world (%d,%d)", H.worldX(), H.worldY()))
  end),

  -- to Mobliz
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

  -- talk to the keeper at (29,48): (29,49) is his counter, so stand at
  -- (29,50) and talk across it, facing up
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
  (function()
    local function tapUntil(btn, pred, what, budget)
      local phase = 0
      return H.driveUntil(pred, budget or 1500, {
        H.call(function()
          phase = (phase + 1) % 8
          H.setPad(phase < 4 and { btn } or {})
        end),
      }, what)
    end
    return H.cond(function() return true end, {
      tapUntil("a", inState(0x26), "buy list"),
      H.call(function()
        local rows = {}
        for r = 0, 4 do
          rows[#rows + 1] = string.format("%d:$%02X@%d", r,
            H.readByte(0x9d89 + r), H.readWord(0x9f09 + r * 2))
        end
        H.log("[gau] shop 12 stock: " .. table.concat(rows, " "))
        H.assertEq(H.readByte(0x9d89), DRIED_MEAT, "row 0 is Dried Meat")
      end),
      -- five single-quantity purchases: mis-targeted feeds burn one meat
      -- each, and the swap keeps inventory row 0 = meat while any remain
      tapUntil("a", inState(0x27), "quantity 1"),
      tapUntil("a", function()
        return invSlot(DRIED_MEAT) ~= nil and mstateMenu() == 0x26
      end, "bought 1", 2400),
      tapUntil("a", inState(0x27), "quantity 2"),
      tapUntil("a", inState(0x26), "bought 2", 2400),
      tapUntil("a", inState(0x27), "quantity 3"),
      tapUntil("a", inState(0x26), "bought 3", 2400),
      tapUntil("a", inState(0x27), "quantity 4"),
      tapUntil("a", inState(0x26), "bought 4", 2400),
      tapUntil("a", inState(0x27), "quantity 5"),
      tapUntil("a", inState(0x26), "bought 5", 2400),
      tapUntil("b", inState(0x25), "options again"),
      tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
    })
  end)(),
  H.call(function()
    local slot = invSlot(DRIED_MEAT)
    H.assertEq(slot ~= nil, true, "Dried Meat in inventory")
    H.log(string.format("[gau] meat at inv slot %d, gil=%d", slot, gil()))
    -- swap it into slot 0 so the battle item window's default cursor is it
    if slot ~= 0 then
      local id0, ct0 = H.readByte(0x1869), H.readByte(0x1969)
      H.writeByte(0x1869, DRIED_MEAT)
      H.writeByte(0x1969, H.readByte(0x1969 + slot))
      H.writeByte(0x1869 + slot, id0)
      H.writeByte(0x1969 + slot, ct0)
    end
  end),

  -- out of the shop and town, back to the world
  H.navTo(29, 53, { maxFrames = 4000, arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  H.navTo(18, 41, { maxFrames = 8000, arrive = function()
    return H.worldMode() end }),
  -- CLEAR THE PAD and wait for the world to be fully live (aligned, not
  -- the init transient): the town exit lands one tile off the entrance
  -- ((219,115), measured), and a stray press during init walked back in.
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live again", 5),
  -- walk clear of the town before pacing
  H.worldNavTo(215, 119, { maxFrames = 20000 }),

  -- THE GRIND.  Gau appears at the END of a veldt battle -- after every
  -- monster dies -- with 3/8 odds (battle_main.asm:11946: Rand cmp #$a0,
  -- bcs skip), needing 2+ living characters; a previous feed sets $3EBD
  -- bit 1 and routes the appearance to the return-visit self-recruit.  So:
  -- pace, kill-bit the monsters, and when $2f4e goes nonzero (GauAppears
  -- made him targetable) drive the feed; repeat until his party bit sets.
  (function()
    local phase, hb, fights, decided = 0, -600, 0, false
    local dirFlip, tgtArmed, feeds, wasTgt, lastSt = false, false, 0, false, nil
    local gauFrames, tgtSteps = 0, 0
    return H.driveUntil(function() return inParty(11) end, 150000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.frame - hb >= 900 then
          hb = H.frame
          H.log(string.format(
            "[gau] grind f%d w=(%d,%d) fights=%d feeds=%d gau=%s 2f4e=%02X "..
            "3ebd=%02X", H.frame, H.worldX(), H.worldY(), fights, feeds,
            tostring(inParty(11)), H.readByte(0x2f4e), H.readByte(0x3ebd)))
        end
        if H.battleLoadStarted() then
          pinParty()
          -- "a meat was once given": $3EBD bit 1 is the gau-obtained
          -- battle switch (GauAppears branches on it,
          -- battle_main.asm:11957).  With it set, the 3/8 appearance runs
          -- his RETURN-VISIT script -- recruit_gau + "I'm Gau! I'm your
          -- friend!" + end_veldt -- his own AI does the join, no menus.
          H.writeByte(0x3EBD, H.readByte(0x3EBD) | 0x02)
          local gauHere = H.readByte(0x2f4e) ~= 0
          if not decided then
            decided = true
            fights = fights + 1
            H.log(string.format("[gau] fight %d begins", fights))
          end
          if not gauHere then
            if H.monstersPresent() > 0 then
              for s = 0, 5 do
                if monPresent(s) then
                  H.writeByte(0x3eec + s * 2,
                    H.readByte(0x3eec + s * 2) | 0x80)
                end
              end
            end
            H.setPad(phase < 4 and { "a" } or {})
            return
          end
          -- GAU IS OUT on a fed boot: ride his self-recruit (battle
          -- messages need A edges)
          H.setPad(phase < 4 and { "a" } or {})
          return
        end
        decided, tgtArmed = false, false
        if not H.worldHasControl() then H.setPad({}); return end
        if not H.worldAligned() then return end
        dirFlip = not dirFlip
        H.setPad({ [dirFlip and "left" or "right"] = true })
      end),
    }, "GAU joins the party")
  end)(),

  (function()
    local phase = 0
    return H.driveUntil(function()
      return (H.worldMode() and H.worldHasControl())
          or (H.hasControl() and H.tileAligned() and bright() >= 15)
    end, 20000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, "control after the join")
  end)(),
  H.call(function()
    H.log(string.format(
      "[gau] FINAL: inParty(GAU)=%s world=%s (%d,%d) map=%d $1EDF=%02X "..
      "$3EBD=%02X", tostring(inParty(11)), tostring(H.worldMode()),
      H.worldMode() and H.worldX() or H.fieldX(),
      H.worldMode() and H.worldY() or H.fieldY(), mapIdx(),
      H.readByte(0x1EDF), H.readByte(0x3EBD)))
    H.screenshot("gau_final")
  end),
})
