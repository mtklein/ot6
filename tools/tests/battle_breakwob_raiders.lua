-- @suite slow savestate=narshe_battle
-- battle_breakwob_raiders.lua -- the Battle for Narshe's raiders' authored rows in play: from the graph's capture
-- `narshe_battle` (the defense live, three squads parked), party 1 (TERRA, EDGAR, CELES) walks gen_narshe_battle's
-- descent toward KEFKA, all of it, and fights every raider that collides, with the library's fight driver on the
-- descent's options (EDGAR's AutoCrossbow, the bank of two, TERRA's care).  docs/design/break-coverage-wob.md
-- section 15 is the design; battle_breakwob_events checks the rows as ROM bytes.
--
-- Which raider meets the party is the march's (battle 22: Trooper x4, or Bounty Man and two Troopers; battle 23:
-- Fidor and a Trooper, or a HeavyArmor and two Troopers; field/event.asm EventBattle); the descent of every draw
-- of the v0.45 lab met Fidor three times (build/attempts/wt/v045-rows/).  In a fight that holds Fidor or Bounty
-- Man the suite stages the property, the way a player who wants the break plays it: the first member whose hand
-- the body's keys take (slash|pierce: a blade, a knife, a spear or the crossbow) Fights it with every point
-- banked, held on it (aimHard), and the others Defend, unless the driver's plan is care (a heal, an item, a
-- raise), which stands.  Played, not written: the plans go through the driver's menus.  Without the staging the
-- driver's own Fire and kill order broke Fidor in the first fight in 1 of 6 distinct plays (the v045-rows review).
-- Asserted from the engine's cells (gauge $3e40+2s, max $3e41+2s, broken timer $3e90+2s, species $57c0+2s):
--   1. the descent deals Fidor or Bounty Man, and each opens with its authored gauge, 2 (the floor gave both 3);
--   2. in every such fight a keyed hand's Fight (command $00, the one member who Fights it) takes a shield;
--   3. one of them is broken across the descent's fights;
--   4. every fight is won (a wipe raises).
-- Nothing writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/narshe_battle.mss.lua"

local AUTHORED = { [0x01C] = 2, [0x079] = 2 }     -- Fidor, Bounty Man
local KEYS = 0x03                                  -- their rows' classes: slash|pierce (battle_breakwob_events)
local CMDTBL, BANK, BCHID, HP = 0x202E, 0x3E9C, 0x3ED8, 0x3BF4
local KEFKA = 0x014A
local SH_CUR, SH_MAX, BRK, SPECIES, PRESENT, MONHP = 0x3E40, 0x3E41, 0x3E90, 0x57C0, 0x3AA8, 0x3BFC
-- gen_narshe_battle's descent (its WAY), and its rest before the raider corridor
local WAY = {
  { 18, 11 }, { 18, 13 }, { 18, 16 }, { 17, 17 }, { 17, 20 },
  { 16, 21 }, { 15, 22 }, { 14, 23 }, { 13, 24 }, { 14, 26 },
  { 15, 27 }, { 16, 28 }, { 18, 28 }, { 18, 30 }, { 18, 33 },
  { 18, 34 }, { 19, 35 }, { 19, 36 },
}
local WAY_CARE_AFTER = 12
local DESCENT = { tactical = true, boost = true, bank = 2, items = true, healer = 0, healPercent = 70,
  tool = H.AUTOCROSSBOW }

