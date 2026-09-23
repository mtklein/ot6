-- gen_sabin_gau.lua -- step 10 of SABIN's scenario: GAU.  Generates:
--   gau_joined.mss   world (214,147), Crescent Mountain's entry point, party
--                    SABIN+CYAN+GAU.  The trench step starts from here.

-- Every Crescent Mountain helmet-scene variant gates on $01AB (GAU in the
-- party), so the trench cannot open without him.  The route: off the shore
-- (159's y=14 edge row; its "map 0" long-entrance records return to the
-- parent slot, which this chain last pushed at Doma, so the landing is
-- (240,16) rather than the record's coords), Mobliz (world (220,115) -> map 157;
-- the item shop 164 via (26,21); keeper (29,48) talked across his counter
-- from (29,50); shop 12 row 0 = DRIED MEAT, row 1 = TONIC, row 2 = POTION,
-- row 5 = FENIX DOWN), then the
-- Veldt grind.

-- The grind is fought the way a person fights it: every Veldt battle is won
-- with the house menu-episode machine (a boosted Fight on every pip banked,
-- the default for random battles; Sabin's Blitz on a lone monster when he
-- knows it and has the MP), a heal under 50% HP and a revive before
-- anything else, because GAU comes only to a NORMAL battle won with two
-- characters standing (battle_main.asm @4840: $3A76 >= 2, then Rand <
-- $A0), and field care with the bag's Tonics after every fight, so the
-- next one starts whole.  When he appears the feed takes
-- whatever party menu opens: Item, then the Dried Meat, then LEFT onto the
-- monster column until the $20 mask is his, and confirm.  AIScript::_370
-- consumes the meat, sets battle switch 13, and recruits Gau in that same
-- encounter.  If a menu opens while he is still in the one-shot $2F4E
-- appearance model, the confirm there is a Tonic: an item confirmed on him
-- in that model has no recipient but normalizes him into a present enemy.
-- The Active battle mode is selected through Config first.  Every gameplay
-- change is controller input; all addresses here are observations used to
-- close the loop.
--
-- There is no parked menu.  This file used to arm Cyan's Retort and park a
-- Tonic target cursor so that a menu was open when the counter killed the
-- last monster; it bound the grind to last monsters that hit Cyan with a
-- weapon, and against one that did not, both menus stayed parked with the
-- 245000-frame deadline as the only bound.  Measured on this chain
-- (2026-09-22) the park is not
-- what makes the feed possible: with it off, fight #3's Templar died to a
-- plain attack at f18292 and a fresh menu fed the meat to the already-
-- normalized GAU at f18495
-- (build/attempts/wt/gen-robust/lab/gen-robust/nopark/gau_nopark.log),
-- and the park-on run fed him through a menu opened after its park had
-- been backed out, too
-- (build/attempts/wt/gen-robust/lab/gen-robust/park_v1/gau_joined.log: the
-- menu backed out at f13634, APPEARANCE at f13929, the meat at f14175).
--
-- The Veldt deals whatever this save has fought (44 formations at
-- falls_done), so the grind is bounded by what progress looks like rather
-- than by a formation: a fight that deals no damage for NO_DAMAGE_FRAMES,
-- or runs past FIGHT_FRAMES, fails with its formation named; an
-- appearance not fed in FEED_FRAMES, or one that leaves unfed, fails with
-- the menu state.  The grind stops on GAU, or after as many wins that
-- could have brought him as the engine's odds say should have (MISS_ODDS),
-- not on a timer.  A win counts toward that cap only when the engine left
-- GAU's flag armed for it ($11E4 bit 0, which InitBattleType clears for a
-- back, pincer or side battle), so a formation that can only come as a
-- pincer (BattleProp byte $B3, formation $29 on this pool) never counts.
--
-- Only a lost battle reloads a checkpoint, in all four of this file's
-- ladders (the shore transit, the staging walk, the grind's three-attempt
-- seed sweep, the post-join route).  A stalled fight, a walk segment out of
-- frames, a walk that never arrives, a feed that did not land, the odds
-- cap, or a wipe the party walked into after it had stopped dealing damage
-- is a driver or detection defect that another seed would only hide, so it
-- fails the run at once (ladderLoss).  Every reload logs the segment
-- runner's own `[retry] attempt n/N FAILED class=wipe` line, which is what
-- tools/audit_retries.py and tools/audit_fenix.py read.
--
-- The generated state is verified by reload, not just a calm capture: a
-- capture taken with full world control satisfied can still boot into a
-- pending battle on reload (a calm capture does not imply a calm boot), so
-- generation replays the captured blob and requires the same calm the
-- fixture promises to its consumers.

local H = dofile("tools/tests/lib/ot6.lua")
local DOOR = "build/states/falls_done.mss.lua"
local ZMENUSTATE, MAIN_MENU, CONFIG_MENU = 0x26, 0x05, 0x0E

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function monHP(i) return H.readWord(0x3BFC + i * 2) end
local function liveMonsters()
  local n, hp = 0, 0
  for i = 0, 5 do
    if monPresent(i) and monHP(i) > 0 then
      n, hp = n + 1, hp + monHP(i)
    end
  end
  return n, hp
end
local DRIED_MEAT, TONIC, POTION, TINCTURE, ETHER, FENIX_DOWN =
  0xFE, 0xE8, 0xE9, 0xEB, 0xEC, 0xF0
local ANTIDOTE, REMEDY = 0xF2, 0xF5
local function mstateMenu() return H.readByte(0x0026) end
local function inState(s) return function() return mstateMenu() == s end end
local function invSlot(id)
  for i = 0, 255 do
    if H.readByte(0x1869 + i) == id then return i end
  end
  return nil
end
local function invCount(id)
  local i = invSlot(id)
  return i and H.readByte(0x1969 + i) or 0
end
local function gil()
  return H.readByte(0x1860) + (H.readByte(0x1861) << 8)
       + (H.readByte(0x1862) << 16)
end

-- battle-menu model (battle_vargas / gen_sabin_train's map; all READS)
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_ITEM, ST_RAGE, ST_TGT, ST_TOOLS =
  0x05, 0x0A, 0x1E, 0x38, 0x30
local CMD_FIGHT, CMD_ITEM, CMD_BLITZ, CMD_RAGE, CMD_LEAP =
  0x00, 0x01, 0x0A, 0x10, 0x11
local PUMMEL, SUPLEX = 0x5D, 0x5F
local CMDTBL, CMDROW, ITEMLIST = 0x202E, 0x890F, 0x4005
local ITEMSCR, ITEMROW = 0x8947, 0x894F
local BLCOL, BLROW = 0x8963, 0x8967
local RAGESCR, RAGECOL, RAGEROW = 0x892B, 0x892F, 0x8933
local BATTINV = 0x2686
local TGTCHARS, TGTMONS = 0x7B7D, 0x7B7E
local BP = 0x3E9C
local function pHP(e) return H.readWord(0x3BF4 + e * 2) end
local function pMaxHP(e) return H.readWord(0x3C1C + e * 2) end
local function pMP(e) return H.readWord(0x3C08 + e * 2) end
-- The lib fight driver's battle-open, [death] and Fenix Down landing lines
-- (newFightDriver, lib/ot6.lua) for a fight this file drives itself, so
-- tools/audit_boost.py sees the pips a member held when they fell and
-- tools/audit_fenix.py the fight a Fenix Down answered (#220).  Ticks count
-- from the first frame the battle table is live with monsters present; no
-- monster action is attributed.
local function newDeathWatch(tag)
  local W = {}
  function W.reset()
    W.tick, W.opened, W.hp, W.said, W.raise = 0, false, {}, {}, {}
  end
  W.reset()
  function W.frame()
    if not H.battleLoadStarted() then W.reset(); return end
    if not W.opened and H.monstersPresent() == 0 then return end
    W.tick = W.tick + 1
    local pbp = {}
    for p = 0, 3 do pbp[#pbp + 1] = tostring(H.readByte(0x3E9C + p * 2)) end
    local party_bp = table.concat(pbp, ",")
    if not W.opened then
      W.opened = true
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = tostring(H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("[%s] battle f+%d partyhp=%s party_bp=%s monsters=%d",
        tag, W.tick, table.concat(hp, ","), party_bp, H.monstersPresent()))
    end
    for e = 0, 3 do
      local hp, maxhp = H.readWord(0x3BF4 + e * 2), H.readWord(0x3C1C + e * 2)
      local last = W.hp[e]
      if last ~= nil and last ~= 0xFFFF and last > 0 and hp == 0 and maxhp > 0
         and not W.said[e] then
        W.said[e] = true
        local bp = H.readByte(0x3E9C + e * 2)
        H.log(string.format("[%s] [death] f+%d entity %d char %d from %d/%d by "
          .. "nobody (no monster action attributed) bp=%d party_bp=%s%s", tag,
          W.tick, e, H.readByte(0x3ED8 + e * 2), last, maxhp, bp, party_bp,
          bp >= 3 and string.format(" -- died holding %d BP", bp) or ""))
      elseif hp > 0 and hp ~= 0xFFFF then
        W.said[e] = nil
      end
      W.hp[e] = hp
      local r = W.raise[e]
      if r ~= nil then
        if hp > 0 and hp ~= 0xFFFF then
          H.log(string.format("[%s] actor %d's Fenix Down landed: entity %d is at "
            .. "%d/%d at tick %d", tag, r.by, e, hp, maxhp, W.tick))
          W.raise[e] = nil
        elseif W.tick - r.tick > 840 then
          H.log(string.format("[%s] actor %d's Fenix Down on entity %d never landed "
            .. "(%d ticks) -- forgetting it", tag, r.by, e, W.tick - r.tick))
          W.raise[e] = nil
        end
      end
    end
  end
  function W.fenix(actor, e) W.raise[e] = { by = actor, tick = W.tick } end
  return W
end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", pHP(e), pMaxHP(e))
  end
  return table.concat(p, " ")
end
local function cmdRowOf(actor, cmdId)
  for i = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + i * 3) == cmdId then return i end
  end
  return nil
end
local function battInvIdx(id)
  for i = 0, 251 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end

local function settle(toMap, what)
  local phase = 0
  return H.cond(function() return true end, {
    H.driveUntil(function()
      return mapIdx() == toMap and H.hasControl() and H.tileAligned()
         and bright() >= 15
    end, 5000, {
      H.call(function()
        phase = (phase + 1) % 8
        H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
      end),
    }, what),
    H.waitFrames(20),
    H.call(function()
      H.log(string.format("[gau] %s: map=%d (%d,%d)", what, mapIdx(),
        H.fieldX(), H.fieldY()))
    end),
  }, {})
end

local function tapUntil(btn, pred, what, budget)
  local phase = 0
  return H.driveUntil(pred, budget or 1500, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(phase < 4 and { btn } or {})
    end),
  }, what)
