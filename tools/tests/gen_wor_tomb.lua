-- gen_wor_tomb.lua -- the World of Ruin from Kohlingen to Darill's Tomb's
-- save point: Continue the `wor-kohlingen-v1` battery (CELES, SABIN, EDGAR
-- and SETZER on the world map east of Kohlingen's door, (40,45)), walk to
-- the tomb, open its door with SETZER in the party, work the switches and
-- the turtles down through its three basements, and save at the save
-- point in B3's east room, 300 (122,14): the `wor-tomb-v1` battery, the
-- retry point for the monster chest and Dullahan.  Generates wor_tomb.mss;
-- its capture run (OT6_CAPTURE_SRM) cuts `wor-tomb-v1`.
-- docs/design/route-wor-falcon.md has the plan (sections 2.5-2.6, 3.3, 7)
-- and what this measured (section 12).
--
-- The route (route-wor-falcon 2.6; the pockets each door, switch and chest
-- stand in are the offline model's without its same-map links,
-- build/attempts/wt/wor-tomb/plan/nolinks.txt):
--   1. Field care at the boot, and the world walk to the tomb (25,52).
--   2. The door, 297: the step-on trigger (8,10) runs only with SETZER in
--      the party ($01A9; _ca3f83) and draws the stairs (7,8) ($00CB=1).
--   3. B1 (298): (13,12) -> (13,24) -> B2 (37,12), the hub.
--   4. B2's hub -> (44,17) -> the switch room (28,47): (28,43) facing up
--      with A ($02B1) opens (28,38) -> B3 (61,44); the water switch (61,33)
--      facing up with A ($02B3) fills the turtle's channel; back.
--   5. The hub -> (45,27) -> the Genji Helmet (43,42); back.  The hub ->
--      (29,27) -> the Crystal Mail (9,59) and the stairs (17,61) -> B3
--      (37,58): the Czarina Gown and the Exp. Egg, (43,57) -> (76,19), the
--      wall switch (76,10) facing up with A ($02B8) opens (79,3); back to
--      the hub.  Whoever each armour improves most (defense plus magic
--      defense, read from the ROM) wears it; the relics are re-planned by
--      the lib's relic rule (H.dressRelics) with what the chests and the
--      drops brought (the Exp. Egg is not ranked; an Amulet is a Zombie
--      guard).
--   6. The hub -> (37,22) -> the turtle (56,14): facing down with A rides
--      it to B3 (69,8) ($02B4); the switch (70,8) facing up with A moves
--      B3's turtle ($02B5); from (71,9) facing right with A it carries the
--      party to the far landing ($02B6); up through (79,3) -> the east room
--      (122,28).
--   7. The Man Eater (124,9); the monster chest (120,9) is left closed (the
--      Dullahan leg's); the field care (a Tent where it is worth one), the
--      relics re-planned once more, and the real Save UI on the save point
--      (H.saveAtCheckpoint "wor-tomb-v1").
-- Every battle's [outcome] is asserted said, judged on the battle's own end
-- reading, and paid as due; every battle's draw is logged as a [key] line
-- (the seed $be at InitBattle's store and the battle group $11E0), and every
-- monster's shield gauge as [brk] lines (each break, what its turns did
-- while it lasted, and the recovery).  Nothing is written; every step,
-- menu and fight is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, SABIN, EDGAR, SETZER = 6, 5, 4, 9
local TONIC, POTION, FENIX, REMEDY, SOFT = 0xE8, 0xE9, 0xF0, 0xF5, 0xF4
local REVIVIFY, GREEN_CHERRY, TENT = 0xF1, 0xF8, 0xF7
local GENJI_HELMET, CRYSTAL_MAIL, CZARINA_GOWN, EXP_EGG, MAN_EATER = 0x81, 0x98, 0x99, 0xE4, 0x06
local MAP_DOOR, MAP_B1, MAP_B2, MAP_B3 = 297, 298, 299, 300
local TOMB_TILE = { 25, 52 }
-- the tomb's chests (treasure bits; maps.txt)
local BIT_GENJI, BIT_CRYSTAL, BIT_CZARINA, BIT_EGG, BIT_MAN_EATER, BIT_MONSTER =
  0x09C, 0x09D, 0x09E, 0x09F, 0x0A0, 0x0A1
local SAVE_POINT = { 122, 14 }
-- the fight driver's options for every walk here: the defaults (the
-- status cure line Revivifies a zombie in battle, Driver:cureFor)
local FIGHT = {}

local function map() return H.mapId() & 0x1ff end
-- a step built when it is first reached, for a step whose arguments are
-- decided live (who wears what)
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
-- the statuses the arc's coming fights inflict, for the relic rule's
-- guards (lib/ot6_field.lua M.ARC_THREATS, shared by the arc's generators)
local ARC_THREATS = H.ARC_THREATS["wor-falcon"]
local function supplies()
  return string.format("tonic=%d potion=%d fenix=%d remedy=%d soft=%d revivify=%d greencherry=%d tent=%d gil=%d",
    H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX), H.invCountOf(REMEDY),
    H.invCountOf(SOFT), H.invCountOf(REVIVIFY), H.invCountOf(GREEN_CHERRY), H.invCountOf(TENT), H.gil())
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
local function say(tag, what)
  H.log(string.format("[%s] f%d %s map %d (%d,%d): %s; %s", tag, H.frame, what, map(),
    H.fieldX(), H.fieldY(), whereLine(), supplies()))
end

-- ---- the item records (ItemProp, 30 bytes: +0 type, +1/+2 who can wear it,
-- +20 battle power or defense, +21 magic defense) ----------------------------
local function prop(id, off) return H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + id * 30 + off) end
local function wears(ch, id) return (((prop(id, 1) | (prop(id, 2) << 8)) >> ch) & 1) == 1 end
local function defScore(id) return prop(id, 20) + prop(id, 21) end

