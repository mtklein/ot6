-- @manual
-- probe_rage_boost.lua -- does a boosted Rage's start-turn attack take the
-- damage multiplier?  (companion to probe_throw_boost / probe_fight_proc_boost)
--
-- Ot6BoostDmg exempts command $10 by `lda $b5 / cmp #$10`, but Cmd_10 runs the
-- possessed attack through _c21554, which rewrites $b5 to GetCmdForAI of the
-- attack ($02 for a spell, $00 for Battle/Special) before any damage is
-- computed, and the pending boost is live on the start turn (Ot6RageTierStore:
-- "the pending byte is not consumed until Ot6ActionEnd").  So which rage
-- attacks multiply depends on the tier test alone: v0.20 and f0484b6f skip a
-- spell in Ot6FoldTbl, the queued-pair key ($3a7c = $10) skips none.
--
-- From gau_joined: pace to a Veldt encounter, everyone Defends until GAU's
-- bank holds 3, snapshot his command window.  From it, for each of the first
-- ENTRIES rage-window cells: R R R (tier 3 = the special, no coin), Rage, the
-- cell, confirm, and log every Ot6BoostDmg call GAU makes on that action.
-- Reads only.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local GAU = 0x0B
local BOOST = 3
local ENTRIES = 8

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_RAGE = 0x05, 0x27, 0x1E
local RSCROLL, RCOL, RROW = 0x892B, 0x892F, 0x8933
local BANK, PEND = 0x3E9C, 0x3E9D
local CMD_RAGE = 0x10
local RAGELIST, RAGECOUNT = 0x257E, 0x3A9A

local slot, snap, armed = nil, nil, nil
local function ent() return slot * 2 end
local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local bd = H.sym("Ot6BoostDmg")
  local b0, b1, b2 = bd & 0xFF, (bd >> 8) & 0xFF, (bd >> 16) & 0xFF
  local sites = {}
  for off = 0x020000, 0x02FFFC do
    if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == b0
       and H.readRomByte(off + 2) == b1 and H.readRomByte(off + 3) == b2 then
      sites[#sites + 1] = 0xC00000 + off + 4
    end
  end
  H.assertEq(#sites, 2, "Ot6BoostDmg has two call sites in bank $C2")
  local base, seen = bd & 0x3FFFFF, {}
  for i = 0, 159 do
    local a, b, c = H.readRomByte(base + i), H.readRomByte(base + i + 1), H.readRomByte(base + i + 2)
    if a == 0xCD and b == 0x7D and c == 0x3A then seen.a7d = true end
    if a == 0xAD and b == 0x7C and c == 0x3A then seen.a7c = true end
    if a == 0xC5 and b == 0xB6 then seen.b6 = true end
  end
  H.log("[rom] tier test: " .. (seen.b6 and "executing $b5/$b6 (468b08ae)"
    or (seen.a7c and seen.a7d) and "queued $3a7c/$3a7d"
    or seen.a7d and "queued attack $3a7d only (v0.20)" or "NEITHER"))
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x ~= ent() then return end
    armed.calls[#armed.calls + 1] = {
      b5 = H.readByte(0xB5), b6 = H.readByte(0xB6), a7c = H.readByte(0x3A7C),
      a7d = H.readByte(0x3A7D), pend = H.readByte(PEND + x), din = H.readWord(0x11B0) }
  end, emu.callbackType.exec, bd, bd)
  for _, ret in ipairs(sites) do
    emu.addMemoryCallback(function()
      if armed == nil or armed.endF or #armed.calls == 0 then return end
      local c = armed.calls[#armed.calls]
      if c.dout == nil then c.dout = H.readWord(0x11B0) end
    end, emu.callbackType.exec, ret, ret)
  end
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) == ent() then
      armed.endF = H.frame
      armed.beast = H.readByte(0x33A8 + ent())
    end
  end, emu.callbackType.exec, ae, ae)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end
local function defendOthers(except)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