end

-- Put Dried Meat first through the ordinary field Item/Use move UI.  Battle
-- inventory preserves this order, making the live post-normalization select a
-- short, deterministic controller path.
local function moveMeatToFront(keepMenu)
  local phase = 0
  local function driveCursor(state, target, what)
    return H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == state and H.readByte(0x4B) == target
    end, 2400, {
      H.call(function()
        phase = (phase + 1) % 8
        local cur = H.readByte(0x4B)
        H.setPad(phase < 4 and
          { [cur < target and "down" or "up"] = true } or {})
      end),
    }, what)
  end
  return H.cond(function() return invSlot(DRIED_MEAT) ~= 0 end, {
    H.pressButtons({ "x" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      600, "main menu for inventory move", 5),
    driveCursor(MAIN_MENU, 0, "main-menu cursor on Item"),
    H.pressButtons({ "a" }, 1),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x08 end,
      1200, "field item list", 5),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == 0x08
         and H.readByte(0x4B) == invSlot(DRIED_MEAT)
    end, 4000, {
      H.call(function()
        phase = (phase + 1) % 8
        local cur, want = H.readByte(0x4B), invSlot(DRIED_MEAT)
        H.setPad(phase < 4 and
          { [cur < want and "down" or "up"] = true } or {})
      end),
    }, "field cursor on Dried Meat"),
    H.release(), H.waitFrames(30), H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x19 end,
      600, "field item move mode", 5),
    driveCursor(0x19, 0, "move Dried Meat to slot 0"),
    H.release(), H.waitFrames(30), H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x08 end,
      600, "field item swap committed", 5),
    H.call(function()
      H.assertEq(invSlot(DRIED_MEAT), 0,
        "Dried Meat moved to inventory slot 0 through Item UI")
    end),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == 0x17 end,
      600, "Item options after move", 5),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      900, "main menu after inventory move", 5),
    H.cond(function() return not keepMenu end, {
      H.pressButtons({ "b" }, 4),
      H.waitUntil(function()
        return H.worldMode() and H.worldHasControl() and H.worldAligned()
            or not H.worldMode() and H.hasControl() and H.tileAligned()
      end, 1800, "field after inventory move", 5),
    }, {}),
  }, {})
end

-- Open the main menu if it is not already up.  moveMeatToFront opens it as
-- a side effect of needing it, but its whole body sits behind "the meat is
-- not already in slot 0" (`invSlot(DRIED_MEAT) ~= 0`), so when the meat is
-- already at the front the menu is never opened and the caller is left
-- pressing buttons at the field.

-- Why the two runs differ in where the meat lands is UNVERIFIED: the
-- observable difference is that this one arrived at the counter with
-- tonic=0 in the bag and s2 arrived with tonic=99, and an emptied stack
-- plausibly frees the front slot the purchase then takes.  The repair does
-- not depend on that being the reason -- the drive must not assume a menu
-- it did not open -- so it is recorded as the open question it is.
local function openMainMenu(what)
  return H.cond(function() return H.readByte(ZMENUSTATE) ~= MAIN_MENU end, {
    H.pressButtons({ "x" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      600, what, 5),
  }, {})
end

local function prepareFeed()
  return H.cond(function() return true end, {
    H.release(),
    H.waitFrames(30),
    moveMeatToFront(true),
    H.release(),
    H.waitFrames(30),
    openMainMenu("main menu for Config"),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == MAIN_MENU and H.readByte(0x4B) == 5
    end, 800, {
      H.pressButtons({ "down" }, 4), H.waitFrames(12),
    }, "main-menu cursor on Config"),
    H.pressButtons({ "a" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == CONFIG_MENU end,
      900, "Config menu", 5),
    H.driveUntil(function()
      return H.readByte(ZMENUSTATE) == CONFIG_MENU and H.readByte(0x4B) == 0
    end, 600, {
      H.pressButtons({ "up" }, 4), H.waitFrames(12),
    }, "Config cursor on Battle Mode"),
    H.driveUntil(function() return (H.readByte(0x1D4D) & 0x08) == 0 end,
      300, {
        H.pressButtons({ "left" }, 4), H.waitFrames(12),
      }, "Battle Mode = Active"),
    H.call(function()
      H.assertEq(H.readByte(0x1D4D) & 0x08, 0,
        "Config Battle Mode is Active via UI")
    end),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function() return H.readByte(ZMENUSTATE) == MAIN_MENU end,
      600, "back to main menu", 5),
    H.pressButtons({ "b" }, 4),
    H.waitUntil(function()
      return H.hasControl() and H.tileAligned()
    end, 1800, "field after Config", 5),
  }, {})
end

-- shop buys ride the library's closed-loop, purse-clamp-accepting
-- drive (M.buyItem, promoted from this file's local copy -- the
-- cursor cells, the widget deltas, and the clamp acceptance are
-- documented at the definition)
local buyItem = H.buyItem

-- ------------------------------------------------------- the grind driver --
-- One driveUntil to GAU's join: world wander for encounters; input-driven
-- fights (boost + Fight, a heal under 50%); field care after each; the FEED
-- the moment $2F4E holds with the meat still in the bag.  All cursor state
-- read live, all input by pad.
--
-- What ended an attempt: `lost` is the message, `lostClass` what kind of
-- ending it was, `lostContext` the battle that was up (the runner's own
-- wipe-context shape).  The classes: `wipe`, a lost battle -- the one
-- ending any ladder here reloads its checkpoint for; `driver`, a fight or a
-- feed that stopped making progress, or a wipe that came after the party
-- had stopped dealing damage (see WIPE_QUIET_FRAMES); `stall`, a walk
-- segment out of frames; `odds`, the grind's give-up cap; `other`, a walk
-- that never arrived.  Everything but `wipe` is the controller or its
-- reading of the game, which another seed would only hide, so it fails the
-- run at once (ladderLoss).
local lost, lostClass, lostContext = nil, nil, nil
local wipeN = 0
-- A wipe the party walked into after dealing no damage for this long is a
-- stalled driver, not a lost battle.  Every turn the fight policies here
-- spend is an attack or a heal, so a party taking its turns chips the
-- formation every few hundred frames; half the grind's no-damage bound
-- (NO_DAMAGE_FRAMES, below) is several turns for each member with no
-- attack landing.  Measured: an idle party (a driver that never presses)
-- wiped 6257 frames into a fight that took no damage from its opening
-- (build/attempts/wt/gen-robust-fix/gau_ctl_wipe/gau_joined.log: "fight #1
-- up f8250" .. "wiped in fight #1 at f14506"), and 9849 frames in on the
-- regenerated falls_done (merge/gen_sabin_gau_nc_stallwipe); the longest
-- quiet stretch of an honest fight, logged on every "fight #n over" line,
-- ran 451 to 1579 frames over eight distinct grind fights, the 1579 the Templar
-- and Soldier pack (build/attempts/wt/gen-robust-fix/merge/: nc_odds2,
-- useup2, useup7, useup8).
local WIPE_QUIET_FRAMES = 3000
local function battleContext()
  if not H.battleLoadStarted() then
    return string.format("no battle table was live at the loss (f%d)", H.frame)
  end
  local seats = {}
  for e = 0, 3 do
    local a = H.readByte(0x3ED8 + e * 2)
    seats[#seats + 1] = (a == 0xFF) and "-" or
      string.format("a%d:%d/%d bp%d", a, H.readWord(0x3BF4 + e * 2),
        H.readWord(0x3C1C + e * 2), H.readByte(0x3E9C + e * 2))
  end
  local w = H.formationWords()
  return string.format("the battle up at f%d was formation %04X %04X %04X " ..
    "%04X %04X %04X; seats %s (actor:hp/maxhp bp)", H.frame, w[1], w[2],
    w[3], w[4], w[5], w[6], table.concat(seats, " "))
end
local function lose(class, msg)
  if lost then return end
  lost, lostClass = msg, class
  lostContext = (class == "wipe" or class == "driver") and battleContext()
    or nil
  H.log("[gau] LOST -- " .. msg)
end
-- A wipe read on this frame: a lost battle, unless the party had dealt the
-- formation no damage for WIPE_QUIET_FRAMES before it (`lastDmg` is the
-- frame of the last monster-HP drop in the fight, or its opening frame).
local function loseWipe(msg, lastDmg)
  if lost then return end
  local quiet = lastDmg and (H.frame - lastDmg) or nil
  if quiet and quiet >= WIPE_QUIET_FRAMES then
    lose("driver", string.format("%s, after the party had dealt no damage " ..
      "for %d frames (since f%d): a stalled driver, not a lost battle", msg,
      quiet, lastDmg))
  else
    lose("wipe", msg)
  end
end
local function clearLoss()
  lost, lostClass, lostContext, wipeN = nil, nil, nil, 0
end
-- A ladder in this file that reloads its checkpoint after a loss counts it
-- the way the segment runner counts its own retries, one `[retry] attempt
-- n/N FAILED class=... frame=... totalframes=... shift=... phase=...: msg`
-- line (and a `wipe context:` line for a wipe), so tools/audit_retries.py
-- lists the reload and tools/audit_fenix.py starts the reloaded bag afresh.
-- `shift` is how far the failed attempt had moved the seed from attempt
-- 1's (the grind's seed sweep phases, the other ladders' stagger frames).
local function ladderFailed(ladder, n, of, shift)
  H.log(string.format("[retry] attempt %d/%d FAILED class=%s frame=%d " ..
    "totalframes=%d shift=%d phase=%d: [%s ladder] %s", n, of,
    lostClass or "other", H.frame, H.totalFrames or 0, shift, H.seedPhase(),
    ladder, tostring(lost)))
  if lostClass == "wipe" then
    H.log(string.format("[retry] attempt %d/%d wipe context: %s", n, of,
      lostContext or "no battle was sampled"))
  end
end
-- The end of a ladder's attempt: nothing lost, carry on; a lost battle,
-- count it and let the next attempt reload; anything else, fail the run
-- now.  The raise carries no retryable text, so the segment runner files it
-- as `other` and does not re-roll it either.
local function ladderLoss(ladder, n, of, shift)
  if lost == nil then return end
  if lostClass ~= "wipe" then
    error(string.format("gau: the %s stopped in attempt %d of %d (%s): %s.  " ..
      "Only a lost battle reloads its checkpoint; this is the controller or " ..
      "its reading of the game, and another seed would only hide it.%s",
      ladder, n, of, lostClass, lost,
      lostContext and ("  " .. lostContext) or ""), 0)
  end
  ladderFailed(ladder, n, of, shift)
end
local fed = false                        -- observed feed reaction completed
local grind = { fights = 0, appearances = 0 }
local function gauOn()
  local targettable = H.readByte(0x2f4e)
  local enemyChar = H.readByte(0x3a40)
  return targettable ~= 0xff and enemyChar ~= 0xff
     and (targettable & enemyChar) ~= 0
end
local function gauPresent()
  local slot = H.readByte(0x300b)
  if slot == 0xff or slot > 6 then return false end
  local mask = H.readByte(0x3018 + slot)
  return (H.readByte(0x3aa0 + slot) & 1) ~= 0
     and (H.readByte(0x3a40) & mask) ~= 0
end
local function fedSwitch() return (H.readByte(0x3EBD) & 0x02) ~= 0 end

-- Who is who in a battle.  A party entity's character id is $3ED8+2e (the
-- actor number Ot6VeldtRow compares against CHAR::GAU), so a plan names
-- SABIN or CYAN and asks which entity that is, rather than assuming Sabin
-- sits in slot 0 and Cyan in slot 1.  The max-HP window skips the stale
-- words an unused slot keeps from an earlier fight (see membersDown).
local SABIN, CYAN, GAU = 5, 2, 11
local function entityOf(char)
  for e = 0, 3 do
    local mx = H.readWord(0x3C1C + e * 2)
    if mx > 0 and mx < 1000 and H.readByte(0x3ED8 + e * 2) == char then
      return e
    end
  end
  return nil
end
local function aliveEntity(char)
  local e = entityOf(char)
  if e and H.readWord(0x3BF4 + e * 2) > 0 then return e end
  return nil
end
-- #163: the wipe predicate, readable on EVERY frame rather than behind a
-- battleLoadStarted() gate.  A wipe zeroes every battle-HP word, which
-- that predicate reads as "no battle", so a gated watch misses the one
-- state it exists for (gen_sabin_falls, #159).  Two readings, OR'd: the
-- lib's M.partyWipedInBattle (the run canary's own), and this party's
-- members by character id -- every seat whose actor ($3ED8+2e) is SABIN,
-- CYAN, or GAU once he is fed, with the seat's present bit ($3AA0+2e bit
-- 0) and a plausible max HP, reads 0 HP.  By character, not by slot: the
-- Veldt seats GAU's hidden character AI in seat 2 at full HP with the
-- present bit clear (the lib's note on M.partyWipedInBattle; a real wipe
-- read "[0/363 0/358 394/394 0/0]"), and nothing fixes which seat SABIN
-- and CYAN take.
local function membersDown()
  if H.partyWipedInBattle() then return true end
  local seated, alive = 0, 0
  for e = 0, 3 do
    local a = H.readByte(0x3ED8 + e * 2)
    local mx = pMaxHP(e)
    if (a == SABIN or a == CYAN or (fed and a == GAU))
       and (H.readByte(0x3AA0 + e * 2) & 1) == 1 and mx > 0 and mx < 10000 then
      seated = seated + 1
      if pHP(e) > 0 then alive = alive + 1 end
    end
  end
  return seated > 0 and alive == 0
