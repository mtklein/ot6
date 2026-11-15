-- @suite slow savestate=narshe_battle
-- battle_breakwob_raiders.lua -- the Battle for Narshe's raiders' authored rows in play: from the graph's capture
-- `narshe_battle` (the defense live, three squads parked), party 1 (TERRA, EDGAR, CELES) walks gen_narshe_battle's
-- descent toward KEFKA and fights every raider that collides, with the library's fight driver on the descent's
-- options (EDGAR's AutoCrossbow, the bank of two, TERRA's care), until a fight that holds Fidor or Bounty Man is
-- over.  docs/design/break-coverage-wob.md section 15 is the design; battle_breakwob_events checks the rows as ROM
-- bytes.
--
-- Which raider meets the party is the march's (battle 22: Trooper x4, or Bounty Man and two Troopers; battle 23:
-- Fidor and a Trooper, or a HeavyArmor and two Troopers; field/event.asm EventBattle), so the walk fights whatever
-- comes until one of the two is dealt; the descent of every draw of the v0.45 lab met Fidor
-- (build/attempts/wt/v045-rows/).  Asserted from the engine's cells (gauge $3e40+2s, max $3e41+2s, broken timer
-- $3e90+2s, species $57c0+2s):
--   1. Fidor or Bounty Man opens with its authored gauge, 2 (the floor gave both 3);
--   2. the party breaks one of them (EDGAR's crossbow and pike are Fidor's point; TERRA's Fire its vanilla weakness);
--   3. the fight is won (a wipe raises).
-- Nothing writes emulated state.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/narshe_battle.mss.lua"

local AUTHORED = { [0x01C] = 2, [0x079] = 2 }     -- Fidor, Bounty Man
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

-- each fight's record; `served` is the first fight that held Fidor or Bounty Man, once it is over
local fights, cur, served = {}, nil, nil
local function watch()
  if not H.battleLoadStarted() or H.monstersPresent() == 0 then
    if cur and not H.battleLoadStarted() then
      cur.over = true
      if cur.target and not served then served = cur end
      cur = nil
    end
    return
  end
  if cur == nil then
    cur = { slots = {}, n = #fights + 1 }
    fights[#fights + 1] = cur
  end
  for s = 0, 5 do
    if (H.readByte(PRESENT + s * 2) & 1) == 1 then
      local r = cur.slots[s]
      if r == nil then
        r = { sp = H.readWord(SPECIES + s * 2), open = H.readByte(SH_MAX + s * 2) }
        cur.slots[s] = r
        if AUTHORED[r.sp] then cur.target = true end
        H.log(string.format("[raiders] fight %d slot %d: species $%03X opens with %d of %d shield(s), %d hp", cur.n,
          s, r.sp, H.readByte(SH_CUR + s * 2), r.open, H.readWord(MONHP + s * 2)))
      end
      local t = H.readByte(BRK + s * 2)
      if r.broke == nil and t ~= 0 and t ~= 0xFF then
        r.broke = H.frame
        H.log(string.format("[raiders] fight %d slot %d ($%03X) BROKEN at f%d, %d hp left", cur.n, s, r.sp, H.frame,
          H.readWord(MONHP + s * 2)))
      end
    end
  end
end

local D
local function walk(wi0, wi1)
  local wi, battN, holdF, axis, wipeN = wi0, 0, 0, 1, 0
  return H.driveUntil(function()
    if H.mapId() & 0x1FF ~= 22 and not H.battleLoadStarted() then
      error(string.format("[raiders] left map 22 outside a battle at wp %d -- a march reached BANON", wi), 0)
    end
    return served ~= nil or (wi > wi1 and H.hasControl() and H.tileAligned())
  end, 90000, {
    H.call(function()
      D = D or H.newFightDriver("raiders", DESCENT)
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
  }, string.format("the descent, waypoints %d-%d, until Fidor or Bounty Man is fought", wi0, wi1))
end

H.run({ maxFrames = 120000 }, {
  H.loadState(STATE),
  walk(1, WAY_CARE_AFTER),
  H.release(),
  H.cond(function() return served == nil end, {
    H.waitFrames(10),
    H.fieldCare({ tag = "care before the raider corridor", threshold = 0.85, mpFloor = 0.5 }),
    walk(WAY_CARE_AFTER + 1, #WAY),
    H.release(),
  }, {}),
  H.call(function()
    H.assertEq(served ~= nil, true, string.format("the descent met Fidor or Bounty Man (%d fights, none held "
      .. "either: the march dealt only Troopers and HeavyArmor)", #fights))
    local n, broke = 0, 0
    for s, r in pairs(served.slots) do
      if AUTHORED[r.sp] then
        n = n + 1
        H.assertEq(r.open, AUTHORED[r.sp], string.format("fight %d slot %d ($%03X): the gauge it opens with (its "
          .. "Ot6ShieldTbl row)", served.n, s, r.sp))
        if r.broke then broke = broke + 1 end
      end
    end
    H.assertEq(broke >= 1, true, string.format("the party broke Fidor or Bounty Man in fight %d", served.n))
    H.log(string.format("[raiders] fight %d: %d of the two's bodies, %d broken by the party; the rows hold in play",
      served.n, n, broke))
  end),
})
