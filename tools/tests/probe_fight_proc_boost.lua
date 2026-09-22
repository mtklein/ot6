-- @manual
-- probe_fight_proc_boost.lua -- is the spell a weapon casts during a
-- boosted Fight multiplied?  (companion to probe_throw_boost.lua, same
-- 468b08ae / #237 question)
--
-- A weapon that casts on hit (Blizzard: Ice, ItemProp+$12 = $41) queues the
-- spell as a follow-up pass of the same action: CheckWeaponMagic writes
-- $3400, and _c237eb then sets $b6 = the spell and $b5 = GetCmdForAI = $02
-- while $3a7c/$3a7d keep the Fight's queue bytes.  Ot6BoostDmg sees that pass
-- as command $02.  Up to v0.20 its tier test read $3a7d (a player's Fight
-- queues $ff, in no table), so the cast took the pending boost's x2/x4/x8;
-- since 468b08ae it reads "fold command and $b6 in Ot6FoldTbl", and Ice ($01)
-- is in Ot6FoldTbl.
--
-- Fixture: fc_alcove (TERRA L26 holding Blizzard, LOCKE, SHADOW, EDGAR).
-- Leave the alcove onto the continent, pace to a random encounter, everyone
-- Defends until TERRA's bank holds 3, snapshot her command window, and from
-- it Fight at boost 0 and boost 3 through the real menus, each after a
-- different idle wait at the window (the proc is a 1-in-4 roll per hit, and
-- the wait moves what the monsters and the RNG do first).  Observed, never
-- written: every Ot6BoostDmg call TERRA makes ($11b0 in and out, $b5/$b6/
-- $3a7d, pending).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local TERRA = 0
local BOOST = 3
local WAITS = { 0, 24, 48, 72, 96, 120 }

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local BANK, PEND = 0x3E9C, 0x3E9D            -- OT6_BP_CLASS / OT6_BOOST_REVEALED
local MON_HP, TGTMONS = 0x3BFC, 0x7B7E
local CMD_FIGHT = 0x00

local slot, snap, armed = nil, nil, nil
local results = {}
local function ent() return slot * 2 end
local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
end
local function monHpStr()
  local t = {}
  for s = 0, 5 do t[#t + 1] = tostring(H.readWord(MON_HP + s * 2)) end
  return table.concat(t, " ")
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
  local base, form = bd & 0x3FFFFF, "NEITHER"
  for i = 0, 159 do
    local a, b, c = H.readRomByte(base + i), H.readRomByte(base + i + 1), H.readRomByte(base + i + 2)
    if a == 0xCD and b == 0x7D and c == 0x3A then form = "cmp $3a7d (v0.20 shape)" end
    if a == 0xC5 and b == 0xB6 then form = "cmp $b6 (468b08ae shape)" end
  end
  H.log(string.format("[rom] Ot6BoostDmg at $%06X; tier test: %s", bd, form))

  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x ~= ent() then return end
    armed.calls[#armed.calls + 1] = {
      b5 = H.readByte(0xB5), b6 = H.readByte(0xB6), a7d = H.readByte(0x3A7D),
      pend = H.readByte(PEND + x), din = H.readWord(0x11B0) }
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
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x == ent() and #armed.calls > 0 then
      armed.endF, armed.endPend = H.frame, H.readByte(PEND + x)
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
    if H.readByte(PEND + ent()) < c.boost then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(slot, CMD_FIGHT)
    local cur = H.readByte(CMDROW + slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "target"
    return "a"
  end
  if phase == "target" then
    if st == ST_CMD then return "a" end            -- the A was not taken
    if st ~= ST_TGT then return nil end
    c.tgt, c.pendAtConfirm = H.readByte(TGTMONS), H.readByte(PEND + ent())
    armed = c
    phase = "confirmed"
    return "a"
  end
end

local function runCase(c)
  local req, waited = nil, 0
  return {
    H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      H.assertEq(H.readByte(ACTOR) & 3, slot, "the snapshot is at TERRA's window")
      c.calls, tick, phase, held, waited = {}, 0, "wait", nil, 0
    end),
    H.driveUntil(function() return phase == "sent" end, 3000, {
      H.call(function()
        if phase == "wait" then
          waited = waited + 1
          H.setPad({})
          if waited >= c.wait then phase = "boost" end
          return
        end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, string.format("Fight at boost %d after %d frames", c.boost, c.wait)),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 60 end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, "the Fight resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      results[#results + 1] = c
      local parts = {}
      for _, k in ipairs(c.calls) do
        parts[#parts + 1] = string.format("%s b5=$%02X b6=$%02X 3a7d=$%02X p%d %d->%s",
          k.b5 == 0x02 and "CAST" or "swing", k.b5, k.b6, k.a7d, k.pend, k.din, tostring(k.dout))
      end
      H.log(string.format("[fight] boost=%d wait=%d pending at confirm %d, ActionEnd pending %s: %s",
        c.boost, c.wait, c.pendAtConfirm or -1, tostring(c.endPend), table.concat(parts, " | ")))
    end),
  }
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function() installObservers() end),
  H.navTo(8, 9, { maxFrames = 3000 }),
  H.driveUntil(function() return (H.mapId() & 0x3FF) == 394 end, 1800, {
    H.call(function()
      if not H.hasControl() then H.setPad({}) return end
      H.setPad({ up = true })
    end),
  }, "alcove -> 394"),
  H.release(),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900, "control on 394", 10),
  (function()
    local lane
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "left", "right", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
          if lane == nil then H.setPad({}) return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
    }, "a random encounter")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(BCHID + s * 2) == TERRA then slot = s end
    end
    assert(slot, "TERRA is in the battle")
    H.log(string.format("[battle] TERRA in slot %d, right hand $%02X, left $%02X; monster HP %s",
      slot, H.readByte(0x1600 + 0x1F), H.readByte(0x1600 + 0x20), monHpStr()))
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
  }, "TERRA's window with " .. BOOST .. " pips banked"),
  H.waitFrames(2),
  H.call(function()
    H.checkReq(snap, "snapshot at TERRA's window")
    H.log(string.format("[snap] f%d TERRA's window: bank %d; monster HP %s",
      H.frame, H.readByte(BANK + ent()), monHpStr()))
  end),
}
for _, w in ipairs(WAITS) do
  for _, b in ipairs({ 0, BOOST }) do
    for _, s in ipairs(runCase({ boost = b, wait = w })) do steps[#steps + 1] = s end
  end
end
steps[#steps + 1] = H.call(function()
  for _, b in ipairs({ 0, BOOST }) do
    local casts, ratios = 0, {}
    for _, c in ipairs(results) do
      if c.boost == b then
        for _, k in ipairs(c.calls) do
          if k.b5 == 0x02 then
            casts = casts + 1
            ratios[#ratios + 1] = string.format("%d->%s", k.din, tostring(k.dout))
          end
        end
      end
    end
    H.log(string.format("[summary] boost %d: %d weapon casts through Ot6BoostDmg: %s",
      b, casts, #ratios > 0 and table.concat(ratios, ", ") or "none"))
  end
end)

H.run({ maxFrames = 200000 }, steps)
