-- @suite slow
-- battle_foldbumrush.lua -- Bum Rush's four blows play one animation (#554).
--
-- docs/design/multi-hit.md 5.3.  Each blow of a fixed multi-hit is a whole
-- pass; since #554 the battle script plays the animation for the first and
-- carries each later blow as a folded strike (command $04, Ot6GfxCmdFold:
-- no animation, a 24-frame beat, the earlier numerals retired), each with
-- its own numeral.  battle_bumrush's draws by Duncan's house are one-blow
-- kills (its scripts read '1 blow(s) landed'), so they never see a fold;
-- here the four blows must land.
--
-- Played: Continue wor-gau-v1 (SABIN, Bum Rush just taught), lap two world
-- tiles into a random battle, field care first (99 MP is a soft
-- precondition), and play SABIN's Bum Rush at three points through the real
-- menu (H.kitBattle; the others Defend while he banks).  DECLARED WRITE
-- (state_write_waivers.txt): at the battle's start every monster is staged
-- to 60000 HP, so no blow kills and all four passes run (battle_bumrushmimic
-- stages the same way).  Asserted, from the action's own events:
--   1. the action made four passes (Ot6PassTargeted with x = SABIN);
--   2. its battle script, read as BtlGfx_04 plays it, is the name, one Bum
--      Rush animation ($06, command Blitz $0a) and its numeral, then three
--      folded strikes each followed by its numeral: 01 06 0B 04 0B 04 0B 04 0B;
--   3. each folded strike's numeral starts at least 24 frames after the one
--      before it (the beat), measured at ExecGfxCmd.
-- Negative: v0.49's ROM plays four animations and folds none
-- (build/attempts/wt/v050-multihit-anim/foldsuites/).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local SABIN, CMD_BLITZ, BUMRUSH = 0x05, 0x0A, 0x64
local STAGED_HP = 60000

local seat, rec, battles = nil, nil, 0

