-- @suite slow savestate=figaro_cleared
-- battle_thief.lua -- #55, Locke's kit, first slice: the thief submenu behind
-- the Steal row, and the two merchant verbs in it.
--
-- Why a submenu behind Steal rather than a new command: Locke's four command
-- rows are FIGHT, STEAL, MAGIC, ITEM (char_prop.asm:157); InitCmd_03 removes
-- MAGIC at runtime for a spell-less Locke, the battle menu is still hard-wired
-- to four rows, so Steal becomes the kit ladder's first row: OpenCmdMenuTbl[$05]
-- opens the Tools-window shell with Steal, Filch and Bestow in it, and the row
-- rides the queued action's attack byte ($2bb0 -> $3a7b -> $b6).
--
-- Issue #75 conversion.  The old apparatus installed LOCKE into all three
-- magitek slots, forged all-Steal command lists, pinned MP, HP and the bank
-- every frame, stopped the enemies, wrote sentinel shield counts, and zeroed
-- the shared cursor block.  On figaro_cleared the whole cast is real: LOCKE
-- carries the real submenu, the desert species seed their own shields
-- (Ot6SeedShields gives each 2, and three monsters sum to 6, enough for both
-- Filch arms), and every bank number below is earned and counted, so the
-- whole test is one deterministic ledger:
--
--   open 1 bp -> [white Bestow @1] -> R+Steal spends it (0, regen skipped)
--   -> [grey Bestow @0] -> one Tonic turn (+1) -> [white again] -> Filch
--   (+2: pip+regen -> 3) -> Bestow to the never-acted ally (3-1=2; ally
--   1+1=2) -> three item turns (5 = the Ot6ActionEnd cap, asserted by a
--   FOURTH item turn that must bank nothing) -> Filch at cap (shield off,
--   banks nothing) -> ally banked to cap by her own item turns -> Bestow
--   to the capped ally (a genuine no-op costing Locke nothing).
--
-- Every original assertion survives:
--   1. the submenu opens: tools-shell state $30, thief mode w7e6168 == 3,
--      three rows packed in the left column with ids, costs and targeting,
--      and the rest $ff.
--   2. the prices are the charged prices: Steal 4 (Ot6StealCost, #52),
--      Filch 6, Bestow 5 (Ot6ThiefCostTbl).
--   3. the rows draw their names from AttackName pad slots $56-$58.
--   4. Bestow greys at 0 BP and only at 0 BP (Ot6BushidoRowGrey's thief
--      arm); Steal and Filch stay white either way.
--   5. Filch moves a shield into a boost point: shield sum -1, bank +2
--      (pip plus regen), and no damage.
--   6. Bestow moves a pip between actors: ally +1, and Locke is charged
--      through the pending byte with regen skipped, so it is never free.
--   7. the caps and the no-regen rule: Filch at 5 still chips and banks
--      nothing; Bestow to a capped ally is a no-op costing Locke nothing.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_THIEF, ST_ITEM, ST_TGT, ST_TRANS = 0x05, 0x30, 0x0A, 0x38, 0x01
local CMD_STEAL, CMD_ITEM = 0x05, 0x01
local KITMODE = 0x6168                  -- w7e6168: 0 tools, 1 blitz, 2 bushido, 3 thief
local ILIST = 0x4005                    -- wItemList: Index +0, Qty +1, Flags +2
local BP = 0x3E9C                       -- OT6_BP_CLASS (character rows)
local SHIELD = 0x3E38                   -- OT6_SHIELD_CUR
local PEND = 0x3E9D
local TCURSOR = 0x7B7D                  -- target cursor's CHARACTER mask
local KCOL, KROW = 0x8963, 0x8967       -- the kit list's own cursor (read!)
local WHITE, GREY = 0x21, 0x25
local NONE = 0xFF
local TONIC, POTION = 0xE8, 0xE9
local function ENT_C(s) return s * 2 end
local function ENT_M(s) return 8 + s * 2 end

local ID_STEAL, ID_FILCH, ID_BESTOW = 0x56, 0x57, 0x58
local COST_STEAL, COST_FILCH, COST_BESTOW = 4, 6, 5

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

local locke, ally
local function bp(slot) return H.readByte(BP + ENT_C(slot)) end
local function mp() return H.readWord(0x3C08 + locke*2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end
local function shieldSum()
  local n = 0
  for s = 0, 5 do n = n + H.readByte(SHIELD + ENT_M(s)) end
  return n
end
local function monsterHpSum()
  local n = 0
  for s = 0, 5 do n = n + H.readWord(0x3BFC + s * 2) end
  return n
end
local function row(i)
  local o = ILIST + i * 6
  return H.readByte(o), H.readByte(o + 1), H.readByte(o + 2)
end

-- ------------------------------------------------------ the menu drive --
-- One driver, selected by mode.  Modes:
--   "defer"      -- this slot X-defers (never acts)
--   "item"       -- one item turn (Tonic/Potion, default target)
--   "kit:<row>"  -- open the thief submenu, pick row, confirm target
--   "boostkit:<row>" -- R once first (pending 1), then kit row
--   "park"       -- open the thief submenu and stop there (for the reads)
local mf = 0
local modeOf = {}                        -- slot -> mode
local target = nil                       -- character-target slot for Bestow
-- blink-proof latch and steer of the character-target mask (measured in
-- battle_steal and moved into the library as H.targetCursor; the character
-- column walks {down,up,left,right})
local tc = H.targetCursor({ mask = TCURSOR,
                            dirs = { "down", "up", "left", "right" } })
local function decide()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local mode = modeOf[act] or "defer"
  local slow = (st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if mode == "defer" then
    btn = (st == ST_CMD) and "x" or "b"
  elseif mode == "item" then
    if st == ST_CMD then
      local want = cmdRowOf(act, CMD_ITEM)
      local cur = H.readByte(CMDROW + act) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then error("bank ran out of items", 0) end
      local cur = H.readByte(0x8947 + act) + H.readByte(0x894F + act)
      if cur < want then btn = "down"
      elseif cur > want then btn = "up"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  else
    local kitRow = tonumber(mode:match(":(%d)"))
    local boost = mode:sub(1, 5) == "boost"
    local park = mode == "park"
    if st == ST_CMD then
      if boost and H.readByte(PEND + ENT_C(act)) < 1 then btn = "r"
      else
        local want = cmdRowOf(act, CMD_STEAL)
        local cur = H.readByte(CMDROW + act) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      end
    elseif st == ST_THIEF then
      if park then btn = nil                  -- sit still for the reads
      else
        local cur = H.readByte(KCOL + act) + H.readByte(KROW + act) * 2
        -- the kit list is one left column: cursor row is KROW, col 0
        local curRow = H.readByte(KROW + act)
        if H.readByte(KCOL + act) ~= 0 then btn = "left"
        elseif curRow < kitRow then btn = "down"
        elseif curRow > kitRow then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then
      btn = tc.steer(target, mf)
    else btn = "b" end
  end
  return btn and { [btn] = true } or {}
end

-- run the driver until pred; modes are set by the caller
local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(function() H.setPad(decide()) end),
  }, tag)
end
-- wait for LOCKE's window in "park" mode at the submenu.  (locke is nil
-- at step-construction time, so the steps must read it at run time.)
local function parkAtSubmenu(_, tag)
  return H.repeatN(1, {
    H.call(function() modeOf[locke] = "park" end),
    driveTo(function()
      return (H.readByte(ACTOR) & 3) == locke and H.readByte(MSTATE) == ST_THIEF
    end, 20000, tag),
    H.call(function() H.setPad({}) end),
    H.waitFrames(20),
  })
