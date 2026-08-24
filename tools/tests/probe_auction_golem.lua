-- probe_auction_golem.lua -- win GOLEM at the Jidoor auction, declining
-- every other lot (#133 item 5).
--
-- probe_jidoor_shop's always-bid ride won Zoneseek but paid 10-20k for
-- junk lots (80k across 7 rounds) and hit the gil floor before Golem
-- drew.  The lots are identified by the announce dialog: after the
-- auctioneer's generic $0AA7 "Here's our next item!", the lot's own dlg
-- follows -- $0AA9 is GOLEM (rides to take_gil 20000 + give_genju),
-- $0AA8?/$0A44 Cherub Down, $0AAA the 1/1200 airship, etc.  The current
-- dialog index is $d0 (field/text.asm:43), so the ride watches it:
-- choices default to DECLINE (row 1: down, then A) until the Golem
-- announce is seen, then bid (row 0: plain A).  A declined lot costs 0.
--
-- Boots from wob_jidoor_done.mss (in Jidoor town, gil 32,737, Zoneseek
-- won).  Stops when the owned-esper count grows or after 14 dry lots.
local H = dofile("tools/tests/lib/ot6.lua")
local function gil() return H.readByte(0x1860) | (H.readByte(0x1861) << 8) | (H.readByte(0x1862) << 16) end
local function espers()
  local n = 0
  for i = 0, 3 do
    local b = H.readByte(0x1a69 + i)
    while b > 0 do n = n + (b & 1); b = b >> 1 end
  end
  return n
end
local function dlgId() return H.readWord(0x00d0) end
local GOLEM_DLG = 0x0AA9
local espers0 = nil
local function mapIs(m) return (H.mapId() & 0x1ff) == m end
local function won() return espers0 ~= nil and espers() > espers0 end

local function bumpIn(i)
  return {
    H.navTo(26, 28, { maxFrames = 9000, playBattles = "flee" }),
    H.driveUntil(function() return mapIs(200) end, 600,
      { H.call(function() H.setPad({ up = true }) end) },
      "lot " .. i .. ": into the Auction House"),
    H.waitFrames(50),
  }
end

local function auctionRound(i)
  local aPhase, sawDlg, calm = 0, false, 0
  local lot, golemLot = nil, false
  return {
    H.navTo(19, 25, { maxFrames = 6000, playBattles = "flee" }),
    H.driveUntil(function() return H.dialogWaiting() end, 1200, {
      H.call(function() H.setPad(H.frame % 16 < 4 and { "up", "a" } or { "up" }) end),
    }, "lot " .. i .. ": auctioneer talks"),
    H.driveUntil(function() return calm >= 90 end, 14000, {
      H.call(function()
        aPhase = (aPhase + 1) % 10
        if H.dialogWaiting() then
          sawDlg = true
          calm = 0
          local d = dlgId()
          if lot == nil and d >= 0x0A42 and d <= 0x0AB6 and d ~= 0x0A41
             and d ~= 0x0AA7 then
            lot = d
            golemLot = (d == GOLEM_DLG)
            H.log(string.format("lot %d announce: dlg $%04X%s", i, d,
              golemLot and " -- GOLEM, bidding!" or " -- declining"))
          end
          if lot == nil or golemLot then
            H.setPad(aPhase < 4 and { "a" } or {})          -- ride/bid: row 0
          else
            -- decline: push the cursor down, then confirm row 1
            if aPhase < 3 then H.setPad({ down = true })
            elseif aPhase < 6 then H.setPad({ a = true })
            else H.setPad({}) end
          end
        else
          if sawDlg and H.hasControl() and not H.eventRunning() then
            calm = calm + 1
          else
            calm = 0
          end
          H.setPad({})
        end
      end),
    }, "lot " .. i .. ": ridden to the end"),
    H.call(function()
      H.log(string.format("lot %d done: gil=%d espers=%d", i, gil(), espers()))
    end),
    H.navTo(18, 25, { maxFrames = 6000, playBattles = "flee" }),
    H.driveUntil(function() return mapIs(198) end, 600,
      { H.call(function() H.setPad({ down = true }) end) },
      "lot " .. i .. ": back to town"),
    H.waitFrames(50),
  }
end
local function flatten(t)
  local out = {}
  for _, v in ipairs(t) do
    if type(v) == "table" and v.tick == nil and v[1] ~= nil then
      for _, s in ipairs(v) do out[#out + 1] = s end
    else out[#out + 1] = v end
  end
  return out
end

local steps = {
  H.loadState("build/states/wob_jidoor_done.mss.lua"),
  H.waitFrames(8),
  H.call(function()
    espers0 = espers()
    H.log(string.format("boot: gil=%d espers=%d", gil(), espers0))
  end),
}
for i = 1, 14 do
  steps[#steps + 1] = H.cond(function() return not won() end,
    flatten({ bumpIn(i), auctionRound(i) }), {})
end
steps[#steps + 1] = H.call(function()
  H.log(string.format("GOLEM RESULT: gil=%d espers %d -> %d (%s)",
    gil(), espers0, espers(), won() and "GOLEM WON" or "not drawn in 14 lots"))
end)
steps[#steps + 1] = H.cond(won, { H.saveState("wob_golem_done.mss") }, {})
steps[#steps + 1] = H.logStep(function() return "done" end)
H.run({ maxFrames = 160000 }, flatten(steps))
