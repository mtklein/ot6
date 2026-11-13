-- gen_wob_kohlingen.lua -- a branch beside the search for TERRA (#284, docs/design/wob-side-trips.md section 3):
-- boot `figaro_submerged` (LOCKE, CELES, EDGAR and SABIN in the engine room, the castle parked west by Kohlingen),
-- out of the castle as gen_zozo2_arrival goes, and into Kohlingen (world (26,39) -> map 188), the town the route
-- walks past: its two chests (the Green Beret, 195 (37,53), and the Elixir, 197 (42,10); treasure bits 65 and 69,
-- the same chests the World of Ruin's Kohlingen offers, so a player who opens them here finds them empty there),
-- its general store's three counters (map 194; their stock is logged), and SHADOW at the inn (map 191 NPC_1 at
-- (25,15), _cc6f84): "Say, oh...3000 GP.  Buy SHADOW's help?"  He is hired when the bag holds 3000 GP.  No leg boots
-- what it leaves (the state `wob_kohlingen`); gen_zozo2_arrival goes on from figaro_submerged.
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, SHADOW, EDGAR, SABIN, CELES = 1, 3, 4, 5, 6
local NAMES = { [LOCKE] = "LOCKE", [SHADOW] = "SHADOW", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [CELES] = "CELES" }
local FOUR = { LOCKE, CELES, EDGAR, SABIN }
local MAP_KOHLINGEN, MAP_INN, MAP_STORE, MAP_K_HOUSE, MAP_K_WEST = 188, 191, 194, 195, 197
local KOHLINGEN_DOOR = { 26, 39 }
local CASTLE_AVOID = { { 30, 48 }, { 31, 48 } }
local GREEN_BERET, ELIXIR = 0x72, 0xEE
local HIRE = 3000
local OBJ_SHADOW = 0x10                  -- 191 NPC_1, (25,15), shown by $0651
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, kitLine, sw, settled, inParty = K.map, K.say, K.kitLine, K.sw, K.settled, K.inParty
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

local function landed(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned() and bright() >= 15 and not H.battleLoadStarted()
      and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 20)
  end
end
-- gen_zozo2_arrival's door: walk to it, hold into it until the map changes
local function door(nx, ny, dir, m, what)
  return H.seqStep({
    H.navTo(nx, ny, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.driveUntil(function() return map() == m end, 900, { H.hold({ dir }), H.waitFrames(4) }, what .. ": the door"),
    H.advanceStory(landed(m, 10), 2400, { playBattles = "tactical", fight = FIGHT }),
    H.waitFrames(150),
  })
end
-- a counter's stock, logged by name, then closed (nothing bought: the branch records what Kohlingen sells)
local function counter(x, y, what)
  return H.seqStep({
    H.shopTalk(x, y, what, { fight = FIGHT }),
    H.call(function()
      local ids, stock = {}, H.shopStock(H.shopId())
      for r = 0, 7 do if stock[r] then ids[#ids + 1] = string.format("$%02X", stock[r]) end end
      local _, kind = H.shopType(H.shopId())
      H.log(string.format("[shop] %s: shop %d (%s) sells %s", what, H.shopId(), kind, table.concat(ids, " ")))
    end),
    H.shopClose(what),
  })
end

local gil0, hired, answers = nil, false, {}
H.run({ maxFrames = 500000 }, {
  H.loadState("build/states/figaro_submerged.mss.lua"),
  K.watches(),
  H.call(function()
    H.assertEq(map(), 61, "booted in the engine room (map 61; gen_zozo1_submerge's state)")
    H.assertEq(sw(0x010C), 1, "$010C: the castle parked west")
    H.assertEq(sw(0x0651), 1, "SHADOW waits at Kohlingen's inn ($0651; hidden once the opera starts)")
    say("wob", "boot")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  -- @@setup-end

  -- ---- 1. out of the castle (gen_zozo2_arrival's doors) --------------------------------------------------
  -- @@stage castle
  H.navTo(11, 32, { arrive = function() return map() == 59 end, maxFrames = 9000, playBattles = "tactical",
    fight = FIGHT }),
  H.waitUntil(landed(59, 10), 1500, "keep hall", 1),
  H.waitFrames(150),
  door(12, 42, "up", 55, "keep -> the gate map"),
  door(28, 31, "down", 59, "terrace -> vestibule"),
  door(12, 49, "down", 55, "vestibule -> gate yard"),
  H.navTo(28, 42, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
  H.driveUntil(function() return H.worldMode() end, 900, { H.hold({ "down" }), H.waitFrames(4) },
    "off the castle to the world"),
  H.release(),
  H.waitWorldSettled("world control", 1500),
  H.call(function() say("wob", "off the castle") end),

  -- ---- 2. Kohlingen ---------------------------------------------------------------------------------------
  -- @@stage kohlingen
  H.fieldCare({ threshold = 0.9, tag = "by the castle" }),
  H.worldNavTo(KOHLINGEN_DOOR[1], KOHLINGEN_DOOR[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT,
    avoid = CASTLE_AVOID, arrive = function() return not H.worldMode() end }),
  H.waitUntil(landed(MAP_KOHLINGEN, 10), 2400, "Kohlingen: map 188", 5),
  H.call(function() say("kohlingen", "in town") end),
  H.fieldCare({ threshold = 0.9, tag = "in Kohlingen" }),
  H.crossDoor(26, 4, MAP_K_HOUSE, 38, 53, "Kohlingen house door 188(26,4)->195(38,53)", { fight = FIGHT }),
  K.chestAt(37, 53, 65, "Green Beret", GREEN_BERET),
  K.walkInto(38, 51, MAP_KOHLINGEN, "the house -> Kohlingen"),
  H.crossDoor(4, 7, MAP_K_WEST, 39, 18, "Kohlingen west house door 188(4,7)->197(39,18)", { fight = FIGHT }),
  K.chestAt(42, 10, 69, "Elixir", ELIXIR),
  K.walkInto(39, 19, MAP_KOHLINGEN, "the west house -> Kohlingen"),
  H.call(function() say("kohlingen", "the chests") end),

  -- ---- 3. the general store ------------------------------------------------------------------------------
  -- @@stage store
  H.crossDoor(11, 11, MAP_STORE, 12, 39, "Kohlingen store door 188(11,11)->194(12,39)", { fight = FIGHT }),
  counter(9, 35, "Kohlingen's weapon counter"),
  counter(15, 35, "Kohlingen's armor counter"),
  counter(19, 35, "Kohlingen's item counter"),
  K.walkInto(12, 40, MAP_KOHLINGEN, "the store -> Kohlingen"),

  -- ---- 4. SHADOW at the inn ------------------------------------------------------------------------------
  -- @@stage shadow
  H.crossDoor(16, 22, MAP_INN, 17, 20, "Kohlingen inn door 188(16,22)->191(17,20)", { fight = FIGHT }),
  H.call(function()
    gil0 = H.gil()
    say("inn", string.format("SHADOW at (%d,%d); %d GP in the bag, his price %d", H.objX(OBJ_SHADOW),
      H.objY(OBJ_SHADOW), gil0, HIRE))
    local t = {}
    for o = 0, 15 do t[#t + 1] = string.format("%d:%02X", o, H.readByte(0x0867 + 0x29 * o)) end
    H.log(string.format("[inn] active party %d; objects' party bytes %s; SHADOW's record party byte $%02X",
      H.readByte(0x1A6D), table.concat(t, " "), H.readByte(0x1850 + SHADOW)))
  end),
  -- His talk (_cc6f84, $000B set: "We meet again...") runs _cac5c1's party check before it names a price: SHADOW
  -- already counted in the active party ($01A3, set_case PARTY_CHARS) answers "Leave me alone..." (dlg $03E5);
  -- else "Say, oh...3000 GP. Buy SHADOW's help?" (dlg $03E7) and Yes.  The leg answers whichever comes, and says
  -- which (labs kohl4-kohl6: the refusal, with $1EB4 reading $78 after the check, SHADOW's bit set, where the
  -- objects' party bytes read him out of the party just before the talk).
  H.cond(function() return H.gil() >= HIRE end, {
    H.talkToObj(OBJ_SHADOW, "SHADOW at the inn (191 NPC_1)", 12000, function() return H.dialogWaiting() end),
    (function()
      local lastDlg = nil
      return H.withReset(H.dialogChoice(0, { inBattle = false, what = "Buy SHADOW's help? (Yes)",
        tag = "SHADOW's price", ready = "count", on = 3, maxFrames = 6000,
        done = function() return lastDlg ~= nil and not H.dialogWaiting() and H.hasControl() and not H.eventRunning() end,
        idle = function(ph)
          if H.dialogWaiting() then
            local d = H.readWord(0x00D0)
            if d ~= lastDlg then
              lastDlg = d
              answers[#answers + 1] = string.format("$%04X", d)
              H.log(string.format("[inn] dialog $%04X; the party check $1EB4=%02X (active party %d)", d,
                H.readByte(0x1EB4), H.readByte(0x1A6D)))
            end
            H.setPad(ph < 3 and { "a" } or {})
          else
            H.setPad({})
          end
        end }), function() lastDlg = nil end)
    end)(),
    H.advanceStory(function() return settled() end, 6000, {}),
    H.call(function()
      hired = inParty(SHADOW)
      if hired then
        H.assertEq(gil0 - H.gil(), HIRE, "SHADOW's help cost 3000 GP")
        say("inn", "SHADOW hired: " .. kitLine({ SHADOW }))
      else
        H.assertEq(H.gil(), gil0, "no gil spent when SHADOW refuses")
        say("inn", "SHADOW refused (dialogs " .. table.concat(answers, " ") .. ")")
      end
    end),
  }, {
    H.call(function() say("inn", "under 3000 GP: SHADOW stays at the inn") end),
  }),
  K.walkInto(17, 21, MAP_KOHLINGEN, "the inn -> Kohlingen"),
  H.call(function()
    say("wob", "Kohlingen done")
    H.log("[kit] " .. kitLine(FOUR))
  end),
  H.saveState("wob_kohlingen.mss"),
  H.logStep(function()
    return string.format("wob_kohlingen generated: map %d (%d,%d), LOCKE L%d CELES L%d EDGAR L%d SABIN L%d, "
      .. "SHADOW %s, gil %d", map(), H.fieldX(), H.fieldY(), K.lv(LOCKE), K.lv(CELES), K.lv(EDGAR), K.lv(SABIN),
      hired and string.format("hired (L%d)", K.lv(SHADOW)) or "not hired", H.gil())
  end),
})
