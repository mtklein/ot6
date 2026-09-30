-- @suite savestate=ultros4_entry slow
-- battle_ultros4.lua -- the story on a counter plays while its monster is
-- Broken (#329), on the airship deck.  Boots ultros4_entry (the Blackjack's
-- deck at the Ultros teaser; gen_fc_landing), walks to the deck's right edge
-- to arm Ultros IV ($168, 7 shields, slash|pierce), and fights him the way
-- that lets the party break him before his story line: every member Fights
-- unboosted while he is unbroken (one chip a weapon hand, the least damage a
-- chip costs), then boosted with every pip once he is Broken.  His counter
--
--     if_hit / if_monster_switch_clr 1 / if_hp SELF, 12800 /
--     dlg $53 / restore_monsters MONSTER_1, SIDE / dlg $57 /
--     set_monster_switch 1
--
-- ("I lose AGAIN!  ...Mr. Chupon!  Come on down!") is all story.  Asserted:
--   1. the hit that takes Ultros under 12,800 HP lands while he is Broken
--      (the precondition: named if a draw breaks the line first);
--   2. Chupon's entry (dlg $53, restore_monsters) runs on cue, within 900
--      frames of that hit, from the counter of a living Ultros who is still
--      Broken -- a Broken monster's story blocks run (Ot6MayAct / Ot6AISkip,
--      ot6_break.asm); before #329 it waited, and here it arrived only as
--      Ultros's dying counter;
--   3. it runs once: the block's set_monster_switch 1, after the anchor,
--      ran too (1800 more frames of fighting bring no second entry);
--   4. while he is Broken, Ultros's own AI queues no attack or command
--      (_1b28, every attack/cmd/item an AI script queues) and runs no turn
--      (no dlg/entry/event from his turn script): only his counter's story.
local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/ultros4_entry.mss.lua"

local ULTROS4 = 0x0168
local LINE = 12800                        -- `if_hp SELF, 12800`
local ON_CUE = 900                          -- unbroken: 275-278 frames (lab probe)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT = 0x05, 0x38
local CMDTBL, CMDROW = 0x202E, 0x890F
local CMD_FIGHT = 0x00

local function map() return H.mapId() & 0x3ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local uSlot = nil
local function brk() return H.readByte(0x3E88 + 8 + uSlot * 2) end
local function shields() return H.readByte(0x3E38 + 8 + uSlot * 2) end
local function uhp() return H.readWord(0x3BFC + uSlot * 2) end

local story, brokenAttacks = {}, {}
local cross = nil

-- chip-then-dump: Fight, unboosted while he is unbroken, every pip once
-- he is Broken; A taps through everything that is not a party menu
local M = { actor = nil, n = 0 }
local function pulse()
  if uSlot and not cross then
    local v = uhp()
    if v > 0 and v < LINE then
      cross = { f = H.frame, hp = v, brk = brk(), sh = shields() }
      H.log(string.format("[ultros4] HP under %d at f%d: hp=%d brk=%d shields=%d",
        LINE, H.frame, v, cross.brk, cross.sh))
    end
  end
  if H.readByte(MENU) == 0 then
    M.actor = nil
    H.setPad(H.frame % 8 < 4 and { "a" } or {})
    return
  end
  local a = H.readByte(ACTOR) & 3
  if M.actor ~= a then M.actor, M.n = a, 0 end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  if st == ST_CMD then
    local cell
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == CMD_FIGHT then cell = i end
    end
    if cell == nil then H.setPad({}); return end
    local cur = H.readByte(CMDROW + a)
    if cur ~= cell then
      H.setPad(ph < 5 and { cur < cell and "down" or "up" } or {})
      return
    end
    local want = (uSlot and brk() > 0) and math.min(H.readByte(0x3E9C + a * 2), 3) or 0
    if H.readByte(0x3E9D + a * 2) < want then
      H.setPad(ph < 5 and { "r" } or {})
      return
    end
    H.setPad(ph < 5 and { "a" } or {})
    return
  end
  if st == ST_TGT then H.setPad(ph < 5 and { "a" } or {}); return end
  -- a list or a side window this driver never means to be in: back out
  if st == 0x0A or st == 0x0E or st == 0x30 or st == 0x16 or st == 0x24
     or st == 0x27 then
    H.setPad(ph < 5 and { "b" } or {})
    return
  end
  H.setPad({})
end
local function driver() return H.call(pulse) end

