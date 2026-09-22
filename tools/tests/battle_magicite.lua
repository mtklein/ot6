-- @suite slow savestate=n024_entry
-- battle_magicite.lua -- the Ifrit and Shiva magicite kits, the halves
-- battle_esperstats.lua does not reach: the ability prices their kits are
-- built on, and the summons. battle_esperstats covers which spells and
-- which stat; this file covers what they cost and what the divine does.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/n024_entry.mss.lua"

-- spell ids (const.inc ATTACK enum)
local FIRE, ICE, DRAIN, SHELL, OSMOSE, CURE = 0x00, 0x01, 0x04, 0x25, 0x29, 0x2D
local ANTDOT = 0x32                      -- the 3-MP row the boundary tail steps with
local INFERNO, DDUST = 0x37, 0x38        -- summon attack ids (esper + $36)
local IFRIT, SHIVA = 0x01, 0x02          -- esper indices (GenjuProp order)

-- authored prices (magic_prop_en.dat +$05, spliced in battle_main.asm)
local OSMOSE_MP = 8                      -- vanilla was 1
local FIRE_MP, ICE_MP, DRAIN_MP, SHELL_MP = 4, 5, 15, 15
local INFERNO_MP, DDUST_MP = 26, 27
-- authored Diamond Dust record ($38): power cut, Slow added
local DDUST_POWER, DDUST_STATUS3 = 34, 0x04       -- STATUS3::SLOW = BIT_2
local INFERNO_POWER, INFERNO_STATUS3 = 51, 0x00   -- unchanged (the control)
local MAGIC_PROP_REC = 14
local STATUS3_SLOW = 0x04

local ZMENUSTATE, ZCURSOR, GENJULIST = 0x26, 0x4b, 0x9d89
local MST_MAIN, MST_CHAR, MST_SKILLS, MST_LIST, MST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local function mst() return H.readByte(ZMENUSTATE) end
local function fieldEsper(c) return H.readByte(0x1600 + 37*c + 0x1e) end

-- battle menu
local MENU, ACTOR, MSTATE, CMDROW = 0x7BCA, 0x62CA, 0x7BC2, 0x890F
local ST_CMD, ST_ITEM, ST_MAGIC, ST_ESPER, ST_TGT, ST_TRANS =
  0x05, 0x0A, 0x0E, 0x16, 0x38, 0x01
local CMD_MAGIC, CMD_ITEM = 0x02, 0x01
local CMD_SUMMON = 0x19                  -- what the engine dispatches a divine as
local TGT_MON0 = 0x0100                  -- target word bit 8 = monster slot 0
local MSCROLL, MCOL, MROW = 0x8913, 0x8917, 0x891B
local LISTS = { [0] = 0x208e, [1] = 0x21ca, [2] = 0x2306, [3] = 0x2442 }
local SUMMONED = 0x3f2e
local TONIC, POTION = 0xE8, 0xE9

local BOSS = 0                            -- Number 024's monster slot
local function bossHp() return H.readWord(0x3BFC + BOSS*2) end
local function bossMp() return H.readWord(0x3C08 + 8 + BOSS*2) end
local function bossAllow34() return H.readWord(0x3330 + 8 + BOSS*2) end
local function bossSt3() return H.readByte(0x3EF8 + 8 + BOSS*2) end

local locke, celes
local function mp(slot) return H.readWord(0x3C08 + slot*2) end

-- The fighting run's n024_entry ships Celes MP-DRY: she arrives at
-- 1 of 126, having nuked Ifrit with Ice through the reserve (a deep fight
-- breaches it by design) and cured the party in the Ifrit/Shiva battle one
-- door earlier, with no inn between that door and this one.  That is
-- honest play, and it is not what this lab measures: every experiment
-- below is built on a 31-MP pool (31 = 1 mod 5, so her kit's 15s and 5s
-- step onto exactly 6, the 7-MP boundary).  So the lab pins her FIELD
-- record to 31 before each boot -- a lab condition the fixture cannot
-- supply on cue (waivered in state_write_waivers.txt), and one that
-- touches nothing under test: the prices, latches, debit deltas and the
-- $331c immunity all read the same whatever the pool opens at.
local function recMp(charId) return 0x1600 + 37 * charId + 13 end   -- the +13 M.charMp reads
local CELES_REC_MP = recMp(6)
local POOL = 31                               -- boot B: 31 = 1 (mod 5), the boundary walk's residue
-- boot A opens her at her MAXIMUM, read from the fixture's field record
-- (+15, beside the +13 current MP), so the 27-MP divine leaves every kit
-- row live and no live-RAM refund is needed.  It was a literal 126 (L16-
-- L19 Celes); the #198 re-cut ships her at L20 with 169, and the value
-- under test is "her maximum", not the number.
local function recMaxMp(charId) return 0x1600 + 37 * charId + 15 end
local POOL_A = nil                            -- set at boot A from recMaxMp(6)
local function pinPool(tag, pool, charId, who)
  charId, who = charId or 6, who or "Celes"
  local cur = H.readWord(recMp(charId))
  if cur ~= pool then
    H.log(string.format("[%s] the fixture ships %s at %d MP; pinning the field record to the lab's %d", tag, who, cur, pool))
    H.writeWord(recMp(charId), pool)
  end
  H.assertEq(H.readWord(recMp(charId)), pool, string.format("[%s] %s opens the boot at the lab's %d MP", tag, who, pool))
end
local function hp(slot) return H.readWord(0x3BF4 + slot*2) end
local function mask(slot) return H.readWord(0x3018 + slot*2) end
local function cmdRowOf(slot, cmd)
  for r = 0, 3 do
    if H.readByte(0x202E + slot*12 + r*3) == cmd then return r end
  end
  return nil
end
local function recOf(slot, id)
  local L = LISTS[slot]
  for n = 1, 78 do
    if H.readByte(L + n*4) == id then return n end
  end
  return nil
end
local function costOf(slot, id)
  local n = recOf(slot, id)
  return n and H.readByte(LISTS[slot] + n*4 + 3) or nil
end
local function recEnabled(slot, n)
  return H.readByte(LISTS[slot] + n*4 + 1) < 0x80
end
local function esperRow(slot) return H.readByte(LISTS[slot]) end
local function esperCost(slot) return H.readByte(LISTS[slot] + 3) end
local function esperEnabled(slot) return H.readByte(LISTS[slot] + 1) < 0x80 end
local function bagIdxOf(ids)
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i*5)
    for _, w in ipairs(ids) do
      if id == w and H.readByte(0x2686 + i*5 + 3) > 0 then return i end
    end
  end
  return nil
end

-- ------------------------------------------------ real field esper equip --
local function listSeek(idx, what)
  local ph = 0
  return H.driveUntil(function()
    return mst() == MST_LIST and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
  end, 3000, {
    H.call(function()
      ph = (ph + 1) % 8
      if ph >= 4 then H.setPad({}); return end
      local target
      for r = 0, 26 do
        if H.readByte(GENJULIST + r) == idx then target = r; break end
      end
      if not target then H.setPad({}); return end
      local row = H.readByte(ZCURSOR)
      local d = target - row
      if d % 2 ~= 0 then
        if row % 2 == 0 then
          H.setPad(row >= 26 and { up = true } or { right = true })
        else
          H.setPad({ left = true })
        end
      else
        H.setPad(d > 0 and { down = true } or { up = true })
      end
    end),
    H.waitFrames(1),
  }, what)
