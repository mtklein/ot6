-- @suite slow savestate=camp_escaped
-- battle_shadowstays.lua -- the vanilla 1/16 Shadow-leave roll, PASSING, on
-- the fixed ROM: Shadow stays, the battle ends normally, nothing halts.
--
-- Vanilla FF6 rolls once after every WON battle with guest Shadow aboard
-- (battle_main.asm, CheckBattleEnd's win path: `ldx $3003` / `jsr Rand` /
-- `cmp #$10` / `bcs` ... `bit $1ede` / `bne ShadowLeaves`).  ShadowLeaves is
-- `jmp Ot6ShadowLeaves`; until 3fffb2a that body was linked into bank $CF, so
-- the bank-relative jmp landed on decompress code's data at $C2:FE00 and the
-- CPU ran into a STP -- every passing roll froze the game.  The fix moves
-- Ot6ShadowLeaves into bank $C2 as a deliberate no-op (`jsr WinBattle` /
-- `jmp _488f`): Shadow stays for the whole game (owner's call, 2026-09-01).
--
-- No suite test had ever seen the roll PASS on the fixed ROM.  This one
-- fights honest random battles on the World of Balance from camp_escaped
-- (SABIN, CYAN, guest SHADOW at world (179,71)) -- the shared navigator's
-- tactical fight driver through the real battle menus, Tonic care through
-- the field menu after every fight, no fleeing, no state writes -- until the
-- roll passes, and asserts on that battle.  Every assertion is backed by an
-- observation: an exec callback on a symbol-resolved address, or a RAM read.
--   (a) it terminates normally: exec callbacks see ShadowLeaves >
--       Ot6ShadowLeaves > WinBattle > _488f > UpdateSRAM > TerminateBattle in
--       that order and nothing else from that set in between; the world
--       comes back under control (the world-module registers, read every
--       frame, settle within a bound); and the field menu still opens and
--       closes on real X/B presses afterward (ZMENUSTATE read at $26);
--   (b) no STP: nothing executes in $C2:FE00-$C2:FFFF between ShadowLeaves
--       and TerminateBattle (decompress code owns that range on every
--       battle LOAD, so the window is the win path only), and the halt site
--       $C2:FEF9 -- verified to hold a $DB STP in this ROM before the run --
--       never executes at all;
--   (c) $1ede keeps Shadow's bit, $3003 held his slot at the roll, and he is
--       still enrolled in the party ($1850) on the field afterward;
--   (d) the win path still ran: WinBattle executed once more for that fight.
--
-- The bound.  The roll is 1/16 per ELIGIBLE win (front attack, $201f = 0;
-- two or more characters up; Shadow not dead/petrified/zombied; $3ebd.3
-- clear; $1ede.3 set), so the wins are capped at MAX_WINS and a run that
-- never sees the roll pass fails with the counts.  The emulation is
-- bit-reproducible, so the number of wins this takes is a property of the
-- fixture plus SETTLE (the idle frames before the first step), not a coin
-- flip: see the [shadowstays] lines in the log.  A world-map fight here
-- costs ~3000-4500 frames, so 80 wins is ~320k frames; the suite edge
-- carries a raised OT6_TIMEOUT for that (see configure.py TEST_ENV).

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/camp_escaped.mss.lua"
local MAX_WINS = 80
local SETTLE = 30                       -- idle frames after the load, before
                                        -- the first step: the RNG lever
local SHADOW = 3                        -- character id
local SHADOW_BIT = 1 << SHADOW          -- $1ede.3
-- the two world tiles the grind bounces between: the fixture's landing and
-- a tile on gen_sabin_forest's own walk to the forest, short of the
-- (178,82) entrance
local TILE_A, TILE_B = { 179, 71 }, { 178, 80 }
local ZMENUSTATE = 0x26                 -- DP: $05 = the main menu is up
local MENU_SCREENS = { [0x05] = true, [0x06] = true, [0x08] = true,
  [0x0A] = true, [0x17] = true, [0x18] = true, [0x19] = true, [0x1A] = true,
  [0x3B] = true, [0x3D] = true, [0x64] = true, [0x70] = true }
local STP_SITE = 0xC2FEF9               -- where the mis-banked jmp halted

local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) ~= 0 end
local function shadowAvail() return (H.readByte(0x1ede) & SHADOW_BIT) ~= 0 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end

