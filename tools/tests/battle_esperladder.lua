-- @suite slow
-- battle_esperladder.lua -- the esper ladder's rungs are kept (#328, plan A: docs/design/esper-rework.md;
-- ot6_esper.asm Ot6EsperFold / Ot6EsperMsg / Ot6EsperSaveAs): a rung crossed at a victory is announced, its
-- stat points and effect reach the battle whatever stone is worn later, another character does not get them,
-- and a save carries the counts into the slot.
--
-- Continue post-opera-v1 (world map below the opera house; LOCKE, EDGAR, SABIN, CELES seated; Ramuh, Siren,
-- Stray, Kirin owned).  T is the first seated member with no count on Siren or Stray (E, the one picked); U is
-- another seated member below E's rung 3.  Through the real menus and random battles fought out by the driver:
--   battle 0: T wears E.  Baseline: every seated member's battle stats ($3b2c vigor*2, $3b19 speed, $3b40
--             stamina, $3b41 mag.pwr) and blocked statuses ($331c / $331d, a clear bit blocks).
--   staged:   T's count on E set to 74 on the live esper page ($317C00), one short of rung 3 (declared in
--             state_write_waivers.txt: the mechanism expedient; a person reaches 74 by fighting about thirty
--             more battles in that stone).
--   battle 1: T's stats are battle 0's plus the stat points of every rung T now holds (Ot6LadderTbl, read
--             from the ROM, summed over every esper's count on the live page); the victory crosses rung 3
--             and shows "<T>: esper rank 3" ($49) for T's seat.
--   T wears the other stone (Skills menu).
--   battle 2: T's stats still carry every held rung's points; T's rung-3 effect bits on E are blocked for T
--             ($331c/$331d) and were not in battle 0; U's are not blocked.
--   save:     slot 3 through the Save menu on the world map; slot 3's esper page equals the live page.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local SIREN, STRAY = 3, 8
local LIVE, SLOT3 = 0x317C00, 0x317800
local COSTS = { 10, 30, 75, 200, 500 }
local LADDER = H.sym("Ot6LadderTbl") & 0x3FFFFF
local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function sramW(a) return sram(a) | (sram(a + 1) << 8) end
local function slotOf(e) if e < 12 then return e elseif e == 12 then return 11 else return e - 1 end end
local function rankOf(n) local r = 0; for _, c in ipairs(COSTS) do if n >= c then r = r + 1 end end; return r end
local function count(a, e) return sramW(LIVE + 0x10 + (a * 26 + slotOf(e)) * 2) end
local function rec(s, k, i) return emu.read(LADDER + (s * 5 + k) * 14 + i, emu.memType.snesPrgRom) end
local function seated(c) local b = H.readByte(0x1850 + c); return b ~= 0 and (b & 7) == H.readByte(0x1A6D) end
local function worn(c) return H.readByte(0x1600 + 37 * c + 0x1E) end
local function pos(c) return (H.readByte(0x1850 + c) >> 3) & 3 end

-- every held rung's stat points for actor a (vig, spd, stm, mag) and status-1/2 protection bits
local function fold(a)
  local pts, p1, p2 = { 0, 0, 0, 0 }, 0, 0
  for s = 0, 25 do
    local r = rankOf(sramW(LIVE + 0x10 + (a * 26 + s) * 2))
    for k = 0, r - 1 do
      for i = 1, 4 do pts[i] = pts[i] + rec(s, k, 9 + i) end
      p1, p2 = p1 | rec(s, k, 1), p2 | rec(s, k, 2)
    end
  end
  return pts, p1, p2
end

local T, U, E, E2 = nil, nil, nil, nil
local snaps, msgs, battle = {}, {}, nil
local function measure(tag)
  local m = { tag = tag, seat = {} }
  for s = 0, 3 do
    local a = H.readByte(0x3ED8 + s * 2)
    if a < 12 then
      local o = s * 2
      m.seat[a] = { s = s, vig = H.readByte(0x3B2C + o), spd = H.readByte(0x3B19 + o), stm = H.readByte(0x3B40 + o),
        mag = H.readByte(0x3B41 + o), p1 = H.readByte(0x331C + o), p2 = H.readByte(0x331D + o) }
    end
  end
  local pts, p1, p2 = fold(T)
  m.fold = { pts = pts, p1 = p1, p2 = p2 }
  H.log(string.format("[ladder] %s: %s holds vig %d spd %d stm %d mag %d, p1 $%02X p2 $%02X; in battle vig*2 %d "
    .. "spd %d stm %d mag %d, blocked1 $%02X blocked2 $%02X", tag, NAMES[T], pts[1], pts[2], pts[3], pts[4], p1, p2,
    m.seat[T].vig, m.seat[T].spd, m.seat[T].stm, m.seat[T].mag, m.seat[T].p1 ~ 0xFF, m.seat[T].p2 ~ 0xFF))
  return m
end

local function arm()
  local show = H.sym("Ot6ShowMsg")
  emu.addMemoryCallback(function()
    if battle then msgs[#msgs + 1] = { id = emu.getState()["cpu.a"] & 0xFF, v0 = H.readWord(0x2F35),
      who = H.readByte(0x2F38) } end
  end, emu.callbackType.exec, show, show)
end

local A, B = nil, nil
local function fight(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(60),
    H.call(function()
      H.assertEq(seated(T) and H.readByte(0x3ED8 + pos(T) * 2) ~= 0xFF, true, NAMES[T] .. " is in the battle")
      msgs, battle = {}, tag
      snaps[tag] = measure(tag)
    end),
    H.fightBattleByMenu(40000),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
      tag .. ": back on the world map", 2),
    H.call(function()
      battle = nil
      H.assertEq(H.readWord(0x1600 + 37 * T + 0x09) > 0, true, NAMES[T] .. " is standing after " .. tag)
    end),
  })
