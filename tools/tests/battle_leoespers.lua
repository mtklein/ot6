-- @suite slow savestate=wor_leo
-- battle_leoespers.lua -- the revealed Leo wears espers (#552 piece F, docs/design/leo-reveal.md "Espers").
--
-- Gogo's slot keeps actor $0C after the reveal; once switch $00E0 is set he wears a stone like actors 0-11, and
-- his Magic Points live in the esper pages' row 12 (save layout version 2, docs/design/save-layout.md).  Played
-- through the real menus and battles, from two of gen_wor_leo's states:
--   before  wor_leo_pre (Thamasa's street, GOGO seated, switch $00E0 clear): the Skills list's Espers row is grey
--           for him ($79 = $24) and A on it opens nothing (the menu stays on the Skills list); he wears nothing;
--   after   wor_leo (the world map by Thamasa after the reveal and its save, LEO seated):
--     1. Magic picked into one of his three command rows on the Status screen when he lacks it (the stage the
--        summon needs: the esper's row sits above the Magic grid);
--     2. the Skills list's Espers row is white for him ($20), and an owned stone E that nobody wears is put on him
--        through Skills -> Espers -> its page -> A (H.equipEsper): record 12's +$1E reads E.  E is the first such
--        stone with a spell S that none of the three others knows, nor gets from a worn stone or item, nor GOGO's
--        Lore carry (so only his own stone can put S in the battle union);
--     3. random battles on the shore by Thamasa, fought through the menus (H.kitBattle: LEO's Magic -> the esper
--        row -> the target, the others Fight): at each battle's open his Magic list (the battle union, which
--        Gogo's slot takes whole) holds S (Ot6UnionEspers) and its esper row is E; Cmd_19 (Summon) runs for his
--        seat with E's summon ($36 + E); at each victory he is alive for, his row-12 counter for E gains the
--        formation's Magic Points doubled (a random battle; capped at 9999) and his other counters do not move;
--        the victory screen shows "<LEO>: esper rank r" ($49) for his seat exactly when the count
--        crossed a rung; and every battle's open has his vigor, speed, stamina and magic power ($3b2c/2, $3b19,
--        $3b40, $3b41) at the first battle's plus the stat points of every rung he holds (Ot6LadderTbl, read from
--        the ROM): Ot6EsperFold folds his kept rungs.  Battles go on until he has reached rung 1 and a battle has
--        opened after it (at most ten);
--     4. a save through the Save menu (slot 3): the block is layout version 2 and slot 3's esper page row 12 is
--        the live row; the console's Reset (tools/state_write_waivers.txt), the title, Continue slot 3: the live
--        row 12 is the saved one and he still wears E.
-- The old-save half of the round trip is the golden suite's (save_golden.lua: every release's save loads with
-- row 12 reading as no progress, the junk saves' $FF rows included).
-- Mutant ROMs (tools/build/mutant_rom.py) that must turn this red, one per property: Ot6LeoGenjuRow=60 (his
-- Espers row stays grey after the reveal), Ot6LeoGenjuRow+4=A901 (white before it), Ot6UnionLeo=3860 (S not in
-- his list), VictoryLeo+4=EAEAEAEA (no earn), FoldHolder=38EAEA (no fold), LeoRowGate=EAEA (the Continue
-- drops row 12).  Screenshots (build/states/shots/battle_leoespers_*).
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 0x0C
local REC = 0x1600 + 37 * GOGO
local SW_BYTE, SW_BIT = 0x1E9C, 0x01             -- event switch $00E0
local CMD_MAGIC, CMD_ITEM, CMD_MIMIC = 0x02, 0x01, 0x12
local GENJU_COLOR = 0x79                         -- zSkillsTextColor::Genju
local WHITE, GREY = 0x20, 0x24
local LIVE, SLOT3 = 0x317C00, 0x317800
local LEO_ROW = 0x280                            -- row 12's page offset
local COSTS = { 10, 30, 75, 200, 500 }
local FALCON, SHORE = { 250, 229 }, { 250, 235 }
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST = 0x05, 0x06, 0x0A, 0x1E
local LADDER = H.sym("Ot6LadderTbl") & 0x3FFFFF
local GENJU = H.sym("GenjuProp") & 0x3FFFFF
local GRANTS = H.sym("Ot6ItemGrantTbl") & 0x3FFFFF
local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function sramW(a) return sram(a) | (sram(a + 1) << 8) end
local function rom(a) return emu.read(a, emu.memType.snesPrgRom) end
local function slotOf(e) if e < 12 then return e elseif e == 12 then return 11 else return e - 1 end end
local function rankOf(n) local r = 0; for _, c in ipairs(COSTS) do if n >= c then r = r + 1 end end; return r end
local function count(page, actor, e) return sramW(page + 0x10 + (actor * 26 + slotOf(e)) * 2) end
local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
local function ctl() if H.worldMode() then return H.worldHasControl() end return H.hasControl() end
local function worn(c) return H.readByte(0x1600 + 37 * c + 0x1E) end
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.activeParty() end
local function posOf(c) return (H.readByte(0x1850 + c) >> 3) & 3 end
local function stoneSpells(e)
  local t = {}
  for _, o in ipairs({ 1, 3, 5, 7, 9 }) do
    local s = rom(GENJU + e * 11 + o)
    if s ~= 0xFF then t[#t + 1] = s end
  end
  return t
end
local function owned(e) return (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 end

-- ---- the Skills list for GOGO's slot: its Espers row's colour, and whether A on it opens the list ----------
local function skillsRow(tag, out)
  local ph, phase, presses, held0 = 0, "in", 0, nil
  return H.withReset(H.driveUntil(function() return phase == "done" and not H.menuRunning() and ctl() end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if phase == "in" then
        if s == -1 then
          if ctl() then held = { "x" } end
        elseif s == ST_MAIN then
          held = H.readByte(0x4B) == 1 and { "a" } or { [H.readByte(0x4B) < 1 and "down" or "up"] = true }
        elseif s == ST_CHAR then
          local p = posOf(GOGO)
          held = H.readByte(0x4B) == p and { "a" } or { [H.readByte(0x4B) < p and "down" or "up"] = true }
        elseif s == ST_SKILLS then
          if H.readByte(0x4B) ~= 0 then held = { up = true }
          else
            if out.color == nil then
              out.color = H.readByte(GENJU_COLOR)
              H.screenshot("battle_leoespers_" .. tag .. "_skills")
            end
            if ph == 0 then presses = presses + 1 end
            held = { "a" }
            if presses > 3 then phase = "out" end
          end
        elseif s == ST_LIST then
          out.opened = true
          phase = "out"
        end
      else
        if s ~= -1 then held = { "b" } else phase = "done" end
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, tag .. ": the Skills list for GOGO's slot"), function() ph, phase, presses = 0, "in", 0 end)
end

-- ---- Magic into one of his three rows (battle_leoshock's walk through the Status screen) --------------------
local magicRow = nil
local function pickMagic()
  local ph, done = 0, false
  return H.withReset(H.driveUntil(function() return done and not H.menuRunning() and ctl() end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if H.readByte(REC + 0x16 + magicRow) == CMD_MAGIC and s ~= 0x6A then done = true end
      if done then
        if s ~= -1 then held = { "b" } end
      elseif s == -1 then
        if ctl() then held = { "x" } end
      elseif s == 0x05 then
        held = H.readByte(0x4B) == 4 and { "a" } or { [H.readByte(0x4B) < 4 and "down" or "up"] = true }
      elseif s == 0x06 then
        local p = posOf(GOGO)
        held = H.readByte(0x4B) == p and { "a" } or { [H.readByte(0x4B) < p and "down" or "up"] = true }
      elseif s == 0x0C then
        held = H.readByte(0x4B) == magicRow and { "a" } or { [H.readByte(0x4B) < magicRow and "down" or "up"] = true }
      elseif s == 0x6A then
        local n, want = H.readByte(0x7E9D89), nil
        for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == CMD_MAGIC then want = r end end
        if want == nil then error("Magic is not in his command list", 0) end
        held = H.readByte(0x4B) == want and { "a" } or { [H.readByte(0x4B) < want and "down" or "up"] = true }
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, "Magic into his command row " .. tostring(magicRow)), function() ph, done = 0, false end)
end

-- ---- the stone and its spell --------------------------------------------------------------------------------
local E, S = nil, nil
local function pickStone()
  local others = {}
  for c = 0, 11 do if seated(c) then others[#others + 1] = c end end
  local known = {}
  for _, c in ipairs(others) do
    for s = 0, 53 do if H.readByte(0x1A6E + c * 54 + s) == 0xFF then known[s] = true end end
  end
  for c = 0, 15 do
    if c == GOGO or (c < 12 and seated(c)) then
      if c ~= GOGO and worn(c) < 27 then for _, s in ipairs(stoneSpells(worn(c))) do known[s] = true end end
      -- worn items' grants (Ot6ItemGrantTbl: item, spell pairs ended by $ff), his own included
      local i = 0
      while rom(GRANTS + i) ~= 0xFF do
        local item, s = rom(GRANTS + i), rom(GRANTS + i + 1)
        for o = 0x1F, 0x24 do if H.readByte(0x1600 + 37 * c + o) == item then known[s] = true end end
        i = i + 2
      end
    end
  end
  -- GOGO carrying Lore has Strago's Scan ($18) and Bserk ($21) (Ot6UnionEspers' Lore carry): never the probe
  known[0x18], known[0x21] = true, true
  local function wornBy(e) for c = 0, 15 do if worn(c) == e then return c end end end
  for e = 0, 26 do
    if owned(e) and wornBy(e) == nil then
      for _, s in ipairs(stoneSpells(e)) do
        if not known[s] then E, S = e, s; break end
      end
    end
    if E then break end
  end
  H.log(string.format("[leoespers] seated others %s; the stone E = %s, its spell S = %s that nobody else has",
    table.concat(others, ","), tostring(E), tostring(S)))
  H.assertEq(E ~= nil, true, "an owned stone nobody wears with a spell none of the others has (the save's espers)")
end

-- ---- battle records -----------------------------------------------------------------------------------------
local seat, battle = nil, nil
local summons, msgs = {}, {}
local armed = false
local function arm()
  if armed then return end
  armed = true
  local c19 = H.sym("Cmd_19")
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if seat ~= nil and y == seat * 2 then
      summons[#summons + 1] = { atk = H.readByte(0xB6), f = H.frame }
      H.log(string.format("[leoespers] f%d Cmd_19 (Summon) by LEO's seat %d: attack $%02X", H.frame, seat,
        H.readByte(0xB6)))
    end
  end, emu.callbackType.exec, c19, c19)
  local show = H.sym("Ot6ShowMsg")
  emu.addMemoryCallback(function()
    if battle then msgs[#msgs + 1] = { id = emu.getState()["cpu.a"] & 0xFF, v0 = H.readWord(0x2F35),
      who = H.readByte(0x2F38) } end
  end, emu.callbackType.exec, show, show)
end

local function counts()
  local t = {}
  for a = 0, 12 do t[a] = {}; for s = 0, 25 do t[a][s] = sramW(LIVE + 0x10 + (a * 26 + s) * 2) end end
  return t
end
-- the stat points (vigor, speed, stamina, magic) of every rung LEO holds, from Ot6LadderTbl
local function bonus()
  local b = { 0, 0, 0, 0 }
  for s = 0, 25 do
    local r = rankOf(sramW(LIVE + 0x10 + (12 * 26 + s) * 2))
    for k = 0, r - 1 do
      for i = 1, 4 do b[i] = b[i] + rom(LADDER + (s * 5 + k) * 14 + 9 + i) end
    end
  end
  return b
end
local function stats(e)
  return { H.readByte(0x3B2C + e) // 2, H.readByte(0x3B19 + e), H.readByte(0x3B40 + e), H.readByte(0x3B41 + e) }
end
local base, nBattles, reached, afterReach = nil, 0, false, false

local function openBattle()
  seat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GOGO then seat = s end end
  H.assertEq(seat ~= nil, true, "LEO (actor $0C) is seated")
  nBattles = nBattles + 1
  local e = seat * 2
  local lists = { [0] = 0x208E, 0x21CA, 0x2306, 0x2442 }
  local held = false
  for i = 0, 53 do if H.readByte(lists[seat] + 4 + i * 4) == S then held = true end end
  battle = { form = H.readWord(0x3ED4), rand = H.readByte(0x57BD), before = counts(),
    leo0 = count(LIVE, 12, E), stats = stats(e), bonus = bonus() }
  msgs = {}
  H.log(string.format("[leoespers] battle %d: formation $%03X random=%d; LEO seat %d, esper row $%02X, S $%02X in his "
    .. "list %s; count on E %d (rank %d); vigor %d speed %d stamina %d magic %d; held rungs' points %d/%d/%d/%d",
    nBattles, battle.form, battle.rand, seat, H.readByte(lists[seat]), S, tostring(held), battle.leo0,
    rankOf(battle.leo0), battle.stats[1], battle.stats[2], battle.stats[3], battle.stats[4], battle.bonus[1],
    battle.bonus[2], battle.bonus[3], battle.bonus[4]))
  if nBattles == 1 then H.screenshot("battle_leoespers_open") end
  H.assertEq(H.readByte(lists[seat]), E, "his Magic list's esper row is the stone he wears")
  H.assertEq(held, true, string.format("his battle Magic list holds $%02X, which only his stone grants (the union)", S))
  if base == nil then
    base = {}
    for i = 1, 4 do base[i] = battle.stats[i] - battle.bonus[i] end
  end
  for i, what in ipairs({ "vigor", "speed", "stamina", "magic power" }) do
    H.assertEq(battle.stats[i], base[i] + battle.bonus[i], string.format("battle %d: his %s is the first battle's plus "
      .. "the stat points of the rungs he holds (Ot6EsperFold)", nBattles, what))
  end
  if reached then afterReach = true end
end

local function closeBattle()
  local mp = 0
  if battle.form < 0x200 then mp = rom((H.sym("BattleMagicPoints") & 0x3FFFFF) + battle.form) end
  local pts = mp * (battle.rand == 1 and 2 or 1)
  local after = counts()
  local alive = H.readWord(REC + 0x09) > 0 and (H.readByte(REC + 0x14) & 0xC2) == 0
  local d = after[12][slotOf(E)] - battle.before[12][slotOf(E)]
  H.log(string.format("[leoespers] battle %d over: formation pays %d Magic Points (%d %s); LEO %s, his count on E "
    .. "%d -> %d", nBattles, mp, pts, battle.rand == 1 and "doubled" or "plain", alive and "alive" or "down",
    battle.before[12][slotOf(E)], after[12][slotOf(E)]))
  for _, m in ipairs(msgs) do H.log(string.format("[leoespers] message $%02X v0=%d who=%d", m.id, m.v0, m.who)) end
  if alive then
    H.assertEq(d, math.min(battle.before[12][slotOf(E)] + pts, 9999) - battle.before[12][slotOf(E)],
      string.format("battle %d: LEO's row-12 counter for the stone he wears gained the battle's Magic Points", nBattles))
  else
    H.assertEq(d, 0, string.format("battle %d: a fallen LEO earned nothing", nBattles))
  end
  for s2 = 0, 25 do
    if s2 ~= slotOf(E) then
      H.assertEq(after[12][s2], battle.before[12][s2], string.format("his counter for esper slot %d did not move", s2))
    end
  end
  local r0, r1 = rankOf(battle.before[12][slotOf(E)]), rankOf(after[12][slotOf(E)])
  local said = nil
  for _, m in ipairs(msgs) do if m.id == 0x49 and m.who == seat then said = m.v0 end end
  H.assertEq(said, r1 > r0 and r1 or nil, string.format("battle %d: the rank line for his seat shows exactly when his "
    .. "count crosses a rung (%d -> %d)", nBattles, r0, r1))
  if r1 >= 1 then reached = true end
  battle = nil
end

local function shoreBattle()
  local wp = 1
  local pts = { SHORE, FALCON }
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return pts[wp][1] end, function() return pts[wp][2] end,
        { maxFrames = 6000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % 2 + 1 end),
    }, "a random battle on the shore"),
    H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
    H.call(openBattle),
    H.kitBattle({ { who = GOGO, cmd = CMD_MAGIC, summon = true, boost = 0 } },
      { others = "fight", maxFrames = 60000 }),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.call(closeBattle),
    H.fieldCare({ tag = "care between battles" }),
  })
end

local savedRow, continued = nil, 0
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

H.run({ maxFrames = 600000 }, {
  -- before the reveal
  H.loadState("build/states/wor_leo_pre.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(SW_BYTE) & SW_BIT, 0, "wor_leo_pre: switch $00E0 clear (before the reveal)")
    H.assertEq(seated(GOGO), true, "wor_leo_pre: GOGO seated")
    H.assertEq(worn(GOGO), 0xFF, "wor_leo_pre: GOGO wears no stone")
  end),
  (function()
    local out = {}
    return H.seqStep({
      skillsRow("pre", out),
      H.call(function()
        H.log(string.format("[leoespers] before: GOGO's Espers row colour $%02X, the list opened: %s", out.color or -1,
          tostring(out.opened)))
        H.assertEq(out.color, GREY, "before the reveal: GOGO's Espers row is grey")
        H.assertEq(out.opened == true, false, "before the reveal: A on it opens no esper list")
        H.assertEq(worn(GOGO), 0xFF, "before the reveal: GOGO still wears nothing")
      end),
    })
  end)(),
  -- after the reveal
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    arm()
    H.assertEq(H.readByte(SW_BYTE) & SW_BIT, SW_BIT, "wor_leo: switch $00E0 set (gen_wor_leo's reveal)")
    H.assertEq(H.readByte(REC + 1), 0x10, "slot 12 wears Leo's sprite")
    H.assertEq(worn(GOGO), 0xFF, "LEO starts wearing nothing")
    H.assertEq(count(LIVE, 12, 0), 0, "and with no progress")
    local t = {}
    for r = 0, 3 do t[#t + 1] = string.format("%02X", H.readByte(REC + 0x16 + r)) end
    H.log("[leoespers] LEO's commands: " .. table.concat(t, " "))
    for r = 1, 3 do if H.readByte(REC + 0x16 + r) == CMD_MAGIC then magicRow = r end end
    if magicRow == nil then
      for r = 3, 1, -1 do
        if magicRow == nil and H.readByte(REC + 0x16 + r) ~= CMD_ITEM then magicRow = r end
      end
    end
    pickStone()
  end),
  H.lazy(function()
    if H.readByte(REC + 0x16 + magicRow) == CMD_MAGIC then return H.logStep("[leoespers] he carries Magic already") end
    return pickMagic()
  end),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x16 + magicRow), CMD_MAGIC, "Magic in his command row " .. magicRow)
  end),
  (function()
    local out = {}
    return H.seqStep({
      skillsRow("post", out),
      H.call(function()
        H.log(string.format("[leoespers] after: LEO's Espers row colour $%02X, the list opened: %s", out.color or -1,
          tostring(out.opened)))
        H.assertEq(out.color, WHITE, "after the reveal: LEO's Espers row is white")
        H.assertEq(out.opened, true, "after the reveal: A on it opens the esper list")
      end),
    })
  end)(),
  H.lazy(function()
    return H.equipEsper(function() return posOf(GOGO) end, E, { tag = "the stone -> LEO" })
  end),
  H.call(function()
    H.assertEq(worn(GOGO), E, string.format("LEO wears the stone (record 12's +$1E = $%02X)", E))
  end),
  H.driveUntil(function() return afterReach end, 500000, {
    H.call(function() H.assertEq(nBattles < 10, true, "rung 1 reached and a battle opened after it, within ten") end),
    shoreBattle(),
  }, "battles until his first rung is held in a battle"),
  H.call(function()
    H.assertEq(#summons > 0, true, "Cmd_19 (Summon) ran for LEO's seat")
    for _, s in ipairs(summons) do
      H.assertEq(s.atk, 0x36 + E, string.format("the summon was his stone's ($%02X)", 0x36 + E))
    end
  end),
  -- the save and the Continue
  H.saveGame({ slot = 3, baseline = false, tag = "the save after LEO's battles" }),
  H.call(function()
    local blockVer = sram(0x306000 + 0x1400 + (0x1E2E - 0x1600))
    H.assertEq(blockVer, 2, "the saved block is layout version 2")
    savedRow = {}
    local nz = 0
    for o = 0, 51 do
      savedRow[o] = sram(SLOT3 + LEO_ROW + o)
      H.assertEq(savedRow[o], sram(LIVE + LEO_ROW + o), string.format("slot 3's row 12 byte %d is the live row's", o))
      if savedRow[o] ~= 0 then nz = nz + 1 end
    end
    H.assertEq(nz > 0, true, "slot 3's row 12 holds his progress")
    local c = H.sym("Ot6EsperContinue")
    emu.addMemoryCallback(function() continued = continued + 1 end, emu.callbackType.exec, c, c)
    H.log(string.format("[leoespers] saved: version %d, row 12's count on E %d; the console's Reset", blockVer,
      count(SLOT3, 12, E)))
    H.expectTitle("battle_leoespers: the console's Reset before the Continue")
    emu.reset()
  end),
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.withReset(H.driveUntil(function()
      return continued > 0 and H.worldMode() and H.worldHasControl() and bright() >= 15
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 48
        if continued > 0 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "Continue slot 3 -> the world map"), function() ph = 0 end)
  end)(),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(continued, 1, "the title's Continue ran (Ot6EsperContinue)")
    for o = 0, 51 do
      H.assertEq(sram(LIVE + LEO_ROW + o), savedRow[o], string.format("after the Continue, live row 12 byte %d is the "
        .. "saved one", o))
    end
    H.assertEq(worn(GOGO), E, "after the Continue, LEO still wears the stone")
    H.log(string.format("[leoespers] PASS: LEO wears $%02X, summons it, earns and keeps its ranks (count %d), and the "
      .. "save carries row 12 through a Continue; before the reveal GOGO had no Espers row", E, count(LIVE, 12, E)))
  end),
})
