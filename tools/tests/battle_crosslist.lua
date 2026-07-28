-- @suite
-- battle_crosslist.lua -- gate for issue #36: "Tools shows Cure 2".
--
-- MECHANISM UNDER GUARD: Ot6RestageGate_ext (ot6_hud.asm) re-renders the open
-- magic list when boost moves, by borrowing the SHARED 4-line staging cycle
-- $7ba5/$7ba6 that every list-window open state runs (one staged line per
-- frame, $7ba5 = $80..$83 then 0).  Leaving magic browse ($7bc2=$0e) before
-- the cycle's four frames elapse -- an R (boost) followed within ~3 frames by
-- B (cancel), a perfectly human "oops, back out" -- used to strand $7ba5 at
-- $81-$83: the gate's @drop cleared its own OT6_RESTAGE flag but not the
-- borrowed staging byte.  Every window-open state trusts `lda $7ba5 / bmi`
-- to mean "my init already ran" (OpenMagicWindow @57c4, MakeToolsList_04
-- @58be, OpenItemWindow @5769, ...), so the NEXT list to open skipped its
-- own init and drew only the cycle's remaining lines: the owner's Tools
-- window rendering "Cure 2" and "Fire 2" over three of its four rows
-- (crosslist_tools.png from probe_crosslist.lua is the sighting, minted
-- deterministically).  Same mechanism covers the original report -- another
-- character's magic list keeping the previous caster's rows.
--
-- The stale rows are DISPLAY-ONLY: wItemList still holds the real tools and
-- Cmd_09 keys off the item id (battle_main.asm:3949 `lda $b6 / sbc #$a2`;
-- measured $3410=$83 NoiseBlaster, never $2e Cure 2) -- but a menu that says
-- Cure 2 and fires NoiseBlaster is a lying surface, the #27/#32 class.
--
-- What is asserted:
--   1. THE CYCLE REALLY RAN.  OT6_RESTAGE saw $80 and $7ba5 went mid-cycle
--      ($8x) during the R->B window -- the test cannot pass by boost or the
--      restage gate being disabled outright.
--   2. THE STRAND IS REPAIRED.  After leaving browse mid-cycle, $7ba5 reads
--      0 (pre-fix: $83).
--   3. THE TOOLS WINDOW IS ALL TOOLS.  Every row renders a tool name
--      (rows 0..3 sampled) and no magic-list name survives anywhere in the
--      BG1 text region (pre-fix: "Fire"/"Cure" present, tool rows absent).
--   4. THE LIST DATA WAS ALWAYS SOUND.  wItemList holds the eight tool ids.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_SPELL, ST_TOOLS = 0x0E, 0x30
local STAGE, RESTAGE = 0x7BA5, 0x57D4

local TOOLS = {
  { 0xA3, "NoiseBlaster" }, { 0xA4, "BioBlaster" }, { 0xA5, "Flash" },
  { 0xA6, "ChainSaw" }, { 0xA7, "Debilitator" }, { 0xA8, "Drill" },
  { 0xA9, "AirAnchor" }, { 0xAA, "AutoCrossbow" },
}

local function up(c)  return 0x80 + (c:byte() - ("A"):byte()) end
local function lo(c)  return 0x9a + (c:byte() - ("a"):byte()) end
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and up(c) or lo(c)
  end
  return t
end

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

local actor
local sawFresh, sawMidCycle = false, false

