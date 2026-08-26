-- @suite
-- battle_rage.lua -- Gau's 8-slot rage loadout, asserted at the one choke point.

-- Veldt learning is unlimited: LearnRage and the 32-byte $1d2c-$1d4b bitfield
-- are untouched. Only the battle menu is narrowed, to eight slots the player
-- configures in the field. The narrowing happens in one place: the flat list
-- InitSkills builds at $257e once per battle. Everything downstream (window
-- draw, confirm, scroll cap, RandRage's confused-rager pick) reads that list,
-- so this test asserts the list, byte for byte.

-- InitSkills does not terminate the rage region itself; the $ff fill comes
-- from InitBattle, which fills $2000-$341f with $ff before calling
-- InitSkills. Past the last known rage, the region is $ff all the way to the
-- dance list at $267e.

-- Gau is not recruitable at this fixture, so he is installed manually:
-- CHAR::GAU into $3ED8 and a Rage-only command list at $202E. The rage
-- window is battle menu state $1e; its cursor is scroll $892b,y / column
-- $892f,y / row $8933,y indexed by the actor slot, entry = (scroll + row) * 2
-- + column.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local MENU = 0x7BCA
local RAGES = 0x1D2C                 -- learned-rage bitfield, 32 bytes
local RAGELOAD = 0x1E1F              -- OT6_RAGELOAD: 8 bytes, id+1, 0 = unset
local LIST, COUNT = 0x257E, 0x3A9A   -- the flat battle list and its length
local DANCELIST = 0x267E             -- the dance list starts here: our ceiling

-- eleven species, ascending, spread over several bitfield bytes so the walk
-- crosses byte boundaries.
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

-- ids currently in the learned-rage bitfield, in id order.
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
-- battle, and read the list InitSkills just built. InitSkills runs exactly
-- once, from InitBattle, so a savestate reload per arm is the only way to
-- re-run it.
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

local AUTO8 = head(KNOWN, 8)
add(arm("auto", function()
  teach(KNOWN)
  loadout(nil)                       -- all eight bytes zero = AUTO
end, function()
  assertList(AUTO8, "auto")
  H.assertEq(#learnedIds(), #KNOWN,
    "auto: and the COLLECTION is untouched -- $1d2c still holds all "
    .. #KNOWN .. " species")
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

-- 2. Manual: the stored ids, in slot order ----------------------------------
add(arm("manual", function()
  teach(KNOWN)
  loadout({ 130, 3, 55, 7 })         -- four slots, deliberately NOT id order
end, function()
  assertList({ 130, 3, 55, 7 }, "manual")
  H.log("MANUAL: four slots -> four ids in the player's order, not the id order")
end))

-- 3. Validation: a stored but unlearned id is dropped -----------------------
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

add(arm("eight", function()
  teach(KNOWN)
  loadout({ 130, 111, 90, 68, 55, 41, 33, 20 })
end, function()
  assertList({ 130, 111, 90, 68, 55, 41, 33, 20 }, "eight")
  H.log("FULL EIGHT: exactly eight ids then $ff -- the battle menu is now as "
    .. "long as Sabin's, chosen from everything he has hunted")
end))

-- 5. The wall is unreachable: 40 learned, 8 carried, collection untouched ---
add(arm("wall", function()
  local many = {}
  for id = 2, 158, 4 do many[#many + 1] = id end       -- 40 species
  _G.__many = many
  teach(many)
  loadout(nil)                                         -- AUTO: never configured
end, function()
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

-- ============================== The trance ==================================
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
local instrument, cmd10HitsReset
local cmd10Hits = 0     -- Cmd_10 entries
local coinSummary
local coins = {}        -- one entry per possessed turn
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
    -- pinPend is nil once the rage has been confirmed, so re-pinning does not
    -- overwrite the pending byte the latch is about to read.
    if pinPend then H.writeByte(0x3E9D + actor * 2, pinPend) end
    if pinMp then H.writeWord(CURMP(actor), startMp) end
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

-- One driving tick: re-pin the fixture and clear any other character's open
-- menu, since an open menu pauses the battle and these arms need the ATB to
-- keep running. It never presses into the rage window itself.
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

-- 6a. The price: flat 8 at the start, nothing on the possessed turns --------
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

-- 6b. The refusal: a Gau who cannot pay does not get the state for free -----
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

-- 7. The tier latch: 3 BP banked at the start, held for the whole trance ----
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
    -- tier 3 takes no roll at all (no `inc $be`) and forces entry 1 on every
    -- possessed turn, including the start turn.
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

-- ====================== 8. The tier ladder's odds ===========================
--   tier 1   the special unless draw < $40   -> $3f = Fight, $40 = special
--   tier 2   the special unless draw < $10   -> $0f = Fight, $10 = special

-- The coin is read straight off the MonsterRage table: X is monsterId*2 +
-- coin, entry 0 is always plain Fight, entry 1 the monster's special.

-- Ot6RageCoin is entered from a site whose index width is unknown, does
-- `rep #$10` to park Y, and must hand the caller's width back by hand
-- (`plp` would also restore the stale carry it exists to replace). The call
-- site is located by scanning RandRage for the `jsl` to Ot6RageCoin.
local RNGTBL   = H.sym("RNGTbl") & 0x3FFFFF
local MONRAGE  = H.sym("MonsterRage")
local COINPROC = H.sym("Ot6RageCoin")
local RANDRAGE = H.sym("RandRage")

local psAtEntry, yAtEntry = nil, nil
local drawsThisRoll, beAtRand, tierAtEntry = 0, nil, nil
local widthChecks = {}
local instrumented = false

-- Mesen exposes the CPU registers as flat "cpu.<field>" keys; the flag byte's
-- key name is resolved once (and logged) rather than hardcoded.
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

-- the $be seed whose next draw is exactly `want`
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
  -- RNGTbl must be a permutation, or "pinned at the boundary" is not true
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

  -- the proc's single `inc $be` is ot6_rand's rolling index bump; an exec
  -- callback there counts draws taken (tier 0 takes none) and records the
  -- index about to be read.
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

  -- pin the draw and snapshot the caller's state, at the proc's own entry
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

  -- counts Cmd_10 re-entries per possessed turn
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
-- every possessed turn come up the same way.
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
        H.assertEq(e.tier, pend, tag .. ": every roll saw the latched tier "
          .. "-- the START turn included (it is rolled at action load)")
        -- tiers 1 and 2 spend exactly one extra draw per turn: the one pinned here
        H.assertEq(e.draws, 1, string.format(
          "%s: the tilted coin took exactly one extra RNG draw", tag))
        H.assertEq(e.seed, seed, string.format(
          "%s: and it read RNGTbl[$be+1] with $be = %d -- the pinned draw $%02x",
          tag, seed, draw))
      end
    end),
  })
end

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

-- tier 1: the special unless a fresh draw < $40, from both sides of $3f/$40
tierArm("t1-under", 1, 0x3F, 0, "draw $3f < $40, so the coin falls to Fight")
tierArm("t1-over",  1, 0x40, 1, "draw $40 >= $40, so the special wins")
-- tier 2: the same compare at $10, and $3f, which tier 1 refused, now wins,
-- which shows the ladder converging rather than two unrelated thresholds
tierArm("t2-under", 2, 0x0F, 0, "draw $0f < $10, so the coin falls to Fight")
tierArm("t2-over",  2, 0x10, 1, "draw $10 >= $10, so the special wins")
tierArm("t2-at-t1-boundary", 2, 0x3F, 1,
  "the very draw that MISSED at tier 1 now hits -- 3/4 -> 15/16")

-- The width restore, on a tier-1 trance. The caller's index-width bit and Y
-- must come back unchanged across the jsl; the carry is the one thing the
-- proc is allowed to replace.
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

local COSTQ = 0x3620                 -- the queued-cost cell CreateAction writes
local CMD_LEAP = 0x11
local LEAP_COST = 0
local leapCosts = {}
local leapWatch = false
local caeHits = 0                    -- CalcAttackEffect entries in the window
local mpSeen = {}                    -- pool samples taken while the battle LIVES

add({
  H.call(function()
    emu.addMemoryCallback(function(_, v)
      if leapWatch and H.readByte(0x3A7A) == CMD_LEAP then
        leapCosts[#leapCosts + 1] = v
      end
    end, emu.callbackType.write, 0x7E0000 + COSTQ, 0x7E0000 + COSTQ + 0xFE)
    -- positive control: CalcAttackEffect reads the staged cost and debits
    -- the pool, refusing when short; counting its entries confirms it ran.
    emu.addMemoryCallback(function() caeHits = caeHits + 1 end,
      emu.callbackType.exec, H.sym("CalcAttackEffect"), H.sym("CalcAttackEffect"))
  end),
})

-- Sample the pool while the battle is alive, and stop when it is not.
local function sampleWhileLive(n)
  return H.repeatN(n, {
    H.call(function()
      tick()
      if H.battleActive() then mpSeen[#mpSeen + 1] = mp(actor) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  })
end

local function poolFloor()
  local lo = nil
  for _, v in ipairs(mpSeen) do if not lo or v < lo then lo = v end end
  return lo
end

-- 9a. The price, at a full pool, so affordability is not in play.
add(trance("leap", function()
  startMp = 20
  cmd0 = CMD_LEAP
end, function()
  leapCosts = {}; mpSeen = {}; caeHits = 0; leapWatch = true
end))
add({
  H.pressButtons({ "a" }, 4),          -- the menu's only row is Leap
  H.waitFrames(10),
  H.call(function() pinMp = false; pinPend = nil end),
  H.driveUntil(function() return #leapCosts > 0 end, 8000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "leap: CreateAction stages a cost for command $11"),
  sampleWhileLive(30),
  H.call(function()
    leapWatch = false
    H.log(string.format("leap: pool floor %s over %d live samples, cost queue "
      .. "%s, CalcAttackEffect entries %d (post-window read %d, battle live=%s)",
      tostring(poolFloor()), #mpSeen, tostring(leapCosts[1]), caeHits,
      mp(actor), tostring(H.battleActive())))
    H.assertEq(leapCosts[1], LEAP_COST,
      "CreateAction staged 0 for command $11: Ot6AbilityCost has no cmd-$11 "
      .. "arm any more, so the leap falls out of the chain with vanilla's own "
      .. "cost.  Pre-change this read 2 (Ot6LeapCost)")
    H.assertEq(caeHits > 0, true, string.format(
      "positive control: CalcAttackEffect actually RAN (%d entries) -- it is "
      .. "the site that reads the staged cost and debits the pool, so without "
      .. "this count 'the pool did not move' would pass on a turn that never "
      .. "resolved", caeHits))
    H.assertEq(#mpSeen > 0, true,
      "positive control: the pool was sampled inside a LIVE battle")
    H.assertEq(poolFloor(), 20,
      "and the universal charge took NOTHING: across every live sample the "
      .. "pool never dipped below where it started.  Pre-change its floor was "
      .. "18 -- the flat 2 Ot6LeapCost handed back")
  end),
})

add(trance("leap-zero", function()
  startMp = 0
  cmd0 = CMD_LEAP
end, function()
  leapCosts = {}; mpSeen = {}; caeHits = 0; leapWatch = true
end))
add({
  H.pressButtons({ "a" }, 4),
  H.waitFrames(10),
  H.call(function() pinMp = false; pinPend = nil end),
  H.driveUntil(function() return #leapCosts > 0 end, 8000, {
    H.call(tick), H.waitFrames(3),
    H.call(function() H.setPad({}) end), H.waitFrames(6),
  }, "leap-zero: CreateAction stages a cost for command $11 on an empty pool"),
  sampleWhileLive(60),
  H.call(function()
    leapWatch = false
    H.log(string.format("leap-zero: pool floor %s over %d live samples, cost "
      .. "queue %s, CalcAttackEffect entries %d (post-window read %d, battle "
      .. "live=%s)", tostring(poolFloor()), #mpSeen, tostring(leapCosts[1]),
      caeHits, mp(actor), tostring(H.battleActive())))
    H.assertEq(leapCosts[1], LEAP_COST,
      "an EMPTY pool stages the same 0: the price does not depend on what the "
      .. "caster can afford, so there is nothing left for the insufficient-MP "
      .. "gate to refuse.  Pre-change this staged 2, and CalcAttackEffect's "
      .. "short-pool arm ate the turn")
    H.assertEq(caeHits > 0, true, string.format(
      "positive control: CalcAttackEffect actually RAN (%d entries) on the "
      .. "empty pool -- the gate had its chance and declined to fire, which "
      .. "is the whole claim", caeHits))
    H.assertEq(#mpSeen > 0, true,
      "positive control: the pool was sampled inside a LIVE battle")
    H.assertEq(poolFloor(), 0,
      "and the pool is still 0 across every live sample -- nothing spent, "
      .. "nothing driven negative.  A Gau at zero MP can still take the "
      .. "Veldt's action, which is what makes sharing the FIGHT row safe")
    H.log("PASSED: list filter + AUTO truncation, trance price, refusal gate, "
      .. "tier latch, the tier-1/tier-2 coin at both boundaries, the width "
      .. "restore, and Leap free at a full pool and at zero")
  end),
})

H.run({ maxFrames = 240000 }, steps)