end

local function statsCarry(tag)
  return H.call(function()
    local b, m = snaps.b0, snaps[tag]
    local d0, d = b.fold.pts, m.fold.pts
    local s0, s = b.seat[T], m.seat[T]
    H.assertEq(s.vig, s0.vig + 2 * (d[1] - d0[1]), tag .. ": vigor*2 carries every held rung's points")
    H.assertEq(s.spd, s0.spd + (d[2] - d0[2]), tag .. ": speed carries every held rung's points")
    H.assertEq(s.stm, s0.stm + (d[3] - d0[3]), tag .. ": stamina carries every held rung's points")
    H.assertEq(s.mag, s0.mag + (d[4] - d0[4]), tag .. ": mag.pwr carries every held rung's points")
  end)
end

H.run({ maxFrames = 600000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    arm()
    for _, c in ipairs({ 1, 4, 5, 6 }) do
      for _, e in ipairs({ SIREN, STRAY }) do
        if T == nil and seated(c) and count(c, e) == 0 then T, E = c, e end
      end
    end
    H.assertEq(T ~= nil, true, "a seated member with no count on Siren or Stray")
    E2 = E == SIREN and STRAY or SIREN
    for _, c in ipairs({ 1, 4, 5, 6 }) do
      if U == nil and c ~= T and seated(c) and count(c, E) < 75 then U = c end
    end
    H.assertEq(U ~= nil, true, "another seated member below E's rung 3")
    H.log(string.format("[ladder] T = %s wears esper %d; U = %s", NAMES[T], E, NAMES[U]))
    local x, y = H.worldX(), H.worldY()
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    A = { x, y }
    for _, dd in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + dd[1], y + dd[2]) then B = { x + dd[1], y + dd[2] } end
    end
    H.assertEq(plain(x, y) and B ~= nil, true, "two plain tiles that roll random battles")
  end),
  H.lazy(function() return H.equipEsper(function() return pos(T) end, E, { tag = "E -> T" }) end),
  fight("b0"),
  H.call(function()
    local s3p1, s3p2 = rec(slotOf(E), 2, 1), rec(slotOf(E), 2, 2)
    H.assertEq(s3p1 | s3p2 ~= 0, true, "E's rung 3 is a status immunity")
    H.assertEq((snaps.b0.seat[T].p1 & s3p1) == s3p1 and (snaps.b0.seat[T].p2 & s3p2) == s3p2, true,
      "battle 0: T was not immune to E's rung-3 statuses (nothing else blocked them)")
    -- staged: one short of rung 3 (see the header)
    local a = LIVE + 0x10 + (T * 26 + slotOf(E)) * 2
    emu.write(a, 74, emu.memType.snesMemory)
    emu.write(a + 1, 0, emu.memType.snesMemory)
  end),
  fight("b1"),
  statsCarry("b1"),
  H.call(function()
    H.assertEq(rankOf(count(T, E)) >= 3, true, "battle 1 took T's count past rung 3 (" .. count(T, E) .. ")")
    local seen = false
    for _, m in ipairs(msgs) do
      H.log(string.format("[ladder] b1 message $%02X v0=%d who=%d", m.id, m.v0, m.who))
      if m.id == 0x49 and m.who == snaps.b1.seat[T].s then
        H.assertEq(m.v0, rankOf(count(T, E)), "the rank line names T's new rank")
        seen = true
      end
    end
    H.assertEq(seen, true, "the victory showed T's rank line ($49)")
  end),
  H.lazy(function() return H.equipEsper(function() return pos(T) end, E2, { tag = "E2 -> T" }) end),
  H.call(function() H.assertEq(worn(T), E2, "T now wears the other stone") end),
  fight("b2"),
  statsCarry("b2"),
  H.call(function()
    local s3p1, s3p2 = rec(slotOf(E), 2, 1), rec(slotOf(E), 2, 2)
    local t, u = snaps.b2.seat[T], snaps.b2.seat[U]
    H.assertEq(t.p1 & s3p1, 0, "battle 2: T, wearing another stone, is immune to E's rung-3 status 1 bits")
    H.assertEq(t.p2 & s3p2, 0, "battle 2: ... and its status 2 bits")
    if u then
      H.assertEq((u.p1 & s3p1) == s3p1 and (u.p2 & s3p2) == s3p2, (snaps.b0.seat[U].p1 & s3p1) == s3p1
        and (snaps.b0.seat[U].p2 & s3p2) == s3p2, "battle 2: U is no more immune to them than in battle 0")
    end
  end),
  H.saveGame({ slot = 3, baseline = false, tag = "ladder save" }),
  H.call(function()
    H.assertEq(sramW(SLOT3), 0x3145, "slot 3's esper page is signed after the save")
    for a = 0, 11 do
      for s = 0, 25 do
        local o = 0x10 + (a * 26 + s) * 2
        H.assertEq(sramW(SLOT3 + o), sramW(LIVE + o), string.format("the save copied %s's slot-%d count", NAMES[a], s))
      end
    end
    H.log("[ladder] PASS: rung 3 crossed and announced; the rungs' points and effect kept on another stone, "
      .. "not on another character; the save carries the counts")
  end),
})
