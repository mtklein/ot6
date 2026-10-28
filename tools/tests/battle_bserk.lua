-- @suite slow
-- battle_bserk.lua -- two of Bserk's sources, played (magicite.md "Berserk").
--
-- Siren grants Bserk while worn (menu/genju_prop.asm), and Strago learns it
-- by watching: the first battle in which a monster inflicts Berserk while he
-- is present and able teaches it to him at the victory (ot6_blue.asm).
--
-- Played: Continue ultros-won-v1 (TERRA, LOCKE, STRAGO and RELM at Esper
-- Mountain's save point, map 375 (8,44), the save holding Siren).  Nothing
-- is written.
--   1. Siren onto RELM through the Skills menu.  In random battles beside
--      the save point (group 90), RELM casts Bserk through the real menu at a
--      monster the ROM's records leave open to Berserk (MonsterProp +21 bit
--      4).  Asserted when her action ends: Berserk stands on that body and
--      did not before; and Strago saw nothing (OT6_BLUESEEN still 0): an
--      ally's Bserk teaches him nothing.  After the battle he still does not
--      know it.
--   2. Into cave 372, where group 89 deals Insecares (Wing Whisp: no damage,
--      Berserk).  In a battle that fields one, everyone Defends until a
--      monster's attack inflicts Berserk (the watch's write of OT6_BLUESEEN:
--      the attacker a monster, its attack carrying Berserk), then the battle
--      is fought out.  A battle without one is fought out and the next taken.
--      Asserted: the watch fired on a monster's attack, the victory made
--      STRAGO's Bserk byte $80 and then $FF (vanilla's "learned" step), and
--      no earlier victory taught it.
--   3. In the next battle STRAGO's Magic list holds Bserk, and he casts it
--      at an open monster: Berserk stands on it when his action ends.
-- Old-ROM red and mutants: build/attempts/wt/v038-berserk/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local TERRA, LOCKE, STRAGO, RELM = 0, 1, 7, 8
local SIREN, BSERK, CMD_MAGIC = 3, 0x21, 0x02
local INSECARE = 0x0D0
local CELL = 0x1A6E + STRAGO * 0x36 + BSERK    -- STRAGO's Bserk learn byte
local SEEN = 0xEE2B                            -- OT6_BLUESEEN (ot6_memory.inc)
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function present(s) return (H.readByte(0x3AA8 + s * 2) & 1) == 1 end
local function species(s) return H.readWord(0x57C0 + s * 2) end
local function monSt2(s) return H.readByte(0x3EED + s * 2) end
local function posOf(ch) return (H.readByte(0x1850 + ch) >> 3) & 3 end
-- a species the ROM leaves open to Berserk (MonsterProp +21: status 2 immunity)
local function open(sp)
  return (H.readRomByte((H.sym("MonsterProp") & 0x3FFFFF) + sp * 32 + 21) & 0x10) == 0
end
local function seatOf(ch)
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == ch then return s end end
end
local function casts(seat)
  local e = seat * 2
  return H.readWord(0x3BF4 + e) > 0 and (H.readByte(0x3EE4 + e) & 0xE2) == 0
    and (H.readByte(0x3EE5 + e) & 0xB8) == 0 and H.readWord(0x3C08 + e) >= 16
end
local function inList(seat, id)
  for i = 0, 53 do
    if H.readByte(0x2092 + SPELL_PTR[seat] + i * 4) == id then return true end
  end
  return false
end
-- the open body to aim at: live, not berserk already
local function target()
  for s = 0, 5 do
    if present(s) and H.readWord(0x3BFC + s * 2) > 0 and open(species(s)) and (monSt2(s) & 0x10) == 0 then
      return s
    end
  end
end

