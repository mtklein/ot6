-- @suite savestate=fc_alcove
-- battle_procboost.lua -- a boosted Fight's weapon spell takes the boost
-- multiplier.
--
-- A weapon that casts on hit (Blizzard: Ice) adds the spell to the same
-- action: CheckWeaponMagic writes $3400 and _c237eb runs it with $b5 = $02
-- and $b6 = the spell, while the queued pair $3a7c/$3a7d still says Fight.
-- Nothing folded that cast, so Ot6BoostDmg must multiply it.  468b08ae keyed
-- the tier test on $b5/$b6, the cast read as a folded Ice, and it went out
-- unmultiplied (probe_fight_proc_boost: `CAST b5=$02 b6=$01 ... p3 820->820`
-- on f0484b6f, `820->6560` on v0.20 and on the queued-pair key).
--
-- From fc_alcove: leave the alcove onto the continent, pace to a random
-- encounter, everyone Defends until the weapon-casting character's bank
-- holds 3, snapshot that command window.  Then, from the snapshot, R R R and
-- Fight through the real menus, each try after a longer idle wait at the
-- window (the cast is a 1-in-4 roll per hit; monsters acting during the
-- wait move the RNG), until a try's Fight casts.  No state is written.
-- Asserted, on every Ot6BoostDmg call that character makes during a try:
--   1. a weapon cast (command $02, $b6 = the weapon's spell, a fold-table
--      spell, queued command $00) arrives with pending 3 and leaves x8
--      (saturating at $7fff);
--   2. the swings themselves (command $00) leave unmultiplied -- Fight spends
--      its boost on swings, not on the multiplier;
--   3. at least one try cast (the setup produced the case at all).
-- Negative control: on f0484b6f (OT6_ROM/OT6_DBG) 1 goes red, 820 -> 820.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local BOOST = 3
local MAX_TRIES = 20
local WAIT_STEP = 48

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_TGT = 0x05, 0x27, 0x38
local BANK, PEND = 0x3E9C, 0x3E9D            -- OT6_BP_CLASS / OT6_BOOST_REVEALED
local CMD_FIGHT, CMD_MAGIC = 0x00, 0x02
local HANDS = 0x3CA8                          -- battle weapons: main +0, off +1, x = entity

local slot, spell, snap, armed = nil, nil, nil, nil
local tries, casts = {}, {}

local function ent() return slot * 2 end
local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
end
local function foldTbl()
  local t, base = {}, H.sym("Ot6FoldTbl") & 0x3FFFFF
  for i = 0, 23 do t[H.readRomByte(base + i)] = true end
  return t
end
-- the spell a weapon casts on hit: ItemProp+$12, bit 6 = cast on hit,
-- bits 0-5 = the spell
local function onHitSpell(item)
  if item == 0xFF then return nil end
  local b = H.readRomByte((H.sym("ItemProp") & 0x3FFFFF) + item * 30 + 0x12)
  if (b & 0x40) == 0 then return nil end
  return b & 0x3F
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
    if (emu.getState()["cpu.x"] & 0xFFFF) == ent() and #armed.calls > 0 then
      armed.endF = H.frame
    end
  end, emu.callbackType.exec, ae, ae)
end

local tick = 0
local function pulse(btn)
  tick = tick + 1
  H.setPad((btn and tick % 12 < 6) and { [btn] = true } or {})
end
-- everyone but `except` Defends: RIGHT opens Def., A commits it
local function defendOthers(except)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

local phase, held = "idle", nil
local function decide(t)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= slot then return nil end
    if H.readByte(PEND + ent()) < BOOST then return "r" end
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
    armed = t
    phase = "confirmed"
    return "a"
  end
end

