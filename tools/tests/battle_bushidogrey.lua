-- @suite
-- battle_bushidogrey.lua -- v0.5 MP costs + BP gating: the SwdTech submenu greys
-- what Cyan cannot reach, for TWO reasons -- not enough MP (like Magic/Blitz),
-- and not enough BP (the boost the row would spend).
--
-- Vanilla Magic greys a spell whose MP cost exceeds current MP: UpdateEnabledMagic
-- rolls a "disabled" bit, DrawMagicListText turns it into $04 OR'd into the row's
-- $21 white font byte -> $25 grey.  The tools-shell verbs never inherited that;
-- Ot6AbilityGrey (ot6.asm, bank F0) ports it, and the row decorator OR's the
-- $00/$04 it returns into the name's font scope.  The Bushido submenu adds a
-- SECOND grey reason on top: each row IS a boost level (row r spends r BP), so a
-- row whose boost exceeds the caster's current bp ($3e9c) is unreachable too --
-- Ot6BushidoRowGrey OR's the same $04, and Ot6BushidoConfirm refuses to commit
-- it (battle_bushido asserts the refusal; this asserts the visual).
--
-- issue #38 put a 1-BP floor under every tech: the window is three rows and
-- row i = boost i+1.  The BP-grey rule is unchanged in shape (row's boost > bp
-- -> grey), but it now bites at 0 bp on EVERY row -- which is the answer to
-- "greyed or absent" for a 0-pip Cyan.  GREYED, deliberately: the list is a
-- price surface, so it must keep showing what the bank would buy (and at what
-- MP), exactly like an unaffordable spell; a list that changed LENGTH with the
-- wallet would also slide the row->boost identity under the player's cursor
-- between turns.  Assertion 4 pins that.
--
-- Cyan is INSTALLED into the opening guard fight the way battle_bushido pins
-- him: CHAR::CYAN ($3ED8), a Bushido-only command list ($202E), the weapon
-- SWDTECH flag ($3BA4/$3BA5 bit 1), and a pinned $2020 (ceiling 4 -> window
-- {Slash,QuadraSlam,Empowerer} at boosts 1/2/3).  Their costs:
--   Slash $57 3   Quadra Slam $58 4   Empowerer $59 5
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey):
--   1. MP GREY.  bp full (isolating MP), MP pinned to 3: Slash(3) is white,
--      Empowerer(5) is grey.  grey - white == $04.
--   2. BP GREY.  MP full (isolating BP), bp pinned to 2: row 2 = Empowerer
--      (boost 3 > 2 bp) is grey while Slash (boost 1) stays white.
--   3. BOTH CLEAR.  bp and MP full: Empowerer is white -- the grey tracks both
--      knobs, it is not unconditional.
--   4. ZERO BP GREYS EVERYTHING (#38).  MP full, bp 0: Slash -- the cheapest
--      rung, and white in every pass above -- is grey too, because boost 1 > 0.
--      The names are still DRAWN: greyed, not absent.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local KNOWN, ST_TOOLS = 0x2020, 0x30
local CMD_SWDTECH = 0x07
local WHITE, GREY = 0x21, 0x25
local PARTY = { 0, 1, 2 }

local ceiling = 4
local bpbank = 5                       -- current BP bank (mutated per pass)
local mpcur = 3                        -- current MP (mutated per pass)
local actor

local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- spaceless techs only, so each glyph run is contiguous in VRAM.
local NM = {
  Slash     = glyphs("Slash"),         -- row 0, boost 1, cost 3
  Empowerer = glyphs("Empowerer"),     -- row 2, boost 3, cost 5
  -- tech 1, the OLD 0x rung at ceiling 4.  #38 retired it off the bottom of
  -- the window, so it must not be on this page at all -- and its absence is
  -- what makes the 0-bp pass below discriminating (a four-row window would
  -- put Retort at boost 0, i.e. WHITE at 0 bp).
  Retort    = glyphs("Retort"),
}

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

local function pinCyan()
  H.writeWord(KNOWN, 0xFF00 | ceiling)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x02)               -- CHAR::CYAN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
    H.writeByte(0x202E + s * 12, CMD_SWDTECH)       -- Bushido, alone
    H.writeByte(0x2031 + s * 12, 0xFF)
    H.writeByte(0x2034 + s * 12, 0xFF)
    H.writeByte(0x2037 + s * 12, 0xFF)
    H.writeByte(0x3BA4 + s * 2, H.readByte(0x3BA4 + s * 2) | 0x02)
    H.writeByte(0x3BA5 + s * 2, H.readByte(0x3BA5 + s * 2) | 0x02)
    H.writeWord(0x3BF4 + s * 2, 999)
    H.writeWord(0x3C30 + s * 2, 99)                 -- max MP
    H.writeWord(0x3C08 + s * 2, mpcur)              -- the MP affordability knob
    H.writeByte(0x3E9C + s * 2, bpbank)             -- the BP knob
  end
