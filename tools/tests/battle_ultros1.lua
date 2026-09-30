-- @suite savestate=ultros1_entry slow
-- battle_ultros1.lua -- a Broken monster's counter plays its story and holds
-- its attacks back (#329), on the Lete River.  Boots ultros1_entry (Ultros's
-- battle as it loads; gen_scenario), where Ultros ($12C, 5 shields,
-- slash|pierce, fire-weak) answers fire with a story block that carries an
-- attack:
--
--     if_element FIRE / dlg $0b ("Yaaooouch!  Seafood soup!") /
--     attack SPECIAL
--
-- The party Fights him unboosted (one chip a weapon hand, the least damage
-- a chip costs) until he is Broken; then TERRA casts Fire on him while the
-- others Defend.  Asserted:
--   1. the Fire lands on a Broken, living Ultros;
--   2. dlg $0b runs from his counter, on cue (within 900 frames of the
--      cast), while he is still Broken and alive -- a Broken monster's story
--      blocks run (Ot6MayAct / Ot6AISkip, ot6_break.asm); on main's ROM his
--      counter was refused and the line never came;
--   3. the SPECIAL after it does not: from the fixture to 300 frames past
--      the line, Ultros's AI queues no attack or command while he is Broken
--      (_1b28, where every attack/cmd/item an AI script picks is queued),
--      counter or turn.  Its control: the same hook sees him queue attacks
--      while unbroken.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros1_entry.mss.lua"

local ULTROS1 = 0x012C
local TERRA = 0x00                        -- character id ($3ED8 per slot)
local FIRE = 0x00                         -- spell id
local ON_CUE = 900                        -- unbroken: 371 frames (lab probe)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_MAGIC, ST_TGT, ST_DEF = 0x05, 0x0E, 0x38, 0x27
local CMDTBL, CMDROW = 0x202E, 0x890F
local CMD_FIGHT, CMD_MAGIC = 0x00, 0x02
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }

local uSlot = nil
local function ent() return 8 + uSlot * 2 end
local function brk() return H.readByte(0x3E88 + ent()) end
local function shields() return H.readByte(0x3E38 + ent()) end
local function uhp() return H.readWord(0x3BFC + uSlot * 2) end

local lines, queues = {}, {}
local fire = nil                          -- TERRA's Fire, once confirmed

local function spellIndex(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
end

local M = { actor = nil, n = 0, via = nil }
local function pulse()
  if H.readByte(MENU) == 0 then
    M.actor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR) & 3
  if M.actor ~= a then M.actor, M.n, M.via = a, 0, nil end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  local broken = brk() > 0 and uhp() > 0
  local caster = H.readByte(0x3ED8 + a * 2) == TERRA
  -- the plan: Fight until he breaks; then TERRA's Fire, the others Defend;
  -- after the Fire, everyone Defends
  local plan = "fight"
  if fire or broken then plan = (caster and not fire) and "fire" or "defend" end
  if st == ST_CMD then
    if plan == "defend" then
      H.setPad(ph < 5 and { "right" } or {})      -- the Def. side window
      return
    end
    local want = plan == "fire" and CMD_MAGIC or CMD_FIGHT
    local cell
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == want then cell = i end
    end
    if cell == nil then
      H.assertEq(cell ~= nil, true, string.format("actor %d's command list " ..
        "holds command $%02X", a, want))
    end
    local cur = H.readByte(CMDROW + a)
    if cur ~= cell then
      H.setPad(ph < 5 and { cur < cell and "down" or "up" } or {})
      return
    end
    if H.readByte(0x3E9D + a * 2) > 0 then        -- never boosted
      H.setPad(ph < 5 and { "l" } or {})
      return
    end
    M.via = plan
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  if st == ST_DEF then
    H.setPad(ph < 5 and { plan == "defend" and "a" or "b" } or {})
    return
  end
  if st == ST_MAGIC then
    if plan ~= "fire" then H.setPad(ph < 5 and { "b" } or {}); return end
    local idx = spellIndex(a, FIRE)
    if idx == nil then
      H.assertEq(idx ~= nil, true, "TERRA's magic list holds Fire")
    end
    local wantRow, wantCol = idx // 2, idx % 2
    local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
    local col = H.readByte(0x8917 + a)
    if absRow ~= wantRow then
      H.setPad(ph < 5 and { absRow < wantRow and "down" or "up" } or {})
      return
    end
    if col ~= wantCol then
      H.setPad(ph < 5 and { col < wantCol and "right" or "left" } or {})
      return
    end
    M.via = "magic"
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  if st == ST_TGT then
    if plan == "fire" then
      if M.via ~= "magic" then H.setPad(ph < 5 and { "b" } or {}); return end
      if H.readByte(0x7B7E) == 0 then H.setPad(ph < 5 and { "right" } or {}); return end
      if ph == 0 then
        fire = fire or { f = H.frame, brk = brk(), hp = uhp(), sh = shields() }
      end
    end
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  -- a list or a side window the plan never means to be in: back out
  if st == 0x0A or st == 0x30 or st == 0x16 or st == 0x24 then
    H.setPad(ph < 5 and { "b" } or {})
    return
  end
  H.setPad({})