-- one try from the snapshot, skipped once an earlier try has cast
local function tryStep(n)
  local t = { n = n, wait = (n - 1) * WAIT_STEP, calls = {} }
  local req, waited = nil, 0
  local skip = false
  return {
    H.call(function()
      skip = #casts > 0
      if skip then return end
      H.setPad({})
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      if skip then return end
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      H.assertEq(H.readByte(ACTOR) & 3, slot, "the snapshot is at the caster's window")
      tick, phase, held, waited = 0, "wait", nil, 0
    end),
    H.driveUntil(function() return skip or phase == "sent" end, 3000 + t.wait, {
      H.call(function()
        if phase == "wait" then
          waited = waited + 1
          H.setPad({})
          if waited >= t.wait then phase = "boost" end
          return
        end
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(t) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "boosted Fight, try " .. n),
    H.driveUntil(function() return skip or (t.endF ~= nil and H.frame >= t.endF + 30) end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, "the Fight resolves, try " .. n),
    H.call(function()
      if skip then return end
      armed = nil
      H.setPad({})
      tries[#tries + 1] = t
      local parts = {}
      for _, k in ipairs(t.calls) do
        local cast = k.b5 == CMD_MAGIC and k.b6 == spell
        parts[#parts + 1] = string.format("%s b5=$%02X b6=$%02X 3a7c=$%02X 3a7d=$%02X p%d %d->%s",
          cast and "CAST" or "swing", k.b5, k.b6, k.a7c, k.a7d, k.pend, k.din, tostring(k.dout))
        if cast then casts[#casts + 1] = k end
      end
      H.log(string.format("[procboost] try %d (wait %d): %s", n, t.wait, table.concat(parts, " | ")))
    end),
  }
end

local steps = {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function() installObservers() end),
  -- the alcove draws no encounters: out by its exit, 358 (8,8) north of the
  -- SavePoint, onto the continent (394), as gen_fc_escape does
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
    -- the first party member holding a weapon whose on-hit spell is a
    -- fold-table spell: the case the $b6 key misread
    local fold = foldTbl()
    for s = 0, 3 do
      local id = H.readByte(BCHID + s * 2)
      if id ~= 0xFF and slot == nil then
        for hand = 0, 1 do
          local item = H.readByte(HANDS + s * 2 + hand)
          local sp = onHitSpell(item)
          if sp and fold[sp] and slot == nil then
            slot, spell = s, sp
            H.log(string.format("[procboost] slot %d (char %d) holds $%02X, casts spell $%02X "
              .. "on hit; $%02X is in Ot6FoldTbl", s, id, item, sp, sp))
          end
        end
      end
    end
    assert(slot, "a party member holds a weapon that casts a fold-table spell on hit")
    H.assertEq(cmdRow(slot, CMD_FIGHT) ~= nil, true, "the caster has a Fight row")
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
  }, "the caster's window with " .. BOOST .. " pips banked"),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "snapshot at the caster's window") end),
}
for n = 1, MAX_TRIES do
  for _, s in ipairs(tryStep(n)) do steps[#steps + 1] = s end
end
steps[#steps + 1] = H.call(function()
  -- 3. the case happened
  H.assertEq(#casts > 0, true, string.format("a boosted Fight cast its weapon's spell "
    .. "within %d tries", #tries))
  local mult = 1 << BOOST
  for i, k in ipairs(casts) do
    -- 1. the cast carries the pending boost and leaves multiplied
    H.assertEq(k.a7c, CMD_FIGHT, "cast " .. i .. ": queued command is Fight")
    H.assertEq(k.pend, BOOST, "cast " .. i .. ": pending boost at Ot6BoostDmg")
    H.assertEq(k.dout, math.min(k.din * mult, 0x7FFF), string.format(
      "cast %d: Ot6BoostDmg leaves the weapon's spell x%d (%d in)", i, mult, k.din))
  end
  -- 2. the swings stay Fight's: no multiplier
  local swings = 0
  for _, t in ipairs(tries) do
    for _, k in ipairs(t.calls) do
      if k.b5 == CMD_FIGHT then
        swings = swings + 1
        H.assertEq(k.dout, k.din, string.format("try %d swing: unmultiplied (%d in)", t.n, k.din))
      end
    end
  end
  H.log(string.format("[procboost] %d cast(s) multiplied x%d over %d tries; %d swings unmultiplied",
    #casts, mult, #tries, swings))
end)

H.run({ maxFrames = 200000 }, steps)
