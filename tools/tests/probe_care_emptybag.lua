-- @manual
-- probe_care_emptybag.lua -- #184 groundwork: what does crescent_landing
-- (a played fixture with 0 Tonics and 36 Potions in the bag) boot as, and
-- what is walkable around it, so the empty-Tonic care suite can pick its
-- legs from measurements rather than guesses.  Reads only.
local H = dofile("tools/tests/lib/ot6.lua")

local TONIC, POTION, FENIX = 0xE8, 0xE9, 0xF0
local function roster(tag)
  local out = {}
  for _, c in ipairs(H.partyMembers()) do
    out[#out + 1] = string.format("c%d %d/%d hp %d/%d mp cure=%s", c, H.charHp(c),
      H.charMaxHp(c), H.charMp(c), H.charMaxMp(c), tostring(H.knowsSpell(c, 0x2D)))
  end
  H.log(string.format("[probe] %s: %s | tonic=%d potion=%d fenix=%d", tag,
    table.concat(out, "  "), H.invCountOf(TONIC), H.invCountOf(POTION), H.invCountOf(FENIX)))
end

H.run({ maxFrames = 6000 }, {
  H.loadState("build/states/crescent_landing.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe] boot: worldMode=%s worldId=%d world=(%d,%d) map=%d field=(%d,%d) ctl=%s aligned=%s",
      tostring(H.worldMode()), H.worldId(), H.worldX(), H.worldY(), H.mapId() & 0x3ff,
      H.fieldX(), H.fieldY(), tostring(H.worldMode() and H.worldHasControl() or H.hasControl()),
      tostring(H.worldMode() and H.worldAligned() or H.tileAligned())))
    roster("at boot")
    if H.worldMode() then
      local x0, y0 = H.worldX(), H.worldY()
      for dy = -6, 6 do
        local row = {}
        for dx = -12, 12 do
          local x, y = x0 + dx, y0 + dy
          local ok = H.worldPassable and H.worldPassable(x, y)
          row[#row + 1] = (dx == 0 and dy == 0) and "@" or (ok and "." or "#")
        end
        H.log(string.format("[probe] y=%3d %s", y0 + dy, table.concat(row)))
      end
    end
  end),
})
