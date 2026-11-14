-- gen_wob_auction.lua -- a branch beside the Sealed Gate mission (#284, docs/design/wob-towns-boxes.md section 3):
-- Continue the `narshe-mission-v1` battery (the v0.6 four outside Narshe, the Blackjack two tiles south), fly to
-- Jidoor and sit in on the Auction House (map 200, the auctioneer's clerk NPC_12 at (19,24), _cb4e47) until both
-- magicite it sells in the World of Balance have been bought: Golem (20000 GP) and ZoneSeek (10000 GP)
-- (docs/design/magicite.md:74-75).  The clerk opens the auction only once $006B is set (the Blackjack's rejoin
-- after the factory escape, event_main.asm:97000; before it, "Today's auction is over."), and each sitting offers
-- one lot, drawn at random (_cb4ecc): the Golem lot only while $016D is clear, the ZoneSeek lot only while $016C
-- is clear.  The party bids on those two and passes on the rest; $01F0 (a sitting held) clears with the next map
-- load, so a visit is out to the street and back in.  No leg boots what it leaves (the state `wob_auction`);
-- gen_water_rondo goes on from the same save.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, SETZER = 1, 4, 5, 9
local NAMES = { [LOCKE] = "LOCKE", [EDGAR] = "EDGAR", [SABIN] = "SABIN", [SETZER] = "SETZER" }
local MAP_JIDOOR, MAP_AUCTION = 198, 200
local JIDOOR_DOOR = { 27, 130 }
local GOLEM_SW, ZONESEEK_SW = 0x016D, 0x016C
local BUDGET = 40                        -- sittings: the Golem lot is drawn 1 in 8, ZoneSeek's 1 in 16 at worst
local FIGHT = { tactical = true, boost = true, items = true, healPercent = 50 }
H.NAV_REFIRE_HOLD = true
local K = H.worLegKit({ fight = FIGHT, links = {}, names = NAMES })
local map, say, sw, settled = K.map, K.say, K.sw, K.settled

local function shipX() return H.readWord(0x34) >> 4 end
local function shipY() return H.readWord(0x38) >> 4 end
local function strafe(txf, tyf)
  local calm = 0
  return H.withReset(H.driveUntil(function()
    calm = (shipX() == txf() and shipY() == tyf()) and calm + 1 or 0
    return calm >= 90
  end, 20000, {
    H.call(function()
      local dx, dy = txf() - shipX(), tyf() - shipY()
      if dx == 0 and dy == 0 then H.setPad({}); return end
      local pad = { y = true }
      if dx > 0 then pad.right = true elseif dx < 0 then pad.left = true end
      if dy > 0 then pad.down = true elseif dy < 0 then pad.up = true end
      H.setPad(pad)
    end),
  }, "strafe-fly to Jidoor"), function() calm = 0 end)
end

-- the lots: the bid prompts by dialog (event_main.asm _cb5197, _cb5312): Golem's 15000 then 20000, ZoneSeek's
-- 7000 then 10000 ($0A5B, the 10000 prompt, is also Cherub Down's second, so the lot is the first prompt's)
local GOLEM_ASK = { [0x0A58] = true, [0x0A5E] = true }
local ZONESEEK_FIRST = 0x0A55
local lot, lots = nil, {}
local function rowFor(dlg)
  if dlg == 0x0A41 then return 0 end                       -- "(Bid on items!)"
  if GOLEM_ASK[dlg] then lot = "Golem"; return 0 end
  if dlg == ZONESEEK_FIRST then lot = "ZoneSeek"; return 0 end
  if dlg == 0x0A5B and lot == "ZoneSeek" then return 0 end
  if lot == nil then lot = dlg == 0x0A51 and "Cherub Down" or string.format("a lot first asked with dlg $%04X", dlg) end
  return 1                                                 -- "I'll pass..."
end

local function sitting(n)
  local g0 = nil
  return H.cond(function() return sw(GOLEM_SW) == 0 or sw(ZONESEEK_SW) == 0 end, {
    H.call(function() lot, g0 = nil, H.gil() end),
    -- the clerk across his counter from (19,25), facing up (lab auct1: K.talkNpc's own story drive answered the
    -- auction's prompts itself, every one on row 0)
    H.navTo(19, 25, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
    H.faceAndHoldA("up", function() return H.dialogWaiting() end, 900, "the auction clerk (200 NPC_12), sitting " .. n),
    H.release(),
    H.dialogChoice(function(dlg) return rowFor(dlg) end, {
      inBattle = false, ready = "count", on = 3, maxFrames = 20000, tag = "the auction, sitting " .. n,
      -- the sitting is over when the field has the party back (the lot's prompts come one after another, with
      -- the auctioneer's lines between them; a "dialog closed" moment is not the end)
      done = function(C) return C.resolved >= 2 and not H.dialogWaiting() and H.hasControl() and not H.eventRunning() end,
    }),
    H.advanceStory(function() return settled() end, 6000, {}),
    H.call(function()
      lots[#lots + 1] = lot or "-"
      H.log(string.format("[auction] sitting %d: lot %s; gil %d -> %d; Golem $016D=%d, ZoneSeek $016C=%d", n,
        tostring(lot), g0, H.gil(), sw(GOLEM_SW), sw(ZONESEEK_SW)))
    end),
    K.walkInto(18, 26, MAP_JIDOOR, "the Auction House -> Jidoor"),
    H.crossDoor(26, 27, MAP_AUCTION, 18, 25, "Jidoor 198 (26,27) -> the Auction House 200 (18,25)", { fight = FIGHT }),
  }, {})
end

local gil0 = nil
local steps = {
  H.bootCheckpoint("narshe-mission-v1"),
  K.watches(),
  H.call(function()
    say("wob", "boot")
    gil0 = H.gil()
    H.assertEq(sw(0x006B), 1, "$006B set: the Blackjack rejoined after the factory (the auction opens on it)")
    H.assertEq(sw(GOLEM_SW) == 0 and sw(ZONESEEK_SW) == 0, true, "neither Golem nor ZoneSeek bought yet")
    H.assertEq(gil0 >= 30000, true, string.format("30000 GP for the two lots (the bag holds %d)", gil0))
  end),
  -- @@setup-end

  -- @@stage fly
  H.fieldCare({ threshold = 1.0, tag = "outside Narshe" }),
  H.worldNavTo(function() return H.readByte(0x1F62) end, function() return H.readByte(0x1F63) end,
    { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.waitFrames(30),
  H.withReset((function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and H.readByte(0xe0) == 0 and H.readByte(0xe2) == 0 end,
      1800, { H.call(function() ph = (ph + 1) % 16; H.setPad(ph < 4 and { "a" } or {}) end) },
      "A on the Blackjack's tile: liftoff (the flight view zeroes $E0/$E2)")
  end)(), function() end),
  H.release(),
  H.waitFrames(240),
  strafe(function() return 27 end, function() return 132 end),
  H.release(),
  H.waitFrames(60),
  H.pressButtons({ "b" }, 8),
  H.waitUntil(function() return H.worldX() == 27 and H.worldY() == 132 and H.worldSettled() end, 1800,
    "the Blackjack grounds below Jidoor (27,132)", 10),
  H.waitFrames(60),
  H.worldNavTo(JIDOOR_DOOR[1], JIDOOR_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_JIDOOR and not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_JIDOOR and settled() end, 2400, "Jidoor: map 198", 1),
  H.crossDoor(26, 27, MAP_AUCTION, 18, 25, "Jidoor 198 (26,27) -> the Auction House 200 (18,25)", { fight = FIGHT }),
  -- @@stage auction
}
for n = 1, BUDGET do steps[#steps + 1] = sitting(n) end
for _, s in ipairs({
  H.call(function()
    H.log("[auction] the lots, in order: " .. table.concat(lots, ", "))
    H.assertEq(sw(GOLEM_SW), 1, string.format("Golem bought within %d sittings", BUDGET))
    H.assertEq(sw(ZONESEEK_SW), 1, string.format("ZoneSeek bought within %d sittings", BUDGET))
    H.assertEq(gil0 - H.gil(), 30000, "the two lots cost 30000 GP")
    say("wob", "the auction done")
  end),
  K.walkInto(18, 26, MAP_JIDOOR, "the Auction House -> Jidoor"),
  H.saveState("wob_auction.mss"),
  H.logStep(function()
    return string.format("wob_auction generated: Jidoor map %d (%d,%d), Golem and ZoneSeek bought in %d sittings "
      .. "(%s), gil %d", map(), H.fieldX(), H.fieldY(), #lots, table.concat(lots, ", "), H.gil())
  end),
}) do steps[#steps + 1] = s end
H.run({ maxFrames = 900000 }, steps)
