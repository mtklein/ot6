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
local ISLAND_LANDING, ISLAND_DOOR = { 75, 238 }, { 76, 240 }
local MAP_ISLAND, MAP_BEACH = 396, 398
local MAP_DECK, MAP_CABIN = 11, 12
local MOBLIZ_EXIT = { 32, 18 }
-- the party the route regroups to aboard: TERRA, who joined, and the three
-- who walked the World of Ruin's first legs (route-wor-terra.md 2.6)
local REGROUP = { 0, 6, 5, 4 }
local REGROUP_MEMBERS = { { 0, "TERRA" }, { 6, "CELES" }, { 5, "SABIN" }, { 4, "EDGAR" } }
-- the cabin's members (map 12): name, object, show-switch
local CABIN_NPCS = { { "CELES", 0x16, 0x038E }, { "SETZER", 0x19, 0x0391 }, { "SABIN", 0x15, 0x038D },
  { "EDGAR", 0x14, 0x038C }, { "TERRA", 0x10, 0x0388 } }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch, 8)) end
local function partyOf(ch) return H.readByte(0x1850 + ch) & 7 end
local function inParty(ch) return partyOf(ch) ~= 0 end
-- magicite owned: give_genju's receipt bits from $1A69 (Ramuh = 0)
local PALIDOR, FENRIR = 0x3F - 0x36, 0x4E - 0x36
local function esper(i) return (H.readByte(0x1A69 + (i >> 3)) >> (i & 7)) & 1 end
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
local function rosterLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do t[#t + 1] = string.format("%s $1850=%02X", p[2], H.readByte(0x1850 + p[1])) end
  return "roster " .. table.concat(t, " ")
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
-- a step built when it is first reached (its arguments decided live)
local function lazy(build)
  local step = nil
  return {
    tick = function()
      if step == nil then step = build() end
      return step:tick()
    end,
    reset = function()
      if step and step.reset then step:reset() end
      step = nil
    end,
  }
end
local lossesSeen = 0
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
-- a chest from whichever side of it the party can reach (the live object
-- map: rubble and NPCs block sides the offline map leaves open)
local function chestAt(cx, cy, bit, what, item)
  return lazy(function()
    for _, o in ipairs({ { 0, 1, "up" }, { -1, 0, "right" }, { 1, 0, "left" }, { 0, -1, "down" } }) do
      if H.bfsPath(cx + o[1], cy + o[2]) then
        return H.openChest({ stand = { cx + o[1], cy + o[2] }, face = o[3], bit = bit, what = what, item = item })
      end
    end
    H.log(string.format("[chest] %s (%d,%d): no side of it is reachable from (%d,%d)", what, cx, cy,
      H.fieldX(), H.fieldY()))
    return H.call(function() end)
  end)
end
local function stepOn(x, y, done)
  local evN = 0
  -- navTo plans to a neighbour of the trigger; the last step is a held
  -- direction (navTo's own last step read the cellar entry's first press,
  -- a turn, as a blocked edge: build/attempts/wt/v027-terra-route/cellar/)
  local function arrived()
    -- (an event taking the party on the trigger or beside it: Mobliz's
    -- gate trigger is two tiles, (27,15) and (27,16))
    -- held for 20 frames: a trigger whose event returns at once (the
    -- cellar's (52,57) once it has played) runs for a frame or two
    local near = math.abs(H.fieldX() - x) + math.abs(H.fieldY() - y) <= 1
    evN = (near and (H.eventRunning() or H.dialogWaiting())) and evN + 1 or 0
    return done() or H.battleLoadStarted() or evN >= 20
      or (H.fieldX() == x and H.fieldY() == y and not H.hasControl())
  end
  local nb = nil
  local function pick()
    if nb then return nb end
    local px, py = H.fieldX(), H.fieldY()
    if math.abs(px - x) + math.abs(py - y) == 1 then nb = { px, py }; return nb end
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      if H.bfsPath(x + d[1], y + d[2]) then nb = { x + d[1], y + d[2] }; return nb end
    end
    nb = { x, y + 1 }
    return nb
  end
  local n = 0
  return H.withReset(H.seqStep({
    H.cond(function() return not arrived() end, {
      H.call(function() nb = nil; pick() end),
      H.navTo(function() return pick()[1] end, function() return pick()[2] end,
        { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = arrived }),
      H.driveUntil(arrived, 1200, {
        H.call(function()
          n = n + 1
          local dx, dy = x - H.fieldX(), y - H.fieldY()
          local dir = dx > 0 and "right" or dx < 0 and "left" or dy > 0 and "down" or "up"
          H.setPad((n % 24) < 16 and { dir } or {})
        end),
      }, string.format("step onto the trigger (%d,%d)", x, y)),
      H.release(),
    }, {}),
  }), function() n = 0; nb = nil; evN = 0 end)
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


-- ---- what each Phunbaba fight did (reads only) ------------------------------
-- Every battle's draw at InitBattle's seed store ([key]: the seed $be and
-- the battle group $11E0), every monster action at ExecCmd ([monact]), and
-- slot 0's gauge each frame ([brk]: OT6_SHIELD_CUR/MAX at $3E38/$3E39 and
-- the HP word $3BF4, entity 4 = monster slot 0, ot6_memory.inc): the
-- break, the HP it landed at, and how long the window held.
local ATTACKS = { [0x08] = "Bolt 2", [0x09] = "Bolt 3", [0x90] = "Blow Fish", [0xEE] = "Battle", [0xEF] = "Special" }
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map()))
    end, emu.callbackType.exec, addr, addr)
    local a = H.sym("ExecCmd@battle_code")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xffff
      if x >= 8 and x < 20 and x % 2 == 0 then
        local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
        if cmd ~= 0x2E and cmd ~= 0x2F then
          H.log(string.format("[monact] f%d slot %d $%03X cmd $%02X atk $%02X%s", H.frame, x // 2 - 4,
            H.readWord(0x57C0 + (x - 8)), cmd, atk, ATTACKS[atk] and (" " .. ATTACKS[atk]) or ""))
        end
      end
    end, emu.callbackType.exec, a, a)
    local was, since = nil, 0
    emu.addEventCallback(function()
      if not H.battleLoadStarted() then was = nil; return end
      local sp = H.readWord(0x57C0)
      if sp < 0x16A or sp > 0x16D then return end
      local cur, max = H.readByte(0x3E40), H.readByte(0x3E41)
      local broken = max > 0 and cur == 0
      if was == nil then was = broken; return end
      if broken and not was then
        since = H.frame
        H.log(string.format("[brk] f%d $%03X broken (0 of %d shields) at HP %d", H.frame, sp, max, H.readWord(0x3BFC)))
      elseif was and not broken then
        H.log(string.format("[brk] f%d $%03X window over after %d frames: shields %d of %d, HP %d", H.frame, sp,
          H.frame - since, cur, max, H.readWord(0x3BFC)))
      end
      was = broken
    end, emu.eventType.endFrame)
  end)
