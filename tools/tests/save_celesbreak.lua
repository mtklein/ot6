-- @suite slow
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- save_celesbreak.lua -- an older release's save, CELES past level 13 with Imp
-- learned and Break not, has Break by her level, and nothing is written (#563).
--
-- Break took Imp's place at level 13 in CELES's natural magic (NaturalMagic,
-- field/event.asm).  A save made before that has her past 13 with Imp in
-- her learned table and Break not; a load must leave the save's block as
-- the file has it (the golden saves, save_golden.lua), so her learned table
-- is not touched: the three spell-known hooks grant Break by her level
-- (Ot6CelesBreak in Ot6FieldSpellKnown, Ot6UnionEspers and
-- Ot6EsperSpellKnown, battle/ot6_progression.asm).  Such a save keeps Imp.
--
-- Boot: a release's own battery, tools/tests/golden-saves/v0.50/wor-cyan-v1
-- (configure.py TEST_ENV; v0.50's "The Falcon, after the Storm Dragon": TERRA,
-- CYAN, SABIN and CELES L36 on the World of Ruin's map), Continued through
-- the real title screen as save_golden does.  A tracked release file, so it
-- stays an old save however the chain is replayed.  By hand:
--   OT6_SRAM_CHECKPOINT=tools/tests/golden-saves/v0.50/wor-cyan-v1 \
--     tools/tests/run.sh tools/tests/save_celesbreak.lua <log>
-- Then, all through the controller, nothing written:
--   0. the file itself is the old kind: in its slot CELES is level 13 or
--      more, her learned byte for Imp is $FF and for Break is not;
--   1. the load: the $1600-$1FFF block the Continue hands the field is the
--      slot's, byte for byte (read at Ot6EsperContinue), so her learned
--      Break byte is the file's (not $FF) and her Imp byte still $FF;
--   2. the field: Skills > Magic for her lists Break ($7E9D89, the list the
--      menu draws; screenshot save_celesbreak_field) beside the Imp she
--      learned, and her learned bytes are still the file's;
--   3. a random battle: her battle Magic list (the pointer at $302C + her
--      entity offset, four-byte rows) holds Break, her learned bytes are
--      still the file's, and she casts it through the Magic menu at a
--      standing monster with shields: an attack pass used $0C under Magic
--      ($3410), OT6's Break ran for her on that monster (Ot6BreakSpell: X =
--      her, $b6 = $0C), and it took one shield off a body that had shields
--      and was not Broken.
-- Mutant red (Ot6CelesBreak never grants): build/attempts/wt/v051-spellblade/sb2/G/.
local H = dofile("tools/tests/lib/ot6.lua")

local CELES, BREAK, IMP, CMD_MAGIC = 0x06, 0x0C, 0x23, 0x02
local LEARNED = 0x1A6E + 54 * CELES            -- her learned table (actor 6)
local LEVEL = 0x1600 + 37 * CELES + 8
local ZM, CUR = 0x26, 0x4B
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_MAGIC = 0x05, 0x06, 0x0A, 0x1A
local MAGIC_LIST, MAGIC_COLOUR = 0x9D89, 0x9E09
local SHIELDS, BROKEN = 0x3E38, 0x3E88         -- OT6_SHIELD_CUR, OT6_BROKEN_TICKS, by entity offset
local SLOT_PTR = { [1] = 0x0000, [2] = 0x0A00, [3] = 0x1400 }

local function st() return H.menuRunning() and H.readByte(ZM) or -1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- ---- the battery and the Continue (save_golden's) --------------------------
-- battery offset -> SNES address: four 8 KiB windows at $6000 of banks $30-$33
local function bat(o) return (0x300000 + (o >> 13) * 0x10000) + 0x6000 + (o & 0x1FFF) end
local function sram(o) return emu.read(bat(o), emu.memType.snesMemory) end
local B0, slot, target
local function slotByte(a) return B0[SLOT_PTR[slot] + (a - 0x1600)] end
-- the loaded block, read where the Continue's confirm hands the game to the
-- field (Ot6EsperContinue): the menu has copied the slot into $1600-$1FFF
-- and nothing has run on it yet
local loaded = nil
local function atTarget()
  if target.world then
    return H.worldMode() and H.worldX() == target.x and H.worldY() == target.y
  end
  return not H.worldMode() and not H.menuRunning() and (H.mapId() & 0x1ff) == target.map
    and H.fieldX() == target.x and H.fieldY() == target.y
end
local function continue(tag)
  local ph = 0
  return H.seqStep({
    H.waitFrames(350),
    H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
    H.waitFrames(120),
    H.withReset(H.driveUntil(function() return atTarget() and bright() >= 15 end, 2400, {
      H.call(function()
        ph = (ph + 1) % 48
        if atTarget() or bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, tag .. ": Continue slot -> the saved tile"), function() ph = 0 end),
    H.release(),
    H.waitUntil(function() return H.worldHasControl() and bright() >= 15 end, 1800, tag .. ": control after the load", 1),
    H.waitFrames(30),
  })
end

local file = {}          -- what the file's slot holds for her
local function learnedNow() return H.readByte(LEARNED + BREAK), H.readByte(LEARNED + IMP) end
local function assertUntouched(when)
  local b, i = learnedNow()
  H.assertEq(b, file.brk, string.format("%s: CELES's learned byte for Break is the file's ($%02X): nothing was "
    .. "written to her learned table", when, file.brk))
  H.assertEq(i, 0xFF, when .. ": CELES's learned byte for Imp is still $FF: the save keeps the Imp it learned")
end

-- ---- the field's Skills > Magic list (battle_shieldgrant's walk) -----------
local function pos() return (H.readByte(0x1850 + CELES) >> 3) & 3 end
local function openMagic(tag)
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, tag .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_MAIN and H.readByte(CUR) == 1 end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300, tag .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_CHAR and H.readByte(CUR) == pos() end, 600,
      { H.pressButtons({ "down" }, 2), H.waitFrames(10) }, tag .. ": cursor on CELES"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300, tag .. ": skills submenu", 5),
    H.waitFrames(10),
    H.driveUntil(function() return st() == ST_SKILLS and H.readByte(CUR) == 1 end, 600,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) }, tag .. ": cursor on Magic"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_MAGIC end, 500, tag .. ": magic list", 5),
    H.waitFrames(120),
  })