-- ------------------------------------------------------------ the hooks --
-- Every name is resolved by symbol from ff6-en.dbg (H.sym raises on a
-- missing or ambiguous one): a relinked ROM moves the addresses, never the
-- meaning.  Each call takes a string LITERAL on purpose: compose.py finds
-- the names by scanning for `H.sym("...")` and injects only those, so a
-- name passed through a variable is "not in ff6-en.dbg" at load time.
local SYM = {
  ShadowLeaves = H.sym("ShadowLeaves"),
  Ot6ShadowLeaves = H.sym("Ot6ShadowLeaves"),
  WinBattle = H.sym("WinBattle"),
  _488f = H.sym("_488f"),
  UpdateSRAM = H.sym("UpdateSRAM"),
  TerminateBattle = H.sym("TerminateBattle"),
  ["Rand@battle_code"] = H.sym("Rand@battle_code"),
}
H.assertEq(SYM.Ot6ShadowLeaves >> 16, 0xC2,
  "Ot6ShadowLeaves is linked into bank $C2 (the fix: a bank-relative jmp "
  .. "can reach it)")
H.assertEq(SYM.Ot6ShadowLeaves < 0xC2FE00, true,
  "Ot6ShadowLeaves sits below decompress code's $C2:FE00 data table")

-- The roll site has no exported label: CheckBattleEnd's `@4861: ldx $3003`
-- block is fixed vanilla code, $2B bytes ending at `@488c: jsr WinBattle`,
-- three bytes before the exported `_488f`.  Derive it and verify the bytes
-- before trusting the derivation.
local ROLL_BASE = SYM._488f - 3 - 0x2B
local function romByte(cpu) return H.readRomByte(cpu & 0x3FFFFF) end
local function verifyRollSite()
  local want = { 0xAE, 0x03, 0x30,                 -- ldx $3003
                 0x30, false,                      -- bmi @488c
                 0x20, SYM["Rand@battle_code"] & 0xFF,
                       (SYM["Rand@battle_code"] >> 8) & 0xFF,   -- jsr Rand
                 0xC9, 0x10,                       -- cmp #$10
                 0xB0, false,                      -- bcs @488c
                 0xAD, 0x1F, 0x20 }                -- lda $201f
  for i = 1, #want do
    if want[i] then
      H.assertEq(romByte(ROLL_BASE + i - 1), want[i], string.format(
        "roll site byte %d at $%06X (the vanilla ldx $3003 / jsr Rand / "
        .. "cmp #$10 block before _488f)", i - 1, ROLL_BASE + i - 1))
    end
  end
  -- ShadowLeaves itself is the fix's jmp: 4C lo hi to Ot6ShadowLeaves
  H.assertEq(romByte(SYM.ShadowLeaves), 0x4C, "ShadowLeaves is a jmp")
  H.assertEq(romByte(SYM.ShadowLeaves + 1) | (romByte(SYM.ShadowLeaves + 2) << 8),
    SYM.Ot6ShadowLeaves & 0xFFFF, "ShadowLeaves jumps to Ot6ShadowLeaves")
  -- (b)'s halt site is only evidence if it is still a STP in this ROM
  H.assertEq(romByte(STP_SITE), 0xDB, string.format(
    "$%06X holds $DB (STP): the byte the mis-banked jmp used to run into",
    STP_SITE))
end
local ROLL_RAND = ROLL_BASE + 5          -- the jsr Rand: a roll was taken
local ROLL_PASSED = ROLL_BASE + 12       -- the lda $201f: the 1/16 came up

-- Counters.  `at` records the frame of the LAST hit; `seq` records the
-- order of the win-path hits from the frame ShadowLeaves fired.
local N = {}
local AT = {}
local seq = {}
local fired = nil                        -- frame ShadowLeaves fired
local rollSnap = nil                     -- RAM at ShadowLeaves
local terminated = nil                   -- frame TerminateBattle ran after the fire
local backAt = nil                       -- frame the world settled after that
local landHits, landFirst = 0, {}        -- $C2:FE00-FFFF exec inside the window
local stpHits = 0                        -- $C2:FEF9 exec, ever
local wins = {}                          -- per WinBattle: { frame, $201f }
local rolls, passes = 0, 0

