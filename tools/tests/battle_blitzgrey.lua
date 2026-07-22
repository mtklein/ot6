-- @suite
-- battle_blitzgrey.lua -- v0.5 MP costs: the Blitz menu greys what Sabin can't
-- afford, exactly as vanilla Magic greys a spell whose MP cost exceeds current
-- MP.
--
-- Vanilla Magic: UpdateEnabledMagic (battle_main.asm) compares each spell's MP
-- cost to the caster's current MP and rolls a "disabled" bit; DrawMagicListText's
-- GetTextColor turns that bit into $04, OR'd into the row's $21 white
-- font-palette byte to make $25 (grey).  Blitz and Tools draw through the
-- tools-window shell, never the magic list, so they never inherited that
-- machinery.  Ot6AbilityGrey (ot6.asm, bank F0) is it, ported to the menu bank:
-- the Blitz row decorator feeds each row's MP cost to it and OR's the $00/$04 it
-- returns into that column's font byte, so an unaffordable name (and its
-- trailing MP cost, which shares the font scope) renders $25 grey instead of
-- $21 white.  The caster is $62ca (the active slot the decorators and magic's
-- own draw both index) and its live MP is $3c08,slot*2 -- the very cell the
-- universal charge at CalcAttackEffect later subtracts from, so the menu greys
-- precisely what the charge would refuse.
--
-- Sabin is INSTALLED into the opening guard fight the way battle_blitzlist pins
-- him: every party slot gets CHAR::SABIN ($3ED8) and an all-Blitz command list
-- ($202E, stride 12), and the known-blitz set $1D28 is written directly.  The
-- twist here: current MP ($3C08) is pinned LOW so the learned kit straddles the
-- affordability line.
--
-- Learned kit (LEARNED $E5) and its Ot6AbilityCostTbl prices:
--   Pummel   $5d  2      Air Blade $62 12
--   Suplex   $5f  7      Spiraler  $63 18
--                        Bum Rush  $64 30
-- With MP pinned to 8, Pummel(2) and Suplex(7) are affordable (white); Air
-- Blade(12), Spiraler(18) and Bum Rush(30) are not (grey) -- a mix of both on
-- one screen.
--
-- What is asserted (attribute byte = the odd/high byte of each name tile's
-- tilemap word, $21 white / $25 grey -- the same VRAM attribute battle_class.lua
-- reads):
--   1. AFFORDABLE STAYS WHITE.  Pummel and Suplex render at attribute $21.
--   2. UNAFFORDABLE GREYS.  Spiraler renders at attribute $25 ($21 | $04).
--   3. THE GREY IS THE DISABLED BIT.  grey - white == $04, magic's own delta.
-- Then a second pass restores full MP and reopens the menu to prove the grey is
-- affordability-driven, not unconditional: with MP high, Spiraler is white too.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_TOOLS = 0x30
local CMD_BLITZ = 0x0A
local CMDTBL, KNOWN, CURMP = 0x202E, 0x1D28, 0x3C08
local LEARNED = 0xE5                    -- Pummel Suplex AirBlade Spiraler BumRush
local WHITE, GREY = 0x21, 0x25          -- ListText font palette: white, and $21|$04
local PARTY = { 0, 1, 2 }

-- FF6 battle-font glyphs: 'A'..'Z' = $80.., 'a'..'z' = $9a.. (the mapping
-- battle_blitzlist / battle_toolslist pin down).
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and (0x80 + c:byte() - ("A"):byte())
                                    or  (0x9a + c:byte() - ("a"):byte())
  end
  return t
end
-- spaceless names only, so the glyph run is contiguous in VRAM.
local NM = {
  Pummel   = glyphs("Pummel"),         -- $5d  cost 2  -> affordable
  Suplex   = glyphs("Suplex"),         -- $5f  cost 7  -> affordable
  Spiraler = glyphs("Spiraler"),       -- $63  cost 18 -> unaffordable
}

local mp = 8                            -- pinned current MP (mutated for pass 2)