end
-- Blitzes Sabin knows: $1D28 bit i is the blitz $5D+i (InitSkills,
-- RandBlitz).  A plan never names one he has not learned.
local function blitzKnown(skill)
  return (H.readByte(0x1D28) >> (skill - 0x5D)) & 1 == 1
end

-- The Veldt's pool and the odds of GAU showing up after a win.  The Veldt
-- deals formations from $1DDD's 512 bits -- every formation this save has
-- fought anywhere (battle_main.asm @49e9 adds each one) -- picking the next
-- nonzero byte after $1FA5 and a bit inside it from $1FA2's table
-- (GetVeldtBattle, field/battle.asm).  Both counters advance once per
-- battle and never per step, so the formation sequence after a snapshot is
-- fixed; what pacing and idle frames vary is the in-battle roll ($BE): the
-- battle type and GAU's appearance.
--
-- He appears only after a NORMAL battle (InitBattleType clears $11E4 bit 0
-- for any other type) that ends with two or more characters standing, on
-- a Rand < $A0 roll (160/256, battle_main.asm @4840).  A normal battle is
-- the $CF+1 = 208 weight of RandBitRateTbl row 4; with fewer than three
-- allies the side attack is dropped, so the others a formation allows
-- (BattleProp byte 0 bits 5/6 after the eor $F0: back, pincer) carry 8
-- each.  The chance a formation's win brings GAU is therefore
-- 160/256 * 208/(208 + 8*allowed), and the pool's odds are the mean over
-- the formations it holds.  This is the log's account of the pool; the
-- grind's cap does not rest on it, because each fight reads the engine's
-- own verdict on its type (GAU's flag, see P_APPEAR below) instead.  Returns the
-- formation count, the mean chance, and the formations that can never
-- come as a normal battle (formation $29 at falls_done: BattleProp byte 0
-- $B3, pincer only).
local function veldtPoolOdds()
  local prop = H.sym("BattleProp") & 0x3FFFFF
  local n, sum, never = 0, 0, {}
  for i = 0, 63 do
    local b = H.readByte(0x1DDD + i)
    for k = 0, 7 do
      if (b >> k) & 1 == 1 then
        local f = i * 8 + k
        local allowed = (H.readRomByte(prop + f * 4) ~ 0xF0) & 0xF0
        local w = 208
        if (allowed & 0x10) == 0 then w = 0 end
        local others = ((allowed & 0x20) ~= 0 and 8 or 0)
                     + ((allowed & 0x40) ~= 0 and 8 or 0)
        local front = w > 0 and w / (w + others) or 0
        n, sum = n + 1, sum + 160 / 256 * front
        if w == 0 then
          never[#never + 1] = string.format("$%02X (BattleProp byte 0 $%02X)",
            f, H.readRomByte(prop + f * 4))
        end
      end
    end
  end
  return n, (n > 0 and sum / n or 0), never
end

-- The "unrunnable" measurement is one formation at one tile, not a rule
-- about the Veldt: nothing in the run path reads the Veldt flag ($11E4 is
-- read at battle_main.asm:14150, :14211 and :15779 only, none of them the
-- run code), so whether a given pack can be fled is that formation's own
-- data.  Do not widen it to "no Veldt battle can be fled" without a
-- decode of the pool.

-- Every caller that crosses open Veldt now passes opts.segment and runs
-- behind a ladder with an H.fieldCare stop between battles.  Do not add a
-- bare continuous one back: all three of them wiped a party that way.
local function worldWalkFight(tx, ty, budget, what, arriveOffWorld, opts)
  opts = opts or {}
  local tick, dirFlip, hb = 0, false, -1800
  local plan, planActor, btn, mstreak = nil, nil, nil, 0
  local calm = 0
  local fought, wasBattle = 0, false
  local stuckN, battleFrames, segFrames = 0, 0, 0
  local segCalm, coasting = 0, false
  local missing = {}                     -- skills a list did not offer
  local dmgAt, dmgHp = nil, nil          -- the last monster-HP drop
  local watch = newDeathWatch("gau walk")
  local function makePlan(actor)
    -- `worldWalkFight()` episodes are constructed before H.run starts, so
    -- resolve this at execution time.  The field party byte is repurposed in
    -- battle; the observed completed feed is the durable third-member fact.
    -- The members are named by character, not by battle slot (entityOf).
    local members = {}
    for _, c in ipairs(fed and { SABIN, CYAN, GAU } or { SABIN, CYAN }) do
      members[#members + 1] = entityOf(c)
    end
    local row = cmdRowOf(actor, CMD_ITEM)
    if row then
      for _, e in ipairs(members) do
        if pMaxHP(e) > 0 and pHP(e) == 0 and battInvIdx(FENIX_DOWN) then
          H.log(string.format("[gau] walk revive e%d with Fenix Down [%s]",
            e, partyLine()))
          return { kind = "item", item = FENIX_DOWN, target = e, row = row }
        end
      end
      local target, worst = nil, 8
      for _, e in ipairs(members) do
        if pHP(e) > 0 and pMaxHP(e) > 0 then
          local frac = pHP(e) * 10 // pMaxHP(e)
          local healBelow = 4
          if frac < worst and frac < healBelow then target, worst = e, frac end
        end
      end
      if target then
        local missing = pMaxHP(target) - pHP(target)
        local item = missing >= 80 and battInvIdx(POTION) and POTION
                  or battInvIdx(TONIC) and TONIC
                  or battInvIdx(POTION) and POTION or nil
        if item then
          H.log(string.format("[gau] walk heal e%d with $%02X [%s]", target,
            item, partyLine()))
          return { kind = "item", item = item, target = target, row = row }
        end
      end
    end
    -- Gau's shared row is terrain-dependent: LEAP on the Veldt, FIGHT off it.
    -- Read the built list.  Never select Leap on this fixture-generating
    -- route (it deliberately removes Gau).  On the Veldt, use his actual
    -- attack verb instead: Rage row 1, entry 0 (Brawler from InitRage).
    -- Skipping Gau made every post-join encounter a two-character fight;
    -- the Nautiloid/Exocite/Pterodon pack then outdamaged Tonics on three
    -- staggered timelines.  Off the Veldt the real Fight row remains valid.
    if fed and actor == entityOf(GAU) then
      local row0 = H.readByte(CMDTBL + actor * 12)
      if row0 == CMD_FIGHT then return { kind = "fight", boostLeft = 0 } end
      local rageRow = cmdRowOf(actor, CMD_RAGE)
      if row0 == CMD_LEAP and rageRow then
        return { kind = "rage", row = rageRow }
      end
      return { kind = "switch" }
    end
    local blitzRow = cmdRowOf(actor, CMD_BLITZ)
    if fed and actor == entityOf(SABIN) and blitzRow then
      local skill = (pMP(actor) >= 13 and blitzKnown(SUPLEX)
                     and not missing[SUPLEX]) and SUPLEX
                 or (pMP(actor) >= 4 and blitzKnown(PUMMEL)
                     and not missing[PUMMEL]) and PUMMEL or nil
      if skill then return { kind = "blitz", skill = skill, row = blitzRow } end
    end
    local bp = H.readByte(BP + actor * 2)
    local boost = bp >= 1 and math.min(bp, 3) or 0
    return { kind = "fight", boostLeft = boost }
  end
  local function button()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then
        if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
          return { "b" }
        end
        return nil
      end
      plan, planActor = makePlan(actor), actor
      return nil
    end
    if st == ST_CMD then
      if plan.kind == "switch" then return { "x" } end
      if plan.kind == "fight" then
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return { "r" }
        end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur ~= 0 then return { "up" } end
        return { "a" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == plan.row then return { "a" } end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and plan.kind == "item" then
      local want = battInvIdx(plan.item)
      if want == nil then return { "b" } end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_RAGE and plan.kind == "rage" then
      local scroll = H.readByte(RAGESCR + actor)
      local col = H.readByte(RAGECOL + actor)
      local row = H.readByte(RAGEROW + actor)
      if col > 0 then return { "left" } end
      if scroll + row > 0 then return { "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "item" and plan.target ~= nil then
        local chars, mons = H.readByte(TGTCHARS), H.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        local wantMask = 1 << plan.target
        if chars == wantMask then
          if plan.item == FENIX_DOWN then watch.fenix(actor, plan.target) end
          plan, planActor = nil, nil
          return { "a" }
        end
        local cur = 0
        for e = 0, 3 do
          if chars & (1 << e) ~= 0 then cur = e; break end
        end
        return { cur < plan.target and "down" or "up" }
      end
      plan, planActor = nil, nil
      return { "a" }                       -- Fight: default enemy
    end
    if st == ST_TOOLS and plan.kind == "blitz" then
      local want
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == plan.skill then want = i end
      end
      if want == nil then
        -- not on the list: plan around it from here on, rather than plan
        -- it again on the next turn and back out again
        H.log(string.format("[gau] walk: $%02X is not on actor %d's list " ..
          "-- planning around it", plan.skill, actor))
        missing[plan.skill] = true
        plan, planActor = nil, nil
        return { "b" }
      end
      local wc, wr = want % 2, want // 2
      local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      return { "a" }
    end
    if st == ST_TOOLS then return { "b" } end
    return nil
  end
  return H.driveUntil(function()
    local parked = H.worldMode() and H.worldX() == tx and H.worldY() == ty
       and H.worldHasControl() and H.worldAligned()
       and not H.battleLoadStarted() and (H.readByte(0x00E8) & 0x20) == 0
    calm = parked and calm + 1 or 0

    if opts.segment and H.worldMode() and H.worldHasControl()
       and H.worldAligned() and not H.battleLoadStarted()
       and (fought >= 1
            or (not arriveOffWorld and H.worldX() == tx
                and H.worldY() == ty)) then
      segCalm = segCalm + 1
      coasting = true
      if segCalm >= 60 then return true end
    else
      segCalm, coasting = 0, false
    end
    if opts.segment then
      segFrames = segFrames + 1
      if segFrames > (budget or 40000) - 400 and lost == nil then
        lose("stall", string.format("segment %s ran out of frames (%d, " ..
          "at %d,%d)", what, segFrames, H.worldX(), H.worldY()))
      end
    end
    return lost ~= nil or (arriveOffWorld and not H.worldMode()) or calm >= 30
  end, budget or 40000, {
    H.call(function()
      watch.frame()
      -- #163: the run canary's count is a loss on any frame (it now counts
      -- a 300-frame battle-side wipe as a game over and freezes the pad;
      -- allowGameOver on the run keeps the sweeps alive for the reload)
      if (H.gameOverFired or 0) > 0 and not lost then
        loseWipe(string.format("GAME OVER counted by the canary during " ..
          "%s at f%d [%s]", what, H.frame, partyLine()), dmgAt)
      end
      if lost then H.setPad({}); return end
      if H.battleLoadStarted() then
        battleFrames = (battleFrames or 0) + 1
        -- the formation's HP, for the wipe's stall reading (loseWipe): the
        -- opening frame, then every frame it drops
        local nmon, mhp = liveMonsters()
        if battleFrames == 1 then dmgAt, dmgHp = H.frame, nil end
        if nmon > 0 then
          if dmgHp ~= nil and mhp < dmgHp then dmgAt = H.frame end
          dmgHp = mhp
        end
        if battleFrames == 120 then
          local sp = {}
          for s = 0, 5 do sp[#sp + 1] = string.format("%04X",
            H.readWord(0x57C0 + s * 2)) end
          H.log(string.format("[gau] walk[%s] battle up f%d species %s [%s]",
            what, H.frame, table.concat(sp, " "), partyLine()))
        end
        wasBattle = true
      elseif wasBattle then
        wasBattle, fought, battleFrames = false, fought + 1, 0
      end
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format("[gau] walk[%s] f%d (%d,%d) b=%s [%s]", what,
          H.frame, H.worldX(), H.worldY(),
          tostring(H.battleLoadStarted()), partyLine()))
      end
      if H.battleLoadStarted() then
        if membersDown() then
          loseWipe(string.format("wiped walking %s at f%d [%s]", what,
            H.frame, partyLine()), dmgAt)
          H.setPad({})
          return
        end
        tick = tick + 1
        -- #183: every encounter on the transit and the Veldt is fought by
        -- the fighter below; nothing here holds L+R.
        local ph = tick % 30
        if H.readByte(MENU) == 0 then
          plan, planActor, mstreak = nil, nil, 0
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        mstreak = mstreak + 1
        if mstreak < 4 then H.setPad({}); return end
        if ph == 0 then btn = button() end
        H.setPad(ph < 6 and btn or {})
        return
      end
      plan, planActor = nil, nil
      local live = H.worldHasControl() and H.worldAligned()
         and bright() >= 15
      if not live then
        if membersDown() then
          wipeN = wipeN + 1
          if wipeN >= 90 and not lost then
            loseWipe(string.format("wiped (game over) during %s at f%d " ..
              "[%s]", what, H.frame, partyLine()), dmgAt)
          end
          H.setPad({})
          return
        end
        wipeN = 0
        stuckN = stuckN + 1
        if stuckN == 601 then
          H.log(string.format("[gau] walk[%s] STUCK 600 frames off-world " ..
            "f%d: menu=%02X map=%d field(%d,%d) ctl=%s dlg=%s -- B taps",
            what, H.frame, H.readByte(0x0026), mapIdx(),
            H.fieldX(), H.fieldY(), tostring(H.hasControl()),
            tostring(H.dialogWaiting())))
        end
        if stuckN > 600 then
          local ph = stuckN % 24
          if stuckN > 2400 and ph >= 16 and ph < 20 then
            H.setPad({ "a" })
          elseif ph < 4 then
            H.setPad({ "b" })
          else
            H.setPad({})
          end
        else
          H.setPad({})
        end
        return
      end
      stuckN = 0
      -- Coasting toward a segment exit (see the predicate): stand still.
      -- A step here would start a fresh encounter roll, which is the
      -- exact race the coast exists to flush out.
      if coasting then H.setPad({}); return end
      local p = H.worldBfs(tx, ty)
      if p and #p > 0 then
        H.setPad({ [p[1]] = true })
      else
        -- No path.  Two causes: a fresh danger reload can transiently
        -- block one, and a walk parked ON its goal tile has an empty one,
        -- which is how an arriveOffWorld transit re-enters a town
        -- entrance it is already standing on.  Flip on a period rather
        -- than per frame: a direction that changes every frame never
        -- completes a step, so the old per-frame flip could only jitter.
        dirFlip = (H.frame // 24) % 2 == 0
        H.setPad({ [dirFlip and "left" or "right"] = true })
      end
    end),
  }, "walk fighting -> " .. what)
end

-- The grind's bounds.  None of them is a deadline on the whole grind: how
-- many wins it may take comes from the engine's odds (the cap), and each
-- fight is held to what a fight that is making progress looks like.  Each
-- of them tripping is a driver or detection defect, not a draw: the grind
-- fails at once rather than reloading (see grindAttempt).
--
--   NO_DAMAGE_FRAMES  a fight whose formation has not lost HP for this long
--                     has stopped making progress: fail fast, naming the
--                     formation.  Every turn the policy spends is a heal or
--                     an attack, so the quiet stretches are heal turns and
--                     misses, and 6000 frames is several turns for each
--                     character: the slowest measured single monster, the
--                     Templar, went from alone at its full 205 HP at f16868
--                     to dead at f18292, 1424 frames for all of it
--                     (build/attempts/wt/gen-robust/lab/gen-robust/nopark/
--                     gau_nopark.log).
--   FIGHT_FRAMES      one fight's whole budget (the slowest measured fight,
--                     the Templar/Soldier pack, ran 4933 frames: "fight #3
--                     up f13359" to the appearance at f18292,
--                     build/attempts/wt/gen-robust/lab/gen-robust/
--                     gau_on_old_chain/gau_joined.log).
--   FEED_FRAMES       an appearance that has not recruited GAU in this long
--                     is a failed feed (the measured feeds: 681 frames from
--                     the appearance at f13927 to the join at f14608, the
--                     old generator's gau_joined.log as quoted in
--                     build/attempts/review/gen-robust/extracts.txt, and
--                     478 from f18292 to f18770 in gau_on_old_chain's).
--                     It sits under the runner's 1800-frame no-progress
--                     watchdog on purpose: an unfed GAU freezes the battle
--                     screen, and a feed that stops pressing tripped that
--                     watchdog 1915 frames after the appearance, a class the
--                     runner retries (build/attempts/wt/gen-robust-fix/
--                     gau_nc_nofeed_3600/gau_joined.log), where this bound
--                     fails it as the driver defect it is.
--   P_APPEAR          GAU's roll after a win that can bring him: Rand < $A0,
--                     160/256 (battle_main.asm @4840).  A win can bring him
--                     when it ends with two or more standing ($3A76 >= 2)
--                     and his flag, $11E4 bit 0, is still armed: the field
--                     arms it for every Veldt battle, InitBattleType clears
--                     it for a back, pincer or side battle, and InitParty
--                     for a party of four (battle_main.asm @2e68, @2fc3).
--   MISS_ODDS         the grind gives up after enough such wins that GAU
--                     never appearing in any of them had at most this
--                     chance at P_APPEAR -- "the dice say this should have
--                     happened", not a timer.
--   GRIND_CARE        field care after every fight tops each member up to
--                     this fraction with the bag's Tonics: the transit and
--                     staging walks' threshold on the same Veldt, since GAU
--                     needs both standing when the last monster falls.
local NO_DAMAGE_FRAMES = 6000
local FIGHT_FRAMES = 20000
local FEED_FRAMES = 1500
local P_APPEAR = 160 / 256
local MISS_ODDS = 0.001
local GRIND_CARE = 0.9

local function grindStep()
  local phase, tick = 0, 0
  local plan, planActor = nil, nil
  local dirFlip = false
  local decided = false
  local hb = -1800
  local mstreak = 0
  local feeding = false
  local feedConfirmUntil, feedSubmissions, feedStart = nil, 0, nil
  local meatSubmitted = false
  local cap = nil
  local F = nil                          -- the fight in progress
  local careD = nil                      -- the field care after a fight
  local watch = newDeathWatch("gau grind")

  local function fightLine()
    local sp = {}
    for s = 0, 5 do
      if monPresent(s) and monHP(s) > 0 then
        sp[#sp + 1] = string.format("%04X:%d", H.readWord(0x57C0 + s * 2),
          monHP(s))
      end
    end
    return string.format("live monsters [%s] [%s]", table.concat(sp, " "),
      partyLine())
  end

  local function makePlan(actor)
    local row = cmdRowOf(actor, CMD_ITEM)
    local nmon = liveMonsters()
    local eS, eC = entityOf(SABIN), entityOf(CYAN)
    if row then
      -- GAU comes only to a win with two standing ($3A76 >= 2), so a
      -- revive is always the first thing a turn is spent on
      for _, e in ipairs({ eS, eC }) do
        if e and pMaxHP(e) > 0 and pHP(e) == 0 and battInvIdx(FENIX_DOWN) then
          H.log(string.format("[gau] revive e%d with Fenix Down [%s]",
            e, partyLine()))
          return { kind = "item", item = FENIX_DOWN, target = e, row = row }
        end
      end
      local target, worst = nil, 8
      for _, e in ipairs({ eS, eC }) do
        if e and pHP(e) > 0 and pMaxHP(e) > 0 then
          local frac = pHP(e) * 10 // pMaxHP(e)
          if frac < worst and frac < 5 then target, worst = e, frac end
        end
      end
      if target then
        local missing = pMaxHP(target) - pHP(target)
        local item = missing >= 80 and battInvIdx(POTION) and POTION
                  or battInvIdx(TONIC) and TONIC
                  or battInvIdx(POTION) and POTION or nil
        if item then
          H.log(string.format("[gau] heal e%d with $%02X [%s]", target,
            item, partyLine()))
          return { kind = "item", item = item, target = target, row = row }
        end
      end
    end
    if actor == eS and nmon == 1 and pMP(actor) < 13 and row then
      local mpItem = battInvIdx(ETHER) and ETHER
                  or battInvIdx(TINCTURE) and TINCTURE or nil
      if mpItem then
        return { kind = "item", item = mpItem, target = actor, row = row }
      end
    end
    local blitzRow = cmdRowOf(actor, CMD_BLITZ)
    if actor == eS and nmon == 1 and blitzRow then
      local skill = (pMP(actor) >= 13 and blitzKnown(SUPLEX)) and SUPLEX
                 or (pMP(actor) >= 4 and blitzKnown(PUMMEL)) and PUMMEL or nil
      if skill and not (F and F.missing[skill]) then
        return { kind = "blitz", skill = skill, row = blitzRow }
      end
    end
    -- boost-Fight on every pip banked: the house default for a random
    -- battle (a one-pip boost restores vanilla pace against an unbroken
    -- enemy), and the same policy on every attempt of the grind
    local bp = H.readByte(BP + actor * 2)
    local boost = bp >= 1 and math.min(bp, 3) or 0
    return { kind = "fight", boostLeft = boost }
  end
  local function button()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    if plan == nil or planActor ~= actor then
      if st ~= ST_CMD then
        if st == ST_TOOLS or st == ST_ITEM or st == ST_TGT then
          return { "b" }
        end
        return nil
      end
      plan = makePlan(actor)
      planActor = actor
      return nil
    end
    if st == ST_CMD then
      if plan.kind == "fight" then
        if plan.boostLeft > 0 then
          plan.boostLeft = plan.boostLeft - 1
          return { "r" }
        end
        local cur = H.readByte(CMDROW + actor) & 3
        if cur ~= 0 then return { "up" } end
        return { "a" }
      end
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == plan.row then return { "a" } end
      return { cur < plan.row and "down" or "up" }
    end
    if st == ST_ITEM and plan.kind == "item" then
      local want = battInvIdx(plan.item)
      if want == nil then return { "b" } end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur < want then return { "down" } end
      if cur > want then return { "up" } end
      return { "a" }
    end
    if st == ST_TOOLS and plan.kind == "blitz" then
      local want
      for i = 0, 7 do
        if H.readByte(ITEMLIST + i * 3) == plan.skill then want = i end
      end
      if want == nil then
        -- not on the list: plan around it for the rest of this fight,
        -- rather than plan it again next turn and back out again
        H.log(string.format("[gau] $%02X is not on actor %d's list -- " ..
          "planning around it", plan.skill, actor))
        if F then F.missing[plan.skill] = true end
        plan, planActor = nil, nil
        return { "b" }
      end
      local wc, wr = want % 2, want // 2
      local cc, cr = H.readByte(BLCOL + actor), H.readByte(BLROW + actor)
      if cc ~= wc then return { wc > cc and "right" or "left" } end
      if cr ~= wr then return { wr > cr and "down" or "up" } end
      return { "a" }
    end
    if st == ST_TGT then
      if plan.kind == "item" then
        local chars, mons = H.readByte(TGTCHARS), H.readByte(TGTMONS)
        if mons ~= 0 then return { "right" } end
        local wantMask = 1 << plan.target
        if chars == wantMask then
          if plan.item == FENIX_DOWN then watch.fenix(actor, plan.target) end
          plan, planActor = nil, nil
          return { "a" }
        end
        local cur = 0
        for e = 0, 3 do
          if chars & (1 << e) ~= 0 then cur = e; break end
        end
        return { cur < plan.target and "down" or "up" }
      end
      plan, planActor = nil, nil
      return { "a" }
    end
    return nil
  end
  -- The feed (see the header): a Tonic while GAU is still in the
  -- appearance model, the Dried Meat once he is a normalized enemy.
  local function feedItem() return gauOn() and TONIC or DRIED_MEAT end
  local function feedDrive()
    local st = H.readByte(MSTATE)
    local actor = H.readByte(ACTOR)
    phase = (phase + 1) % 8
    fed = fedSwitch() or invCount(DRIED_MEAT) == 0
    if fed or meatSubmitted or feedSubmissions >= 3 then
      H.setPad({})
      return
    end
    if H.readByte(MENU) == 0 then
      -- Advance GAU's hungry line; no party menu owns input yet.
      H.setPad(H.frame % 30 < 4 and { "a" } or {})
      return
    end
    if st ~= ST_TGT then feedConfirmUntil = nil end
    if st == ST_CMD then
      local row = cmdRowOf(actor, CMD_ITEM) or 0
      local cur = H.readByte(CMDROW + actor) & 3
      if cur == row then H.setPad(phase < 2 and { "a" } or {})
      else H.setPad(phase < 2 and
        { [cur < row and "down" or "up"] = true } or {}) end
      return
    end
    if st == ST_ITEM then
      local want = battInvIdx(feedItem())
      if want == nil then H.setPad(phase < 2 and { "b" } or {}); return end
      local cur = H.readByte(ITEMSCR + actor) + H.readByte(ITEMROW + actor)
      if cur == want then H.setPad(phase < 2 and { "a" } or {})
      else H.setPad(phase < 2 and
        { [cur < want and "down" or "up"] = true } or {}) end
      return
    end
    if st == ST_TGT then
      local mons = H.readByte(TGTMONS)
      if mons == 0x20 then
        if feedConfirmUntil == nil then
          feedSubmissions = feedSubmissions + 1
          feedConfirmUntil = H.frame + 3
          local item = H.readByte(0x7a85)
          if item == DRIED_MEAT then meatSubmitted = true end
          H.log(string.format("[gau feed] confirm item $%02X submission #%d " ..
            "on Gau (%s target model)", item, feedSubmissions,
            gauOn() and "appearance" or gauPresent() and "normalized"
              or "unknown"))
        end
        H.setPad(H.frame <= feedConfirmUntil and { "a" } or {})
      else
        H.setPad(H.frame % 4 < 2 and { "left" } or {})
      end
      return
    end
    H.setPad({})
  end

  -- A fight is over (the battle is gone and the world has control, or GAU
  -- joined inside it): count it, and hold the grind to the engine's odds.
  -- Only a win the engine left GAU's flag armed for counts toward the cap
  -- (P_APPEAR): a back, pincer or side battle -- formation $29 can only
  -- come as a pincer -- can never bring him, whatever the dice say.
  local function closeFight(joined)
    local f = F
    F = nil
    if f == nil or lost then return end
    -- the appearance is proof of the win: CheckBattleEnd rolls for GAU only
    -- once every monster is down ($3A77 = 0, battle_main.asm @4833)
    if f.appeared then f.won = true end
    local eligible = f.won and f.standing >= 2 and f.gauFlag
    if f.won then grind.wins = grind.wins + 1 end
    if eligible then grind.eligible = grind.eligible + 1 end
    H.log(string.format("[gau] fight #%d over at f%d after %d frames " ..
      "(longest stretch without damage %d): %s, " ..
      "%d standing, battle type %s, GAU's flag %s, appearance=%s%s -- " ..
      "wins=%d eligible=%d appearances=%d, cap %d eligible", f.n, H.frame,
      H.frame - f.start, f.maxQuiet, f.won and "won" or "not won", f.standing,
      f.btype and string.format("%d", f.btype) or "?",
      f.gauFlag and "armed" or "cleared", tostring(f.appeared),
      joined and " (GAU joined)" or "", grind.wins, grind.eligible,
      grind.appearances, cap or -1))
    if joined or fed then return end
    if cap and grind.eligible >= cap then
      lose("odds", string.format("%d Veldt wins that could bring GAU (two " ..
        "standing, his flag armed) and he never came: at p=%.3f a win, " ..
        "that many without him is under %.4f -- appearances=%d.  A driver " ..
        "or detection defect, not a draw", grind.eligible, P_APPEAR,
        MISS_ODDS, grind.appearances))
    elseif cap and grind.fights >= 3 * cap then
      lose("odds", string.format("%d fights (3x the %d-win cap) and only " ..
        "%d that could bring GAU -- the fights are not ending with both " ..
        "characters standing in a normal battle", grind.fights, cap,
        grind.eligible))
    end
  end

  return H.cond(function() return true end, {
  H.driveUntil(function()
    return lost ~= nil or inParty(GAU)
  end, 400000, {
    H.call(function()
      phase = (phase + 1) % 8
      if cap == nil then
        local poolN, poolMean, never = veldtPoolOdds()
        cap = math.ceil(math.log(MISS_ODDS) / math.log(1 - P_APPEAR))
        H.log(string.format("[gau] Veldt pool: %d formations, GAU per win " ..
          "p=%.3f over the pool with battle types; never a normal battle: " ..
          "%s.  A win that can bring him (two standing, his flag armed) " ..
          "does so at p=%.3f -> give up after %d such wins without him " ..
          "(miss odds %.4f)", poolN, poolMean,
          #never > 0 and table.concat(never, ", ") or "none", P_APPEAR, cap,
          MISS_ODDS))
      end
      watch.frame()
      -- #163: the wipe watch runs before the battleLoadStarted() gate,
      -- every frame (see membersDown): a two-character wipe reads as "no
      -- battle" and the gated watch below never ran.  The run canary's
      -- count is a loss too.
      wipeN = membersDown() and wipeN + 1 or 0
      if (H.gameOverFired or 0) > 0 and not lost then
        loseWipe(string.format("GAME OVER counted by the canary in fight " ..
          "#%d at f%d [%s]", grind.fights, H.frame, partyLine()),
          F and F.lastDmg)
      end
      if wipeN >= 90 and not lost then
        loseWipe(string.format("wiped in fight #%d at f%d [%s]",
          grind.fights, H.frame, partyLine()), F and F.lastDmg)
      end
      if lost then H.setPad({}); return end
      if H.frame - hb >= 1800 then
        hb = H.frame
        H.log(string.format(
          "[gau] grind f%d fights=%d apps=%d 2f4e=%02X fed=%s sw13=%s " ..
          "tonics=%d %s", H.frame, grind.fights, grind.appearances,
          H.readByte(0x2f4e), tostring(fed), tostring(fedSwitch()),
          invCount(TONIC), F and fightLine() or ("[" .. partyLine() .. "]")))
      end
      -- the field care after a fight owns the pad until it is done (it
      -- yields on its own if a battle opens under it)
      if careD then
        if careD.done() then careD = nil
        else careD.frame(); return end
      end
      -- Gau's special appearance can flicker battleLoadStarted() false, so
      -- latch it before the ordinary battle gate -- but only inside a fight
      -- this grind opened: he appears at a fight's end, never on the world
      if not feeding and decided and gauOn() then
        feeding, feedStart = true, H.frame
        feedSubmissions, feedConfirmUntil, meatSubmitted = 0, nil, false
        grind.appearances = grind.appearances + 1
        if F then F.appeared = true end
        H.log(string.format("[gau] *** APPEARANCE #%d at fight #%d f%d",
          grind.appearances, grind.fights, H.frame))
        H.screenshot(string.format("gau_appear%d", grind.appearances))
      end
      if feeding then
        if not fed and H.frame - feedStart > FEED_FRAMES then
          lose("driver", string.format("appearance #%d in fight #%d not " ..
            "fed in %d frames: %d confirm(s) on him, meat submitted=%s, " ..
            "menu=%02X state=%02X [%s]", grind.appearances, grind.fights,
            FEED_FRAMES, feedSubmissions, tostring(meatSubmitted),
            H.readByte(MENU), H.readByte(MSTATE), partyLine()))
          H.screenshot(string.format("gau_unfed%d", grind.appearances))
          H.setPad({})
          return
        end
        if not fed and not H.battleLoadStarted() and H.worldMode()
           and H.worldHasControl() then
          -- he left and the battle closed with no meat in him: the feed
          -- did not land, which a person holding the meat would not let
          -- happen -- a driver defect, not a draw
          lose("driver", string.format("appearance #%d in fight #%d left " ..
            "unfed: back on the world at f%d (%d confirm(s) on him, meat " ..
            "submitted=%s) [%s]", grind.appearances, grind.fights, H.frame,
            feedSubmissions, tostring(meatSubmitted), partyLine()))
          H.screenshot(string.format("gau_left%d", grind.appearances))
          H.setPad({})
          return
        end
        feedDrive()
        return
      end
      if H.battleLoadStarted() then
        if not decided then
          decided = true
          plan, planActor = nil, nil
          grind.fights = grind.fights + 1
          F = { n = grind.fights, start = H.frame, lastDmg = H.frame,
                monHp = nil, missing = {}, standing = 2, won = false,
                appeared = false, logged = false, gauFlag = true,
                btype = nil, maxQuiet = 0 }
        end
        -- progress: the formation's HP.  The first live reading seeds it;
        -- only a drop counts as damage dealt.
        local nmon, mhp = liveMonsters()
        if nmon > 0 and not F.won then
          -- the engine's verdict on this fight: GAU's flag ($11E4 bit 0)
          -- and the battle type ($201F, 0 normal 1 back 2 pincer 3 side),
          -- read while the formation lives.  Once cleared the flag stays
          -- cleared until the end-of-battle roll clears it itself, and
          -- the field arms it for every Veldt battle, so the AND over the
          -- fight is the verdict whichever init frame the first read sees.
          F.gauFlag = F.gauFlag and (H.readByte(0x11E4) & 1) == 1
          F.btype = H.readByte(0x201F)
        end
        if nmon > 0 then
          if not F.logged then
            F.logged = true
            H.log(string.format("[gau] fight #%d up f%d, %d monsters %d HP: " ..
              "%s", F.n, H.frame, nmon, mhp, fightLine()))
          end
          if F.monHp ~= nil and mhp < F.monHp then
            F.maxQuiet = math.max(F.maxQuiet, H.frame - F.lastDmg)
            F.lastDmg = H.frame
          end
          F.monHp = mhp
        elseif F.monHp ~= nil and F.monHp > 0 and not F.won then
          F.maxQuiet = math.max(F.maxQuiet, H.frame - F.lastDmg)
          F.won, F.lastDmg = true, H.frame
        end
        local standing = 0
        for _, c in ipairs({ SABIN, CYAN }) do
          if aliveEntity(c) then standing = standing + 1 end
        end
        F.standing = standing
        if nmon > 0 and H.frame - F.lastDmg > NO_DAMAGE_FRAMES then
          lose("driver", string.format("fight #%d dealt no damage for %d " ..
            "frames (f%d..f%d): %s", F.n, NO_DAMAGE_FRAMES, F.lastDmg,
            H.frame, fightLine()))
          H.screenshot(string.format("gau_nodamage%d", F.n))
          H.setPad({})
          return
        end
        if H.frame - F.start > FIGHT_FRAMES then
          lose("driver", string.format("fight #%d ran past its %d-frame " ..
            "budget: %s", F.n, FIGHT_FRAMES, fightLine()))
          H.screenshot(string.format("gau_longfight%d", F.n))
          H.setPad({})
          return
        end
        tick = tick + 1
        local ph = tick % 30
        if H.readByte(MENU) == 0 then
          plan, planActor, mstreak = nil, nil, 0
          H.setPad(ph < 4 and { "a" } or {})
          return
        end
        mstreak = mstreak + 1
        if mstreak < 4 then H.setPad({}); return end
        if ph == 0 then grind.btn = button() end
        H.setPad(ph < 6 and grind.btn or {})
        return
      end
      if decided and H.worldMode() and H.worldHasControl() then
        local n = F and F.n or grind.fights
        decided = false
        closeFight()
        if lost then H.setPad({}); return end
        -- heal outside battles: the lib's between-battles care stop, with
        -- the bag's items (never MP), before the next step on the Veldt
        careD = H.newCareDriver({ tag = string.format("gau grind care " ..
          "after fight #%d", n), threshold = GRIND_CARE })
        H.setPad({})
        return
      end
      plan, planActor = nil, nil
      if not H.worldHasControl() then H.setPad({}); return end
      if not H.worldAligned() then return end
      dirFlip = not dirFlip
      H.setPad({ [dirFlip and "left" or "right"] = true })
    end),
  }, "GAU joins the party"),
  -- GAU joins inside the fight he appeared in, so that fight never reached
  -- the world: count it here, so the join line counts it too
  H.call(function()
    if lost == nil and inParty(GAU) and F then closeFight(true) end
  end),
  }, {})
end

-- ------------------------------------------------------ the retry sweep --
-- Only a lost battle reloads.  A wipe (or the canary's game over) is a
-- line in the retry inventory: the next attempt reloads the grind
-- checkpoint behind the seed sweep below, and the reload is logged in the
-- segment runner's own `[retry] attempt n/N FAILED class=wipe` shape.  A
-- stalled fight, a fight past its budget, a feed that did not land, the
-- odds cap, or a wipe after WIPE_QUIET_FRAMES without damage (lostClass
-- driver/odds) is a defect in this file's controller or its reading of the
-- game, which a fresh seed would only hide: it fails the run at once
-- (ladderLoss), and the runner files it as `other`, not retried.
--
-- The reload replays the same formation SEQUENCE whatever the attempt does
-- on the way to its first battle: the Veldt picks from $1FA5/$1FA2, which
-- move once per battle and never per step (see veldtPoolOdds).  Pacing
-- steps before it would only move WHEN the first battle fires, and so its
-- seed.  The retry varies that seed directly instead: the seed sweep
-- spreads each attempt's first battle to its own $021E phase and so its
-- own $BE seed (the battle type, every damage roll, GAU's 160/256), and
-- its report fails the run if two attempts drew the same seed.
local GRIND_ATTEMPTS = 3
local grindSeeds = H.newSeedSweep("gau grind", { attempts = GRIND_ATTEMPTS })
local GRIND_GAP = H.SEED_PERIOD // GRIND_ATTEMPTS
local grindBlob, grindWon = nil, false
local function grindAttempt(n)
  local ldReq
  return H.cond(function() return not grindWon end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[gau] ATTEMPT %d -- reloading the grind " ..
          "checkpoint after a lost battle (%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(grindBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ldReq, "attempt " .. n .. ": reload")
        -- the restored snapshot restarts the experiment: the canary's
        -- count (and its pad freeze, which the reload thaws) belong to
        -- the lost attempt (#163)
        H.gameOverFired = 0
      end),
      H.waitFrames(60),
    }, {}),
    grindSeeds.spread(n),
    H.call(function()
      clearLoss()
      fed = false
      H.gameOverFired = 0
      grind = { fights = 0, appearances = 0, wins = 0, eligible = 0 }
    end),
    grindStep(),
    H.call(function()
      ladderLoss("Veldt grind", n, GRIND_ATTEMPTS, GRIND_GAP * (n - 1))
    end),
    (function()
      local phase = 0
      return H.cond(function() return lost == nil and inParty(GAU) end, {
        H.driveUntil(function()
          return H.worldMode() and H.worldHasControl() and H.worldAligned()
        end, 20000, {
          H.call(function()
            phase = (phase + 1) % 12
            H.setPad(phase < 4 and { "a" } or {})
          end),
        }, "advance Gau's join event to the world"),
      }, {})
    end)(),
    H.call(function()
      fed = fedSwitch() or invCount(DRIED_MEAT) == 0
      if lost == nil and inParty(GAU) and fed then
        grindWon = true
        H.log(string.format("[gau] attempt %d: GAU JOINED after %d fights " ..
          "(%d wins, %d that could bring him), %d appearances, fed=%s", n,
          grind.fights, grind.wins, grind.eligible, grind.appearances,
          tostring(fed)))
      end
    end),
  }, {})
end

-- THE RELOAD-VERIFIED GENERATE (see the header).
local genBlob, genDone = nil, false
local function genAttempt(n)
  local tag = string.format("[gau_joined] generation attempt %d", n)
  local saveReq, loadReq
  return H.cond(function() return not genDone end, {
    H.call(function() saveReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(saveReq, tag .. ": capture")
      genBlob = saveReq.blob
      H.log(string.format("%s: captured %d bytes at (%d,%d) f%d -- " ..
        "reloading to verify the consumer's boot", tag, #genBlob,
        H.worldX(), H.worldY(), H.frame))
      loadReq = H.requestLoadState(genBlob)
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, tag .. ": verify reload") end),
    H.waitFrames(300),
    H.cond(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
         and H.worldX() == 214 and H.worldY() == 149
    end, {
      H.call(function()
        genDone = true
        H.log(tag .. ": reload stayed calm at the entry point -- verified")
      end),
    }, {
      H.logStep(function()
        return string.format("%s: reload NOT calm ($E8=%02X bls=%s at " ..
          "%d,%d) -- fight, re-park, recapture", tag, H.readByte(0x00e8),
          tostring(H.battleLoadStarted()), H.worldX(), H.worldY())
      end),
      (function() local W = H.newWalkFighter(tag .. ": boot battle")
        return H.driveUntil(function()
          return H.worldMode() and H.worldHasControl() and H.worldAligned()
        end, 20000, {
          H.call(function()
            if W.frame() then return end   -- fought, not fled (#183)
            H.setPad({})
          end),
        }, tag .. ": fight the boot battle, ride out the world reload") end)(),
      H.call(function() H.setPad({}) end),
      H.worldNavTo(214, 149, { maxFrames = 8000, playBattles = true }),
      H.waitFrames(30),
    }),
  }, {})
end

-- Fighting the crossing earns nothing but gil: a Veldt battle's experience
-- sum is skipped monster by monster while $11E4 bit 1 is set
-- (battle_main.asm:15778-15781), which is why the party cannot level its
-- way out of this stretch and why the answer has to be the heal rate.
local transitBlob, transitDone = nil, false
local function transitCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "shore-transit checkpoint")
      transitBlob = ckReq.blob
      H.log(string.format("[gau] shore-transit checkpoint captured " ..
        "(%d bytes) f%d [%s]", #transitBlob, H.frame, partyLine()))
    end),
  }, {})
