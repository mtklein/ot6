-- @suite slow savestate=figaro_cleared
-- battle_stealmp.lua -- "every ability costs MP": Steal (cmd $05) joins the
-- cost gate.  A self-detecting A/B: it checks that the flat-cost path added
-- to Ot6AbilityCost (cmd $05 -> 4 MP, keyed on the command rather than an
-- id-table row) charges and refuses through the universal code, and stays
-- free on the OFF baseline.

--   * ON  (build/ot6.sfc, the suite default): a Steal is queued at cost 4
--     (Ot6AbilityCost's flat path), deducts 4 MP when it executes, and a caster
--     below that is refused AT THE MENU: since v0.19 the tools-shell confirm
--     asks Ot6KitConfirmMP whether the caster can pay the row it is about to
--     commit, and buzzes and stays open when they cannot, so a drained LOCKE
--     keeps his turn, his pips and his MP instead of spending the turn on a
--     steal that was always going to fizzle (mp-economy.md ruling 2).  The
--     universal insufficient-mp fizzle at CalcAttackEffect is still the
--     backstop for a pool that moves between the commit and the resolve --
--     battle_mpcost exercises that seam -- but it is no longer what a player
--     meets.
--     The 4 is flat at EVERY boost level, and both arms below are boosted so
--     that they say so.  #219 made boosting cost 2.5x per level; the owner
--     then exempted the three chance verbs (Steal, Rage, Slot), because a
--     boost on them multiplies nothing -- it converts variance into
--     reliability across a spread of outcomes that are not merely damage --
--     and the BP it costs is what pays for that certainty.  The rule is now
--     one test: a price escalates exactly when Ot6BoostDmg multiplies the
--     action, and cmd $05 is in Ot6BoostDmg's gate.  So the affordable arm
--     at boost 2 must be charged 4 and NOT 25, and the refusal arm at boost 3
--     must be priced 4 and NOT 63.
--   * OFF (ff6/rom/ff6-en-nomp.sfc, handed in via OT6_ROM): Ot6AbilityCost is
--     not assembled, so cmd $05 keeps vanilla's 0 and the identical Steal is
--     free, deducting 0 MP. The refusal half has nothing to refuse and is
--     skipped. This is the negative control.

-- The cost is read at the source, unchanged: a write watch on the mp-cost
-- queue ($3620,y, stored in CreateAction) filtered to command $05
-- captures what Ot6AbilityCost returned, 4 on ON and 0 on OFF,
-- and the MP delta then confirms the charge landed.  In the refusal arm the
-- same watch is read the other way round -- it must NOT fire, because the
-- menu refuses before an action is ever created -- so that arm waits on the
-- error buzz ($95) instead and asserts the price off the row's own stamp in
-- the submenu.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/figaro_cleared.mss.lua"

local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_THIEF, ST_ITEM, ST_TGT, ST_TRANS = 0x05, 0x30, 0x0A, 0x38, 0x01
local CMD_STEAL, CMD_ITEM = 0x05, 0x01
local ITEMLIST, THIEF_STEAL = 0x4005, 0x56   -- the thief submenu's row buffer
local NONE = 0xFF
local TONIC, POTION = 0xE8, 0xE9
local STEAL_COST = 4                     -- Ot6StealCost's immediate, flat

-- Steal's price at a given boost: the constant, because cmd $05 is exempt.
local function stealPrice(_) return STEAL_COST end

-- ...and what it WOULD cost if it were not, so the arms below can name the
-- number they are refusing rather than merely not mentioning it.  This is
-- #219's arithmetic, recomputed rather than copied: Ot6BoostPriceFor does
-- (base * 5^n + 2^(n-1)) >> n capped at 99, i.e.
-- min(99, floor(base * 2.5^n + 1/2)) -- 4 / 10 / 25 / 63.
local function escalated(boost)
  if boost == 0 then return STEAL_COST end
  local x = STEAL_COST
  for _ = 1, boost do x = x * 5 end
  return math.min(99, (x + (1 << (boost - 1))) >> boost)
end

-- The affordable arm boosts to 2 rather than 3 for a reason that has nothing
-- to do with price: boost 3 is the STRUCTURAL guarantee (Ot6StealBoostLevel
-- clamps the level to $ff so vanilla's own `bcs` fires), which would make the
-- grant unfalsifiable as evidence that anything was rolled.  Boost 2 adds 90
-- to the thief level, and TargetEffect_52 takes its `bmi` shortcut -- an
-- outright steal, no roll -- whenever level + 90 + $32 - target level >= 128,
-- which the arm asserts off live RAM before it presses A rather than
-- assuming.  Boost 2 also happens to be the level where the escalation would
-- have been most visible (25 against LOCKE's real ~37-MP pool), so it is the
-- arm that shows the exemption is real and not a rounding accident.
local AFFORD_BOOST, REFUSE_BOOST = 2, 3

local mode                               -- "on" (charges) | "off" (free)
local locke
local function bp() return H.readByte(0x3E9C + locke*2) end
local function pend() return H.readByte(0x3E9D + locke*2) end
local function mp() return H.readWord(0x3C08 + locke*2) end
-- $3C08 is the BATTLE MP table and means nothing on the field (it read 20302
-- there, which is trap 1: a WRAM cell means what its owning module says it
-- means).  The segmented drain below crosses battle boundaries, so it asks
-- for the pool through this instead: LOCKE is character 1 and the field
-- record is 37 bytes from $1600 with current MP at +$0d, the same read
-- battle_toolsgrey uses for EDGAR.
local function poolMp()
  if H.battleLoadStarted() and locke then return mp() end
  return H.readWord(0x160d + 37 * 1)
end
local function stealRare(s)   return H.readByte(0x3308 + 8 + s*2) end
local function stealCommon(s) return H.readByte(0x3309 + 8 + s*2) end
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

-- ------------------------------------------------- the observation rig --
local rec = nil
local buzzes, confirms = 0, 0
local snap = nil                         -- arm 3's pre-confirm world
local function newRec() rec = { code = 0 } end
local function armWatches()
  emu.addMemoryCallback(function(_, v)
    if not rec then return end
    if v >= 1 and v <= 3 then rec.code = math.max(rec.code, v)
    elseif v == NONE and rec.code >= 1 and not rec.msgDone then
      rec.msgDone = true
    end
  end, emu.callbackType.write, 0x7E3401, 0x7E3401)
  -- mp-cost queue store (CreateAction), filtered to command $05: the
  -- exact cost Ot6AbilityCost handed back for this Steal.  First $05
  -- store per record (queued latches).
  emu.addMemoryCallback(function(_, v)
    if rec and not rec.queued and H.readByte(0x3A7A) == 0x05 then
      rec.qcost = v; rec.queued = true
    end
  end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
  emu.addMemoryCallback(function(_, v)
    if rec and rec.code >= 1 and v ~= NONE and not rec.msgDone then
      rec.grant = v
    end
  end, emu.callbackType.write, 0x7E32F4, 0x7E32F4 + 18)
  -- the two menu sounds, so the confirm refusal in arm 3 is OBSERVED rather
  -- than inferred from an absence: $95 is magic's error buzz (and the tools
  -- shell's own refusal for an empty cell), $96 the confirm sound the shell
  -- stamps on every A press BEFORE the affordability gate.  Direct-page
  -- stores land in bank $00, so both views are counted together.
  for _, base in ipairs({ 0x000000, 0x7E0000 }) do
    emu.addMemoryCallback(function() buzzes = buzzes + 1 end,
      emu.callbackType.write, base + 0x95, base + 0x95)
    emu.addMemoryCallback(function() confirms = confirms + 1 end,
      emu.callbackType.write, base + 0x96, base + 0x96)
  end
end

local mf = 0
local drive = { wantBp = 0, wantPend = 0, target = nil, hold = false }
local tc = H.targetCursor({ mask = 0x7B7E })
-- Where is the machine?  The party's HP is what tells a stuck menu apart
-- from a party that has been ground down over a long unboosted drain.
local hb = -600
local function heartbeat()
  if H.frame - hb < 600 then return end
  hb = H.frame
  local hps = {}
  for s = 0, 3 do hps[#hps+1] = tostring(H.readWord(0x3BF4 + s*2)) end
  H.log(string.format("[hb f%d] batt=%s menu=%02x actor=%d mstate=%02x "
    .. "bp=%d pend=%d mp=%d hp=%s", H.frame,
    tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
    H.readByte(MSTATE), bp(), pend(), mp(), table.concat(hps, "/")))
end
local function decide()
  heartbeat()
  if H.readByte(MENU) == 0 then
    return (H.frame % 8 < 4) and { a = true } or {}
  end
  tc.observe()
  mf = mf + 1
  local act = H.readByte(ACTOR) & 3
  local st = H.readByte(MSTATE)
  if st == ST_TRANS then return {} end
  local slow = (act == locke and st == ST_ITEM)
  if slow then
    if (mf - 1) % 30 >= 6 then return {} end
  else
    if (mf - 1) % 8 >= 4 then return {} end
  end
  local btn
  if act ~= locke then
    btn = (st == ST_CMD) and "x" or "b"
  elseif bp() < drive.wantBp then
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_ITEM)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_ITEM then
      local want = bagIdxOf({ TONIC, POTION })
      if want == nil then error("bank ran out of items", 0) end
      local cur = H.readByte(0x8947 + locke) + H.readByte(0x894F + locke)
      if cur < want then btn = "down"
      elseif cur > want then btn = "up"
      else btn = "a" end
    elseif st == ST_TGT then btn = "a"
    else btn = "b" end
  elseif pend() < drive.wantPend then
    btn = (st == ST_CMD) and "r" or "b"
  else
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_STEAL)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_THIEF then
      -- drive.hold parks the cursor on the Steal row without confirming, so
      -- the refusal arm can read the row and snapshot the world before the
      -- A press it is measuring
      if drive.hold then return {} end
      btn = "a"
    elseif st == ST_TGT then
      btn = tc.steer(drive.target, mf)   -- nil target: any monster will do
    else btn = "b" end
  end
  return btn and { [btn] = true } or {}
end

-- drive one steal until its action is queued, then hold while it executes
-- (a grant) or fizzles (a bounded wait, since a refused steal grants nothing
-- to signal on).  This is the original's completion shape.
local function oneSteal(tag, wantBp, wantPend, execWait)
  local execFrames = 0
  return H.repeatN(1, {
    H.call(function()
      drive.wantBp, drive.wantPend = wantBp, wantPend
      newRec(); execFrames = 0
    end),
    H.driveUntil(function()
      if rec.queued then execFrames = execFrames + 1 end
      return rec.queued and (rec.grant ~= nil or execFrames >= (execWait or 300))
    end, 30000, {
      H.call(function() H.setPad(decide()) end),
    }, tag),
    H.call(function()
      H.setPad({})
      H.log(string.format("[%s] qcost=%s grant=%s code=%d bp=%d pend=%d mp=%d",
        tag, tostring(rec.qcost), rec.grant and string.format("%02X", rec.grant)
        or "nil", rec.code, bp(), pend(), mp()))
    end),
    H.waitFrames(60),
  })
end

-- classify + suitable-formation battle entry (battle_steal's shape): the
-- executed-signal arms need a BOTH-populated species so a granted item is
-- exactly "the steal executed"
local rareT
local function classify()
  rareT = nil
  for s = 0, 5 do
    if H.readWord(0x3BFC + s*2) > 0 and stealRare(s) ~= NONE then
      rareT = rareT or s
    end
  end
end
local plan
local function enterDesertBattle(n)
  local steps = {}
  for try = 1, 6 do
    steps[#steps+1] = H.cond(function()
      return H.battleLoadStarted() and rareT ~= nil
    end, {}, {
      H.cond(function() return H.battleLoadStarted() end, {
        H.logStep("formation unsuitable -- fleeing for a fresh draw"),
        H.fleeBattle(12000),
        H.waitFrames(240),
      }, {}),
      H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
        H.call(function()
          if not H.worldMode() or not H.worldHasControl() then
            H.setPad({}); return
          end
          H.setPad(((H.frame // 120) % 2 == 0) and { left = true }
            or { right = true })
        end),
      }, "desert encounter " .. n .. " try " .. try),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900,
        "battle " .. n .. " active", 30),
      H.waitFrames(90),
      H.call(function()
        locke = nil
        for slot = 0, 3 do
          if H.readByte(0x3ED8 + slot*2) == 0x01 then locke = slot end
        end
        H.assertEq(locke ~= nil, true, "LOCKE is really in this party")
        classify()
        H.log(string.format("battle %d: rareT=%s mp=%d", n,
          tostring(rareT), mp()))
      end),
    })
  end
  steps[#steps+1] = H.call(function()
    H.assertEq(rareT ~= nil, true,
      "a both-populated species drawn within six encounters")
  end)
  return H.repeatN(1, steps)
end

local mp0

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),

  -- ------------------------------------------------ 1. detect the build --
  H.call(function()
    -- Ot6AbilityCostTbl is present in bank F0 iff OT6_MP_COSTS was on, and a
    -- byte scan is the only way to ask: OT6_SYMS is scraped from the ON build's
    -- ff6-en.dbg, so H.sym would hand back an address that means nothing in the
    -- nomp ROM this test also runs against.

    local keys = { 0x5d, 0x5e, 0x5f, 0x60, 0x61, 0x62, 0x63, 0x64 }
    local base
    for a = 0x300000, 0x30FFF0 do
      local ok = true
      for i, k in ipairs(keys) do
        if H.readRomByte(a + (i - 1) * 2) ~= k then ok = false break end
      end
      if ok and H.readRomByte(a + 16) ~= 0x55 then ok = false end
      if ok then base = a break end
    end
    mode = base and "on" or "off"
    if mode == "on" then
      H.log(string.format("ON build: cost table at $%06x -- Steal must charge %d MP",
        base, STEAL_COST))
    else
      H.log("OFF build: cost table absent -- Steal must be FREE (the control)")
    end
  end),

  H.hold({ "b" }),                    -- real chocobo dismount (gen_kolts)
  H.driveUntil(function() return H.readByte(0x11fa) & 3 == 0 end, 900, {
    H.waitFrames(1),
  }, "chocobo dismount"),
  H.release(),
  H.waitFrames(120),

  -- ------------------------------ 2. charge (ON) / free (OFF, the control) --
  enterDesertBattle(1),
  H.call(function()
    armWatches()
    mp0 = mp()
    if mode == "on" then
      H.assertEq(mp0 >= stealPrice(AFFORD_BOOST), true, string.format(
        "his real pool (%d MP) affords the boost-%d steal (%d MP)",
        mp0, AFFORD_BOOST, stealPrice(AFFORD_BOOST)))
    end
    drive.target = rareT
    -- the guarantee premise, off live RAM: thief level + the boost's 90 +
    -- TargetEffect_52's own $32, less the target's level, has to reach 128
    -- for the `bmi` outright-steal shortcut (battle_main.asm:9574)
    local lvT = H.readByte(0x3B18 + locke * 2)
    local lvM = H.readByte(0x3B18 + 8 + rareT * 2)
    local margin = lvT + 90 + 0x32 - lvM
    H.log(string.format("guarantee premise: LOCKE LV%d +90 +$32 - target LV%d "
      .. "= %d (needs >= 128 for the outright steal)", lvT, lvM, margin))
    H.assertEq(margin >= 128, true,
      "boost 2 carries this steal past TargetEffect_52's bmi shortcut, so the "
      .. "grant below is a guarantee and not a roll")
  end),
  oneSteal("affordable steal (real pool)", AFFORD_BOOST, AFFORD_BOOST),
  H.call(function()
    local left = mp()
    H.log(string.format("affordable steal: queued cost %s, MP %d -> %d, granted %s",
      tostring(rec.qcost), mp0, left, tostring(rec.grant)))
    H.assertEq(rec.grant ~= nil, true,
      "the steal executed and took an item (both builds)")
    if mode == "on" then
      H.assertEq(rec.qcost, stealPrice(AFFORD_BOOST), string.format(
        "ON: Ot6AbilityCost priced a boost-%d cmd $05 at %d -- the FLAT base, "
        .. "not the %d the 2.5x escalation would have charged.  Steal is a "
        .. "chance verb: cmd $05 is in Ot6BoostDmg's gate, the boost buys "
        .. "odds rather than magnitude, and the BP is what pays for it",
        AFFORD_BOOST, stealPrice(AFFORD_BOOST), escalated(AFFORD_BOOST)))
      H.assertEq(rec.qcost ~= escalated(AFFORD_BOOST), true, string.format(
        "ON: and %d really is a different number from the escalated %d, so "
        .. "this arm can tell the two rules apart", stealPrice(AFFORD_BOOST),
        escalated(AFFORD_BOOST)))
      H.assertEq(left, mp0 - stealPrice(AFFORD_BOOST), string.format(
        "ON: the steal deducted exactly %d MP", stealPrice(AFFORD_BOOST)))
    else
      H.assertEq(rec.qcost, 0, "OFF: cmd $05 keeps vanilla's 0 (Ot6AbilityCost absent)")
      H.assertEq(left, mp0, "OFF: the steal is FREE -- vanilla behavior, the control")
    end
    H.screenshot("stealmp_" .. mode .. "_affordable")
  end),

  -- ------------------------------------------------- 3. refusal (ON only) --
  -- Poverty is earned: real unboosted attempts drain 4 MP each (the target does
  -- not matter, because the universal charge lands before the steal effect
  -- looks at the loot) until the pool cannot pay one more.  Then a fresh battle
  -- re-seeds real loot, and a 3-bp guaranteed steal, which cannot
  -- miss, is refused by the universal insufficient-mp fizzle: nothing
  -- taken, MP untouched.  The OFF build charges 0, so there is nothing to
  -- refuse, and this half runs only under the flag.

  -- The segmented shape is the route's own answer to the same problem: a few
  -- steals, flee (a flee pays no experience, so the pool stays drained), a
  -- real field care stop, then back in.  Six rounds is enough for a 31-MP
  -- pool at 4 MP a steal with room to spare.
  H.cond(function() return mode == "on" end, {
    H.call(function()
      drive.target = nil                         -- any monster will do
      drive.wantBp, drive.wantPend = 0, 0        -- pure unboosted attempts
    end),
    (function()
      local steps = {}
      local function partyHurt()
        for s = 0, 3 do
          local h, m = H.readWord(0x3BF4 + s*2), H.readWord(0x3C1C + s*2)
          if m > 0 and m < 9999 and h * 100 // m < 55 then return true end
        end
        return false
      end
      for round = 1, 6 do
        steps[#steps+1] = H.cond(function() return poolMp() < STEAL_COST end, {}, {
          -- in the first round the battle from arm 2 is still up
          H.cond(function() return H.battleLoadStarted() end, {}, {
            H.driveUntil(function() return H.battleLoadStarted() end, 25000, {
              H.call(function()
                if not H.worldMode() or not H.worldHasControl() then
                  H.setPad({}); return
                end
                H.setPad(((H.frame // 120) % 2 == 0) and { left = true }
                  or { right = true })
              end),
            }, "drain round " .. round .. ": an encounter"),
            H.release(),
            H.waitUntil(function() return H.battleActive() end, 900,
              "drain round " .. round .. ": battle active", 30),
            H.waitFrames(90),
            H.call(function()
              locke = nil
              for slot = 0, 3 do
                if H.readByte(0x3ED8 + slot*2) == 0x01 then locke = slot end
              end
              H.assertEq(locke ~= nil, true,
                "LOCKE is really in this party (drain round " .. round .. ")")
            end),
          }),
          -- steal until the pool is spent or the party has taken enough
          H.driveUntil(function()
            return poolMp() < STEAL_COST or not H.battleLoadStarted()
              or partyHurt()
          end, 25000, {
            H.call(function() H.setPad(decide()) end),
          }, "drain round " .. round .. ": steals"),
          H.call(function()
            H.setPad({})
            H.log(string.format("drain round %d: mp=%d", round, poolMp()))
          end),
          H.cond(function() return H.battleLoadStarted() end, {
            H.fleeBattle(12000),
            H.waitFrames(240),
          }, {}),
          -- a real field care stop between rounds, the route's own pattern
          H.cond(function() return poolMp() < STEAL_COST end, {}, {
            H.fieldCare({ tag = "drain round " .. round, threshold = 0.9 }),
          }),
        })
      end
      return H.repeatN(1, steps)
    end)(),
    H.call(function()
      H.setPad({})
      H.log(string.format("drained: mp=%d (< %d)", poolMp(), STEAL_COST))
      H.assertEq(poolMp() < STEAL_COST, true,
        "the pool really was drained below one steal by real attempts")
    end),
    H.cond(function() return H.battleLoadStarted() end, {
      H.fleeBattle(12000),
      H.waitFrames(240),
    }, {}),
    -- and one more care stop, so the refusal battle is not fought by a party
    -- that is about to die in it
    H.fieldCare({ tag = "before the refusal battle", threshold = 0.9 }),
    enterDesertBattle(2),
    -- Park on the Steal row of the thief submenu at the refusal boost and
    -- read the world before pressing anything.  Since v0.19 the refusal is
    -- at the CONFIRM: Ot6KitConfirmMP sits in the tools-shell confirm
    -- (btlgfx UpdateMenuState_30 @8809) and prices the row through
    -- Ot6KitRowCost -- the leaf that stamped the number in the list -- then
    -- takes its verdict from the same Ot6AbilityGrey that greyed it.  So a
    -- drained LOCKE cannot spend the turn on a steal he cannot pay for; he
    -- gets magic's buzz and keeps the turn.  This arm asserts that, not the
    -- absence of a grant.  (The execution-time fizzle is still the backstop
    -- for a pool that moves between the commit and the resolve; that seam is
    -- battle_mpcost's.)
    H.call(function()
      drive.target = rareT
      drive.wantBp, drive.wantPend = REFUSE_BOOST, REFUSE_BOOST
      drive.hold = true
      newRec()
    end),
    H.driveUntil(function()
      return H.readByte(MSTATE) == ST_THIEF
         and (H.readByte(ACTOR) & 3) == locke and pend() == REFUSE_BOOST
    end, 30000, {
      H.call(function() H.setPad(decide()) end),
    }, "the drained LOCKE's thief submenu, at the refusal boost"),
    H.waitFrames(30),
    H.call(function()
      H.setPad({})
      local stamp
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == THIEF_STEAL then
          stamp = H.readByte(ITEMLIST + i * 3 + 1)
        end
      end
      H.log(string.format("[refusal] Steal stamped %s (flat %d; escalated "
        .. "would be %d), pool %d, bp %d, pend %d", tostring(stamp),
        stealPrice(REFUSE_BOOST), escalated(REFUSE_BOOST), mp(), bp(), pend()))
      H.assertEq(stamp, stealPrice(REFUSE_BOOST), string.format(
        "ON: the row this arm is about to be refused for is priced at the "
        .. "flat %d, NOT the %d a 2.5x escalation would draw.  The refusal is "
        .. "therefore the pool failing to afford FOUR MP, which is what "
        .. "earned poverty means, rather than a price nobody could pay",
        stealPrice(REFUSE_BOOST), escalated(REFUSE_BOOST)))
      H.assertEq(mp() < stealPrice(REFUSE_BOOST), true,
        "...and the pool really is under it")
      snap = { mp = mp(), bp = bp(), pend = pend(),
               qcount = H.readByte(0x7B80),
               buzzes = buzzes, confirms = confirms }
      drive.hold = false
    end),
    H.driveUntil(function() return buzzes > snap.buzzes end, 1800, {
      H.call(function() H.setPad(decide()) end),
    }, "the greyed Steal is confirmed and buzzes"),
    H.waitFrames(120),
    H.call(function()
      H.setPad({})
      H.log(string.format("[refusal] after the confirm: mp=%d bp=%d pend=%d "
        .. "state=%02x qcount=%d queued=%s granted=%s buzz(+%d) confirm(+%d)",
        mp(), bp(), pend(), H.readByte(MSTATE), H.readByte(0x7B80),
        tostring(rec.queued), tostring(rec.grant), buzzes - snap.buzzes,
        confirms - snap.confirms))
      H.assertEq(confirms > snap.confirms, true,
        "ON: the A press reached the list ($96, stamped before the gate) -- "
        .. "so what follows is a rejection and not a press that never came")
      H.assertEq(buzzes > snap.buzzes, true,
        "ON: ...and the confirm BUZZED ($95, magic's own error sound)")
      H.assertEq(H.readByte(MSTATE), ST_THIEF,
        "ON: the thief submenu is still open -- LOCKE is still choosing")
      H.assertEq(rec.queued, nil,
        "ON: no action was created -- nothing reached the mp-cost queue, so "
        .. "the TURN was not spent on a steal that could never happen")
      H.assertEq(H.readByte(0x7B80), snap.qcount,
        "ON: and the action-queue commit counter never moved")
      H.assertEq(rec.grant, nil,
        "ON: no item taken, though the 3-bp guarantee means a steal that ran "
        .. "could not have missed")
      H.assertEq(bp(), snap.bp,
        "ON: the BP bank is untouched -- refusing costs no pips")
      H.assertEq(pend(), snap.pend,
        "ON: the boost is still pending, still the player's to spend")
      H.assertEq(mp(), snap.mp,
        "ON: MP unmoved, and never driven negative")
      H.screenshot("stealmp_on_refused")
    end),
  }, {}),

  H.logStep(function() return "steal mpcost A/B complete in " .. mode .. " mode" end),
})