local function arm()
  local hc = H.sym("Ot6HitCount")
  emu.addMemoryCallback(function()
    if seat == nil or rec ~= nil or (emu.getState()["cpu.a"] & 0xFF) ~= BUMRUSH then return end
    rec = { f = H.frame, passes = 0, cmds = {}, pend = H.readByte(0x3E9D + seat * 2) }
  end, emu.callbackType.exec, hc, hc)
  local pt = H.sym("Ot6PassTargeted")
  emu.addMemoryCallback(function()
    if rec == nil or rec.q ~= nil or (emu.getState()["cpu.x"] & 0xFF) ~= seat * 2 then return end
    rec.passes = rec.passes + 1
  end, emu.callbackType.exec, pt, pt)
  local b4 = H.sym("BtlGfx_04")
  emu.addMemoryCallback(function()
    if rec == nil or rec.q ~= nil then return end
    local q = {}
    for i = 0, 63 do
      local c = H.readByte(0x2D6E + i * 4)
      if c == 0xFF then break end
      q[#q + 1] = { c = c, b1 = H.readByte(0x2D6F + i * 4) }
    end
    rec.q = q
  end, emu.callbackType.exec, b4, b4)
  local eg = H.sym("ExecGfxCmd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.q == nil or rec.done then return end
    rec.cmds[#rec.cmds + 1] = { c = emu.getState()["cpu.a"] & 0xFF, f = H.frame }
  end, emu.callbackType.exec, eg, eg)
  local ud = H.sym("UpdateDead")
  emu.addMemoryCallback(function()
    if rec ~= nil and rec.q ~= nil and not rec.done then rec.done = H.frame end
  end, emu.callbackType.exec, ud, ud)
end

local function closed() return rec ~= nil and rec.done ~= nil end

local function judge()
  local codes, anim = {}, 0
  for _, e in ipairs(rec.q) do
    codes[#codes + 1] = string.format("%02X", e.c)
    if e.c == 0x06 and e.b1 == CMD_BLITZ then anim = anim + 1 end
  end
  local played, beats = {}, {}
  local lastNum, afterFold = nil, false
  for _, c in ipairs(rec.cmds) do
    played[#played + 1] = string.format("%02X@%d", c.c, c.f - rec.cmds[1].f)
    if c.c == 0x04 then afterFold = true end
    if c.c == 0x0B then
      if afterFold and lastNum then beats[#beats + 1] = c.f - lastNum end
      lastNum, afterFold = c.f, false
    end
  end
  H.log(string.format("[foldbumrush] battle %d: Bum Rush at %d BP, %d pass(es); script [%s]; played {%s}; "
    .. "beats {%s}", battles, rec.pend, rec.passes, table.concat(codes, " "), table.concat(played, " "),
    table.concat(beats, ",")))
  H.assertEq(rec.pend, 3, "Bum Rush ran at three points pending")
  H.assertEq(rec.passes, 4, "the action made four passes: every blow landed on a standing body (staged HP)")
  H.assertEq(anim, 1, "the script plays the Bum Rush animation ONCE for its four blows (#554; v0.49 played four)")
  H.assertEq(table.concat(codes, " "), "01 06 0B 04 0B 04 0B 04 0B",
    "name, the animation and its numeral, then three folded strikes each with its numeral")
  H.assertEq(#beats, 3, "three folded strikes' numerals were played")
  for i, b in ipairs(beats) do
    H.assertEq(b >= 24, true, string.format("folded strike %d's numeral lands a beat (%d frames, at least 24) "
      .. "after the one before", i + 1, b))
  end
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
  })
end

local judged = false
local function decide()
  battles = battles + 1
  H.assertEq(battles <= 6, true, "a battle SABIN can play Bum Rush in, within 6 battles")
  seat, rec = nil, nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == SABIN then seat = s end end
  H.assertEq(seat ~= nil, true, "SABIN is seated")
  H.assertEq(H.readWord(0x3C08 + seat * 2) >= 99, true, "SABIN holds 99 MP at the battle's start (the field care)")
  for m = 0, 5 do
    if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
      H.writeWord(0x3BFC + m * 2, STAGED_HP)
      H.writeWord(0x3C24 + m * 2, STAGED_HP)
    end
  end
  H.log(string.format("[foldbumrush] battle %d: monsters staged to %d HP (declared write)", battles, STAGED_HP))
end

H.run({ maxFrames = 300000 }, {
  H.bootCheckpoint("wor-gau-v1"),
  H.call(function()
    arm()
    H.assertEq(H.readByte(0x1D28) & 0x80, 0x80, "SABIN knows Bum Rush ($1D28 bit 7: Duncan, gen_wor_gau)")
    local x, y = H.worldX(), H.worldY()
    A = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      if B == nil and H.worldPassable(x + d[1], y + d[2]) then B = { x + d[1], y + d[2] } end
    end
    H.assertEq(B ~= nil, true, "a passable tile beside the party")
  end),
  H.driveUntil(function() return judged end, 280000, {
    H.cond(function() return not H.battleActive() end, {
      H.fieldCare({ threshold = 1.0, tag = "foldbumrush", mpBand = 0.9 }),
      pace("a random battle by Duncan's house"),
    }, {}),
    H.call(decide),
    H.kitBattle({ { who = SABIN, cmd = CMD_BLITZ, row = BUMRUSH, boost = 3, direct = true } },
      { untilPlanDone = true, idle = "defend", maxFrames = 60000, planDone = closed }),
    H.call(function()
      if closed() then judge(); judged = true
      else H.log("[foldbumrush] the battle ended before the Bum Rush resolved: not counted") end
    end),
    H.cond(function() return not judged and H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
  }, "a Bum Rush whose four blows land"),
  H.call(function()
    H.log("[foldbumrush] PASS: four passes, one animation, three folded strikes a beat apart, a numeral each")
  end),
})