end
local function transitAttempt(n)
  local ldReq
  local reloadSteps = {
    H.logStep(function()
      return string.format("[gau] shore transit ATTEMPT %d -- reloading " ..
        "(%s)", n, tostring(lost))
    end),
    H.call(function() ldReq = H.requestLoadState(transitBlob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ldReq, "transit attempt " .. n)
      H.gameOverFired = 0               -- the lost attempt's count (#163)
    end),
    H.waitFrames(60 + (n - 1) * 17),
  }

  -- The pacing MUST run after the `lost` reset below: worldWalkFight's
  -- terminator treats a set `lost` as done, and the first draft put the
  -- pacing inside the reload block, where attempt n-1's loss string was
  -- still live -- every jitter step "satisfied after 0 frames" and the
  -- rungs replayed identically anyway.
  -- The 12000-frame budget matches the transit segments': the accumulator
  -- is primed enough that the jitter's very first step can (and does) eat
  -- the route's opening fight, and a 3000 budget timed out inside it.
  local jitterSteps = {}
  for j = 2, n do
    jitterSteps[#jitterSteps + 1] = worldWalkFight(193, 105, 12000,
      string.format("transit a%d jitter %d out", n, j), false)
    jitterSteps[#jitterSteps + 1] = worldWalkFight(192, 105, 12000,
      string.format("transit a%d jitter %d back", n, j), false)
  end
  local steps = {
    H.cond(function() return n > 1 end, reloadSteps, {}),
    H.call(function() clearLoss(); H.gameOverFired = 0 end),
    H.cond(function() return n > 1 end, jitterSteps, {}),
  }
  -- The transit ends OFF the world (Mobliz's entrance tile loads map 157),
  -- so "still on the world" is the loop condition rather than a tile test.
  for i = 1, 20 do
    steps[#steps + 1] = H.cond(function()
      return lost == nil and H.worldMode()
    end, {
      worldWalkFight(220, 115, 12000,
        string.format("transit a%d seg %d", n, i), true,
        { segment = true }),
      H.cond(function() return lost == nil and H.worldMode() end, {
        H.fieldCare({ tag = string.format("transit a%d care %d", n, i),
                      threshold = 0.9, maxFrames = 12000 }),
      }, {}),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    if lost == nil and not H.worldMode() then
      transitDone = true
      H.log(string.format("[gau] shore transit attempt %d ARRIVED at " ..
        "Mobliz f%d [%s]", n, H.frame, partyLine()))
    elseif lost == nil then
      lose("other", string.format("transit attempt %d never reached " ..
        "Mobliz in 20 segments; at (%d,%d) f%d", n, H.worldX(), H.worldY(),
        H.frame))
    end
    ladderLoss("shore transit", n, 5, (n - 1) * 17)
  end)
  return H.cond(function() return not transitDone end, steps, {})
end

-- The staging-walk sweep: the checkpoint is cut on the live world just
-- south of Mobliz, and an attempt is the whole segmented walk -- fight one
-- battle, field-care, repeat -- ending parked at (215,119).  A lost battle
-- reloads (and logs its `[retry]` line) with the house 17-frame stagger,
-- which moves $021E 17 phases and so gives the attempt's battles their own
-- $BE seed.  It does not change which formations come:
-- on the Veldt that sequence is fixed by $1FA5/$1FA2 (veldtPoolOdds), and
-- the fighter here is the same one that crosses the whole Veldt.
local walkBlob, walkDone = nil, false
local function walkCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "staging-walk checkpoint")
      walkBlob = ckReq.blob
      H.log(string.format("[gau] staging-walk checkpoint captured " ..
        "(%d bytes) f%d", #walkBlob, H.frame))
    end),
  }, {})