end
local function closeMenu(tag)
  return H.seqStep({
    H.driveUntil(function() return st() == -1 and H.worldHasControl() and H.worldSettled() end, 1500,
      { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, tag .. ": menu closed"),
    H.waitFrames(30),
  })
end
local function fieldIndex(spell)
  for i = 0, 0x35 do
    if H.readByte(MAGIC_LIST + i) == spell then return i end
  end
end

-- ---- the battle ------------------------------------------------------------
local seat, tgt = nil, nil
local passes = {}        -- $3410 <- $0C under Magic: { b8, b9, f }
local takes = {}         -- Ot6BreakSpell for her: { y, shields, broken, f, after }
local ended = nil        -- her Ot6ActionEnd after a take: { cmd, atk, f }
local function arm()
  emu.addMemoryCallback(function(_, v)
    if v ~= BREAK or seat == nil or H.readByte(0x3A7C) ~= CMD_MAGIC then return end
    passes[#passes + 1] = { b8 = H.readByte(0xB8), b9 = H.readByte(0xB9), f = H.frame }
    H.log(string.format("[celesbreak] f%d an attack pass uses spell $0C under Magic: targets chars $%02X mons $%02X",
      H.frame, H.readByte(0xB8), H.readByte(0xB9)))
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  local bs = H.sym("Ot6BreakSpell")
  emu.addMemoryCallback(function()
    if seat == nil then return end
    local stt = emu.getState()
    local x, y = stt["cpu.x"] & 0xFF, stt["cpu.y"] & 0xFF
    if x ~= seat * 2 or H.readByte(0xB6) ~= BREAK or y < 8 then return end
    takes[#takes + 1] = { y = y, shields = H.readByte(SHIELDS + y), broken = H.readByte(BROKEN + y), f = H.frame,
      cmd = H.readByte(0x3A7C) }
    H.log(string.format("[celesbreak] f%d Ot6BreakSpell: attacker entity %d (CELES), target entity %d with %d shield(s), "
      .. "broken ticks %d, command $%02X", H.frame, x, y, H.readByte(SHIELDS + y), H.readByte(BROKEN + y),
      H.readByte(0x3A7C)))
  end, emu.callbackType.exec, bs, bs)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if seat == nil or (emu.getState()["cpu.x"] & 0xFF) ~= seat * 2 then return end
    local t = takes[#takes]
    if t == nil or t.after ~= nil then return end
    t.after = H.readByte(SHIELDS + t.y)
    ended = { cmd = H.readByte(0x3A7C), atk = H.readByte(0x3A7D), f = H.frame }
    H.log(string.format("[celesbreak] f%d CELES's Ot6ActionEnd: command $%02X attack $%02X; the target's shields %d -> %d",
      H.frame, ended.cmd, ended.atk, t.shields, t.after))
  end, emu.callbackType.exec, ae, ae)
end
local function standing(m)
  return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0
end
local A, B = nil, nil
local function toBattle()
  return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
    H.call(function()
      if A ~= nil then return end
      local x0, y0 = H.worldX(), H.worldY()
      for _, d in ipairs({ { 0, 2 }, { 0, -2 }, { 2, 0 }, { -2, 0 }, { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }) do
        if H.worldBfs(x0 + d[1], y0 + d[2]) then A, B = { x0, y0 }, { x0 + d[1], y0 + d[2] }; break end
      end
      H.assertEq(A ~= nil, true, string.format("a walkable pace from world (%d,%d)", x0, y0))
      H.log(string.format("[celesbreak] pacing world (%d,%d) <-> (%d,%d)", A[1], A[2], B[1], B[2]))
    end),
    H.worldNavTo(function() return B[1] end, function() return B[2] end,
      { maxFrames = 8000, arrive = function() return H.battleLoadStarted() end }),
    H.call(function() A, B = B, A end),
  }, "a random battle on the world map")
end
local plan, battles, BATTLES, played = { {} }, 0, 6, false

H.run({ maxFrames = 400000 }, {
  H.call(function()
    B0 = {}
    for o = 0, 0x7FFF do B0[o] = sram(o) end
    slot = B0[0x1FF0]
    H.assertEq(slot, 3, "the battery last saved slot 3 ($1FF0), as every release save does")
    local word = slotByte(0x1F64) | (slotByte(0x1F65) << 8)
    local map = word & 0x1ff
    H.assertEq(map <= 1, true, "the golden save was made on the world map (v0.50's wor-cyan-v1, beside the Falcon)")
    target = { world = true, map = map, x = slotByte(0x1F60), y = slotByte(0x1F61) }
    -- 0. the file is an old save
    file.level, file.brk, file.imp = slotByte(LEVEL), slotByte(LEARNED + BREAK), slotByte(LEARNED + IMP)
    H.log(string.format("[celesbreak] the file's slot %d: CELES level %d, learned Break $%02X, learned Imp $%02X; saved "
      .. "on world %d at (%d,%d)", slot, file.level, file.brk, file.imp, map, target.x, target.y))
    H.assertEq(file.level >= 13, true, "the file: CELES is level 13 or more")
    H.assertEq(file.imp, 0xFF, "the file: CELES has learned Imp (a save from before Break took its place)")
    H.assertEq(file.brk ~= 0xFF, true, "the file: CELES has not learned Break")
    local at = H.sym("Ot6EsperContinue")
    emu.addMemoryCallback(function()
      loaded = {}
      for a = 0x1600, 0x1FFF do loaded[a] = H.readByte(a) end
    end, emu.callbackType.exec, at, at)
    arm()
  end),
  continue("load"),
  -- 1. the load
  H.call(function()
    H.assertEq(loaded ~= nil, true, "the Continue's confirm ran Ot6EsperContinue")
    local bad = 0
    for a = 0x1600, 0x1FFF do
      if loaded[a] ~= slotByte(a) then
        bad = bad + 1
        if bad <= 12 then
          H.log(string.format("[celesbreak] $%04X loaded %02X, the slot holds %02X", a, loaded[a], slotByte(a)))
        end
      end
    end
    H.assertEq(bad, 0, "1: the loaded $1600-$1FFF block is the slot's, byte for byte")
    H.assertEq(loaded[LEARNED + BREAK], file.brk, "1: at the load CELES's learned byte for Break is the file's")
    H.assertEq(loaded[LEARNED + BREAK] ~= 0xFF, true, "1: ... and not $FF: nothing was written")
    H.assertEq(loaded[LEARNED + IMP], 0xFF, "1: at the load her learned byte for Imp is still $FF")
    assertUntouched("1, with control on the map")
    local pb = H.readByte(0x1850 + CELES)
    H.assertEq((pb & 7) ~= 0 and (pb & 7) == (H.readByte(0x1A6D) & 7), true, "CELES is seated in the loaded party")
    H.assertEq(H.readByte(LEVEL), file.level, "her level is the file's")
  end),
  H.fieldCare({ tag = "celesbreak: care before the menu", threshold = 0.95 }),
  H.waitUntil(function() return H.worldHasControl() end, 3000, "world control after the care", 5),
  -- 2. the field Magic list
  openMagic("2"),
  H.call(function()
    local t = {}
    for i = 0, 0x35 do
      local id = H.readByte(MAGIC_LIST + i)
      if id ~= 0xFF then t[#t + 1] = string.format("%02X/%02X", id, H.readByte(MAGIC_COLOUR + i)) end
    end
    H.log("[celesbreak] 2: CELES's field Magic list (spell/colour): " .. table.concat(t, " "))
    local i = fieldIndex(BREAK)
    H.assertEq(i ~= nil, true, "2: Break is in CELES's field Magic list (granted by her level, Ot6FieldSpellKnown)")
    H.assertEq(fieldIndex(IMP) ~= nil, true, "2: the Imp she learned is in the list too")
    assertUntouched("2, with the list open")
    H.screenshot("save_celesbreak_field")
  end),
  closeMenu("2"),
  H.call(function() assertUntouched("2, back on the map") end),
  -- 3. battles until her cast lands (one she cannot act in is fought out
  -- and the next taken, up to BATTLES)
  H.driveUntil(function() return played and not H.battleLoadStarted() end, 300000, {
    H.cond(function() return not H.battleLoadStarted() end, {
      H.waitUntil(function() return H.worldHasControl() end, 3000, "3: world control", 5),
      H.fieldCare({ tag = "celesbreak: care before a battle", threshold = 0.95 }),
      H.waitUntil(function() return H.worldHasControl() end, 3000, "3: world control after the care", 5),
      toBattle(),
      H.waitUntil(function() return H.battleActive() end, 1200, "3: the battle is up", 2),
      H.waitFrames(30),
    }, {}),
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= BATTLES, true, string.format("3: the cast within %d battles", BATTLES))
      seat = nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == CELES then seat = s end end
      H.assertEq(seat ~= nil, true, "3: CELES is seated in the battle")
      H.assertEq(H.readWord(0x3BF4 + seat * 2) > 0, true, "3: she stands at the battle's open (the care saw to it)")
      local base, cell, list = H.readWord(0x302C + seat * 2), nil, {}
      for k = 1, 54 do
        local id = H.readByte(base + k * 4)
        if id ~= 0xFF then list[#list + 1] = string.format("%02X", id) end
        if id == BREAK then cell = k end
      end
      H.log(string.format("[celesbreak] 3: battle %d, CELES seat %d, MP %d; her battle Magic list: %s", battles, seat,
        H.readWord(0x3C08 + seat * 2), table.concat(list, " ")))
      H.assertEq(cell ~= nil, true, "3: Break has a cell in CELES's battle Magic list (Ot6UnionEspers, "
        .. "Ot6EsperSpellKnown)")
      assertUntouched("3, with the battle up")
      -- the target: the standing, unbroken body with the most shields
      tgt = nil
      for m = 0, 5 do
        local e = 8 + m * 2
        if standing(m) and H.readByte(BROKEN + e) == 0 and H.readByte(SHIELDS + e) > 0
            and (tgt == nil or H.readByte(SHIELDS + e) > H.readByte(SHIELDS + 8 + tgt * 2)) then
          tgt = m
        end
      end
      H.assertEq(tgt ~= nil, true, "3: a standing monster with shields, not Broken, to cast Break at")
      H.log(string.format("[celesbreak] 3: the target is monster slot %d with %d shield(s)", tgt,
        H.readByte(SHIELDS + 8 + tgt * 2)))
      plan[1] = { who = CELES, cmd = CMD_MAGIC, spell = BREAK, slot = tgt, boost = 0 }
    end),
    H.kitBattle(plan, { untilPlanDone = true, idle = "defend", maxFrames = 60000,
      planDone = function() return ended ~= nil and H.frame > ended.f + 60 end }),
    H.call(function()
      if ended == nil then
        H.log(string.format("[celesbreak] 3: battle %d ended without her cast; the next", battles))
        return
      end
      local t = takes[#takes]
      H.assertEq(#passes > 0, true, "3: an attack pass used spell $0C under Magic ($3410)")
      H.assertEq(passes[#passes].b8 == 0 and passes[#passes].b9 ~= 0, true, "3: ... aimed at the monsters")
      H.assertEq(ended.cmd, CMD_MAGIC, "3: CELES's turn ran the Magic command")
      H.assertEq(ended.atk, BREAK, "3: ... and the attack was Break ($0C)")
      H.assertEq(t.y, 8 + tgt * 2, "3: OT6's Break ran for her on the monster she aimed at (Ot6BreakSpell)")
      if t.shields > 0 and t.broken == 0 then
        H.assertEq(t.after, t.shields - 1, string.format("3: her Break took one shield off the target (%d -> %d)",
          t.shields, t.after))
      else
        H.log(string.format("[celesbreak] 3: the target had %d shield(s), broken ticks %d, when the cast landed: "
          .. "nothing to take", t.shields, t.broken))
      end
      H.assertEq(t.shields > 0 and t.broken == 0, true, "3: the target still had shields and was not Broken when "
        .. "the cast landed (everyone else Defended)")
      played = true
      H.screenshot("save_celesbreak_battle")
    end),
    H.cond(function() return H.battleLoadStarted() end, { H.kitBattle({}, { maxFrames = 60000 }) }, {}),
  }, "3: CELES casts Break"),
  H.call(function()
    H.log(string.format("[celesbreak] PASS: an old save's CELES (L%d, learned Break $%02X, Imp $FF) has Break in the "
      .. "field and in battle, cast it and took a shield; her learned table was never written", file.level, file.brk))
  end),
})