-- ---- the battles --------------------------------------------------------
-- Every battle the walkers fight ends in an [outcome]; each is asserted
-- judged on its own end reading and paid as due, and the count is asserted
-- against the runner's own battle count (gen_wor_kohlingen's shape).
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

-- Every battle's draw, at InitBattle's seed store (H.seedStoreAddr): the
-- seed $be and the battle group $11E0 (gen_wor_kohlingen's key watch).
-- And the shield gauges: OT6_BROKEN_TICKS ($3E88 + entity; a monster is
-- entity 8 + 2*slot) is read at the two places the ROM asks it -- the
-- queue-time gate (Ot6Gate: a broken monster's full gauge queues no turn)
-- and ExecAction (Ot6BrokenTurn: a turn queued before the break is
-- consumed without running) -- and at CheckRetal (Ot6MayAct: a broken
-- monster makes no counterattack) -- and, the independent witness, at
-- vanilla's ExecMonsterAction, where a monster's script runs its action (a
-- broken monster reaching it acts after all).  Each monster's gauge ($3E40 shields,
-- $3E90 broken ticks, +2*slot) is polled every frame of a battle for its
-- breaks and recoveries.  All reads.
local watchOn = false
local brk = { on = false }
local function brkReset()
  brk = { on = true, slot = {}, f0 = H.frame }
  for s = 0, 5 do brk.slot[s] = { sh = nil, broken = false, acted = 0, purged = 0, gated = 0,
    lastGate = -10, refused = 0, breaks = 0 } end
end
local function speciesAt(s) return H.readWord(0x57C0 + s * 2) end
local function watches()
  return H.call(function()
    if watchOn then return end
    watchOn = true
    local addr = H.seedStoreAddr()
    emu.addMemoryCallback(function()
      local seed = emu.getState()["cpu.a"] & 0xff
      H.log(string.format("[key] battle key be%02X-g%04X f%d map %d", seed, H.readWord(0x11e0),
        H.frame, map()))
      brk.on = false
    end, emu.callbackType.exec, addr, addr)
    local function slotOfX()
      local x = emu.getState()["cpu.x"] & 0xFF
      if x < 8 or x > 0x12 or (x & 1) ~= 0 then return nil end
      return (x - 8) // 2, x
    end
    local gate = H.sym("Ot6Gate")
    emu.addMemoryCallback(function()
      if not brk.on then return end
      local s, x = slotOfX()
      if s == nil then return end
      local b = brk.slot[s]
      if H.readByte(0x3E88 + x) ~= 0 then
        -- one denial per held gauge: the gate is asked again every pass
        -- while the gauge stays full, so a run of asks is one turn
        if H.frame - b.lastGate > 4 then b.gated = b.gated + 1 end
        b.lastGate = H.frame
      end
    end, emu.callbackType.exec, gate, gate)
    local turn = H.sym("Ot6BrokenTurn")
    emu.addMemoryCallback(function()
      if not brk.on then return end
      -- a member's turn while Zombied (STATUS1 $02 without the Wound bit):
      -- the engine's, said with what it was (the command list's head)
      local px = emu.getState()["cpu.x"] & 0xFF
      if px < 8 and (px & 1) == 0 then
        local s1 = H.readByte(0x3EE4 + px)
        if (s1 & 0x02) ~= 0 and (s1 & 0x80) == 0 then
          local head = H.readByte(0x32CC + px)
          H.log(string.format("[zombie] f%d entity %d (char %d) takes a turn while Zombied (command $%02X)",
            H.frame, px // 2, H.readByte(0x3ED8 + px),
            head < 0x80 and H.readByte(0x3420 + head * 2) or 0xFF))
        end
        return
      end
      local s, x = slotOfX()
      if s == nil then return end
      local b = brk.slot[s]
      if H.readByte(0x3E88 + x) ~= 0 then
        b.purged = b.purged + 1
        H.log(string.format("[brk] f%d slot %d $%03X: a turn queued before the break is consumed "
          .. "without running (Ot6BrokenTurn, broken ticks %d)", H.frame, s, speciesAt(s), H.readByte(0x3E88 + x)))
      end
    end, emu.callbackType.exec, turn, turn)
    -- vanilla's own monster action (ExecMonsterAction: the AI script picks
    -- and runs the action, a turn's or a counter's), the independent
    -- witness: a broken monster reaching it is an action the break did not
    -- hold back
    local act = H.sym("ExecMonsterAction")
    emu.addMemoryCallback(function()
      if not brk.on then return end
      local s, x = slotOfX()
      if s == nil then return end
      local b = brk.slot[s]
      if H.readByte(0x3E88 + x) ~= 0 then
        b.acted = b.acted + 1
        H.log(string.format("[brk] f%d slot %d $%03X ACTS WHILE BROKEN (ExecMonsterAction, broken ticks %d)",
          H.frame, s, speciesAt(s), H.readByte(0x3E88 + x)))
      end
    end, emu.callbackType.exec, act, act)
    local may = H.sym("Ot6MayAct")
    emu.addMemoryCallback(function()
      if not brk.on then return end
      local s, x = slotOfX()
      if s == nil then return end
      if H.readByte(0x3E88 + x) ~= 0 then brk.slot[s].refused = brk.slot[s].refused + 1 end
    end, emu.callbackType.exec, may, may)
    -- a break's close: said once, when the gauge reads unbroken again, when
    -- the monster is gone from the field while broken, or when the battle
    -- ends with it broken
    local function closeBreak(s, how)
      local b = brk.slot[s]
      if not b.broken then return end
      b.broken = false
      H.log(string.format("[brk] f%d slot %d $%03X the break ends after %d frames (%s): while broken "
        .. "%d turn(s) denied at the gate, %d queued turn(s) consumed, %d counter(s) refused, %d action(s) "
        .. "run; shields %d/%d", H.frame, s, speciesAt(s), H.frame - b.bf, how,
        b.gated - b.gated0, b.purged - b.purged0, b.refused - b.refused0, b.acted - b.acted0,
        H.readByte(0x3E40 + s * 2), H.readByte(0x3E41 + s * 2)))
    end
    emu.addEventCallback(function()
      if not (H.battleLoadStarted() and H.monstersPresent() > 0) then
        if brk.on and not brk.closed then
          brk.closed = true
          for s = 0, 5 do closeBreak(s, "the battle ended") end
        end
        return
      end
      if not brk.on then brkReset() end
      local any = false
      for s = 0, 5 do if (H.readByte(0x3AA8 + s * 2) & 1) == 1 then any = true end end
      if not brk.said and any then
        brk.said = true
        H.log(string.format("[brk] f%d battle opens: monsters %s", H.frame, (function()
          local t = {}
          for s = 0, 5 do
            if (H.readByte(0x3AA8 + s * 2) & 1) == 1 then
              t[#t + 1] = string.format("s%d $%03X %d/%d shields", s, speciesAt(s),
                H.readByte(0x3E40 + s * 2), H.readByte(0x3E41 + s * 2))
            end
          end
          return #t > 0 and table.concat(t, ", ") or "none yet"
        end)()))
      end
      for s = 0, 5 do
        local b = brk.slot[s]
        local sh = H.readByte(0x3E40 + s * 2)
        local broken = H.readByte(0x3E90 + s * 2) ~= 0
        local present = (H.readByte(0x3AA8 + s * 2) & 1) == 1
        local dead = (H.readByte(0x3EEC + s * 2) & 0xC2) ~= 0 or H.readWord(0x3BFC + s * 2) == 0
        if present and b.sh ~= nil and sh < b.sh and not broken then
          H.log(string.format("[brk] f%d slot %d $%03X chipped %d -> %d of %d (HP %d)", H.frame, s,
            speciesAt(s), b.sh, sh, H.readByte(0x3E41 + s * 2), H.readWord(0x3BFC + s * 2)))
        end
        if dead or not present then
          -- the gauge of a dead monster is not watched: a break that lands
          -- with the killing blow is said as such, once
          if b.broken then
            closeBreak(s, "it died")
          elseif broken and present and not b.dead then
            b.breaks = b.breaks + 1
            H.log(string.format("[brk] f%d slot %d $%03X BROKEN by the killing blow (break %d; HP %d)",
              H.frame, s, speciesAt(s), b.breaks, H.readWord(0x3BFC + s * 2)))
          end
          b.dead = present
        else
          b.dead = false
          if broken and not b.broken then
            b.broken = true
            b.breaks = b.breaks + 1
            b.bf, b.acted0, b.purged0, b.gated0, b.refused0 = H.frame, b.acted, b.purged, b.gated, b.refused
            H.log(string.format("[brk] f%d slot %d $%03X BROKEN (break %d; ticks %d; HP %d)", H.frame, s,
              speciesAt(s), b.breaks, H.readByte(0x3E90 + s * 2), H.readWord(0x3BFC + s * 2)))
          elseif b.broken and not broken then
            closeBreak(s, "it recovered")
          end
        end
        b.sh = present and sh or b.sh
      end
    end, emu.eventType.endFrame)
  end)