end

H.run({ maxFrames = 120000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.hold({ "b" }),
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1) }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),
  H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
    H.call(function()
      if not H.worldMode() or not H.worldHasControl() then H.setPad({}); return end
      H.setPad(((H.frame // 120) % 2 == 0) and { left = true } or { right = true })
    end),
  }, "desert encounter"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(90),
  H.call(function()
    for slot = 0, 3 do
      local id = H.readByte(0x3ED8 + slot*2)
      if id == 0x01 then locke = slot end
      if id == 0x00 then ally = slot end          -- TERRA, the ledger's ally
    end
    H.assertEq(locke ~= nil, true, "LOCKE is really in this party")
    H.assertEq(ally ~= nil, true, "TERRA (the ally) is really in this party")
    H.assertEq(bp(locke), 1, "Locke opens with Ot6InitBP's 1")
    H.assertEq(bp(ally), 1, "so does the ally (her ledger starts here)")
    H.vars.sh0 = shieldSum()
    H.assertEq(H.vars.sh0 >= 2, true,
      "the species seeded real shields (Ot6SeedShields) -- enough to filch")
    H.log(string.format("locke slot %d (mp %d), ally slot %d, shield sum %d",
      locke, mp(), ally, H.vars.sh0))
  end),

  -- 1/2/3: the submenu opens on the real kit; rows, prices, names ----------
  parkAtSubmenu(locke, "his real thief submenu opens"),
  H.call(function() H.screenshot("thief_submenu") end),
  H.call(function()
    H.assertEq(H.readByte(KITMODE), 0x03,
      "thief mode raised (w7e6168 == 3) -- Steal opened a list, not the target cursor")
    local i0, q0, f0 = row(0)
    local i1, q1, f1 = row(1)
    local i2, q2, f2 = row(2)
    H.log(string.format("rows: [$%02x %d MP $%02x] [$%02x %d MP $%02x] [$%02x %d MP $%02x]",
      i0, q0, f0, i1, q1, f1, i2, q2, f2))
    H.assertEq(i0, ID_STEAL,  "row 0 is the Steal id ($56, an AttackName pad slot)")
    H.assertEq(i1, ID_FILCH,  "row 1 is the Filch id ($57)")
    H.assertEq(i2, ID_BESTOW, "row 2 is the Bestow id ($58)")
    H.assertEq(q0, COST_STEAL,
      "Steal draws 4 MP -- Ot6StealCost's number, VISIBLE (#52)")
    H.assertEq(q1, COST_FILCH,  "Filch draws 6 MP (Ot6ThiefCostTbl)")
    H.assertEq(q2, COST_BESTOW, "Bestow draws 5 MP (Ot6ThiefCostTbl)")
    H.assertEq(f0, 0x43, "Steal targets an enemy (MANUAL|ONE_SIDE|ENEMY)")
    H.assertEq(f1, 0x43, "Filch targets an enemy")
    H.assertEq(f2, 0x03, "Bestow targets the PARTY side (MANUAL|ONE_SIDE)")
    H.assertEq(H.readByte(ILIST + 3), 0xFF, "row 0 column 2 is empty ($ff)")
    H.assertEq(H.readByte(ILIST + 18), 0xFF, "row 3 is empty ($ff)")
    H.assertEq(findName(NM.Steal) ~= nil, true, "the Steal row draws its name")
    H.assertEq(findName(NM.Filch) ~= nil, true, "the Filch row draws its name")
    H.assertEq(findName(NM.Bestow) ~= nil, true, "the Bestow row draws its name")
    -- 4a, the free half: at his real 1-bp bank Bestow is white
    H.assertEq(attrOf(NM.Bestow), WHITE,
      "at 1 real bp Bestow is white -- the grey is not unconditional")
    H.log("PASSED phase 1: the submenu, its three priced rows, their names")
  end),

  -- 4: Bestow greys at 0 BP; the bank is spent there rather than written ---
  H.call(function() modeOf[locke] = "boostkit:0" end),   -- R + Steal: 1-1=0
  driveTo(function() return bp(locke) == 0 end, 20000,
    "a boosted Steal spends the bank to 0 (regen skipped)"),
  parkAtSubmenu(locke, "his next window's submenu, at a 0 bank"),
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
  H.call(function() modeOf[locke] = "item" end),         -- +1: bank 1
  driveTo(function() return bp(locke) == 1 end, 20000,
    "one real item turn banks the pip back"),
  parkAtSubmenu(locke, "and the submenu again, at 1"),
  H.call(function()
    H.assertEq(attrOf(NM.Bestow), WHITE,
      "at 1 BP Bestow is white -- the grey tracks the bank, it is not unconditional")
    H.log("PASSED phase 2: Bestow's grey is its own BP reason and tracks the bank")
  end),

  -- 5: Filch takes one shield off the target and puts one pip into Locke ----
  -- Which monster the cursor lands on is the game's choice; the chip is a
  -- sum over the enemy side, which also catches a double chip.
  H.call(function()
    H.vars.shA = shieldSum()
    H.vars.hpA = monsterHpSum()
    H.vars.bA = bp(locke)
    H.assertEq(H.vars.bA, 1, "the ledger: bank reads 1 before the filch")
    modeOf[locke] = "kit:1"
  end),
  driveTo(function() return shieldSum() == H.vars.shA - 1 end, 20000,
    "the filch lands: exactly one shield comes off the enemy side"),
  H.call(function() modeOf[locke] = "defer" end),
  H.waitFrames(180),                            -- past the actor's own ActionEnd
  H.call(function()
    local sh, b = shieldSum(), bp(locke)
    H.log(string.format("after filch: shield sum %d (was %d), locke bp %d (was %d)",
      sh, H.vars.shA, b, H.vars.bA))
    H.assertEq(sh, H.vars.shA - 1, "exactly ONE shield came off -- Filch is a single chip")
    H.assertEq(b, H.vars.bA + 2,
      "Locke banked 2: the filched pip + Ot6ActionEnd's unboosted regen -- the "
      .. "only way in the game to gain two in a turn")
    H.assertEq(monsterHpSum(), H.vars.hpA,
      "Filch deals no damage: enemy HP is untouched")
    H.log("PASSED phase 3: Filch moves a shield into a boost point")
  end),

  -- 6: Bestow moves a pip from Locke to the never-acted ally ---------------
  H.call(function()
    H.assertEq(bp(locke), 3, "the ledger: Locke holds 3 (1+2)")
    H.assertEq(bp(ally), 1,
      "the ledger: the deferred ally still holds her opening 1")
    target = ally
    modeOf[locke] = "kit:2"
  end),
  driveTo(function() return bp(ally) >= 2 end, 20000,
    "the bestow lands: the ally's bank goes up"),
  H.call(function() modeOf[locke] = "defer"; target = nil end),
  H.waitFrames(180),                            -- past Locke's own ActionEnd
  H.call(function()
    local a, t = bp(locke), bp(ally)
    H.log(string.format("after bestow: locke bp %d (was 3), ally bp %d (was 1)", a, t))
    H.assertEq(t, 2, "the ally banked exactly one pip")
    H.assertEq(a, 2,
      "Locke is down to 2: Ot6ActionEnd charged the pending 1 AND skipped his "
      .. "regen, so the transfer is not free")
    H.log("PASSED phase 4: Bestow moves a boost point from Locke to an ally")
  end),

  -- 7: the caps.  Bank both actors to Ot6ActionEnd's cap of 5, interleaved,
  -- using non-damaging Steal for Locke and item turns for the ally.  A
  -- deferred ally who waits her turn out
  -- for another 30k frames dies to the desert chip damage (measured: the
  -- serial version timed out on her bank), while item turns heal.
  -- Then a fourth Locke turn must bank nothing, which is the cap, asserted;
  -- Filch at cap chips but banks nothing; and a Bestow to the capped
  -- ally is a no-op.
  H.call(function() modeOf[locke] = "kit:0"; modeOf[ally] = "item" end),
  driveTo(function() return bp(locke) == 5 and bp(ally) == 5 end, 60000,
    "interleaved item turns walk both banks to the cap"),
  H.call(function() modeOf[ally] = "defer" end),
  (function()
    local turns0
    return H.repeatN(1, {
      H.call(function() H.vars.mpCap = mp() end),
      -- one MORE item turn: the bank must stay 5.  Locke's three Steal
      -- banks above preserve enough of the fixture's real bag for this
      -- positive control.
      H.call(function()
        modeOf[locke] = "item"
        local i = bagIdxOf({TONIC, POTION})
        turns0 = i and H.readByte(0x2686 + i*5 + 3) or -1
      end),
      driveTo(function()
        local i = bagIdxOf({TONIC, POTION})
        return i ~= nil and H.readByte(0x2686 + i*5 + 3) ~= turns0
      end, 20000, "an item turn at the cap"),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(bp(locke), 5,
          "the cap: a regen at 5 banks nothing (Ot6ActionEnd's clamp)")
      end),
    })
  end)(),
  H.call(function()
    H.vars.shB = shieldSum()
    modeOf[locke] = "kit:1"
  end),
  driveTo(function() return shieldSum() == H.vars.shB - 1 end, 20000,
    "a filch at the cap still chips"),
  H.call(function() modeOf[locke] = "defer" end),
  H.waitFrames(180),
  H.call(function()
    H.assertEq(bp(locke), 5,
      "a Filch at 5 BP still takes the shield and banks NOTHING (the cap)")
    H.assertEq(bp(ally), 5, "ally at the cap (banked by her own real turns)")
    target = ally
    modeOf[locke] = "kit:2"
    H.vars.bC = bp(locke)
  end),
  -- the no-op bestow: nothing observable moves, so drive on the QUEUE
  -- becoming visible and then settle
  (function()
    local sawQ = false
    return H.repeatN(1, {
      H.call(function()
        emu.addMemoryCallback(function()
          sawQ = true
        end, emu.callbackType.write, 0x7E2BB0 + locke*8, 0x7E2BB0 + locke*8)
      end),
      driveTo(function() return sawQ end, 20000, "the capped bestow is queued"),
      H.call(function() modeOf[locke] = "defer"; target = nil end),
      H.waitFrames(400),
    })
  end)(),
  H.call(function()
    H.log(string.format("capped bestow: locke bp %d (was %d), ally bp %d",
      bp(locke), H.vars.bC, bp(ally)))
    H.assertEq(bp(ally), 5, "a Bestow to a capped ally leaves her at the cap")
    H.assertEq(bp(locke), H.vars.bC,
      "...and is a no-op that costs Locke nothing")
    H.log("PASSED phase 5: the caps and the no-regen rule are Runic's, unchanged")
    H.screenshot("thief_done")
  end),
})
