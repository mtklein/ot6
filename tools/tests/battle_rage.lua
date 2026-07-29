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
-- Arm 1 pins that: zeros must reproduce the vanilla walk byte for byte.
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
--   1. AUTO + THE FILL.  All eight bytes zero -> the vanilla walk, byte for
--      byte, in id order; and the region past the count is $ff to $267d.
--   2. MANUAL.  Stored ids appear in SLOT order (not id order -- the player
--      arranged them), the count is the number of filled slots, and the cell
--      after the last one is $ff.
--   3. VALIDATION.  A stored id whose $1d2c bit is clear is dropped, not
--      offered: the list shrinks and the remaining slots keep their order.
--   4. FULL EIGHT.  All eight slots filled -> exactly eight ids then $ff --
--      the "reasonable limit" the owner asked for, measured.
--   5. THE WALL IS GONE.  With 40 species learned, AUTO shows 40 and the
--      loadout shows 8.  Same save, same battle, one byte of difference.
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

-- 1. AUTO -- the vanilla walk, and the $ff fill that terminates it -----------
add(arm("auto", function()
  teach(KNOWN)
  loadout(nil)                       -- all eight bytes zero = AUTO
end, function()
  assertList(KNOWN, "auto")
  -- the fill, measured: nothing between the terminator and the dance list is
  -- anything but $ff.  This is InitBattle's doing, not InitSkills' -- see the
  -- header.  Sampled rather than swept so one bad byte still shows up but the
  -- assertion log stays readable.
  local bad = nil
  for i = #KNOWN, (DANCELIST - LIST) - 1 do
    if cell(i) ~= 0xFF then bad = i break end
  end
  H.assertEq(bad, nil, string.format(
    "$257e+%d..$267d is $ff-filled (first non-$ff at index %s)",
    #KNOWN, tostring(bad)))
  H.log(string.format("AUTO: %d known rages walked in id order; the region past "
    .. "them is $ff to $267d -- InitBattle's fill, not InitSkills'", #KNOWN))
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

-- 5. THE WALL IS GONE -- 40 learned, 8 carried ------------------------------
add(arm("wall", function()
  local many = {}
  for id = 2, 158, 4 do many[#many + 1] = id end       -- 40 species
  _G.__many = many
  teach(many)
  loadout(nil)
end, function()
  H.assertEq(H.readByte(COUNT), #_G.__many,
    "wall: AUTO offers every one of the " .. #_G.__many .. " learned species")
  H.log("wall: AUTO count = " .. H.readByte(COUNT))
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
    .. "AUTO is vanilla to the byte, a set loadout is exactly the slots")
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

local function pinGau()
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, GAU)                  -- CHAR::GAU
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)          -- clear magitek
    H.writeByte(0x202E + s * 12, CMD_RAGE)            -- Rage, alone
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
    -- park the bench: an un-driven party menu pauses the battle, and these
    -- arms drive nothing after the confirm (battle_bushido's own rule).
    for _, s in ipairs(PARTY) do
      if s ~= actor then
        H.writeByte(ST3(s * 2), H.readByte(ST3(s * 2)) | 0x10)
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
      actor, pinMp, pinPend = nil, true, 0
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
  -- the latch must not move.
  ride(90),                               -- several more possessed turns
  H.call(function()
    H.assertEq(raging(actor), true, "still possessed after riding the trance")
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
add(trance("tier3", function() startMp = 50; pinPend = 3 end, function() end))
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
  ride(90),                               -- several more possessed turns
  H.call(function()
    H.assertEq(H.readByte(RAGETIER), 3,
      "and it is STILL 3 after several possessed turns -- the mid-trance "
      .. "Cmd_10 re-entries did not re-latch the consumed pending byte")
    H.assertEq(H.readByte(0x3E9D + actor * 2), 0,
      "the pending boost itself was consumed by the start action")
    H.log("PASSED: list filter, trance price, refusal gate and tier latch")
  end),
})

H.run({ maxFrames = 90000 }, steps)
