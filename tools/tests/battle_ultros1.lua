-- @suite savestate=ultros1_entry slow
-- battle_ultros1.lua -- a Broken monster's counter plays its story and holds
-- its attacks back (#329), on the Lete River.  Boots ultros1_entry (the
-- dialog before Ultros's battle, waiting on a press; gen_scenario) and pages
-- it into the battle, so the battle seeds its RNG from the clock after the
-- boot and a seed shift is a different fight.  (The first cut booted three
-- frames into the load, after InitBattle had seeded $be: every shift was
-- the same fight.)  Ultros ($12C, 5 shields,
-- slash|pierce, fire-weak) answers fire with a story block that carries an
-- attack:
--
--     if_element FIRE / dlg $0b ("Yaaooouch!  Seafood soup!") /
--     attack SPECIAL
--
-- The party Fights him unboosted (one chip a weapon hand, the least damage
-- a chip costs) until he is Broken, with BANON's Health and Fenix Downs
-- keeping it standing (the care note at the driver); then TERRA casts Fire
-- on him while the others Defend.  Breaking him before the party falls is
-- this file's precondition, reached by that play rather than by the
-- fixture's luck.  Asserted:
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

-- The party's care, played the way a person would.  The river deals its
-- fights before this one with no field menu between them, so the party
-- arrives with whatever the last fight left: on 2.1.1's fixture 244/271
-- 280/280 258/324 192/192, on MesenCE 2.2.1's 116/271 82/280 123/324
-- 46/192 with EDGAR, SABIN and BANON Dark (the same levels, gear and gil;
-- probe in build/attempts/wt/suites-2.2.1/), and Fighting with no care
-- the party wiped before the break at every shift.  So, on each actor's
-- turn, before the plan below:
--   * BANON uses Health (cmd $1A, his designed sustain: a whole-party heal
--     that costs no MP) while a living member is below CARE_PCT of max HP,
--     boosted with every pip he banks (cap 3) -- one strong heal, not
--     several weak turns;
--   * otherwise a dead member is raised with a Fenix Down, TERRA first (no
--     TERRA, no Fire), one raise in flight at a time.
-- TERRA's Fire on a Broken Ultros outranks both: the Broken window is the
-- point of the fight.  The Fighters stay unboosted: a boosted volley's
-- swings past the last chip land Broken (x4) and can kill him before
-- TERRA's turn comes.
local CARE_PCT = 60
local CMD_ITEM, CMD_HEALTH = 0x01, 0x1A
local ST_ITEM = 0x0A
local FENIX = 0xF0
local BATTINV, ITEMSCR, ITEMROW = 0x2686, 0x8947, 0x894F
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local function chid(s) return H.readByte(0x3ED8 + s * 2) end
local function php(s) return H.readWord(0x3BF4 + s * 2) end
local function pmax(s) return H.readWord(0x3C1C + s * 2) end
local function seated(s) return chid(s) ~= 0xFF and pmax(s) > 0 end
local function bank(s) return H.readByte(0x3E9C + s * 2) end
local function partyLine()
  local t = {}
  for s = 0, 3 do
    if seated(s) then
      t[#t + 1] = string.format("%02X:%d/%d st1=%02X bp%d", chid(s), php(s),
        pmax(s), H.readByte(0x3EE4 + s * 2), bank(s))
    end
  end
  return table.concat(t, " ")
end
local function cmdCell(a, want)
  for i = 0, 3 do
    if H.readByte(CMDTBL + a * 12 + i * 3) == want then return i end
  end
end
local function invIdx(item)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == item and H.readByte(BATTINV + i * 5 + 3) > 0 then
      return i
    end
  end
end
local function needsHealth()
  for s = 0, 3 do
    if seated(s) and php(s) > 0 and php(s) * 100 < pmax(s) * CARE_PCT then
      return true
    end
  end
  return false
end
local raising = nil                       -- { e, by, f }: a Fenix Down in flight
local cared = { health = 0, raise = 0 }
-- This turn's care, chosen once when the actor's window opens: "health",
-- "raise" (with its target), or nil for the plan below.
local function carePlan(a, caster, broken)
  if raising and (php(raising.e) > 0 or H.frame - raising.f > 900) then raising = nil end
  if caster and broken and not fire then return nil end
  if cmdCell(a, CMD_HEALTH) ~= nil and needsHealth() then return "health" end
  if raising == nil and cmdCell(a, CMD_ITEM) ~= nil and invIdx(FENIX) ~= nil then
    for pass = 1, 2 do
      for s = 0, 3 do
        if seated(s) and php(s) == 0 and (chid(s) == TERRA) == (pass == 1) then
          return "raise", s, invIdx(FENIX)
        end
      end
    end
  end
  return nil
end

local M = { actor = nil, n = 0, via = nil, care = nil, tgt = nil, idx = nil }
local brokeSaid = false
local function pulse()
  local broken = brk() > 0 and uhp() > 0
  if broken and not brokeSaid then
    brokeSaid = true
    H.log(string.format("[ultros1] Broken f%d: brk=%d hp=%d | party %s",
      H.frame, brk(), uhp(), partyLine()))
  end
  if H.readByte(MENU) == 0 then
    M.actor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR) & 3
  local caster = H.readByte(0x3ED8 + a * 2) == TERRA
  if M.actor ~= a then
    M.actor, M.n, M.via = a, 0, nil
    M.care, M.tgt, M.idx = carePlan(a, caster, broken)
    H.log(string.format("[ultros1] f%d turn: actor %d (%02X) %s | Ultros brk=%d " ..
      "hp=%d | party %s", H.frame, a, chid(a),
      M.care == "raise" and string.format("raise slot %d", M.tgt)
        or M.care or "plan", brk(), uhp(), partyLine()))
  end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  -- the plan: care first (above); else Fight until he breaks; then TERRA's
  -- Fire, the others Defend; after the Fire, everyone Defends
  local plan = M.care or "fight"
  if M.care == nil and (fire or broken) then
    plan = (caster and not fire) and "fire" or "defend"
  end
  if st == ST_CMD then
    if plan == "defend" then
      H.setPad(ph < 5 and { "right" } or {})      -- the Def. side window
      return
    end
    local want = ({ fire = CMD_MAGIC, health = CMD_HEALTH, raise = CMD_ITEM })[plan]
      or CMD_FIGHT
    local cell = cmdCell(a, want)
    if cell == nil then
      H.assertEq(cell ~= nil, true, string.format("actor %d's command list " ..
        "holds command $%02X", a, want))
    end
    local cur = H.readByte(CMDROW + a)
    if cur ~= cell then
      H.setPad(ph < 5 and { cur < cell and "down" or "up" } or {})
      return
    end
    -- the boost: Health takes every pip banked (cap 3); everything else
    -- goes unboosted
    local boost = plan == "health" and math.min(bank(a), 3) or 0
    local pend = H.readByte(0x3E9D + a * 2)
    if pend ~= boost then
      H.setPad(ph < 5 and { pend < boost and "r" or "l" } or {})
      return
    end
    if M.via ~= plan and plan == "health" then
      cared.health = cared.health + 1
      H.log(string.format("[ultros1] f%d Health, boost %d (#%d) | party %s",
        H.frame, boost, cared.health, partyLine()))
    end
    M.via = plan
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  if st == ST_DEF then
    H.setPad(ph < 5 and { plan == "defend" and "a" or "b" } or {})
    return
  end
  if st == ST_ITEM then
    if plan ~= "raise" then H.setPad(ph < 5 and { "b" } or {}); return end
    local cur = H.readByte(ITEMSCR + a) + H.readByte(ITEMROW + a)
    if cur ~= M.idx then
      H.setPad(ph < 5 and { cur < M.idx and "down" or "up" } or {})
      return
    end
    M.via = "item"
    H.setPad(ph < 5 and { "a" } or {})
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
      if H.readByte(TGTMONS) == 0 then H.setPad(ph < 5 and { "right" } or {}); return end
      if ph < 5 then
        fire = fire or { f = H.frame, brk = brk(), hp = uhp(), sh = shields() }
      end
    elseif plan == "raise" then
      if M.via ~= "item" then H.setPad(ph < 5 and { "b" } or {}); return end
      local chars = H.readByte(TGTCHARS)
      if H.readByte(TGTMONS) ~= 0 or chars == 0 then
        H.setPad(ph < 5 and { H.battleLayout().toChars[1] } or {})
        return
      end
      if chars ~= (1 << M.tgt) then
        local cur = 0
        for s = 3, 0, -1 do if chars & (1 << s) ~= 0 then cur = s end end
        H.setPad(ph < 5 and { cur < M.tgt and "down" or "up" } or {})
        return
      end
      if ph < 5 and raising == nil then
        raising = { e = M.tgt, by = a, f = H.frame }
        cared.raise = cared.raise + 1
        H.log(string.format("[ultros1] f%d Fenix Down on slot %d (%02X) by actor %d " ..
          "(#%d) | party %s", H.frame, M.tgt, chid(M.tgt), a, cared.raise, partyLine()))
      end
    end
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  -- a list or a side window the plan never means to be in: back out
  if st == 0x30 or st == 0x16 or st == 0x24 then
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
  -- the fixture is the dialog before his battle, waiting on a press: page it
  -- (A, edge-tapped, only while a dialog waits) until the battle loads.  How
  -- long that press waits is what a seed shift varies, so the fight is drawn
  -- here, not in the fixture ([seed] first battle, the runner's line)
  (function()
    local n = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function()
        n = H.dialogWaiting() and n + 1 or 0
        H.setPad((n > 0 and n % 8 < 4) and { "a" } or {})
      end),
    }, "the dialog paged into Ultros's battle")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "Ultros's battle up", 10),
  H.call(function()
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == ULTROS1
         and (H.readByte(0x3AA8 + s * 2) & 1) == 1 and uSlot == nil then uSlot = s end
    end
    H.assertEq(uSlot ~= nil, true, "Ultros ($12C) is up")
    H.log(string.format("[ultros1] slot %d: shields %d, hp %d", uSlot, shields(), uhp()))
    H.log(string.format("[ultros1] arrival: party %s", partyLine()))
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
  (function()
    local last = nil                    -- the last frame the battle read live
    return H.driveUntil(function()
      if fire ~= nil then return true end
      local seatedN, standing = 0, 0
      for s = 0, 3 do
        if seated(s) then
          seatedN = seatedN + 1
          if php(s) > 0 then standing = standing + 1 end
        end
      end
      if seatedN > 0 then
        last = { f = H.frame, brk = brk(), sh = shields(), hp = uhp(), party = partyLine() }
      end
      if seatedN == 0 or standing == 0 then
        error(string.format("precondition: the party breaks Ultros and TERRA " ..
          "casts Fire before it falls -- the party is down at f%d; last live " ..
          "read f%d: Ultros brk=%d shields=%d hp=%d | party %s (care: %d " ..
          "Health, %d Fenix Down)", H.frame, last and last.f or -1,
          last and last.brk or -1, last and last.sh or -1, last and last.hp or -1,
          last and last.party or "-", cared.health, cared.raise), 0)
      end
      return false
    end, 20000, { driver() },
    "TERRA's Fire on the Broken Ultros is confirmed")
  end)(),
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
