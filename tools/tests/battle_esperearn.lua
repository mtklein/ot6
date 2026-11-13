-- @suite slow
-- battle_esperearn.lua -- a won battle pays its Magic Points to each living seated member's counter for the
-- stone that member wears, doubled for a random battle; nobody else's counters move (#328, plan A:
-- docs/design/esper-rework.md; ot6_esper.asm Ot6EsperEarn / Ot6EsperMsg).
--
-- Played: Continue post-opera-v1 (the world map below the opera house; LOCKE, EDGAR, SABIN and CELES seated,
-- Ramuh, Siren, Stray and Kirin owned), put Ramuh on EDGAR through the Skills menu when nobody seated wears it
-- (so two members wear a stone, whatever the save's gear left), pace beside the save tile into a random battle
-- and fight it out with the driver.  Nothing is written.
--
-- The properties, each read from expanded SRAM's live esper page ($317C00: a magic word, then one word per
-- character per esper slot, Odin and Raiden sharing one):
--   0. the Continue copied the slot's page into the live page (slot 3's counters = the live ones), and the
--      live page is signed;
--   1. at the victory, each member who is alive and wears a stone gains BattleMagicPoints[formation] x 2 (the
--      battle is random: OT6_RANDBTL = 1) on that stone's counter, capped at 9999;
--   2. no other counter moves: not a seated member's other stones, not a member wearing nothing, not the
--      bench (every unseated character's whole row);
--   3. the victory screen shows "Got <n> Magic Point(s)" ($35) with n = that doubled count when a living
--      member wore a stone and the formation pays any, and "<char>: esper rank <r>" ($49) once for each
--      member whose count crossed a rung (10 / 30 / 75 / 200 / 500), and never otherwise.
-- A battle that pays nothing (BattleMagicPoints 0) or that a stone-wearer did not survive proves less: it is
-- logged and the next random battle taken, up to six.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0] = "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN", "CELES", "STRAGO", "RELM",
  "SETZER", "MOG", "GAU" }
local EDGAR, RAMUH = 4, 0
local LIVE, SLOT3 = 0x317C00, 0x317800
local RUNGS = { 10, 30, 75, 200, 500 }
local function sram(a) return emu.read(a, emu.memType.snesMemory) end
local function sramW(a) return sram(a) | (sram(a + 1) << 8) end
local function slotOf(e) if e < 12 then return e elseif e == 12 then return 11 else return e - 1 end end
local function ctr(page, actor, e) return sramW(page + 0x10 + (actor * 26 + slotOf(e)) * 2) end
local function rank(n) local r = 0; for _, c in ipairs(RUNGS) do if n >= c then r = r + 1 end end; return r end
local function snapshot()
  local t = {}
  for a = 0, 11 do
    t[a] = {}
    for s = 0, 25 do t[a][s] = sramW(LIVE + 0x10 + (a * 26 + s) * 2) end
  end
  return t
end
local function worn(c) return H.readByte(0x1600 + 37 * c + 0x1E) end
local function seated(c) return (H.readByte(0x1850 + c) & 7) == H.readByte(0x1A6D) and H.readByte(0x1850 + c) ~= 0 end

local msgs, before, battle, done, tries, earns = {}, nil, nil, false, 0, 0
local function exp24(c) local r = 0x1600 + 37 * c; return H.readByte(r + 0x11) | (H.readByte(r + 0x12) << 8)
  | (H.readByte(r + 0x13) << 16) end
local function arm()
  local earn = H.sym("Ot6EsperEarn")
  emu.addMemoryCallback(function()
    if not battle then return end
    earns = earns + 1
    local st = emu.getState()
    H.log(string.format("[earn] Ot6EsperEarn: record +$%03X (actor %d) wears $%02X; $fb=%d", st["cpu.x"],
      H.readByte(0x1600 + st["cpu.x"]), H.readByte(0x161E + st["cpu.x"]), H.readByte(0xFB)))
  end, emu.callbackType.exec, earn, earn)
  local show = H.sym("Ot6ShowMsg")
  emu.addMemoryCallback(function()
    if battle then msgs[#msgs + 1] = { id = emu.getState()["cpu.a"] & 0xFF, v0 = H.readWord(0x2F35),
      who = H.readByte(0x2F38) } end
  end, emu.callbackType.exec, show, show)
end

local A, B = nil, nil
local function pace(what)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 3000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, what),
    H.waitUntil(function() return H.battleActive() end, 1200, what .. ": the battle is up", 2),
    H.call(function()
      tries = tries + 1
      msgs, earns = {}, 0
      battle = { form = H.readWord(0x3ED4), rand = H.readByte(0x57BD), seats = {} }
      for s = 0, 3 do
        local a = H.readByte(0x3ED8 + s * 2)
        if a < 12 then battle.seats[s] = a end
      end
      before = snapshot()
      battle.exp = {}
      for _, a in pairs(battle.seats) do battle.exp[a] = exp24(a) end
      H.log(string.format("[earn] battle %d: formation $%03X, random=%d", tries, battle.form, battle.rand))
    end),
  })
end

