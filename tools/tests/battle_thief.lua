-- @suite
-- battle_thief.lua -- #55, Locke's kit, first slice: the THIEF SUBMENU behind
-- the Steal row, and the two merchant verbs in it.
--
-- WHY A SUBMENU BEHIND STEAL AND NOT A NEW COMMAND.  Locke's four command rows
-- are FIGHT, STEAL, MAGIC, ITEM (char_prop.asm:157).  The third row LOOKS blank
-- in game and is not: InitCmd_03 (battle_main.asm:14100) removes MAGIC at
-- runtime for a character who knows no spell and holds no esper -- the same
-- instruction #47 found doing it to Gau -- and the battle menu is still
-- hard-wired to four rows.  So there is no spare slot, and Steal (rung one of
-- kits.md's eight-rung ladder) becomes the ladder's first ROW instead:
-- OpenCmdMenuTbl[$05] opens the Tools-window shell with Steal / Filch / Bestow
-- in it, and the row the player picks rides into the queued action's ATTACK byte
-- ($2bb0 -> $3a7b -> $b6), a byte nothing under command $05 has ever used.
--
-- WHAT IS ASSERTED
--
--   1. THE SUBMENU OPENS.  Picking Steal reaches the tools-shell menu state
--      ($7bc2 == $30) with thief mode raised (w7e6168 == 3), not the target
--      cursor it used to reach.  Three rows are packed into wItemList's LEFT
--      column with their ids, their MP costs and their own targeting bytes, and
--      every other cell is $ff (empty, unselectable).
--   2. THE PRICES ARE THE CHARGED PRICES.  Steal 4 (Ot6StealCost -- #52's single
--      authority, and this is the first surface that has ever DRAWN it),
--      Filch 6, Bestow 5 (Ot6ThiefCostTbl).
--   3. THE ROWS DRAW THEIR NAMES.  "Steal", "Filch" and "Bestow" render in the
--      window out of the AttackName pad slots $56-$58, which is what makes the
--      row ids free.
--   4. BESTOW GREYS AT 0 BP and only at 0 BP -- the row's own reason, on top of
--      the MP one (Ot6BushidoRowGrey's thief arm).  Steal and Filch have no BP
--      precondition and stay white either way.
--   5. FILCH MOVES A SHIELD INTO A BOOST POINT.  kits.md designs Filch as "steal
--      1 BP from the target" and that is structurally impossible: OT6_BP_CLASS
--      ($3e9c) is a SPLIT table -- character rows hold BP, MONSTER rows hold the
--      species' authored class-weakness mask (ot6.asm's header; seeded by
--      Ot6SeedShields, ot6_break.asm:36/51) -- so an enemy has no BP to take.
--      Filch takes the resource it does have: one shield, CLASS-BLIND, and Locke
--      keeps it as a pip.  Asserted as a conservation law: target shields -1,
--      Locke's bank +2 (the filched pip plus Ot6ActionEnd's own unboosted
--      regen), and no damage dealt.
--   6. BESTOW MOVES A BOOST POINT BETWEEN ACTORS.  Ally +1; Locke's half is
--      debited by Ot6ActionEnd through the pending-boost byte, which is the only
--      BP charge path in the game, so a Bestow can never be free.
--   7. THE CAPS AND THE NO-REGEN RULE ARE RUNIC'S, UNCHANGED.  A Filch at 5 BP
--      still takes the shield and banks nothing; a Bestow to a capped ally is an
--      honest no-op that costs Locke nothing.
--
-- LOCKE IS INSTALLED BY POKE into the opening guard fight, the idiom
-- battle_blitzgrey uses for Sabin and battle_steal for Locke: every party slot
-- gets CHAR::LOCKE ($3ed8) and an all-Steal command list ($202e, stride 12).
-- The state itself is minted from a natural boot.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TOOLS = 0x30
local KITMODE = 0x6168                  -- w7e6168: 0 tools, 1 blitz, 2 bushido, 3 thief
local CMDTBL, CURMP = 0x202E, 0x3C08
local CMD_STEAL = 0x05
local CHAR_LOCKE = 0x01
local ILIST = 0x4005                    -- wItemList: Index +0, Qty +1, Flags +2
local BP = 0x3E9C                       -- OT6_BP_CLASS (character rows)
local SHIELD = 0x3E38                   -- OT6_SHIELD_CUR
local BROKEN = 0x3E88                   -- OT6_BROKEN_TICKS
local PEND = 0x3E9D                     -- OT6_BOOST_REVEALED (pending boost)
local TCURSOR = 0x7B7D                  -- w7e7b7d: the target cursor's CHARACTER mask
local WHITE, GREY = 0x21, 0x25
local PARTY = { 0, 1, 2 }
local MSLOTS = { 0, 1, 2, 3, 4, 5 }
local function ENT_C(s) return s * 2 end
local function ENT_M(s) return 8 + s * 2 end

