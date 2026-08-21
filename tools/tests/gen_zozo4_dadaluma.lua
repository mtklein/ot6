-- gen_zozo4_dadaluma.lua -- v0.4 step 3: zozo_arrival (map 221 street) ->
-- the crane maze -> DADALUMA.  Generates dadaluma_entry.mss at (30,13),
-- one A-press from the fight, and dadaluma_won.mss on the same tile after
-- battle 69's scripted win clears him off the tower porch.
--
-- The maze (probe_climb5/9/11/15/16; every claim below was walked):
--  * The city is a directed graph once door source tiles are modeled as
--    walk-on teleports.  Flooding with doors-as-floor
--    fuses regions only a teleport connects (that error hid the route);
--    with doors as walls the islands and their only bridges appear:
--      street --P9(38,57)--> 225 --P10b(47,47)--> roof (35,54)
--      --P11a(34,50)--> the stair room --P12b(46,9)--> U1 crane roof
--      --J39 jumps west--> P17a(15,39) --> west room --> P18b(104,27)
--      --> W33 strip --J33 jumps east--> U2 --P14a(31,30)--> bridge room
--      --P15b(30,34)--> top roof (30,22) --z-loop corridor--> (30,13).
--  * The stair room is a bandit conveyor: init event _caefb8 keeps seven
--    walkers climbing its one-wide stair column (x=53, y=18..29) and the
--    top "\" beam forever, so a snapshot BFS almost never sees a clear
--    path (probe_climb8 starved on 20 straight no-paths).  The engine
--    itself queues a held direction behind a moving body, so that step is
--    driven as follow-the-queue: press the route direction for the
--    current tile and wait out whoever is standing in it.
--  * The jumps ($01B0-$01B5 = the live $1EB6 control bits, event_trigger
--    _221 + _ca95c6..): {28,y}/{25,y} high pair, {21,y}/{19,y} low pair,
--    rows y=39 and y=33, each side firing only with the facing bit
--    toward the gap set -- so a jump is "walk onto the tile holding the
--    gap direction".  Measured live (probe_climb13/16): westbound fires
--    at $1EB6=C8 (bit3 = facing left), eastbound at $82 (bit1 = right);
--    the obj_script arcs dip a row (25,40 / 28,34) and settle facing up
--    ($1EB6 bit0), which is why the twin trigger never re-fires on
--    landing.  A held direction CHAINS the whole row -- both jumps of a
--    row fire under one hold, and the row is transit only.
--  * The talk: Dadaluma's tile (30,14) seals the roof from the tower
--    porch, and (29,14)/(30,15) are $F7, which is the one prop byte
--    CheckNPCs' talk-across-a-counter extension rejects
--    (player.asm @478e), so there is no south-side talk.  The authored
--    approach is a z-level loop (probe_climb15): west along y=16 on the
--    lower level, drop to (30,17), climb the "/" beam at (31,17) (zAfter
--    flips the party to upper), then the same tiles again as upright
--    diagonals ((32,16)/(33,15)/(34,14) carry $44/$49 bridge-diag props
--    that only engage at z=1), onto the y=13 strip and west to (30,13),
--    facing DOWN at him.  That loop is the last of three tiers: the whole
--    corridor from the (30,22) landing is a switchback ladder of the same
--    shape (full measured tile dump at corridorDir below), and it is
--    driven from a script rather than pathfound, because the bridge-diag
--    tiles move differently per z, so followPath's all-z-seeded BFS
--    mispredicts the live engine there and oscillates at y=19 indefinitely
--    (measured twice, 9000-frame timeouts, x wandering 30..35).  Dadaluma's
--    (30,14) stays
--    object-occupied until the win; the scripted route never aims at it.
--  * The fight: battle 69 = formation 438 = DADALUMA $0107 + two $006C
--    sidekicks (measured words 0107 006C 006C FFFF FFFF FFFF).  The
--    post-battle event _ca5ea9 gates on battle-switch $40 exactly like
--    Kefka/Vargas: a real win despawns him (hide_obj NPC_14, $034A=0,
--    fade_in, control back on (30,13) -- the porch opens); a loss is
--    `call GameOver`.  Since issue #75 the fight is played; see the
--    fighter and retry ladder at the fight site.  This file writes no
--    emulated game state anywhere, and every mid-route encounter on the
--    climb is played by the library fighter -- see `encounters` below for
--    what blind A taps cost here and what replaced them.
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id)
  return (H.readByte(0x1E80 + math.floor(id / 8)) >> (id % 8)) & 1
end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted()
end

-- ------------------------------------------- mid-route encounters, played --
-- Every hand-rolled drive below used to fight its mid-route encounters with
-- blind A taps: tap A, which opens the command list, confirms Fight, takes
-- whatever target the cursor is already on, and pages the victory text.  The
-- file's header claimed that was enough because gen_zozo5_ramuh beats this
-- same pool on these same maps the same way.  On this party it is not.
--
-- Measured 2026-08-12 on the first step of this file, door (38,57), twice:
--
--   * from the fixture as it ships (LOCKE 69/249), the encounter at (45,55)
--     took the party from 69/120/280/233 to all zeros between f+1200 and
--     f+7800;
--   * with the care stop below healing everyone to full first, the same
--     step drew the same pool and the party went from 249/195/280/289 to
--     all zeros by f+7800 anyway.
--
-- So the HP was not the whole story here and the drive is the rest of it.
-- The comparison that settles it is gen_zozo3_clock, which walks the same
-- street with navTo's playBattles="tactical": at full HP that driver killed
-- every monster in the formation by f+4800 and finished its step in 6352
-- frames.  Blind A taps lose the fight the tactical driver wins, because
-- they never read a menu -- no boost, no item, and every swing aimed at
-- whatever the cursor happened to be on (FF6 auto-targets nothing; HANDOFF
-- records what that cost once already).
--
-- So these drives play their encounters with the library's fighter, on the
-- same options M.rideOut uses (lib/ot6_field.lua:3325-3331); bank = 3 is
-- there because a shielded monster halves damage and a broken one takes 4x
-- (ot6_break.asm:1487-1497), so the fight is won by breaking rather than
-- chipping.
--
-- AND THE THING THAT BREAKS THEM IS THE BIO BLASTER, not a weapon and not
-- AutoCrossbow.  This is the whole reason the climb kept wiping, and it was
-- authored on purpose rather than missing.  All four species this town
-- draws -- SlamDancer $052, Harvester $04e, HadesGigas $053, Gabbldegak
-- $0df -- carry an Ot6ShieldTbl row of two shields and NO class byte
-- (ot6_hud.asm:2086-2097), so no weapon and no ability any party can field
-- ever takes a shield off, and every hit lands at the shielded halving for
-- the whole fight.  The block comment over those four rows says what the
-- answer is instead: "the answer is the tool rather than the A button"
-- (:2084-2085), meaning the vanilla poison weakness all four already carry
-- (monster_prop.dat +25 = $08) and EDGAR's Bio Blaster, item $a4 -> attack
-- $7d, element $08, all enemies, 0 MP (ot6_break.asm:203-204, :279-281;
-- battle_main.asm:6577).  The same comment records the sweep that set the
-- shield counts: at 2 shields the pack breaks penultimate and the loop wins
-- 6/6, while "mashing wipes 6/6 in this town" (:2078).
--
-- newFightDriver defaults EDGAR to AutoCrossbow, which is pierce-class and
-- right nearly everywhere else on the route, and there was no way to ask it
-- for anything else until opts.tool.  So every drive on this climb was
-- fighting the town with the one Tool that cannot open it.
local BIO_BLASTER = H.BIO_BLASTER
local CELES = 6
-- Zozo's groups use every formation slot across their eight possible draws.
-- Once EDGAR's MP is below Bio Blaster's 8-MP price, every remaining action
-- is single-target; steer those confirms through the live slots instead of
-- leaving the cursor on a defeated middle Gabbldegak.  Target-mask bits are
-- the formation slots (the same measured mapping used by the N128 and Cranes
-- drivers), so the list is deliberately explicit rather than inferred from
-- screen coordinates.
local ZOZO_FOCUS = {
  { slot = 0, mask = 0x01 }, { slot = 1, mask = 0x02 },
  { slot = 2, mask = 0x04 }, { slot = 3, mask = 0x08 },
  { slot = 4, mask = 0x10 }, { slot = 5, mask = 0x20 },
}
--
-- The wipe check rides along, because a loss still has to report itself as
-- a loss.  It cannot use H.partyWiped(): out of battle that reads $1600,
-- which keeps PRE-battle HP, and in battle it defers to
-- M.partyWipedInBattle, whose first line requires M.battleLoadStarted() --
-- and that returns false the moment every slot reads 0, by its own
-- documented limit (lib/ot6.lua:463-466).  A total wipe therefore satisfies
-- neither.  What a wipe does leave, measured on both runs above, is all
-- four $3BF4 words at 0 with the Game Over event running and control never
-- returning; that held for the remaining 22000 frames of the step.  A live
-- menu also zeroes those words, which is why the event and control clauses
-- are in the test, and the 300-frame debounce is the library wipeCanary's.
local function battleHpAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
end

-- Returns a per-drive frame handler.  It answers true on a frame it has
-- taken over (a battle is up), false when the caller should get on with
-- walking.
-- onWipe: optional soft sink.  Without it a wipe is a hard FAIL (the right
-- default: an unladdered drive that wiped has nothing to recover to).  A
-- retry ladder passes one, gets the wipe line as a value instead of an
-- error, and reloads its checkpoint; after the sink fires this callback
-- goes inert (the game is on its Game Over path and only a reload helps).
local function encounters(what, onWipe)
  -- CELES is the party's prepared healer; naming her here keeps LOCKE,
  -- EDGAR and SABIN on offense.  Leaving the role implicit measured a
  -- 157-hp survivor wiping the party while every available turn queued a
  -- revive or top-up, and spent all three reserved Potions one fight prior.
  local F = H.newFightDriver(what, { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, healer = CELES, cadence = 12,
    tool = BIO_BLASTER, focus = ZOZO_FOCUS })
  local dead = 0
  local wiped = false
  return function()
    if wiped then H.setPad({}); return true end
    if battleHpAllZero() and not H.hasControl() and H.eventRunning() then
      dead = dead + 1
      if dead >= 300 then
        local msg = string.format("%s: THE PARTY IS WIPED -- all four " ..
          "battle-HP words have read 0 with the event running and no " ..
          "control for 300 consecutive frames, at (%d,%d) on map %d.  " ..
          "This is a lost fight, not a stuck walk.",
          what, H.fieldX(), H.fieldY(), map())
        if onWipe then
          wiped = true
          onWipe(msg)
          H.setPad({})
          return true
        end
        error(msg, 0)
      end
    else
      dead = 0
    end
    if H.battleLoadStarted() then
      F.frame()
      return true
    end
    F.idle()
    return false
  end
end

