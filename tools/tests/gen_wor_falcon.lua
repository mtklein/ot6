-- gen_wor_falcon.lua -- the World of Ruin from Darill's Tomb's save point to
-- the Falcon: Continue the `wor-tomb-v1` battery (CELES, SABIN, EDGAR and
-- SETZER on the save point in B3's east room, 300 (122,14)), open the
-- monster chest beside it (the Presenter and the Whelk Head), save again,
-- walk to the grave and beat Dullahan (event battle 85; a loss is a game
-- over), play SETZER's flashback in map 301, ride the Falcon's rising, land
-- it, and save on the World of Ruin map: the `wor-falcon-v1` battery, the
-- hub the next arcs boot from.  Generates wor_falcon.mss; its capture run
-- (OT6_CAPTURE_SRM) cuts `wor-falcon-v1`.
-- docs/design/route-wor-falcon.md has the plan (sections 2.7, 5, 6, 7) and
-- what this measured (section 13).
--
-- The route (legs 9-11):
--   1. Arm for the two fights ahead (the rule at armForFights): the chest
--      pair absorbs bolt, so CELES's ThunderBlade cannot stay in her hand,
--      and the Man Eater (pierce) keys the Whelk Head and Dullahan.
--   2. The monster chest (120,9): up the room's west column, (121,14) ->
--      (120,14) -> (120,10), facing up with A.  Kill order: the Whelk Head
--      (6 · pierce, weak fire); the Presenter has no gauge and answers hits
--      with Giga Volt.  Either one's death ends the fight (boss_death).
--   3. The gil's last digit is read against every member's level (L? Pearl,
--      Dullahan's opener, hits a member whose level it divides) and moved,
--      where it would hit someone, by a random battle's purse in the east
--      room (the tomb has no shop to buy or sell in: settleDigit); then
--      field care and Save on the save point, as a person does before a
--      boss.
--   4. The grave room: (122,7) -> 299 (100,28) -> (100,15); the walk's own
--      battles can move the digit back, so it is read again there and
--      settled in the grave room's pool if it must be; care.
--   5. Dullahan at (100,14), facing up with A, with DULL_FIGHT.
--   6. Up through (100,7) to map 301: talk to SETZER (NPC_5), step on
--      (17,16), talk to him again; the Falcon's hangar, its first flight,
--      and the rising, whose own scripted flight leaves the Falcon over
--      world (68,187) with the pilot's controls.
--   7. Fly to (25,160), the tile the rising loads (H.flyTo: Left/Right to
--      the bearing, A, a coast, B over a landable tile), land, and Save
--      there: H.saveAtCheckpoint.
-- Every battle's [outcome] is asserted said, judged on its own end reading
-- and paid as due; its draw is a [key] line (the seed $be at InitBattle's
-- store and the battle group $11E0); every monster action is a [monact]
-- line.  Nothing is written; every step, menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR, SETZER = 6, 5, 4, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
-- (the bag line said "elixir" of $EC, which is the Ether; Elixir is $EE)
local REVIVIFY, TENT, XPOTION, ETHER, ELIXIR = 0xF1, 0xF7, 0xEA, 0xEC, 0xEE
local MAP_B2, MAP_B3, MAP_FLASH = 299, 300, 301
local SAVE_POINT = { 122, 14 }
local BIT_MONSTER = 0x0A1
local PRESENTER, WHELK_HEAD, DULLAHAN = 0x101, 0x135, 0x11C
-- the species of the two fights ahead (route-wor-falcon 5, 6: the chest's
-- formation 433 and Dullahan's 455 are fixed by their events)
local FIGHTS_AHEAD = { PRESENTER, WHELK_HEAD, DULLAHAN }
local GRAVE = { 100, 14 }
local FALCON_LANDING = { 25, 160 }
local OBJ_SETZER = 0x14                               -- 301 NPC_5 (28,6), _ca43d9
-- the fight driver's options: the walks (the defaults), the chest (the
-- head first: the shell has no gauge and counters), Dullahan (CELES on
-- Runic: Ice 2, Ice 3, Pearl, N. Cross and his Cure 2 are runic)
local FIGHT = {}
local CHEST_FIGHT = { focus = { { species = WHELK_HEAD } } }
local DULL_FIGHT = { runic = true }
-- the most random battles the gil's digit may cost (each pays its purse);
-- DIGIT_POLICY = false is the lever that leaves the digit as the walk left
-- it (the lab's control arm)
local DIGIT_BATTLES = 8
local DIGIT_POLICY = true

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function c(ch, off) return 0x1600 + 37 * ch + off end
local function level(ch) return H.readByte(c(ch or CELES, 8)) end
local function inParty(ch) return (H.readByte(0x1850 + ch) & 7) ~= 0 end
local function kit(ch)
  local t = {}
  for k = 0x1E, 0x24 do t[#t + 1] = string.format("%02X", H.readByte(c(ch, k))) end
  return table.concat(t, " ")
end
local MEMBERS = { { CELES, "CELES" }, { SABIN, "SABIN" }, { EDGAR, "EDGAR" }, { SETZER, "SETZER" } }
local function supplies()
  return string.format("tonic=%d potion=%d xpotion=%d ether=%d elixir=%d fenix=%d remedy=%d soft=%d revivify=%d tent=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(XPOTION), H.invCountOf(ETHER), H.invCountOf(ELIXIR),
    H.invCountOf(FENIX),
    H.invCountOf(REMEDY), H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(TENT), H.gil())
end
local function member(ch, name)
  return string.format("%s L%d HP %d/%d MP %d/%d status1 $%02X", name, level(ch), H.charHp(ch),
    H.charMaxHp(ch), H.charMp(ch), H.charMaxMp(ch), H.charStatus1(ch))
end
local function whereLine()
  local t = {}
  for _, p in ipairs(MEMBERS) do if inParty(p[1]) then t[#t + 1] = member(p[1], p[2]) end end
  return table.concat(t, "; ")
end
local function kitLine()
  return string.format("kit CELES %s, SABIN %s, EDGAR %s, SETZER %s", kit(CELES), kit(SABIN), kit(EDGAR), kit(SETZER))
end
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end

-- ---- the item and monster records (ROM) ---------------------------------
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function isWeapon(id) return id ~= 0xFF and (prop(id, 0) & 0x80) == 0 and (prop(id, 0) & 7) == 1 end
local function monByte(sp, off) return H.readRomByte((H.sym("MonsterProp") & 0x3FFFFF) + sp * 32 + off) end
-- a species' shield row's classes (Ot6ShieldTbl: word species, count,
-- classes; else the generated floor), 0 for a species with no gauge
local function shieldClasses(sp)
  local tbl = H.sym("Ot6ShieldTbl") & 0x3FFFFF
  for i = 0, 400 do
    local w = H.readRomByte(tbl + 4 * i) | (H.readRomByte(tbl + 4 * i + 1) << 8)
    if w == 0xFFFF then break end
    if w == sp then
      if H.readRomByte(tbl + 4 * i + 2) == 0 then return 0, 0 end
      return H.readRomByte(tbl + 4 * i + 3), H.readRomByte(tbl + 4 * i + 2)
    end
  end
  return H.readRomByte((H.sym("OT6_FLOOR_CLASS") & 0x3FFFFF) + sp), -1
end

-- ---- arming for the fights ahead -----------------------------------------
-- An experienced player's read of the ROM: for each weapon hand, the
-- weapon from that hand and the bag that keys the most of the fights'
-- species (its class in the species' shield row, or its element among the
-- species' vanilla weaknesses, on a species with a gauge), then the most
-- power; never one whose element any of them absorbs (it would heal them;
-- the runner's absorb guard refuses that fight).  The members are dressed
-- in the order their Fights matter: EDGAR, SETZER and SABIN first, CELES
-- last (her turns are Runic in both fights), so a weapon in short supply
-- goes to a Fight that uses it.  A left hand is a weapon hand only when it
-- holds a weapon now (a Genji Glove's second blade).
local function absorbed(id)
  local e = H.weaponElement(id)
  for _, sp in ipairs(FIGHTS_AHEAD) do if e ~= 0 and (monByte(sp, 23) & e) ~= 0 then return true end end
  return false
end
local function keys(id)
  local cls, e, n = H.weaponClass(id), H.weaponElement(id), 0
  for _, sp in ipairs(FIGHTS_AHEAD) do
    local row, count = shieldClasses(sp)
    if count ~= 0 and ((row & cls) ~= 0 or (e ~= 0 and (monByte(sp, 25) & e) ~= 0)) then n = n + 1 end
  end
  return n
end
-- power, scaled up by the share of the fights' gauged species the weapon
-- keys: a key is worth having, a 30-power knife that keys both is not worth
-- a 133-power weapon that keys one
local function score(id)
  local gauged = 0
  for _, sp in ipairs(FIGHTS_AHEAD) do
    local _, count = shieldClasses(sp)
    if count ~= 0 then gauged = gauged + 1 end
  end
  return H.itemPower(id) * (gauged + keys(id)) / gauged
end
local function bagWeapons()
  local out = {}
  for s = 0, 255 do
    local id, n = H.readByte(0x1869 + s), H.readByte(0x1969 + s)
    if id ~= 0xFF and n > 0 and isWeapon(id) then out[id] = n end
  end
  return out
end
local function armPlan()
  local bag, plan = bagWeapons(), {}
  for _, p in ipairs({ { EDGAR, "EDGAR" }, { SETZER, "SETZER" }, { SABIN, "SABIN" }, { CELES, "CELES" } }) do
    local ch = p[1]
    for hand = 0, 1 do
      local cur = H.readByte(c(ch, 0x1F + hand))
      if inParty(ch) and (hand == 0 or isWeapon(cur)) then
        local best, bs = nil, -1
        if cur ~= 0xFF and isWeapon(cur) and not absorbed(cur) then best, bs = cur, score(cur) end
        for id, n in pairs(bag) do
          if n > 0 and wears(ch, id) and not absorbed(id) and score(id) > bs then best, bs = id, score(id) end
        end
        H.log(string.format("[kit] %s hand %d: holds $%02X (keys %d of the fights' species, power %d%s); "
          .. "the best for the fights ahead is $%02X (keys %d, power %d)", p[2], hand, cur,
          isWeapon(cur) and keys(cur) or 0, isWeapon(cur) and H.itemPower(cur) or 0,
          isWeapon(cur) and absorbed(cur) and ", ABSORBED by one of them" or "", best or 0xFF,
          best and keys(best) or 0, best and H.itemPower(best) or 0))
        if best and best ~= cur then
          bag[best] = bag[best] - 1
          if isWeapon(cur) then bag[cur] = (bag[cur] or 0) + 1 end
          plan[#plan + 1] = { ch = ch, name = p[2], hand = hand, id = best }
        end
      end
    end
  end
  return plan
end
local function armForFights()
  local plan = nil
  local function step(i)
    return H.cond(function() return plan[i] ~= nil end, {
      (function()
        local s = nil
        return {
          tick = function()
            if s == nil then
              local e = plan[i]
              s = H.equipKit(e.ch, { { e.hand, e.id } }, { tag = string.format("%s hand %d -> $%02X", e.name, e.hand, e.id) })
            end
            return s:tick()
          end,
          reset = function() s = nil end,
        }
      end)(),
      H.call(function()
        local e = plan[i]
        H.assertEq(H.readByte(c(e.ch, 0x1F + e.hand)), e.id, string.format("%s's hand %d holds $%02X", e.name, e.hand, e.id))
      end),
    }, {})
  end
  return H.seqStep({
    H.call(function() plan = armPlan() end),
    step(1), step(2), step(3), step(4), step(5), step(6), step(7), step(8),
    H.call(function()
      for _, p in ipairs(MEMBERS) do
        for hand = 0, 1 do
          local id = H.readByte(c(p[1], 0x1F + hand))
          H.assertEq(isWeapon(id) and absorbed(id), false, string.format("%s's hand %d ($%02X) is not absorbed by "
            .. "the chest pair or Dullahan", p[2], hand, id))
        end
      end
      H.log("[kit] armed: " .. kitLine())
    end),
  })
end

-- ---- the battles --------------------------------------------------------
local seen, tally, outcome0, battles0
local function tallyReset()
  tally = { won = 0, ["party left"] = 0, lost = 0, escaped = 0, forms = {}, order = {} }
  outcome0, battles0 = #H.outcomes, H.absorbGuardBattles
  seen = outcome0
end
tallyReset()
local function checkOutcomes(what)
  return H.call(function()
    for i = seen + 1, #H.outcomes do
      local o = H.outcomes[i]
      H.assertEq(o.atEnd, true, string.format("%s: battle %d ($%03X, %s) was judged on its own "
        .. "end reading (the UpdateSRAM hook), not the last per-frame one", what, i - outcome0,
        o.form & 0x1FF, o.kind))
      H.assertEq(o.ok, true, string.format("%s: battle %d ($%03X, %s) paid its reward as due",
        what, i - outcome0, o.form & 0x1FF, o.kind))
      tally[o.kind] = (tally[o.kind] or 0) + 1
      tally.escaped = tally.escaped + #o.escaped
      local k = string.format("$%03X", o.form & 0x1FF)
      if not tally.forms[k] then tally.order[#tally.order + 1] = k end
      tally.forms[k] = (tally.forms[k] or 0) + 1
    end
    H.assertEq(#H.outcomes - outcome0, H.absorbGuardBattles - battles0,
      string.format("%s: an [outcome] said for every battle fought (the runner's battle count)", what))
    if #H.outcomes > seen then
      seen = #H.outcomes
      H.log(string.format("[route] %s: %d battle(s) so far, %d [outcome] line(s) (%d won, %d the "
        .. "party left, %d monster escape(s)); %s; %s", what, H.absorbGuardBattles - battles0,
        seen - outcome0, tally.won, tally["party left"], tally.escaped, whereLine(), supplies()))
    end
  end)
end

-- Every battle's draw at InitBattle's seed store (the seed $be and the
-- battle group $11E0, with the purse: L? Pearl reads its last digit), and
-- every monster action at ExecCmd (the slot, species, command and attack):
-- the lab's evidence for what the chest pair and Dullahan did.  All reads.
local ATTACKS = { [0x98] = "L? Pearl", [0xBB] = "Absolute 0", [0x0A] = "Ice 3", [0x06] = "Ice 2",
  [0x0E] = "Pearl", [0xC5] = "N. Cross", [0x2E] = "Cure 2", [0x1F] = "Haste", [0x22] = "Float",
  [0xB9] = "Giga Volt", [0xB8] = "Mega Volt", [0x90] = "Blow Fish", [0xBC] = "Magnitude8", [0x6F] = "El Nino" }
local watchOn = false
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d gil %d", emu.getState()["cpu.a"] & 0xff,
        H.readWord(0x11e0), H.frame, map(), H.gil()))
    end, emu.callbackType.exec, addr, addr)
    local a = H.sym("ExecCmd@battle_code")
    emu.addMemoryCallback(function()
      local x = emu.getState()["cpu.x"] & 0xffff
      if x >= 8 and x < 20 and x % 2 == 0 then
        local cmd, atk = H.readByte(0xB5), H.readByte(0xB6)
        -- the script's own bookkeeping commands ($2E/$2F: set and clear a
        -- target, the counter's no-op) are not actions
        if cmd ~= 0x2E and cmd ~= 0x2F then
          H.log(string.format("[monact] f%d slot %d $%03X cmd $%02X atk $%02X%s", H.frame, x // 2 - 4,
            H.readWord(0x57C0 + (x - 8)), cmd, atk, ATTACKS[atk] and (" " .. ATTACKS[atk]) or ""))
        end
      end
    end, emu.callbackType.exec, a, a)
  end)
end

local function control(what)
  return H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
  end, 3000, what, 5)
end
local function walkInto(x, y, dst, what, fight)
  local function there()
    return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
  end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = fight or FIGHT,
          arrive = function() return map() == dst end }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
      }, {}),
    }),
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end