-- the records: a cast of Bserk (its $3410 write) closed by the caster's
-- Ot6ActionEnd, and every write of OT6_BLUESEEN with who made it
local caster, rec, seen, cellWrites = nil, nil, {}, {}
local function arm()
  emu.addMemoryCallback(function(_, v)
    if v ~= BSERK or caster == nil or rec ~= nil then return end
    if H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    rec = { seat = caster.seat, slot = caster.slot, st0 = monSt2(caster.slot), seen0 = H.readByte(SEEN), f = H.frame }
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or caster == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == caster.seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
  emu.addMemoryCallback(function(_, v)
    if v == 0 then return end   -- InitBP's clear
    local st = emu.getState()
    seen[#seen + 1] = { v = v, x = st["cpu.x"] & 0xff, atk = H.readByte(0xB6), st2 = H.readByte(0x11AB),
      f = H.frame, pc = (st["cpu.k"] << 16) | st["cpu.pc"] }
    H.log(string.format("[bserk] OT6_BLUESEEN <- %d at f%d: attacker entity $%02X, attack $%02X, status 2 set $%02X",
      v, H.frame, st["cpu.x"] & 0xff, H.readByte(0xB6), H.readByte(0x11AB)))
  end, emu.callbackType.write, 0x7E0000 + SEEN, 0x7E0000 + SEEN)
  emu.addMemoryCallback(function(_, v)
    local st = emu.getState()
    local pc = (st["cpu.k"] << 16) | st["cpu.pc"]
    cellWrites[#cellWrites + 1] = { v = v, pc = pc, f = H.frame }
    H.log(string.format("[bserk] STRAGO's Bserk byte <- $%02X at f%d (pc $%06X)", v, H.frame, pc))
  end, emu.callbackType.write, 0x7E0000 + CELL, 0x7E0000 + CELL)
end
-- a write's pc inside a routine: from its label to the next 96 bytes
-- (compose.py embeds the symbols a script names literally)
-- (looked up when first asked, so an old ROM without them fails on the play)
local function inProc(pc, which)
  -- Ot6BlueWatch runs up to Ot6BlueLearn, which follows it in ot6_blue.asm
  if which == "watch" then return pc >= H.sym("Ot6BlueWatch") and pc < H.sym("Ot6BlueLearn") end
  local a = which == "learn" and H.sym("Ot6BlueLearn") or H.sym("ShowLearnedMagicMsg")
  return pc >= a and pc < a + 96
end
local function closed() return rec ~= nil and rec.ended ~= nil and H.frame > rec.ended + 30 end

local stage, battles, mode, plan, watch0 = 1, 0, nil, {}, nil
-- The battle budget, from the pool odds (route_data SLOT_ODDS, 80/80/80/16
-- of 256, over each map's group): beside the save point (map 375, group 90)
-- and in cave 372 (group 89) the formations with a body open to Berserk are
-- slots 0, 1 and 3, 176/256; an Insecare stands only in group 89's slot 1,
-- 80/256.  Its Wing Whisp came inside the watch in each of 8 Insecare
-- battles over K 0-7 (build/attempts/wt/v038-berserk-2/lab-air/bk_k*); 0.7
-- is taken for it.  Each stage gets the battles that leave it a 1-in-1000
-- chance of running out: 6, 28 and 6, so 40
local function within(p) return math.ceil(math.log(1e-3) / math.log(1 - p)) end
local P_OPEN, P_INSECARE, Q_WATCH = 176 / 256, 80 / 256, 0.7
local BUDGET = within(P_OPEN) + within(P_INSECARE * Q_WATCH) + within(P_OPEN)
-- how long the party Defends for an Insecare's Wing Whisp before it fights
-- the battle out (about five of the Insecare's turns)
local WATCH_FRAMES = 4000
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15 and not H.dialogWaiting()
    and not H.battleLoadStarted()
end
local function hop(sx, sy, arriveFn, what)
  return H.seqStep({
    H.navTo(sx, sy, { maxFrames = 40000, playBattles = "tactical", arrive = arriveFn }),
    H.release(),
    H.waitUntil(function() return arriveFn() and settled() end, 6000, what, 10),
    H.waitFrames(45),
    H.logStep(function() return string.format("[bserk] %s: map %d (%d,%d)", what, map(), H.fieldX(), H.fieldY()) end),
  })
end

-- one battle's choice, made when it is up
local function decide()
  battles = battles + 1
  H.assertEq(battles <= BUDGET, true, string.format("the three stages within %d battles (the pool odds)", BUDGET))
  plan, mode, rec, caster, seen = {}, "fightout", nil, nil, {}
  local ids, insecare = {}, false
  for s = 0, 5 do
    if present(s) then
      ids[#ids + 1] = string.format("%d:$%03X%s", s, species(s), open(species(s)) and "" or "(immune)")
      if species(s) == INSECARE then insecare = true end
    end
  end
  H.log(string.format("[bserk] battle %d, stage %d, map %d: %s; STRAGO's Bserk byte $%02X", battles, stage, map(),
    table.concat(ids, " "), H.readByte(CELL)))
  if stage == 1 or stage == 3 then
    local who = stage == 1 and RELM or STRAGO
    local seat, t = seatOf(who), target()
    if seat == nil or t == nil or not casts(seat) then
      H.log("[bserk] no open body here, or the caster cannot cast: fought out, the next battle taken")
      return
    end
    H.assertEq(inList(seat, BSERK), true, string.format("%s's battle Magic list holds Bserk",
      stage == 1 and "RELM (Siren worn)" or "STRAGO (learned)"))
    caster = { seat = seat, slot = t }
    mode = "cast"
    plan = { { who = who, cmd = CMD_MAGIC, spell = BSERK, boost = 0, slot = t } }
    H.log(string.format("[bserk] %s casts Bserk at slot %d ($%03X)", stage == 1 and "RELM" or "STRAGO", t, species(t)))
  elseif stage == 2 then
    if insecare and H.readByte(SEEN) == 0 then mode, watch0 = "watch", H.frame end
  end
end

H.run({ maxFrames = 1500000 }, {
  H.bootCheckpoint("ultros-won-v1"),
  -- off the save tile (its trigger re-fires under the party), as
  -- gen_massacre steps off it
  (function() local ph = 0
    return H.driveUntil(function()
      return H.fieldX() <= 7 and H.tileAligned() and not H.dialogWaiting()
    end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad({ left = true })
      end),
    }, "step left off the save tile")
  end)(),
  H.release(),
  H.waitUntil(settled, 3000, "settled off the save tile", 5),
  H.call(function()
    H.assertEq(map(), 375, "on Esper Mountain (map 375)")
    for _, ch in ipairs({ TERRA, LOCKE, STRAGO, RELM }) do
      H.assertEq((H.readByte(0x1850 + ch) & 7) ~= 0, true, string.format("char %d is in the party", ch))
    end
    H.assertEq((H.readByte(0x1A69 + (SIREN >> 3)) >> (SIREN & 7)) & 1, 1, "the save holds Siren")
    H.assertEq(H.readByte(CELL) ~= 0xFF, true, "STRAGO does not know Bserk yet (his learn byte is not $FF)")
    arm()
  end),
  H.equipEsper(function() return posOf(RELM) end, SIREN, { tag = "Siren -> RELM" }),
  H.call(function() H.assertEq(H.readByte(0x1600 + 37 * RELM + 0x1E), SIREN, "RELM wears Siren") end),
  H.driveUntil(function() return stage > 3 end, 1400000, {
    H.cond(function() return not H.battleLoadStarted() end, {
      H.fieldCare({ tag = "bserk" }),
      H.cond(function() return stage == 2 and map() ~= 372 end, {
        hop(11, 51, function() return H.fieldX() >= 30 and map() == 375 end, "the (11,51) shortcut"),
        hop(45, 41, function() return map() == 372 end, "375 (45,41) -> cave 372"),
      }, {}),
      H.cond(function() return map() == 372 end,
        { H.paceToEncounter("bserk", 0, { { 51, 19 }, { 51, 22 } }) },
        { H.paceToEncounter("bserk", 0, { { 6, 45 }, { 4, 45 } }) }),
    }, {}),
    H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
    H.call(decide),
    H.cond(function() return mode == "cast" end, {
      H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = closed }),
      H.call(function()
        if not closed() then
          H.log("[bserk] the battle ended before the cast resolved: not counted")
          mode = "skip"
          return
        end
        local st1 = monSt2(rec.slot)
        H.log(string.format("[bserk] the cast (f%d): slot %d status 2 $%02X -> $%02X; OT6_BLUESEEN %d -> %d",
          rec.f, rec.slot, rec.st0, st1, rec.seen0, H.readByte(SEEN)))
        H.assertEq(rec.st0 & 0x10, 0, "the target was not berserk before the cast")
        H.assertEq(st1 & 0x10, 0x10, "Bserk left Berserk on its target")
        if stage == 1 then
          H.assertEq(H.readByte(SEEN), 0, "an ally's Bserk is nothing STRAGO learns from (OT6_BLUESEEN still 0)")
        end
      end),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    }, {
      H.cond(function() return mode == "watch" end, {
        H.kitBattle({}, { untilPlanDone = true, idle = "defend", maxFrames = WATCH_FRAMES + 2000,
          planDone = function() return H.readByte(SEEN) ~= 0 or H.frame - watch0 > WATCH_FRAMES end }),
        H.logStep(function()
          return string.format("[bserk] the watch ends: OT6_BLUESEEN %d", H.readByte(SEEN))
        end),
      }, {}),
      H.cond(function() return H.battleLoadStarted() end, { H.fightBattleByMenu(40000) }, {}),
    }),
    H.waitUntil(function() return settled() end, 6000, "back in the field", 5),
    H.call(function()
      local b = H.readByte(CELL)
      H.log(string.format("[bserk] after battle %d: STRAGO's Bserk byte $%02X", battles, b))
      if stage == 1 then
        H.assertEq(b ~= 0xFF, true, "RELM's Bserk taught STRAGO nothing")
        if mode == "cast" then stage = 2 end
      elseif stage == 2 then
        if b == 0xFF then
          H.assertEq(#seen >= 1, true, "the watch fired before STRAGO learned Bserk")
          local s = seen[1]
          -- the write is Ot6BlueWatch's own: a SEEN address gone stale (the
          -- cell moved in ot6_memory.inc) would leave stage 1's "still 0"
          -- true of a cell nothing writes
          H.assertEq(inProc(s.pc, "watch"), true, string.format("OT6_BLUESEEN was written by Ot6BlueWatch (pc $%06X)",
            s.pc))
          H.assertEq(s.x >= 8, true, string.format("the attack that taught it was a monster's (entity $%02X)", s.x))
          H.assertEq(s.st2 & 0x10, 0x10, "the attack that taught it carried Berserk")
          -- vanilla's "learned" step: Ot6BlueLearn marks it newly learned
          -- ($80), and the battle-end loop's ShowLearnedMagicMsg, which prints
          -- "<name> learned <spell>", makes it $FF
          local w = cellWrites
          H.assertEq(#w >= 2 and w[#w - 1].v == 0x80 and inProc(w[#w - 1].pc, "learn"), true,
            "the victory's Ot6BlueLearn marked Bserk newly learned ($80)")
          H.assertEq(w[#w].v == 0xFF and inProc(w[#w].pc, "msg"), true,
            "ShowLearnedMagicMsg made it learned ($FF), the step that prints the message")
          stage = 3
        elseif #seen > 0 then
          -- seen, and not learned: he was not standing at the victory
          -- (Ot6BlueLearn), so he must see it again
          H.log(string.format("[bserk] seen this battle, not learned: STRAGO HP %d status1 $%02X at the end",
            H.charHp(STRAGO), H.charStatus1(STRAGO)))
          H.assertEq(H.charHp(STRAGO) == 0 or (H.charStatus1(STRAGO) & 0xC0) ~= 0, true,
            "a Berserk seen and not learned means STRAGO was down at the victory")
        end
      elseif stage == 3 and mode == "cast" then
        stage = 4
      end
    end),
  }, "the three stages"),
  H.logStep("[bserk] done: Siren's Bserk cast by RELM, STRAGO's learned and cast"),
})