-- ------------------------------------------------- a care stop per step --
-- HANDOFF's rule for any walk that fights its encounters: heal BETWEEN the
-- battles, not only inside them.  In-battle healing is bounded by turns, so
-- a deeper bag cannot fix a heal RATE deficit and a field menu between
-- fights can, because it costs no battle turns.  This climb had one care
-- stop at the bottom and none after it.
--
-- Measured 2026-08-13 from a zozo_arrival at LOCKE 13 / EDGAR 14 / SABIN 14
-- / CELES 13, everyone at full HP: the party won five of this town's
-- encounters back to back and lost the sixth, in the stair room at (53,30)
-- on map 225.  It entered that fight at 189/314, 349/349, 398/398, 305/310,
-- and one SlamDancer round cost 189, 225, 234 and 223 -- so LOCKE, the one
-- who had not been topped up since the bottom of the climb, died to a round
-- everyone else survived, and the fight was then three against four.  The
-- bag's only healing item is a Tonic at 50 against that round, which is the
-- rate deficit exactly.
--
-- The stop is skipped rather than forced when the party is not settled: a
-- few of the drives below end on a scene beam or a z-loop, and a menu drive
-- launched into one of those hangs instead of healing.  A skip logs, so
-- "the stop did nothing" and "the stop never ran" do not read the same.
--
-- The 120-frame margin after `settled` is not padding.  A stop placed on the
-- frame a walk finishes can land within a few frames of a battle teardown,
-- and `settled` does not cover the menu module's own RAM: measured
-- 2026-08-13 at (29,39) on map 221, a stop opened four frames after
-- followPath ended, reached state $05, and then read the menu's on-screen
-- character list ($69..$6C) without CELES in it -- "dropping plan (caster
-- not on screen)" for a caster who was in the party the whole time.  The
-- item plan it fell back to then made no progress for its whole 24000-frame
-- budget.  Both are consistent with the list not being populated yet; that
-- is the hypothesis the margin is against, and it is unverified beyond the
-- one observation.
-- The field-menu screens ZMENUSTATE ($26) shows while a menu owns the screen
-- (ot6_field.lua's CARE_SCREENS, replicated here because it is a lib local).
-- When none of these is set the field menu is genuinely closed.
local MENU_SCREENS = {
  [0x05] = true, [0x06] = true, [0x08] = true, [0x0A] = true, [0x17] = true,
  [0x18] = true, [0x19] = true, [0x1A] = true, [0x3B] = true, [0x3D] = true,
  [0x64] = true, [0x70] = true,
}
-- careReady strengthens `settled` with "the field menu is actually closed".
-- The 120-frame margin below was sized (2026-08-13) against a plain walk-end;
-- it does NOT cover a fought-out battle VICTORY with a level-up.  #124's
-- Leo-break ROM re-rolled the battle chain, and a P9a leg that used to flee
-- now wins its fight and levels a member (measured 2026-08-20, dadaluma_entry
-- leg 4: EDGAR 354->398).  Through that longer victory teardown ZMENUSTATE
-- reads a menu screen while hasControl()/settled() briefly go true, so
-- fieldCare "opened the menu in 0 frames" onto the transient and read an
-- unpopulated on-screen character list -- "caster not on screen" for a caster
-- in the party the whole time, then its item fallback stalled the full
-- 24000-frame budget (the exact symptom the margin's own comment predicted).
-- Gating on "no menu screen" is the discriminator the fixed margin lacked; a
-- transient that never clears just skips the stop (soft), which the next leg's
-- care answers, rather than hanging the generate.
local function careReady()
  return settled() and not MENU_SCREENS[H.readByte(0x26)]
end
local function climbCare(what)
  return H.cond(function() return true end, {
    -- Wait for careReady to hold CONTINUOUSLY, not just be true once.  A won
    -- leg's victory+level-up teardown flickers careReady true in the gaps
    -- between its own screens, so a single-sample wait (plus even a 120-frame
    -- margin) returned into one of those gaps and fieldCare then opened onto
    -- the LEVEL UP! screen -- "menu open after 0 frames", an empty on-screen
    -- character list, "caster not on screen", and a 24000-frame stall
    -- (measured 2026-08-20, dadaluma_entry leg 4, EDGAR 354->398 on #124's
    -- re-rolled chain).  Requiring 90 straight ready frames does not complete
    -- until the whole teardown is gone; the internal soft cap keeps a
    -- genuinely-stuck state (a scene beam / z-loop) a SKIP, not a hang.  The
    -- pad is neutral throughout -- the teardown advances itself.
    (function()
      local calm, waited = 0, 0
      return H.driveUntil(function()
        waited = waited + 1
        calm = careReady() and calm + 1 or 0
        return calm >= 90 or waited >= 6000
      end, 8000, { H.call(function() H.setPad({}) end) },
        "climbCare settle " .. what)
    end)(),
    H.cond(careReady, {
      H.fieldCare({ tag = "care " .. what, threshold = 0.9 }),
    }, {
      H.logStep(function()
        return string.format("[care %s] SKIPPED -- not settled/menu-clear at " ..
          "(%d,%d) on map %d ($26=%02X) after the settle budget", what,
          H.fieldX(), H.fieldY(), map(), H.readByte(0x26))
      end),
    }),
  })
end

-- ----------------------------------------------- the input-driven fighter --
-- gen_narshe_battle's menu-episode machine (gen_scenario's cadence) for the
-- DADALUMA fight.  Party here is LOCKE+CELES+SABIN+EDGAR (#21's canonical
-- four); his authored row (Ot6ShieldTbl: 6 shields, PIERCE|BLUDG; ElemAdd:
-- poison-weak; 3270 HP) is exactly what they carry -- LOCKE's dagger and
-- EDGAR's spear are pierce, SABIN's fists are bludgeon, and EDGAR's Tools
-- add poison/pierce volume.  Boost banked to 2 and dumped every turn:
--     EDGAR (4), tier 2+   down A A A   Tools -> AutoCrossbow
--     SABIN (5), tier 3+   down A A A   Blitz -> Pummel (menu-picked,
--                                       battle_vargas's tools-shell list)
--     everyone else        A A          Fight, default target
local BCHID, BCHP, BCMAXHP = 0x3ed8, 0x3bf4, 0x3c1c
local MENU, ACTOR = 0x7bca, 0x62ca
local BP = 0x3e9c
local function monSpecies(i) return H.readWord(0x57c0 + i * 2) end
local function monHp(i) return H.readWord(0x3bfc + i * 2) end
local function monShields(i) return H.readByte(0x3e40 + i * 2) end
local function monPresent(i) return H.readByte(0x3aa8 + i * 2) % 2 == 1 end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(BCHP + e * 2),
      H.readWord(BCMAXHP + e * 2))
  end
  return table.concat(p, " ")
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("$%04X hp=%d sh=%d", monSpecies(i),
        monHp(i), monShields(i))
    end
  end
  return table.concat(m, " | ")
end
local function seqFor(id, tier, slot)
  local bp = H.readByte(BP + slot * 2)
  local boost = bp >= 2 and math.min(bp, 3) or 0
  local seq = {}
  for _ = 1, boost do seq[#seq + 1] = "r" end
  local function push(...)
    for _, b in ipairs({ ... }) do seq[#seq + 1] = b end
    return seq
  end
  if id == 4 and tier >= 2 then
    return push("down", "a", "a", "a")                        -- AutoCrossbow
  end
  if id == 5 and tier >= 3 then
    return push("down", "a", "a", "a")                        -- Pummel
  end
  return push("a", "a")                                       -- Fight
end
local function mkFighter(tier, tag)
  local F = { lost = nil }
  local bt = nil
  local mStreak, mSeq, mIdx, mTick, mStall = 0, nil, 1, 0, 0
  local phase = 0
  function F.frame(battN)
    phase = (phase + 1) % 8
    if battN == 3 then
      bt = { f0 = H.frame, wiped = 0 }
      local w = H.formationWords()
      H.log(string.format("[%s] battle up f%d (%04X %04X %04X %04X %04X %04X)",
        tag, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    if bt then
      bt.lastParty = partyLine()
      if battN % 300 == 0 then
        H.log(string.format("[%s] f%d party [%s] vs %s",
          tag, H.frame, partyLine(), monsterLine()))
      end
      local wiped, any = true, false
      for e = 0, 3 do
        if H.readWord(BCMAXHP + e * 2) > 0 then
          any = true
          if H.readWord(BCHP + e * 2) > 0 then wiped = false end
        end
      end
      bt.wiped = (any and wiped) and bt.wiped + 1 or 0
      if bt.wiped >= 90 and not F.lost then
        F.lost = string.format("PARTY WIPED at f%d (started f%d, %d frames " ..
          "in, tier %d) -- party [%s] vs %s", H.frame, bt.f0,
          H.frame - bt.f0, tier, partyLine(), monsterLine())
        H.log("[" .. tag .. "] " .. F.lost)
      end
    end
    if bt == nil or H.readByte(MENU) == 0 then
      mStreak, mSeq = 0, nil
      H.setPad(phase < 4 and { "a" } or {})
      return
    end
    mStreak = mStreak + 1
    if mStreak < 4 then H.setPad({}); return end
    if mSeq == nil then
      local slot = H.readByte(ACTOR) & 3
      local id = H.readByte(BCHID + slot * 2)
      mSeq, mIdx, mTick, mStall = seqFor(id, tier, slot), 1, 0, 0
      H.log(string.format("[%s] cast f%d slot=%d char=%d bp=%d seq=%s",
        tag, H.frame, slot, id, H.readByte(BP + slot * 2),
        table.concat(mSeq, ",")))
    end
    mTick = mTick + 1
    local ph = mTick % 30
    local btn
    if mIdx <= #mSeq then
      btn = mSeq[mIdx]
    elseif mStall < 2 then
      btn = "a"
    elseif mStall < 4 then
      btn = "b"
    else
      mSeq = nil
      H.setPad({})
      return
    end
    if ph < 6 then H.setPad({ [btn] = true }) else H.setPad({}) end
    if ph == 29 then
      if mIdx <= #mSeq then mIdx = mIdx + 1 else mStall = mStall + 1 end
    end
  end
  function F.idle()
    if bt then
      H.log(string.format("[%s] battle done at f%d (%d frames) -- party [%s]",
        tag, H.frame, H.frame - bt.f0, bt.lastParty or "?"))
      bt = nil
    end
    mStreak, mSeq = 0, nil
  end
  return F
end

-- ---- door-walled step model (the lib's own rules + door tiles as walls;
-- transcribed from lib/ot6.lua stepAllowed/zAfter, minus the object-map
-- test: bodies here are conveyor walkers, waited out rather than pathed
-- around) --------------------------------------------------------------
local DIRBIT = { up = 0x08, right = 0x01, down = 0x04, left = 0x02 }
local DELTA  = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 },
                 upright = { 1, -1 }, downright = { 1, 1 },
                 downleft = { -1, 1 }, upleft = { -1, -1 } }
local MOVES  = { "up", "right", "down", "left",
                 "upright", "downright", "downleft", "upleft" }
local PRESS  = { up = "up", right = "right", down = "down", left = "left",
                 upright = "right", downright = "right",
                 downleft = "left", upleft = "left" }
local function prop1(x, y) return H.readByte(0x7E7600 + H.maptile(x, y)) end
local function prop2(x, y) return H.readByte(0x7E7700 + H.maptile(x, y)) end
local function diagStep(x, y, c, press, z)
  if press ~= "left" and press ~= "right" then return nil end
  if (c & 0xC0) == 0 then return nil end
  if (c & 0x04) ~= 0 and z == 0x02 then return nil end
  local bit = (c & 0x80) ~= 0 and 0x80 or 0x40
  local mv
  if bit == 0x80 then mv = press == "right" and "downright" or "upleft"
  else                mv = press == "right" and "upright"   or "downleft" end
  local d = DELTA[mv]
  local t = prop1(x + d[1], y + d[2])
  if t == 0xF7 or (t & bit) == 0 then return nil end
  return mv
end
local function stepAllowed(x, y, move, z)
  local c = prop1(x, y)
  local press = PRESS[move]
  local diag = diagStep(x, y, c, press, z)
  if move ~= press then return move == diag end
  if diag then return false end
  local d = DELTA[move]
  local nx, ny = x + d[1], y + d[2]
  local e = prop2(x, y)
  local t = prop1(nx, ny)
  if (e & 0x0F & DIRBIT[move]) == 0 then return false end
  if (t & 0x07) == 0x07 then return false end
  if (c & 0x04) ~= 0 then
    if (z & 0x01) ~= 0 then
      if (t & 0x02) ~= 0 then return false end
    else
      if (t & 0x01) ~= 0 then return false end
    end
  elseif (t & 0x03) == 0x03 then
  elseif (c & 0x03) == 0x03 then
    if (t & 0x04) ~= 0 then return false end
  elseif (((c & 0x03) ~ 0x03) & (t & 0x03)) ~= 0 then
    return false
  end
  return true
end
local function zAfter(x, y, z)
  local c = prop1(x, y)
  if (c & 0x07) >= 0x03 then return z end
  return c & 0x03
end
local function key(x, y) return y * 256 + x end
local ZS = { 0, 1, 2, 3 }
-- every short-entrance source on each map (short_entrance.dat _221/_225)
local DOORS221 = { {13,21},{23,17},{42,28},{43,24},{44,48},{44,41},{49,38},
  {54,35},{38,57},{35,53},{34,50},{30,42},{35,33},{31,30},{30,21},{35,15},
  {15,39},{12,36},{49,31},{33,9} }
local DOORS225 = { {12,44},{11,17},{21,15},{52,57},{47,47},{59,35},{46,9},
  {118,27},{104,27},{83,62},{124,56},{98,62},{110,55},{66,57},{11,62},
  {30,62},{30,34},{35,14} }
local function doorSet(list)
  local s = {}
  for _, d in ipairs(list) do s[key(d[1], d[2])] = true end
  return s
end
local W221, W225 = doorSet(DOORS221), doorSet(DOORS225)

local function firstStep(sx, sy, tx, ty, walls)
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local function nkey(x, y, z) return (z << 16) | (y << 8) | x end
  local seen, q, qi = {}, {}, 1
  for _, z in ipairs(ZS) do
    seen[nkey(sx, sy, z)] = true
    q[#q + 1] = { sx, sy, z, nil }
  end
  while qi <= #q do
    local x, y, z, f = q[qi][1], q[qi][2], q[qi][3], q[qi][4]
    qi = qi + 1
    if x == tx and y == ty then return f end
    local zn = zAfter(x, y, z)
    for _, mv in ipairs(MOVES) do
      local d = DELTA[mv]
      local nx, ny = x + d[1], y + d[2]
      if nx >= 0 and ny >= 0 and nx <= xm and ny <= ym
         and (not walls[key(nx, ny)] or (nx == tx and ny == ty)) then
        local k = nkey(nx, ny, zn)
        if not seen[k] and stepAllowed(x, y, mv, z) then
          seen[k] = true
          q[#q + 1] = { nx, ny, zn, f or mv }
        end
      end
    end
  end
  return nil
end

-- walk to (tx,ty) recomputing the door-walled first step each aligned
-- frame; a body on the next tile just holds the press until it moves.
-- opts.arriveMap terminates on the map flip (door targets); extraWalls
-- adds tiles (Dadaluma's body) to the wall set.
local function followPath(tx, ty, opts)
  opts = opts or {}
  local extra = {}
  for _, w in ipairs(opts.extraWalls or {}) do extra[key(w[1], w[2])] = true end
  local hb, foughtOne = 0, false
  local fought = encounters(string.format("followPath (%d,%d)", tx, ty))
  return H.driveUntil(function()
    if opts.arriveMap then
      if map() == opts.arriveMap then H.setPad({}); return true end
    elseif H.fieldX() == tx and H.fieldY() == ty and H.tileAligned() then
      H.setPad({})
      return true
    end
    -- A long door approach can draw several fights.  Let its caller stop
    -- after each win, use the field menu, then resume; otherwise a monster's
    -- final round can leave a victorious party at single-digit HP and the
    -- very next encounter begins before the care stop at the door.
    if opts.stopAfterBattle and foughtOne and settled() then
      H.setPad({})
      return true
    end
    return false
  end, opts.maxFrames or 20000, {
    H.call(function()
      hb = hb + 1
      if hb % 600 == 0 then
        -- Say WHY a stalled walk is stalled.  A bare position heartbeat
        -- reports the same line for "no path found", "no control" and
        -- "walking into a body", and the three want different repairs;
        -- reading that absence as information cost a diagnosis once
        -- (dadaluma_entry, 2026-08-12).
        local walls0 = map() == 221 and W221 or W225
        local mv0 = H.tileAligned()
          and firstStep(H.fieldX(), H.fieldY(), tx, ty, walls0) or nil
        -- The raw $3BF4 words, not H.partyHp()'s reading of them: an
        -- all-zero table is how a wipe presents, and battleLoadStarted()
        -- calls that "no battle" by its own documented limit
        -- (lib/ot6.lua:463-466), so btl=false here means either "back on
        -- the field" or "everybody is dead" and only the words separate them.
        local raw = {}
        for e = 0, 3 do raw[#raw + 1] = string.format("%04X",
          H.readWord(0x3BF4 + e * 2)) end
        H.log(string.format(
          "[path] ->(%d,%d) f+%d at (%d,%d) map=%d ctl=%s align=%s dlg=%s "
          .. "btl=%s ev=%s step=%s bhp=%s", tx, ty, hb, H.fieldX(), H.fieldY(),
          map(), tostring(H.hasControl()), tostring(H.tileAligned()),
          tostring(H.dialogWaiting()), tostring(H.battleLoadStarted()),
          tostring(H.eventRunning()), tostring(mv0), table.concat(raw, ",")))
      end
      if fought() then foughtOne = true; return end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then return end
      local walls = map() == 221 and W221 or W225
      if next(extra) then
        local merged = {}
        for k in pairs(walls) do merged[k] = true end
        for k in pairs(extra) do merged[k] = true end
        walls = merged
      end
      local mv = firstStep(H.fieldX(), H.fieldY(), tx, ty, walls)
      if not mv then H.setPad({}); return end
      H.setPad({ [PRESS[mv]] = true })
    end),
  }, string.format("followPath (%d,%d)", tx, ty))
end

local function door(sx, sy, destMap, what)
  local legs = {}
  -- Eight encounter-sized legs is well above the four measured on the
  -- longest street approach.  Each leg returns after one battle and heals;
  -- once the door has loaded, the remaining conditional legs are skipped.
  for n = 1, 8 do
    legs[#legs + 1] = H.cond(function() return map() ~= destMap end, {
      followPath(sx, sy, { arriveMap = destMap, maxFrames = 30000,
                           stopAfterBattle = true }),
      climbCare(string.format("during %s (leg %d)", what, n)),
    }, {})
  end
  legs[#legs + 1] = H.cond(function() return map() ~= destMap end, {
    followPath(sx, sy, { arriveMap = destMap, maxFrames = 30000 }),
  }, {})
  legs[#legs + 1] = H.call(function()
    H.assertEq(map(), destMap, what .. ": reached the destination map")
  end)
  legs[#legs + 1] = H.waitUntil(settled, 2400, what .. " settled", 5)
  -- door loads finalize the decompressed prop table LATE (gen_zozo2's
  -- measured rule); settle before any pathfinding reads it
  legs[#legs + 1] = H.waitFrames(150)
  legs[#legs + 1] = H.logStep(function() return string.format(
    "%s: landed map %d (%d,%d)", what, map(), H.fieldX(), H.fieldY()) end)
  return H.cond(function() return true end, {
    table.unpack(legs),
  })
end

-- THE WEST-ROOM CROSSING (map 225): the party lands at (118,26) from door
-- 221(15,39) and must reach the exit door (104,27)->221 (the W33 strip).  This
-- step is why `followPath` timed out (measured twice + probe_westroom.lua):
--  * The two chambers of the west room connect ONLY through a "\" diagonal
--    beam (111,15)->(110,14)->(109,13)->(108,12); a cardinal-only door-walled
--    BFS finds NO path, and (104,27)'s only non-door neighbour is (104,26),
--    reachable solely from the beam top.  followPath's all-z BFS *does* route
--    over the beam, but drives it WRONG:
--  * Stepping onto (111,15) fires a ONE-SHOT SCENE (screen fade, the party's
--    z flips 2->3).  It MUST be ridden with A -- holding/pulsing a DIRECTION
--    into it hangs control forever (measured: 6000+ frames frozen, ev stuck
--    true).  With A it completes in ~900 frames and returns control at z=3.
--  * At z=3 the beam is traversable up-left across the gap; dropping onto the
--    left chamber's flat `02` floor restores z=2 for the descent to the door.
-- So it is a hand-coded per-tile table (gen_opera5/corridorFollow precedent),
-- canStep-gated on the LIVE z, that A-mashes any scene/dialog and walks the
-- table otherwise.  Verified end-to-end by probe_westroom.lua (lands map 221).
local WESTROOM = {}
local function wr(x, y, dir) WESTROOM[key(x, y)] = dir end
for yy = 16, 26 do wr(118, yy, "up") end               -- climb the x=118 column
for xx = 113, 117 do wr(xx, 15, "left") end            -- west along y=15
wr(118, 15, "left"); wr(112, 15, "left")
wr(111, 15, "upleft"); wr(110, 14, "upleft")           -- the beam (z=3 post-scene)
wr(109, 13, "upleft"); wr(108, 12, "left")
wr(107, 12, "down"); wr(107, 13, "down"); wr(107, 14, "down"); wr(107, 15, "left")
wr(106, 15, "down"); wr(106, 16, "left"); wr(105, 16, "left"); wr(104, 16, "down")
for yy = 17, 26 do wr(104, yy, "down") end             -- (104,26) -> door (104,27)
-- stopPred: nil = the whole crossing (drive until map 221); a predicate
-- stops the table-drive early on map 225 -- the #84 chest detour below
-- pauses the descent at (104,16), the left chamber's floor, and a second
-- westRoomCross() resumes the same table to the door.
local function westRoomCross(stopPred, label)
  local hb = 0
  local fought = encounters("westRoomCross")
  local donePred = stopPred or function() return map() == 221 end
  return H.cond(function() return true end, {
    H.driveUntil(function() return donePred() end, 30000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format("[westroom] f+%d at (%d,%d) z%d", hb,
            H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3))
        end
        if fought() then return end
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        -- the (111,15) scene: RIDE it with A -- a direction press here hangs
        if not H.hasControl() or H.eventRunning() then
          H.setPad(hb % 8 < 4 and { "a" } or {}); return
        end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local dir = WESTROOM[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, label or "west room -> (104,27) exit"),
    H.waitUntil(settled, 2400, "W33 strip settled", 5),
    H.waitFrames(150),
    H.logStep(function() return string.format(
      "westRoomCross: landed map %d (%d,%d)", map(), H.fieldX(), H.fieldY()) end),
  })
end

-- THE BRIDGE-ROOM APPROACH (map 221): after the J33 jump the party is at
-- ~(28,33) and must reach the door (31,30)->225.  followPath timed out here
-- too: the route climbs a "/" z-loop beam (tiles $41/$44/$49 at
-- (31,35)->(34,32), the same motif corridorFollow drives for (30,22)->(30,13)),
-- and followPath's all-z BFS mispredicts the live z across the beam.  A single
-- door-walled BFS is z-consistent (probe_bridge.lua, identical route at every
-- seed z), so this is a canStep-gated per-tile table like corridorFollow.
local BRIDGE = {}
local function br(x, y, dir) BRIDGE[key(x, y)] = dir end
br(28, 33, "right"); br(29, 33, "right"); br(30, 33, "down"); br(30, 34, "down")
br(30, 35, "right")                                    -- into the "/" beam base
br(31, 35, "upright"); br(32, 34, "upright"); br(33, 33, "upright"); br(34, 32, "up")
br(34, 31, "left"); br(33, 31, "left"); br(32, 31, "left"); br(31, 31, "up")  -- -> (31,30) door
local function bridgeCross()
  local hb = 0
  local fought = encounters("bridgeCross")
  return H.cond(function() return true end, {
    H.driveUntil(function() return map() == 225 end, 24000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format("[bridge] f+%d at (%d,%d) z%d", hb,
            H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3))
        end
        if fought() then return end
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local dir = BRIDGE[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, "bridge room approach -> (31,30) exit"),
    H.waitUntil(settled, 2400, "bridge room settled", 5),
    H.waitFrames(150),
    H.logStep(function() return string.format(
      "bridgeCross: landed map %d (%d,%d)", map(), H.fieldX(), H.fieldY()) end),
  })
end

-- THE BRIDGE-ROOM CLIMB (map 225): from (30,61) up to the door (30,34)->221
-- (top roof).  The direct x=30 column is z-split; the real route is a 50-step
-- SWITCHBACK LADDER over "/" ($43/$4B) and "\" ($83/$8B) z-loop beams
-- (probe_westroom.lua solve; a single-live-z door-walled BFS gives the same
-- route, verified probe_climb_suppress.lua).  The table below IS correct and
-- reaches (30,34) at z=2 every tier.
--
-- THE REAL BLOCKER WAS A HANGING RANDOM ENCOUNTER, NOT A WARP (sixth pass,
-- probe_climb_dump/live/stall/suppress).  The v0.5 fifth-pass diagnosis --
-- "(30,41) is a corrupting warp that chains 225->5->18->19, the Narshe intro"
-- -- was WRONG.  Measured facts that overturn it:
--   * (30,41) has p1=$43, byte-identical to (30,57) which the party crosses
--     fine one tier below; it is NEITHER a short/long entrance (all 22
--     map-225 records decode to map 221, none at (30,41)) NOR an event
--     trigger (map 225 has exactly 3: the clock {98,59} and
--     {125,46}/{103,55}).
--   * Stepping (29,41)->(30,41) rolls a RANDOM ENCOUNTER: the event PC jumps
--     to $CA0029 = inside RandBattle ($CA0018).  On this ambiguous-z beam the
--     party sprite's z oscillates 0/2/3 and the pre-battle scroll_obj never
--     settles, so the encounter HANGS at $CA0029 forever -- battleLoadStarted
--     never latches (so the battle-clear write can't fire it) and both
--     A-mash and a neutral pad leave it stuck.  Riding that hang under A is
--     what the fifth pass mis-rode into the intro maps.
-- THE input-driven crossing (issue #75 -- the old fix wrote $1f6e/$1f6f to 0
-- every frame, suppressing the roll; a generator script may never write game
-- state, so that is gone).  What replaced it is what a cautious PLAYER
-- can actually do, informed by the same mechanism (battle.asm:350-388):
-- every step adds the map's rate to the 16-bit accumulator $1f6e, a
-- battle-RNG byte is compared against its HIGH byte $1f6f, and a win
-- ZEROES the counter -- so the roll probability right after any fight is
-- as low as it ever gets.  So each climb attempt:
--   1. BURNS the pending encounter at the BASE, on flat ground: pace
--      (30,61)<->(30,60) until the roll fires on a safe tile, then FIGHT
--      it with the route's tactical battle driver.  The counter is now zero.
--   2. climbs the BRIDGE2 ladder immediately, watching for the hang
--      signature (control lost, no battle latch, position frozen, the
--      event PC inside RandBattle) -- a roll that lands on one of the
--      ambiguous-z beams anyway.
--   3. a hang or an in-climb loss RELOADS the pre-climb checkpoint (the
--      generator's spelling of a player reloading a save) and goes
--      again; the burn pacing itself reshuffles every subsequent roll.
-- Five attempts; if all five hang, the generation FAILS with the full
-- characterization on the record -- that outcome is the product bug the
-- header describes (a human player crossing this shaft can hit the same
-- un-settleable encounter and softlock), and it must be fixed game-side,
-- not scripted around.  A held direction into a beam base still must not
-- outlive its step, so the walker pulses the pad like corridorFollow.
local BRIDGE2 = {}
do
  local seq = {
    { 30, 61, "up" }, { 30, 60, "up" }, { 30, 59, "left" }, { 29, 59, "up" },
    { 29, 58, "up" }, { 29, 57, "right" }, { 30, 57, "upright" }, { 31, 56, "upright" },
    { 32, 55, "upright" }, { 33, 54, "upright" }, { 34, 53, "upright" }, { 35, 52, "upright" },
    { 36, 51, "right" }, { 37, 51, "up" }, { 37, 50, "up" }, { 37, 49, "left" },
    { 36, 49, "upleft" }, { 35, 48, "upleft" }, { 34, 47, "upleft" }, { 33, 46, "upleft" },
    { 32, 45, "upleft" }, { 31, 44, "upleft" }, { 30, 43, "left" }, { 29, 43, "up" },
    { 29, 42, "up" }, { 29, 41, "right" }, { 30, 41, "upright" }, { 31, 40, "upright" },
    { 32, 39, "upright" }, { 33, 38, "upright" }, { 34, 37, "upright" }, { 35, 36, "upright" },
    { 36, 35, "upright" }, { 37, 34, "upright" }, { 38, 33, "upright" }, { 39, 32, "right" },
    { 40, 32, "up" }, { 40, 31, "left" }, { 39, 31, "left" }, { 38, 31, "left" },
    { 37, 31, "left" }, { 36, 31, "left" }, { 35, 31, "left" }, { 34, 31, "left" },
    { 33, 31, "down" }, { 33, 32, "down" }, { 33, 33, "left" }, { 32, 33, "left" },
    { 31, 33, "left" }, { 30, 33, "down" },   -- (30,33) -> door (30,34)
  }
  for _, s in ipairs(seq) do BRIDGE2[key(s[1], s[2])] = s[3] end
end
local climbBlob, climbDone = nil, false
local climbFail = nil
local function hangLine(tag)
  return string.format("%s at f%d: map=%d tile=(%d,%d) z=%d danger=$%04X " ..
    "ctl=%s batt=%s dlg=%s ev=%s evPC=%02X:%02X%02X", tag, H.frame, map(),
    H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3, H.readWord(0x1f6e),
    tostring(H.hasControl()), tostring(H.battleLoadStarted()),
    tostring(H.dialogWaiting()), tostring(H.eventRunning()),
    H.readByte(0x00e7), H.readByte(0x00e6), H.readByte(0x00e5))
end
-- one pace-burn: walk (30,61)<->(30,60) until a battle fires ON FLAT
-- GROUND, fight it with real input, and settle.  Bounded; a base that never
-- rolls within the budget just proceeds with whatever the counter holds.
local function burnStep()
  local hb, fought = 0, false
  local play = encounters("bridge2 burn")
  return H.driveUntil(function()
    return (fought and settled()) or (not fought and hb > 6000 and settled())
  end, 12000, {
    H.call(function()
      hb = hb + 1
      if H.battleLoadStarted() then fought = true end
      if play() then return end
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      if fought then H.setPad({}); return end
      H.setPad({ [H.fieldY() >= 61 and "up" or "down"] = true })
    end),
  }, "burn the pending encounter on flat ground")
end
local function climbBody(n)
  local hb, stuckN, lx, ly = 0, 0, -1, -1
  local battN = 0
  return H.driveUntil(function()
    return map() == 221 or climbFail ~= nil
  end, 40000, {
    H.call(function()
      hb = hb + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if hb % 600 == 0 then
        H.log(string.format("[bridge2] f+%d at (%d,%d) z%d ctl=%s danger=$%04X",
          hb, H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3,
          tostring(H.hasControl()), H.readWord(0x1f6e)))
      end
      if hb > 30000 then
        climbFail = hangLine("[bridge2] attempt " .. n .. " TIMED OUT")
        H.log(climbFail)
        return
      end
      -- the hang signature: no control, no battle latch, no dialog, the
      -- party frozen in place for 900 straight frames.  A real battle
      -- entry latches battleLoadStarted within dozens of frames and a
      -- post-battle fade returns control within ~150; nothing legitimate
      -- on this ladder goes quiet for 900.
      local x, y = H.fieldX(), H.fieldY()
      local frozen = (x == lx and y == ly and not H.hasControl()
        and not H.battleLoadStarted() and not H.dialogWaiting())
      lx, ly = x, y
      stuckN = frozen and stuckN + 1 or 0
      if stuckN >= 900 then
        climbFail = hangLine("[bridge2] attempt " .. n ..
          " HUNG (the un-settleable beam encounter)")
        H.log(climbFail)
        H.screenshot("bridge2_hang" .. n)
        return
      end
      if battN >= 3 then
        if battN == 3 then
          local w = H.formationWords()
          H.log(string.format("[bridge2] in-climb battle at (%d,%d) f%d " ..
            "(%04X %04X %04X %04X %04X %04X) -- fighting", x, y, H.frame,
            w[1], w[2], w[3], w[4], w[5], w[6]))
        end
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() or H.eventRunning() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      local dir = BRIDGE2[key(x, y)]
      if dir and H.canStep(x, y, dir) then
        H.setPad({ [PRESS[dir]] = true })
      else
        H.setPad({})
      end
    end),
  }, "bridge room climb -> (30,34) exit, attempt " .. n)
end
-- Reloading a savestate and replaying identical input replays the
-- identical outcome -- the emulator is deterministic -- so each ladder
-- attempt VARIES ITS INPUT: (n-1)*2 extra pace steps between the burn and
-- the climb.  The battle RNG advances once per step (UpdateBattleRng,
-- battle.asm:385), so the extra steps reshuffle every subsequent roll
-- along the ladder at the cost of a whisper of danger.
local function jitterStep(k)
  local moves, lx, ly = 0, nil, nil
  return H.cond(function() return k > 0 end, {
    H.driveUntil(function() return moves >= k end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then
          H.setPad(H.frame % 8 < 4 and { "a" } or {})   -- fought if rolled
          return
        end
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if lx ~= nil and (x ~= lx or y ~= ly) then moves = moves + 1 end
        lx, ly = x, y
        H.setPad({ [y >= 61 and "up" or "down"] = true })
      end),
    }, "jitter " .. k .. " steps"),
    H.call(function() H.setPad({}) end),
  }, {})
end
-- NOTE: this ladder (climbAttempt/burnStep/jitterStep/climbBody) is not on
-- the live route today -- the run list crosses the shaft with bridgeClimb(),
-- which treats any in-shaft encounter as a product regression.  The ladder
-- is kept as the fallback for a shaft that rolls encounters again, and
-- attempt 1 now captures the checkpoint its reload path loads: before this,
-- climbBlob was declared and reloaded but never assigned, so any attempt
-- past the first would have called requestLoadState(nil).
local function climbAttempt(n)
  local ldReq, ckReq
  return H.cond(function() return not climbDone end, {
    H.cond(function() return n == 1 end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "pre-climb checkpoint")
        climbBlob = ckReq.blob
      end),
    }, {}),
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[bridge2] ATTEMPT %d -- reloading the " ..
          "pre-climb checkpoint (%s)", n, tostring(climbFail))
      end),
      H.call(function() ldReq = H.requestLoadState(climbBlob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(ldReq, "climb attempt " .. n) end),
      H.waitFrames(60),
    }, {}),
    H.call(function() climbFail = nil end),
    burnStep(),
    jitterStep((n - 1) * 2),
    H.logStep(function()
      return string.format("[bridge2] burned; danger=$%04X -- climbing " ..
        "(attempt %d)", H.readWord(0x1f6e), n)
    end),
    climbBody(n),
    H.cond(function() return climbFail == nil end, {
      H.waitUntil(settled, 2400, "top roof settled", 5),
      H.waitFrames(150),
      H.call(function()
        climbDone = true
        H.log(string.format("[bridge2] attempt %d landed map %d (%d,%d)",
          n, map(), H.fieldX(), H.fieldY()))
      end),
    }, {}),
  }, {})