local function judge()
  local form = battle.form
  local mp = 0
  if form < 0x200 then
    mp = emu.read((H.sym("BattleMagicPoints") & 0x3FFFFF) + form, emu.memType.snesPrgRom)
  end
  H.assertEq(battle.rand, 1, "the battle paced into on the world map is a random one (OT6_RANDBTL)")
  local pts = mp * 2
  local won = false
  for _, a in pairs(battle.seats) do if exp24(a) > battle.exp[a] then won = true end end
  H.log(string.format("[earn] won=%s; Ot6EsperEarn ran %d time(s)", tostring(won), earns))
  if not won then return false end
  local after = snapshot()
  for a = 0, 11 do for s = 0, 25 do
    if after[a][s] ~= before[a][s] then H.log(string.format("[earn] moved: actor %d slot %d %d -> %d", a, s,
      before[a][s], after[a][s])) end
  end end
  local nz = {}
  for i = 0, 0x3FF, 2 do local w = sramW(LIVE + i); if w ~= 0 then nz[#nz + 1] = string.format("+%03X=%d", i, w) end end
  H.log("[earn] live page nonzero words: " .. table.concat(nz, " "))
  local earners, crossed = {}, {}
  for s, a in pairs(battle.seats) do
    local e = worn(a)
    local alive = H.readWord(0x1600 + 37 * a + 0x09) > 0 and (H.readByte(0x1600 + 37 * a + 0x14) & 0xC2) == 0
    if e < 27 and alive and pts > 0 then earners[a] = { slot = slotOf(e), seat = s, e = e } end
  end
  local anyEarner = next(earners) ~= nil
  H.log(string.format("[earn] formation $%03X pays %d Magic Points, %d doubled", form, mp, pts))
  -- 1 and 2
  for a = 0, 11 do
    for s = 0, 25 do
      local d = after[a][s] - before[a][s]
      local er = earners[a]
      if er and er.slot == s then
        local want = math.min(before[a][s] + pts, 9999) - before[a][s]
        H.log(string.format("[earn] %s on stone %d: %d -> %d", NAMES[a], er.e, before[a][s], after[a][s]))
        H.assertEq(d, want, string.format("%s's counter for the stone worn (esper %d) gained the battle's "
          .. "Magic Points doubled", NAMES[a], er.e))
        if rank(after[a][s]) > rank(before[a][s]) then crossed[er.seat] = rank(after[a][s]) end
      else
        H.assertEq(d, 0, string.format("%s's counter for esper slot %d did not move (%s)", NAMES[a], s,
          seated(a) and "seated, not the stone worn" or "the bench"))
      end
    end
  end
  -- 3
  local sawMP, ranks = false, {}
  for _, m in ipairs(msgs) do
    H.log(string.format("[earn] message $%02X v0=%d who=%d", m.id, m.v0, m.who))
    if m.id == 0x35 then
      sawMP = true
      H.assertEq(m.v0, pts, "the Magic Points line names the doubled count")
    elseif m.id == 0x49 then
      ranks[m.who] = m.v0
    end
  end
  H.assertEq(sawMP, anyEarner, "the Magic Points line shows exactly when a living member wore a stone and the "
    .. "battle paid some")
  for seat, r in pairs(crossed) do
    H.assertEq(ranks[seat], r, string.format("seat %d's new rank %d is announced", seat, r))
  end
  for seat, r in pairs(ranks) do
    H.assertEq(crossed[seat], r, string.format("seat %d's rank line (%d) names a rung its count crossed", seat, r))
  end
  return anyEarner
end

H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("post-opera-v1"),
  H.call(function()
    arm()
    H.assertEq(sramW(LIVE), 0x3145, "the live esper page is signed ('E1')")
    for a = 0, 11 do
      for e = 0, 26 do
        H.assertEq(ctr(LIVE, a, e), ctr(SLOT3, a, e), string.format("the Continue copied slot 3's count for %s, "
          .. "esper %d, into the live page", NAMES[a], e))
      end
    end
  end),
  H.lazy(function()
    for c = 0, 13 do if seated(c) and worn(c) == RAMUH then return H.logStep("[earn] Ramuh is worn already") end end
    H.assertEq(seated(EDGAR), true, "EDGAR is seated (post-opera-v1's party)")
    return H.equipEsper(function() return (H.readByte(0x1850 + EDGAR) >> 3) & 3 end, RAMUH,
      { tag = "Ramuh -> EDGAR" })
  end),
  H.call(function()
    local n = 0
    for c = 0, 11 do if seated(c) and worn(c) < 27 then n = n + 1 end end
    H.assertEq(n >= 1, true, "a seated member wears a stone")
    H.assertEq(H.worldMode(), true, "on the world map")
    local x, y = H.worldX(), H.worldY()
    A = { x, y }
    -- a plain tile that rolls random battles (property $40) and is walkable ($10 clear): never an entrance
    local function plain(tx, ty) return (H.worldTileProp(tx, ty) & 0x50) == 0x40 end
    H.assertEq(plain(x, y), true, "the save tile rolls random battles")
    for _, d in ipairs({ { -1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 0 } }) do
      if B == nil and plain(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(B ~= nil, true, "a plain tile that rolls random battles beside the party")
  end),
  H.driveUntil(function() return done end, 380000, {
    pace("a random battle by the opera house"),
    H.fightBattleByMenu(40000),
    H.waitUntil(function() return not H.battleLoadStarted() and H.worldHasControl() end, 6000,
      "back on the world map", 2),
    H.call(function()
      if judge() then done = true
      else
        H.log("[earn] nobody earned in this battle (it paid nothing, or no stone-wearer lived): the next one")
        H.assertEq(tries < 6, true, "a battle a stone-wearer survives that pays Magic Points, within six")
      end
      battle = nil
    end),
  }, "a battle that pays a stone-wearer"),
  H.logStep("[earn] PASS: the wearers' counters gained the doubled Magic Points, nothing else moved"),
})