end

H.run({ maxFrames = 300000, allowGameOver = true }, {
  H.bootCheckpoint("wor-falcon-v1"),
  watches(),
  H.call(function()
    H.log(string.format("[wor] boot f%d: world (%d,%d), %s; %s; %s; TERRA's record: %s",
      H.frame, H.worldX(), H.worldY(), whereLine(), kitLine(), supplies(), member(TERRA, "TERRA")))
  end),
  -- ---- Palidor, on the Solitary Island's beach (shown since the rising, $039B) ----
  board(),
  H.flyTo(ISLAND_LANDING[1], ISLAND_LANDING[2], { what = "the Falcon to the Solitary Island" }),
  H.worldNavTo(ISLAND_DOOR[1], ISLAND_DOOR[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return map() == MAP_ISLAND end }),
  H.waitUntil(function() return map() == MAP_ISLAND and settled() end, 1200, "the island: map 396", 1),
  walkInto(8, 14, MAP_BEACH, "the island -> the beach 398"),
  H.talkToObj(0x15, "the magicite on the beach (398 NPC_6)"),
  ride(function() return esper(PALIDOR) == 1 end, 3000, "Palidor"),
  H.call(function() H.assertEq(esper(PALIDOR), 1, "Palidor is owned (give_genju, _ca55e9)") end),
  walkInto(3, 1, MAP_ISLAND, "the beach -> the island"),
  H.cond(function() return not H.worldMode() end, {
    H.navTo(7, 0, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT, arrive = function() return H.worldMode() end }),
  }, {}),
  H.waitWorldSettled("back on the World of Ruin map", 1800, 30),
  H.worldNavTo(ISLAND_LANDING[1], ISLAND_LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.call(function() say("palidor", "back at the Falcon") end),
  -- ---- Mobliz ----
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
  chestAt(51, 12, 0x03D, "Elixir (163 (51,12))", ELIXIR),
  walkInto(43, 22, MAP_SHELTER, "the house -> the cellar stairs 165", { avoid = { { 50, 17 } } }),
  walkInto(10, 43, MAP_CELLAR, "the stairs -> the cellar 154"),
  H.saveState("wor_terra_cellar.mss"),
  stepOn(52, 57, function() return sw(0x028F) == 1 end),
  ride(function() return sw(0x028F) == 1 end, 12000, "TERRA and the children"),
  H.talkToObj(0x11, "TERRA (154 NPC_2)"),
  ride(function() return sw(0x0290) == 1 end, 20000, "TERRA's story"),
  H.saveState("wor_terra_phun1.mss"),
  stepOn(52, 58, function() return sw(0x0291) == 1 or H.battleLoadStarted() end),
  -- battle 128: TERRA alone (char_party TERRA, 2) against an invincible
  -- Phunbaba (AIScript _362: invincible_on SELF); the event plays on after
  -- her loss (no _ca5ea9 after it, event_main.asm _cc4990), so the loss is
  -- the story's, answered at the Annihilated screen as a person does
  -- (a ride may end on the canary's wipe count, or ride on through 129;
  -- either way the outcomes since the trigger are judged below)
  H.call(function() lossesSeen = #H.outcomes end),
  -- Battle 128's wipe reading outlives the battle: the seat table keeps
  -- TERRA at 0 HP (and $3EBC's LoseBattle bit) until battle 129's
  -- InitBattle clears it, so a ride's wipe canary may end on it in the
  -- scene between the two (measured: the ride ended there in 4 of 8
  -- seeds).  After the loss the scene's dialog is answered until battle 129
  -- is up, then the party's fight is ridden.
  ride(function() return sw(0x0291) == 1 and map() == MAP_CELLAR end, 120000, "Phunbaba's first visit: TERRA alone",
    { wipeEndsRide = true }),
  (function()
    local ph = 0
    local function past128()
      if sw(0x0291) == 1 then return true end
      for i = lossesSeen + 1, #H.outcomes do
        if (H.outcomes[i].form & 0x1FF) == 0x1A5 then return true end
      end
      return H.battleLoadStarted() and H.formationWords()[1] == 0x016B
    end
    return H.withReset(H.driveUntil(past128, 12000, {
      H.call(function()
        ph = (ph + 1) % 8
        H.setPad((H.dialogWaiting() or (H.battleLoadStarted() and H.formationWords()[1] == 0x016A)) and ph < 4
          and { "a" } or {})
      end),
    }, "the scene after battle 128, to battle 129"), function() ph = 0 end)
  end)(),
  H.release(),
  H.call(function()
    H.log(string.format("[phunbaba] battle 128 behind (game over counted %d by its wipe reading); battle 129 next",
      H.gameOverFired or 0))
    H.gameOverFired = 0
  end),
  ride(function() return sw(0x0291) == 1 and map() == MAP_CELLAR end, 120000, "Phunbaba's first visit: the party",
    { wipeEndsRide = true }),
  H.call(function()
    local lost, won = 0, 0
    for i = lossesSeen + 1, #H.outcomes do
      local o = H.outcomes[i]
      local f = o.form & 0x1FF
      H.log(string.format("[phunbaba] battle $%03X %s after %d ticks, %d seated", f, o.kind, o.tick or -1, o.seatedN or -1))
      if o.kind == "lost" and f ~= 0x1A4 then
        -- a lost battle 129 is the game's game over (_ca5ea9): a person
        -- reloads; the runner retries from the boot, counted
        error(string.format("LOST: battle $%03X (Phunbaba's first visit) lost", f), 0)
      elseif o.kind == "lost" then
        lost = lost + 1
        H.assertEq(o.seatedN, 1, "battle 128 seats TERRA alone")
      elseif f == 0x1A5 then
        won = won + 1
      end
    end
    H.assertEq(sw(0x0291), 1, "Phunbaba driven off ($0291, _cc4990)")
    H.assertEq(lost, 1, "battle 128 was lost once (the scripted loss)")
    H.assertEq(won, 1, "battle 129 (formation $1A5) was won")
    H.log(string.format("[phunbaba] the scripted loss answered at the Annihilated screen (game over counted %d); "
      .. "battle 129 won", H.gameOverFired or 0))
    H.gameOverFired = 0
  end),
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
  chestAt(34, 49, 0x0A7, "Ether (150 (34,49))", ETHER),
  H.saveState("wor_terra_katarin.mss"),
  stepOn(40, 52, function() return sw(0x0292) == 1 end),
  ride(function() return sw(0x0292) == 1 end, 20000, "Phunbaba is back"),
  H.saveState("wor_terra_phun3.mss"),
  stepOn(40, 50, function() return sw(0x00BF) == 1 or H.battleLoadStarted() end),
  ride(function() return sw(0x00BF) == 1 and inParty(TERRA) end, 120000, "Phunbaba's return: TERRA joins"),
  H.saveState("wor_terra_joined.mss"),
  H.call(function()
    say("wor", "TERRA joined")
    H.log("[wor] " .. kitLine() .. "; " .. rosterLine())
    H.assertEq(inParty(TERRA), true, "TERRA is in the party (_cc4c1b: char_party TERRA, 1)")
    H.assertEq(esper(FENRIR), 1, "Fenrir is owned (Phunbaba dropped it, _cc4abd)")
  end),
  -- the last chest, and out of town to the Falcon
  chestAt(9, 17, 0x0FB, "Fenix Down (158 (9,17))", FENIX),
  H.navTo(MOBLIZ_EXIT[1], MOBLIZ_EXIT[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return H.worldMode() end }),
  H.waitWorldSettled("out of Mobliz", 1800, 30),
  H.worldNavTo(LANDING[1], LANDING[2], { maxFrames = 6000, playBattles = "tactical", fight = FIGHT,
    avoid = { MOBLIZ_DOOR } }),
  -- ---- the party, regrouped aboard (the BabaBreaths sent two of the four
  -- back to the Falcon): the Falcon's cabin, a member's "Change party
  -- members?", and the party menu ----
  board(),
  H.withReset((function()
    local ph = 0
    return H.driveUntil(function() return map() == MAP_DECK and settled() end, 2400, {
      H.call(function()
        ph = (ph + 1) % 16
        H.setPad((H.airshipControl() and ph < 4) and { "x" } or {})
      end),
    }, "X: to the Falcon's deck (map 11)")
  end)(), function() end),
  walkInto(24, 8, MAP_CABIN, "the deck -> the cabin (map 12)"),
  H.call(function() H.log("[regroup] in the cabin: " .. rosterLine()) end),
  (function()
    local obj = nil
    return H.seqStep({
      H.call(function()
        for _, n in ipairs(CABIN_NPCS) do
          local ox, oy = H.objX(n[2]), H.objY(n[2])
          if sw(n[3]) == 1 and (H.bfsPath(ox, oy + 1) or H.bfsPath(ox - 1, oy) or H.bfsPath(ox + 1, oy)
              or H.bfsPath(ox, oy - 1)) then
            obj = n; break
          end
        end
        H.assertEq(obj ~= nil, true, "a member waits in the cabin to talk to")
        H.log(string.format("[regroup] talking to %s (obj $%02X, show-switch $%04X)", obj[1], obj[2], obj[3]))
      end),
      lazy(function() return H.talkToObj(obj[2], obj[1] .. " in the cabin") end),
    })
  end)(),
  -- "Change party members?" (_caf59d): 0 No, 1 Yes
  H.dialogChoice(1, { inBattle = false, what = "Change party members? Yes", tag = "the cabin" }),
  H.partySelect(REGROUP, { tag = "the Falcon's cabin" }),
  H.waitUntil(function() return map() == MAP_DECK and settled() end, 2400, "back on the deck after the menu", 5),
  H.call(function()
    H.log("[regroup] " .. rosterLine())
    for _, ch in ipairs(REGROUP) do
      H.assertEq(partyOf(ch) == 1, true, string.format("char %d is in party 1 after the regroup", ch))
    end
  end),
  -- dressed for the arc: TERRA's relics and Fenrir
  H.fieldCare({ tag = "after the regroup", threshold = H.CARE_BEFORE_FIGHTS }),
  H.dressRelics(REGROUP_MEMBERS, { threats = H.ARC_THREATS["wor-falcon"], tag = "relics with TERRA" }),
  H.equipEsper(function() return (H.readByte(0x1850 + TERRA) >> 3) & 3 end, FENRIR, { tag = "FENRIR -> TERRA" }),
  H.call(function()
    H.assertEq(H.readByte(c(TERRA, 0x1E)), FENRIR, "TERRA holds Fenrir")
    say("regroup", "dressed: " .. kitLine())
  end),
  -- lift off from the deck's wheel (_caf532: "(Lift-off)"), land on the
  -- same tile, and Save beside the Falcon
  -- the wheel answers A held facing left on its tile (_caf532: $01B3
  -- facing left, $01B4 A held, the switches _ca42f1's grave reads too)
  H.navTo(15, 8, { maxFrames = 3000 }),
  H.faceAndHoldA("left", function() return H.dialogWaiting() end, 1200, "the Falcon's wheel (11 (15,8)): face left, A"),
  H.release(),
  H.dialogChoice(0, { inBattle = false, what = "the wheel: (Lift-off)", tag = "the wheel" }),
  H.flyTo(LANDING[1], LANDING[2], { what = "land beside Mobliz" }),
  H.saveAtCheckpoint("wor-terra-v1"),
  H.call(function()
    H.log(string.format("[wor] the stretch: %s; %s; %s", whereLine(), kitLine(), supplies()))
  end),
  H.saveState("wor_terra.mss"),
  H.logStep(function()
    return string.format("wor_terra generated: TERRA L%d, CELES L%d, SABIN L%d and EDGAR L%d on foot beside the Falcon, world (%d,%d), saved in slot 3",
      level(TERRA), level(CELES), level(SABIN), level(EDGAR), H.worldX(), H.worldY())
  end),
})