-- fnFirst: run fn before the seq append (ShadowLeaves opens the window
-- with its own hit); otherwise after (TerminateBattle closes it with its own).
local function hook(name, addr, fn, fnFirst)
  N[name] = 0
  emu.addMemoryCallback(function()
    N[name] = N[name] + 1
    AT[name] = H.frame
    if fnFirst and fn then fn() end
    if fired and not terminated then seq[#seq + 1] = name end
    if not fnFirst and fn then fn() end
  end, emu.callbackType.exec, addr, addr)
end

hook("ShadowLeaves", SYM.ShadowLeaves, function()
  fired = fired or H.frame
  local x = H.readByte(0x3003)
  rollSnap = rollSnap or {
    slot3003 = x, status1 = H.readByte(0x3ee4 + (x & 0x7f)),
    type201f = H.readByte(0x201f), chars3a76 = H.readByte(0x3a76),
    flags3ebd = H.readByte(0x3ebd), avail1ede = H.readByte(0x1ede),
    nwins = #wins,
  }
  H.log(string.format("[shadowstays] f%d the 1/16 roll PASSED after %d "
    .. "win(s), %d roll(s): ShadowLeaves ($%06X) $3003=%02X status1=%02X "
    .. "$201f=%02X $3a76=%d $3ebd=%02X $1ede=%02X", H.frame, #wins, rolls,
    SYM.ShadowLeaves, x, rollSnap.status1, rollSnap.type201f,
    rollSnap.chars3a76, rollSnap.flags3ebd, rollSnap.avail1ede))
end, true)
hook("Ot6ShadowLeaves", SYM.Ot6ShadowLeaves, function()
  H.log(string.format("[shadowstays] f%d Ot6ShadowLeaves ($%06X) $1ede=%02X",
    H.frame, SYM.Ot6ShadowLeaves, H.readByte(0x1ede)))
end)
hook("WinBattle", SYM.WinBattle, function()
  wins[#wins + 1] = { frame = H.frame, type = H.readByte(0x201f) }
end)
hook("_488f", SYM._488f)
hook("UpdateSRAM", SYM.UpdateSRAM)
hook("TerminateBattle", SYM.TerminateBattle, function()
  if fired and not terminated then
    terminated = H.frame
    H.log(string.format("[shadowstays] f%d TerminateBattle %d frame(s) after "
      .. "the roll; win path %s; $C2:FE00-FFFF exec in the window: %d",
      H.frame, H.frame - fired, table.concat(seq, " > "), landHits))
  end
end)
emu.addMemoryCallback(function() rolls = rolls + 1 end,
  emu.callbackType.exec, ROLL_RAND, ROLL_RAND)
emu.addMemoryCallback(function() passes = passes + 1 end,
  emu.callbackType.exec, ROLL_PASSED, ROLL_PASSED)

-- (b): where the mis-banked jmp used to land, and the STP it ran into.
-- decompress code legitimately executes in $C2:FE00-$C2:FFFF on every
-- battle load, so only the window from ShadowLeaves to TerminateBattle
-- counts against the fix.
emu.addMemoryCallback(function(a)
  if fired and not terminated then
    landHits = landHits + 1
    if #landFirst < 8 then landFirst[#landFirst + 1] = string.format("%06X", a or -1) end
  end
end, emu.callbackType.exec, 0xC2FE00, 0xC2FFFF)
emu.addMemoryCallback(function()
  stpHits = stpHits + 1
end, emu.callbackType.exec, STP_SITE, STP_SITE)

-- ------------------------------------------------------------ the grind --
-- The ride ends once the roll has passed AND that battle has torn down and
-- the world is back under control; or once MAX_WINS wins have passed with
-- the roll never coming up (the fail case, asserted below).
local function settled()
  return not H.battleLoadStarted() and H.worldHasControl()
     and H.worldAligned() and bright() >= 15
end
local function stop()
  if fired then return terminated ~= nil and settled() end
  return #wins >= MAX_WINS and settled()
end

-- bounce between TILE_A and TILE_B on the shared world navigator: every
-- encounter is fought tactically through the real menus, and each fight is
-- followed by the navigator's own between-battles care stop (Tonics
-- through the field menu) before walking on.
local function grind()
  local leg, toB, legs = nil, true, 0
  local hb = -1200
  return {
    tick = function()
      if terminated and not backAt and settled() then
        backAt = H.frame
        H.log(string.format("[shadowstays] f%d the world is back under control "
          .. "%d frame(s) after TerminateBattle (%d after the roll) at (%d,%d)",
          H.frame, backAt - terminated, backAt - fired, H.worldX(), H.worldY()))
      end
      if stop() then H.setPad({}); return "done" end
      if H.frame - hb >= 1200 then
        hb = H.frame
        H.log(string.format("[shadowstays] f%d wins=%d rolls=%d passes=%d "
          .. "legs=%d tonic=%d potion=%d fenix=%d", H.frame, #wins, rolls,
          passes, legs, H.invCountOf(0xE8), H.invCountOf(0xE9),
          H.invCountOf(0xF0)))
      end
      if not leg then
        local t = toB and TILE_B or TILE_A
        toB = not toB
        legs = legs + 1
        leg = H.worldNavTo(t[1], t[2], { maxFrames = 20000,
          playBattles = "tactical", arrive = stop })
      end
      if leg:tick() == "done" then leg = nil end
      return "frame"
    end,
  }
end

-- The field menu, opened and closed on real presses after the roll battle:
-- X until ZMENUSTATE reads $05 (the main menu), B until it reads no menu
-- screen and the world module has held control for 30 consecutive frames
-- (the same debounce the lib's care close uses on the world map, where the
-- registers can read stale-live mid-handoff).
local menuAt = nil
local function menuRoundTrip()
  local ph, calm = 0, 0
  -- H.cond(always, steps) is the lib's step-group idiom: H.run wants one
  -- step per slot, not a bare list
  return H.cond(function() return true end, {
    H.driveUntil(function()
      if H.readByte(ZMENUSTATE) == 0x05 then menuAt = menuAt or H.frame; return true end
      return false
    end, 1800, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { "x" } or {})
      end),
    }, "field menu open (ZMENUSTATE $05) after the roll battle"),
    H.release(),
    H.waitFrames(10),
    H.driveUntil(function()
      local ok = H.worldHasControl() and H.worldAligned()
             and not MENU_SCREENS[H.readByte(ZMENUSTATE)]
      calm = ok and calm + 1 or 0
      return calm >= 30
    end, 2400, {
      H.call(function()
        ph = (ph + 1) % 12
        H.setPad(ph < 4 and { "b" } or {})
      end),
    }, "field menu closed, world control back"),
    H.release(),
  })
