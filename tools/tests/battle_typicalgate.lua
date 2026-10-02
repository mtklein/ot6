-- @suite savestate=wor_grave
-- battle_typicalgate.lua -- the typical-action gate read against the
-- engine's own account (review of ad048b29, made independent on the review
-- of 4ff9b236): Dullahan's fight, the grave pressed with A as the route
-- does, played by the fight driver one call a frame.
--
-- The ground truth does not read what the driver reads.  The driver keys
-- its ledger off party HP deltas, the $B1 counter flag and the $B8 target
-- bits at each ExecCmd entry, and its turns off the monster's ATB gauge.
-- This file keys off:
--   the turns: the ATB queueing one (gaugefull's `jsr _c24e77`, "add
--              action to queue", checked against the ROM bytes: one per
--              gauge fill, a Broken monster's refused turn included), and
--              every ExecCmd entry of that monster after it that ExecRetal
--              did not run -- the driver reads the gauge's high byte
--              instead;
--   the counters: ExecRetal (@4b7b) and the entry it runs;
--   the damage: ApplyDmg (@12f5) as the engine applies it, $33D0,y on a
--              party target y, capped at that target's HP;
--   the final targets: the targets ApplyDmg was called on.
-- A unit counts when it is a counter that landed HP, or a turn that did
-- not land only on monsters.  The script's $2E/$2F entries are nobody's
-- action.  A unit's value is the most HP it took off one member.  The
-- truth block is build/lab/care/truth_hook.lua's, kept in step by hand.
--
-- Asserted at the fight's end, the driver's ledger flushed
-- (Driver:flushLedger), for every slot:
--   - the count (L.actN) and the typical sum (L.actSum) equal the
--     engine's;
--   - precondition: at least one counter landed (Dullahan's retal Battle,
--     "if_hit: attack NOTHING, NOTHING, BATTLE", ai_script.asm:5470).
-- The bcf5240f-ad048b29 reading (H.MONACT_OLD) closed 89 actions over arm
-- B's 32 fights at ad048b29 (build/attempts/wt/care-policy-review/
-- recount_r3.txt, dull_r10_B), where lab_grave logged 227 monster ExecCmd
-- entries ($2E/$2F excluded: build/attempts/wt/care-policy/dull/
-- dull_r10_B); f8f9ad66's arm on the same snapshots logged 223
-- (dull_policy_basesnap).  It is this file's negative control.
-- No chain fixture stands at a two-action monster's fight.  The
-- two-action case (the last of three $011 in gen_tunnelarmr's first
-- battle, ai_script.asm _17: "if_num_monsters 1 / attack SPECIAL / attack
-- BATTLE, BATTLE, NOTHING") is the lab's: build/lab/care/truth_hook.lua
-- on that generator (build/attempts/wt/care-policy/twoact/).  Nothing here
-- writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"
TRUTH_LAB = false
TRUTH = { units = {}, turn = {}, retal = {}, cur = nil, inBattle = false }
do
  local T = TRUTH
  -- (each address by a literal H.sym("...") call: compose.py injects only
  -- the symbols it finds written that way)
  local function hookAt(a, fn)
    emu.addMemoryCallback(function()
      local st = emu.getState()
      fn(st["cpu.x"] & 0xffff, st["cpu.y"] & 0xffff)
    end, emu.callbackType.exec, a, a)
  end
  local function newUnit(x, counter)
    local u = { slot = x // 2 - 4, counter = counter, cmds = {}, per = {}, hitParty = false, hitMon = false }
    T.units[#T.units + 1] = u
    return u
  end
  function T.install()
    if T.installed then return end
    T.installed = true
    -- the jsr inside gaugefull: checked against the ROM's own bytes
    local q = H.sym("gaugefull") + 0x1C
    local target = H.sym("_c24e77") & 0xFFFF
    local f = q & 0x3FFFFF
    if H.readRomByte(f) ~= 0x20 or (H.readRomByte(f + 1) | (H.readRomByte(f + 2) << 8)) ~= target then
      error(string.format("truth_hook: no `jsr _c24e77` at gaugefull+$1C ($%06X)", q))
    end
    hookAt(q, function(x) if x >= 8 and x < 20 then T.turn[x] = newUnit(x, false) end end)
    hookAt(H.sym("ExecRetal"), function(x) if x >= 8 and x < 20 then T.retal[x] = true end end)
    -- a retal script that issued nothing runs no ExecCmd: its mark ends
    -- when control is back at the top of the battle loop (ExecRetal
    -- pushes BattleLoop-1 as its return)
    hookAt(H.sym("BattleLoop"), function() T.retal = {} end)
    hookAt(H.sym("ExecCmd@battle_code"), function(x)
      T.cur = nil
      if x < 8 or x >= 20 or x % 2 ~= 0 then return end
      local u
      if T.retal[x] then
        T.retal[x] = nil
        u = newUnit(x, true)
      else
        u = T.turn[x] or newUnit(x, false)
        T.turn[x] = u
      end
      u.cmds[#u.cmds + 1] = H.readByte(0xB5)
      T.cur = u
    end)
    hookAt(H.sym("ApplyDmg"), function(x, y)
      local u = T.cur
      if u == nil or (H.readByte(0x11A2) & 0x80) ~= 0 then return end
      if y < 8 then
        u.hitParty = true
        local dmg = H.readWord(0x33D0 + y)
        if dmg ~= 0xFFFF and dmg > 0 then
          local hp = H.readWord(0x3BF4 + y)
          u.per[y // 2] = (u.per[y // 2] or 0) + math.min(dmg, hp)
        end
      elseif y < 20 then
        u.hitMon = true
      end
    end)
  end
  function T.reset() T.units, T.turn, T.retal, T.cur = {}, {}, {}, nil end
  -- the expected count and sum per slot, and the units' lines
  function T.expected()
    local want, lines = {}, {}
    for i, u in ipairs(T.units) do
      local script = #u.cmds > 0
      for _, c in ipairs(u.cmds) do if c ~= 0x2E and c ~= 0x2F then script = false end end
      local v = 0
      for _, d in pairs(u.per) do if d > v then v = d end end
      local counted
      if #u.cmds == 0 or script then counted = false
      elseif u.counter then counted = v > 0
      else counted = not (u.hitMon and not u.hitParty) end
      local cs = {}
      for _, c in ipairs(u.cmds) do cs[#cs + 1] = string.format("$%02X", c) end
      lines[#lines + 1] = string.format("unit %d: slot %d %s cmds %s value %d -> %s", i, u.slot,
        u.counter and "counter" or "turn", table.concat(cs, ","), v, counted and "counted" or "out")
      if counted then
        local w = want[u.slot] or { n = 0, sum = 0 }
        w.n, w.sum = w.n + 1, w.sum + v
        want[u.slot] = w
      end
    end
    return want, lines
  end
end
TRUTH.install()

local F
local function up() return H.battleLoadStarted() and H.monstersPresent() > 0 end
local function tick()
  if not up() then F.idle(); return end
  F.frame()
end

H.run({ maxFrames = 30000 }, {
  H.loadState(STATE),
  H.waitFrames(10),
  H.call(function()
    TRUTH.reset()
    F = H.newFightDriver("typicalgate", { tactical = true, boost = true, items = true, runic = true })
  end),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave: face up, A"),
  H.release(),
  H.waitUntil(function() return up() end, 3000, "the fight is up", 1),
  H.driveUntil(function() return not up() end, 25000, { H.call(tick) }, "the driver's play"),
  H.release(),
  H.call(function()
    F.driver:flushLedger()
    local want, lines = TRUTH.expected()
    for _, l in ipairs(lines) do H.log("[typicalgate] " .. l) end
    local landed = 0
    for _, u in ipairs(TRUTH.units) do
      local v = 0
      for _, d in pairs(u.per) do if d > v then v = d end end
      if u.counter and v > 0 then landed = landed + 1 end
    end
    H.assertEq(landed >= 1, true, "precondition: a counterattack landed HP in the fight (Dullahan's retal Battle)")
    for s = 0, 5 do
      local w, L = want[s], F.driver.hitLedger[s]
      if w ~= nil or (L and (L.actN or 0) > 0) then
        local wn, ws = w and w.n or 0, w and w.sum or 0
        local gn, gs = L and L.actN or 0, L and L.actSum or 0
        H.log(string.format("[typicalgate] slot %d: the engine's units %d (sum %d), the driver's ledger %d (sum %d)",
          s, wn, ws, gn, gs))
        H.assertEq(gn, wn, string.format("slot %d: the driver's typical-action count is the engine's", s))
        H.assertEq(gs, ws, string.format("slot %d: the driver's typical-action sum is the engine's", s))
      end
    end
    H.log("[typicalgate] PASSED")
  end),
})