end

local function control(what)
  return H.waitUntil(function()
    return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
  end, 3000, what, 5)
end
-- a door to another map (gen_wor_kohlingen's walkInto: the arrival counts
-- once the new map is lit and in control)
local function walkInto(x, y, dst, what, avoid)
  local function there()
    return map() == dst and H.hasControl() and H.tileAligned() and bright() >= 15
  end
  return H.seqStep({
    H.repeatN(3, {
      H.cond(function() return not there() end, {
        H.cond(function() return H.bfsPath(x, y) ~= nil end, {
          H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT, avoid = avoid,
            arrive = function() return map() == dst end }),
        }, {
          H.crossDoor(x, y, dst, -1, -1, what, { avoid = avoid, fight = FIGHT }),
        }),
        H.release(),
        H.waitUntil(function() return map() == dst end, 600, what .. ": onto map " .. dst, 5),
        H.waitUntil(function()
          return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
        end, 3000, what .. ": control", 5),
      }, {}),
    }),
    H.call(function()
      H.log(string.format("[route] %s: on map %d at (%d,%d)", what, map(), H.fieldX(), H.fieldY()))
      H.assertEq(map(), dst, what .. ": on map " .. dst)
    end),
  })
end
-- a door within the map: crossed until the party stands on its far side
local function link(m, x, y, dx, dy, what)
  return H.seqStep({
    H.crossDoor(x, y, m, dx, dy, what, { fight = FIGHT }),
    H.call(function()
      H.assertEq(H.fieldX() == dx and H.fieldY() == dy, true, string.format(
        "%s: on the far side (%d,%d) (standing on (%d,%d))", what, dx, dy, H.fieldX(), H.fieldY()))
    end),
  })