local ID_STEAL, ID_FILCH, ID_BESTOW = 0x56, 0x57, 0x58
local COST_STEAL, COST_FILCH, COST_BESTOW = 4, 6, 5

-- FF6 battle-font glyphs (battle_blitzgrey's mapping).
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
local NM = {
  Steal  = glyphs("Steal"),
  Filch  = glyphs("Filch"),
  Bestow = glyphs("Bestow"),
}

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

-- pinned knobs, mutated between phases; pinLocke writes them every frame.
local mp = 99
local bp = 3                            -- Locke's bank (every party slot)

local function pinLocke()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, CHAR_LOCKE)
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, CMD_STEAL) end
    H.writeWord(0x3BF4 + s * 2, 999)                -- nobody dies mid-bench
    H.writeWord(CURMP + s * 2, mp)
  end
end

-- pin the bank too (a separate pin: the resolution phases must NOT have it
-- rewritten under them, or the whole point of the test is erased).
local function pinBank()
  for _, s in ipairs(PARTY) do H.writeByte(BP + ENT_C(s), bp) end
end

local function pinEnemies()
  for _, s in ipairs(MSLOTS) do
    H.writeWord(0x3BFC + s * 2, 0xF000)             -- never dies
    local st3 = 0x3EF8 + ENT_M(s)
    H.writeByte(st3, H.readByte(st3) | 0x10)        -- stopped: nobody acts but us
  end
end

-- the first present monster's entity offset
local function firstMonster()
  for _, s in ipairs(MSLOTS) do
    if H.readByte(0x3AA0 + ENT_M(s)) & 0x01 ~= 0 then return ENT_M(s) end
  end
  return nil
end

-- Shields and HP summed over the whole enemy side.  Which monster the target
-- cursor lands on is the game's choice; a SUM is what makes "exactly one shield
-- came off, from somebody" assertable without pinning the cursor.
local function shieldSum()
  local n = 0
  for _, s in ipairs(MSLOTS) do n = n + H.readByte(SHIELD + ENT_M(s)) end
  return n
end
local function monsterHpSum()
  local n = 0
  for _, s in ipairs(MSLOTS) do n = n + H.readWord(0x3BFC + s * 2) end
  return n
end

