-- @suite slow
-- battle_ragedriver.lua -- the fight driver's Rage line for GAU (#269;
-- Driver:rageLine, kit-gau.md).
--
-- Played: Continue the wor-veldt-cave-v1 battery (the play's save on the
-- Veldt cave's save point, GAU seated with TERRA, CELES and RELM: nothing
-- here writes it), pace two tiles beside the save point into the cave's
-- random battles, and let the real driver fight each one.  Whatever the
-- cave deals (Toe Cutters, Rhyos), the first battle in which the driver
-- plans GAU's Rage and Cmd_10 then runs for his seat twice (the start and
-- a possessed turn: every possessed turn goes through Cmd_10 again) is the
-- one measured; the asserts read the engine:
--   1. the possession is the planned beast: Cmd_10 ran for GAU's seat and
--      $33A8 (his seat's beast) holds the rage the plan named, the one the
--      d-pad steer went to in the live list ($257E);
--   2. the price: GAU's MP (his record, $1600 + 37 * 11 + $0D) after the
--      battle is his MP before it less 8, over the start and at least one
--      possessed turn: 8 once, nothing a turn (read over a battle GAU does not level up in: a
--      level-up raises his MP at the battle's end);
--   3. the tier: OT6_RAGETIER holds the plan's boost (Cmd_10
--      stores the pending pips, capped 3), so the coin the plan bought is
--      the coin the trance rolls;
-- The plan's absorb veto is logged at the plan (the "[rage] plan read"
-- line), not asserted: the cave's randoms absorb ice, and no rage GAU
-- carries is ice, so no draw here could make it fail.  The play shows it
-- (route-wor-gau.md section 5: Were-Rat's Poison scored -1 against the
-- monster chest's Allo Ver, which drinks poison).
-- Then the control: RAGE_OFF set, the next battle is fought with no Cmd_10
-- for GAU at all.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local GAU = 0x0B
local RAGETIER = nil                  -- OT6_RAGETIER (ot6_memory.inc), read from the symbols
-- The battle's length is staged by play: until GAU's possessed turn is seen, the others Defend (the driver's
-- opts.hold), so the party does not end the fight before his second turn (on the #328 line at f51cf3ac the party
-- ended 15 of 16 cave battles at one Cmd_10: "no Rage planned and possessed past its start within 16 cave
-- battles").  The budget is the cave pool's (BUDGET, set at the start from the ROM's decoded odds): the battles
-- within which every formation the map deals comes up at least once, at 99%, so the measure meets whatever the
-- cave holds rather than one draw's luck.
local BUDGET = nil
local A, B = { 57, 45 }, { 58, 45 }
local cur = nil
local FIGHT = { rage = true }      -- the line is opt-in (Driver:rageLine)
-- the others Defend until GAU's possessed turn is seen in this battle (the staging above); the control sets
-- RAGE_OFF and so never holds
FIGHT.hold = function(id) return id ~= GAU and not RAGE_OFF and cur ~= nil and cur.cmd10 < 2 end

local function gauSlot()
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == GAU then return s end end
  return nil
end
local function raging(s) return (H.readByte(0x3EF9 + s * 2) & 0x01) ~= 0 end
local function recMp() return H.readWord(0x1600 + 37 * GAU + 0x0D) end
local function batMp(s) return H.readWord(0x3C08 + s * 2) end
local function recLevel() return H.readByte(0x1600 + 37 * GAU + 8) end
-- a battle GAU levels up in is not a price reading: the level-up raises his MP with his max at the battle's end
-- (#524 landing at 9d0374c8: "record MP 323 -> 353" over a battle that took his max MP up, and the price assert read
-- "got 353 ($161), want 315 ($13B)").  So the price is read from his battle MP ($3C08 + seat * 2): at the battle's
-- open and at his possessed turn's Cmd_10, which a level-up at the battle's end cannot touch.

-- per battle: the Rage plans made in it, GAU's Cmd_10s (his seat in Y),
-- and the tier and beast the first frame his RAGE status reads set
done = nil
local nr0, n0 = 0, 0
local function fresh() return { cmd10 = 0, tier = nil, beast = nil, rage = nil } end
local inBattle = false

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-veldt-cave-v1"),
  H.call(function()
    RAGETIER = H.sym("OT6_RAGETIER") & 0xFFFF
    H.assertEq(H.partyOfChar(GAU), 1, "GAU seated in wor-veldt-cave-v1 (the play's own save)")
    n0 = #H.outcomes
    -- the budget from the cave's pool (see BUDGET's note)
    local grp = H.fieldEncounterGroup(H.mapId())
    local pool = H.encounterPool(grp)
    local pmin = 1
    for slot = 1, 4 do local sl = pool[slot]; if sl and sl.odds and sl.odds > 0 then pmin = math.min(pmin, sl.odds / 256) end end
    BUDGET = math.ceil(math.log(0.01) / math.log(1 - pmin))
    H.log(string.format("[rage] the cave's group %d: the rarest slot %.3f; budget %d battles (every slot at 99%%)",
      grp, pmin, BUDGET))
    emu.addMemoryCallback(function()
      local s = gauSlot()
      if cur and s ~= nil and (emu.getState()["cpu.y"] & 0xFF) == s * 2 then
        cur.cmd10 = cur.cmd10 + 1
        if cur.cmd10 == 2 then cur.bmp2 = batMp(s) end   -- the possessed turn: the start's charge is in
      end
    end, emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))
  end),
  H.navTo(A[1], A[2], { maxFrames = 3000 }),
  H.driveUntil(function()
    local b = H.battleLoadStarted()
    -- the beast and the tier, the first frame GAU's RAGE status reads set
    -- (Cmd_10 writes both before it sets the bit)
    local gs = gauSlot()
    if b and inBattle and cur.tier == nil and gs ~= nil and raging(gs) then
      cur.tier, cur.beast = H.readByte(RAGETIER), H.readByte(0x33A8 + gs * 2)
    end
    if b and not inBattle then
      inBattle, cur, nr0 = true, fresh(), #H.rages
      cur.mp0, cur.lv0 = recMp(), recLevel()
    elseif not b and inBattle and H.hasControl() then
      inBattle = false
      cur.mp1, cur.lv1 = recMp(), recLevel()
      if #H.rages > nr0 then cur.rage = H.rages[nr0 + 1] end
      H.log(string.format("[rage] battle %d: rage plans %d; Cmd_10 %d; tier %s; beast %s; record MP %d -> %d; "
        .. "GAU L%d -> L%d", #H.outcomes - n0, #H.rages - nr0, cur.cmd10, tostring(cur.tier),
        cur.beast and string.format("$%02X", cur.beast) or "-", cur.mp0, cur.mp1, cur.lv0, cur.lv1))
      if cur.rage and cur.cmd10 >= 2 and done == nil then done = cur end
    end
    -- read the moment the plan is made (a log, not an assert): the chosen
    -- beast's special (MonsterRage +1) and its element, against every
    -- standing body
    if inBattle and cur.vetoFree == nil and #H.rages > nr0 then
      local r = H.rages[nr0 + 1]
      local atk = H.readRomByte((H.sym("MonsterRage") & 0x3FFFFF) + r.rage * 2 + 1)
      local elem = (atk == 0xEE or atk == 0xEF) and 0 or H.readRomByte((H.sym("MagicProp") & 0x3FFFFF) + atk * 14 + 1)
      cur.vetoFree = true
      for m = 0, 5 do
        local x = 8 + m * 2
        if H.monStanding(m) and elem ~= 0
           and ((H.readByte(0x3BCC + x) & elem) ~= 0 or (H.readByte(0x3BCD + x) & elem) == elem) then
          cur.vetoFree = false
        end
      end
      H.log(string.format("[rage] plan read: beast $%02X special $%02X element $%02X; absorbed or nulled by a standing "
        .. "body: %s", r.rage, atk, elem, tostring(not cur.vetoFree)))
    end
    if done then return not inBattle and H.hasControl() end
    if #H.outcomes - n0 > BUDGET then
      error(string.format("no Rage planned and possessed past its start within %d cave battles", BUDGET))
    end
    return false
  end, 800000, {
    H.navTo(B[1], B[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.navTo(A[1], A[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
  }, "cave battles until GAU's Rage is measured"),
  H.call(function()
    local r = done.rage
    H.log(string.format("[rage] measured: entry %d ($%02X) at %d BP, score %d, battle MP %d; Cmd_10 %d, "
      .. "tier %d, beast $%02X, record MP %d -> %d", r.entry, r.rage, r.boost, r.score, r.mp, done.cmd10,
      done.tier, done.beast, done.mp0, done.mp1))
    H.assertEq(done.cmd10 >= 2, true, "1. Cmd_10 ran for GAU's seat at the start and a possessed turn")
    H.assertEq(done.beast, r.rage, "1. GAU's seat possessed by the planned beast ($33A8)")
    H.log(string.format("[rage] battle MP at the plan %d, at the possessed turn %d", r.mp, done.bmp2))
    H.assertEq(done.bmp2, r.mp - 8, "2. 8 MP for the start and none for the possessed turn after it (battle MP)")
    H.assertEq(done.tier, math.min(r.boost, 3), "3. OT6_RAGETIER holds the plan's boost")
  end),
  -- the control: the same driver with the line off
  H.call(function()
    RAGE_OFF = true
    done, n0 = nil, #H.outcomes
  end),
  H.driveUntil(function()
    local b = H.battleLoadStarted()
    if b and not inBattle then
      inBattle, cur = true, fresh()
    elseif not b and inBattle and H.hasControl() then
      inBattle = false
      done = cur
      H.log(string.format("[rage] control battle: Cmd_10 for GAU %d", cur.cmd10))
    end
    return done ~= nil
  end, 400000, {
    H.navTo(B[1], B[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
    H.navTo(A[1], A[2], { maxFrames = 20000, playBattles = "tactical", fight = FIGHT }),
  }, "a control battle with RAGE_OFF"),
  H.call(function() H.assertEq(done.cmd10, 0, "control: with the line off GAU never Rages") end),
})