end
-- A chest: opened from whichever neighbour the party can reach where it
-- stands (gen_wor_kohlingen's chest).  H.openChest is idempotent on the
-- treasure bit.
local function chest(x, y, bit, what, item)
  local steps = {}
  for _, d in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" } }) do
    local sx, sy = x + d[1], y + d[2]
    steps[#steps + 1] = H.cond(function()
      return not H.chestOpen(bit) and H.bfsPath(sx, sy) ~= nil
    end, { H.openChest({ stand = { sx, sy }, face = d[3], bit = bit, what = what, item = item,
      nav = { fight = FIGHT } }) }, {})
  end
  steps[#steps + 1] = H.call(function()
    H.assertEq(H.chestOpen(bit), true, string.format("%s (%d,%d) bit $%03X: opened from a reachable "
      .. "neighbour (standing on (%d,%d))", what, x, y, bit, H.fieldX(), H.fieldY()))
  end)
  return H.seqStep(steps)
end
-- A switch read with a facing and A held (H.faceAndHoldA): walk onto its
-- tile, then turn and press until the switch it sets reads `want`.
local function examine(x, y, dir, pred, what)
  return H.seqStep({
    H.navTo(x, y, { maxFrames = 12000, playBattles = "tactical", fight = FIGHT }),
    H.faceAndHoldA(dir, pred, 3000, what),
    H.release(),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
    end, 3000, what .. ": control", 5),
    H.call(function() say("tomb", what) end),
  })
