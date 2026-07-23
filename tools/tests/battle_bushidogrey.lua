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
-- Cyan is INSTALLED into the opening guard fight the way battle_bushido pins
-- him: CHAR::CYAN ($3ED8), a Bushido-only command list ($202E), the weapon
-- SWDTECH flag ($3BA4/$3BA5 bit 1), and a pinned $2020 (ceiling 4 -> window
-- {Retort,Slash,QuadraSlam,Empowerer} at boosts 0/1/2/3).  Their costs:
--   Retort $56 2   Slash $57 3   Quadra Slam $58 4   Empowerer $59 5
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey):
--   1. MP GREY.  bp full (isolating MP), MP pinned to 3: Retort(2)/Slash(3) are
--      white, Empowerer(5) is grey.  grey - white == $04.
--   2. BP GREY.  MP full (isolating BP), bp pinned to 2: row 3 = Empowerer
--      (boost 3 > 2 bp) is grey while Retort/Slash (boosts 0/1) stay white.
--   3. BOTH CLEAR.  bp and MP full: Empowerer is white -- the grey tracks both
--      knobs, it is not unconditional.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

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
  Retort    = glyphs("Retort"),        -- boost 0, cost 2
  Slash     = glyphs("Slash"),         -- boost 1, cost 3
  Empowerer = glyphs("Empowerer"),     -- boost 3, cost 5
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
    local aR, aS, aE = attrOf(NM.Retort), attrOf(NM.Slash), attrOf(NM.Empowerer)
    H.log(string.format("MP=3 attr: Retort=%s Slash=%s Empowerer=%s",
      aR and string.format("$%02x", aR) or "nil",
      aS and string.format("$%02x", aS) or "nil",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aR, WHITE, "Retort (cost 2, MP 3) renders white -- affordable")
    H.assertEq(aS, WHITE, "Slash (cost 3, MP 3) renders white -- affordable")
    H.assertEq(aE, GREY, "Empowerer (cost 5, MP 3) renders grey -- unaffordable MP")
    H.assertEq(aE - aR, 0x04, "grey - white == $04, magic's own disabled-bit delta")
  end),

  -- 2. BP GREY (MP full, bp = 2) --------------------------------------------
  closeSub(),
  H.call(function() bpbank = 2; mpcur = 99 end),
  openSub(),
  H.waitFrames(6),
  H.call(function() H.screenshot("bushido_grey_bp") end),
  H.call(function()
    local aR, aS, aE = attrOf(NM.Retort), attrOf(NM.Slash), attrOf(NM.Empowerer)
    H.log(string.format("bp=2 MP=99 attr: Retort=%s Slash=%s Empowerer=%s",
      aR and string.format("$%02x", aR) or "nil",
      aS and string.format("$%02x", aS) or "nil",
      aE and string.format("$%02x", aE) or "nil"))
    H.assertEq(aR, WHITE, "Retort (boost 0, bp 2) white -- reachable")
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
    H.log("PASSED: the SwdTech submenu greys the MP- and BP-unreachable rows only")
  end),
})