-- ---- L? Pearl and the purse ------------------------------------------------
-- L? Pearl hits the members whose level the last digit of the party's gil
-- divides (AttackerEffect_1d, battle_main.asm:10842: level / digit, a miss
-- on any remainder).  A digit of 0 divides by zero; what the SNES divider
-- then does is not measured, so 0 counts as unsafe here.
local function pearlHits()
  local d, hit = H.gil() % 10, {}
  for _, p in ipairs(MEMBERS) do
    if inParty(p[1]) and (d == 0 or level(p[1]) % d == 0) then
      hit[#hit + 1] = string.format("%s L%d", p[2], level(p[1]))
    end
  end
  return hit, d
end
local function digitLine()
  local hit, d = pearlHits()
  return string.format("gil %d, last digit %d: L? Pearl would hit %s", H.gil(), d,
    #hit > 0 and table.concat(hit, ", ") or "no one")
end
-- Walk back and forth between two tiles (WPS) until a random battle comes,
-- while the digit would let L? Pearl hit someone: a battle's purse moves the
-- digit.  The tomb has no shop to buy or sell in, and of its formations only
-- the Mad Oscar's pay a purse that does not end in 0 (2292 GP, x2 as a
-- random: +4 to the digit; the others' end in 0: route-wor-falcon 13), so
-- the walk goes on until one comes.  Bounded by DIGIT_BATTLES.
local function settleDigit(WPS, where)
  local fought0, wp = nil, 1
  return H.withReset(H.driveUntil(function()
    if fought0 == nil then fought0 = #H.outcomes end
    -- not while a battle is up: its purse lands on the victory screen, and
    -- ending the walk there abandons the battle before its [outcome] is
    -- said (merged main 53b6a887's qualification: the Mad Oscar pair's
    -- 2292 GP moved the digit at f+1500 of the east room's fourth battle,
    -- "an [outcome] said for every battle fought ...: got 3, want 4")
    if H.battleLoadStarted() then return false end
    local hit = pearlHits()
    return not DIGIT_POLICY or #hit == 0 or #H.outcomes - fought0 >= DIGIT_BATTLES
  end, 200000, {
    H.call(function() H.log("[pearl] " .. where .. ": " .. digitLine() .. "; walking for a battle's purse") end),
    H.navTo(function() return WPS[wp][1] end, function() return WPS[wp][2] end,
      { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.fieldCare({ tag = "after a purse battle" }),
    H.call(function() wp = wp % #WPS + 1 end),
  }, "the gil's last digit off every member's level (" .. where .. ")"), function() fought0, wp = nil, 1 end)
end

H.run({ maxFrames = 200000 }, {
  -- ---- 0. Continue wor-tomb-v1 ---------------------------------------------------------------
  H.bootCheckpoint("wor-tomb-v1"),
  watches(),
  H.call(function()
    tallyReset()
    H.log(string.format("[wor] boot f%d: map %d (%d,%d), %s; %s; %s; $1FA1-5 = %02X %02X %02X %02X %02X",
      H.frame, map(), H.fieldX(), H.fieldY(), whereLine(), kitLine(), supplies(), H.readByte(0x1FA1),
      H.readByte(0x1FA2), H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    -- what this leg relies on that the checkpoint's contract does not pin
    H.assertEq(inParty(SETZER), true, "SETZER is in the party (the flashback's scenes are his)")
    H.assertEq(H.invCountOf(POTION) > 0, true, "Potions in the bag for the two fights")
    H.assertEq(H.invCountOf(FENIX) > 0, true, "Fenix Downs in the bag for the two fights")
  end),

  -- ---- 1. care, and arm for the chest and Dullahan -----------------------------------------
  -- (the checkpoint's party is cared for; a body that starts from another
  -- draw may not be, and the Equip menu will not take a fallen member)
  H.fieldCare({ tag = "care at the boot", threshold = H.CARE_BEFORE_FIGHTS }),
  H.call(function()
    for _, p in ipairs(MEMBERS) do
      H.assertEq(H.charHp(p[1]) > 0 and (H.charStatus1(p[1]) & 0xC2) == 0, true, string.format(
        "%s stands before the kit is changed (HP %d, status1 $%02X)", p[2], H.charHp(p[1]), H.charStatus1(p[1])))
    end
  end),
  armForFights(),

  -- ---- 2. the monster chest ------------------------------------------------------------------
  H.cond(function() return not H.chestOpen(BIT_MONSTER) end, {
    H.navTo(121, 14, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
    H.navTo(120, 10, { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
    H.call(function() say("chest", "below the monster chest") end),
    H.saveState("wor_chest.mss"),
    H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000,
      "the monster chest (120,9): face up, A (EventCmd_8e)"),
    H.release(),
    H.advanceStory(function()
      return H.chestOpen(BIT_MONSTER) and not H.battleLoadStarted() and map() == MAP_B3 and H.hasControl()
        and H.tileAligned() and not H.dialogWaiting()
    end, 60000, { playBattles = "tactical", fight = CHEST_FIGHT }),
  }, {}),
  checkOutcomes("the monster chest"),
  H.call(function()
    H.assertEq(H.chestOpen(BIT_MONSTER), true, "the monster chest (120,9) is open (treasure bit $0A1)")
    say("chest", "the chest fight is over")
  end),

  -- ---- 3. the purse, then care and Save on the save point -----------------------------------
  H.call(function() H.log("[pearl] after the chest: " .. digitLine()) end),
  settleDigit({ { 124, 26 }, { 120, 11 } }, "the east room"),
  checkOutcomes("the purse in the east room"),
  H.stepOntoSavePoint(SAVE_POINT[1], SAVE_POINT[2]),
  H.fieldCare({ threshold = 1.0, tag = "on the save point after the chest" }),
  H.saveGame({ slot = 3, tag = "the tomb's save point, after the chest" }),
  H.call(function()
    H.assertSavedSlot(MAP_B3, SAVE_POINT[1], SAVE_POINT[2], "the save after the chest", 3)
    say("tomb", "saved after the chest")
  end),

  -- ---- 4. the grave room, and the purse --------------------------------------------------------
  walkInto(122, 7, MAP_B2, "B3 (122,7) -> the grave room (100,28)"),
  H.navTo(GRAVE[1], GRAVE[2] + 1, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT }),
  checkOutcomes("the walk to the grave"),
  H.call(function() H.log("[pearl] at the grave: " .. digitLine()) end),
  settleDigit({ { 100, 24 }, { 100, 16 } }, "the grave room"),
  checkOutcomes("the purse in the grave room"),
  H.navTo(GRAVE[1], GRAVE[2] + 1, { maxFrames = 8000, playBattles = "tactical", fight = FIGHT }),
  -- armed for the fight ahead (#351): the lib's relic rule against
  -- Dullahan's own threats (H.FIGHT_THREATS.dullahan: magic damage, no
  -- status a relic guards), and back to the arc's after him
  H.dressRelics(MEMBERS, { threats = H.FIGHT_THREATS.dullahan, tag = "relics for Dullahan" }),
  H.fieldCare({ threshold = 1.0, tag = "before the grave" }),
  H.navTo(GRAVE[1], GRAVE[2], { maxFrames = 3000, playBattles = "tactical", fight = FIGHT }),
  checkOutcomes("the grave's approach"),
  H.call(function()
    H.log("[pearl] pressing the grave: " .. digitLine())
    say("dullahan", "at the grave")
  end),
  H.saveState("wor_grave.mss"),

  -- ---- 5. Dullahan ---------------------------------------------------------------------------
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000,
    "the grave (100,14): face up, A (_ca42f1, battle 85)"),
  H.release(),
  H.advanceStory(function()
    return sw(0x02B2) == 1 and not H.battleLoadStarted() and map() == MAP_B2 and H.hasControl()
      and H.tileAligned() and not H.dialogWaiting()
  end, 120000, { playBattles = "tactical", fight = DULL_FIGHT }),
  checkOutcomes("Dullahan"),
  H.call(function()
    H.assertEq(sw(0x02B2), 1, "Dullahan is beaten ($02B2, _ca42f1)")
    say("dullahan", "Dullahan is beaten")
  end),

  -- ---- 6. the flashback and the Falcon ----------------------------------------------------
  H.fieldCare({ tag = "after Dullahan" }),
  H.dressRelics(MEMBERS, { threats = H.ARC_THREATS["wor-falcon"], tag = "relics after Dullahan" }),
  walkInto(GRAVE[1], 7, MAP_FLASH, "the grave room (100,7) -> the flashback (301)"),
  H.advanceStory(function()
    return map() == MAP_FLASH and sw(0x01F1) == 1 and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 6000, {}),
  H.call(function()
    H.assertEq(inParty(SETZER), false, "SETZER has left the party for the flashback (_ca435d)")
    say("falcon", "in the flashback")
  end),
  H.talkToObj(OBJ_SETZER, "SETZER (301 NPC_5): \"Watch your step\""),
  H.advanceStory(function()
    return sw(0x01F0) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.navTo(17, 16, { maxFrames = 6000, arrive = function() return sw(0x01F2) == 1 end }),
  H.advanceStory(function()
    return sw(0x01F3) == 1 and H.hasControl() and H.tileAligned() and not H.dialogWaiting()
  end, 6000, {}),
  H.call(function() say("falcon", "Daryl's promise seen") end),
  H.talkToObj(OBJ_SETZER, "SETZER (301 NPC_5): the Falcon"),
  (function()
    local n = 0
    return H.withReset(H.advanceStory(function()
      n = H.airshipControl() and n + 1 or 0
      return n >= 60
    end, 30000, {}), function() n = 0 end)
  end)(),
  H.call(function()
    H.assertEq(sw(0x00CC) == 1 and sw(0x00CD) == 1 and sw(0x039B) == 1, true,
      "the Falcon has risen ($00CC, $00CD, $039B; _ca4502)")
    H.assertEq(inParty(SETZER), true, "SETZER is back in the party (_ca4502)")
    local fx, fy = H.airshipTile()
    H.log(string.format("[falcon] f%d in flight over world %d (%d,%d): vehicle %d, altitude $11F4=%04X, tile props "
      .. "$C2=%02X $C3=%02X (bit 1 of $C2 set: the airship cannot land here); %s; %s", H.frame, H.worldId(),
      fx, fy, H.readByte(0x11FA), H.readWord(0x11F4), H.readByte(0xC2), H.readByte(0xC3),
      whereLine(), supplies()))
    H.screenshot("wor_falcon_flight")
  end),
  H.saveState("wor_flight.mss"),

  -- ---- 7. fly to (25,160), land, and Save --------------------------------------------------
  -- the rising's scripted flight leaves the Falcon over (68,187); the arc's
  -- end is the tile the rising loads, (25,160) (route-wor-falcon 2.7)
  H.flyTo(FALCON_LANDING[1], FALCON_LANDING[2], { what = "the Falcon to (25,160)" }),
  H.call(function()
    H.log(string.format("[falcon] f%d landed: on foot at world %d (%d,%d); the Falcon parked at ($1F62,$1F63) = "
      .. "(%d,%d); $1F64 = $%04X; %s; %s", H.frame, H.worldId(), H.worldX(), H.worldY(), H.readByte(0x1F62),
      H.readByte(0x1F63), H.readWord(0x1F64), whereLine(), supplies()))
    H.screenshot("wor_falcon_landed")
  end),
  H.saveAtCheckpoint("wor-falcon-v1"),
  checkOutcomes("the stretch"),
  H.call(function()
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the battles: %d (%s): %d won, %d the party left, %d monster escape(s)",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped))
    H.log(string.format("[wor] the stretch: %s; %s; %s", whereLine(), kitLine(), supplies()))
  end),
  H.saveState("wor_falcon.mss"),
  H.logStep(function()
    return string.format("wor_falcon generated: CELES L%d, SABIN L%d, EDGAR L%d and SETZER L%d on foot beside the Falcon, world (%d,%d), saved in slot 3",
      level(CELES), level(SABIN), level(EDGAR), level(SETZER), H.worldX(), H.worldY())
  end),
})