end

-- ---- the tomb's armour: on whoever it improves most ------------------------
-- each piece's gain on a member is its defense plus magic defense over what
-- the member wears in that slot; the member with the largest gain wears it
-- (none when nobody gains)
local function bestWearer(id, slot)
  local best, gain = nil, 0
  for _, p in ipairs(MEMBERS) do
    if inParty(p[1]) and wears(p[1], id) then
      local cur = H.readByte(c(p[1], 0x1F + slot))
      local g = defScore(id) - (cur == 0xFF and 0 or defScore(cur))
      H.log(string.format("[kit] $%02X on %s: def+mdef %d over his $%02X's %d (gain %d)", id, p[2],
        defScore(id), cur, cur == 0xFF and 0 or defScore(cur), g))
      if g > gain then best, gain = p, g end
    end
  end
  return best
end
local function dressFrom(id, slot, what)
  local who = nil
  return H.seqStep({
    H.call(function()
      who = H.invCountOf(id) > 0 and bestWearer(id, slot) or nil
      H.log(string.format("[kit] %s ($%02X) goes to %s", what, id, who and who[2] or "nobody (the bag)"))
    end),
    H.cond(function() return who ~= nil end, {
      lazy(function() return H.equipKit(who[1], { { slot, id } }, { tag = what .. " on " .. who[2] }) end),
      H.call(function()
        H.assertEq(H.readByte(c(who[1], 0x1F + slot)), id, string.format("%s worn by %s", what, who[2]))
      end),
    }, {}),
  })
end

