-- gen_wor_terra.lua -- the World of Ruin from the Falcon to TERRA: Continue
-- the `wor-falcon-v1` battery (CELES, SABIN, EDGAR and SETZER on foot beside
-- the landed Falcon, world (25,160)), board, fly to Mobliz and land beside
-- it, meet the children and TERRA in the cellar, Phunbaba's first visit
-- (event battles 128 and 129), Fenrir, Katarin's flight, Phunbaba's return
-- (event battles 130 and 131: TERRA joins), and save beside the Falcon:
-- the `wor-terra-v1` battery.
-- docs/design/route-wor-terra.md has the plan and what this measured.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, CELES, SABIN, EDGAR, SETZER = 0, 6, 5, 4, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE
local MAP_MOBLIZ, MAP_SHELTER, MAP_CELLAR, MAP_KATARIN, MAP_HOUSE = 158, 165, 154, 150, 163
local MOBLIZ_DOOR = { 237, 135 }
local LANDING = { 238, 135 }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function inParty(ch) return partyOf(ch) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local MEMBERS = { { TERRA, "TERRA" }, { CELES, "CELES" }, { SABIN, "SABIN" }, { EDGAR, "EDGAR" },
  { SETZER, "SETZER" } }
local function supplies()
  return string.format("tonic=%d potion=%d xpotion=%d ether=%d elixir=%d fenix=%d remedy=%d soft=%d revivify=%d tent=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(XPOTION), H.invCountOf(ETHER), H.invCountOf(ELIXIR),
    H.invCountOf(FENIX), H.invCountOf(REMEDY), H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(TENT), H.gil())
end
local function member(ch, name)
  return string.format("%s(p%d) L%d HP %d/%d MP %d/%d status1 $%02X", name, partyOf(ch), level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then t[#t + 1] = member(p[1], p[2]) end end
  return table.concat(t, "; ")
end
local function kitLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do t[#t + 1] = p[2] .. " " .. kit(p[1]) end
  return "kit " .. table.concat(t, ", ")
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end

local FIGHT = {}
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
end
local function walkInto(x, y, dst, what, opts)
  opts = opts or {}
  local function there() return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15 end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = opts.avoid,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.waitUntil(there, 1200, what .. ": control on map " .. dst, 1),
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end
-- walk onto a trigger tile: the walk ends when its event takes the party
-- (or the flag it sets reads set); the ride after it answers the event
local function stepOn(x, y, done)
  return H.navTo(x, y, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = function()
    return done() or H.battleLoadStarted() or (H.fieldX() == x and H.fieldY() == y
      and (H.eventRunning() or H.dialogWaiting() or not H.hasControl()))
  end })
end
local function ride(pred, maxF, what, opts)
  opts = opts or {}
  return H.seqStep({
    H.advanceStory(function() return pred() and settled() end, maxF, {
      playBattles = "tactical", fight = opts.fight or FIGHT, wipeEndsRide = opts.wipeEndsRide }),
    H.call(function() say("story", what) end),
  })
end

-- boarding: on foot on the parked airship's tile, A boards (world/move.asm
-- @204e: $08 bit 7, ($E0,$E2) == ($1F62,$1F63))
local function board()
  local n, ph = 0, 0
  return H.withReset(H.driveUntil(function()
    n = H.airshipControl() and n + 1 or 0
    return n >= 30
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 16
      if H.aboardAirship() then H.setPad({}); return end
      H.setPad(ph < 4 and { "a" } or {})
    end),
  }, "board the Falcon"), function() n, ph = 0, 0 end)
end

H.run({ maxFrames = 300000, allowGameOver = true }, {
  H.bootCheckpoint("wor-falcon-v1"),
  H.call(function()
    H.log(string.format("[wor] boot f%d: world (%d,%d), %s; %s; %s; TERRA's record: %s",
      H.frame, H.worldX(), H.worldY(), whereLine(), kitLine(), supplies(), member(TERRA, "TERRA")))
  end),
  board(),
  H.flyTo(LANDING[1], LANDING[2], { what = "the Falcon to Mobliz" }),
  H.call(function() H.log(string.format("[falcon] landed at (%d,%d)", H.worldX(), H.worldY())) end),
  H.saveState("wor_terra_landed.mss"),
  H.worldNavTo(MOBLIZ_DOOR[1], MOBLIZ_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_MOBLIZ end }),
  H.waitUntil(function() return map() == MAP_MOBLIZ and settled() end, 1200, "Mobliz: map 158", 1),
  H.call(function() say("mobliz", "in Mobliz") end),
  -- the child at the gate (_cc43e2: (27,15)/(27,16))
  stepOn(27, 16, function() return sw(0x028E) == 1 end),
  ride(function() return sw(0x028E) == 1 end, 6000, "the child ran in"),
  H.crossDoor(16, 16, MAP_HOUSE, 50, 16, "Mobliz 158 (16,16) -> the house 163 (50,16)"),
  walkInto(43, 22, MAP_SHELTER, "the house -> the cellar stairs 165", { avoid = { { 50, 17 } } }),
  walkInto(10, 43, MAP_CELLAR, "the stairs -> the cellar 154"),
  H.saveState("wor_terra_cellar.mss"),
  stepOn(52, 57, function() return sw(0x028F) == 1 end),
  ride(function() return sw(0x028F) == 1 end, 12000, "TERRA and the children"),
  H.talkToObj(0x11, "TERRA (154 NPC_2)"),
  ride(function() return sw(0x0290) == 1 end, 20000, "TERRA's story"),
  H.saveState("wor_terra_phun1.mss"),
  stepOn(52, 58, function() return sw(0x0291) == 1 or H.battleLoadStarted() end),
  ride(function() return sw(0x0291) == 1 and map() == MAP_CELLAR end, 120000, "Phunbaba's first visit",
    { wipeEndsRide = true }),
  H.call(function() H.log(string.format("[wor] gameOverFired %d after Phunbaba's first visit", H.gameOverFired or 0)) end),
  H.saveState("wor_terra_after1.mss"),
  stepOn(50, 53, function() return sw(0x02D7) == 1 end),
  ride(function() return sw(0x02D7) == 1 end, 6000, "Fenrir"),
  walkInto(52, 59, MAP_SHELTER, "the cellar -> the stairs 165"),
  walkInto(18, 39, MAP_HOUSE, "the stairs -> the house 163"),
  walkInto(50, 17, MAP_MOBLIZ, "the house -> Mobliz"),
  stepOn(27, 16, function() return sw(0x00BE) == 1 end),
  ride(function() return sw(0x00BE) == 1 end, 6000, "Katarin is gone"),
  H.crossDoor(6, 20, MAP_SHELTER, 11, 25, "Mobliz 158 (6,20) -> the shelter 165 (11,25)"),
  walkInto(7, 17, MAP_KATARIN, "the shelter -> Katarin's room 150", { avoid = { { 11, 26 } } }),
  H.saveState("wor_terra_katarin.mss"),
  stepOn(40, 52, function() return sw(0x0292) == 1 end),
  ride(function() return sw(0x0292) == 1 end, 20000, "Phunbaba is back"),
  H.saveState("wor_terra_phun3.mss"),
  stepOn(40, 50, function() return sw(0x00BF) == 1 or H.battleLoadStarted() end),
  ride(function() return sw(0x00BF) == 1 and inParty(TERRA) end, 120000, "Phunbaba's return: TERRA joins"),
  H.saveState("wor_terra_joined.mss"),
  H.call(function()
    say("wor", "TERRA joined")
    H.log("[wor] " .. kitLine())
  end),
})