-- Stop every party slot but the one whose menu is open, so exactly one actor
-- acts per phase and every effect is attributable (battle_steal's discipline).
-- It must also UN-stop the actor: the next phase's actor is usually a slot the
-- PREVIOUS phase benched, and a stopped actor's queued action never executes
-- (measured -- the bestow phase hung 1500 frames on exactly that).
local function benchOthers()
  for _, s in ipairs(PARTY) do
    local st3 = 0x3EF8 + ENT_C(s)
    local v = H.readByte(st3)
    if s == H.vars.actor then v = v & 0xEF else v = v | 0x10 end
    H.writeByte(st3, v)
  end
end

local traceN = 0
local function trace(tag, extra)
  traceN = traceN + 1
  if traceN % 12 == 1 then
    H.log(string.format("%s: mstate $%02x menu $%02x %s", tag,
      H.readByte(MSTATE), H.readByte(MENU), extra()))
  end
  pinEnemies()
end
local function traceFilch()
  trace("filch-wait", function()
    return string.format("shieldsum %d bp %d", shieldSum(), H.readByte(BP + H.vars.ent))
  end)
end
-- Clear STOP on every party slot.  Phase 4 must NOT leave a benched character
-- holding a command window: the fixture runs in Wait mode, so an open menu
-- freezes the battle clock and the queued Bestow never reaches the top of the
-- queue (measured -- that is exactly how phase 4 hung, with the action created
-- and $2bae already cleared).
local function unbenchParty()
  for _, s in ipairs(PARTY) do
    local st3 = 0x3EF8 + ENT_C(s)
    H.writeByte(st3, H.readByte(st3) & 0xEF)
  end
end

-- Zero the shared list-cursor block ($895f scroll / $8963 col / $8967 row, four
-- slots each) -- what Config>Cursor "Reset" does at command-window open.  Used
-- while nudging a BYSTANDER's menu along so its thief list is guaranteed to be
-- sitting on row 0 (Steal) and the nudge can never fire a second Bestow.
local function zeroListCursor()
  for i = 0, 11 do H.writeByte(0x895F + i, 0) end
end

local function traceBestow()
  benchOthers()
  trace("bestow-wait", function()
    local q = {}
    for s = 0, 3 do
      q[#q + 1] = string.format("[%02x %02x %02x]", H.readByte(0x2BAE + s * 8),
        H.readByte(0x2BAF + s * 8), H.readByte(0x2BB0 + s * 8))
    end
    local st = {}
    for _, s in ipairs(PARTY) do
      st[#st + 1] = string.format("%02x", H.readByte(0x3EF8 + ENT_C(s)))
    end
    return string.format("locke %d ally %d atb %d actor %d t2f41 $%02x 7b80 $%02x 7bcb $%02x q%s st3 %s",
      H.readByte(BP + H.vars.ent), H.readByte(BP + H.vars.allyEnt),
      H.readWord(0x3218 + H.vars.ent), H.readByte(ACTOR), H.readByte(0x2F41),
      H.readByte(0x7B80), H.readByte(0x7BCB), table.concat(q), table.concat(st, ","))
  end)
end

local function row(i)                   -- left-column row i lives at cell i*2
  local o = ILIST + i * 6
  return H.readByte(o), H.readByte(o + 1), H.readByte(o + 2)
end

local function openThief()
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinLocke(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the thief submenu opens (tools-shell state $30)")
end

local function closeThief()
  return H.driveUntil(function() return H.readByte(MSTATE) ~= ST_TOOLS end, 300, {
    H.call(function() H.setPad({ "b" }) end), H.waitFrames(2),
    H.call(function() H.setPad({}) end), H.waitFrames(2),
  }, "the thief submenu closes back to the command window")
end

-- move the cursor down n rows inside the open list
local function cursorDown(n)
  local steps = {}
  for _ = 1, n do
    steps[#steps + 1] = H.call(function() H.setPad({ "down" }) end)
    steps[#steps + 1] = H.waitFrames(3)
    steps[#steps + 1] = H.call(function() H.setPad({}) end)
    steps[#steps + 1] = H.waitFrames(6)
  end
  return H.seqStep(steps)
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function() pinLocke(); pinEnemies(); pinBank() end), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    H.log(string.format("locke installed in slot %d; MP pinned %d, BP pinned %d",
      H.readByte(ACTOR), mp, bp))
  end),

  -- 1/2/3: the submenu opens, its rows are right, its names draw ------------
  openThief(),
  H.waitFrames(8),
  H.call(function() H.screenshot("thief_submenu") end),
  H.call(function()
    H.assertEq(H.readByte(KITMODE), 0x03,
      "thief mode raised (w7e6168 == 3) -- Steal opened a list, not the target cursor")
    local i0, q0, f0 = row(0)
    local i1, q1, f1 = row(1)
    local i2, q2, f2 = row(2)
    H.log(string.format("rows: [$%02x %d MP flags $%02x] [$%02x %d MP flags $%02x] [$%02x %d MP flags $%02x]",
      i0, q0, f0, i1, q1, f1, i2, q2, f2))
    H.assertEq(i0, ID_STEAL,  "row 0 is the Steal id ($56, an AttackName pad slot)")
    H.assertEq(i1, ID_FILCH,  "row 1 is the Filch id ($57)")
    H.assertEq(i2, ID_BESTOW, "row 2 is the Bestow id ($58)")
    H.assertEq(q0, COST_STEAL,
      "Steal draws 4 MP -- Ot6StealCost's number, VISIBLE for the first time (#52)")
    H.assertEq(q1, COST_FILCH,  "Filch draws 6 MP (Ot6ThiefCostTbl)")
    H.assertEq(q2, COST_BESTOW, "Bestow draws 5 MP (Ot6ThiefCostTbl)")
    H.assertEq(f0, 0x43, "Steal targets an enemy (MANUAL|ONE_SIDE|ENEMY)")
    H.assertEq(f1, 0x43, "Filch targets an enemy")
    H.assertEq(f2, 0x03, "Bestow targets the PARTY side (MANUAL|ONE_SIDE, no ENEMY)")
    -- the right column and the fourth row must be empty, so the window draws
    -- one clean column of three and nothing else is selectable.
    H.assertEq(H.readByte(ILIST + 3), 0xFF, "row 0 column 2 is empty ($ff)")
    H.assertEq(H.readByte(ILIST + 18), 0xFF, "row 3 is empty ($ff)")
    -- names, out of the pad slots
    H.assertEq(findName(NM.Steal) ~= nil, true, "the Steal row draws its name")
    H.assertEq(findName(NM.Filch) ~= nil, true, "the Filch row draws its name")
    H.assertEq(findName(NM.Bestow) ~= nil, true, "the Bestow row draws its name")
    H.log("PASSED phase 1: the submenu, its three priced rows, and their names")
  end),

  -- 4: Bestow greys at 0 BP, and only at 0 BP -------------------------------
  closeThief(),
  H.call(function() bp = 0; pinBank() end),
  H.waitFrames(4),
  openThief(),
  H.waitFrames(8),
  H.call(function() H.screenshot("thief_bestow_grey") end),
  H.call(function()
    local aS, aF, aB = attrOf(NM.Steal), attrOf(NM.Filch), attrOf(NM.Bestow)
    H.log(string.format("0 BP -> attr Steal=%s Filch=%s Bestow=%s",
      tostring(aS), tostring(aF), tostring(aB)))
    H.assertEq(aB, GREY,  "at 0 BP Bestow is grey -- there is no pip to hand over")
    H.assertEq(aS, WHITE, "Steal has no BP precondition: still white")
    H.assertEq(aF, WHITE, "Filch has no BP precondition: still white")
    H.assertEq(aB - aS, 0x04, "grey - white == $04, magic's own disabled-bit delta")
  end),
  closeThief(),
  H.call(function() bp = 2; pinBank() end),
  H.waitFrames(4),
  openThief(),
  H.waitFrames(8),
  H.call(function()
    H.assertEq(attrOf(NM.Bestow), WHITE,
      "at 2 BP Bestow is white -- the grey tracks the bank, it is not unconditional")
    H.log("PASSED phase 2: Bestow's grey is its own BP reason and tracks the bank")
  end),

  -- 5: FILCH -- one shield off the target, one pip into Locke ----------------
  --
  -- Which monster the cursor lands on is the game's choice, not ours, so the
  -- chip is asserted as a SUM over every present monster: every one of them is
  -- given the same shield count and the total must fall by exactly one.  That
  -- also catches a Filch that chipped the wrong target or chipped twice, which
  -- a single-slot read would not.
  closeThief(),
  H.call(function()
    H.vars.actor = H.readByte(ACTOR) & 0x03
    H.vars.ent = ENT_C(H.vars.actor)
    benchOthers()
    for _, s in ipairs(MSLOTS) do
      H.writeByte(SHIELD + ENT_M(s), 4)         -- shields to lose
      H.writeByte(BROKEN + ENT_M(s), 0)         -- and definitely not broken
    end
    H.writeByte(BP + H.vars.ent, 0)             -- empty bank, so +2 is exact
    H.writeByte(PEND + H.vars.ent, 0)           -- and no boost armed by L/R
    H.vars.sh0 = shieldSum()
    H.vars.hp0 = monsterHpSum()
    H.log(string.format("filch: actor slot %d (entity $%02x), bp %d, shield sum %d",
      H.vars.actor, H.vars.ent, H.readByte(BP + H.vars.ent), H.vars.sh0))
  end),
  H.waitFrames(4),
  openThief(),
  H.waitFrames(8),
  cursorDown(1),                                -- row 1 = Filch
  H.call(function() H.setPad({ "a" }) end), H.waitFrames(3),
  H.call(function() H.setPad({}) end), H.waitFrames(14),
  H.call(function()
    H.log(string.format("after row confirm: mstate $%02x", H.readByte(MSTATE)))
  end),
  H.call(function() H.setPad({ "a" }) end), H.waitFrames(3),
  H.call(function() H.setPad({}) end),
  -- let the action resolve.  Nothing re-pins the bank or the shields from here.
  H.driveUntil(function() return shieldSum() == H.vars.sh0 - 1 end, 1500,
    { H.call(traceFilch), H.waitFrames(4) },
    "the filch lands: exactly one shield comes off the enemy side"),
  H.waitFrames(180),                            -- past the actor's own ActionEnd
  H.call(function()
    local sh, b = shieldSum(), H.readByte(BP + H.vars.ent)
    H.log(string.format("after filch: shield sum %d (was %d), locke bp %d (was 0)",
      sh, H.vars.sh0, b))
    H.assertEq(sh, H.vars.sh0 - 1, "exactly ONE shield came off -- Filch is a single chip")
    H.assertEq(b, 2,
      "Locke banked 2: the filched pip + Ot6ActionEnd's unboosted regen -- the "
      .. "only way in the game to gain two in a turn")
    H.assertEq(monsterHpSum(), H.vars.hp0,
      "Filch deals no damage: enemy HP is untouched")
    H.log("PASSED phase 3: Filch moves a shield into a boost point")
  end),

  -- 6: BESTOW -- a pip from Locke to an ally --------------------------------
  --
  -- FLUSH FIRST.  By now a second party slot is holding an open command window,
  -- and this fixture runs in Wait mode: that window freezes the battle clock, so
  -- a Bestow queued underneath it never reaches the top of the queue (measured:
  -- 1500 frames, $62ca == 0, $2bae already cleared, the ATB byte frozen).
  -- Benching the slot does NOT close a window that is already open.  So every
  -- pending menu is walked out first -- A pulses with the list cursor reset to
  -- row 0, which makes each bystander Steal and hand the clock back -- and only
  -- THEN is the phase set up.  Row 0 is Steal, so the flush can never itself move
  -- a boost point.  Once the actor is chosen and the others are benched their
  -- gauges stall, no new window can open behind us, and the measurement runs
  -- against a quiet battle the way phase 3's did.
  H.driveUntil(function() return H.readByte(MENU) == 0 end, 3000, {
    H.call(function() pinLocke(); pinEnemies(); zeroListCursor(); H.setPad({ "a" }) end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(9),
  }, "every pending command window is walked out (the clock is ours again)"),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(function() pinLocke(); pinEnemies() end), H.waitFrames(2),
  }, "a fresh battle menu opens"),
  H.call(function()
    H.vars.actor = H.readByte(ACTOR) & 0x03
    H.vars.ally = (H.vars.actor + 1) % 3
    H.vars.ent = ENT_C(H.vars.actor)
    H.vars.allyEnt = ENT_C(H.vars.ally)
    benchOthers()
    H.writeByte(BP + H.vars.ent, 3)             -- Locke holds three
    H.writeByte(BP + H.vars.allyEnt, 0)         -- the ally holds none
    H.writeByte(PEND + H.vars.ent, 0)           -- no boost armed by L/R
    H.log(string.format("bestow: actor slot %d bp 3 -> ally slot %d bp 0",
      H.vars.actor, H.vars.ally))
  end),
  openThief(),
  H.waitFrames(8),
  cursorDown(2),                                -- row 2 = Bestow
  H.call(function() H.setPad({ "a" }) end), H.waitFrames(3),
  H.call(function() H.setPad({}) end), H.waitFrames(14),
  H.call(function()
    H.log(string.format("after bestow row confirm: mstate $%02x tcursor $%02x a84 $%02x a85 $%02x",
      H.readByte(MSTATE), H.readByte(TCURSOR), H.readByte(0x7A84), H.readByte(0x7A85)))
  end),
  -- The cursor opens on the PARTY side (row flags $03).  Walk it until the
  -- chosen mask is the ally's bit -- driven, not counted, so a different
  -- starting slot cannot silently target the wrong ally.
  H.driveUntil(function()
    return H.readByte(TCURSOR) == (1 << H.vars.ally)
  end, 400, {
    H.call(function() H.setPad({ "down" }) end), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "the target cursor reaches the ally"),
  H.call(function()
    H.log(string.format("target cursor mask $%02x (ally bit $%02x)",
      H.readByte(TCURSOR), 1 << H.vars.ally))
  end),
  H.call(function() H.setPad({ "a" }) end), H.waitFrames(3),
  H.call(function() H.setPad({}) end),
  -- The others are benched and no window is open behind us, so the clock runs
  -- on its own and nothing but this Bestow can touch either bank.
  H.driveUntil(function()
    return H.readByte(BP + H.vars.allyEnt) >= 1
  end, 1500, { H.call(traceBestow), H.waitFrames(4) },
     "the bestow lands: the ally's bank goes up"),
  H.waitFrames(180),                            -- past Locke's own ActionEnd
  H.call(function()
    local a = H.readByte(BP + H.vars.ent)
    local t = H.readByte(BP + H.vars.allyEnt)
    H.log(string.format("after bestow: locke bp %d (was 3), ally bp %d (was 0)", a, t))
    H.assertEq(t, 1, "the ally banked exactly one pip")
    H.assertEq(a, 2,
      "Locke is down to 2: Ot6ActionEnd charged the pending 1 AND skipped his "
      .. "regen, so the transfer is not free")
    H.log("PASSED phase 4: Bestow moves a boost point from Locke to an ally")
  end),
})
