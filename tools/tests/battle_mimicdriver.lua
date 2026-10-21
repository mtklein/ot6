-- @suite slow
-- battle_mimicdriver.lua -- the fight driver's Mimic line for GOGO (#270;
-- Driver:mimicLine, kits.md "Gogo").
--
-- Played: the wor_opera leg's own snapshot on the Opera House's catwalk,
-- at the switch that drops the party onto the Dirt Dragon (wor_opera_switch:
-- STRAGO, RELM, GOGO and TERRA, his kit Mimic, Lore, Tools, Item; nothing
-- here writes it).  The switch is pressed and the real driver fights the
-- dragon (event battle 134), whose length gives GOGO's line the windows a
-- random battle on the plain rarely does (measured, lab md2: one Mimic plan
-- in eleven of Thamasa's randoms, where a Fight that kills leaves no target
-- to copy).  Every copy the engine makes for GOGO's seat (mimicreplace, X =
-- his seat) is measured, and the asserts read the engine:
--   1. the plans are carried out: mimicreplace runs for his seat at least
--      once and never more often than the driver confirmed a Mimic (one
--      whose turn never runs, GOGO felled first, makes none), each copying a
--      command the line copies (M.MIMIC_COPY).  The copy is the party's last action when
--      his turn runs, which can be later than the one the plan read (another
--      member acting between: lab md1, a Tools plan copied a Fight); both
--      are logged;
--   2. the price: his MP ($3C08 + his seat) when each copy ends
--      (Ot6ActionEnd for his seat) is his MP at the copy: Mimic is free;
--   3. the boost: the pips pending at each copy ($3E9D + his seat) are the
--      plan's (its boost, capped by the bank it read and 3), and at least
--      one copy is boosted, so the check is not of zeros alone.
-- Then the control: the same snapshot again, MIMIC_OFF set, the same fight:
-- no mimicreplace for his seat.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 0x0C
local FIGHT = {}

local function gogoSlot()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GOGO then return s end end
  return nil
end
local function map() return H.mapId() & 0x1ff end
local snap = nil
local cur = nil
local function fresh() return { copies = {}, plans0 = #H.mimics, confirms = 0 } end
-- the switch (232 (118,27), _cab497: facing up, A) and the fight to the dragon's end (map 237, $0387 clear)
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function theFight(what)
  return H.seqStep({
    H.faceAndHoldA("up", function() return map() ~= 232 or H.battleLoadStarted() end, 900,
      what .. ": the catwalk's switch (232 (118,27)): face up, A"),
    H.release(),
    H.advanceStory(function() return sw(0x0387) == 0 and map() == 237 and H.hasControl() end, 300000,
      { playBattles = "tactical", fight = FIGHT }),
  })
end

H.run({ maxFrames = 900000 }, {
  H.loadState("build/states/wor_opera_switch.mss.lua"),
  H.call(function()
    H.assertEq(H.partyOfChar(GOGO), 1, "GOGO seated at the catwalk's switch (the play's own snapshot)")
    H.assertEq(H.readByte(0x1600 + 37 * GOGO + 0x16), 0x12, "GOGO's first command Mimic")
    H.assertEq(sw(0x0387), 1, "the Dirt Dragon on the stage ($0387)")
    -- each copy: mimicreplace runs with the acting seat in X
    emu.addMemoryCallback(function()
      local s = gogoSlot()
      if cur and s ~= nil and (emu.getState()["cpu.x"] & 0xFF) == s * 2 then
        cur.copies[#cur.copies + 1] = { cmd = H.readByte(0x3F20), atk = H.readByte(0x3F21),
          mp = H.readWord(0x3C08 + s * 2), pend = H.readByte(0x3E9D + s * 2), plans = #H.mimics }
      end
    end, emu.callbackType.exec, H.sym("mimicreplace"), H.sym("mimicreplace"))
    -- each copy's end: Ot6ActionEnd for the same seat
    emu.addMemoryCallback(function()
      local s = gogoSlot()
      local c = cur and cur.copies[#cur.copies]
      if c and c.mpEnd == nil and s ~= nil and (emu.getState()["cpu.x"] & 0xFF) == s * 2 then
        c.mpEnd = H.readWord(0x3C08 + s * 2)
      end
    end, emu.callbackType.exec, H.sym("Ot6ActionEnd"), H.sym("Ot6ActionEnd"))
  end),
  -- the snapshot both fights start from
  H.call(function() snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the switch's snapshot"); cur = fresh() end),
  theFight("with the line"),
  H.call(function()
    local n = #cur.copies
    local planned, confirmed = #H.mimics - cur.plans0, 0
    for i = cur.plans0 + 1, #H.mimics do if H.mimics[i].confirmed then confirmed = confirmed + 1 end end
    H.log(string.format("[mimic] the fight with the line: %d Mimic plan(s), %d confirmed, %d copy(ies) for GOGO's seat",
      planned, confirmed, n))
    local boosted = 0
    for i, c in ipairs(cur.copies) do
      -- the plan behind a copy: GOGO's latest, made before it (he gets no window between his plan and his turn)
      local p = c.plans > cur.plans0 and H.mimics[c.plans] or nil
      H.log(string.format("[mimic]   copy %d: engine cmd $%02X atk $%02X, MP %d -> %s, pending %d; plan %s", i, c.cmd,
        c.atk, c.mp, tostring(c.mpEnd), c.pend, p and string.format("read cmd $%02X atk $%02X at %d BP (bank %d)",
          p.cmd, p.atk, p.boost, p.bp) or "-"))
      H.assertEq(H.MIMIC_COPY[c.cmd] ~= nil, true, string.format("1. copy %d's command $%02X is one the line copies",
        i, c.cmd))
      H.assertEq(c.mpEnd, c.mp, string.format("2. copy %d is free (GOGO's MP at its end)", i))
      if p then
        H.assertEq(c.pend, math.min(p.boost, p.bp, 3), string.format("3. copy %d's pending pips are its plan's", i))
      end
      if c.pend > 0 then boosted = boosted + 1 end
    end
    H.assertEq(n >= 1, true, "1. at least one copy for GOGO's seat")
    -- a confirmed Mimic whose turn never runs (GOGO felled first) makes no copy; no copy comes without one
    H.assertEq(n <= confirmed, true, string.format("1. no more copies (%d) than confirmed Mimics (%d)", n, confirmed))
    H.assertEq(boosted >= 1, true, "3. at least one copy boosted")
  end),
  -- the control: the same snapshot, the line off
  H.call(function()
    MIMIC_OFF = true
    snap.load = H.requestLoadState(snap.blob)
  end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap.load, "the switch's snapshot again"); cur = fresh() end),
  H.waitUntil(function() return H.hasControl() end, 600, "control at the switch again", 1),
  theFight("with MIMIC_OFF"),
  H.call(function()
    H.log(string.format("[mimic] the control fight: %d copy(ies) for GOGO's seat", #cur.copies))
    H.assertEq(#cur.copies, 0, "control: with the line off GOGO never Mimics")
  end),
})
