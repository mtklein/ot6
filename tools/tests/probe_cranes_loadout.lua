-- probe_cranes_loadout.lua -- read-only instrument (issue #75, the Cranes
-- vanilla-playbook re-test): reports what the n128_won party brings to the
-- reunion fight.
--
-- The wall record (gen_terra_returned_checkpoint header, probe_cranes_wedge)
-- says the fight's designed key, water (bosses-wob.md 16), is unobtainable
-- by this party.  The vanilla playbook disagrees: BISMARK ($1A69 bit 7,
-- the tube-room give_genju per gen_esper_tubes_done) carries Sea Song
-- ($3d: water, power 58, 50 MP, all enemies), the game's only water spell
-- (magicite-tube-six.md section 8).  Whether the key exists here reduces
-- to three readable facts, dumped below:
--   * esper ownership ($1A69/$1A6A): whether BISMARK is owned at this
--     boundary;
--   * per-character MP: whether anyone can pay the 50 MP Sea Song costs;
--   * known spells ($1a6e + 54*actor): whether anyone knows Bolt (the
--     Right Crane's second weakness) or any element that would feed an
--     absorb (Left absorbs bolt 0x04, Right absorbs fire 0x01;
--     monster_prop.dat +23, read 2026-08-10).
-- Not a suite test; no fixture output.
local H = dofile("tools/tests/lib/ot6.lua")

local NAMES = { [0]="TERRA","LOCKE","CYAN","SHADOW","EDGAR","SABIN","CELES",
  "STRAGO","RELM","SETZER","MOG","GAU" }
local SPELLS = { [0]="Fire","Ice","Bolt","Poison","Drain","Fire2","Ice2",
  "Bolt2","Bio","Fire3","Ice3","Bolt3" }

H.run({ maxFrames = 900 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.log(string.format("[espers] $1A69=%02X $1A6A=%02X (bit5 SHOAT bit6 "
      .. "MADUIN bit7 BISMARK; bits0-2 RAMUH/IFRIT/SHIVA, bit3 SIREN)",
      H.readByte(0x1A69), H.readByte(0x1A6A)))
    local pid = H.readByte(0x1A6D)
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == pid then
        local base = 0x1600 + 37 * c
        local actor = H.readByte(base) & 0x3f
        local known = {}
        for s = 0, 53 do
          if H.readByte(0x1a6e + 54 * actor + s) == 0xff then
            known[#known + 1] = SPELLS[s] or string.format("$%02X", s)
          end
        end
        local gear = {}
        for g = 31, 36 do gear[#gear + 1] = string.format("%02X", H.readByte(base + g)) end
        H.log(string.format(
          "[char c%d] actor=%d(%s) lvl=%d hp=%d/%d mp=%d/%d esper=%02X "
          .. "gear=%s knows{%s}", c, actor, NAMES[actor] or "?", H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15),
          H.readByte(base + 30), table.concat(gear, " "), table.concat(known, ",")))
      end
    end
    H.log(string.format("[switches] $006B(reunion)=%d $02F6(celes)=%d",
      (H.readByte(0x1E80 + (0x6B >> 3)) >> (0x6B & 7)) & 1,
      (H.readByte(0x1E80 + (0x2F6 >> 3)) >> (0x2F6 & 7)) & 1))
    -- the whole bag, weapon-range ids: what is available to re-arm the riders
    local bag = {}
    for i = 0, 255 do
      local id, qty = H.readByte(0x1869 + i), H.readByte(0x1969 + i)
      if id ~= 0xFF and qty > 0 and id < 0x5A then
        bag[#bag + 1] = string.format("%02X x%d", id, qty)
      end
    end
    H.log("[bag weapons/gear] " .. table.concat(bag, ", "))
  end),
})