end
local function walkAttempt(n)
  local ldReq
  local steps = {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[gau] staging-walk ATTEMPT %d -- reloading " ..
          "(%s)", n, tostring(lost))
      end),
      H.call(function() ldReq = H.requestLoadState(walkBlob) end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ldReq, "walk attempt " .. n)
        H.gameOverFired = 0             -- the lost attempt's count (#163)
      end),
      H.waitFrames(60 + (n - 1) * 17),
    }, {}),
    H.call(function() clearLoss(); H.gameOverFired = 0 end),
  }
  for i = 1, 30 do
    steps[#steps + 1] = H.cond(function()
      return lost == nil and not (H.worldMode() and H.worldX() == 215
         and H.worldY() == 119 and H.worldHasControl() and H.worldAligned())
    end, {
      worldWalkFight(215, 119, 12000,
        string.format("staging a%d seg %d", n, i), nil,
        { segment = true }),
      H.cond(function() return lost == nil end, {
        H.fieldCare({ tag = string.format("staging a%d care %d", n, i),
                      threshold = 0.9, maxFrames = 12000 }),
      }, {}),
    }, {})
  end
  -- no non-segmented closer here: 30 fought-and-cared segments that never
  -- parked is a walk that never arrives, which ladderLoss fails loudly
  steps[#steps + 1] = H.call(function()
    if lost == nil and H.worldMode() and H.worldX() == 215
       and H.worldY() == 119 then
      walkDone = true
      H.log(string.format("[gau] staging walk attempt %d ARRIVED f%d",
        n, H.frame))
    elseif lost == nil then
      lose("other", string.format("staging attempt %d never arrived (at " ..
        "%d,%d) f%d", n, H.worldX(), H.worldY(), H.frame))
    end
    ladderLoss("staging walk", n, 3, (n - 1) * 17)
  end)
  return H.cond(function() return not walkDone end, steps, {})