end

local before = {}

H.run({ maxFrames = 600000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(SETTLE),
  H.call(function()
    verifyRollSite()
    H.assertEq(H.worldMode(), true, "camp_escaped starts on the World of Balance")
    H.assertEq(inParty(SHADOW), true, "SHADOW is enrolled in the party")
    H.assertEq(shadowAvail(), true, "$1ede has Shadow's bit (he is a guest the roll can see)")
    before.members = #H.partyMembers()
    before.hp = H.charHp(SHADOW)
    H.log(string.format("[shadowstays] start f%d settle=%d world (%d,%d) party=%d "
      .. "shadow %d/%d hp tonic=%d potion=%d fenix=%d", H.frame, SETTLE,
      H.worldX(), H.worldY(), before.members, before.hp, H.charMaxHp(SHADOW),
      H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0)))
  end),

  grind(),

  -- the verdict on the search itself
  H.call(function()
    local eligible = 0
    for _, w in ipairs(wins) do if w.type == 0 then eligible = eligible + 1 end end
    H.log(string.format("[shadowstays] search over at f%d: %d win(s), %d "
      .. "front-attack, %d roll(s) taken, %d passed; ShadowLeaves x%d "
      .. "Ot6ShadowLeaves x%d WinBattle x%d TerminateBattle x%d", H.frame,
      #wins, eligible, rolls, passes, N.ShadowLeaves, N.Ot6ShadowLeaves,
      N.WinBattle, N.TerminateBattle))
    if not fired then
      error(string.format("the 1/16 Shadow-leave roll never passed in %d "
        .. "won battles (%d eligible front attacks, %d rolls taken, %d "
        .. "passed the cmp #$10) -- raise MAX_WINS, vary SETTLE, or pick a "
        .. "fixture with more eligible wins", #wins, eligible, rolls, passes), 0)
    end
  end),

  -- (a) the battle terminated normally, in order, and the world is back
  H.call(function()
    H.assertEq(N.ShadowLeaves, 1, "ShadowLeaves ran exactly once")
    H.assertEq(N.Ot6ShadowLeaves, 1, "Ot6ShadowLeaves (bank $C2) ran exactly once")
    H.assertEq(AT.Ot6ShadowLeaves, fired, "Ot6ShadowLeaves ran on the roll's frame")
    H.assertEq(terminated ~= nil, true, "TerminateBattle ran after the roll")
    H.assertEq(table.concat(seq, ">"),
      "ShadowLeaves>Ot6ShadowLeaves>WinBattle>_488f>UpdateSRAM>TerminateBattle",
      "the win path in order: ShadowLeaves > Ot6ShadowLeaves > WinBattle > "
      .. "_488f > UpdateSRAM > TerminateBattle")
    H.assertEq(terminated - fired < 1200, true, string.format(
      "TerminateBattle within 1200 frames of the roll (took %d)", terminated - fired))
    H.assertEq(backAt ~= nil, true, "the world settled (control, aligned, bright) after the roll battle")
    H.assertEq(backAt - terminated < 1200, true, string.format(
      "the world was back within 1200 frames of TerminateBattle (took %d)",
      backAt - terminated))
    H.assertEq(settled(), true, "back on the world map with control after the roll battle")
  end),
  -- (b) no STP, nowhere near the old landing
  H.call(function()
    H.assertEq(landHits, 0, "nothing executed in $C2:FE00-$C2:FFFF between "
      .. "ShadowLeaves and TerminateBattle" .. (landHits > 0 and
      (" (first: " .. table.concat(landFirst, " ") .. ")") or ""))
    H.assertEq(stpHits, 0, "the STP at $C2:FEF9 never executed")
    H.assertEq(H.frame > terminated + 30, true, "the CPU kept running past the teardown")
  end),
  -- (c) Shadow stays
  H.call(function()
    H.assertEq(rollSnap.slot3003 & 0x80, 0, "$3003 held Shadow's slot at the roll")
    H.assertEq(rollSnap.avail1ede & SHADOW_BIT, SHADOW_BIT, "$1ede had Shadow's bit at the roll")
    H.assertEq(shadowAvail(), true, "$1ede still has Shadow's bit on the field")
    H.assertEq(inParty(SHADOW), true, "SHADOW is still enrolled in the party")
    H.assertEq(#H.partyMembers(), before.members, "the party is the same size as at the start")
    H.log(string.format("[shadowstays] (c) f%d $1ede=%02X $1850+3=%02X party={%s} "
      .. "shadow %d/%d hp", H.frame, H.readByte(0x1ede), H.readByte(0x1850 + SHADOW),
      table.concat(H.partyMembers(), ","), H.charHp(SHADOW), H.charMaxHp(SHADOW)))
  end),
  -- (d) the win path ran for that fight
  H.call(function()
    H.assertEq(#wins, rollSnap.nwins + 1, "WinBattle ran once more for the roll battle")
    H.assertEq(wins[#wins].frame >= fired, true, "that WinBattle came after ShadowLeaves")
    H.assertEq(wins[#wins].type, 0, "the roll battle was a front attack ($201f = 0)")
    H.assertEq(N.WinBattle, N.TerminateBattle, "every fight won terminated")
  end),

  -- (a), the rest: the field menu opens and closes on real presses, and the
  -- CPU is still taking input
  menuRoundTrip(),
  H.call(function()
    H.assertEq(menuAt ~= nil, true, "the field menu opened (ZMENUSTATE $05) after the roll battle")
    H.assertEq(settled(), true, "the world is back under control after the menu closed")
    H.log(string.format("[shadowstays] (a) f%d field menu opened at f%d and closed; "
      .. "ZMENUSTATE=%02X", H.frame, menuAt, H.readByte(ZMENUSTATE)))
  end),

  -- the directive after the last fight too: Tonic care through the field
  -- menu (a no-op when nobody needs it)
  H.fieldCare({ threshold = 0.65, tag = "care after the roll battle" }),
  H.call(function()
    H.assertPartyStanding("after the roll battle")
    H.assertEq(inParty(SHADOW), true, "SHADOW still aboard after care")
    H.log(string.format("[shadowstays] PASSED: the roll passed on win %d at f%d, "
      .. "the battle ended at f%d, the world was back at f%d, Shadow stays "
      .. "($1ede=%02X)", rollSnap.nwins + 1, fired, terminated, backAt,
      H.readByte(0x1ede)))
  end),
})