local phase, held = "idle", nil
local function decide(c)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= slot then return nil end
    if H.readByte(PEND + ent()) < BOOST then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(slot, CMD_RAGE)
    local cur = H.readByte(CMDROW + slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "list"
    return "a"
  end
  if phase == "list" then
    if st == ST_CMD then return "a" end
    if st ~= ST_RAGE then return nil end
    local row = H.readByte(RSCROLL + slot) + H.readByte(RROW + slot)
    local col = H.readByte(RCOL + slot)
    local wr, wc = c.entry // 2, c.entry % 2
    if col ~= wc then return wc > col and "right" or "left" end
    if row ~= wr then return wr > row and "down" or "up" end
    c.pendAtConfirm = H.readByte(PEND + ent())
    armed = c
    phase = "confirming"
    return "a"
  end
  if phase == "confirming" then
    -- a follow-up target select, if the beast's attack asks for one
    if H.readByte(MENU) ~= 0 and a == slot and st ~= ST_CMD then return "a" end
    if st == ST_CMD and a == slot then return nil end
    phase = "sent"
    return nil
  end
end

local function runCase(c)
  local req
  return {
    H.call(function()
      c.skip = c.entry >= H.readByte(RAGECOUNT)
      if c.skip then return end
      H.setPad({}); req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      if c.skip then return end
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      c.calls, tick, phase, held = {}, 0, "boost", nil
    end),
    H.driveUntil(function() return c.skip or phase == "sent" or (armed == c and c.endF ~= nil) end, 3000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "Rage entry " .. c.entry),
    H.driveUntil(function() return c.skip or (c.endF ~= nil and H.frame >= c.endF + 30) end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, "the rage start resolves"),
    H.call(function()
      if c.skip then return end
      armed = nil
      H.setPad({})
      local rage = H.sym("MonsterRage") & 0x3FFFFF
      local special = c.beast and H.readRomByte(rage + c.beast * 2 + 1) or -1
      local parts = {}
      for _, k in ipairs(c.calls) do
        parts[#parts + 1] = string.format("b5=$%02X b6=$%02X 3a7c=$%02X 3a7d=$%02X p%d %d->%s",
          k.b5, k.b6, k.a7c, k.a7d, k.pend, k.din, tostring(k.dout))
      end
      H.log(string.format("[rage] entry %d: beast $%02X (special $%02X), pending at confirm %s: %s",
        c.entry, c.beast or 0xFF, special, tostring(c.pendAtConfirm),
        #parts > 0 and table.concat(parts, " | ") or "no Ot6BoostDmg call"))
    end),
  }
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function() installObservers() end),
  (function()
    local dirs = { "left", "right", "up", "down" }
    local di, lastPos, n = 1, nil, 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not H.worldHasControl() then H.setPad({}) return end
        n = n + 1
        local pos = H.worldX() * 256 + H.worldY()
        if n >= 24 then
          if pos == lastPos then di = di % 4 + 1
          else di = (di % 2 == 1) and di + 1 or di - 1 end
          lastPos, n = pos, 0
        end
        H.setPad({ [dirs[di]] = true })
      end),
    }, "a Veldt encounter")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(BCHID + s * 2) == GAU then slot = s end
    end
    assert(slot, "GAU is in the battle")
    local list, rage = {}, H.sym("MonsterRage") & 0x3FFFFF
    for i = 0, H.readByte(RAGECOUNT) - 1 do
      local m = H.readByte(RAGELIST + i)
      list[#list + 1] = string.format("$%02X(special $%02X)", m, H.readRomByte(rage + m * 2 + 1))
    end
    H.log(string.format("[battle] GAU in slot %d; %d known rages: %s", slot,
      H.readByte(RAGECOUNT), table.concat(list, " ")))
  end),
  H.driveUntil(function() return snap ~= nil end, 30000, {
    H.call(function()
      local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
      if H.readByte(MENU) ~= 0 and st == ST_CMD and a == slot
         and H.readByte(BANK + ent()) >= BOOST and H.readByte(PEND + ent()) == 0 then
        H.setPad({})
        snap = H.requestSaveState()
        return
      end
      defendOthers(-1)
    end),
  }, "GAU's window with " .. BOOST .. " pips banked"),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot at GAU's window") end),
}
for e = 0, ENTRIES - 1 do
  for _, s in ipairs(runCase({ entry = e })) do steps[#steps + 1] = s end
end

H.run({ maxFrames = 200000 }, steps)