-- each fight's record
local fights, cur = {}, nil
local function watch()
  if not H.battleLoadStarted() or H.monstersPresent() == 0 then
    if cur and not H.battleLoadStarted() then
      cur.over = true
      cur = nil
    end
    return
  end
  if cur == nil then
    cur = { slots = {}, n = #fights + 1 }
    fights[#fights + 1] = cur
  end
  for s = 0, 5 do
    if (H.readByte(PRESENT + s * 2) & 1) == 1 and H.readWord(SPECIES + s * 2) ~= 0xFFFF then
      local r = cur.slots[s]
      if r == nil then
        r = { sp = H.readWord(SPECIES + s * 2), open = H.readByte(SH_MAX + s * 2) }
        cur.slots[s] = r
        if AUTHORED[r.sp] then cur.target = true end
        H.log(string.format("[raiders] fight %d slot %d: species $%03X opens with %d of %d shield(s), %d hp", cur.n,
          s, r.sp, H.readByte(SH_CUR + s * 2), r.open, H.readWord(MONHP + s * 2)))
      end
      if r.open == 0 and H.readByte(SH_MAX + s * 2) ~= 0 then r.open = H.readByte(SH_MAX + s * 2) end
      local sh = H.readByte(SH_CUR + s * 2)
      if r.sh ~= nil and sh < r.sh and sh ~= 0xFF then
        local cmd = H.readByte(0xB5)
        if AUTHORED[r.sp] and cmd == 0x00 then r.chips = (r.chips or 0) + (r.sh - sh) end
        H.log(string.format("[raiders] fight %d slot %d ($%03X) shields %d -> %d, cmd $%02X atk $%02X", cur.n, s,
          r.sp, r.sh, sh, cmd, H.readByte(0xB6)))
      end
      r.sh = sh
      local t = H.readByte(BRK + s * 2)
      if r.broke == nil and t ~= 0 and t ~= 0xFF then
        r.broke = H.frame
        H.log(string.format("[raiders] fight %d slot %d ($%03X) BROKEN at f%d, %d hp left", cur.n, s, r.sp, H.frame,
          H.readWord(MONHP + s * 2)))
      end
    end
  end
end

-- the staging in a fight that holds Fidor or Bounty Man (see the header)
local function targetSlot()
  for s = 0, 5 do
    if (H.readByte(PRESENT + s * 2) & 1) == 1 and AUTHORED[H.readWord(SPECIES + s * 2)]
       and H.readWord(MONHP + s * 2) > 0 then return s end
  end
end
local function keyedHand(actor)
  local c = H.readByte(BCHID + actor * 2)
  if c > 13 then return false end
  for _, o in ipairs({ 0x1F, 0x20 }) do
    local w = H.readByte(0x1600 + 37 * c + o)
    if H.isWeapon(w) and (H.weaponClass(w) & KEYS) ~= 0 then return true end
  end
  return false
end
local function keyedMember()
  for a = 0, 3 do
    local hp = H.readWord(HP + a * 2)
    if hp > 0 and hp ~= 0xFFFF and keyedHand(a) then return a end
  end
end
local CARE = { heal = true, item = true, raise = true, revive = true, cure = true }
local function staged(self, actor, plan)
  local t = targetSlot()
  if t == nil or plan == nil or CARE[plan.kind] then return plan end
  local k = keyedMember()
  H.assertEq(k ~= nil, true, "a standing member holds a hand Fidor's and Bounty Man's keys take (slash|pierce)")
  if cur then cur.keyed = cur.keyed or k end
  if actor ~= k then
    H.log(string.format("[raiders] staged: actor %d Defends while actor %d Fights slot %d", actor, k, t))
    return { kind = "defend", reason = "staged" }
  end
  local row
  for r = 0, 3 do if row == nil and H.readByte(CMDTBL + actor * 12 + r * 3) == 0x00 then row = r end end
  H.assertEq(row ~= nil, true, "the keyed member has Fight")
  local b = math.min(3, H.readByte(BANK + actor * 2))
  H.log(string.format("[raiders] staged: actor %d Fights slot %d ($%03X) at %d BP", actor, t,
    H.readWord(SPECIES + t * 2), b))
  return { kind = "fight", row = row, boostLeft = b, aim = t, aimHard = t, reason = "staged" }
end

local D
local function walk(wi0, wi1)
  local wi, battN, holdF, axis, wipeN = wi0, 0, 0, 1, 0
  return H.driveUntil(function()
    if H.mapId() & 0x1FF ~= 22 and not H.battleLoadStarted() then
      error(string.format("[raiders] left map 22 outside a battle at wp %d -- a march reached BANON", wi), 0)
    end
    return wi > wi1 and H.hasControl() and H.tileAligned() and not H.battleLoadStarted()
  end, 90000, {
    H.call(function()
      if D == nil then
        D = H.newFightDriver("raiders", DESCENT)
        D.driver.policyPlan = staged
      end
      watch()
      wipeN = H.partyWipedInBattle() and wipeN + 1 or 0
      if wipeN >= 90 then error("[raiders] THE PARTY IS WIPED", 0) end
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        if H.formationHas({ [KEFKA] = true }) then H.setPad({}); return end
        D.frame()
        return
      end
      D.idle()
      if H.dialogWaiting() then H.setPad(H.frame % 8 < 4 and { "a" } or {}); return end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
      while wi <= wi1 and H.fieldX() == WAY[wi][1] and H.fieldY() == WAY[wi][2] do
        wi, holdF, axis = wi + 1, 0, 1
      end
      if wi > wi1 then H.setPad({}); return end
      local dx, dy = WAY[wi][1] - H.fieldX(), WAY[wi][2] - H.fieldY()
      holdF = holdF + 1
      if holdF % 40 == 0 then axis = -axis end
      if holdF > 600 then error(string.format("[raiders] stuck at (%d,%d) short of (%d,%d)", H.fieldX(), H.fieldY(),
        WAY[wi][1], WAY[wi][2]), 0) end
      local press
      if (axis > 0 and dy ~= 0) or dx == 0 then press = dy > 0 and "down" or "up"
      else press = dx > 0 and "right" or "left" end
      H.setPad({ [press] = true })
    end),
  }, string.format("the descent, waypoints %d-%d", wi0, wi1))
end

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  walk(1, WAY_CARE_AFTER),
  H.release(),
  H.waitFrames(10),
  H.fieldCare({ tag = "care before the raider corridor", threshold = 0.85, mpFloor = 0.5 }),
  walk(WAY_CARE_AFTER + 1, #WAY),
  H.release(),
  H.call(function()
    local served, bodies, broke = 0, 0, 0
    for _, f in ipairs(fights) do
      local chips, has = 0, false
      for s, r in pairs(f.slots) do
        if AUTHORED[r.sp] then
          has, bodies = true, bodies + 1
          H.assertEq(r.open, AUTHORED[r.sp], string.format("fight %d slot %d ($%03X): the gauge it opens with (its "
            .. "Ot6ShieldTbl row)", f.n, s, r.sp))
          chips = chips + (r.chips or 0)
          if r.broke then broke = broke + 1 end
        end
      end
      if has then
        served = served + 1
        H.log(string.format("[raiders] fight %d: keyed member %s, %d shield(s) taken by its Fight", f.n,
          tostring(f.keyed), chips))
        H.assertEq(chips >= 1, true, string.format("fight %d: the keyed hand's Fight (actor %s) took a shield off "
          .. "Fidor or Bounty Man", f.n, tostring(f.keyed)))
      end
    end
    H.assertEq(served >= 1, true, string.format("the descent met Fidor or Bounty Man (%d fights, none held "
      .. "either: the march dealt only Troopers and HeavyArmor)", #fights))
    H.assertEq(broke >= 1, true, string.format("Fidor or Bounty Man was broken in one of the descent's %d fights "
      .. "that held them (%d bodies)", served, bodies))
    H.log(string.format("[raiders] the descent: %d fights, %d held the two (%d bodies), %d broken; the rows hold in "
      .. "play", #fights, served, bodies, broke))
  end),
})
