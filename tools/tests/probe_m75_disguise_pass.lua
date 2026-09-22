-- probe_m75_disguise_pass.lua -- #244/#145.  The decisive engine test of the
-- owner's hypothesis: does the Imperial disguise ($0103) let LOCKE WALK PAST
-- the gate soldier (HeavyArmor, obj 26 at (30,42)) into the west town, or is
-- the soldier a hard blocker removed only by WINNING battle 11?
-- Read-mostly; the one write is a labelled disguise-flag set, to answer the
-- question without a play-through that cannot legally reach an Imperial
-- soldier (they are themselves west of the gate).  @manual
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function setsw(id, v)
  local a = 0x1e80 + (id >> 3); local b = 1 << (id & 7)
  H.writeByte(a, v == 1 and (H.readByte(a) | b) or (H.readByte(a) & ~b))
end

H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.BFS_CAP = 20000
    H.assertEq(map(), 75, "map 75")
    H.log(string.format("[pass] boot (%d,%d) obj26(gate soldier)=(%d,%d) 0103=%d 0104=%d",
      H.fieldX(), H.fieldY(), H.objX(26), H.objY(26), sw(0x0103), sw(0x0104)))
  end),
  -- reach the tile just SOUTH of the gate soldier (z-aware reachable, 27 steps)
  H.navTo(30, 43, { maxFrames = 15000, playBattles = true }),
  H.release(),
  H.call(function()
    H.log(string.format("[pass] at (%d,%d), soldier at (%d,%d) present=%d; west (24,34) bfsPath=%s",
      H.fieldX(), H.fieldY(), H.objX(26), H.objY(26),
      H.readByte(0x7e2000 + 26) and 1 or 1,
      H.bfsPath(24, 34) and "PATH" or "NO PATH"))
    -- put on the IMPERIAL disguise (labelled test write) and CLEAR merchant
    setsw(0x0103, 1); setsw(0x0104, 0)
    H.log(string.format("[pass] Imperial disguise ON: 0103=%d 0104=%d; west (24,34) bfsPath=%s",
      sw(0x0103), sw(0x0104), H.bfsPath(24, 34) and "PATH" or "NO PATH"))
  end),
  -- now DRIVE north/west into and past the soldier for a good while, then
  -- report the furthest west LOCKE reached -- a pass shows x < 30
  (function()
    local minx = 99
    return H.driveUntil(function() return false end, 1200, {
      H.call(function()
        if H.fieldX() < minx then minx = H.fieldX() end
        local ph = (H.frame // 8) % 4
        H.setPad(ph == 0 and { "up" } or ph == 1 and { "left" }
              or ph == 2 and { "left" } or { "up" })
      end),
    }, "drive into the disguised gate soldier")
  end)(),
  H.release(),
  H.call(function()
    H.log(string.format("[pass] AFTER driving disguised: at (%d,%d), soldier (%d,%d), "
      .. "map=%d; west (24,34) bfsPath=%s; cider (22,43) bfsPath=%s",
      H.fieldX(), H.fieldY(), H.objX(26), H.objY(26), map(),
      H.bfsPath(24, 34) and "PATH" or "NO PATH",
      H.bfsPath(22, 43) and "PATH" or "NO PATH"))
    H.log("[pass] VERDICT: if still at x>=30 and west is NO PATH, the Imperial "
      .. "disguise does NOT open the gate -- the HeavyArmor must be fought")
  end),
})