end

local ROUTE = {
  { 216, 128, "fence north" },
  { 218, 140, "east bend" },
  { 220, 149, "south bend" },
  { 219, 153, "south bend 1" },
  { 217, 155, "south bend 2" },
  { 212, 156, "south run" },
  { 205, 153, "west bend" },
  { 207, 151, "northwest bend" },
  { 214, 149, "Crescent entry point" },
}
local routeBlob, routeDone = nil, false
local function routeCheckpoint()
  local ckReq
  return H.cond(function() return true end, {
    H.call(function() ckReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ckReq, "post-join route checkpoint")
      routeBlob = ckReq.blob
      H.log(string.format("[gau] post-join route checkpoint captured " ..
        "(%d bytes) f%d", #routeBlob, H.frame))
    end),
  }, {})
end
local function routeAttempt(n)
  local ldReq
  local reloadSteps = {
    H.logStep(function()
      return string.format("[gau] post-join route ATTEMPT %d -- " ..
        "reloading (%s)", n, tostring(lost))
    end),
    H.call(function() ldReq = H.requestLoadState(routeBlob) end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(ldReq, "route attempt " .. n)
      H.gameOverFired = 0               -- the lost attempt's count (#163)
    end),
    H.waitFrames(60 + (n - 1) * 17),
  }

  -- The pacing MUST run after the `lost` reset below, for the same
  -- reason transitAttempt's does: worldWalkFight's terminator treats a
  -- set `lost` as done, and pacing inside the reload block would see
  -- attempt n-1's loss string still live and skip straight through.
  local jitterSteps = {}
  for j = 2, n do
    jitterSteps[#jitterSteps + 1] = worldWalkFight(217, 119, 12000,
      string.format("route a%d jitter %d out", n, j), nil)
    jitterSteps[#jitterSteps + 1] = worldWalkFight(219, 119, 12000,
      string.format("route a%d jitter %d back", n, j), nil)
  end
  local steps = {
    H.cond(function() return n > 1 end, reloadSteps, {}),
    H.call(function() clearLoss(); H.gameOverFired = 0 end),
    H.cond(function() return n > 1 end, jitterSteps, {}),
  }
  for w = 1, #ROUTE do
    local tx, ty, name = ROUTE[w][1], ROUTE[w][2], ROUTE[w][3]
    for i = 1, 12 do
      steps[#steps + 1] = H.cond(function()
        return lost == nil and not (H.worldMode() and H.worldX() == tx
           and H.worldY() == ty and H.worldHasControl()
           and H.worldAligned())
      end, {
        worldWalkFight(tx, ty, 12000,
          string.format("route a%d %s seg %d", n, name, i), nil,
          { segment = true }),
        H.cond(function() return lost == nil end, {
          H.fieldCare({ tag = string.format("route a%d %s care %d",
                          n, name, i),
                        threshold = 0.75, maxFrames = 12000 }),
        }, {}),
      }, {})
    end
    steps[#steps + 1] = H.call(function()
      if lost == nil and not (H.worldMode() and H.worldX() == tx
         and H.worldY() == ty) then
        lose("other", string.format("route attempt %d never reached %s " ..
          "(%d,%d) in 12 segments; at (%d,%d) f%d", n, name, tx, ty,
          H.worldX(), H.worldY(), H.frame))
      end
    end)
  end
  steps[#steps + 1] = H.call(function()
    if lost == nil then
      routeDone = true
      H.log(string.format("[gau] post-join route attempt %d ARRIVED at " ..
        "the Crescent entry point f%d [%s]", n, H.frame, partyLine()))
    else
      ladderLoss("post-join route", n, 5, (n - 1) * 17)
    end
  end)
  return H.cond(function() return not routeDone end, steps, {})
end

-- allowGameOver: the transit, grind, staging-walk and route ladders
-- deliberately survive a lost fight (#163); the walk and the grind read
-- H.gameOverFired as a loss and the next attempt reloads (a wipe after the
-- party stopped dealing damage excepted: see loseWipe).
H.run({ maxFrames = 500000, allowGameOver = true }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(mapIdx(), 159, "boot on the shore, map 159")
    H.assertEq(sw(0x3F), 1, "$003F set -- GAU met at the falls")
    H.assertEq(inParty(11), false, "GAU not yet in the party")
  end),

  -- off the shore, to Mobliz, buy the Dried Meat and the grind's Tonics
  H.navTo(8, 14, { maxFrames = 6000, playBattles = "tactical", arrive = function()
    return H.worldMode() end }),
  H.waitUntil(function() return H.worldMode() and H.worldHasControl() end,
    3000, "on the world", 5),
  H.fieldCare({ tag = "care before the Veldt crossing", threshold = 0.95,
                maxFrames = 12000 }),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 6000, "world live before the crossing", 5),
  transitCheckpoint(),
  transitAttempt(1),
  transitAttempt(2),
  transitAttempt(3),
  transitAttempt(4),
  transitAttempt(5),
  H.call(function()
    if not transitDone then
      error("gau: the Veldt transit to Mobliz was lost -- " .. tostring(lost)
        .. " (a #74-style balance finding; do not rig)", 0)
    end
    clearLoss()
  end),
  settle(157, "Mobliz"),
  H.navTo(26, 22, { maxFrames = 10000, playBattles = "tactical", arrive = function()
    return mapIdx() == 164 end }),
  H.cond(function() return mapIdx() ~= 164 end, {
    H.navTo(26, 21, { maxFrames = 3000, playBattles = "tactical", arrive = function()
      return mapIdx() == 164 end }),
  }, {}),
  settle(164, "item shop"),
  H.navTo(29, 50, { maxFrames = 6000, playBattles = "tactical" }),
  (function()
    local phase = 0
    return H.driveUntil(function() return mstateMenu() == 0x25 end, 3000, {
      H.call(function()
        phase = (phase + 1) % 8
        if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
        H.setPad(phase < 4 and { "up", "a" } or { "up" })
      end),
    }, "shop options open")
  end)(),
  tapUntil("a", inState(0x26), "buy list"),
  H.call(function()
    H.assertEq(H.readByte(0x9d89), DRIED_MEAT, "shop 12 row 0 is Dried Meat")
    H.log(string.format("[gau] shopping: gil=%d", gil()))
  end),
  tapUntil("a", inState(0x27), "quantity"),
  tapUntil("a", function()
    return invSlot(DRIED_MEAT) ~= nil and mstateMenu() == 0x26
  end, "bought", 2400),
  -- the grind's medicine, bought the verified-loop way.  Mobliz's shop 12
  -- also stocks Fenix Down at row 5 (shop_prop.dat): the route-wide revive
  -- floor, bought BEFORE the Tonic soak so a short purse shorts Tonics, not
  -- the revives.  Fenix -> 15, Tonic -> 99 are ceilings; H.buyItem
  -- purse-clamps each to the merchant's gil.
  H.call(function()
    H.assertEq(H.readByte(0x9d89 + 2), POTION, "shop 12 row 2 is Potion")
    H.assertEq(H.readByte(0x9d89 + 5), FENIX_DOWN, "shop 12 row 5 is Fenix Down")
  end),
  -- Potions are the in-combat heal, topped up at every town that sells them
  -- (docs/design/level-curve.md: ~level x1.5; L15 here -> 23).  Mobliz is
  -- the first shop after the falls and the last before the Veldt grind and
  -- Crescent Mountain, and the train merchant's stock is what the falls
  -- fight spent (#167).
  buyItem(POTION, 2, function() return 23 - invCount(POTION) end,
    "POTION to 23"),
  buyItem(FENIX_DOWN, 5, function() return 15 - invCount(FENIX_DOWN) end,
    "FENIX DOWN to 15"),
  buyItem(TONIC, 1, function() return 99 - invCount(TONIC) end, "TONIC to 99"),
  tapUntil("b", inState(0x25), "options again"),
  tapUntil("b", function() return H.hasControl() end, "shop closed", 2400),
  -- #197: the combat items back on top of the bag after every purchase
  -- (the fight driver found the Potion at row 43 downstream of a stop
  -- that did not re-arrange)
  -- Dried Meat first: prepareFeed's moveMeatToFront wants it at slot 0 for
  -- GAU's feed and gets it there by an Item-menu SWAP, which sent a Potion
  -- arranged to slot 0 to the meat's old slot at the bag's end (the trench
  -- ride steered "row 0 -> 21" to it); with the meat already first that
  -- move is skipped and the Potion rides at slot 1, one press away.
  H.bagArrange({ DRIED_MEAT, POTION, FENIX_DOWN, TONIC, ANTIDOTE, REMEDY }, { tag = "bag: combat items on top (Mobliz item shop)" }),
  H.call(function()
    H.assertEq(invSlot(DRIED_MEAT) ~= nil, true, "Dried Meat in the bag")
    H.assertEq(invCount(FENIX_DOWN) >= 6, true,
      "the party leaves Mobliz with Fenix Downs -- a death is answerable now")
    H.assertEq(invCount(POTION) >= 10, true,
      "the party leaves Mobliz with Potions -- the in-combat heal (the band's floor)")
    H.log(string.format("[gau] leaving the shop: gil=%d tonics=%d potions=%d fenix=%d",
      gil(), invCount(TONIC), invCount(POTION), invCount(FENIX_DOWN)))
  end),
  -- Prepare the feed while Mobliz is reliably menu-capable.  The Veldt
  -- staging tile can remain field-menu hostile briefly after a random battle.
  prepareFeed(),

  H.navTo(29, 53, { maxFrames = 4000, playBattles = "tactical", arrive = function()
    return mapIdx() == 157 end }),
  settle(157, "town again"),
  -- (18,41) is Mobliz's south exit ROW, and a row you leave a town by is a
  -- tile you STEP THROUGH, never one you come to rest on.  navTo to the
  -- entry point and press SOUTH through the row.
  H.navTo(18, 40, { maxFrames = 8000, playBattles = "tactical", arrive = function()
    return H.worldMode() end }),
  (function()
    local hb = -600
    return H.driveUntil(function() return H.worldMode() end, 1800, {
      H.call(function()
        if H.frame - hb >= 300 then
          hb = H.frame
          H.log(string.format("[gau] leaving Mobliz f%d map=%d (%d,%d) ctl=%s",
            H.frame, mapIdx(), H.fieldX(), H.fieldY(),
            tostring(H.hasControl())))
        end
        H.setPad({ down = true })
      end),
    }, "SOUTH out of Mobliz onto the world")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 3000, "world live again", 5),

  walkCheckpoint(),
  walkAttempt(1),
  walkAttempt(2),
  walkAttempt(3),
  H.call(function()
    if not walkDone then
      error(string.format("gau: the walk to the Veldt staging was lost " ..
        "on all 3 staggered attempts -- last: %s", tostring(lost)), 0)
    end
  end),

  -- the grind, with real input, behind the sweep (see the header)
  (function()
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "grind checkpoint")
        grindBlob = ckReq.blob
        H.log(string.format("[gau] grind checkpoint captured (%d bytes) f%d",
          #grindBlob, H.frame))
      end),
    }, {})
  end)(),
  grindSeeds.watch(),
  grindAttempt(1),
  grindAttempt(2),
  grindAttempt(3),
  grindSeeds.report(),
  H.call(function()
    if not grindWon then
      error(string.format("gau: the Veldt grind did not recruit GAU on " ..
        "any of 3 attempts -- last: %s", tostring(lost)), 0)
    end
    H.assertEq(fed, true,
      "the Dried Meat was fed to GAU through the real battle Item menu " ..
      "(the old 'measured undrivable' claim is retired -- see the header)")
    H.assertEq(invCount(DRIED_MEAT), 0, "the meat left the bag with GAU")
    H.assertEq(fedSwitch(), true,
      "the Dried-Meat reaction set Gau's battle switch")
  end),
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 20000, "world after the join", 5),
  H.waitFrames(120),

  -- park on Crescent Mountain's entry point (one short of the (214,148)
  -- entrance) and generate.  The route rides the ladder defined above;
  -- every Veldt encounter on it is fought by the input-driven menu fighter,
  -- one per segment, with field care between.
  routeCheckpoint(),
  routeAttempt(1),
  routeAttempt(2),
  routeAttempt(3),
  routeAttempt(4),
  routeAttempt(5),
  H.call(function()
    if not routeDone then
      error(string.format("gau: post-join walk to Crescent Mountain was " ..
        "lost on all 5 staggered attempts -- last: %s", tostring(lost)), 0)
    end
  end),
  -- The landing step itself can WIN the encounter roll ($E8 bit5 the
  -- instant it wins); require REAL control before generating, fighting
  -- any landing-roll battle (#183) -- the post-battle reload restores
  -- this tile.
  (function() local W = H.newWalkFighter("landing-roll battle at the entry point")
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned()
    end, 20000, {
      H.call(function()
        if W.frame() then return end
        H.setPad({})
      end),
    }, "calm, controllable entry point (fight any landing-roll battle)") end)(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "on the world")
    H.assertEq(H.worldX(), 214, "x=214")
    H.assertEq(H.worldY(), 149, "y=149 -- one short of the Crescent entrance")
    H.assertEq(inParty(11), true, "GAU in the party")
    H.assertEq(inParty(5), true, "SABIN in the party")
    H.assertEq(inParty(2), true, "CYAN in the party")
    H.assertEq((H.readByte(0x1EDF) & 0x08) ~= 0, true,
      "GAU in the available-characters roster")
    H.log(string.format("[gau_joined] f%d world (%d,%d)", H.frame,
      H.worldX(), H.worldY()))
    H.screenshot("gau_joined")
  end),
  genAttempt(1),
  genAttempt(2),
  genAttempt(3),
  H.call(function()
    H.assertEq(genDone, true,
      "a reload-verified calm entry point capture within 3 attempts")
    H.emitBlob("gau_joined.mss", genBlob)
  end),
  H.logStep(function()
    return string.format("gau_joined generated at frame %d world (%d,%d) -- " ..
      "GAU fed and recruited through real menus", H.frame,
      H.worldX(), H.worldY())
  end),
})