end

local function openSub()
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinCyan(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the swdtech submenu opens (tools shell $30)")
end
local function closeSub()
  return H.driveUntil(function() return H.readByte(MSTATE) ~= ST_TOOLS end, 400, {
    H.call(function() pinCyan(); H.setPad({ "b" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "the submenu closes back to the command window")
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinCyan), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    actor = H.readByte(ACTOR)
    H.log(string.format("cyan installed in slot %d, ceiling %d", actor, ceiling))
  end),

  -- 1. MP GREY (bp full, MP = 3) --------------------------------------------
  H.call(function() bpbank = 5; mpcur = 3 end),
  openSub(),
  H.waitFrames(6),
  H.call(function() H.screenshot("bushido_grey_mp") end),
  H.call(function()
    local aS, aE = attrOf(NM.Slash), attrOf(NM.Empowerer)
    H.log(string.format("MP=3 attr: Slash=%s Empowerer=%s",
      aS and string.format("$%02x", aS) or "nil",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aS, WHITE, "Slash (cost 3, MP 3) renders white -- affordable")
    H.assertEq(aE, GREY, "Empowerer (cost 5, MP 3) renders grey -- unaffordable MP")
    H.assertEq(aE - aS, 0x04, "grey - white == $04, magic's own disabled-bit delta")
  end),

  -- 2. BP GREY (MP full, bp = 2) --------------------------------------------
  closeSub(),
  H.call(function() bpbank = 2; mpcur = 99 end),
  openSub(),
  H.waitFrames(6),
  H.call(function() H.screenshot("bushido_grey_bp") end),
  H.call(function()
    local aS, aE = attrOf(NM.Slash), attrOf(NM.Empowerer)
    H.log(string.format("bp=2 MP=99 attr: Slash=%s Empowerer=%s",
      aS and string.format("$%02x", aS) or "nil",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aS, WHITE, "Slash (boost 1, bp 2) white -- reachable")
    H.assertEq(aE, GREY, "Empowerer (boost 3 > 2 bp) grey -- not enough BP (MP full)")
  end),

  -- 3. BOTH CLEAR (bp and MP full) ------------------------------------------
  closeSub(),
  H.call(function() bpbank = 5; mpcur = 99 end),
  openSub(),
  H.waitFrames(6),
  H.call(function()
    local aE = attrOf(NM.Empowerer)
    H.log(string.format("bp=5 MP=99 -> Empowerer attr = %s",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aE, WHITE, "Empowerer white now -- the grey tracks both BP and MP")
  end),

  -- 4. ZERO BP GREYS EVERY ROW (#38's 1-BP floor) ---------------------------
  -- The presentation ruling, pinned: a 0-pip Cyan still SEES his three techs
  -- and their prices, all greyed and all refused (battle_bushido asserts the
  -- refusal).  Before #38 row 0 was boost 0 and stayed white at 0 bp.
  closeSub(),
  H.call(function() bpbank = 0; mpcur = 99 end),
  openSub(),
  H.waitFrames(6),
  H.call(function() H.screenshot("bushido_grey_bp0") end),
  H.call(function()
    local aS, aE = attrOf(NM.Slash), attrOf(NM.Empowerer)
    H.log(string.format("bp=0 MP=99 attr: Slash=%s Empowerer=%s",
      aS and string.format("$%02x", aS) or "nil",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aS ~= nil, true,
      "Slash is still DRAWN at 0 bp -- greyed, not absent (#38's presentation)")
    H.assertEq(aS, GREY, "Slash (boost 1 > 0 bp) grey -- no free rung any more")
    H.assertEq(aE, GREY, "Empowerer (boost 3 > 0 bp) grey too")
    -- the discriminator: the ceiling-4 window's TOP row is Slash at boost 1,
    -- not Retort at boost 0.  If a free rung still existed it would be here,
    -- drawn and WHITE, and Cyan would have a Bushido turn on an empty bank.
    H.assertEq(attrOf(NM.Retort), nil,
      "no Retort row at all -- the 0x rung is gone, so nothing on this page "
      .. "is reachable at 0 bp (#38)")
    H.log("PASSED: the SwdTech submenu greys the MP- and BP-unreachable rows only, "
      .. "and at 0 bp that is every row")
  end),
})
