-- gen_wor_island.lua -- the World of Ruin's first save: from wor_landing
-- (solo CELES at Cid's bedside on the Solitary Island, map 397, the WoR
-- flag $00A4 set) out of the house and off the island's west edge onto its
-- own tile on the World of Ruin map, where the game allows saving, and a
-- save through the real Save UI into slot 3.  Generates wor_island.mss,
-- and its capture run (OT6_CAPTURE_SRM) cuts the `wor-island-v1` battery,
-- which gen_wor_start cold-Continues to save Cid.
--
-- The route (docs/design/wor-start.md has the measurements):
--   1. Dress CELES.  The WoR opening hands her over with every slot empty
--      (her escape kit went to the bag).  The menu costs Cid nothing: his
--      clock is timer 0 with the FIELD_ONLY flag ($1188 = $80), which
--      DecTimersMenuBattle skips.
--   2. Out of the house (397 (100,46) -> 396 (8,7)) and west off 396's edge
--      onto the World of Ruin map: the island's tile, (76,239) on arrival
--      (the opening's set_parent_map 1, {76, 240}; (76,240) is the way back
--      in).  The world map allows saving and Cid's field clock stands still
--      there (build/attempts/wt/wor-start/lab/probe_wor_islesave_1.log: 600
--      frames on the island, health 114 -> 114).
--   3. Save: the first save the World of Ruin offers, before Cid is fed; a
--      person who knows he can be lost makes it here.
-- Nothing is written; every step is a button press.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CELES = 6
local MAP_HOUSE, MAP_ISLE = 397, 396

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function health() return H.readWord(0x1FD0) end          -- event var 7
local function ready()
  return H.hasControl() and H.tileAligned() and bright() >= 15
    and not H.dialogWaiting() and not H.battleLoadStarted()
end

