-- @suite slow savestate=wor_leo
-- battle_leoespers.lua -- the revealed Leo's esper is one of his picks (#552 piece F, docs/design/leo-reveal.md
-- "Espers"; the owner, 2026-11-23).
--
-- Gogo's slot keeps actor $0C after the reveal.  Once switch $00E0 is set, Gogo's Status-screen command picker
-- offers Summon ($19, BattleCmdName "Summon"); while it is one of his picks he wears a stone like actors 0-11 (the
-- Skills list's Espers page, ranks and progress in the esper pages' row 12, save layout version 2, and the Summon
-- command casts it); unpicked, a stone he wore stays in his record and does nothing.  Played through the real
-- menus and battles, from two of gen_wor_leo's states:
--   before  wor_leo_pre (Thamasa's street, GOGO seated, switch $00E0 clear): his command picker holds no Summon,
--           the Skills list's Espers row is grey for him ($79 = $24) and A on it opens nothing; he wears nothing;
--   after   wor_leo (the world map by Thamasa after the reveal and its save, LEO seated):
--     1. unpicked: the picker offers Summon; his Espers row is still grey and closed;
--     2. Summon picked into a row (not Item or Lore): the Espers row is white, and an owned stone E that nobody
--        wears goes on him through Skills -> Espers -> its page -> A (H.equipEsper).  E is the first such stone
--        with a spell S that none of the three others knows, nor gets from a worn stone or item, nor GOGO's Lore
--        carry (so only his own stone can put S in his lists).  Magic picked into row 1 (Lore's) and Fight into
--        row 3 (Item's: the fight-out's verb once Summon greys); his field Magic list holds S;
--     3. random battles on the shore by Thamasa through the menus (H.kitBattle: LEO's Summon -> the target, the
--        others Fight): at each open his battle Magic list holds S (the union) and its esper row is E; Cmd_19
--        runs for his seat with E's summon ($36 + E), once a battle (the Summon command greys once spent); at
--        each victory he lives through, his row-12 count on E
--        gains the formation's Magic Points doubled (a random battle) and his other counts stay; the rank line
--        ($49) shows for his seat exactly when the count crosses a rung; every open has his vigor, speed, stamina
--        and magic power ($3b2c/2, $3b19, $3b40, $3b41) at the first battle's plus the stat points of every rung
--        he holds (Ot6LadderTbl, from the ROM).  Until he holds rung 1 in a battle (at most ten);
--     4. unpicked (his old command back in the row): the Espers row grey again, the stone still in his record;
--        one battle: no esper row ($ff) and no stone in $3344 for his seat, S not in his list, his stats the
--        first battle's without the rungs, no summon, and his counts do not move;
--     5. Summon picked again: the Espers row white, the stone his; one battle: the esper row E, S, the rungs'
--        stats back;
--     6. a save (slot 3): layout version 2, slot 3's row 12 the live row; the console's Reset
--        (tools/state_write_waivers.txt), Continue slot 3: the live row 12 the saved one, the stone still his.
-- The old-save half of the round trip is the golden suite's (save_golden.lua: every release's save loads with
-- row 12 reading as no progress, the junk saves' $FF rows included).
-- Mutant ROMs that must turn this red (build/attempts/wt/v051-leo-espers/mutants.sh): Ot6LeoSummonList=60 (no
-- Summon offered), Ot6LeoSummonList+4=A901 (offered before the reveal), Ot6LeoGenjuRow=60 (Espers grey when
-- picked), Ot6UnionLeo=3860, FieldLeo=38EAEA, VictoryLeo+4=EAEAEAEA, FoldHolder=38EAEA, PickGate=EAEA (the pick
-- ignored: unpicked still earns), InertGate=80 (unpicked keeps the summon), UpdateCmd_08=1860 (Summon every
-- turn), LeoRowGate=EAEA (the Continue drops row 12).  Screenshots (build/states/shots/battle_leoespers_*).
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 0x0C
local REC = 0x1600 + 37 * GOGO
local SW_BYTE, SW_BIT = 0x1E9C, 0x01             -- event switch $00E0
local CMD_ITEM, CMD_LORE, CMD_SUMMON = 0x01, 0x0C, 0x19
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
local LISTS = { [0] = 0x208E, 0x21CA, 0x2306, 0x2442 }
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
local function has(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end
local function stoneSpells(e)
  local t = {}
  for _, o in ipairs({ 1, 3, 5, 7, 9 }) do
    local s = rom(GENJU + e * 11 + o)
    if s ~= 0xFF then t[#t + 1] = s end
  end
  return t
end
local function owned(e) return (H.readByte(0x1A69 + (e >> 3)) >> (e & 7)) & 1 == 1 end
local function cmds()
  local t = {}
  for r = 0, 3 do t[#t + 1] = string.format("%02X", H.readByte(REC + 0x16 + r)) end
  return table.concat(t, " ")
end

-- ---- the Skills list for GOGO's slot: its Espers row's colour, and whether A on it opens the list ----------
local function skillsRow(tag, out)
  local ph, phase, presses = 0, "in", 0
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
local function espersRow(tag, want, opened)
  local out = {}
  return H.seqStep({
    skillsRow(tag, out),
    H.call(function()
      H.log(string.format("[leoespers] %s: GOGO's Espers row colour $%02X, the list opened: %s (commands %s)", tag,
        out.color or -1, tostring(out.opened), cmds()))
      H.assertEq(out.color, want, string.format("%s: his Espers row is %s", tag, want == WHITE and "white" or "grey"))
      H.assertEq(out.opened == true, opened, string.format("%s: A on it %s the esper list", tag,
        opened and "opens" or "does not open"))
    end),
  })
end

-- ---- his field Magic list (Skills -> Magic): the spell ids drawn ($7E9D89, field_subjob's reading) ----------
local function fieldMagic(out)
  local ph, phase, wait = 0, "in", 0
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
          held = H.readByte(0x4B) == 1 and { "a" } or { [H.readByte(0x4B) < 1 and "down" or "up"] = true }
        elseif s == 0x1A then
          wait = wait + 1
          if wait >= 120 then
            for i = 0, 0x35 do out[#out + 1] = H.readByte(0x7E9D89 + i) end
            H.screenshot("battle_leoespers_fieldmagic")
            phase = "out"
          end
        end
      else
        if s ~= -1 then held = { "b" } else phase = "done" end
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, "LEO's field Magic list"), function() ph, phase, wait = 0, "in", 0 end)
end

-- ---- the Status screen's command picker (battle_leoshock's walk): `cmd` into his row `row`, or with cmd nil the
-- list read and backed out of; `seen` gets the list
local function picker(row, cmd, seen, tag)
  local ph, done, read = 0, false, false
  return H.withReset(H.driveUntil(function() return done and not H.menuRunning() and ctl() end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if cmd ~= nil and H.readByte(REC + 0x16 + row) == cmd and s ~= 0x6A then done = true end
      if cmd == nil and read and s ~= 0x6A then done = true end
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
        held = H.readByte(0x4B) == row and { "a" } or { [H.readByte(0x4B) < row and "down" or "up"] = true }
      elseif s == 0x6A then
        local n = H.readByte(0x7E9D89)
        if not read then
          read = true
          for r = 0, n - 1 do seen[#seen + 1] = H.readByte(0x7E9D8A + r) end
          local t = {}
          for _, c in ipairs(seen) do t[#t + 1] = string.format("%02X", c) end
          H.log(string.format("[leoespers] %s: GOGO's command picker (%d rows): %s", tag, n, table.concat(t, " ")))
          H.screenshot("battle_leoespers_" .. tag .. "_picker")
        end
        if cmd == nil then
          held = { "b" }
        else
          local want = nil
          for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == cmd then want = r end end
          if want == nil then error(string.format("%s: command $%02X is not in his picker", tag, cmd), 0) end
          held = H.readByte(0x4B) == want and { "a" } or { [H.readByte(0x4B) < want and "down" or "up"] = true }
          if H.readByte(0x4B) == want and ph == 0 then H.screenshot("battle_leoespers_" .. tag .. "_cursor") end
        end
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, tag .. ": his command picker"), function() ph, done, read = 0, false, false end)
end

-- ---- the stone and its spell --------------------------------------------------------------------------------
local E, S = nil, nil
local pickRow, oldCmd, otherRows = nil, nil, {}
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
local greySeen, whiteSeen = 0, 0
local summons, msgs = {}, {}
local armed = false
local function arm()
  if armed then return end
  armed = true
  local c19 = H.sym("Cmd_19")
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if seat ~= nil and y == seat * 2 then
      summons[#summons + 1] = { atk = H.readByte(0xB6), f = H.frame, mode = battle and battle.mode }
      H.log(string.format("[leoespers] f%d Cmd_19 (Summon) by LEO's seat %d: attack $%02X (queued command $%02X, $3f2e $%02X)", H.frame, seat,
        H.readByte(0xB6), H.readByte(0x3A7C), H.readByte(0x3F2E)))
    end
  end, emu.callbackType.exec, c19, c19)
  -- his command window after his summon ran this battle: the Summon row's grey bit ($202E + seat*12, 3 bytes a
  -- row, the second's bit 7), once per window
  local lastWin = nil
  emu.addEventCallback(function()
    if not battle or battle.mode ~= "picked" or seat == nil or #summons <= battle.s0 then return end
    local open = H.readByte(0x7BCA) ~= 0 and (H.readByte(0x62CA) & 3) == seat and H.readByte(0x7BC2) == 0x05
    if not open then lastWin = nil; return end
    if lastWin == H.frame - 1 then lastWin = H.frame; return end
    lastWin = H.frame
    for r = 0, 3 do
      if H.readByte(0x202E + seat * 12 + r * 3) == CMD_SUMMON then
        local grey = (H.readByte(0x202E + seat * 12 + r * 3 + 1) & 0x80) ~= 0
        if grey then greySeen = greySeen + 1 else whiteSeen = whiteSeen + 1 end
        H.log(string.format("[leoespers] f%d his command window after his summon: Summon (row %d) %s", H.frame, r,
          grey and "greyed" or "WHITE"))
      end
    end
  end, emu.eventType.endFrame)
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
local base, nBattles, reached, afterReach, cycleDone = nil, 0, false, false, false
local unpickedProven, nUnpicked = false, 0

-- mode "picked": the stone is his; "unpicked": it is inert
local function openBattle(mode)
  seat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GOGO then seat = s end end
  H.assertEq(seat ~= nil, true, "LEO (actor $0C) is seated")
  nBattles = nBattles + 1
  local e = seat * 2
  local held = false
  for i = 0, 53 do if H.readByte(LISTS[seat] + 4 + i * 4) == S then held = true end end
  battle = { mode = mode, s0 = #summons, f0 = H.frame, form = H.readWord(0x3ED4), rand = H.readByte(0x57BD), before = counts(),
    stats = stats(e), bonus = bonus() }
  msgs = {}
  H.log(string.format("[leoespers] battle %d (%s): formation $%03X random=%d; LEO seat %d, esper row $%02X, $3344 "
    .. "$%02X, S $%02X in his list %s; count on E %d (rank %d); vigor %d speed %d stamina %d magic %d; held rungs' "
    .. "points %d/%d/%d/%d", nBattles, mode, battle.form, battle.rand, seat, H.readByte(LISTS[seat]),
    H.readByte(0x3344 + e), S, tostring(held), count(LIVE, 12, E), rankOf(count(LIVE, 12, E)), battle.stats[1],
    battle.stats[2], battle.stats[3], battle.stats[4], battle.bonus[1], battle.bonus[2], battle.bonus[3],
    battle.bonus[4]))
  H.screenshot("battle_leoespers_open" .. nBattles)
  if mode == "picked" then
    H.assertEq(H.readByte(LISTS[seat]), E, string.format("battle %d: his Magic list's esper row is the stone he wears",
      nBattles))
    H.assertEq(held, true, string.format("battle %d: his battle Magic list holds $%02X, which only his stone grants "
      .. "(the union)", nBattles, S))
  end
  if base == nil then
    base = {}
    for i = 1, 4 do base[i] = battle.stats[i] - battle.bonus[i] end
  end
  for i, what in ipairs({ "vigor", "speed", "stamina", "magic power" }) do
    if mode == "picked" then
      H.assertEq(battle.stats[i], base[i] + battle.bonus[i], string.format("battle %d: his %s is the first battle's "
        .. "plus the stat points of the rungs he holds (Ot6EsperFold)", nBattles, what))
    else
      H.assertEq(battle.stats[i], base[i], string.format("battle %d: unpicked, his %s is the first battle's without "
        .. "the rungs", nBattles, what))
    end
  end
  if mode == "unpicked" then
    H.assertEq(H.readByte(LISTS[seat]), 0xFF, string.format("battle %d: unpicked, his Magic list has no esper row",
      nBattles))
    H.assertEq(H.readByte(0x3344 + e), 0xFF, string.format("battle %d: unpicked, no stone in $3344 for his seat",
      nBattles))
    H.assertEq(held, false, string.format("battle %d: unpicked, his list lacks $%02X", nBattles, S))
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
  H.log(string.format("[leoespers] battle %d (%s) over: formation pays %d Magic Points (%d %s); LEO %s, his count "
    .. "on E %d -> %d", nBattles, battle.mode, mp, pts, battle.rand == 1 and "doubled" or "plain",
    alive and "alive" or "down", battle.before[12][slotOf(E)], after[12][slotOf(E)]))
  for _, m in ipairs(msgs) do H.log(string.format("[leoespers] message $%02X v0=%d who=%d", m.id, m.v0, m.who)) end
  local ns = #summons - battle.s0
  H.assertEq(ns <= 1, true, string.format("battle %d: his summon ran at most once (once a battle: the Summon command "
    .. "greys once it is spent, UpdateCmd_08); it ran %d time(s)", nBattles, ns))
  if battle.mode == "unpicked" then
    H.assertEq(ns, 0, string.format("battle %d: unpicked, no summon ran for his seat", nBattles))
  end
  if battle.mode == "picked" and alive then
    H.assertEq(d, math.min(battle.before[12][slotOf(E)] + pts, 9999) - battle.before[12][slotOf(E)],
      string.format("battle %d: LEO's row-12 counter for the stone he wears gained the battle's Magic Points", nBattles))
  elseif battle.mode == "picked" then
    H.assertEq(d, 0, string.format("battle %d: a fallen LEO earned nothing", nBattles))
  else
    H.assertEq(d, 0, string.format("battle %d: unpicked, his count on the stone did not move", nBattles))
    if mp > 0 and alive then unpickedProven = true
    else H.log("[leoespers] the unpicked battle paid nothing or LEO fell: it proves less; another") end
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

local function shoreBattle(mode)
  local wp = 1
  local pts = { SHORE, FALCON }
  local plan = mode == "picked" and { { who = GOGO, cmd = CMD_SUMMON, summon = true, self = true, boost = 0 } } or {}
  return H.seqStep({
    H.call(function() cycleDone = false end),
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return pts[wp][1] end, function() return pts[wp][2] end,
        { maxFrames = 6000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % 2 + 1 end),
    }, "a random battle on the shore"),
    H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
    H.call(function() openBattle(mode) end),
    H.kitBattle(plan, { others = "fight", maxFrames = 60000 }),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000, "back on the map", 2),
    H.call(closeBattle),
    H.fieldCare({ tag = "care between battles" }),
    H.call(function() cycleDone = true end),
  })
end

local savedRow, continued = nil, 0
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local pre, offered, unpickSeen, repickSeen = {}, {}, {}, {}
local nSummons = 0

H.run({ maxFrames = 700000 }, {
  -- before the reveal
  H.loadState("build/states/wor_leo_pre.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.readByte(SW_BYTE) & SW_BIT, 0, "wor_leo_pre: switch $00E0 clear (before the reveal)")
    H.assertEq(seated(GOGO), true, "wor_leo_pre: GOGO seated")
    H.assertEq(worn(GOGO), 0xFF, "wor_leo_pre: GOGO wears no stone")
  end),
  picker(1, nil, pre, "pre"),
  H.call(function()
    H.assertEq(#pre > 0, true, "before the reveal: the picker was read")
    H.assertEq(has(pre, CMD_SUMMON), false, "before the reveal: GOGO's command picker offers no Summon")
  end),
  espersRow("before the reveal", GREY, false),
  H.call(function() H.assertEq(worn(GOGO), 0xFF, "before the reveal: GOGO still wears nothing") end),
  -- after the reveal
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    arm()
    H.assertEq(H.readByte(SW_BYTE) & SW_BIT, SW_BIT, "wor_leo: switch $00E0 set (gen_wor_leo's reveal)")
    H.assertEq(H.readByte(REC + 1), 0x10, "slot 12 wears Leo's sprite")
    H.assertEq(worn(GOGO), 0xFF, "LEO starts wearing nothing")
    H.assertEq(count(LIVE, 12, 0), 0, "and with no progress")
    H.log("[leoespers] LEO's commands: " .. cmds())
    for r = 1, 3 do H.assertEq(H.readByte(REC + 0x16 + r) ~= CMD_SUMMON, true, "Summon is not picked yet") end
    for r = 3, 1, -1 do
      local c = H.readByte(REC + 0x16 + r)
      if pickRow == nil and c ~= CMD_ITEM and c ~= CMD_LORE then pickRow = r end
    end
    H.assertEq(pickRow ~= nil, true, "a row to pick Summon into (not Item or Lore)")
    oldCmd = H.readByte(REC + 0x16 + pickRow)
    for r = 1, 3 do if r ~= pickRow then otherRows[#otherRows + 1] = r end end
    pickStone()
  end),
  espersRow("revealed, Summon unpicked", GREY, false),
  H.lazy(function() return picker(pickRow, CMD_SUMMON, offered, "pick") end),
  H.call(function()
    H.assertEq(has(offered, CMD_SUMMON), true, "after the reveal: the picker offers Summon")
    H.assertEq(H.readByte(REC + 0x16 + pickRow), CMD_SUMMON, "Summon picked into his row " .. pickRow)
  end),
  espersRow("Summon picked", WHITE, true),
  H.lazy(function()
    return H.equipEsper(function() return posOf(GOGO) end, E, { tag = "the stone -> LEO" })
  end),
  H.call(function()
    H.assertEq(worn(GOGO), E, string.format("LEO wears the stone (record 12's +$1E = $%02X)", E))
  end),
  -- Magic into row 1 (Lore's): the field Magic list opens only for a Magic carrier, and with Magic his battle
  -- Magic list's esper row is the stone's other door, which an unpicked Summon must close too
  H.lazy(function() return picker(otherRows[1], 0x02, {}, "magic") end),
  H.call(function() H.assertEq(H.readByte(REC + 0x16 + otherRows[1]), 0x02, "Magic picked into his other row") end),
  -- and Fight into row 3 (Item's): once his summon is spent the Summon command greys, and the fight-out needs a
  -- Fight row for him
  H.lazy(function() return picker(otherRows[2], 0x00, {}, "fight") end),
  H.call(function() H.assertEq(H.readByte(REC + 0x16 + otherRows[2]), 0x00, "Fight picked into his last row") end),
  (function()
    local list = {}
    return H.seqStep({
      fieldMagic(list),
      H.call(function()
        H.log(string.format("[leoespers] his field Magic list holds $%02X: %s", S, tostring(has(list, S))))
        H.assertEq(has(list, S), true, string.format("his field Magic list holds $%02X, which only his stone grants "
          .. "(Ot6FieldLeoMagic)", S))
      end),
    })
  end)(),
  H.driveUntil(function() return afterReach and cycleDone end, 500000, {
    H.call(function() H.assertEq(nBattles < 10, true, "rung 1 reached and a battle opened after it, within ten") end),
    shoreBattle("picked"),
  }, "battles until his first rung is held in a battle"),
  H.call(function()
    H.assertEq(#summons > 0, true, "Cmd_19 (Summon) ran for LEO's seat")
    H.log(string.format("[leoespers] his command windows after his summon: Summon greyed %d, white %d", greySeen,
      whiteSeen))
    H.assertEq(whiteSeen, 0, "once spent, his Summon command is greyed for the rest of the battle (UpdateCmd_08)")
    H.assertEq(greySeen > 0, true, "his command window opened after his summon (the once-a-battle grey was read)")
    for _, s in ipairs(summons) do
      H.assertEq(s.atk, 0x36 + E, string.format("the summon was his stone's ($%02X)", 0x36 + E))
    end
    nSummons = #summons
  end),
  -- unpicked: his old command back in the row
  H.lazy(function() return picker(pickRow, oldCmd, unpickSeen, "unpick") end),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x16 + pickRow), oldCmd, "unpicked: his old command back in row " .. pickRow)
    H.assertEq(worn(GOGO), E, "unpicked: the stone stays in his record")
    H.assertEq(has(unpickSeen, CMD_SUMMON), true, "the picker still offers Summon while it is picked")
  end),
  espersRow("Summon unpicked", GREY, false),
  H.driveUntil(function() return unpickedProven and cycleDone end, 400000, {
    H.call(function()
      nUnpicked = nUnpicked + 1
      H.assertEq(nUnpicked <= 4, true, "an unpicked battle that pays and LEO lives through, within four")
    end),
    shoreBattle("unpicked"),
  }, "a battle with Summon unpicked"),
  H.call(function()
    H.assertEq(#summons, nSummons, "unpicked: no summon ran for his seat")
    H.assertEq(worn(GOGO), E, "unpicked: the stone is still in his record after the battle")
  end),
  -- picked again
  H.lazy(function() return picker(pickRow, CMD_SUMMON, repickSeen, "repick") end),
  H.call(function()
    H.assertEq(has(repickSeen, CMD_SUMMON), true, "unpicked, the picker offers Summon again")
    H.assertEq(H.readByte(REC + 0x16 + pickRow), CMD_SUMMON, "Summon picked again")
  end),
  espersRow("Summon picked again", WHITE, true),
  H.call(function() cycleDone = false end),
  shoreBattle("picked"),
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
    H.assertEq(H.readByte(REC + 0x16 + pickRow), CMD_SUMMON, "after the Continue, Summon is still his pick")
    H.log(string.format("[leoespers] PASS: LEO picks Summon, wears $%02X, summons it, earns and keeps its ranks "
      .. "(count %d); unpicked it is inert and kept, re-picked it is back; the save carries row 12 through a "
      .. "Continue; before the reveal GOGO had no Summon pick and no Espers row", E, count(LIVE, 12, E)))
  end),
})
