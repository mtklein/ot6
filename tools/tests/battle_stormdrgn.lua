-- @suite savestate=stormdrgn_entry slow
-- battle_stormdrgn.lua -- the Storm Dragon under the boss contract (docs/design/bosses-wor.md block 6,
-- wt/v052-tg-wor2): Cyclonic is its telegraph, a break cancels it, and its gauge grows with each break.
--
-- Its script (ai_script.asm AIScript::_331): under 15,360 HP, on a low rotation's first turn, a roll of one in three
-- (if_roll 85, on the arming block, as the CzarDragon's worked example) arms monster switch 0 with that turn's attack;
-- its next turn, the fuse block (the script's first), attacks (Battle, Battle or Aero), says "It swallows the wind!"
-- (battle dialogue $A6) and glows; the turn after casts Cyclonic (attack $B2, command $0C) whatever its HP reads then.
-- Unarmed, the low rotation is vanilla's with Battle in Cyclonic's place: Cyclonic comes only announced.  Under the
-- contract (Ot6FuseTbl's row $014B) a break while it is lit cancels it: switch 0 cleared, the `wait` forgotten, the
-- roll to be won again.
-- Its gauge (Ot6GrowTbl, ot6_break.asm Ot6GaugeGrow): its row opens at 10 shields; each break's recovery adds two,
-- to 14; at 14 it stays.  The count the HUD draws is the new one from the recovery on.
--
-- Boots stormdrgn_entry (gen_wor_storm: the Storm Dragon's battle, event battle 133, as it comes up).  From a
-- snapshot at the battle's open:
--   grows     nothing staged and nothing held: the route's own fight driver (gen_wor_storm's STORM_FIGHT under the
--             tactical base) breaks it from its opening gauge; at each recovery (up to two) its max reads two more, to 14, the count is the
--             max, and the HUD's count tile for its slot is that count.  The first recovery is from 10.
--   cap       (DECLARED: the gauge staged to 1 and every class a key before each breaking Fight, M.fuseCases' own
--             staging) three breaks in a row: its max reads 12, 14, then 14 -- at its cap it stays.
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: the route's own fight driver
--             (gen_wor_storm's STORM_FIGHT under the tactical base) brings it from its full HP under the 15,360 line,
--             then the party Defends; the line comes and Cyclonic on its next turn, and lands: a member's HP falls.
--             The effect is logged member by member.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, HP held -- its at 12,000, under the line -- and the
--   party's):
--   unbroken  the party Defends; the line shows; the lit-fuse mark stands; Cyclonic is dispatched on its next turn, a
--             glow between; the mark goes; the line reads "It swallows the wind!" where the dialogue table points.
--   broken    an aimed Fight confirmed once the mark is up breaks it: the cancel fires, monster switch 0 reads clear,
--             the mark goes, no Cyclonic on its first turns back, and the line returns only after another roll under
--             the chance; Cyclonic follows.
--   outside   a break with no fuse lit: nothing is cancelled and the cells stand, and the fuse then lights and fires.
--   and in every case: Cyclonic comes only announced (every Cyclonic has its line since the one before); the script
--   names Cyclonic once (the fuse's); every roll of its arming block arms exactly when it is under the chance.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor2/mutants/): see the report there.  A mechanism
-- test, not play (grows and landed write nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row's classes and held HP through them; the cap case
-- stages the gauge and classes for its breaking Fights; nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/stormdrgn_entry.mss.lua"

local STORM, CYCLONIC, LINE = 0x14B, 0xB2, 0xA6
local OPEN, STEP, CAP = 10, 2, 14
local LOW = 15360
-- gen_wor_storm's own fight options for the dragon, under advanceStory's tactical base
local BASE = { tactical = true, boost = true, items = true, healPercent = 55 }
local STORM_FIGHT = { runic = true, bushido = true }
local HAVE = 0x7E0000 | (H.sym("OT6_SHHAVE") & 0xFFFF)

local function slotOf()
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == STORM then return s end
  end
  return nil
end
local function ent() local s = slotOf(); return s and 8 + 2 * s end

-- every dispatch of the line or of Cyclonic, over the suite
local seen, unannounced = {}, 0
-- every roll of its arming block: { f, r, n, armed }; gen counts the snapshots
local rollsSeen, gen = {}, 0
-- every recovery of the dragon's gauge: { f, before, after, count }
local recs = {}
local brks = {}
local watching = false
local function watchAll()
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFF
    if x < 8 or x > 18 or H.readWord(0x57C0 + (x - 8)) ~= STORM then return end
    local cmd, arg = H.readByte(0xB5), H.readByte(0xB6)
    if cmd == 0x21 and arg == LINE then seen[#seen + 1] = { f = H.frame, move = false } end
    if cmd == 0x0C and arg == CYCLONIC then
      local ok = #seen > 0 and not seen[#seen].move
      seen[#seen + 1] = { f = H.frame, move = true }
      if not ok then unannounced = unannounced + 1 end
      H.log(string.format("[storm] f%d Cyclonic dispatched: %s", H.frame, ok and "its line came since the Cyclonic "
        .. "before" or "UNANNOUNCED (no line since the Cyclonic before)"))
    end
  end, emu.callbackType.exec, H.sym("_dispatcher"), H.sym("_dispatcher"))
  local ro = H.sym("Ot6AIRolled")
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if y ~= ent() then return end
    rollsSeen[#rollsSeen + 1] = { f = H.frame, r = emu.getState()["cpu.a"] & 0xFF, n = H.readByte(0x3A2E), gen = gen,
      armed = false, sw = H.readByte(0x3DAC + y) & 0x01, sw1 = H.readByte(0x3DAC + y) & 0x02 }
  end, emu.callbackType.exec, ro, ro)
  emu.addMemoryCallback(function()
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == ent() then brks[#brks + 1] = { f = H.frame, gen = gen } end
  end, emu.callbackType.exec, H.sym("Ot6HitBroke"), H.sym("Ot6HitBroke"))
  -- the gauge, a frame at a time: a recovery is the broken timer reaching 0
  local lastTicks, lastMax = nil, nil
  emu.addEventCallback(function()
    local e = ent()
    if e == nil then lastTicks = nil; return end
    local r = rollsSeen[#rollsSeen]
    if r ~= nil and r.gen == gen and r.sw == 0 and H.readByte(0x3DAC + e) & 0x01 ~= 0 then r.armed = true end
    local ticks, mx = H.readByte(0x3E88 + e), H.readByte(0x3E39 + e)
    -- the HUD's count tile for its slot: the frames from the recovery until the flush has uploaded the new count
    local lr = recs[#recs]
    if watching and lr ~= nil and lr.hudF == nil and H.frame - lr.f <= 60 and H.readByte(HAVE + lr.slot) == lr.count then
      lr.hudF = H.frame - lr.f
      H.log(string.format("[storm] f%d the HUD's count tile for slot %d reads %d, %d frame(s) after the recovery",
        H.frame, lr.slot, lr.count, lr.hudF))
    end
    if watching and lastTicks ~= nil and lastTicks > 0 and ticks == 0 then
      recs[#recs + 1] = { f = H.frame, before = lastMax, after = mx, count = H.readByte(0x3E38 + e), slot = slotOf(),
        hp = H.readWord(0x3BF4 + e) }
      H.log(string.format("[storm] f%d recovered from a break: max %d -> %d, count %d; its HP %d, status 1 $%02X; the "
        .. "HUD's tile for its slot reads %d", H.frame, lastMax, mx, H.readByte(0x3E38 + e), H.readWord(0x3BF4 + e),
        H.readByte(0x3EE4 + e), H.readByte(HAVE + slotOf())))
    end
    lastTicks, lastMax = ticks, mx
  end, emu.eventType.endFrame)
end
-- the HUD's count tile for the dragon's slot drew each recovery's new count within 60 frames of it (the watcher's
-- hudF); waits out the last recovery's 60 frames while the battle stands, then stops the watch.  A recovery the
-- battle's end cut short of its 60 frames is logged and not judged.
local function hudCheck(what)
  return H.seqStep({
    H.waitUntil(function()
      local r = recs[#recs]
      return r == nil or r.hudF ~= nil or H.frame - r.f > 60 or not H.battleLoadStarted()
    end, 120, what .. ": the last recovery's 60 frames", 1),
    H.call(function()
      watching = false
      local e = ent()
      for k, r in ipairs(recs) do
        local gone = not H.battleLoadStarted() or e == nil or H.readWord(0x3BF4 + e) == 0
          or (H.readByte(0x3EE4 + e) & 0xC0) ~= 0
        if r.hudF == nil and k == #recs and gone then
          H.log(string.format("[storm] %s: recovery %d's HUD tile not judged: the dragon fell or the battle ended "
            .. "within its 60 frames (the line draws empty)", what, k))
        else
          if r.hudF == nil then
            H.log(string.format("[storm] %s: recovery %d: the HUD's tile for slot %d reads %d now (the count %d), the "
              .. "dragon's HP %d, status 1 $%02X", what, k, r.slot, H.readByte(HAVE + r.slot), r.count,
              e and H.readWord(0x3BF4 + e) or -1, e and H.readByte(0x3EE4 + e) or -1))
          end
          H.assertEq(r.hudF ~= nil, true, string.format("%s: recovery %d: the HUD's count tile for its slot drew the new "
            .. "count (%d) within 60 frames", what, k, r.count))
        end
      end
    end),
  })
end

local function effect(m)
  local t, fell = {}, 0
  for i = 0, 3 do
    local id = H.readByte(0x3ED8 + 2 * i)
    if id ~= 0xFF then
      local now, mx = H.readWord(0x3BF4 + 2 * i), H.readWord(0x3C1C + 2 * i)
      local hit = m.tchars & (1 << i) ~= 0
      if hit and now < m.hp[i] then fell = fell + 1 end
      t[#t + 1] = string.format("seat %d char $%02X %s: %d -> %d of %d (%d%% of max), status $%02X/$%02X", i, id,
        hit and "a target" or "NOT a target", m.hp[i], now, mx, mx > 0 and (m.hp[i] - now) * 100 // mx or 0,
        H.readByte(0x3EE4 + 2 * i), H.readByte(0x3EF8 + 2 * i))
    end
  end
  H.log(string.format("[storm] effect: the move ($%02X/$%02X, targets $%02X) on the party: %s", m.cmd, m.arg, m.tchars,
    table.concat(t, "; ")))
  return fell
end

-- the route's own fight driver (gen_wor_storm's STORM_FIGHT under the tactical base) until done() or the battle ends
-- (the first cut's plain aimed Fights, Tonics for care, wiped on the replay's draw after the first recovery:
-- build/attempts/wt/v052-tg-wor2/d1/suites/battle_stormdrgn-1.log)
local function routeUntil(done, max, what)
  local F = nil
  return H.seqStep({
    H.call(function() F = H.fightDriverFor("storm-" .. what, BASE, STORM_FIGHT) end),
    H.driveUntil(function() return done() or not H.battleLoadStarted() or ent() == nil end, max,
      { H.call(function() F.frame() end) }, "storm " .. what .. ": the route's driver"),
  })
end

local S = {}
H.run({ maxFrames = 140000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "the Storm Dragon's battle is up", 2),
  H.call(function()
    local at = H.aiAttacks(STORM, CYCLONIC)
    H.log(string.format("[storm] its turn script names Cyclonic at %d place(s)", #at))
    H.assertEq(#at, 1, "the Storm Dragon's turn script names Cyclonic once: the fuse's move (not its low rotation's "
      .. "second turn)")
    -- the growth row, read from the ROM
    local g = H.sym("Ot6GrowTbl") & 0x3FFFFF
    local rows, mine = {}, nil
    local x = g
    while (H.readRomByte(x) | (H.readRomByte(x + 1) << 8)) ~= 0xFFFF do
      local sp = H.readRomByte(x) | (H.readRomByte(x + 1) << 8)
      rows[#rows + 1] = string.format("$%03X +%d to %d", sp, H.readRomByte(x + 2), H.readRomByte(x + 3))
      if sp == STORM then mine = { step = H.readRomByte(x + 2), cap = H.readRomByte(x + 3) } end
      H.assertEq(H.readRomByte(x + 3) < 64, true, "every growth cap is under 64 (the gauge byte's bit 6 is the HUD's "
        .. "dead flag)")
      x = x + 4
    end
    H.log(string.format("[storm] Ot6GrowTbl: %s", table.concat(rows, "; ")))
    local e = ent()
    H.log(string.format("[storm] at the open: shields %d of %d, HP %d", H.readByte(0x3E38 + e), H.readByte(0x3E39 + e),
      H.readWord(0x3BF4 + e)))
    H.assertEq(H.readByte(0x3E39 + e), OPEN, "the Storm Dragon's gauge opens at 10 (its row)")
    watchAll()
  end),
  H.fuseSnap(S),

  -- ---- grows: the party's own breaks, nothing written ----
  H.call(function()
    gen = gen + 1; watching = true; recs = {}
    H.log("[storm] case grows, from the battle's open; nothing staged, nothing held")
  end),
  routeUntil(function() return #recs >= 2 end, 40000, "grows"),
  hudCheck("storm grows"),
  H.call(function()
    H.log(string.format("[storm] grows: %d recovery(ies) seen; the dragon's HP %d", #recs,
      ent() and H.readWord(0x3BF4 + ent()) or -1))
    H.assertEq(#recs >= 1, true, "storm grows: the route's driver broke the dragon by its own play and it recovered (one or more)")
    H.assertEq(recs[1].before, OPEN, "storm grows: the first break was of its opening gauge (10)")
    H.assertEq(recs[1].after, OPEN + STEP, "storm grows: the gauge came back from its first break with two more "
      .. "(10 -> 12)")
    for k, r in ipairs(recs) do
      H.assertEq(r.after, math.min(r.before + STEP, CAP), string.format("storm grows: recovery %d: max %d -> %d, two "
        .. "more to its cap of 14", k, r.before, r.after))
      H.assertEq(r.count, r.after, string.format("storm grows: recovery %d: the count is the new max", k))
    end
  end),
  H.fuseRestore(S, "storm grows"),

  -- ---- cap: three staged breaks in a row ----
  H.call(function()
    gen = gen + 1; watching = true; recs = {}
    H.log("[storm] case cap, from the battle's open; DECLARED: the gauge staged to 1 and every class a key before "
      .. "each breaking Fight")
  end),
  (function()
    local steps = {}
    for k = 1, 3 do
      steps[#steps + 1] = H.lazy(function()
        local n0 = #recs
        local staged = false
        local plan = {}
        for i = 0, 3 do
          local id = H.readByte(0x3ED8 + 2 * i)
          if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and #plan == 0 then
            plan[1] = { who = id, cmd = 0x00, boost = 0, slot = slotOf(), confirmWhen = function()
              local e = ent()
              if e == nil or H.readByte(0x3E88 + e) > 0 then return false end
              if not staged then
                staged = true
                WRITE.byte(0x3E9C + e, 0x3F)
                WRITE.byte(0x3E38 + e, 1)
                H.log(string.format("[storm] f%d cap: the gauge staged to 1, every class a key (break %d)", H.frame, k))
              end
              return true
            end }
          end
        end
        return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = 12000,
          giveUp = function() return #recs > n0 or ent() == nil end })
      end)
    end
    return H.seqStep(steps)
  end)(),
  hudCheck("storm cap"),
  H.call(function()
    local t = {}
    for _, r in ipairs(recs) do t[#t + 1] = string.format("%d -> %d", r.before, r.after) end
    H.log(string.format("[storm] cap: the recoveries: %s", table.concat(t, ", ")))
    H.assertEq(#recs, 3, "storm cap: three breaks, three recoveries")
    H.assertEq(recs[1].after, 12, "storm cap: the first recovery reads 12")
    H.assertEq(recs[2].after, CAP, "storm cap: the second recovery reads 14")
    H.assertEq(recs[3].after, CAP, "storm cap: at its cap the gauge stays 14 (the third recovery reads 14)")
    H.assertEq(recs[3].count, CAP, "storm cap: the count at the cap is 14")
  end),
  H.fuseRestore(S, "storm cap"),

  -- ---- landed: the route's driver to the line, nothing written ----
  H.call(function() gen = gen + 1 end),
  H.fuseLanded({
    tag = "storm", species = STORM, line = LINE, move = { cmd = 0x0C, atk = CYCLONIC }, turns = 1,
    arm = function(pred, max, W)
      local F = nil
      return H.seqStep({
        H.call(function() F = H.fightDriverFor("storm-landed", BASE, STORM_FIGHT) end),
        H.driveUntil(function()
          local e = W.ent()
          return pred() or e == nil or H.readWord(0x3BF4 + e) < LOW
        end, 60000, { H.call(function() F.frame() end) }, "storm landed: the route's driver to the 15,360 line"),
        H.call(function()
          local e = W.ent()
          H.log(string.format("[storm] landed: the driver brought it to %d HP (the game's own); the party Defends",
            e and H.readWord(0x3BF4 + e) or -1))
        end),
        H.lazy(function()
          local t1 = H.frame
          return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 40600,
            giveUp = function() return pred() or H.frame - t1 >= 40000 end })
        end),
      })
    end,
    landed = function(W, l, m)
      H.log(string.format("[storm] landed: the line at f%d (its HP %d then), Cyclonic at f%d", l.f,
        W.cells() and W.cells().hp or -1, m.f))
      local fell = effect(m)
      H.assertEq(fell >= 1, true, "storm landed: Cyclonic landed (a target's HP fell within 420 frames)")
    end,
  }),
  H.fuseRestore(S, "storm"),
  H.call(function() gen = gen + 1 end),
  H.fuseCases({
    tag = "storm", species = STORM, write = WRITE,
    line = LINE, move = { cmd = 0x0C, atk = CYCLONIC }, turns = 1, glows = 1,
    lineText = "It swallows the wind!{wait}",
    arm = "idle", aim = true, plainBreaker = true,
    bossHp = 12000,
    onOpen = function() gen = gen + 1 end,
    -- no fuse lit and none armed (monster switch 0 clear)
    partway = function(W)
      local c = W.cells()
      return c ~= nil and not W.litBit() and (c.mvar & 0x01) == 0
    end,
    earned = function(C, W)
      local pre, post = C.brk.pre, C.brk.post
      H.assertEq(pre.mvar & 0x01, 1, "storm: monster switch 0 stood at the break (the roll had armed the fuse)")
      H.assertEq(post.mvar & 0x01, 0, "storm: monster switch 0 is clear after the cancel (the roll is to be won "
        .. "again)")
      H.assertEq(post.blk, 0xFF, "storm: the script waits nowhere after the cancel ($3240 = $FF)")
      local won = 0
      for _, r in ipairs(rollsSeen) do
        if r.gen == gen and r.f > C.brk.f and r.f < C.lines[2].f and r.r < r.n then won = won + 1 end
      end
      H.assertEq(won >= 1, true, "storm: a roll under the chance came between the cancel and the second line")
    end,
  }),
  H.call(function()
    local t, under = {}, 0
    for _, r in ipairs(rollsSeen) do
      t[#t + 1] = string.format("%d/%d%s", r.r, r.n, r.armed and "*" or "")
      if r.r < r.n then under = under + 1 end
      local cut = false
      for _, b in ipairs(brks) do if b.gen == r.gen and b.f >= r.f and b.f <= r.f + 300 then cut = true end end
      if cut and r.r < r.n and not r.armed then
        H.log(string.format("[storm] the roll at f%d was under the chance, and a break purged its turn: not armed", r.f))
      else
        H.assertEq(r.armed, r.r < r.n, string.format("storm: the roll at f%d (%d against a chance of %d in 256) %s the "
          .. "fuse", r.f, r.r, r.n, r.r < r.n and "arms" or "does not arm"))
      end
    end
    H.log(string.format("[storm] the arming rolls (roll/chance, * armed): %s -- %d under the chance of %d", table.concat(t,
      " "), under, #rollsSeen))
    local off, mid = 0, 0
    for _, r in ipairs(rollsSeen) do
      if r.n ~= 85 then off = off + 1 end
      if r.sw1 ~= 0 then mid = mid + 1 end
    end
    H.assertEq(#rollsSeen >= 1 and off, 0, "storm: its arming block rolled, and every roll's chance is 85 in 256 (a "
      .. "third of the low rotations, vanilla's share of Cyclonic)")
    H.assertEq(mid, 0, "storm: every roll comes on a low rotation's first turn (monster switch 1 clear: one roll a "
      .. "rotation)")
    local n = 0
    for _, x in ipairs(seen) do if x.move then n = n + 1 end end
    H.log(string.format("[storm] Cyclonic dispatched %d time(s) over the suite, %d unannounced", n, unannounced))
    H.assertEq(n >= 3 and unannounced, 0, "Cyclonic comes only announced (every Cyclonic has its line since the one "
      .. "before; three or more seen)")
  end),
  H.logStep("[storm] PASS: the gauge grows to its cap, the announce, Cyclonic on its next turn, the cancel and the "
    .. "roll again"),
})