-- Install a full-Blitz Sabin, with current MP pinned to `mp`, every frame.
local function pinSabin()
  H.writeByte(KNOWN, LEARNED)
  for _, s in ipairs(PARTY) do
    H.writeByte(0x3ED8 + s * 2, 0x05)               -- CHAR::SABIN
    local st1 = 0x3EE4 + s * 2
    H.writeByte(st1, H.readByte(st1) & 0xF7)        -- clear magitek
    for i = 0, 3 do H.writeByte(CMDTBL + s * 12 + i * 3, CMD_BLITZ) end
    H.writeWord(0x3BF4 + s * 2, 999)                -- nobody dies mid-bench
    H.writeWord(CURMP + s * 2, mp)                  -- the affordability knob
  end
end

-- word address of a rendered glyph run in VRAM, or nil (battle_blitzlist's
-- findName).
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

-- attribute (palette) byte of a drawn name's first tile: the odd byte of its
-- tilemap word.  $21 white, $25 grey.  nil if the name is not on screen.
local function attrOf(seq)
  local w = findName(seq)
  if not w then return nil end
  return emu.read(w * 2 + 1, emu.memType.snesVideoRam)
end

-- open the blitz list (state $30) fresh from the command window.
local function openBlitz()
  return H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 900, {
    H.call(function() pinSabin(); H.setPad({ "a" }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(14),
  }, "the blitz list opens (tools-shell state $30)")
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),

  H.driveUntil(function() return H.readByte(MENU) ~= 0 end, 3000, {
    H.call(pinSabin), H.waitFrames(1),
  }, "a battle menu opens"),
  H.call(function()
    H.log(string.format("sabin installed in slot %d, known $%02x, MP pinned to %d",
      H.readByte(ACTOR), H.readByte(KNOWN), mp))
  end),

  -- PASS 1: MP = 8 -- some blitzes affordable, some not ----------------------
  openBlitz(),
  H.waitFrames(6),                     -- let every row finish drawing
  H.call(function() H.screenshot("blitz_grey_display") end),
  H.call(function()
    local aP, aS, aSp = attrOf(NM.Pummel), attrOf(NM.Suplex), attrOf(NM.Spiraler)
    H.log(string.format("attr: Pummel=%s Suplex=%s Spiraler=%s (white=$%02x grey=$%02x)",
      aP and string.format("$%02x", aP) or "nil",
      aS and string.format("$%02x", aS) or "nil",
      aSp and string.format("$%02x", aSp) or "nil", WHITE, GREY))
    H.assertEq(aP, WHITE, "Pummel (cost 2, MP 8) renders white -- affordable")
    H.assertEq(aS, WHITE, "Suplex (cost 7, MP 8) renders white -- affordable")
    H.assertEq(aSp, GREY, "Spiraler (cost 18, MP 8) renders grey -- unaffordable")
    H.assertEq(aSp - aP, 0x04,
      "grey - white == $04, magic's own disabled-bit delta")
  end),

  -- PASS 2: MP high -- the same row is white, proving grey tracks MP ---------
  H.call(function() H.setPad({ "b" }) end), H.waitFrames(6),  -- close the list
  H.call(function() H.setPad({}) end),
  H.driveUntil(function() return H.readByte(MSTATE) ~= ST_TOOLS end, 300, {
    H.call(function() H.setPad({ "b" }) end), H.waitFrames(2),
    H.call(function() H.setPad({}) end), H.waitFrames(2),
  }, "the blitz list closes back to the command window"),
  H.call(function() mp = 99 end),      -- pinSabin now writes full MP every frame
  H.waitFrames(4),
  openBlitz(),
  H.waitFrames(6),
  H.call(function()
    local aSp = attrOf(NM.Spiraler)
    H.log(string.format("MP now %d -> Spiraler attr = %s", mp,
      aSp and string.format("$%02x", aSp) or "nil"))
    H.assertEq(aSp, WHITE, "Spiraler (cost 18, MP 99) is white now -- grey tracks MP")
    H.log("PASSED: Blitz greys the unaffordable rows and only the unaffordable rows")
  end),
})
