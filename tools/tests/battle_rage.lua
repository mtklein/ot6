-- @suite
-- battle_rage.lua -- issue #40: Gau's 8-slot rage loadout, asserted at the ONE
-- choke point the design ruled on (docs/design/kit-gau.md §2.2, §8.3, §8.7).
--
-- The Ochette model keeps Veldt learning unlimited -- LearnRage and the 32-byte
-- $1d2c-$1d4b bitfield are untouched, because the collection game IS Gau -- and
-- narrows only the BATTLE menu, to eight slots the player configures in the
-- field.  The narrowing happens in exactly one place: the flat list InitSkills
-- builds at $257e once per battle (battle_main.asm:14656+).  Everything
-- downstream reads that list and narrows itself for free -- the window draw
-- (DrawRageListText), the confirm (btlgfx_main.asm:20264-20266, which refuses
-- an $ff cell), the scroll cap, even RandRage's confused-rager pick
-- (battle_main.asm:987-999).  So this test asserts the list, byte for byte,
-- and nothing about window chrome: if the list is right the window cannot be
-- wrong.
--
-- Storage is EIGHT BYTES at $1e1f-$1e26, the next scrap after the Bushido
-- loadout word inside the checksummed working-save block.  byte = rage id + 1;
-- $00 = unset; all eight zero = AUTO.  No persistent_layout bump: the sentinel
-- means every existing save and every tracked battery anchor -- which hold
-- zeros there, measured -- decodes as AUTO, the state they are genuinely in.
--
-- THE AUTO RULING, 2026-07-28.  kit-gau.md contradicted itself: §2.2 defined
-- AUTO as "the first eight known rages in id order", §8.2 wrote "all-zero ->
-- return carry, use the vanilla walk", and the first build pass shipped §8.2.
-- That left the vanilla 200-entry wall reachable by INACTION -- a player who
-- never opens the configurator meets exactly the wall the owner asked to be
-- rid of.  The dispatcher reversed §8 onto §2.2: AUTO TRUNCATES TO EIGHT.
-- Arm 1 asserts the truncation.  Arm 1b is the separate, explicitly-labelled
-- vanilla-walk EQUIVALENCE measurement -- with eight or fewer species learned
-- the AUTO list is still the vanilla walk byte for byte, which is the only
-- range over which "byte-for-byte vanilla under AUTO" survives the ruling --
-- and it also measures what the underlying collection still contains ($1d2c
-- is read back and counted, so the arm shows the album is untouched while the
-- battle menu is capped).
--
-- THE $ff-FILL, verified (kit-gau.md §8.3 flagged it UNVERIFIED and asked for
-- one probe before the build relied on it).  InitSkills does NOT terminate the
-- rage region -- unlike the dance list right above it, which explicitly writes
-- $ff for every unknown dance (battle_main.asm:14666-14671), the rage walk only
-- streams the ids it finds.  The terminator comes from InitBattle, whose
-- 16-bit double-store loop fills $2000-$341f with $ff (battle_main.asm:
-- 6096-6102) BEFORE it calls InitSkills (:6162) -- and InitSkills has exactly
-- that one caller.  Arm 1 measures it: past the last known rage the region is
-- $ff all the way to the dance list at $267e.
--
-- What is asserted:
--   1. AUTO TRUNCATES + THE FILL.  All eight bytes zero, eleven species
--      learned -> the FIRST EIGHT in id order and nothing else; and the region
--      past the count is $ff to $267d.
--   1b. VANILLA-WALK EQUIVALENCE (a measurement, not the ruling).  With six
--      species learned -- inside the eight-wide window -- the AUTO list is the
--      whole vanilla walk, byte for byte.  The collection behind it is counted
--      out of $1d2c in the same arm.
--   2. MANUAL.  Stored ids appear in SLOT order (not id order -- the player
--      arranged them), the count is the number of filled slots, and the cell
--      after the last one is $ff.
--   3. VALIDATION.  A stored id whose $1d2c bit is clear is dropped, not
--      offered: the list shrinks and the remaining slots keep their order.
--   4. FULL EIGHT.  All eight slots filled -> exactly eight ids then $ff --
--      the "reasonable limit" the owner asked for, measured.
--   5. THE WALL IS UNREACHABLE.  With 40 species learned, AUTO shows the first
--      8 and a set loadout shows the player's 8.  The album still holds 40 --
--      counted from the bitfield in the same arm -- so nothing was taken away
--      from the collection game; only the battle menu is capped.
--   6. THE TRANCE'S PRICE (the Dance model, #34's rule applied to the other
--      possess-verb).  Rage-start debits the flat 8; every possessed turn
--      after it debits 0; and a Gau who cannot pay the start does NOT get the
--      whole-battle state for free -- the RAGE status never sets.
--   7. THE TIER LATCH.  The pending boost is copied into OT6_RAGETIER at
--      Cmd_10 and must OUTLIVE the action it was spent on: mid-trance turns
--      re-enter Cmd_10 with the pending byte already consumed, and a naive
--      re-latch would silently drop the whole possession to tier 0.
--
-- Gau is not recruitable at this fixture, so he is INSTALLED the way
-- battle_bushido installs Cyan: CHAR::GAU into $3ED8 and a Rage-only command
-- list at $202E.  The rage WINDOW is battle menu state $1e, and its cursor is
-- the same triple the tools window uses -- scroll $892b,y / column $892f,y /
-- row $8933,y indexed by the actor slot, entry = (scroll + row) * 2 + column
-- (_c18438, btlgfx_main.asm:20096-20111).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU = 0x7BCA
local RAGES = 0x1D2C                 -- learned-rage bitfield, 32 bytes
local RAGELOAD = 0x1E1F              -- OT6_RAGELOAD: 8 bytes, id+1, 0 = unset
local LIST, COUNT = 0x257E, 0x3A9A   -- the flat battle list and its length
local DANCELIST = 0x267E             -- the dance list starts here: our ceiling