-- b1 is the dlg id (low byte) or, for "entry", the entry/exit op (restore = 0)
local function firstStory(op, b1, after)
  for _, e in ipairs(story) do
    if e.op == op and (b1 == nil or (op == "entry" and e.b2 or e.b1) == b1)
       and e.f >= after then return e end
  end
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 10, "booted on the Blackjack's deck (map 10)")
    H.assertEq(sw(0x01F0), 1, "the Ultros teaser is up ($01F0)")
    H.assertEq(H.hasControl(), true, "controllable")
  end),
  -- arm Ultros IV: the deck's right edge (map 10 triggers (22,5-7))
  H.navTo(22, 6, { maxFrames = 6000,
                   arrive = function() return not H.hasControl() or H.fieldX() == 22 end }),
  H.driveUntil(function()
    if not (H.battleActive() or H.battleLoadStarted()) then return false end
    for s = 0, 5 do
      if H.readWord(0x57C0 + s * 2) == ULTROS4
         and (H.readByte(0x3AA8 + s * 2) & 1) == 1 then uSlot = s end
    end
    return uSlot ~= nil
  end, 6000, { H.call(function() H.setPad(H.frame % 8 < 4 and { "a" } or {}) end) },
    "Ultros IV's battle is up"),
  H.call(function()
    H.log(string.format("[ultros4] slot %d: shields %d, hp %d", uSlot,
      shields(), uhp()))
    H.assertEq(shields(), 7, "Ultros IV seeds 7 shields")
    H.assertEq(uhp() >= LINE, true, "Ultros IV starts above his story line")
    local ent = 8 + uSlot * 2
    local f3, f5, f7 = H.sym("AICmd_f3"), H.sym("AICmd_f5"), H.sym("AICmd_f7")
    local atk = H.sym("_1b28")
    local function rec(op)
      return function()
        if H.readByte(0x00F6) ~= ent then return end
        local e = { f = H.frame, op = op, b1 = H.readByte(0x3A2D),
                    b2 = H.readByte(0x3A2E), brk = brk(), hp = uhp(),
                    counter = H.readByte(0x00B1) & 1 }
        story[#story + 1] = e
        H.log(string.format("[ultros4] %s $%02X $%02X f%d counter=%d brk=%d hp=%d",
          op, e.b1, e.b2, e.f, e.counter, e.brk, e.hp))
      end
    end
    emu.addMemoryCallback(rec("dlg"), emu.callbackType.exec, f3, f3)
    emu.addMemoryCallback(rec("entry"), emu.callbackType.exec, f5, f5)
    emu.addMemoryCallback(rec("event"), emu.callbackType.exec, f7, f7)
    emu.addMemoryCallback(function()
      if H.readByte(0x00F6) ~= ent or brk() == 0 then return end
      brokenAttacks[#brokenAttacks + 1] = { f = H.frame, cmd = H.readByte(0x3A2C) }
      H.log(string.format("[ultros4] Ultros's AI queued cmd $%02X f%d while Broken",
        H.readByte(0x3A2C), H.frame))
    end, emu.callbackType.exec, atk, atk)
  end),
  H.driveUntil(function() return cross ~= nil end, 20000, { driver() },
    "a hit takes Ultros IV under " .. LINE .. " HP"),
  H.call(function()
    H.assertEq(cross.brk > 0, true, "the hit that took Ultros IV under " ..
      LINE .. " HP landed while he was Broken (brk=" .. cross.brk ..
      ", shields=" .. cross.sh .. " at f" .. cross.f .. ")")
  end),
  H.driveUntil(function() return firstStory("entry", 0x00, cross.f) ~= nil end,
    ON_CUE, { driver() },
    "Chupon's entry (restore_monsters) runs on cue while Ultros IV is Broken"),
  H.call(function()
    local d53 = firstStory("dlg", 0x53, cross.f)
    local e = firstStory("entry", 0x00, cross.f)
    H.log(string.format("[ultros4] under the line f%d (brk=%d); dlg $53 f%s; " ..
      "restore_monsters f%d (brk=%d, counter=%d), %d frames after the hit",
      cross.f, cross.brk, d53 and tostring(d53.f) or "-", e.f, e.brk,
      e.counter, e.f - cross.f))
    H.assertEq(d53 ~= nil and d53.brk > 0, true, "dlg $53 (\"Mr. Chupon! " ..
      "Come on down!\") ran while Ultros IV was Broken")
    H.assertEq(e.brk > 0, true, "restore_monsters (Chupon) ran while Ultros " ..
      "IV was Broken")
    H.assertEq(e.counter, 1, "and from his counter")
    -- a dying monster's counter always ran in full, so on main's ROM the
    -- entry came only as Ultros died (hp 0, still Broken, 1220 frames
    -- after the hit): the story must come from the living, Broken Ultros
    H.assertEq(e.hp > 0, true, "Chupon entered while Ultros IV was alive " ..
      "(hp " .. e.hp .. "), not as his dying counter")
    H.screenshot("ultros4_chupon")
  end),
  (function()
    local n = 0
    return H.driveUntil(function() n = n + 1; return n > 1800 end, 1900,
      { driver() }, "the fight goes on for 1800 frames")
  end)(),
  H.call(function()
    local entries = 0
    for _, e in ipairs(story) do
      if e.op == "entry" and e.b2 == 0x00 then entries = entries + 1 end
    end
    H.assertEq(entries, 1, "Chupon entered once (set_monster_switch 1 ran " ..
      "after the entry, Broken or not)")
    local brokenTurn = 0
    for _, e in ipairs(story) do
      if e.counter == 0 and e.brk > 0 then brokenTurn = brokenTurn + 1 end
    end
    H.assertEq(#brokenAttacks + brokenTurn, 0, "while Broken, Ultros IV's AI " ..
      "queued no attack and ran no turn (" .. #brokenAttacks .. " attack(s), " ..
      brokenTurn .. " turn command(s)); only his counter's story ran")
    H.log("[ultros4] PASSED")
  end),
})
