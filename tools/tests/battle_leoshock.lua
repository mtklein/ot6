-- @suite slow savestate=wor_leo
-- battle_leoshock.lua -- the revealed Leo in battle (#552, docs/design/leo-reveal.md).
--
-- Played from gen_wor_leo's save after the reveal (STRAGO, RELM, LEO -- slot 12, actor $0C -- and TERRA on
-- the world map by Thamasa): the Status screen's command list, Shock picked into his second row; the shore by
-- Thamasa walked until a random battle opens; then through the real battle menu (H.kitBattle; the others
-- Defend): LEO's Shock unboosted, his Mimic, his Shock at 2 BP.
-- Declared unit-test expedient (tools/state_write_waivers.txt): at the battle's open every present monster's
-- HP is raised to 30,000 and its shields staged at six of six, unbroken, so the battle outlasts three Shocks and
-- each Shock's take on the shields can be read; a mechanism test of Shock, not a claim about play.
-- Asserted:
--   his battle sprite is Leo's ($2eae = $10) in Leo's palette (btlgfx CharPalTbl entry $10 read), his battle
--     stats came from Leo's CharProp row (battle power, defense, magic defense, evade, magic block: row 15's
--     bytes read for him at the battle's init, row 12's not), and his actor mask carries bit 15 ($3a21 bit 7:
--     Leo's set in the in-battle equip lists) beside bit 12;
--   each Shock (Cmd_1b) cost him no MP, hit every standing monster, took no shield and broke none, and revealed
--     no weakness (non-elemental);
--   his Mimic after his Shock ran Shock again (Cmd_1b, after the Mimic's confirm), free, and its damage is the first
--     Shock's (within the damage variance, 224..255 of 256: x0.87..x1.14);
--   the Shock at 2 BP dealt the first Shock's damage times four (x3.5..x4.6, or the 9,999 cap): the multiplier
--     (boost-rewards.md "MagiTek beams with a number, Health, Shock").
-- Screenshots (build/states/shots/battle_leoshock_*): the battle at its open, each Shock's command window.
local H = dofile("tools/tests/lib/ot6.lua")

local GOGO = 0x0C
local REC = 0x1600 + 37 * GOGO
local CMD_SHOCK, CMD_MIMIC = 0x1B, 0x12
local SH_CUR, SH_MAX, BRK_TICKS, REVEALED = 0x3E38, 0x3E39, 0x3E88, 0x3E89
local STAGED = 6
local FALCON, SHORE = { 250, 229 }, { 250, 235 }
local GOGO_ROW, LEO_ROW = 12 * 22, 15 * 22
local function st() return H.menuRunning() and H.readByte(0x26) or -1 end
local function gogoPos()
  local b = H.readByte(0x1850 + GOGO)
  if (b & 7) ~= H.activeParty() then return nil end
  return (b >> 3) & 3
end
local function ctl() if H.worldMode() then return H.worldHasControl() end return H.hasControl() end

-- ---- Shock into his second row (menu_leo's walk through the Status screen) --------------------------------
local function pickShock()
  local ph, done = 0, false
  return H.withReset(H.driveUntil(function() return done and not H.menuRunning() and ctl() end, 6000, {
    H.call(function()
      ph = (ph + 1) % 12
      local s, held = st(), {}
      if H.readByte(REC + 0x17) == CMD_SHOCK and s ~= 0x6A then done = true end
      if done then
        if s ~= -1 then held = { "b" } end
      elseif s == -1 then
        if ctl() then held = { "x" } end
      elseif s == 0x05 then
        held = H.readByte(0x4B) == 4 and { "a" } or { [H.readByte(0x4B) < 4 and "down" or "up"] = true }
      elseif s == 0x06 then
        local p = gogoPos()
        held = H.readByte(0x4B) == p and { "a" } or { [H.readByte(0x4B) < p and "down" or "up"] = true }
      elseif s == 0x0C then
        held = H.readByte(0x4B) == 1 and { "a" } or { [H.readByte(0x4B) < 1 and "down" or "up"] = true }
      elseif s == 0x6A then
        local n, want = H.readByte(0x7E9D89), nil
        for r = 0, n - 1 do if H.readByte(0x7E9D8A + r) == CMD_SHOCK then want = r end end
        if want == nil then error("Shock is not in his command list", 0) end
        held = H.readByte(0x4B) == want and { "a" } or { [H.readByte(0x4B) < want and "down" or "up"] = true }
      end
      if ph < 4 then H.setPad(held) else H.setPad({}) end
    end),
  }, "Shock into his second command row"), function() ph, done = 0, false end)
end

-- ---- records -----------------------------------------------------------------------------------------------
local seat = nil
local confirmed, shotAt = {}, {}
local shocks = {}               -- one per Cmd_1b: { queued, pend, mp0, mp1, before = {[e] = body}, after }
local open = nil
local rowReads = { [GOGO_ROW] = 0, [LEO_ROW] = 0 }
local palLeo = 0
local function monsters()
  local t = {}
  for m = 0, 5 do
    if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 then t[#t + 1] = 8 + m * 2 end
  end
  return t
end
local function bodies()
  local t = {}
  for _, e in ipairs(monsters()) do
    t[e] = { hp = H.readWord(0x3BF4 + e), sh = H.readByte(SH_CUR + e), br = H.readByte(BRK_TICKS + e) ~= 0,
      rev = H.readByte(REVEALED + e) }
  end
  return t
end
local function arm()
  local cp = H.sym("CharProp")
  for row in pairs(rowReads) do
    emu.addMemoryCallback(function() rowReads[row] = rowReads[row] + 1 end, emu.callbackType.read,
      cp + row + 10, cp + row + 14)
  end
  local pal = H.sym("CharPalTbl") + 0x10
  emu.addMemoryCallback(function() palLeo = palLeo + 1 end, emu.callbackType.read, pal, pal)
  local c1b = H.sym("Cmd_1b")
  emu.addMemoryCallback(function()
    if seat == nil or (emu.getState()["cpu.y"] & 0xFF) ~= seat * 2 then return end
    open = { queued = H.readByte(0x3A7C), mp0 = H.readWord(0x3C08 + seat * 2), before = bodies(),
      pend = H.readByte(0x3E9D + seat * 2), f = H.frame }
    shocks[#shocks + 1] = open
    shotAt[#shotAt + 1] = { f = H.frame + 40, tag = "battle_leoshock_shock" .. #shocks }
    H.log(string.format("[leoshock] f%d Cmd_1b: Shock by LEO (queued $%02X, %d BP pending, MP %d)", H.frame,
      open.queued, open.pend, open.mp0))
  end, emu.callbackType.exec, c1b, c1b)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if open == nil or open.after ~= nil then return end
    if seat == nil or (emu.getState()["cpu.x"] & 0xFF) ~= seat * 2 then return end
    open.after = bodies()
    open.mp1 = H.readWord(0x3C08 + seat * 2)
    open = nil
  end, emu.callbackType.exec, ae, ae)
end

local plan = {}
local proxy = setmetatable({}, { __index = function(_, i) return plan[i] end, __len = function() return #plan end })
local function stage()
  seat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GOGO then seat = s end end
  H.assertEq(seat ~= nil, true, "LEO (actor $0C) is seated")
  local e = seat * 2
  H.screenshot("battle_leoshock_open")
  H.log(string.format("[leoshock] LEO seat %d: graphics $%02X, actor mask $%04X, battle power %d, defense %d, "
    .. "magic defense %d; CharProp battle-stat reads: GOGO's row %d, Leo's row %d; CharPalTbl[$10] read %d",
    seat, H.readByte(0x2EAE + seat * 0x20), H.readWord(0x3A20 + e), H.readByte(0x3B68 + e), H.readByte(0x3BB8 + e),
    H.readByte(0x3BB9 + e), rowReads[GOGO_ROW], rowReads[LEO_ROW], palLeo))
  H.assertEq(H.readByte(0x2EAE + seat * 0x20), 0x10, "his battle sprite is Leo's (graphics $10)")
  H.assertEq(palLeo > 0, true, "Leo's battle palette was looked up (CharPalTbl entry $10)")
  H.assertEq(rowReads[LEO_ROW] > 0, true, "his battle stats came from Leo's CharProp row")
  H.assertEq(rowReads[GOGO_ROW], 0, "and not from GOGO's")
  H.assertEq(H.readWord(0x3A20 + e) & 0x9000, 0x9000, "his actor mask holds bit 12 (GOGO's) and bit 15 (Leo's set)")
  for _, m in ipairs(monsters()) do
    H.writeWord(0x3BF4 + m, 30000)
    H.writeByte(SH_CUR + m, STAGED)
    H.writeByte(SH_MAX + m, STAGED)
  end
  H.log(string.format("[leoshock] every present monster's HP := 30000, shields := %d of %d (declared expedient)",
    STAGED, STAGED))
  plan = { { who = GOGO, cmd = CMD_SHOCK, boost = 0 },
           { who = GOGO, cmd = CMD_MIMIC, boost = 0, self = true },
           { who = GOGO, cmd = CMD_SHOCK, boost = 2 } }
end

-- the kit's own log lines mark its entries: the window opened for an entry (a screenshot of the command
-- window) and an entry confirmed (the frame, so the second Shock can be placed after the Mimic's confirm)
do
  local rawLog = H.log
  H.log = function(msg)
    if type(msg) == "string" then
      local k = msg:match("^%[kit%] f%d+ entry (%d+) of %d+: confirmed, char %$0C")
      if k then confirmed[tonumber(k)] = H.frame end
    end
    return rawLog(msg)
  end
end
local windowShot = {}
local function shots()
  emu.addEventCallback(function()
    local k = #shocks + 1
    if seat ~= nil and k <= 3 and not windowShot[k] and H.readByte(0x62CA) == seat and H.readByte(0x7BC2) == 0x05 then
      windowShot[k] = true
      shotAt[#shotAt + 1] = { f = H.frame + 12, tag = "battle_leoshock_window" .. k }
    end
    for i = #shotAt, 1, -1 do
      if H.frame >= shotAt[i].f then H.screenshot(shotAt[i].tag); table.remove(shotAt, i) end
    end
  end, emu.eventType.endFrame)
end

local function dmg(s, e) return s.before[e].hp - s.after[e].hp end

H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/wor_leo.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    arm()
    shots()
    H.assertEq(H.readByte(REC + 1), 0x10, "slot 12 wears Leo's sprite (gen_wor_leo's reveal)")
  end),
  pickShock(),
  H.call(function()
    H.assertEq(H.readByte(REC + 0x17), CMD_SHOCK, "Shock in his second command row")
    rowReads[GOGO_ROW], rowReads[LEO_ROW], palLeo = 0, 0, 0
  end),
  -- the shore by Thamasa (world group 56: gen_wor_thamasa_plain's lap) until a battle opens
  (function()
    local wp = 1
    local pts = { SHORE, FALCON }
    return H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return pts[wp][1] end, function() return pts[wp][2] end,
        { maxFrames = 6000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() wp = wp % 2 + 1 end),
    }, "a random battle on the shore")
  end)(),
  H.waitUntil(function() return H.battleActive() end, 3000, "the battle is up", 2),
  H.call(stage),
  H.kitBattle(proxy, { untilPlanDone = true, idle = "defend", maxFrames = 60000, care = false,
    planDone = function() return #shocks >= 3 and shocks[3].after ~= nil end }),
  H.call(function()
    H.assertEq(#shocks >= 3, true, "three Shocks ran (Shock, Mimic's copy, the boosted Shock)")
    for i = 1, 3 do
      local s = shocks[i]
      H.assertEq(s.after ~= nil, true, string.format("Shock %d resolved", i))
      H.assertEq(s.mp1, s.mp0, string.format("Shock %d cost no MP (%d -> %d)", i, s.mp0, s.mp1))
      local hit, n = 0, 0
      for e, b in pairs(s.before) do
        n = n + 1
        local a = s.after[e]
        H.log(string.format("[leoshock] Shock %d m%d: HP %d -> %d (%d), shields %d -> %d%s, revealed $%02X -> $%02X",
          i, (e - 8) // 2, b.hp, a and a.hp or -1, a and (b.hp - a.hp) or -1, b.sh, a and a.sh or -1,
          a and a.br and " Broken" or "", b.rev, a and a.rev or -1))
        if a then
          if a.hp < b.hp then hit = hit + 1 end
          H.assertEq(a.sh, b.sh, string.format("Shock %d took no shield from m%d", i, (e - 8) // 2))
          H.assertEq(a.br, b.br, string.format("Shock %d broke nothing on m%d", i, (e - 8) // 2))
          H.assertEq(a.rev, b.rev, string.format("Shock %d revealed no weakness on m%d (non-elemental)", i, (e - 8) // 2))
        end
      end
      H.assertEq(hit, n, string.format("Shock %d hit every standing monster (%d of %d)", i, hit, n))
    end
    H.assertEq(shocks[1].queued, CMD_SHOCK, "the first Shock was queued as Shock")
    H.assertEq(shocks[1].pend, 0, "and ran at 0 BP")
    H.assertEq(confirmed[2] ~= nil and shocks[2].f > confirmed[2] and (confirmed[3] == nil or shocks[2].f < confirmed[3]),
      true, "the second Shock ran after his Mimic was confirmed (kit entry 2, command $12) and before entry 3")
    H.assertEq(shocks[3].queued, CMD_SHOCK, "the third was queued as Shock")
    H.assertEq(shocks[3].pend, 2, "and ran at 2 BP pending")
    for e in pairs(shocks[1].before) do
      if shocks[2].after[e] and shocks[3].after[e] then
        local d1, d2, d3 = dmg(shocks[1], e), dmg(shocks[2], e), dmg(shocks[3], e)
        H.log(string.format("[leoshock] m%d: Shock %d, Mimic's copy %d (x%.2f), Shock at 2 BP %d (x%.2f)",
          (e - 8) // 2, d1, d2, d2 / d1, d3, d3 / d1))
        H.assertEq(d2 >= d1 * 0.87 and d2 <= d1 * 1.15, true, string.format("m%d: the copy's damage is the first "
          .. "Shock's (no multiplier on a 0-BP Mimic)", (e - 8) // 2))
        H.assertEq((d3 >= d1 * 3.5 or d3 == 9999) and d3 <= d1 * 4.6, true, string.format("m%d: the 2-BP Shock's "
          .. "damage is four times the first's (the multiplier)", (e - 8) // 2))
      end
    end
    H.log("[leoshock] PASS: LEO's battle sprite, palette, row and mask; Shock free, keyless, multiplied by its boost; "
      .. "Mimic copies it")
  end),
})