-- eleven species, ascending, spread over several bitfield bytes so the walk
-- has to cross byte boundaries the way a real Gau's does.
local KNOWN = { 3, 7, 12, 20, 33, 41, 55, 68, 90, 111, 130 }

local function teach(ids)
  for i = 0, 31 do H.writeByte(RAGES + i, 0) end
  for _, id in ipairs(ids) do
    local a = RAGES + (id >> 3)
    H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
  end
end

-- slots: an array of rage ids (nil entries and a short array leave slots unset)
local function loadout(slots)
  for i = 0, 7 do
    local v = slots and slots[i + 1]
    H.writeByte(RAGELOAD + i, v and (v + 1) or 0)
  end
end

local function cell(i) return H.readByte(LIST + i) end

-- what the COLLECTION still holds, read back out of the bitfield the battle
-- list no longer mirrors: the popcount of $1d2c-$1d4b, in id order.
local function learnedIds()
  local ids = {}
  for id = 0, 254 do
    if (H.readByte(RAGES + (id >> 3)) & (1 << (id & 7))) ~= 0 then
      ids[#ids + 1] = id
    end
  end
  return ids
end

-- the first n of a list (AUTO's window)
local function head(t, n)
  local o = {}
  for i = 1, math.min(n, #t) do o[i] = t[i] end
  return o
end

local function assertList(want, tag)
  H.assertEq(H.readByte(COUNT), #want,
    string.format("%s: $3a9a = %d rages", tag, #want))
  for i, id in ipairs(want) do
    H.assertEq(cell(i - 1), id,
      string.format("%s: list[%d] = rage %d", tag, i - 1, id))
  end
  H.assertEq(cell(#want), 0xFF,
    string.format("%s: list[%d] terminates ($ff)", tag, #want))
end

-- One arm: reload the field fixture, install the save-side state, drop into a
-- battle, and read the list InitSkills just built.  A savestate reload per arm
-- is the only honest way to re-run InitSkills -- it runs exactly once, from
-- InitBattle.
local function arm(tag, setup, check)
  return {
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      H.log("---- " .. tag .. " ----")
      setup()
    end),
    H.enterEncounter(),
    H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000,
      { H.waitFrames(4) }, tag .. ": a battle menu opens"),
    H.call(check),
  }
end

local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({ H.waitFrames(20) })

-- 1. AUTO TRUNCATES TO EIGHT, and the $ff fill that terminates it -----------
-- The 2026-07-28 ruling: the wall must not be reachable through inaction.
-- Eleven species are learned; the battle menu offers the first eight.
local AUTO8 = head(KNOWN, 8)
add(arm("auto", function()
  teach(KNOWN)
  loadout(nil)                       -- all eight bytes zero = AUTO
end, function()
  assertList(AUTO8, "auto")
  H.assertEq(#learnedIds(), #KNOWN,
    "auto: and the COLLECTION is untouched -- $1d2c still holds all "
    .. #KNOWN .. " species")
  -- the fill, measured: nothing between the terminator and the dance list is
  -- anything but $ff.  This is InitBattle's doing, not InitSkills' -- see the
  -- header.  Swept, not sampled: one bad byte anywhere still shows up.
  local bad = nil
  for i = #AUTO8, (DANCELIST - LIST) - 1 do
    if cell(i) ~= 0xFF then bad = i break end
  end
  H.assertEq(bad, nil, string.format(
    "$257e+%d..$267d is $ff-filled (first non-$ff at index %s)",
    #AUTO8, tostring(bad)))
  H.log(string.format("AUTO: %d learned, %d offered -- the first eight in id "
    .. "order; the region past them is $ff to $267d", #KNOWN, #AUTO8))
end))

-- 1b. VANILLA-WALK EQUIVALENCE -- the measurement the ruling did NOT delete --
-- Inside the window (<= 8 learned) the AUTO list is still, exactly, what the
-- vanilla $1d2c walk would have written.  This arm is labelled a measurement
-- on purpose: it is not the ruling, it is the range over which kit-gau.md's
-- "a fresh Gau with <= 8 rages is byte-for-byte vanilla under AUTO" (§2.2)
-- still holds after the truncation.
local SIX = { 3, 7, 12, 20, 33, 41 }
add(arm("auto-vanilla-equiv", function()
  teach(SIX)
  loadout(nil)
end, function()
  local ids = learnedIds()
  H.assertEq(#ids, #SIX, "auto-vanilla-equiv: six species in the bitfield")
  assertList(ids, "auto-vanilla-equiv")   -- the WHOLE walk, byte for byte
  H.log("VANILLA-WALK EQUIVALENCE: with " .. #SIX .. " learned (<= 8) the AUTO "
    .. "list is the full id-order walk -- the truncation only bites past eight")
end))

-- 2. MANUAL -- the stored ids, in SLOT order --------------------------------
add(arm("manual", function()
  teach(KNOWN)
  loadout({ 130, 3, 55, 7 })         -- four slots, deliberately NOT id order
end, function()
  assertList({ 130, 3, 55, 7 }, "manual")
  H.log("MANUAL: four slots -> four ids in the player's order, not the id order")
end))

-- 3. VALIDATION -- a stored-but-unlearned id is dropped ---------------------
add(arm("validate", function()
  local minus55 = {}
  for _, id in ipairs(KNOWN) do if id ~= 55 then minus55[#minus55 + 1] = id end end
  teach(minus55)                     -- 55 is no longer in $1d2c
  loadout({ 130, 55, 3 })            -- ... but it is still in the loadout
end, function()
  assertList({ 130, 3 }, "validate")
  H.log("VALIDATION: an unlearned stored id is dropped from the list, and the "
    .. "surviving slots keep their order")
end))

-- 4. FULL EIGHT -- the owner's "choose from 8", measured --------------------
add(arm("eight", function()
  teach(KNOWN)
  loadout({ 130, 111, 90, 68, 55, 41, 33, 20 })
end, function()
  assertList({ 130, 111, 90, 68, 55, 41, 33, 20 }, "eight")
  H.log("FULL EIGHT: exactly eight ids then $ff -- the battle menu is now as "
    .. "long as Sabin's, chosen from everything he has hunted")
end))

-- 5. THE WALL IS UNREACHABLE -- 40 learned, 8 carried, even untouched -------
add(arm("wall", function()
  local many = {}
  for id = 2, 158, 4 do many[#many + 1] = id end       -- 40 species
  _G.__many = many
  teach(many)
  loadout(nil)                                         -- AUTO: never configured
end, function()
  -- the ruling, at the size that motivated it: a player who never opened the
  -- configurator gets EIGHT, not forty.
  assertList(head(_G.__many, 8), "wall")
  H.assertEq(#learnedIds(), #_G.__many,
    "wall: and the album still holds all " .. #_G.__many .. " species")
  H.log("WALL: 40 hunted, 8 offered through pure inaction -- the vanilla "
    .. "200-entry list is no longer reachable by not deciding")
end))
add(arm("wall-filtered", function()
  teach(_G.__many)
  local eight = {}
  for i = 1, 8 do eight[i] = _G.__many[i * 3] end      -- eight of the forty
  _G.__eight = eight
  loadout(eight)
end, function()
  assertList(_G.__eight, "wall-filtered")
  H.assertEq(H.readByte(COUNT), 8,
    "wall-filtered: the same save shows 8, not " .. #_G.__many)
  H.log("the rage list filters at InitSkills' build and nowhere else -- "
    .. "AUTO is the first eight, a set loadout is exactly the slots")
end))

-- ============================ THE TRANCE ====================================
local ACTOR, MSTATE = 0x62CA, 0x7BC2
local ST_RAGE = 0x1E                 -- the rage window's battle menu state
local CMD_RAGE = 0x10
local GAU = 0x0B                     -- CHAR::GAU
local RAGETIER = 0xED73              -- OT6_RAGETIER ($7eed73, ot6_memory.inc)
local PARTY = { 0, 1, 2 }
local GUARDS = { 2, 3 }
local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function CURHP(s) return 0x3BF4 + s * 2 end
local function MHP(s)   return 0x3BFC + s * 2 end
local function ST3(e)   return 0x3EF8 + e end
local function ST4(e)   return 0x3EF9 + e end
local function raging(s) return (H.readByte(ST4(s * 2)) & 0x01) ~= 0 end
local function mp(s)    return H.readWord(CURMP(s)) end

local actor
local startMp = 50
local pinMp, pinPend = true, 0
-- forward declaration: trance() arms the tier/coin instrument for EVERY arm,
-- so even the arms that only care about MP can assert how many possessed
-- turns actually happened (see the vacuous-claim note in kit-gau.md §9).
local instrument, cmd10HitsReset
local cmd10Hits = 0     -- Cmd_10 entries: declared HERE, above every closure
                        --   that reads it (a later `local` would leave those
                        --   closures reading a nil global instead -- measured:
                        --   "attempt to compare number with nil")
local coinSummary       -- forward: the tier3 arm sits above its definition
local coins = {}        -- one entry per possessed turn (see the tier section)
local pinBe = nil       -- the $be seed to force at each Ot6RageCoin entry
local cmd0 = CMD_RAGE                -- the one command Gau is installed with

local function pinGau()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, GAU)                  -- CHAR::GAU
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, cmd0)                -- one verb, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeWord(CURHP(s), 999)
    H.writeWord(MAXMP(s), 99)
  end
  if actor then
    -- pinPend is nil once the rage has been CONFIRMED: Cmd_10 has not run yet
    -- at that point, and re-pinning would overwrite the very pending byte the
    -- latch is about to read.
    if pinPend then H.writeByte(0x3E9D + actor * 2, pinPend) end
    if pinMp then H.writeWord(CURMP(actor), startMp) end
    -- Park the bench by WOUNDING it, not by stopping it -- battle_slots.lua's
    -- own measured lesson (:114-118): "a stopped character's pending menu stays
    -- open forever and starves the actor's next turn".  This fixture used the
    -- stopped form and paid exactly that price: a battle with a list open is
    -- PAUSED, so after the rage-start action Cmd_10 re-entered ZERO more times
    -- (measured: cmd10=1, menu=$01, mstate=$1e over 2700 frames).  Every
    -- "several possessed turns" claim in the arms below was therefore vacuous
    -- until this line changed.  A dead row raises no menu at all.
    for _, s in ipairs(PARTY) do
      if s ~= actor then
        H.writeByte(0x3EE4 + s * 2, H.readByte(0x3EE4 + s * 2) | 0x80)  -- wound
        H.writeWord(CURHP(s), 0)
      end
    end
  end
end

local function pinGuards()
  for _, s in ipairs(GUARDS) do
    local st3 = ST3(8 + s * 2)
    H.writeByte(st3, H.readByte(st3) | 0x10)          -- stopped: nothing contests
    H.writeWord(MHP(s), 0xF000)
  end
end
local function pinAll() pinGau(); pinGuards() end

-- One driving tick: re-pin the fixture and clear any OTHER character's open
-- menu, because a battle with a list open is PAUSED and these arms need the
-- ATB to keep running.  Never presses into the rage window itself.
local function tick()
  pinAll()
  if H.readByte(MENU) ~= 0 and H.readByte(MSTATE) ~= ST_RAGE then
    H.setPad({ "a" })
  end
end
local function ride(n)
  return H.repeatN(n, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  })
end

-- open the rage window, put the cursor on entry 0, confirm.
local function rageStart(tag)
  return {
    H.driveUntil(function() return H.readByte(MSTATE) == ST_RAGE end, 1500, {
      H.call(function() pinAll(); H.setPad({ "a" }) end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(14),
    }, tag .. ": the rage window opens (battle menu state $1e)"),
    H.call(function()
      pinAll()
      H.writeByte(0x892B + actor, 0)   -- scroll
      H.writeByte(0x892F + actor, 0)   -- column 0
      H.writeByte(0x8933 + actor, 0)   -- row 0 -> list entry 0
    end),
    H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
    H.waitFrames(10),
  }
end

local function trance(tag, setup, check)
  return {
    H.loadState(STATE),
    H.waitFrames(10),
    H.call(function()
      H.log("---- " .. tag .. " ----")
      actor, pinMp, pinPend, cmd0 = nil, true, 0, CMD_RAGE
      teach(KNOWN)
      loadout({ 33, 68 })
      setup()
    end),
    H.enterEncounter(),
    H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
      H.call(pinAll), H.waitFrames(1),
    }, tag .. ": a battle menu opens"),
    H.call(function()
      actor = H.readByte(ACTOR)
      pinAll()
      instrument()
      cmd10HitsReset()
      H.log(string.format("%s: gau in slot %d, MP %d, pending %d",
        tag, actor, mp(actor), pinPend))
    end),
    H.call(check),
  }
end

-- 6a. THE PRICE -- flat 8 at the start, nothing on the possessed turns -------
add(trance("charge", function() startMp = 50 end, function() end))
add(rageStart("charge"))
add({
  H.call(function() pinMp = false; pinPend = nil end),  -- debit now observable
  H.driveUntil(function() return raging(actor) end, 4000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "charge: the RAGE status latches (Cmd_10 ran)"),
  H.call(function()
    local left = mp(actor)
    H.log(string.format("charge: MP %d -> %d after the rage START", startMp, left))
    H.assertEq(left, startMp - 8,
      "the trance costs a flat 8 at the start (the Dance rule, one price for "
      .. "both possess-verbs)")
    _G.__afterStart = left
    _G.__tier0 = H.readByte(RAGETIER)
    H.assertEq(_G.__tier0, 0, "unboosted start latched tier 0")
  end),
  -- ride the possession: several more possessed turns must cost nothing, and
  -- the latch must not move.  300 ticks, not 90: the turn COUNT is asserted
  -- below, and 90 was not enough for "several" to be true.
  ride(300),
  H.call(function()
    H.assertEq(raging(actor), true, "still possessed after riding the trance")
    H.assertEq(cmd10Hits >= 3, true, string.format(
      "the trance actually took several turns (Cmd_10 re-entered %d times) -- "
      .. "without this count the free-turns claim below is vacuous", cmd10Hits))
    H.assertEq(mp(actor), _G.__afterStart,
      "every possessed turn after the start is FREE -- one payment, whole battle")
    H.assertEq(H.readByte(RAGETIER), _G.__tier0,
      "the latched tier survived the mid-trance Cmd_10 re-entries")
    H.log("CHARGE: 8 once, then nothing -- and the tier latch held")
  end),
})

-- 6b. THE REFUSAL -- a Gau who cannot pay does not get the state for free ----
add(trance("refuse", function() startMp = 5 end, function() end))
add(rageStart("refuse"))
add({
  H.call(function() pinMp = false; pinPend = nil end),
  ride(90),                               -- let the refused action resolve
  H.call(function()
    H.log(string.format("refuse: MP stayed %d, raging = %s",
      mp(actor), tostring(raging(actor))))
    H.assertEq(raging(actor), false,
      "an unpayable rage START never sets the whole-battle RAGE status -- the "
      .. "#34 lesson, re-applied (Ot6RageStartGate)")
    H.assertEq(mp(actor), 5, "and MP was not driven negative")
  end),
})

-- 7. THE TIER LATCH -- 3 BP banked at the start, held for the whole trance ---
add(trance("tier3", function() startMp = 50; pinPend = 3 end,
  function() coins = {}; pinBe = nil end))
add(rageStart("tier3"))
add({
  H.call(function() pinMp = false; pinPend = nil end),
  H.driveUntil(function() return raging(actor) end, 4000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "tier3: the RAGE status latches"),
  H.call(function()
    H.assertEq(H.readByte(RAGETIER), 3,
      "Cmd_10 latched the pending 3 into OT6_RAGETIER")
  end),
  ride(300),                              -- several more possessed turns
  H.call(function()
    H.assertEq(cmd10Hits >= 3, true, string.format(
      "the trance actually took several turns (Cmd_10 re-entered %d times)",
      cmd10Hits))
    H.assertEq(H.readByte(RAGETIER), 3,
      "and it is STILL 3 after several possessed turns -- the mid-trance "
      .. "Cmd_10 re-entries did not re-latch the consumed pending byte")
    H.assertEq(H.readByte(0x3E9D + actor * 2), 0,
      "the pending boost itself was consumed by the start action")
    -- ... and the top of the ladder, on the same instrument the tier-1/2 arms
    -- use: tier 3 takes NO roll at all (no `inc $be`) and forces entry 1 on
    -- every possessed turn, start turn included.
    local c0, c1, draws = coinSummary()
    H.log(string.format("tier3: %d Fight / %d special over %d possessed turns "
      .. "[%s]", c0, c1, #coins, draws))
    H.assertEq(#coins >= 2, true,
      "tier3: the trance rolled more than once (got " .. #coins .. ")")
    for _, e in ipairs(coins) do
      H.assertEq(e.tier, 3, "tier3: every roll saw the latched 3")
      H.assertEq(e.coin, 1,
        "tier3: the special, every turn -- 3 BP buys the whole trance")
      H.assertEq(e.draws, 0,
        "tier3: and it takes no roll at all (certainty, not a better coin)")
    end
  end),
})

-- ====================== 8. THE TIER LADDER'S ODDS ===========================
-- Ot6RageCoin's tier-1 and tier-2 arms had never executed: the latch was
-- asserted, the coin was not.  Both are one threshold compare against one
-- fresh RNG draw, so battle_slots.lua's discipline applies exactly -- pin the
-- draw at the threshold from BOTH sides and demand the opposite outcome:
--
--   tier 1   the special unless draw < $40   -> $3f = Fight, $40 = special
--   tier 2   the special unless draw < $10   -> $0f = Fight, $10 = special
--
-- THE OBSERVABLE is the coin itself, not a proxy.  RandRage's tail is
-- `rol / tax / lda f:MonsterRage,x` (battle_main.asm:1008-1012), and X is
-- monsterId*2 + coin -- so a READ callback over the MonsterRage table reports
-- the coin exactly, per possessed turn, with no inference: entry 0 is always
-- plain Fight, entry 1 the beast's special (monster_rage.asm:3-5).
--
-- THE DRAW is pinned the battle_steal way: an exec callback on Ot6RageCoin's
-- own entry writes $be, and the macro's `inc $be; ldx $be; lda f:RNGTbl,x`
-- then reads RNGTbl[$be+1].  RNGTbl is a permutation of 0..255 (asserted
-- below), so every boundary value is reachable EXACTLY -- no "nearest
-- available" fudge.  The same callback pair also counts the draws the proc
-- takes ($be delta across it), which is how tier 0's "byte-vanilla, draws
-- NOTHING extra" claim is measured rather than assumed.
--
-- THE WIDTH CONTRACT.  Ot6RageCoin is entered from a site whose index width
-- is unknown, does `rep #$10` to park Y, and must hand the caller's width
-- back by hand (`plp` would also restore the stale carry it exists to
-- replace).  The call site is located by SCANNING RandRage for the `jsl`
-- to Ot6RageCoin -- derived, so it cannot go stale -- and the CPU state is
-- compared either side of it.
local RNGTBL   = H.sym("RNGTbl") & 0x3FFFFF
local MONRAGE  = H.sym("MonsterRage")
local COINPROC = H.sym("Ot6RageCoin")
local RANDRAGE = H.sym("RandRage")

local psAtEntry, yAtEntry = nil, nil
local drawsThisRoll, beAtRand, tierAtEntry = 0, nil, nil
local widthChecks = {}
local instrumented = false

-- Mesen exposes the CPU registers as flat "cpu.<field>" keys; the flag byte's
-- name is resolved once (and logged) rather than guessed, so a Mesen upgrade
-- that renames it fails loudly here instead of silently skipping the check.
local PS_KEY, Y_KEY
local function resolveCpuKeys()
  local s = emu.getState()
  local names = {}
  for k in pairs(s) do
    if type(k) == "string" and k:sub(1, 4) == "cpu." then names[#names + 1] = k end
  end
  table.sort(names)
  H.log("cpu state keys: " .. table.concat(names, " "))
  for _, cand in ipairs({ "cpu.ps", "cpu.p", "cpu.flags", "cpu.status" }) do
    if s[cand] ~= nil then PS_KEY = cand break end
  end
  for _, cand in ipairs({ "cpu.y", "cpu.Y" }) do
    if s[cand] ~= nil then Y_KEY = cand break end
  end
  H.assertEq(PS_KEY ~= nil and Y_KEY ~= nil, true,
    "Mesen exposes the CPU flag byte and Y (needed for the width contract)")
end
cmd10HitsReset = function() cmd10Hits = 0 end

local function cpu()
  local s = emu.getState()
  return s[PS_KEY], s[Y_KEY]
end

-- the $be seed whose NEXT draw is exactly `want`
local function seedFor(want)
  for v = 0, 255 do
    if H.readRomByte(RNGTBL + ((v + 1) & 0xFF)) == want then return v end
  end
  return nil
end

instrument = function()
  if instrumented then return end
  instrumented = true
  resolveCpuKeys()
  -- RNGTbl must be a permutation, or "pinned at the boundary" is a fiction
  local seen = {}
  for i = 0, 255 do seen[H.readRomByte(RNGTBL + i)] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  H.assertEq(n, 256, "RNGTbl is a permutation of 0..255 -- every draw value "
    .. "is reachable exactly, so the boundary pins are literal")

  -- locate `jsl Ot6RageCoin` inside RandRage, by opcode, so the width probe
  -- can never point at a stale address
  local site = nil
  for i = 0, 96 do
    local a = (RANDRAGE & 0x3FFFFF) + i
    if H.readRomByte(a) == 0x22
       and H.readRomWord(a + 1) == (COINPROC & 0xFFFF)
       and H.readRomByte(a + 3) == ((COINPROC >> 16) & 0xFF) then
      site = RANDRAGE + i
      break
    end
  end
  H.assertEq(site ~= nil, true, "found `jsl Ot6RageCoin` inside RandRage")
  H.log(string.format("RandRage=%06x  jsl site=%06x  Ot6RageCoin=%06x",
    RANDRAGE, site, COINPROC))

  -- locate the proc's ONE `inc $be` -- ot6_rand's rolling index bump.  An exec
  -- callback there counts the draws the proc actually takes (tier 0 must take
  -- none) and records the index the draw is about to read, which is how the
  -- boundary pin is PROVEN to have landed rather than assumed.
  local randSite = nil
  for i = 0, 160 do
    local a = (COINPROC & 0x3FFFFF) + i
    if H.readRomByte(a) == 0xE6 and H.readRomByte(a + 1) == 0xBE then
      randSite = COINPROC + i
      break
    end
  end
  H.assertEq(randSite ~= nil, true,
    "found ot6_rand's `inc $be` inside Ot6RageCoin (the only draw it can take)")
  H.log(string.format("RandRage=%06x  jsl site=%06x  Ot6RageCoin=%06x  "
    .. "inc $be=%06x", RANDRAGE, site, COINPROC, randSite))

  -- pin the draw AND snapshot the caller's state, at the proc's own entry
  emu.addMemoryCallback(function()
    if pinBe then H.writeByte(0xBE, pinBe) end
    drawsThisRoll, beAtRand = 0, nil
    tierAtEntry = H.readByte(RAGETIER)
    psAtEntry, yAtEntry = cpu()
  end, emu.callbackType.exec, COINPROC, COINPROC)

  emu.addMemoryCallback(function()
    drawsThisRoll = drawsThisRoll + 1
    beAtRand = H.readByte(0xBE)         -- pre-increment: the seed we pinned
  end, emu.callbackType.exec, randSite, randSite)

  -- how many times the possessed turn re-enters Cmd_10 at all: the denominator
  -- for "every roll", and the thing that makes a multi-turn claim non-vacuous
  emu.addMemoryCallback(function() cmd10Hits = cmd10Hits + 1 end,
    emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))

  -- the width/register contract, one instruction past the jsl's return
  emu.addMemoryCallback(function()
    local ps, y = cpu()
    if psAtEntry then
      widthChecks[#widthChecks + 1] = {
        pre = psAtEntry, post = ps, ypre = yAtEntry, ypost = y,
      }
    end
  end, emu.callbackType.exec, site + 4, site + 4)

  -- the coin, read straight off the MonsterRage index
  emu.addMemoryCallback(function(addr)
    local off = addr - MONRAGE
    coins[#coins + 1] = {
      coin = off & 1,
      id = off >> 1,
      draws = drawsThisRoll,
      seed = beAtRand,
      tier = tierAtEntry,
    }
  end, emu.callbackType.read, MONRAGE, MONRAGE + 0x1FF)
end

coinSummary = function()
  local c0, c1, drawn = 0, 0, {}
  for _, e in ipairs(coins) do
    if e.coin == 0 then c0 = c0 + 1 else c1 = c1 + 1 end
    drawn[e.draws] = (drawn[e.draws] or 0) + 1
  end
  local d = {}
  for k, v in pairs(drawn) do d[#d + 1] = string.format("%d draw(s) x%d", k, v) end
  return c0, c1, table.concat(d, ", ")
end

-- One tier arm: pin the pending BP and the draw, ride the trance, and demand
-- EVERY possessed turn come up the same way.  Same drive, one pending byte and
-- one RNG byte different -- the tier and the draw are the only variables.
local function tierArm(tag, pend, draw, wantCoin, why)
  local seed = nil
  add(trance(tag, function()
    startMp = 50
    pinPend = pend
  end, function()
    instrument()
    seed = seedFor(draw)
    H.assertEq(seed ~= nil, true,
      string.format("%s: RNGTbl yields a seed whose next draw is $%02x",
        tag, draw))
    coins = {}
  end))
  add(rageStart(tag))
  add({
    H.call(function()
      pinMp, pinPend = false, nil
      pinBe = seed                       -- armed from the first coin onward
      coins = {}
    end),
    H.driveUntil(function() return raging(actor) end, 4000, {
      H.call(tick), H.waitFrames(3),
      H.call(function() H.setPad({}) end), H.waitFrames(6),
    }, tag .. ": the RAGE status latches"),
    H.call(function()
      H.assertEq(H.readByte(RAGETIER), pend,
        string.format("%s: Cmd_10 latched tier %d", tag, pend))
    end),
    ride(300),
    H.call(function()
      pinBe = nil
      local c0, c1, draws = coinSummary()
      H.log(string.format("%s: tier %d, draw pinned $%02x ($be seed %d) -> "
        .. "%d Fight / %d special over %d possessed turns [%s]",
        tag, pend, draw, seed, c0, c1, #coins, draws))
      for i, e in ipairs(coins) do
        H.log(string.format("  %s roll %d: tier=%s draws=%d seed=%s coin=%d "
          .. "(rage %d)", tag, i, tostring(e.tier), e.draws, tostring(e.seed),
          e.coin, e.id))
      end
      H.assertEq(#coins >= 2, true,
        tag .. ": the trance rolled more than once (got " .. #coins .. ")")
      local bad = 0
      for _, e in ipairs(coins) do if e.coin ~= wantCoin then bad = bad + 1 end end
      H.assertEq(bad, 0, string.format(
        "%s: every one of the %d rolls picked entry %d (%s)",
        tag, #coins, wantCoin, why))
      for _, e in ipairs(coins) do
        -- INCLUDING roll 1.  Vanilla rolls the START turn's attack at action
        -- LOAD (FixPlayerAttack's cmd-$10 arm), before Cmd_10 runs, so the
        -- original single latch in Cmd_10 left exactly one turn untiered --
        -- the turn the BP was spent on.  Measured before the fix:
        -- roll 1 tier=0 draws=0, rolls 2..5 tier=1 draws=1.
        H.assertEq(e.tier, pend, tag .. ": every roll saw the latched tier "
          .. "-- the START turn included (it is rolled at action load)")
        -- tiers 1/2 spend exactly one extra draw per turn -- and it is OUR
        -- draw: the index the roll read is the seed we pinned, so the value
        -- compared against the threshold was literally $%02x.
        H.assertEq(e.draws, 1, string.format(
          "%s: the tilted coin took exactly one extra RNG draw", tag))
        H.assertEq(e.seed, seed, string.format(
          "%s: and it read RNGTbl[$be+1] with $be = %d -- the pinned draw $%02x",
          tag, seed, draw))
      end
    end),
  })
end

-- TIER 0 IS BYTE-VANILLA, measured on the same instrument: the proc hands the
-- caller's own carry straight back and executes ot6_rand's `inc $be` ZERO
-- times, so an unboosted trance walks exactly the RNGTbl indices vanilla
-- walks.  That is the property the whole same-drive A/B rests on, and it is
-- the one arm that must not be pinned -- pinning would hide it.
add(trance("t0-vanilla", function() startMp = 50; pinPend = 0 end, function()
  instrument()
  coins = {}
end))
add(rageStart("t0-vanilla"))
add({
  H.call(function()
    pinMp, pinPend, pinBe = false, nil, nil
    coins, cmd10Hits = {}, 0
  end),
  H.driveUntil(function() return raging(actor) end, 4000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "t0-vanilla: the RAGE status latches"),
  ride(300),
  H.call(function()
    local c0, c1, draws = coinSummary()
    H.log(string.format("t0-vanilla: tier 0, unpinned -> %d Fight / %d special "
      .. "over %d possessed turns [%s]", c0, c1, #coins, draws))
    H.log(string.format("t0-vanilla: diag cmd10=%d menu=%02x mstate=%02x "
      .. "raging=%s battleActive=%s mHP=%d/%d",
      cmd10Hits, H.readByte(MENU), H.readByte(MSTATE), tostring(raging(actor)),
      tostring(H.battleActive()), H.readWord(MHP(2)), H.readWord(MHP(3))))
    H.assertEq(#coins >= 2, true,
      "t0-vanilla: the trance rolled more than once (got " .. #coins .. ")")
    for _, e in ipairs(coins) do
      H.assertEq(e.tier, 0, "t0-vanilla: every roll saw tier 0")
      H.assertEq(e.draws, 0,
        "tier 0 takes NO extra RNG draw -- byte-vanilla stream, which is why "
        .. "the tier arms can be a same-drive A/B")
    end
  end),
})

-- tier 1: the special unless a fresh draw < $40 -- both sides of $3f/$40
tierArm("t1-under", 1, 0x3F, 0, "draw $3f < $40, so the coin falls to Fight")
tierArm("t1-over",  1, 0x40, 1, "draw $40 >= $40, so the special wins")
-- tier 2: the same compare at $10 -- and $3f, which tier 1 REFUSED, now wins,
-- which is the ladder converging rather than two unrelated thresholds
tierArm("t2-under", 2, 0x0F, 0, "draw $0f < $10, so the coin falls to Fight")
tierArm("t2-over",  2, 0x10, 1, "draw $10 >= $10, so the special wins")
tierArm("t2-at-t1-boundary", 2, 0x3F, 1,
  "the very draw that MISSED at tier 1 now hits -- 3/4 -> 15/16")

-- THE WIDTH RESTORE, on a tier-1 trance (the arm that actually takes the
-- rep/sep path).  The caller's index-width bit and Y must come back unchanged
-- across the jsl; the carry is the one thing the proc is allowed to replace.
add({
  H.call(function()
    H.assertEq(#widthChecks > 0, true,
      "the width probe fired (the jsl site was reached)")
    local badWidth, badY = 0, 0
    for _, w in ipairs(widthChecks) do
      if (w.pre & 0x10) ~= (w.post & 0x10) then badWidth = badWidth + 1 end
      if w.ypre ~= w.ypost then badY = badY + 1 end
    end
    H.log(string.format("width probe: %d crossings, first pre P=%02x post P=%02x",
      #widthChecks, widthChecks[1].pre, widthChecks[1].post))
    H.assertEq(badWidth, 0,
      "Ot6RageCoin handed the caller's INDEX WIDTH back on every crossing -- "
      .. "the sep/rep restore, not plp (which would clobber the coin)")
    H.assertEq(badY, 0,
      "and Y came back unchanged from the rep #$10 / phy / ply park")
  end),
})

-- ========================= 9. LEAP COSTS 2 MP ===============================
-- "only the basic Fight command is free" is the owner absolute
-- (mp-economy.md:30-34), and kit-gau.md §5 prices the leap at the
-- probe-collect rung -- flat 2, the same as Steal, for the same reason: it
-- COLLECTS rather than resolves.  Implemented (Ot6AbilityCost's cmd-$11 arm ->
-- Ot6LeapCost) and, until now, never exercised.  Gau is installed with LEAP
-- alone so the battle menu's first row IS the verb under test.
local COSTQ = 0x3620                 -- the queued-cost cell CreateAction writes
local CMD_LEAP = 0x11
local LEAP_COST = 2
local leapCosts = {}
local leapWatch = false

add({
  H.call(function()
    emu.addMemoryCallback(function(_, v)
      if leapWatch and H.readByte(0x3A7A) == CMD_LEAP then
        leapCosts[#leapCosts + 1] = v
      end
    end, emu.callbackType.write, 0x7E0000 + COSTQ, 0x7E0000 + COSTQ + 0xFE)
  end),
})

-- 9a. the charge
add(trance("leap", function()
  startMp = 20
  cmd0 = CMD_LEAP
end, function() leapCosts = {}; leapWatch = true end))
add({
  H.pressButtons({ "a" }, 4),          -- the menu's only row is Leap
  H.waitFrames(10),
  H.call(function() pinMp = false; pinPend = nil end),
  H.driveUntil(function() return mp(actor) ~= 20 end, 8000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "leap: the charge lands"),
  H.call(function()
    leapWatch = false
    H.log(string.format("leap: MP 20 -> %d, cost queue %s",
      mp(actor), tostring(leapCosts[1])))
    H.assertEq(leapCosts[1], LEAP_COST,
      "Ot6AbilityCost's cmd-$11 arm priced the leap at the flat 2")
    H.assertEq(mp(actor), 20 - LEAP_COST,
      "and the universal charge took exactly 2 -- the probe-collect rung")
  end),
})

-- 9b. the refusal: under 2 MP the leap is refused, not silently freed
add(trance("leap-refuse", function()
  startMp = 1
  cmd0 = CMD_LEAP
end, function() leapCosts = {}; leapWatch = true end))
add({
  H.pressButtons({ "a" }, 4),
  H.waitFrames(10),
  H.call(function() pinMp = false; pinPend = nil end),
  ride(60),
  H.call(function()
    leapWatch = false
    H.log(string.format("leap-refuse: MP stayed %d, cost queue %s",
      mp(actor), tostring(leapCosts[1])))
    H.assertEq(leapCosts[1], LEAP_COST,
      "the queue still PRICES the leap at 2 (the refusal is the pool's, not "
      .. "the price's)")
    H.assertEq(mp(actor), 1,
      "and a Gau with 1 MP is refused: nothing spent, nothing driven negative "
      .. "-- the standard insufficient-MP surface, no leap-shaped exception")
    H.log("PASSED: list filter + AUTO truncation, trance price, refusal gate, "
      .. "tier latch, the tier-1/tier-2 coin at both boundaries, the width "
      .. "restore, and Leap's 2 MP")
  end),
})

H.run({ maxFrames = 240000 }, steps)