end

-- pos is char-select menu order: 0=EDGAR 1=SABIN 2=LOCKE 3=CELES
local function equipOn(pos, idx, roster, tag)
  local steps = {
    H.driveUntil(function() return mst() == MST_MAIN end, 1200, {
      H.pressButtons({ "x" }, 4), H.waitFrames(30),
    }, tag .. ": main menu"),
    H.waitFrames(20),
    H.pressButtons({ "down" }, 3), H.waitFrames(12),   -- Item -> Skills
    H.driveUntil(function() return mst() == MST_CHAR end, 600, {
      H.pressButtons({ "a" }, 3), H.waitFrames(16),
    }, tag .. ": char select"),
    H.waitFrames(10),
  }
  for _ = 1, pos do
    steps[#steps+1] = H.pressButtons({ "down" }, 3)
    steps[#steps+1] = H.waitFrames(12)
  end
  local more = {
    H.driveUntil(function() return mst() == MST_SKILLS end, 600, {
      H.pressButtons({ "a" }, 3), H.waitFrames(16),
    }, tag .. ": skills"),
    H.driveUntil(function()
      return mst() == MST_SKILLS and H.readByte(ZCURSOR) == 0
    end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
      tag .. ": cursor to Espers"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return mst() == MST_LIST end, 300,
      tag .. ": esper list", 5),
    listSeek(idx, tag .. ": cursor to the stone"),
    H.waitFrames(20),
    H.driveUntil(function() return mst() == MST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, tag .. ": detail page"),
    H.waitFrames(20),
    H.pressButtons({ "a" }, 3),            -- equip (MenuState_4d's A)
    H.waitFrames(20),
    H.driveUntil(function() return H.hasControl() and not H.dialogWaiting() end,
      1200, { H.pressButtons({ "b" }, 3), H.waitFrames(20) },
      tag .. ": menu closed"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(fieldEsper(roster), idx,
        tag .. ": the REAL equip landed in the roster record")
    end),
  }
  for _, s in ipairs(more) do steps[#steps+1] = s end
  return H.repeatN(1, steps)
end

-- ------------------------------------------------------ the battle drive --
local spells, mpWrites = {}, {}
local R = {}   -- results; declared BEFORE enterBoss so its $3410 callback
               -- closes over this table
local function sawSpell(id)
  for _, v in ipairs(spells) do if v == id then return true end end
  return false
end

-- modes: the bench (everyone but Celes) is the medic line, spending its
-- turns on the party's condition from the bag, because a two-man fight
-- against a L24 boss does not survive a deferring bench; Celes runs the
-- arms.  The medic line is on for the whole fight, parks included: the
-- one time it was switched off "briefly for menu assertions" (the two
-- latch windows and boot B's walk) the regenerated n024_entry wiped the
-- party under it -- see carePlan below.
local mf = 0
local celesMode = "defer"                -- "defer"|"summon"|"cast"|"park"
local lockeMode = "medic"                -- "medic"|"summon"
local castRec = nil                      -- list record to cast in "cast"
local tc = H.targetCursor({ mask = 0x7B7D,
                            dirs = { "down", "up", "left", "right" } })
-- The medic line's priorities, measured on the regenerated n024_entry
-- (2026-09-07, engine observer below): NUMBER 024's SPECIAL ($ef) is a
-- Muddle -- it took Edgar with the boss's first action (status2 $20 at
-- f1803) and Celes at f3174; muddled Edgar fired NoiseBlaster ($a3) at
-- his own party (tgt=000f), and muddled Sabin's Fire Dance ($60) on the
-- party is what killed Locke (502/466/212/443 -> 201/201/0/180).  No
-- monster action killed anyone until the party was already at 56 HP.
-- So: (1) a muddled living ally is cured first -- a Remedy while the bag
-- has one, a plain hit on the ally after it (physical damage clears
-- Muddle); (2) the dead are raised with Fenix Down; (3) the hurt are
-- healed from the bag: X-Potion in extremis, Potion when badly hurt,
-- Tonics for the rest (this bag carries 0 Potions and 65 Tonics); (4)
-- nothing to do -> Defer, so the next window comes sooner.  Every item
-- here is HP/status only: Celes's pool, the quantity under test, is
-- never touched by the bench.
local REMEDY, XPOTION, FENIX = 0xF5, 0xEA, 0xF0
local CMD_FIGHT = 0x00
local HEAL_PCT = 60
local ST2_MUDDLE = 0x20                  -- $3ee5,e*2 bit 5
local function st2(s) return H.readByte(0x3EE5 + s*2) end
local function maxHp(s) return H.readWord(0x3C1C + s*2) end
local function alive(s) return maxHp(s) > 0 and hp(s) > 0 end
local function carePlan()
  for s = 0, 3 do
    if alive(s) and (st2(s) & ST2_MUDDLE) ~= 0 then
      -- a plain hit on the ally.  Remedy ($F5) was measured NOT to clear
      -- it on this ROM (two Remedies on muddled Edgar, status2 $20 held
      -- through both: exec f3242/done f3623, exec f4596/done f4978); an
      -- ally's Fight did, both times it was tried (f7178, f7367 in the
      -- wipe run, $20 -> $00 at the return).
      return { kind = "fight", target = s, why = "muddled: a hit clears it" }
    end
  end
  for s = 0, 3 do
    if maxHp(s) > 0 and hp(s) == 0 and bagIdxOf({ FENIX }) then
      return { kind = "item", item = FENIX, target = s, why = "down" }
    end
  end
  local worst, wpct = nil, 101
  for s = 0, 3 do
    if alive(s) then
      local pct = hp(s) * 100 // maxHp(s)
      if pct < wpct then worst, wpct = s, pct end
    end
  end
  if worst and wpct < HEAL_PCT then
    local item = (wpct < 25 and bagIdxOf({ XPOTION }) and XPOTION)
              or (wpct < 45 and bagIdxOf({ POTION }) and POTION)
              or (bagIdxOf({ TONIC }) and TONIC)
              or (bagIdxOf({ POTION }) and POTION) or nil
    if item then
      return { kind = "item", item = item, target = worst,
               why = string.format("at %d%%", wpct) }
    end
  end
  return nil
end
local plans, planKey = {}, {}            -- per bench actor: the held plan, its log key
local summonArmed = {}                   -- per summoner: this window came through the esper list
-- ...and the summoner's pool AS SHE CONFIRMED IT, which is the only
-- baseline a "the divine charged its N MP" claim can rest on.
--
-- It used to rest on her pool at the top of the fight, and that is a claim
-- about everyone else's turns as well as her own.  NUMBER 024 muddles, and
-- a muddled Celes takes a turn of her own before she ever reaches the
-- esper window: measured at "[exec f1836] party3 cmd=02 atk=23", a spell
-- nobody chose, in the gap between the muddle landing at f1581 and her
-- divine at f3107 (build/attempts/<branch>/attempts/bisect/
-- post-battle_magicite.log).
-- Her pool was then permanently off the pinned number, "queued and paid
-- for" could not come true on any later frame, and the drive spent its
-- whole 20000-frame budget parked in her magic list while the boss ground
-- the party down -- the run ended in a GAME OVER instead of at the thing
-- it measures.  Sampling at the confirm keeps the assertion word for word
-- and stops it depending on nothing else touching her MP first.
local mpAtArm = {}
local function armSummon(slot)
  if not summonArmed[slot] then mpAtArm[slot] = mp(slot) end
  summonArmed[slot] = true
end
-- Steering a Fight onto an ally: the Fight target screen opens on the
-- monster column, where the party mask ($7b7d) can hold a stale value
-- and the shared targetCursor confirms early (measured: the first
-- "hit slot 0" of the 2026-09-07 rearrangement went to the boss,
-- tgt=0100).  So: monster mask ($7b7e) non-zero -> RIGHT, onto the party
-- column (the monsters stand on the left of the screen; a "left" here
-- parked Sabin in the target screen for 20000 frames, attempt 5); then
-- up/down along the party mask until it is the target's bit and has
-- held four observations.
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local allyAge, allyMask = 0, nil
local function steerAlly(target)
  if H.readByte(TGTMONS) ~= 0 then allyAge, allyMask = 0, nil; return "right" end
  local m = H.readByte(TGTCHARS)
  if m == allyMask then allyAge = allyAge + 1 else allyMask, allyAge = m, 1 end
  if m == (1 << target) then return allyAge >= 4 and "a" or nil end
  if m == 0 then return nil end
  return (m > (1 << target)) and "up" or "down"
end
-- Where is the machine?  The fight ending, and the party being ground down
-- by a level-24 boss, look identical from outside.
local hbF = -600
-- entity e (0..3 party, 4..9 monsters): status1/status2 at $3ee4,e*2 and
-- status3/status4 at $3ef8,e*2 -- the four bytes a status question reads
local function stFour(e)
  return string.format("%02x%02x.%02x%02x", H.readByte(0x3EE4 + e*2),
    H.readByte(0x3EE5 + e*2), H.readByte(0x3EF8 + e*2), H.readByte(0x3EF9 + e*2))
end
local function partyLine()
  local hps, sts = {}, {}
  for s = 0, 3 do
    hps[#hps+1] = tostring(H.readWord(0x3BF4 + s*2))
    sts[#sts+1] = stFour(s)
  end
  return table.concat(hps, "/"), table.concat(sts, " ")
end
local function heartbeat()
  if H.frame - hbF < 600 then return end
  hbF = H.frame
  local hps, sts = partyLine()
  H.log(string.format("[hb f%d] live=%s menu=%02x actor=%d mstate=%02x "
    .. "mons=%d hp=%s st=%s boss=%d/%s celes=%s locke=%s", H.frame,
    tostring(H.battleLoadStarted()), H.readByte(MENU), H.readByte(ACTOR),
    H.readByte(MSTATE), H.monstersPresent(), hps, sts, bossHp(),
    stFour(4 + BOSS), celesMode, lockeMode))
end
-- Engine observer, read-only: every command the engine dispatches, party
-- or monster, at ExecCmd (X = entity offset; $b5/$b6 the command/attack
-- after queue-time folding, $b8 the target word) and its return at
-- SaveForMimic -- the same two observers the lib's action trace reads,
-- which only follows newFightDriver plans and so sees nothing of this
-- file's own decide().  Installed once; callbacks survive loadState.
local execA = H.sym("ExecCmd@battle_code")
local execB = H.sym("SaveForMimic")
local observerOn = false
-- How many monster actions are between their ExecCmd and their return.
-- A monster's status rider lands at the END of its action (measured: the
-- boss's $ef left ExecCmd at f1438 and Celes's Muddle bit appeared with
-- its return at f1595), so "an enemy action is in flight" is exactly the
-- window in which a summon confirmed now can be hijacked before it
-- executes.  summonSafe below refuses to confirm in it.
local monInFlight = 0
-- What the engine actually dispatched for each once-per-battle divine:
-- the caster's status-2 byte and the target word at ExecCmd.  Kept so the
-- phase can ASSERT the precondition was reached instead of inferring it
-- from a boss-HP drop that never comes.
local divineDispatch = {}
local function installObserver()
  if observerOn then return end
  observerOn = true
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x % 2 ~= 0 or x >= 20 then return end
    local cmd, atk, tgt = H.readByte(0xB5), H.readByte(0xB6), H.readWord(0xB8)
    local hps, sts = partyLine()
    H.log(string.format("[exec f%d] %s%d cmd=%02x atk=%02x tgt=%04x | hp=%s st=%s boss=%d/%s",
      H.frame, x < 8 and "party" or "mon", x < 8 and x // 2 or x // 2 - 4,
      cmd, atk, tgt, hps, sts, bossHp(), stFour(4 + BOSS)))
    -- Celes's own Osmose, as the engine dispatches it: the target word
    -- (a muddled caster's spell is re-aimed here, not at the menu) and
    -- the two pools on entry, for the [osmose] verdict below
    if celes and x // 2 == celes and cmd == CMD_MAGIC and atk == OSMOSE then
      R.osmoses = R.osmoses or {}
      R.osmoses[#R.osmoses + 1] = { frame = H.frame, tgt = tgt,
        bossMp0 = bossMp(), mp0 = mp(celes) }
    end
    if x >= 8 then monInFlight = monInFlight + 1 end
    -- the two divines, as dispatched (cmd $19 = Summon): who cast, in what
    -- shape, and at what.  A caster the engine re-aimed leaves its mark
    -- here, where the boss-HP wait can only report "nothing happened".
    if x < 8 and cmd == CMD_SUMMON and (atk == DDUST or atk == INFERNO) then
      divineDispatch[atk] = divineDispatch[atk] or
        { frame = H.frame, slot = x // 2, tgt = tgt,
          st1 = H.readByte(0x3EE4 + (x // 2) * 2),
          st2 = H.readByte(0x3EE5 + (x // 2) * 2), hp0 = bossHp() }
    end
  end, emu.callbackType.exec, execA, execA)
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xffff
    if x % 2 ~= 0 or x >= 20 then return end
    if x >= 8 and monInFlight > 0 then monInFlight = monInFlight - 1 end
    local hps, sts = partyLine()
    H.log(string.format("[done f%d] %s%d | hp=%s st=%s boss=%d/%s", H.frame,
      x < 8 and "party" or "mon", x < 8 and x // 2 or x // 2 - 4, hps, sts,
      bossHp(), stFour(4 + BOSS)))
    if celes and x // 2 == celes and R.osmoses then
      local o = R.osmoses[#R.osmoses]
      if o and o.bossMp1 == nil then
        o.bossMp1, o.mp1, o.doneFrame = bossMp(), mp(celes), H.frame
        H.log(string.format("[osmose f%d] Celes's Osmose tgt=%04x: boss pool %d->%d, hers %d->%d",
          H.frame, o.tgt, o.bossMp0, o.bossMp1, o.mp0, o.mp1))
      end
    end
  end, emu.callbackType.exec, execB, execB)
end
-- the Osmose that proves the reprice: hers, dispatched at the boss
-- (target word bit 8 = monster slot 0), and the boss's pool lower at its
-- return than at its entry.  An Osmose re-aimed by Muddle, or the boss's
-- own casts spending its pool (Ice cost it 777->772 in the wipe run,
-- which is what satisfied a bare bossMp() < g0), do not count.
local function osmoseLanded()
  for _, o in ipairs(R.osmoses or {}) do
    if (o.tgt & (0x0100 << BOSS)) ~= 0 and o.bossMp1 and o.bossMp1 < o.bossMp0 then
      return o
    end
  end
  return nil
end
-- The windows each line acts on are named in decide(); every other
-- $7BC2 value is the engine moving between them -- $17 while the item
-- list scrolls a row, $41/$40 while a target window opens and closes, $09
-- and $0f/$10 while a list opens.  These lines used to press B in all of
-- them, and B there backs out of the line's own selection: on the #177
-- run's n024_entry Locke's Tonic (row 22) cost a B at every scrolled
-- row and 12 target windows cancelled in their opening frame (f4190..f4702,
-- 2026-09-17), the bench held the menu ~600 frames a turn, Celes's
-- post-Osmose window never came, and two Magnitude8s ($BC, f6786/f7576)
-- wiped the party.  So an unhandled state gets no press until it has
-- stood BACKOUT_F frames (a window nobody drives), and then one B.
local BACKOUT_F = 90
-- A divine is once per battle.  Confirming one is therefore the single
-- irreversible press this file makes, and it was being made on luck: on
-- the current n024_entry the boss's FIRST action ($ef, ExecCmd f1438) was
-- still in flight when the esper window confirmed at f1537, its Muddle
-- landed on Celes with that action's return at f1595, and her queued
-- Diamond Dust left ExecCmd at f1634 re-aimed (cmd=19 atk=38 tgt=0000).
-- The summon latched $3f2e and charged its 27 MP, the boss took nothing,
-- and a wait for "boss HP drops" can only time out -- the divine cannot
-- be recast.  (build/lab/magicite/repro1.log, and the retained main
-- baseline it reproduces frame for frame.)
--
-- So the confirm waits for the state it needs instead of hoping for it:
-- the caster's own command is not hijacked, and no enemy action is
-- between its ExecCmd and its return.  A rider lands with that return, so
-- an enemy that starts acting AFTER the confirm has that whole action to
-- run first: on this fixture the boss's actions took 94, 157, 158, 280
-- and 308 frames from ExecCmd to return (repro1.log), against the 97
-- frames from the esper confirm at f1537 to the divine's own ExecCmd at
-- f1634.  Waiting costs only turns; the
-- esper window is a window a player can sit in, and a Muddle that lands
-- while it is open closes it and gives the turn back, unspent.
local ST1_IMP, ST1_PETRIFY = 0x20, 0x40
local ST2_BERSERK, ST2_SLEEP = 0x10, 0x80
local function summonUnsafe(s)
  local a, b = H.readByte(0x3EE4 + s*2), st2(s)
  if (b & ST2_MUDDLE) ~= 0 then return "Muddled" end
  if (b & ST2_BERSERK) ~= 0 then return "Berserk" end
  if (b & ST2_SLEEP) ~= 0 then return "asleep" end
  if (a & ST1_IMP) ~= 0 then return "an Imp" end
  if (a & ST1_PETRIFY) ~= 0 then return "petrified" end
  if monInFlight > 0 then return "an enemy action is in flight" end
  return nil
end
local holdWhy = {}
local function summonHold(s, who)
  local why = summonUnsafe(s)
  if why ~= holdWhy[s] then
    holdWhy[s] = why
    if why then
      H.log(string.format("[divine f%d] %s holds the esper window: %s", H.frame, who, why))
    else
      H.log(string.format("[divine f%d] %s confirms the divine: caster clean, no enemy action in flight", H.frame, who))
    end
  end
  return why
end
-- A plan made at the command window can be overtaken before its target
-- window confirms: another bench member's X-Potion lands on the same
-- ally, or a hit clears the Muddle the plan was for.  On main's run
-- at seed shift 17 (2026-09-17) Sabin sat in a Tonic's target window for
-- Locke while Edgar's X-Potion (exec f3788, done f4120) healed him to
-- full, and slot 2 never lit in 18 taps -- the lib's steer bailed; at
-- shift 31 all three of the bench hit Celes for one Muddle the first hit
-- had cleared (f3813, f3903, f3988).  A moot plan is dropped, not
-- confirmed.
local function planMoot(p)
  if p == nil then return nil end
  local s = p.target
  if p.kind == "fight" then
    if not alive(s) then return "the ally is down" end
    if (st2(s) & ST2_MUDDLE) == 0 then return "the Muddle is already cleared" end
  elseif p.item == FENIX then
    if alive(s) then return "the ally is already up" end
  elseif p.item then
    if not alive(s) then return "the ally is down" end
    if hp(s) * 100 // maxHp(s) >= HEAL_PCT then
      return string.format("the ally is back at %d%%", hp(s) * 100 // maxHp(s))
    end
  end
  return nil
end
-- The shared targetCursor raises when the wanted slot never lights in a
-- target window.  A slot that does not light while its plan is still
-- live is backed out of and re-planned, the way a player whose cursor
-- skips an ally cancels and chooses again; a third bail in one battle
-- is raised as the lib raised it.
local steerBails = 0
local function safeSteer(act, target)
  local ok, r = pcall(tc.steer, target, mf)
  if ok then return r end
  steerBails = steerBails + 1
  H.log(string.format("[steer f%d] actor=%d: bail %d this battle: %s", H.frame, act, steerBails, tostring(r)))
  if steerBails >= 3 then error(r, 0) end
  plans[act], planKey[act] = nil, nil
  return "b"
end
local lastSt, lastAct, lastStF = nil, nil, 0
local backouts = 0
local function settle(act, st)
  if H.frame - lastStF < BACKOUT_F then return nil end
  backouts = backouts + 1
  lastStF = H.frame
  H.log(string.format("[settle f%d] actor=%d: menu state $%02x stood %d frames with no line driving it -- B",
    H.frame, act, st, BACKOUT_F))
  return "b"
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
  -- How long the menu has sat in this state: an unhandled state is the
  -- engine between windows and gets no press until it has stood still
  -- for BACKOUT_F frames (settle below).
  if st ~= lastSt or act ~= lastAct then lastSt, lastAct, lastStF = st, act, H.frame end
  if st == ST_TRANS then return {} end
  -- One cadence for every window, the item list included.  The item list
  -- used to walk at one press per 30 frames; this fixture's battle mode is
  -- ACTIVE ($1D4D=$22), so that walk was live exposure -- a Tonic sits at
  -- row 22 and the X-Potion at 29 -- and in the 2026-09-07 rearrangement
  -- run Edgar's X-Potion for a 3-HP Locke was still walking when the
  -- boss's second Magnitude8 (f12998) put three of the four down.
  if (mf - 1) % 8 >= 4 then return {} end
  local btn
  if act == locke and lockeMode == "summon" then
    if st == ST_CMD then
      local want = cmdRowOf(locke, CMD_MAGIC)
      local cur = H.readByte(CMDROW + locke) & 3
      if cur == want then btn = "a"
      else btn = (cur < want) and "down" or "up" end
    elseif st == ST_MAGIC then btn = "up"       -- to the top, then the esper window
    elseif st == ST_ESPER then
      if summonHold(locke, "Locke") then btn = nil
      else btn = "a"; armSummon(locke) end
    elseif st == ST_TGT then
      -- confirm only a target screen this branch opened from the esper
      -- window: when the mode flipped medic -> summon with his Fight's
      -- target screen already open, a bare "a" here confirmed that Fight
      -- on the boss (party2 cmd=00 tgt=0100 at f2422, 2026-09-07)
      btn = summonArmed[locke] and "a" or "b"
    else btn = settle(act, st) end
    if st == ST_CMD then summonArmed[locke] = nil end
    return btn and { [btn] = true } or {}
  end
  if act ~= celes then                          -- the medic line
    if st == ST_CMD then
      -- plan at the command window and hold it through the item and
      -- target windows, so a mid-menu HP change cannot thrash the cursor
      local p = carePlan()
      local key = p and string.format("%s/%s/%d", p.kind, tostring(p.item), p.target) or "-"
      if key ~= planKey[act] then
        planKey[act] = key
        if p then
          H.log(string.format("[medic f%d] actor=%d: %s slot %d (%s) -- hp=%d/%d/%d/%d",
            H.frame, act, p.item and string.format("item $%02X on", p.item) or "hit",
            p.target, p.why, hp(0), hp(1), hp(2), hp(3)))
        end
      end
      plans[act] = p
      local want = p and cmdRowOf(act, p.kind == "item" and CMD_ITEM or CMD_FIGHT)
      if want == nil then btn = "x"
      else
        local cur = H.readByte(CMDROW + act) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      end
    elseif st == ST_ITEM then
      local p = plans[act]
      local want = p and p.item and bagIdxOf({ p.item })
      if want == nil then btn = "b"
      else
        local cur = H.readByte(0x8947 + act) + H.readByte(0x894F + act)
        if cur < want then btn = "down"
        elseif cur > want then btn = "up"
        else btn = "a" end
      end
    elseif st == ST_TGT then
      -- steer onto the plan's slot (a corpse for Fenix Down, the muddled
      -- ally for Remedy or the hit, the worst-hp ally for a heal) -- unless
      -- the plan went moot while its windows were open (planMoot), in which
      -- case back out and plan again at the command window
      local p = plans[act]
      local moot = planMoot(p)
      if moot then
        H.log(string.format("[medic f%d] actor=%d: %s on slot %d is moot (%s) -- backing out to re-plan",
          H.frame, act, p.item and string.format("item $%02X", p.item) or "hit", p.target, moot))
        plans[act], planKey[act] = nil, nil
        btn = "b"
      elseif p and p.kind == "fight" then btn = steerAlly(p.target)
      else btn = safeSteer(act, p and p.target) end
    else btn = settle(act, st) end
  elseif act == celes then
    if celesMode == "defer" then
      if st == ST_CMD then btn = "x"
      elseif st == ST_ITEM or st == ST_MAGIC or st == ST_ESPER or st == ST_TGT then btn = "b"
      else btn = settle(act, st) end
    elseif celesMode == "summon" then
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then
        -- scroll the list to the top, then up opens the esper window
        if H.readByte(MSCROLL + celes) + H.readByte(MROW + celes) > 0 then
          btn = "up"
        else btn = "up" end
      elseif st == ST_ESPER then
        if summonHold(celes, "Celes") then btn = nil
        else btn = "a"; armSummon(celes) end
      elseif st == ST_TGT then btn = summonArmed[celes] and "a" or "b"   -- as Locke's
      else btn = settle(act, st) end
      if st == ST_CMD then summonArmed[celes] = nil end
    elseif celesMode == "cast" then
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then
        -- grid cell p = list record p+1 (record 0 is the esper row)
        local idx = castRec - 1
        local wr, wc = idx // 2, idx % 2
        local ar = H.readByte(MSCROLL + celes) + H.readByte(MROW + celes)
        local col = H.readByte(MCOL + celes)
        if ar < wr then btn = "down"
        elseif ar > wr then btn = "up"
        elseif col < wc then btn = "right"
        elseif col > wc then btn = "left"
        else btn = "a" end
      elseif st == ST_ESPER then btn = "b"
      elseif st == ST_TGT then
        -- the spell's own default side -- except a Cure, which the walk
        -- spends anyway: same 5 MP, so it goes to the worst-hp living
        -- ally (the tail's two Cures used to land on Celes herself at
        -- full HP while the bench was being ground down by ~190-a-head
        -- AoEs, 2026-09-07)
        if castRec == recOf(celes, CURE) then
          local worst, wpct = nil, 101
          for s = 0, 3 do
            if alive(s) then
              local pct = hp(s) * 100 // maxHp(s)
              if pct < wpct then worst, wpct = s, pct end
            end
          end
          btn = safeSteer(act, worst)
        else btn = "a" end
      else btn = settle(act, st) end
    else                                   -- "park": open her list and hold
      if st == ST_CMD then
        local want = cmdRowOf(celes, CMD_MAGIC)
        local cur = H.readByte(CMDROW + celes) & 3
        if cur == want then btn = "a"
        else btn = (cur < want) and "down" or "up" end
      elseif st == ST_MAGIC then btn = nil
      elseif st == ST_ESPER then btn = "b"
      else btn = settle(act, st) end
    end
  end
  return btn and { [btn] = true } or {}
end
-- The divine's one shot, as the engine dispatched it.  This is checked
-- BEFORE the wait for the boss's HP to move, so a divine the engine
-- re-aimed off the boss fails saying so, at the frame it happened, rather
-- than as a 5000-frame timeout on an effect that can never arrive.
local function divineDispatched(tag, atk, name)
  local d = divineDispatch[atk]
  H.assertEq(d ~= nil, true,
    tag .. " the engine dispatched " .. name .. " as a Summon (cmd $19)")
  H.log(string.format("%s %s dispatched at f%d by slot %d: caster st=%02x%02x, target word %04x, boss hp %d",
    tag, name, d.frame, d.slot, d.st1, d.st2, d.tgt, d.hp0))
  H.assertEq(d.st2 & (ST2_MUDDLE | ST2_BERSERK | ST2_SLEEP), 0,
    tag .. " " .. name .. " left ExecCmd from a caster whose own command "
    .. "was still hers (no Muddle/Berserk/Sleep on the once-per-battle turn)")
  H.assertEq((d.tgt & TGT_MON0) ~= 0, true,
    tag .. " ...and aimed at NUMBER 024 (target word bit 8): the divine "
    .. "was pointed at the boss, not re-aimed away from it")
end

local function driveTo(pred, maxF, tag)
  return H.driveUntil(pred, maxF, {
    H.call(function()
      -- Wall pin, not play: NUMBER 024's WallChange re-rolls its
      -- absorbed/nullified elements at random, and the fighting
      -- run's fixture rolled a wall that ate Inferno's fire -- the
      -- summon queued, paid, and latched, then "resolves" (boss HP
      -- drops) never came, and a once-per-battle divine cannot retry.
      -- The properties under test are kit prices, latches, and the
      -- status rider (species immunity at $331c), never the wall, so
      -- the boss's $3bcc absorb/null word is held at zero while this
      -- file drives.  Declared in state_write_waivers.txt.
      if H.battleActive() then H.writeWord(0x3BCC + 8 + BOSS * 2, 0) end
      H.setPad(decide())
    end),
  }, tag)
end

-- enter battle 72 from the entry-point park (face up, one A)
local function enterBoss(tag)
  return H.repeatN(1, {
    H.hold({ "up" }), H.waitFrames(4), H.release(), H.waitFrames(10),
    H.driveUntil(function() return H.battleLoadStarted() end, 2000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(20),
    }, tag .. ": battle 72 opens"),
    H.waitUntil(function() return H.battleActive() end, 900,
      tag .. ": battle active", 30),
    H.waitFrames(120),
    H.call(function()
      locke, celes = nil, nil
      for slot = 0, 3 do
        local id = H.readByte(0x3ED8 + slot*2)
        if id == 0x01 then locke = slot end
        if id == 0x06 then celes = slot end
      end
      H.assertEq(locke ~= nil and celes ~= nil, true,
        tag .. ": LOCKE and CELES really fight this")
      plans, planKey, summonArmed, mpAtArm = {}, {}, {}, {}
      divineDispatch, holdWhy, monInFlight = {}, {}, 0
      steerBails = 0
      R.osmoses = {}
      spells, mpWrites = {}, {}
      emu.addMemoryCallback(function(_, v)
        spells[#spells + 1] = v
        -- actions serialize, so the boss HP at Inferno's own queue write is
        -- the value after DDust fully resolved, which is the per-summon
        -- damage baseline
        if v == INFERNO and R.hpMid == nil then R.hpMid = bossHp() end
      end, emu.callbackType.write, 0x7e3410, 0x7e3410)
      emu.addMemoryCallback(function(_, v) mpWrites[#mpWrites + 1] = v end,
        emu.callbackType.write, 0x7e3C08 + celes*2, 0x7e3C08 + celes*2)
      H.log(string.format("%s: locke slot %d mp=%d, celes slot %d mp=%d, "
        .. "boss hp=%d mp=%d allow34=%04x", tag, locke, mp(locke), celes,
        mp(celes), bossHp(), bossMp(), bossAllow34()))
    end),
  })
end

H.run({ maxFrames = 150000 }, {
  H.waitFrames(20),
  H.call(installObserver),

  -- ------------------------------------------------- 0. the records, in ROM --
  H.call(function()
    local base = H.sym("MagicProp") & 0x3fffff
    local function fld(rec, off) return H.readRomByte(base + rec * MAGIC_PROP_REC + off) end
    H.log(string.format("MagicProp @ file $%06x", base))
    H.assertEq(fld(DDUST, 6), DDUST_POWER, "Diamond Dust ($38) power re-authored to 34")
    H.assertEq(fld(DDUST, 12), DDUST_STATUS3, "Diamond Dust carries STATUS3::SLOW")
    H.assertEq(fld(DDUST, 5), DDUST_MP, "Diamond Dust still costs 27 MP (unchanged)")
    H.assertEq(fld(DDUST, 1), 0x02, "Diamond Dust still ice (unchanged)")
    H.assertEq(fld(INFERNO, 6), INFERNO_POWER, "control: Inferno ($37) power untouched")
    H.assertEq(fld(INFERNO, 12), INFERNO_STATUS3, "control: Inferno carries no status rider")
    H.assertEq(fld(INFERNO, 5), INFERNO_MP, "control: Inferno still costs 26 MP")
    H.assertEq(fld(OSMOSE, 5), OSMOSE_MP, "Osmose ($29) repriced to 8 MP in the record")
  end),

  -- ============================= boot A: the kits, the divine, the latch ==
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function()
    H.assertEq(H.readByte(0x1A69) & 0x06, 0x06,
      "IFRIT and SHIVA really in the bag ($1A69 give_genju receipts)")
  end),
  H.call(function()
    POOL_A = H.readWord(recMaxMp(6))
    H.log(string.format("[bootA] the fixture ships Celes with a %d-MP maximum; boot A opens her there", POOL_A))
    pinPool("bootA", POOL_A)
    -- LOCKE too: the same fixture ships him drained (13 MP; Inferno is 26),
    -- so the Ifrit positive control needs his pool as much as Celes's
    pinPool("bootA", H.charMaxMp(1), 1, "Locke")
  end),
  equipOn(3, SHIVA, 6, "A/celes-shiva"),
  equipOn(2, IFRIT, 1, "A/locke-ifrit"),
  H.fieldCare({ tag = "before battle 72", threshold = 0.95, magic = false }),
  enterBoss("bootA"),
  H.call(function()
    -- 1. Ifrit: the Furnace's prices, on Locke's real granted list
    H.assertEq(esperRow(locke), IFRIT, "[ifrit] list record 0 is Ifrit's summon row")
    H.assertEq(esperCost(locke), INFERNO_MP, "[ifrit] Inferno priced at 26 MP")
    H.assertEq(esperEnabled(locke), true, "[ifrit] the summon is offered at battle start")
    H.assertEq(costOf(locke, FIRE), FIRE_MP, "[ifrit] granted Fire costs 4 MP (base tier)")
    H.assertEq(costOf(locke, DRAIN), DRAIN_MP, "[ifrit] granted Drain costs 15 MP")
    -- 2. Shiva's kit on Celes's real list
    H.assertEq(esperRow(celes), SHIVA, "[shiva] list record 0 is Shiva's summon row")
    H.assertEq(esperCost(celes), DDUST_MP, "[shiva] Diamond Dust published at 27 MP")
    H.assertEq(esperEnabled(celes), true,
      "[shiva] the summon is OFFERED before it is spent (the positive control)")
    H.assertEq(costOf(celes, ICE), ICE_MP, "[shiva] Ice published at 5 MP")
    H.assertEq(costOf(celes, OSMOSE), OSMOSE_MP, "[shiva] Osmose published at 8 MP")
    H.assertEq(costOf(celes, SHELL), SHELL_MP, "[shiva] Shell published at 15 MP")
    H.assertEq(H.readWord(SUMMONED) & (mask(locke) | mask(celes)), 0,
      "[latch] $3f2e clear: nobody has summoned yet")
    -- 3. the species facts the divine arm depends on, read not written
    H.assertEq(bossAllow34() & STATUS3_SLOW, 0,
      "[ddust] NUMBER 024's own authored status word BLOCKS Slow "
      .. "(monster_prop +$16 -- the species choice, read live)")
    H.assertEq(bossSt3() & STATUS3_SLOW, 0, "[ddust] and it starts un-Slowed")
    H.assertEq(bossMp() >= 447, true,
      "[osmose] the real Facility-scale MP pool the reprice exists for")
    R.hp0, R.mp0 = bossHp(), mp(celes)
  end),
  (function()
    local lm0
    return H.repeatN(1, {
      H.call(function()
        R.hpMid = nil
        lm0 = mp(locke)
        celesMode = "summon"
      end),
      driveTo(function()
        return H.readWord(SUMMONED) & mask(celes) ~= 0
           and mpAtArm[celes] ~= nil
           and mp(celes) == mpAtArm[celes] - DDUST_MP
      end, 20000, "Celes's Diamond Dust is really queued and paid for"),
      H.call(function()
        celesMode = "defer"
        divineDispatched("[ddust]", DDUST, "Diamond Dust")
      end),
      driveTo(function() return bossHp() < R.hp0 end, 5000,
        "Diamond Dust resolves against NUMBER 024"),
      H.call(function()
        -- $3410 is a shared numeric ability id: a monster action can also
        -- write $37/$38.  Take the damage baseline only after Celes's latch,
        -- debit and HP change have jointly identified her real summon.
        R.hpMid = bossHp()
        -- The debit is read here, at the queue, and remembered: boot A's
        -- pool is her maximum, so the divine leaves 99 and every kit row
        -- stays live without any refund.  (The engine re-derives a
        -- character's enabled bits only at her action's END -- AfterAction2
        -- consumes the $3204 request; CheckMagicEnabled is cost vs the pool
        -- at that moment -- and again only on the L/R boost edge, which the
        -- parked window never presses; a Defer was measured NOT to rebuild
        -- them.  An earlier cut pinned 31 here and needed a live-RAM refund
        -- ahead of that rebuild; the higher pin removes the write.)
        R.ddustDebit = mpAtArm[celes] - mp(celes)
        lockeMode = "summon"
      end),
      driveTo(function()
        return H.readWord(SUMMONED) & mask(locke) ~= 0
           and mpAtArm[locke] ~= nil
           and mp(locke) == mpAtArm[locke] - INFERNO_MP
      end, 20000, "Locke's Inferno is really queued and paid for"),
      H.call(function()
        lockeMode = "medic"
        divineDispatched("[inferno]", INFERNO, "Inferno")
      end),
      driveTo(function() return bossHp() < R.hpMid end, 5000,
        "Inferno resolves against NUMBER 024"),
      H.call(function()
        H.log(string.format("[divines] boss hp %d->%d->%d st3=%02x | celes "
          .. "mp %d->%d (fight opened at %d) | locke mp %d->%d (opened at "
          .. "%d) | $3f2e=%04x", R.hp0, R.hpMid or -1,
          bossHp(), bossSt3(), mpAtArm[celes], mp(celes), R.mp0,
          mpAtArm[locke], mp(locke), lm0, H.readWord(SUMMONED)))
        H.assertEq(R.hpMid ~= nil and R.hpMid < R.hp0, true,
          "[ddust] the divine HIT (positive control for the status result)")
        H.assertEq(bossHp() < R.hpMid, true, "[inferno] the control divine hit too")
        H.assertEq(bossSt3() & STATUS3_SLOW, 0,
          "[ddust] the Slow rider was REFUSED where the species' authored "
          .. "immunity blocks it -- per-monster immunity is still consulted; "
          .. "[inferno] and Inferno carries no rider of its own")
        H.assertEq(R.ddustDebit, DDUST_MP, "[ddust] the summon charged its 27 MP (the debit verified at the queue)")
        H.assertEq(mpAtArm[locke] - mp(locke), INFERNO_MP,
          "[inferno] charged its 26 MP")
        H.assertEq(H.readWord(SUMMONED) & mask(celes) ~= 0, true,
          "[latch] the engine set Celes's once-per-battle bit in $3f2e")
        H.assertEq(H.readWord(SUMMONED) & mask(locke) ~= 0, true,
          "[latch] ...and Locke's, for his own summon")
        H.screenshot("magicite_ddust")
      end),
    })
  end)(),
  -- 5. the spent summon greys at her next real window (natural refresh)
  H.call(function()
    celesMode = "park"
    -- Boot A's pool is her maximum, so nothing here needs a refund: the
    -- window below must show the summon row greyed by the LATCH alone,
    -- with every kit row live by MP.
    H.assertEq(mp(celes), mpAtArm[celes] - DDUST_MP, "[latch] her pool is the divine's debit and nothing else (no refund, nothing spent since the confirm)")
  end),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her next window's list is open"),
  -- The window's enabled bits were built at her action's end, at the
  -- post-divine pool (99 of 126 here): the summon row greys by the latch,
  -- the kit rows stay live by MP.
  H.call(function()
    H.setPad({})
    H.assertEq(esperCost(celes), DDUST_MP, "[latch] ...still priced at 27")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[latch] her Ice row stays live after the summon")
  end),

  (function()
    local m0, g0
    return H.repeatN(1, {
      H.call(function()
        m0, g0 = mp(celes), bossMp()
        mpWrites = {}
        celesMode = "cast"; castRec = recOf(celes, OSMOSE)
        H.log(string.format("[osmose] casting at mp=%d, boss pool=%d", m0, g0))
      end),
      driveTo(function()
        -- The refill can only show if her pool has room for it: an Osmose
        -- entered at her maximum pays 8, drains, and is capped straight
        -- back to where it started.  On main's run at seed shift 31
        -- (2026-09-17) Muddle re-aimed her first Osmose at Edgar
        -- (tgt=0000, hers 99->126), and the second, at the boss, entered
        -- at 126 and left at 126 -- the [osmose] rise assertion failed on
        -- a full pool, not on the price.  So while no Osmose has landed on
        -- the boss and her pool is within one Osmose of full, she casts
        -- Shell (15) first, a spell of her own kit, and Osmose after it.
        -- (Osmose's transfer is applied at ExecCmd and the done callback
        -- comes ~400 frames later, so an Osmose still in flight is left to
        -- finish before the pool is judged.)
        local last = R.osmoses and R.osmoses[#R.osmoses]
        local inFlight = last ~= nil and last.bossMp1 == nil
        if osmoseLanded() == nil and not inFlight then
          local full = H.readWord(0x3C30 + celes*2)
          local want = (mp(celes) > full - OSMOSE_MP - 1) and SHELL or OSMOSE
          if castRec ~= recOf(celes, want) then
            H.log(string.format("[osmose f%d] her pool reads %d of %d: casting %s next",
              H.frame, mp(celes), full, want == SHELL and "Shell to make room" or "Osmose"))
            castRec = recOf(celes, want)
          end
        end
        local o = osmoseLanded()
        local debited = false
        for _, v in ipairs(mpWrites) do
          if o and (v & 0xff) == ((o.mp0 - OSMOSE_MP) & 0xff) then debited = true end
        end
        return debited and bossMp() < g0 and o ~= nil
      end, 20000, "Celes's Osmose is really charged and drains the boss"),
      H.call(function() celesMode = "defer" end),
      H.waitFrames(240),
      H.call(function()
        local seen = {}
        for _, v in ipairs(mpWrites) do seen[v & 0xff] = true end
        H.log(string.format("[osmose] mp %d->%d, boss pool %d->%d",
          m0, mp(celes), g0, bossMp()))
        local o = osmoseLanded()
        H.assertEq(o ~= nil, true,
          "[osmose] HER Osmose was dispatched at the boss (target word) and "
          .. "the boss's pool was lower at its return than at its entry")
        H.assertEq(o ~= nil and o.mp1 > o.mp0, true,
          "[osmose] ...and her own pool rose across that same execution")
        H.assertEq(o ~= nil and seen[(o.mp0 - OSMOSE_MP) & 0xff], true,
          "[osmose] the caster's MP was debited to exactly mp0-8 (the charge; "
          .. "mp0 = her pool as that landed Osmose entered ExecCmd)")
        H.assertEq(bossMp() < g0, true, "[osmose] the boss's real pool dropped")
        H.assertEq(o ~= nil and mp(celes) > o.mp0, true,
          "[osmose] and the caster ended NET POSITIVE -- 8 MP is still a refill "
          .. "(against her pool as that Osmose entered)")
        H.screenshot("magicite_osmose")
      end),
    })
  end)(),

  -- Now that Osmose has restored her above 27 MP, the spent summon row's
  -- grey cannot be explained by price.  Re-open the same live list and bind
  -- the verdict uniquely to the once-per-battle latch.
  H.call(function() celesMode = "park" end),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her refilled post-summon list is open"),
  H.call(function()
    H.setPad({})
    H.assertEq(mp(celes) >= DDUST_MP, true,
      "[latch] Osmose restored enough MP to afford another summon")
    H.assertEq(esperEnabled(celes), false,
      "[latch] the affordable spent summon is grey from $3f2e")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[latch] an ordinary affordable spell remains live beside it")
  end),

  -- ============================ boot B: the re-offer and the boundary ==
  H.loadState(STATE),
  H.waitFrames(60),
  H.call(function() pinPool("bootB", POOL) end),
  equipOn(3, SHIVA, 6, "B/celes-shiva"),
  H.fieldCare({ tag = "before battle 72 (boot B)", threshold = 0.95,
                magic = false }),
  enterBoss("bootB"),
  H.call(function()
    -- 7. the re-offer half of once-per-battle: a fresh battle offers the
    -- summon again (boot A's was spent and greyed when its battle ended)
    H.assertEq(esperEnabled(celes), true,
      "[latch] a NEW battle offers the summon again -- the latch is "
      .. "per-battle, not forever")
    H.assertEq(H.readWord(SUMMONED) & mask(celes), 0,
      "[latch] ...because battle init cleared $3f2e")
    R.mp0 = mp(celes)
    -- Her pool is the lab's 31 (pinPool above; the fled fixture carried
    -- 41 of 106, the first fighting re-cut 31 of 126, the current one 1 of
    -- 126), and the care stop above is deliberately item-only so that it
    -- heals her HP without touching the pool.  The boundary walk below
    -- rests on the residue: 31 = 1 (mod 5) exactly as 41 was, and Shell
    -- (15) and Cure (5) both preserve it, so kit casts alone land on
    -- exactly 6.  The maximum is pinned beside it so a fixture that ships
    -- a different maximum says so.
    H.assertEq(R.mp0, POOL,
      "[drain] her pool opens at the lab's pinned 31")
    -- $3BF4 hp, $3C08 mp, $3C1C max hp, $3C30 max mp: one 20-byte stride
    H.assertEq(H.readWord(0x3C30 + celes*2), H.readWord(recMaxMp(6)),
      "[drain] and her battle maximum is the fixture's field-record maximum")
    -- The boundary is only a handful of her turns from this start.  The
    -- bench stays on the medic line throughout: decide() branches on the
    -- acting slot, so a bench item-target cursor only ever delays her
    -- window, never steers it, and the fixture's boss muddles a
    -- deferring bench into wiping the party (carePlan above).
  end),
  -- 7. the 7-MP boundary, earned by real casts of her own kit: Shells (15)
  -- to bring the pool down in big steps, then a tail that steps onto the
  -- 5..7 window exactly.

  -- So the tail picks its spell from where the pool actually is: Cure (5)
  -- down to 10, then Antdot (3) from 8 or 9, which reaches every value in
  -- 5..7 from any pool of 8 or more.
  H.call(function()
    celesMode = "cast"; castRec = recOf(celes, SHELL)
  end),
  driveTo(function() return mp(celes) < 31 end, 60000,
    "Shell casts walk the pool toward the boundary"),
  (function()
    local function step()
      local m = mp(celes)
      if m >= 10 then return CURE end
      if m >= 8 then return ANTDOT end
      return nil
    end
    local n = 0
    return H.repeatN(1, {
      driveTo(function()
        n = n + 1
        local nxt = step()
        if nxt == nil then return true end
        if celesMode ~= "cast" or castRec ~= recOf(celes, nxt) then
          celesMode = "cast"; castRec = recOf(celes, nxt)
        end
        if n % 300 == 0 then
          H.log(string.format("tail: mp=%d rec=%s st=%02x act=%d chp=%d lhp=%d",
            mp(celes), tostring(castRec), H.readByte(MSTATE),
            H.readByte(ACTOR) & 3, hp(celes), hp(locke)))
        end
        return false
      end, 60000, "Cure casts land the pool in 5..7"),
      H.call(function() celesMode = "park" end),
    })
  end)(),
  driveTo(function()
    return (H.readByte(ACTOR) & 3) == celes and H.readByte(MSTATE) == ST_MAGIC
  end, 20000, "her list open on the earned boundary"),
  H.call(function()
    H.setPad({})
    local m = mp(celes)
    H.log(string.format("[boundary] mp=%d", m))
    H.assertEq(m >= 5 and m <= 7, true,
      "[boundary] the pool really reads 5..7, walked there by real casts")
    H.assertEq(recEnabled(celes, recOf(celes, ICE)), true,
      "[boundary] Ice (5) is castable -- the control")
    H.assertEq(recEnabled(celes, recOf(celes, OSMOSE)), false,
      "[boundary] Osmose (8) is GREYED -- vanilla's 1 MP would not be")
    H.assertEq(recEnabled(celes, recOf(celes, SHELL)), false,
      "[boundary] Shell (15) is greyed")
    -- no summon was spent this battle, so this grey comes only from the MP gate
    H.assertEq(esperEnabled(celes), false,
      "[boundary] and the 27 MP summon is greyed too (no latch spent in "
      .. "this battle -- the grey is the price alone)")
    H.screenshot("magicite_boundary")
    H.log("[magicite] all scenarios passed")
  end),
})
