-- @manual
-- lab_nerapa_bake.lua -- the Nerapa lab's fixture half: from escape_start
-- (gen_fc_escape's second artifact: first control on the escape map 393,
-- 6:00 master clock and 5:55 Shadow clock running, CELES bare) to Nerapa's
-- doorstep at (106,15), exactly the way gen_fc_escape gets there -- dress
-- CELES under the clock (Break Blade $11, relics $B1/$B5; the shield/helm/
-- armor rungs her list refuses are asked for and refused, as the gen does),
-- then walk east fighting every Naughty through the real menus -- and bank
-- one savestate there, nerapalab_doorstep.mss, for lab_nerapa_template.lua
-- to branch into policy x seed experiments (docs/TESTING.md: one
-- legitimately reached snapshot, many experiments).
--
-- Also logs, read-only, what the party brings to the doorstep: levels,
-- HP/MP, worn esper and gear, every spell known, the bag's care items, and
-- both clocks -- the lab header's "what the party has" row.
--
-- Pad presses and reads only.  Nothing here fights Nerapa.
local H = dofile("tools/tests/lib/ot6.lua")

local CELES = 6
local function map() return H.mapId() & 0x3ff end
local function nerapaUp() return (H.readByte(0x1EEC) >> 1) & 1 == 1 end    -- $0361

-- Timer records at $1188 (field-ram.txt:684-692): +0 flags, +1 count (word).
-- Timer 0 is the 6:00 master clock, timer 2 Shadow's 5:55 arrival.
local function clock(tag)
  return H.call(function()
    local f0, c0 = H.readByte(0x1188), H.readWord(0x1189)
    local f2, c2 = H.readByte(0x1188 + 12), H.readWord(0x1189 + 12)
    H.log(string.format("[escape clock] %s: master=%d frames (%d:%02d) flags=%02X | shadow=%d flags=%02X | at (%d,%d) f%d",
      tag, c0, c0 // 3600, (c0 % 3600) // 60, f0, c2, f2, H.fieldX(), H.fieldY(), H.frame))
  end)
end

-- Character record $1600 + 37*c (field-ram.txt:885-927): +8 level, +9 HP,
-- +11 max HP, +13 MP, +15 max MP, +$1E esper, +$1F..+$24 weapon/shield/
-- helm/armor/relic/relic.  Spells known: $1A6E + 54*c + spell, $FF = known
-- (field-ram.txt:944).
local function probeParty()
  for _, c in ipairs(H.partyMembers()) do
    local b = 0x1600 + 37 * c
    local known = {}
    for id = 0, 53 do
      if H.readByte(0x1A6E + c * 54 + id) == 0xFF then known[#known + 1] = string.format("%02X", id) end
    end
    H.log(string.format("[party] char=%d L%d hp=%d/%d mp=%d/%d esper=$%02X gear=%02X,%02X,%02X,%02X,%02X,%02X spells=%s",
      c, H.readByte(b + 8), H.readWord(b + 9), H.readWord(b + 11), H.readWord(b + 13), H.readWord(b + 15),
      H.readByte(b + 0x1E), H.readByte(b + 0x1F), H.readByte(b + 0x20), H.readByte(b + 0x21),
      H.readByte(b + 0x22), H.readByte(b + 0x23), H.readByte(b + 0x24), table.concat(known, ",")))
  end
  H.log(string.format("[bag] tonic=%d potion=%d fenix=%d autocrossbow=%d",
    H.invCountOf(0xE8), H.invCountOf(0xE9), H.invCountOf(0xF0), H.invCountOf(H.AUTOCROSSBOW)))
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/escape_start.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map() == 393, true, "escape_start is on the escape map (393)")
    H.log(string.format("[bake] escape_start at (%d,%d) f%d", H.fieldX(), H.fieldY(), H.frame))
  end),
  clock("escape_start"),
  -- gen_fc_escape 3b: CELES's kit under the clock, the same call
  H.equipKit(CELES, { { 0, 0x11 }, { 0, 0x0E }, { 0, 0x0A },
                      { 4, 0xB1 }, { 5, 0xB5 } }, { tag = "CELES escape kit", ladder = true }),
  clock("CELES dressed"),
  -- gen_fc_escape 4: the fought walk (Naughty $169 x1 per encounter, the
  -- map sets can't-run; physical line, no BP bank, no care under the clock)
  H.navTo(106, 15, { maxFrames = 20000, playBattles = "tactical", bank = 0,
    healPercent = 60, care = false }),
  clock("at Nerapa's doorstep"),
  H.release(),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.fieldX() == 106 and H.fieldY() == 15, true, "standing at (106,15), Nerapa's doorstep")
    H.assertEq(nerapaUp(), true, "$0361 set -- Nerapa stands at (108,15)")
    probeParty()
  end),
  H.saveState("nerapalab_doorstep.mss"),
  H.logStep(function() return string.format("[bake] nerapalab_doorstep banked at f%d, master clock %d", H.frame, H.readWord(0x1189)) end),
})
