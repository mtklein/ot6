-- @manual
-- probe_zozo_zones.lua -- the world battle group per tile around the Zozo
-- crossing and grind, read the way CheckBattleWorld reads it
-- (field/battle.asm:97-140, world/move.asm:876-881): bg = tile prop high
-- byte & 7, zone = (y & $E0) | ((x >> 3) & $1C),
-- group = WorldBattleGroup[zone | BattleBGGroupTbl[bg]].
local H = dofile("tools/tests/lib/ot6.lua")
local BGGROUP = { [0] = 0, 1, 2, 1, 0, 3, 0, 0 }
H.run({ maxFrames = 3000 }, {
  H.loadState("build/states/zozogrind_landing.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    local wbg = H.sym("WorldBattleGroup") & 0x3FFFFF
    H.log(string.format("[zones] WorldBattleGroup at rom $%06X world=%d at (%d,%d)",
      wbg, H.worldId(), H.worldX(), H.worldY()))
    H.log("[zones] legend: # impassable, . no battles, hex digit = world battle group (upper case = group + 16), V = veldt")
    for y = 40, 135 do
      local row = {}
      for x = 0, 63 do
        local p = H.worldTileProp(x, y)
        local ch
        if (p & 0x0010) ~= 0 then ch = "#"
        elseif (p & 0x0040) == 0 then ch = "."
        else
          local bg = (p >> 8) & 7
          local zone = (y & 0xE0) | ((x >> 3) & 0x1C)
          local g = H.readRomByte(wbg + (zone | BGGROUP[bg]))
          if g == 0xFF then ch = "V"
          else
            ch = string.format("%x", g % 16)
            if g >= 16 then ch = string.upper(ch) end
          end
        end
        row[#row + 1] = ch
      end
      H.log(string.format("[zones] y=%3d %s", y, table.concat(row)))
    end
  end),
})
