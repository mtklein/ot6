-- @suite savestate=tunnelarmr_entry slow
-- battle_umaro.lua -- Umaro's kit (#380): a full dump is always Storm, his
-- divine, and Charge and Throw strike as bludgeoning.
--
-- THIS IS A SYNTHETIC MECHANISM TEST (docs/TESTING.md, "Synthetic mechanism
-- tests"): Umaro is World of Ruin content (Narshe, v0.29) and no route state
-- reaches him, so nothing here is a route, balance or play claim.  One party
-- member of a legitimately reached battle (battle 67, TunnelArmr, from
-- tunnelarmr_entry) is STAGED as Umaro the way battle_retaliate_umaro.lua
-- stages him: his character id ($3ED8) becomes UMARO at the battle's first
-- CheckPlayerAction pass (so his gauge auto-commands, as the real Umaro's
-- does), and once the battle is up he is Berserk (STATUS2 bit 4) with no
-- relic in either cell ($3CD0/$3CD1), so the vanilla roll can never pick
-- Storm (that needs the Blizzard Orb) and every Storm is the divine.
--
-- What is staged per turn, at his chooser (_163b) before its first
-- instruction: his pending boost ($3E9D) to the turn's entry of CYCLE
-- (3, 0, 2, 1, repeating), the
-- shape a provoked dump leaves it in (Ot6UmaroRetaliate, at that same
-- instruction, leaves a nonzero pending alone), and his bank to at least
-- that, so Ot6ActionEnd charges what is pending.  The dump's own trigger
-- (being hurt below his last turn's line) is battle_retaliate_umaro's; this
-- suite is about what three points buy at the roll.  Also staged, so the
-- fight lasts for the turns: TunnelArmr's HP put back to 30,000 under
-- 20,000, and either seat's HP put back to its max whenever it falls (on
-- main's ROM a seat put back only under half fell to one blow from above
-- it: build/attempts/wt/v028-kits/px13-lab/old/battle_umaro.out).  Everything else is the engine's: the
-- roll, the arm, the class, the damage.
--
-- Watched: the arm each turn rolls (the `jmp (UmaroAttackTbl,x)`), the
-- pending boost there, and OT6_ATKCLASS at each ExecAttack pass of a
-- Charge or Throw (Throw needs the Rage Ring, so here it is Charge; both
-- take the class at the chooser).  He takes turns until four at three
-- points, four under, and two Charges have resolved (at most MAX_TURNS;
-- Charge is about 96 in 255 of an unboosted relic-less roll, RandBitRateTbl
-- row 0).  Asserted:
--   1. every turn with three points pending rolls Storm (arm 1);
--   2. no turn with fewer rolls Storm (no Blizzard Orb: vanilla never can);
--   3. every Charge and Throw pass carries the bludgeoning class ($04).
-- Old-ROM red and mutants: build/attempts/wt/v028-kits/.
local H = dofile("tools/tests/lib/ot6.lua")
local ENTRY = "build/states/tunnelarmr_entry.mss.lua"

local CHAR_UMARO = 0x0D
local BERSERK = 0x10
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_DEF = 0x05, 0x27
local CMDTBL = 0x202E
local ATKCLASS = 0x57B8
local BLUDG = 0x04
local ARM = { [0] = "Throw", [1] = "Storm", [2] = "Charge", [3] = "Fight" }
local CYCLE = { 3, 0, 2, 1 }             -- the staged pending, turn by turn
local MAX_TURNS = 40

local function hp(e)     return H.readWord(0x3BF4 + e * 2) end
local function bp(e)     return H.readByte(0x3E9C + e * 2) end
local function pend(e)   return H.readByte(0x3E9D + e * 2) end
local function charOf(e) return H.readByte(0x3ED8 + e * 2) end

local SUBJ, staged = nil, false
local turns = {}                        -- one record per turn of his
local T = nil                           -- the open turn

local function installObservers()
  local sChooser, sTbl = H.sym("_163b"), H.sym("UmaroAttackTbl")
  local jmp = sTbl - 3
  H.assertEq(H.readRomByte(jmp & 0x3FFFFF), 0x7C, "UmaroAttackTbl is indexed by the `jmp (abs,x)` before it")
  local sExec, sCPA = H.sym("ExecAttack"), H.sym("CheckPlayerAction")
  local function yIsSubj() return SUBJ ~= nil and (emu.getState()["cpu.y"] & 0xFFFF) == SUBJ * 2 end

  emu.addMemoryCallback(function()
    if not yIsSubj() or (H.readByte(0xB1) & 0x01) ~= 0 then return end
    if #turns >= MAX_TURNS then return end
    local want = CYCLE[(#turns % #CYCLE) + 1]
    T = { f = H.frame, want = want, classes = {} }
    turns[#turns + 1] = T
    H.writeByte(0x3E9D + SUBJ * 2, want)
    if bp(SUBJ) < want then H.writeByte(0x3E9C + SUBJ * 2, want) end
  end, emu.callbackType.exec, sChooser, sChooser)

  emu.addMemoryCallback(function()
    if T == nil or T.arm ~= nil or not yIsSubj() then return end
    T.arm = (emu.getState()["cpu.x"] & 0xFFFF) // 2
    T.pendAtRoll = pend(SUBJ)
  end, emu.callbackType.exec, jmp, jmp)

  emu.addMemoryCallback(function()
    if T == nil or T.arm == nil or T.done then return end
    if (H.readByte(0xB1) & 0x01) ~= 0 then return end
    if T.arm == 0 or T.arm == 2 then T.classes[#T.classes + 1] = H.readByte(ATKCLASS) end
  end, emu.callbackType.exec, sExec, sExec)

  if UMARO_TRACE then
    emu.addMemoryCallback(function(_, v)
      if T == nil or T.done then return end
      local st = emu.getState()
      H.log(string.format("[trace] f%d $57B8 <- %02X at $%02X%04X (arm %s)", H.frame, v, st["cpu.k"], st["cpu.pc"],
        tostring(T.arm)))
    end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
  end
  local sAE = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if T == nil or T.arm == nil or T.done then return end
    if (emu.getState()["cpu.x"] & 0xFF) ~= SUBJ * 2 then return end
    T.done = true
    local cl = {}
    for _, c in ipairs(T.classes) do cl[#cl + 1] = string.format("%02X", c) end
    H.log(string.format("[umaro] f%d turn %d: pending %d staged, %d at the roll -> %s; class at its passes {%s}",
      T.f, #turns, T.want, T.pendAtRoll, ARM[T.arm] or "?", table.concat(cl, ",")))
  end, emu.callbackType.exec, sAE, sAE)

  -- the rename, at the battle's first CheckPlayerAction pass (see
  -- battle_retaliate_umaro.lua's note on why it must land there)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x >= 8 or staged or not H.battleLoadStarted() then return end
    local best = nil
    for e = 0, 3 do
      local fights = false
      for r = 0, 3 do
        if H.readByte(CMDTBL + e * 12 + r * 3) == 0x00 then fights = true end
      end
      if hp(e) > 0 and fights and best == nil then best = e end
    end
    SUBJ = best
    H.writeByte(0x3ED8 + SUBJ * 2, CHAR_UMARO)
    staged = true
    H.log(string.format("[stage] f%d e%d renamed to character $%02X at the first CheckPlayerAction pass",
      H.frame, SUBJ, charOf(SUBJ)))
  end, emu.callbackType.exec, sCPA, sCPA)
end

-- the other seat Defends (Right to the Def. window, A there)
local ph = 0
local function hands()
  ph = ph + 1
  if not H.battleLoadStarted() then H.setPad({}) return end
  if H.readByte(MENU) == 0 then H.setPad(ph % 8 < 4 and { a = true } or {}) return end
  local st, step = H.readByte(MSTATE), ph % 40
  if st == ST_DEF then H.setPad(ph % 10 < 5 and { a = true } or {})
  elseif st ~= ST_CMD then H.setPad(ph % 10 < 5 and { b = true } or {})
  elseif step < 4 then H.setPad({ right = true })
  elseif step >= 20 and step < 24 then H.setPad({ a = true })
  else H.setPad({}) end
end

local function keepStanding()
  if not H.battleActive() then return end
  for e = 0, 3 do
    local h, mx = hp(e), H.readWord(0x3C1C + e * 2)
    if h > 0 and mx > 0 and h < mx then H.writeWord(0x3BF4 + e * 2, mx) end
  end
  for m = 0, 5 do
    if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) < 20000 then
      H.writeWord(0x3BFC + m * 2, 30000)
    end
  end
end

local function tally()
  local full, other, charges = 0, 0, 0
  for _, t in ipairs(turns) do
    if t.done then
      if t.pendAtRoll == 3 then full = full + 1 else other = other + 1 end
      if t.arm == 2 then charges = charges + 1 end
    end
  end
  return full, other, charges
end

H.run({ maxFrames = 120000 }, {
  H.loadState(ENTRY),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.mapId() & 0x1FF, 70, "tunnelarmr_entry boots on map 70")
    installObservers()
  end),
  H.hold({ "down" }), H.waitFrames(12), H.release(), H.waitFrames(4),
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.call(function() H.setPad((H.frame % 8 < 4) and { a = true } or {}) end),
  }, "battle 67 loads"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(staged and SUBJ ~= nil and charOf(SUBJ) == CHAR_UMARO, true, "a seat is staged as Umaro")
    H.writeByte(0x3CD0 + SUBJ * 2, 0xFF)
    H.writeByte(0x3CD1 + SUBJ * 2, 0xFF)
    H.writeByte(0x3EE5 + SUBJ * 2, H.readByte(0x3EE5 + SUBJ * 2) | BERSERK)
    H.log(string.format("[stage] e%d: relics cleared, Berserk", SUBJ))
  end),
  H.driveUntil(function()
    local full, other, charges = tally()
    return (full >= 4 and other >= 4 and charges >= 2) or #turns >= MAX_TURNS
      or not H.battleLoadStarted()
  end, 150000, {
    H.call(function() keepStanding(); hands() end),
    H.waitFrames(1),
  }, "his turns"),
  H.call(function()
    H.setPad({})
    local fails, full, other, struck = {}, 0, 0, 0
    for i, t in ipairs(turns) do
      if t.done then
        if t.pendAtRoll == 3 then
          full = full + 1
          if t.arm ~= 1 then fails[#fails + 1] = string.format("turn %d: three points rolled %s, not Storm", i, ARM[t.arm]) end
        else
          other = other + 1
          if t.arm == 1 then fails[#fails + 1] = string.format("turn %d: %d point(s) rolled Storm", i, t.pendAtRoll) end
        end
        for _, c in ipairs(t.classes) do
          struck = struck + 1
          if c ~= BLUDG then
            fails[#fails + 1] = string.format("turn %d: %s carried class %02X, not bludgeoning", i, ARM[t.arm], c)
          end
        end
      end
    end
    H.log(string.format("[umaro] SUMMARY %d turns: %d at three points, %d under; %d Charge/Throw passes",
      #turns, full, other, struck))
    for _, m in ipairs(fails) do H.log("[umaro] FAIL " .. m) end
    H.assertEq(full >= 4 and other >= 4, true, "at least four turns at three points and four under")
    H.assertEq(struck >= 2, true, "at least two Charge passes were watched")
    H.assertEq(#fails, 0, "a full dump is Storm, and only a full dump; Charge and Throw bludgeon")
    H.log("[umaro] PASS")
  end),
})