end
local function bridgeClimb()
  local hb, stuckN, lx, ly = 0, 0, -1, -1
  return H.cond(function() return true end, {
    H.driveUntil(function() return map() == 221 end, 30000, {
      H.call(function()
        hb = hb + 1
        local x, y = H.fieldX(), H.fieldY()
        if hb % 600 == 0 then
          H.log(string.format("[bridge2] f+%d at (%d,%d) z%d ctl=%s " ..
            "danger=$%04X", hb, x, y, H.readByte(0x00b2) & 3,
            tostring(H.hasControl()), H.readWord(0x1f6e)))
        end
        if H.battleLoadStarted() then
          error(string.format("[bridge2] product regression: a random battle " ..
            "started inside map 225's protected shaft at (%d,%d)", x, y), 0)
        end
        local frozen = x == lx and y == ly and not H.hasControl()
          and not H.dialogWaiting()
        lx, ly = x, y
        stuckN = frozen and stuckN + 1 or 0
        if stuckN >= 900 then
          error(hangLine("[bridge2] product regression: the shaft hung"), 0)
        end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {})
          return
        end
        if not H.hasControl() or H.eventRunning() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local dir = BRIDGE2[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, "bridge room climb with protected encounter-free shaft"),
    H.waitUntil(settled, 2400, "top roof settled", 5),
    H.waitFrames(150),
    H.call(function()
      H.assertEq(map(), 221, "the protected bridge shaft reaches the top roof")
      H.log(string.format("[bridge2] crossed directly in %d frames; " ..
        "danger stayed $%04X", hb, H.readWord(0x1f6e)))
    end),
  })
end

-- THE U1 CRANE-ROOF CROSSING (map 221): from the stair room's exit door the
-- party lands at (30,43) and must reach (29,39), the J39 jump row's east
-- end.  Two prior drives both failed here and the failures are on the
-- record:
--  * followPath(29,39) oscillated on the (30..32,43) strip for its whole
--    18000-frame budget (measured 2026-08-17) -- the file's own all-z-BFS
--    hazard, on the "/" beam this crossing climbs.
--  * navTo(29,39), the wave's repair for that, walked the party OFF THE
--    REGION: navTo's BFS does not model door tiles, and its 5-step plan
--    from (30,43) crossed (30,42) -- a short-entrance source (DOORS221)
--    leading back into the stair room at 225 (47,10), from which nothing
--    on map 225 reaches (29,39).  The run died on "no path
--    (47,10)->(29,39)" after 20 retries (measured 2026-08-17, /tmp/fz4b).
--    The wave-era comment blaming "a different stair exit door" was wrong:
--    the failing run's own tile trail exits by the same 225 (46,9) door to
--    the same (30,43) landing the passing pre-wave run used.
-- So the crossing is a measured per-tile table like bridgeCross.  The tiles
-- are probe_u1route.lua's live-map BFS route from (30,43), which is
-- IDENTICAL at all four z seeds and matches the passing baseline's tile
-- trail exactly (base_regen.log, [tiles] map=221 after the stair segment,
-- (31,44)/(32,44) included): the crossing is one more of this map's z-loop
-- tiers -- $0B drop (31,44), $41 beam base (32,44), $44/$44 chain
-- (33,43)/(34,42), $49 top (35,41) -- then west along the y=40 strip and
-- north to (29,39).  The beam MUST be entered at its (32,44) base: a first
-- cut of this table walked east along y=43 instead and parked at (33,43)
-- forever, because a $44 tile's diagonal is z-suppressed at z=2
-- (player.asm's c&$04 + z==2 rule) and only stepping off the $41 base
-- flips the party to the z where the chain is alive (measured 2026-08-17:
-- 24000 frames at (33,43) z2 with canStep refusing "upright").  canStep
-- gates every move on the live z, and door (30,42) is never on the table.
local U1CROSS = {}
local function u1(x, y, dir) U1CROSS[key(x, y)] = dir end
u1(30, 43, "right"); u1(31, 43, "down"); u1(31, 44, "right")    -- to the base
u1(32, 44, "upright")                                           -- $41 base
u1(33, 43, "upright"); u1(34, 42, "upright"); u1(35, 41, "up")  -- the "/" beam
u1(35, 40, "left"); u1(34, 40, "left"); u1(33, 40, "left")
u1(32, 40, "left"); u1(31, 40, "left")
u1(30, 40, "up"); u1(30, 39, "left")                            -- -> (29,39)
local function u1Cross()
  local hb = 0
  local fought = encounters("u1Cross")
  return H.cond(function() return true end, {
    H.driveUntil(function()
      if H.fieldX() == 29 and H.fieldY() == 39 and H.tileAligned() then
        H.setPad({})
        return true
      end
      return false
    end, 24000, {
      H.call(function()
        hb = hb + 1
        if hb % 600 == 0 then
          H.log(string.format("[u1] f+%d at (%d,%d) z%d ctl=%s", hb,
            H.fieldX(), H.fieldY(), H.readByte(0x00b2) & 3,
            tostring(H.hasControl())))
        end
        if fought() then return end
        if H.dialogWaiting() then
          H.setPad(hb % 8 < 4 and { "a" } or {})
          return
        end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        local dir = U1CROSS[key(x, y)]
        if dir and H.canStep(x, y, dir) then
          H.setPad({ [PRESS[dir]] = true })
        else
          H.setPad({})
        end
      end),
    }, "U1 crane roof -> (29,39), the J39 row"),
    H.logStep(function() return string.format(
      "u1Cross: at (%d,%d) on map %d", H.fieldX(), H.fieldY(), map()) end),
  })
end

-- the stair-room conveyor: route direction as a pure function of tile
local function stairDir(x, y)
  if x == 54 and y >= 12 and y <= 14 then
    return y == 12 and { "left" } or { "up" }
  end
  if y <= 12 and x >= 46 and x <= 53 then return { "left", "upleft" } end
  if x == 53 then
    if y == 14 then return { "right" } end
    return { "up" }
  end
  if y >= 30 then
    if x < 53 then return { "right" } end
    if x > 53 then return { "left" } end
    return { "up" }
  end
  if x < 53 and y >= 13 and y <= 17 then return { "right" } end
  if x > 54 then return { "left" } end
  return { "up" }
end
-- The stair climb is a retry ladder now (the house 3 attempts): the
-- enumeration regen after the #84 wave measured a real wipe here -- the
-- shifted arrival state met a stair-room pack that killed the full-prep
-- party (HANDOFF's Zozo record: one round can exceed a whole HP bar).  An
-- attempt that wipes or stalls reloads the pre-stair checkpoint; the
-- (n-1)*29-frame stagger before the re-climb moves every subsequent battle
-- seed ($021e advances while we wait), which is what varies the draw.
--
-- MEASURED 2026-08-19 (ROM #122's battle-init cycles, dadaluma_entry.GbIX2kXB):
-- the frame stagger above did NOT vary the draw.  All three attempts entered
-- the very first stair-room fight at IDENTICAL party HP (314,349,325,363,
-- the pre-climb care stop's own top-up) against the same 392hp/shield-2
-- monster, and the opening round dealt near-identical damage every time
-- (attempt 1: 55,118,79,129; attempt 2: 55,123,83,140) -- the same near-wipe
-- opening every attempt, which is why all three then died the same way over
-- the following rounds.  This is gen_sabin_gau's lesson: encounter rolls are
-- STEP-indexed and the accumulator rides the savestate, so idle frames after
-- a reload change nothing.  Each attempt now also paces (52,30)<->(53,30)
-- -- both proven passable by attempt 1's own walked route (the stairDir
-- landing tile and the base of the stair column), and below the stair
-- column's walker band (x=53, y=18..29 per the header) so pacing there stays
-- clear of the conveyor bodies -- (n-1) times before climbing, so every
-- subsequent roll along the ladder lands on a different step index.  A
-- fight during the pacing is fine and is fought with the same tactical
-- driver as the climb itself (this town's shields need the real fighter,
-- not a blind mash -- see `encounters` above), and it must run AFTER the
-- stairFail reset below: a stale wipe string from the prior attempt reads
-- as "already done" to the pacing's own driveUntil otherwise.
local stairSaveReq, stairFail, stairDone = nil, nil, false
local function stairJitter(n)
  local pairs_ = n - 1
  local hb, moves, lx, ly = 0, 0, nil, nil
  local fought = encounters("stair jitter attempt " .. n,
    function(msg) stairFail = msg end)
  return H.cond(function() return pairs_ > 0 end, {
    H.driveUntil(function() return moves >= pairs_ * 2 or stairFail ~= nil end,
      20000, {
      H.call(function()
        hb = hb + 1
        if fought() then return end
        if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        if not H.tileAligned() then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if lx ~= nil and (x ~= lx or y ~= ly) then moves = moves + 1 end
        lx, ly = x, y
        local dir = (moves % 2 == 0) and "right" or "left"
        if H.canStep(x, y, dir) then
          H.setPad({ [H.movePress(dir)] = true })
        else
          H.setPad({})
        end
      end),
    }, "stair jitter, attempt " .. n),
    H.call(function() H.setPad({}) end),
  }, {})
end
-- One leg of the conveyor drive: walk until either the map flips (done),
-- stairFail fires (a wipe or timeout elsewhere), or this leg's own budget
-- runs out (a soft per-leg timeout -- stairFail is left nil so the caller
-- tries another leg rather than reloading over a merely slow leg) or one
-- battle has been fought and the party is settled again (stopAfterBattle,
-- followPath/door's own pattern).  A caller strings legs together with a
-- care stop between them; see stairAttempt below for why.
local function stairLeg(n, leg, foughtFn, maxFrames)
  local hb = 0
  local foughtOne = false
  return H.driveUntil(function()
    if map() == 221 or stairFail ~= nil then return true end
    if foughtOne and settled() then return true end
    return false
  end, maxFrames, {
    H.call(function()
      hb = hb + 1
      if hb % 600 == 0 then
        H.log(string.format("[stair] f+%d at (%d,%d)", hb, H.fieldX(), H.fieldY()))
      end
      if foughtFn() then foughtOne = true; return end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then return end
      local x, y = H.fieldX(), H.fieldY()
      for _, mv in ipairs(stairDir(x, y)) do
        if H.canStep(x, y, mv) then
          H.setPad({ [H.movePress(mv)] = true })
          return
        end
      end
      H.setPad({})
    end),
  }, string.format("stair conveyor leg %s, attempt %d", tostring(leg), n))
end
-- MEASURED 2026-08-19 (dadaluma_entry.Dqyzu0wc, after adding stairJitter):
-- the jitter DID de-correlate the draw (attempt 2's opening round now deals
-- 366/113/128 where the un-jittered baseline dealt 369/118/129 -- a
-- different roll), but every attempt still wiped, and not from an
-- over-healing fight: attempt 3's fatal stretch logged ZERO heal/cure/revive
-- actions across three straight battles (4 fight, 9 skill, 0 heal).  What
-- actually happened, read off the raw $3BF4 party-HP words: this single
-- continuous drive fights every stair-room encounter back to back with NO
-- care stop between them (climbCare, the pattern `door()` already uses
-- below, was never applied here) -- so attempt 2 won its first fight at
-- 55/113/79/128, was immediately dropped into a second encounter at that
-- same HP with nobody topped up, and died there; and attempt 3's roll had
-- CELES (entity 1, the sole opts.healer) die in round 1 of the FIRST fight,
-- which is worse than it sounds -- newFightDriver's makePlan gates ALL
-- healing and reviving on `actor == opts.healer` (ot6.lua:1915-1916,
-- deliberate: role-splitting a party avoids the heal-lock a shared healer
-- causes), so once the one designated healer is down, nobody else may ever
-- act to revive her for the rest of the fight, or the next one, or the one
-- after that.  Three straight uncared fights against a party that can never
-- recover a downed CELES is not a survivable draw regardless of tactics.
-- The fix is HANDOFF's rule this file already states above `climbCare`:
-- heal BETWEEN battles, not only inside them.  Unlike the in-battle healer
-- restriction, M.fieldCare is not gated to one designated caster (it tries
-- every living party member -- ot6_field.lua:2451), so a care stop after
-- each stair-room battle both tops up survivors AND can revive a downed
-- CELES with anyone's Fenix Down before the next encounter -- closing the
-- heal-lock as a side effect of the same fix that closes the missing-care
-- gap.  Legs mirror door()'s own per-leg followPath+climbCare shape.
local STAIR_LEG_FRAMES = 12000
local function stairAttempt(n)
  local fought
  local legs = {}
  for leg = 1, 5 do
    legs[#legs + 1] = H.cond(function() return map() ~= 221 and stairFail == nil end, {
      stairLeg(n, leg, function() return fought() end, STAIR_LEG_FRAMES),
      climbCare(string.format("stair attempt %d leg %d", n, leg)),
    }, {})
  end
  legs[#legs + 1] = H.cond(function() return map() ~= 221 and stairFail == nil end, {
    stairLeg(n, "final", function() return fought() end, 24000),
    H.call(function()
      if map() ~= 221 and stairFail == nil then
        stairFail = string.format("[stair] attempt %d TIMED OUT at (%d,%d)",
          n, H.fieldX(), H.fieldY())
      end
    end),
  }, {})
  -- Marking the climb done belongs IN the legs array, not after it: Lua
  -- truncates a `table.unpack(...)` that is not the LAST element of a table
  -- constructor to its first return value alone.  A first draft put this
  -- cond after `table.unpack(legs)` in the return below and it silently
  -- dropped every leg past the first -- measured 2026-08-19
  -- (dadaluma_entry.14y4UOg5): only "stair conveyor leg 1" ever ran, and
  -- stairDone latched true right after leg 1's care stop even though the
  -- party was still on map 225 at (52,30)/(54,30), which sent the U1 crossing
  -- (which assumes map 221 at (30,43)) into a 24000-frame stall with nothing
  -- in its per-tile table for that position.  This check now MUST also gate
  -- on map() == 221, not merely stairFail == nil, or a leg that exits via
  -- its OWN timeout-without-stairFail (impossible today since every leg
  -- either reaches map 221, fights, or the final leg sets stairFail on
  -- timeout -- but the gate is cheap insurance against the same class of bug).
  legs[#legs + 1] = H.cond(function() return map() == 221 and stairFail == nil end, {
    H.call(function() stairDone = true end),
  }, {})
  return H.cond(function() return not stairDone end, {
    H.cond(function() return n > 1 end, {
      H.logStep(function()
        return string.format("[stair] ATTEMPT %d -- reloading the pre-stair " ..
          "checkpoint (%s)", n, tostring(stairFail))
      end),
      H.call(function()
        local r = H.requestLoadState(stairSaveReq.blob)
        stairSaveReq.reload = r
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(stairSaveReq.reload, "stair attempt " .. n) end),
      H.waitFrames(60 + (n - 1) * 29),
    }, {}),
    H.call(function()
      stairFail = nil
      fought = encounters("stairFollow attempt " .. n,
        function(msg) stairFail = msg end)
    end),
    stairJitter(n),
    table.unpack(legs),
  }, {})
end
local function stairFollow()
  return H.cond(function() return true end, {
    H.call(function() stairSaveReq = H.requestSaveState() end),
    H.waitFrames(2),
    H.call(function() H.checkReq(stairSaveReq, "pre-stair checkpoint") end),
    stairAttempt(1), stairAttempt(2), stairAttempt(3),
    H.call(function()
      if not stairDone then
        error("the stair climb failed all three attempts -- a finding, not " ..
          "a retry candidate: " .. tostring(stairFail), 0)
      end
    end),
  })
end

-- the TOP-roof z-loop corridor, (30,22) -> (30,13): route direction(s) as
-- a pure function of tile, canStep-gated -- stairDir's pattern, for a
-- cousin of stairDir's reason.  followPath's firstStep seeds its BFS at
-- ALL FOUR z-levels (the party carries exactly one), and this corridor is
-- the one step where that lies: its bridge-diag tiles move DIFFERENTLY per
-- z (diagonal at z=1, plain floor at z=2 -- player.asm's own c&$04 + z==2
-- suppression, transcribed in diagStep above), so the phantom-z first
-- step keeps disagreeing with the live engine and the step oscillates on
-- the y=19 strip forever (measured twice: 9000-frame timeouts, x
-- wandering 30..35; it once passed on an older ROM by RNG luck).
--
-- The corridor itself, measured (p1/p2 dump of x24..40 y8..24 from
-- zozo_arrival -- the street is the same map 221, so the decompressed
-- prop tables are live there), is a THREE-TIER SWITCHBACK of the header's
-- z-loop motif.  Every tier is the same four bytes: a $0B drop tile, a
-- $41 "/" beam base (zAfter flips the party to upper stepping off it), a
-- $44/$44/$49 upright chain, and a $03 both-z strip top:
--   A: (30,22)R (31,22)D (31,23)R $41(32,23) /$44(33,22)(34,21)
--      $49(35,20) U-> y=19 strip, west (35,19)..(31,19)
--   B: (31,19)D (31,20)R $41(32,20) /$44(33,19)(34,18)
--      $49(35,17) U-> y=16 strip, west (35,16)..(30,16)
--   C: (30,16)D (30,17)R $41(31,17) /$44(32,16)(33,15)
--      $49(34,14) U-> (34,13), west along y=13 to (30,13)
--      -- tier C is exactly the header's documented loop.
-- The loop tiles (33,19)/(32,16) are stood on TWICE -- flat westbound on
-- the lower level, diagonally on the climb -- so their entry lists the
-- climb first and canStep (live z) picks: upright is dead at z=2 by the
-- bridge suppression and alive at z=1, when it is also the right move.
-- THE DRIVE PULSES THE PAD: press only while tile-aligned, clear it the
-- frame the step commits.  A direction still held at the arrival instant
-- CHAINS -- the engine latches the next step before this callback can
-- swap the pad (measured here: the step's first held right chained
-- (30,22)->(31,22)->(32,22) and parked off-route for the whole 9000-frame
-- budget).  stairFollow can hold its presses because every stairDir
-- corner is map-fenced and the column is body-throttled besides; this
-- corridor's turns are open floor ((32,22) is plain $0A), so no press may
-- outlive its own step.  Pulsing is also what keeps the one walkable
-- overshoot on the route, door (35,15) north of the y=16 strip, from
-- ever firing.  The $49 beam tops carry no east exit (p2=$0E), so the
-- diagonal chains are fenced by the map itself either way.  A tile off
-- this table (or a body on the next tile) parks the pad and waits,
-- stairFollow-style; the 300-frame heartbeat names the stuck tile.
local CORRIDOR = {}
local function corr(x, y, dirs) CORRIDOR[key(x, y)] = dirs end
corr(30, 22, { "right" })            -- tier A: hook east-south to the base
corr(31, 22, { "down" })
corr(32, 22, { "left" })             -- recovery: the measured pre-pulse
                                     -- chaining overshoot parked here
corr(31, 23, { "right" })
corr(32, 23, { "upright" })          -- $41 base: diag fires at any z
corr(33, 22, { "upright" })          -- $44
corr(34, 21, { "upright" })          -- $44
corr(35, 20, { "up" })               -- $49 top; no east exit
corr(35, 19, { "left" })             -- y=19 strip westbound (z drops to 2)
corr(34, 19, { "left" })
corr(33, 19, { "upright", "left" })  -- LOOP tile: climb at z=1, cross at z=2
corr(32, 19, { "left" })
corr(31, 19, { "down" })             -- tier B: hook south to the base
corr(31, 20, { "right" })
corr(32, 20, { "upright" })          -- $41 base
corr(34, 18, { "upright" })          -- $44 ((33,19) is the loop tile above)
corr(35, 17, { "up" })               -- $49 top
corr(35, 16, { "left" })             -- y=16 strip westbound
corr(34, 16, { "left" })
corr(33, 16, { "left" })
corr(32, 16, { "upright", "left" })  -- LOOP tile: tier C's chain
corr(31, 16, { "left" })
corr(30, 16, { "down" })             -- tier C: the header's documented loop
corr(30, 17, { "right" })
corr(31, 17, { "upright" })          -- $41 base -- "the / beam at (31,17)"
corr(33, 15, { "upright" })          -- $44 ((32,16) is the loop tile above)
corr(34, 14, { "up" })               -- $49 top -> the y=13 strip
corr(34, 13, { "left" })             -- west to the entry point
corr(33, 13, { "left" })
corr(32, 13, { "left" })             -- $44 crossed flat (z=2 here, always)
corr(31, 13, { "left" })
-- Arrival must be QUIET, not merely positioned: the map rolls random
-- encounters (gen_zozo5 measured the same on the tower porch), and the
-- first clean walk of this route rolled trash on its FINAL steps -- a
-- position-only arrive fired while the battle load was already in flight
-- ($4c mid-fade, the object map's NPC byte cleared, battleLoadStarted
-- latched), and the generated entry point booted INTO that battle, starving
-- the talk that follows (hasControl never true; measured via probe replay
-- of the contaminated state).  So the pred demands twenty straight
-- settled()  frames at (30,13) -- jumpRow's calm-counter, aimed at a tile
-- -- and a last-step roll is FOUGHT by the same battle interrupt every
-- other step carries, BEFORE the generation instead of inside it.
local function corridorFollow()
  local hb, calm = 0, 0
  local fought = encounters("corridorFollow")
  return H.driveUntil(function()
    local there = H.fieldX() == 30 and H.fieldY() == 13 and settled()
    calm = there and calm + 1 or 0
    if calm >= 20 then
      H.setPad({})
      return true
    end
    return false
  end, 18000, {
    H.call(function()
      hb = hb + 1
      if hb % 300 == 0 then
        H.log(string.format("[corridor] f+%d at (%d,%d)", hb,
          H.fieldX(), H.fieldY()))
      end
      if fought() then return end
      if H.dialogWaiting() then
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}); return end
      -- the pulse: a press must not outlive its own step (see above)
      if not H.tileAligned() then H.setPad({}); return end
      local x, y = H.fieldX(), H.fieldY()
      for _, mv in ipairs(CORRIDOR[key(x, y)] or {}) do
        if H.canStep(x, y, mv) then
          H.setPad({ [H.movePress(mv)] = true })
          return
        end
      end
      H.setPad({})
    end),
  }, "z-loop corridor -> (30,13)")
end

-- hold `dir` across a whole jump row; both of the row's facing-gated
-- triggers fire under the one hold, and the landing leaves the party
-- facing up so nothing re-fires.  pred names the far strip.
local function jumpRow(dir, pred, maxFrames, what)
  local evWas, calm, hb, lastFire = false, 0, 0, nil
  local fought = encounters(what)
  return H.cond(function() return true end, {
    H.driveUntil(function()
      local there = pred() and H.tileAligned()
      calm = there and calm + 1 or 0
      return calm >= 20
    end, maxFrames, {
      H.call(function()
        hb = hb + 1
        local ev = H.eventRunning()
        if ev and not evWas and hb - (lastFire or -100) >= 30 then
          lastFire = hb
          H.log(string.format("[jump] %s: fired at (%d,%d) $1EB6=%02X",
            what, H.fieldX(), H.fieldY(), H.readByte(0x1EB6)))
        end
        evWas = ev
        if fought() then return end
        if ev or not H.hasControl() then
          H.setPad({})
          return
        end
        H.setPad({ [dir] = true })
      end),
    }, what),
    H.call(function() H.setPad({}) end),
  })
end

H.run({ maxFrames = 400000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
    H.assertEq(sw(0x034A), 1, "$034A SET -- the gentleman waits")
    H.assertEq(sw(0x0053), 0, "$0053 clear -- the Ramuh scene has not run")
    -- The climb's whole answer to this town is in the bag rather than on
    -- anybody's hands, so check it is there.  Without it EDGAR's Tools dive
    -- finds no matching row, the fight driver drops the plan and re-plans
    -- every frame, and the drive makes no progress at all -- which reads as
    -- a stuck walk rather than as a missing item.
    H.assertEq(H.invCountOf(BIO_BLASTER) > 0, true,
      "a Bio Blaster is in the bag -- the poison every Zozo body is weak to")
  end),

  -- Top the party up before the climb starts.  Earlier versions of
  -- zozo_arrival could hand this step a badly hurt party, and both Zozo
  -- maps draw random encounters (map_prop byte +5 bit 7 set
  -- for 221 and 225, the same decode gen_zozo3_clock's header records).
  -- Measured 2026-08-12: the first encounter, eleven tiles into the first
  -- step at (45,55), killed the whole party.  A player walking into a new
  -- town at 28% would drink first.  This is not on its own enough -- the
  -- same encounter killed a full-HP party too, which is what moved these
  -- drives onto the library fighter (see `encounters`) -- but the two
  -- together are what a normal player brings to that street.
  H.fieldCare({ tag = "care before the Zozo climb", threshold = 0.95 }),

  -- Put on the gear that is already in the bag.  A player who has just been
  -- told the town is full of thugs opens the menu, and this party arrives
  -- with five empty slots and exactly five items to fill them: CELES with no
  -- body armour and no relics, and SABIN with no shield or second relic,
  -- against one LeatherArmor, one Buckler, one Star Pendant, a Peace Ring
  -- and a Black Belt sitting unused.  SABIN already wears the other Star
  -- Pendant bought for the scenario route; preserve useful inherited gear
  -- instead of taking it off merely to put it back on.  It is not cosmetic:
  -- CELES's defence is 34 where
  -- LOCKE runs 44, SABIN 45 and EDGAR 55, and she is the party's only
  -- healer, so the member most worth keeping upright is the one taking the
  -- most damage per hit.  The LeatherArmor alone is +28 defence and +19
  -- magic defence, and the Buckler +16/+10.
  --
  -- Equipped by item and never through Optimum, which is the owner's ruling
  -- (design/wob-route.md SS2) and would be wrong here anyway, since Optimum
  -- picks by attack power and none of these six has any.  None of them is a
  -- Genji Glove, Gauntlet or Merit Award either, so backing out of the
  -- Relic screen does not set the reequip flag and the game does not run
  -- Optimum behind us (CheckReequipRelics, equip.asm:2843-2850).
  --
  -- pos is the character-select row, which is party order: LOCKE 0, CELES
  -- 1, EDGAR 2, SABIN 3.  slot is 0..5 = R-Hand, L-Hand, Helmet, Armor,
  -- Relic 1, Relic 2; 4 and 5 live on a different menu and equipWeapon
  -- knows which walk to take.
  H.call(function()
    for _, it in ipairs({ { 0x84, "LeatherArmor" }, { 0x5A, "Buckler" },
                          { 0xB1, "Star Pendant" }, { 0xB2, "Peace Ring" },
                          { 0xD5, "Black Belt" } }) do
      H.assertEq(H.invCountOf(it[1]) > 0, true,
        string.format("a %s is in the bag to equip", it[2]))
    end
    H.assertEq(H.readByte(0x1600 + 37 * 5 + 0x1F + 4), 0xB1,
      "SABIN retains the scenario route's Star Pendant")
  end),
  H.equipWeapon(1, 0x84, { slot = 3, tag = "CELES LeatherArmor" }),
  H.equipWeapon(1, 0xB1, { slot = 4, tag = "CELES Star Pendant" }),
  H.equipWeapon(1, 0xB2, { slot = 5, tag = "CELES Peace Ring" }),
  H.equipWeapon(3, 0x5A, { slot = 1, tag = "SABIN Buckler" }),
  H.equipWeapon(3, 0xD5, { slot = 5, tag = "SABIN Black Belt" }),
  -- Read the slots back rather than trusting six menu drives.  A seek that
  -- timed out would have failed already, but a drive that landed on the
  -- wrong row would not, and "the menu was opened" and "the item is worn"
  -- are different claims.  $1600 + 37*c + $1F + slot, with c the character
  -- index (CELES 6, SABIN 5) rather than the party row.
  H.call(function()
    local function worn(c, s)
      return H.readByte(0x1600 + 37 * c + 0x1F + s)
    end
    for _, w in ipairs({ { 6, 3, 0x84, "CELES wears the LeatherArmor" },
                         { 6, 4, 0xB1, "CELES wears the Star Pendant" },
                         { 6, 5, 0xB2, "CELES wears the Peace Ring" },
                         { 5, 1, 0x5A, "SABIN carries the Buckler" },
                         { 5, 4, 0xB1, "SABIN wears the Star Pendant" },
                         { 5, 5, 0xD5, "SABIN wears the Black Belt" } }) do
      H.assertEq(worn(w[1], w[2]), w[3], w[4])
    end
    H.log("[zozo kit] inherited Star Pendant preserved; five empty slots " ..
      "filled from the bag")
  end),
  -- CELES and SABIN to the back row.  Physical damage taken is halved there
  -- and only a weapon swing pays for it: ExecCmd sets $B3 = $FF at the top
  -- of every command (battle_main.asm:3131-3133) and only the swing setup
  -- _c2299f clears the ignore-row bit (:7127-7133), so Tools, Blitz and
  -- Magic are row-exempt.  This is the case HANDOFF calls free: SABIN
  -- fights this town and DADALUMA with Pummel and CELES casts, so neither
  -- of them loses anything, while LOCKE stays in front because his swing is
  -- what chips DADALUMA's pierce row.  Nothing is given up against the
  -- town's own four species either, since none of them has a class key at
  -- all and no weapon of any class takes a shield off them.
  --
  -- EDGAR is already in the back row and is left there: gen_kolts put him
  -- there at the South Figaro stop because he fights with Tools, which are
  -- row-exempt.  This step asserts only LOCKE's row and logs the rest, since
  -- changing a row somebody else set deliberately is not this step's call.
  --
  -- It is here because of what a full-HP party still lost to on 2026-08-13:
  -- in the stair room at (53,30) on map 225 one round cost 269, 224, 241
  -- and 363 against maximums of 314, 349, 398 and 363, so SABIN went from
  -- full to 0 in a round, and every actor then spent every turn reviving or
  -- healing him instead of firing the Bio Blaster.  Halving the physical
  -- half of that is the cheapest thing that breaks the loop.
  H.setRows({ [5] = true, [6] = true }, { tag = "CELES and SABIN back row" }),
  H.call(function()
    for _, c in ipairs({ 5, 6 }) do
      H.assertEq((H.readByte(0x1850 + c) & 0x20) ~= 0, true,
        string.format("char %d is in the back row for the climb", c))
    end
    H.assertEq((H.readByte(0x1850 + 1) & 0x20) == 0, true,
      "LOCKE stays in front -- his swing chips DADALUMA's pierce row")
    local out = {}
    for _, c in ipairs(H.partyMembers()) do
      out[#out + 1] = string.format("c%d=%s", c,
        (H.readByte(0x1850 + c) & 0x20) ~= 0 and "back" or "front")
    end
    H.log("[zozo rows] " .. table.concat(out, " "))
  end),

  -- and top up again: six menu walks cost no HP, but the care stop above
  -- ran before them and a step between menus can still draw a fight.
  H.fieldCare({ tag = "care after the equip stop", threshold = 0.95 }),

  -- the climb.  Every step that can draw a fight is followed by a care stop
  -- (climbCare above): the party won five of this town's encounters in a row
  -- and lost the sixth with nobody topped up in between.
  door(38, 57, 225, "P9a street -> interior"),
  climbCare("after P9a"),
  door(47, 47, 221, "P10b -> roof (35,54)"),
  climbCare("after P10b"),
  door(34, 50, 225, "P11a -> stair room"),
  climbCare("after P11a"),
  followPath(52, 30, { maxFrames = 18000 }),
  climbCare("before the stair climb"),
  stairFollow(),
  H.waitUntil(settled, 2400, "U1 settled", 5),
  H.waitFrames(150),
  climbCare("after the stair climb"),
  -- u1Cross, not followPath (which oscillated on the strip) and not navTo
  -- (which walked into the (30,42) door and off the region) -- both
  -- failures and the measured baseline route are in u1Cross's header.
  u1Cross(),
  climbCare("before the J39 row"),
  jumpRow("left", function()
    return H.fieldX() <= 18 and H.fieldY() == 39
  end, 9000, "J39 row westbound"),
  -- P17a is a walk-on short entrance, and the shared navigator was measured
  -- crossing it directly (probe_climb).  The custom all-z pathfinder can
  -- instead oscillate between (14,40) and (15,40): one failed run farmed
  -- three encounters on those two tiles, killed a HadesGigas, then entered
  -- the next fight before the care stop with three casualties.  Use the
  -- live-z navigator for this door so the three-tile approach stays three
  -- tiles and the care stop below remains between encounters.
  H.navTo(15, 39, {
    arrive = function() return map() == 225 end,
    maxFrames = 30000, playBattles = "tactical", healer = CELES,
    healPercent = 60, tool = BIO_BLASTER,
  }),
  H.waitUntil(settled, 2400, "P17a -> west room settled", 5),
  H.waitFrames(150),
  H.logStep(function() return string.format(
    "P17a -> west room: landed map %d (%d,%d)",
    map(), H.fieldX(), H.fieldY()) end),
  climbCare("after P17a"),
  -- P18b: cross the west room to (104,27)->221.  followPath mispredicts +
  -- HANGS on the (111,15) scene-beam here; westRoomCross rides it (see above).
  -- #84: the clock-shelf pair (Tincture/Potion at (104,9)/(105,9)) hangs
  -- over this crossing's x=104 descent and is reachable from no other
  -- generator: zozo3's component BFS reads every adjacent tile NO PATH
  -- (probe_zozo3_chests), and only this crossing's tiles see them under the
  -- measured camera.  Pause the table-drive on the left chamber's floor,
  -- detour up the column, then resume the same table to the door.
  westRoomCross(function()
    return map() == 225 and H.fieldX() == 104 and H.fieldY() == 16
  end, "west room -> the (104,16) chest pause"),
  H.openChest{ stand = { 104, 10 }, face = "up", bit = 239,
               what = "Tincture", item = 0xEB,
               nav = { playBattles = "tactical", tool = H.BIO_BLASTER } },
  H.openChest{ stand = { 105, 10 }, face = "up", bit = 240,
               what = "Potion", item = 0xE9,
               nav = { playBattles = "tactical", tool = H.BIO_BLASTER } },
  -- back ONTO the direction table before resuming it: the table-drive
  -- presses nothing on a tile it has no entry for, and (105,10) is such a
  -- tile -- the resume stalled its whole budget there (the closing agent's
  -- west-room timeout).
  H.navTo(104, 16, { maxFrames = 8000, playBattles = "tactical",
                     tool = H.BIO_BLASTER }),
  westRoomCross(),
  climbCare("after the west room"),
  followPath(18, 33, { maxFrames = 12000 }),
  climbCare("before the J33 row"),
  jumpRow("right", function()
    return H.fieldX() >= 28 and H.fieldY() == 33
  end, 9000, "J33 row eastbound"),
  -- P14a: the "/" z-loop beam approach to (31,30) -- followPath mispredicts
  -- the live z here too; bridgeCross drives the measured table (see above).
  bridgeCross(),
  -- P15b: the bridge-room switchback ladder up to (30,34)->221.  bridgeClimb
  -- drives the measured z-loop table (correct) with random encounters SUPPRESSED
  -- -- the fifth pass's "(30,41) corrupting warp" was a mis-rode HANGING random
  -- encounter, not a warp (see bridgeClimb's header + wob-route sixth pass).
  bridgeClimb(),
  corridorFollow(),
  climbCare("at the entry point"),

  -- the entry point: one A-press from battle 69.  The extra beat plus the
  -- settled assert keep this generated savestate trustworthy: the state is
  -- the suite's boot point, so a battle-load or event in flight here
  -- poisons everything downstream (see corridorFollow's arrive note for the
  -- measured case).
  H.waitFrames(60),
  H.call(function()
    H.assertEq(map(), 221, "on the roof (map 221)")
    H.assertEq(H.fieldX() == 30 and H.fieldY() == 13, true,
      "at (30,13), north of the gentleman")
    H.assertEq(settled(), true, "entry point is QUIET -- no battle/event in flight")
    H.assertEq(sw(0x034A), 1, "$034A still set -- he waits below")
    H.log(string.format("[dadaluma_entry] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("dadaluma_entry")
  end),
  H.saveState("dadaluma_entry.mss"),

  -- face him and talk, then FIGHT battle 69 -- with real input (issue #75).
  -- _ca96a9: dlg $042D -> set_b_switch $4B -> `battle 69` -> _ca5ea9,
  -- which gates on battle-switch $40: a WIN despawns him ($034A=0, control
  -- back at (30,13)); a LOSS is `call GameOver`.  Formation 438 = DADALUMA
  -- $0107 + two $006C (verified probe_fight.lua).  The drive is the menu-
  -- episode fighter above, wrapped in a three-attempt retry ladder off the
  -- entry point just generated: a wipe reloads the entry point -- the
  -- generator script's spelling of a player reloading a save, caught BEFORE
  -- the GameOver fade -- and escalates the tier (2 adds EDGAR's
  -- AutoCrossbow, 3 adds SABIN's Pummel), which reshuffles every subsequent
  -- roll.  Outside the battle the driver still edge-A's broadly: the talk
  -- dialog, the reward and the win-tail text do NOT set the dialogWaiting
  -- latch.
  (function()
    local dadaBlob, dadaWon = nil, false
    local dadaLost = nil
    -- A STALL IS A LOSS, and it has to be one here or the ladder is not a
    -- ladder.  `F.lost` only fires on a wipe; a fight that neither wins nor
    -- wipes inside the budget used to reach driveUntil's own raise, which
    -- ends the whole run on attempt 1 and leaves attempts 2 and 3 unplayed.
    -- Measured 2026-08-13: attempt 1 lost LOCKE and EDGAR in the first four
    -- rounds, DADALUMA called his two Iron Fists, and the surviving pair
    -- ground at his 2784 of 3270 until the budget ran out -- reported as
    -- "timeout after 40000 frames", which reads as a harness fault rather
    -- than as the fight the party could not finish.  The soft limit is set
    -- under the hard one so the hard one stays a backstop.
    local function fightBody(tier)
      local F = mkFighter(tier, "dadaluma")
      local battN = 0
      local started = nil
      return H.driveUntil(function()
        if started == nil then started = H.frame end
        if F.lost then
          dadaLost = F.lost
          return true                 -- reload beats riding the GameOver
        end
        if H.frame - started >= 39000 then
          dadaLost = string.format(
            "stalled -- 39000 frames with no win and no wipe (tier %d)", tier)
          H.log("[dadaluma] " .. dadaLost)
          return true
        end
        return sw(0x034A) == 0 and map() == 221 and H.hasControl()
          and H.tileAligned() and bright() >= 15
      end, 40000, {
        H.call(function()
          battN = H.battleLoadStarted() and battN + 1 or 0
          if battN >= 3 then
            F.frame(battN)
            return
          end
          F.idle()
          H.setPad(H.frame % 8 < 4 and { "a" } or {})
        end),
      }, "Dadaluma fought (tier " .. tier .. ") -> $034A clear")
    end
    local function attempt(n)
      local ldReq
      return H.cond(function() return not dadaWon end, {
        H.cond(function() return n > 1 end, {
          H.logStep(function()
            return string.format("[dadaluma] ATTEMPT %d -- reloading the " ..
              "entry point after a loss (%s)", n, tostring(dadaLost))
          end),
          H.call(function() ldReq = H.requestLoadState(dadaBlob) end),
          H.waitFrames(2),
          H.call(function() H.checkReq(ldReq, "dadaluma attempt " .. n) end),
          H.waitFrames(60),
        }, {}),
        H.call(function() dadaLost = nil end),
        H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(4),
        fightBody(n),
        H.call(function()
          if dadaLost == nil then
            dadaWon = true
            H.log(string.format("[dadaluma] attempt %d WON battle 69 " ..
              "at f%d", n, H.frame))
          end
        end),
      }, {})
    end
    local ckReq
    return H.cond(function() return true end, {
      H.call(function() ckReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(ckReq, "entry point checkpoint")
        dadaBlob = ckReq.blob
        H.log(string.format("[dadaluma] entry point checkpoint captured " ..
          "(%d bytes) f%d", #dadaBlob, H.frame))
      end),
      attempt(1),
      attempt(2),
      attempt(3),
      H.call(function()
        if not dadaWon then
          error(string.format("[dadaluma] battle 69 not won in 3 " ..
            "attempts -- last loss: %s -- the per-attempt numbers above " ..
            "are the balance finding (#74-style); do not rig this fight",
            tostring(dadaLost)), 0)
        end
      end),
    })
  end)(),
  H.waitFrames(60),
  -- A won boss fight can still leave casualties.  Restore them before this
  -- reusable checkpoint so the Ramuh scene does not inherit a lost route.
  H.fieldCare({ tag = "care after Dadaluma", threshold = 0.55 }),
  H.call(function()
    H.assertEq(sw(0x034A), 0, "$034A CLEAR -- the gentleman is gone")
    H.assertEq(map(), 221, "still on map 221")
    H.assertEq(H.fieldX() == 30 and H.fieldY() == 13, true,
      "control returned at (30,13)")
    H.assertEq(H.bfsPath(33, 10) ~= nil, true,
      "the tower porch is OPEN -- (33,10) walkable")
    H.assertEq(sw(0x0053), 0, "$0053 still clear -- TERRA waits upstairs")
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("dadaluma_won: char %d is on their feet", c))
    end
    H.log(string.format("[dadaluma_won] f%d at (%d,%d)",
      H.frame, H.fieldX(), H.fieldY()))
    H.screenshot("dadaluma_won")
  end),
  H.saveState("dadaluma_won.mss"),
  H.logStep(function()
    return string.format(
      "dadaluma_won generated at frame %d -- the maze is climbed", H.frame)
  end),
})