end
local function driver() return H.call(pulse) end

local function lineAfter(f)
  for _, e in ipairs(lines) do
    if e.id == 0x0B and e.f >= f then return e end
  end
end

H.run({ maxFrames = 40000 }, {
  H.loadState(DOOR),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros's battle up", 10),
  H.call(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == ULTROS1
         and (H.readByte(0x3AA8 + s * 2) & 1) == 1 and uSlot == nil then uSlot = s end
    end
    H.assertEq(uSlot ~= nil, true, "Ultros ($12C) is up")
    H.log(string.format("[ultros1] slot %d: shields %d, hp %d", uSlot, shields(), uhp()))
    local f3, atk = H.sym("AICmd_f3"), H.sym("_1b28")
    emu.addMemoryCallback(function()
      if H.readByte(0x00F6) ~= ent() then return end
      local e = { f = H.frame, id = H.readByte(0x3A2D), brk = brk(), hp = uhp(),
                  counter = H.readByte(0x00B1) & 1 }
      lines[#lines + 1] = e
      H.log(string.format("[ultros1] dlg $%02X f%d counter=%d brk=%d hp=%d",
        e.id, e.f, e.counter, e.brk, e.hp))
    end, emu.callbackType.exec, f3, f3)
    emu.addMemoryCallback(function()
      if H.readByte(0x00F6) ~= ent() then return end
      local e = { f = H.frame, cmd = H.readByte(0x3A2C), arg = H.readByte(0x3A2D),
                  brk = brk(), hp = uhp(), counter = H.readByte(0x00B1) & 1 }
      queues[#queues + 1] = e
      H.log(string.format("[ultros1] AI queues cmd $%02X arg $%02X f%d counter=%d brk=%d hp=%d",
        e.cmd, e.arg, e.f, e.counter, e.brk, e.hp))
    end, emu.callbackType.exec, atk, atk)
  end),
  H.driveUntil(function() return fire ~= nil end, 20000, { driver() },
    "TERRA's Fire on the Broken Ultros is confirmed"),
  H.call(function()
    H.log(string.format("[ultros1] Fire confirmed f%d: brk=%d shields=%d hp=%d",
      fire.f, fire.brk, fire.sh, fire.hp))
    H.assertEq(fire.brk > 0 and fire.hp > 0, true, "the Fire goes onto a " ..
      "Broken, living Ultros")
  end),
  H.driveUntil(function() return lineAfter(fire.f) ~= nil end, ON_CUE,
    { driver() }, "Ultros's fire line (dlg $0b) runs on cue while he is Broken"),
  H.call(function()
    local e = lineAfter(fire.f)
    H.log(string.format("[ultros1] dlg $0B f%d (counter=%d brk=%d hp=%d), " ..
      "%d frames after the Fire", e.f, e.counter, e.brk, e.hp, e.f - fire.f))
    H.assertEq(e.counter, 1, "dlg $0b came from his counter")
    H.assertEq(e.brk > 0 and e.hp > 0, true, "while he was Broken and alive " ..
      "(not his dying counter)")
    H.screenshot("ultros1_fireline")
  end),
  (function()
    local n = 0
    return H.driveUntil(function() n = n + 1; return n > 300 end, 400,
      { driver() }, "300 more frames")
  end)(),
  H.call(function()
    local unbroken, bad = 0, {}
    for _, q in ipairs(queues) do
      if q.brk == 0 then unbroken = unbroken + 1
      elseif q.hp > 0 then bad[#bad + 1] = q end
    end
    H.assertEq(unbroken > 0, true, "control: the _1b28 hook saw Ultros " ..
      "queue attacks while unbroken")
    for _, q in ipairs(bad) do
      H.log(string.format("[ultros1] BROKEN QUEUE: cmd $%02X arg $%02X f%d counter=%d brk=%d",
        q.cmd, q.arg, q.f, q.counter, q.brk))
    end
    H.assertEq(#bad, 0, "while Broken, Ultros's AI queued no attack or " ..
      "command (the SPECIAL behind his fire line was held back)")
    H.log("[ultros1] PASSED")
  end),
})