local healthBefore = 0
H.run({ maxFrames = 12000 }, {
  H.loadState("build/states/wor_landing.mss.lua"),
  H.waitFrames(2),
  H.call(function()
    local c = 0x1600 + 37 * CELES
    local members = H.partyMembers()
    H.log(string.format("[wor] boot f%d: map %d (%d,%d), party %d, CELES L%d HP %d/%d MP %d, Cid health %d, timer 0 flags $%02X at $%04X, fish %d%d%d%d, tonic=%d potion=%d fenix=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), #members, H.readByte(c + 8), H.charHp(CELES),
      H.charMaxHp(CELES), H.charMp(CELES), health(), H.readByte(0x1188), H.readWord(0x118B),
      sw(0x369), sw(0x36A), sw(0x36B), sw(0x36C), H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0)))
    H.assertEq(map(), MAP_HOUSE, "wor_landing: Cid's house on the Solitary Island (397)")
    H.assertEq(sw(0x00A4), 1, "wor_landing: $00A4 set -- the World of Ruin")
    H.assertEq(#members == 1 and members[1] == CELES, true, "wor_landing: the party is Celes alone")
    H.assertEq(sw(0x00B3) == 1 or sw(0x00B4) == 1, false, "wor_landing: Cid neither recovered nor lost yet")
    H.assertEq(H.readByte(0x1188), 0x80, "wor_landing: Cid's clock (timer 0, FIELD_ONLY) is running")
  end),

  -- ---- 1. dress CELES ---------------------------------------------------------
  -- Relics first: the Genji Glove opens her left hand to a second weapon
  -- (owner guideline: it stays on the boost-Fighter, and alone she is
  -- that), and the Czarina Ring beside it (item_prop_en.dat byte $0D = $03:
  -- Safe and Shell when her HP runs low, the Barrier Ring's $01 doubled --
  -- a solo's insurance).  Leaving the Relic screen with the Genji Glove
  -- changed runs the game's own Optimum on her gear (measured: 11 0E 76 8F,
  -- Break Blade / Blizzard / Gold Helmet / Gold Armor, the bag's strongest
  -- by item_prop_en.dat battle power and defense), so the gear session
  -- below only confirms it: each slot's ladder lists what Optimum picks
  -- first and the next-best in the bag after it.  Her row stays as it is
  -- (BACK); no fight in this segment or the next measures it.
  H.call(function() healthBefore = health() end),
  H.equipKit(CELES, { { 4, 0xD1 }, { 5, 0xC1 } }, { tag = "CELES relics" }),
  H.equipKit(CELES, { { 0, 0x11 }, { 0, 0x0F },
                      { 1, 0x0E }, { 1, 0x0F }, { 1, 0x5C },
                      { 2, 0x76 }, { 2, 0x6E },
                      { 3, 0x8F }, { 3, 0x89 } }, { tag = "CELES gear", ladder = true }),
  H.call(function()
    local c = 0x1600 + 37 * CELES
    H.log(string.format("[wor] CELES dressed: %02X %02X %02X %02X %02X %02X; Cid health %d before the menus, %d after",
      H.readByte(c + 0x1F), H.readByte(c + 0x20), H.readByte(c + 0x21), H.readByte(c + 0x22),
      H.readByte(c + 0x23), H.readByte(c + 0x24), healthBefore, health()))
    H.assertEq(H.readByte(c + 0x1F) ~= 0xFF, true, "CELES holds a weapon")
    H.assertEq(H.readByte(c + 0x22) ~= 0xFF, true, "CELES wears armor")
    H.assertEq(H.readByte(c + 0x23), 0xD1, "CELES wears the Genji Glove")
  end),

  -- ---- 2. out of the house and off the island's west edge ------------------
  H.navTo(100, 45, { maxFrames = 3000, playBattles = "tactical" }),
  H.driveUntil(function() return map() == MAP_ISLE end, 600, {
    H.call(function() H.setPad({ down = true }) end),
  }, "the house door -> 396"),
  H.release(),
  H.waitUntil(function() return map() == MAP_ISLE and ready() end, 900, "396: control", 1),
  H.navTo(1, 7, { maxFrames = 3000, playBattles = "tactical" }),
  (function()
    local W = H.newWalkFighter("off the island's west edge")
    return H.driveUntil(function()
      return H.worldMode() and H.worldHasControl() and H.worldAligned() and bright() >= 15
    end, 1800, {
      H.call(function()
        if W.frame() then return end
        H.setPad(H.worldMode() and {} or { left = true })
      end),
    }, "the island's tile on the World of Ruin map")
  end)(),
  H.call(function()
    H.log(string.format("[wor] the island on the world map: world %d at (%d,%d), Cid health %d",
      H.worldId(), H.worldX(), H.worldY(), health()))
    H.assertEq(H.worldId(), 1, "the island is on the World of Ruin map")
  end),

  -- ---- 3. the island save ---------------------------------------------------------
  H.saveGame({ slot = 3, tag = "wor-island-v1 save" }),
  H.call(function()
    -- what the battery holds (#218): the slot's own copy of $1F64 and
    -- $1F60/$1F61 (map 1 is the World of Ruin, where
    -- H.assertSavedSlotWorld expects the World of Balance's 0)
    local s = H.savedSlot()
    H.log(string.format("[saved] wor-island-v1: slot %d holds map %d ($%04X) world tile (%d,%d), Cid health %d",
      s.slot, s.map, s.mapWord, s.worldX, s.worldY, health()))
    H.assertEq(s.slot, 3, "wor-island-v1: the save went to slot 3")
    H.assertEq(s.map, 1, "wor-island-v1: saved on the World of Ruin map")
    H.assertEq(s.worldX == H.worldX() and s.worldY == H.worldY(), true,
      "wor-island-v1: the battery holds the tile she stands on")
    H.assertExitContract("wor-island-v1")
    H.screenshot("wor_island")
  end),
  H.saveState("wor_island.mss"),
  H.logStep(function()
    return string.format("wor_island generated: CELES saved on the island's World of Ruin tile (%d,%d), Cid health %d",
      H.worldX(), H.worldY(), health())
  end),
})