-- pinned every frame until the menu opens: the command window is BUILT from
-- $202e at open, so writing it later changes nothing the cursor can reach.
local function pinTerra()
  for s = 0, 3 do
    if H.readByte(0x3ed8 + s*2) == 0 then
      local s1 = 0x3ee4 + s*2                   -- clear magitek
      H.writeByte(s1, H.readByte(s1) & 0xf7)
      H.writeByte(0x202e + s*12 + 0*3, 0x02)    -- Magic
      H.writeByte(0x202e + s*12 + 1*3, 0x09)    -- Tools
      H.writeByte(0x202e + s*12 + 2*3, 0xff)
      H.writeByte(0x202e + s*12 + 3*3, 0xff)
      H.writeWord(0x3c08 + s*2, 99)             -- mp
    end
  end
  for i, t in ipairs(TOOLS) do                  -- battle_toolslist's item pin
    local b = 0x2686 + (i - 1) * 5
    H.writeByte(b + 0, t[1])
    H.writeByte(b + 1, 0x40)
    H.writeByte(b + 2, 0x00)
    H.writeByte(b + 3, 1)
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.driveUntil(function()
    if H.readByte(MENU) == 0 then pinTerra(); return false end
    return H.readByte(0x3ed8 + (H.readByte(ACTOR) & 3)*2) == 0
  end, 8000, {
    H.call(function()
      pinTerra()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "terra holds the menu"),
  H.call(function()
    actor = H.readByte(ACTOR) & 3
    H.writeByte(0x3e9c + actor*2, 5)            -- bp so R commits a boost
    H.writeByte(0x3e9d + actor*2, 0)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)  -- quiet the guards
    H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
    -- positive controls: the restage request fires and the cycle starts
    emu.addMemoryCallback(function(_, v)
      if v == 0x80 then sawFresh = true end
    end, emu.callbackType.write, 0x7e57d4, 0x7e57d4)
    emu.addMemoryCallback(function(_, v)
      if v >= 0x80 and v <= 0x83 then sawMidCycle = true end
    end, emu.callbackType.write, 0x7e7ba5, 0x7e7ba5)
  end),

  -- open the magic list (command cursor rests on row 0 = Magic)
  H.driveUntil(function() return H.readByte(MSTATE) == ST_SPELL end, 600, {
    H.pressButtons({ "a" }, 4), H.waitFrames(16),
  }, "spell list open"),
  H.call(function()
    H.writeByte(0x8913 + actor, 0)              -- park the list at the top
    H.writeByte(0x8917 + actor, 0)
    H.writeByte(0x891b + actor, 0)
  end),
  H.waitFrames(20),

  -- the trigger ordering: R (boost -> restage) then B before the 4-line
  -- cycle finishes
  H.hold({ "r" }), H.waitFrames(2), H.release(),
  H.hold({ "b" }), H.waitFrames(4), H.release(),
  H.waitFrames(14),
  H.call(function()
    H.assertEq(sawFresh, true, "R raised a fresh restage request ($80)")
    H.assertEq(sawMidCycle, true, "the restage cycle started ($7ba5 = $8x)")
    H.assertEq(H.readByte(MSTATE) ~= ST_SPELL, true, "B left magic browse")
    H.assertEq(H.readByte(STAGE), 0,
      "the abandoned restage hands the shared staging byte $7ba5 back closed")
  end),

  -- open Tools on the same character and demand an honest window
  H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 600, {
    H.call(function()
      local s = H.readByte(MSTATE)
      if s == ST_SPELL or s == 0x0d then
        H.setPad({ "b" })
      elseif s == 0x05 or s == 0x01 then
        H.writeByte(0x890f + actor, 1)          -- command cursor -> Tools
        H.writeByte(0x202e + actor*12 + 1*3 + 1, 0x00)  -- row enabled
        H.setPad({ "a" })
      else
        H.setPad({})
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "tools window open"),
  H.waitFrames(12),                             -- let every row finish drawing
  H.call(function()
    H.screenshot("crosslist_tools_after")
    local ids = {}
    for i = 0, 7 do ids[i] = H.readByte(0x4005 + i*3) end
    for i, t in ipairs(TOOLS) do
      H.assertEq(ids[i - 1], t[1],
        string.format("wItemList row %d is tool $%02x", i - 1, t[1]))
    end
    -- one name per window row: 0 NoiseBlaster, 1 Flash, 2 Drill,
    -- 3 AutoCrossbow -- pre-fix only row 3 drew ("Chain Saw"/"Air Anchor"
    -- carry spaces findName's contiguous glyph match cannot span)
    for _, nm in ipairs({ "NoiseBlaster", "Flash", "Drill", "AutoCrossbow" }) do
      H.assertEq(findName(glyphs(nm)) ~= nil, true,
        "\"" .. nm .. "\" renders in the tools window")
    end
    -- and no magic-list row survives -- pre-fix "Fire"/"Cure" sat in rows 0-2
    for _, nm in ipairs({ "Fire", "Cure" }) do
      H.assertEq(findName(glyphs(nm)), nil,
        "no stale magic row (\"" .. nm .. "\") in the tools window")
    end
    H.log("PASSED: an abandoned boost-restage no longer bleeds the magic list into the next window")
  end),
})