H.run({ maxFrames = 200000 }, {
  -- ---- 0. Continue wor-kohlingen-v1 --------------------------------------------------------
  H.bootCheckpoint("wor-kohlingen-v1"),
  watches(),
  H.call(function()
    tallyReset()
    H.log(string.format("[wor] boot f%d: world %d (%d,%d), %s; kit CELES %s, SABIN %s, EDGAR %s, SETZER %s; %s; "
      .. "$1FA1-5 = %02X %02X %02X %02X %02X", H.frame, H.worldId(), H.worldX(), H.worldY(), whereLine(),
      kit(CELES), kit(SABIN), kit(EDGAR), kit(SETZER), supplies(), H.readByte(0x1FA1), H.readByte(0x1FA2),
      H.readByte(0x1FA3), H.readByte(0x1FA4), H.readByte(0x1FA5)))
    -- what this leg relies on that the checkpoint's contract does not pin:
    -- the tomb's cures in the bag (four of its five species Zombie, the Mad
    -- Oscar Sour-Mouths), and SETZER's Esper (UNICORN: Pearl, holy)
    H.assertEq(H.invCountOf(REVIVIFY) > 0, true, "Revivify in the bag for the tomb's Zombie (#190)")
    H.assertEq(H.invCountOf(REMEDY) > 0, true, "Remedy in the bag for the Mad Oscar's Sour Mouth")
    H.log(string.format("[wor] SETZER's Esper byte $%02X (UNICORN is 23 = $17)", H.readByte(c(SETZER, 0x1E))))
  end),
  H.fieldCare({ tag = "care at the boot", threshold = H.CARE_BEFORE_FIGHTS }),

  -- ---- 1. the walk to the tomb ---------------------------------------------------------------
  H.worldNavTo(TOMB_TILE[1], TOMB_TILE[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT,
    arrive = function() return not H.worldMode() end }),
  H.waitUntil(function() return map() == MAP_DOOR end, 2400, "Darill's Tomb: map 297", 5),
  control("Darill's Tomb: control"),
  checkOutcomes("the walk to the tomb"),
  H.call(function() say("tomb", "at the door") end),
  H.fieldCare({ tag = "at the tomb's door" }),

  -- ---- 2. the door: SETZER ---------------------------------------------------------------------
  H.call(function()
    H.assertEq(inParty(SETZER), true, "SETZER is in the party: the door's trigger reads $01A9 (_ca3f83)")
  end),
  H.navTo(8, 10, { maxFrames = 3000, arrive = function() return sw(0x00CB) == 1 end }),
  H.advanceStory(function()
    return sw(0x00CB) == 1 and map() == MAP_DOOR and H.hasControl() and H.tileAligned()
      and not H.dialogWaiting() and bright() >= 15
  end, 6000, {}),
  H.call(function()
    H.assertEq(sw(0x00CB), 1, "the tomb's door is open ($00CB, _ca3f83)")
    say("tomb", "the door opened")
  end),
  walkInto(7, 8, MAP_B1, "the stairs (7,8) -> B1"),

  -- ---- 3. B1 -> B2 ---------------------------------------------------------------------------------
  walkInto(13, 24, MAP_B2, "B1 (13,24) -> B2"),
  checkOutcomes("B1"),

  -- ---- 4. the switch room and the water ---------------------------------------------------------
  link(MAP_B2, 44, 17, 28, 47, "B2 hub (44,17) -> the switch room (28,47)"),
  examine(28, 43, "up", function() return sw(0x02B1) == 1 end, "the switch (28,43): $02B1"),
  walkInto(28, 38, MAP_B3, "the opened way (28,38) -> B3 (61,44)"),
  examine(61, 33, "up", function() return sw(0x02B3) == 1 end, "the water switch (61,33): $02B3"),
  walkInto(61, 45, MAP_B2, "B3 (61,45) -> B2 (28,40)"),
  link(MAP_B2, 28, 48, 44, 19, "the switch room (28,48) -> the hub (44,19)"),
  checkOutcomes("the switch room"),

  -- ---- 5. the chests and the wall switch -----------------------------------------------------
  link(MAP_B2, 45, 27, 43, 40, "the hub (45,27) -> the Genji Helmet's room (43,40)"),
  chest(43, 42, BIT_GENJI, "Genji Helmet", GENJI_HELMET),
  link(MAP_B2, 43, 38, 45, 26, "the Genji Helmet's room (43,38) -> the hub (45,26)"),
  link(MAP_B2, 29, 27, 11, 57, "the hub (29,27) -> the Crystal Mail's room (11,57)"),
  chest(9, 59, BIT_CRYSTAL, "Crystal Mail", CRYSTAL_MAIL),
  dressFrom(GENJI_HELMET, 2, "the Genji Helmet"),
  dressFrom(CRYSTAL_MAIL, 3, "the Crystal Mail"),
  walkInto(17, 61, MAP_B3, "B2 (17,61) -> B3 (37,58)"),
  chest(43, 60, BIT_CZARINA, "Czarina Gown", CZARINA_GOWN),
  chest(55, 58, BIT_EGG, "Exp. Egg", EXP_EGG),
  link(MAP_B3, 43, 57, 76, 19, "B3 (43,57) -> the wall switch's corridor (76,19)"),
  examine(76, 10, "up", function() return sw(0x02B8) == 1 end, "the wall switch (76,10): $02B8"),
  link(MAP_B3, 76, 20, 43, 59, "the corridor (76,20) -> B3 (43,59)"),
  walkInto(36, 57, MAP_B2, "B3 (36,57) -> B2 (16,60)"),
  link(MAP_B2, 11, 55, 29, 26, "the Crystal Mail's room (11,55) -> the hub (29,26)"),
  checkOutcomes("the chests and the wall switch"),
  H.fieldCare({ tag = "before the turtles" }),
  -- The relics re-planned with what the chests and the drops brought (the
  -- lib's relic rule, H.dressRelics; an Amulet, say, guards Zombie), here on
  -- the hub with the chests opened, where a player would change them.
  H.dressRelics(MEMBERS, { threats = ARC_THREATS, tag = "relics after the chests" }),

  -- ---- 6. the turtles ---------------------------------------------------------------------------
  link(MAP_B2, 37, 22, 56, 12, "the hub (37,22) -> the turtle's landing (56,12)"),
  H.navTo(56, 14, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.faceAndHoldA("down", function() return map() == MAP_B3 and sw(0x02B4) == 1 end, 3000,
    "the B2 turtle: face down and hold A on (56,14) -- _ca422e"),
  H.release(),
  control("B3: off the turtle"),
  H.call(function() say("tomb", "down on the turtle") end),
  H.cond(function() return sw(0x02B5) == 0 end, {
    examine(70, 8, "up", function() return sw(0x02B5) == 1 end, "the turtle switch (70,8): $02B5"),
  }, {}),
  H.navTo(71, 9, { maxFrames = 6000, playBattles = "tactical", fight = FIGHT }),
  H.faceAndHoldA("right", function()
    return sw(0x02B6) == 1 and H.hasControl() and H.tileAligned()
  end, 3000, "the B3 turtle: face right and hold A on (71,9) -- _ca4278"),
  H.release(),
  control("the far landing"),
  H.call(function() say("tomb", "across on the turtle") end),
  link(MAP_B3, 79, 3, 122, 28, "the landing (79,3) -> the east room (122,28)"),
  checkOutcomes("the turtles"),

  -- ---- 7. the east room: the Man Eater, the save point ---------------------------------------
  chest(124, 9, BIT_MAN_EATER, "Man Eater", MAN_EATER),
  H.call(function()
    H.assertEq(H.chestOpen(BIT_MONSTER), false, "the monster chest (120,9) is left for the Dullahan leg")
  end),
  -- on the save point first, where the item list offers a Tent (the care
  -- pitches one when the party's hole is past a Tent's worth of Tonics)
  H.stepOntoSavePoint(SAVE_POINT[1], SAVE_POINT[2]),
  H.fieldCare({ threshold = 1.0, tag = "on the save point" }),
  -- and once more before the save, for what the turtles' rooms dropped
  H.dressRelics(MEMBERS, { threats = ARC_THREATS, tag = "relics on the save point" }),
  H.saveAtCheckpoint("wor-tomb-v1"),
  checkOutcomes("the stretch"),
  H.call(function()
    local forms = {}
    for _, k in ipairs(tally.order) do forms[#forms + 1] = string.format("%s x%d", k, tally.forms[k]) end
    H.log(string.format("[wor] the battles: %d (%s): %d won, %d the party left, %d monster escape(s)",
      seen - outcome0, table.concat(forms, ", "), tally.won, tally["party left"], tally.escaped))
    H.log(string.format("[wor] the stretch: %s; kit CELES %s, SABIN %s, EDGAR %s, SETZER %s; %s", whereLine(),
      kit(CELES), kit(SABIN), kit(EDGAR), kit(SETZER), supplies()))
    H.screenshot("wor_tomb")
  end),
  H.saveState("wor_tomb.mss"),
  H.logStep(function()
    return string.format("wor_tomb generated: CELES L%d, SABIN L%d, EDGAR L%d and SETZER L%d on Darill's Tomb's save point, B3 (%d,%d), saved in slot 3",
      level(CELES), level(SABIN), level(EDGAR), level(SETZER), H.fieldX(), H.fieldY())
  end),
})
