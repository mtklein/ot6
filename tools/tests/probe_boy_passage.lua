-- probe_boy_passage.lua -- #244/#145.  DRIVE the disguise-gated interior with
-- the CORRECT flag: the grandson boy (_ca7bcd -> _ca7bf8) is gated on $0104
-- (MERCHANT), not $0103.  With $0104 set he steps aside (obj_script NPC_5) and
-- sets $01F0, opening the passage.  Enter the old man's house from the pocket
-- (town (37,40) -> map 86), flood map 86 z-aware to find the boy, talk to him,
-- and see the passage open.  @manual
local H = dofile("tools/tests/lib/ot6.lua")
local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end
local function setsw(id, v)
  local a = 0x1e80 + (id >> 3); local b = 1 << (id & 7)
  H.writeByte(a, v == 1 and (H.readByte(a) | b) or (H.readByte(a) & ~b))
end
local function seq(steps) return H.cond(function() return true end, steps) end

H.run({ maxFrames = 80000 }, {
  H.loadState("build/states/locke_scenario.mss.lua"),
  H.waitFrames(60),
  H.call(function()
    H.BFS_CAP = 20000
    setsw(0x0104, 1)  -- exploration: put on the MERCHANT disguise (the boy's flag)
    H.log(string.format("[boy] boot map=%d (%d,%d) 0104(merchant)=%d 0105=%d 0107=%d 01F0=%d",
      map(), H.fieldX(), H.fieldY(), sw(0x0104), sw(0x0105), sw(0x0107), sw(0x01F0)))
  end),
  H.navTo(37, 41, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.driveUntil(function() return map() == 86 end, 3000, {
    H.hold({ "up" }), H.waitFrames(8),
  }, "into the old man's house"),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[boy] inside old man's house: map=%d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
  end),
  -- downstairs = the same-map warp (32,11) -> (9,8), into the grandson's region
  H.navTo(32, 11, { maxFrames = 12000, playBattles = true,
                    arrive = function() return H.fieldX() < 15 end }),
  H.release(), H.waitFrames(60),
  H.call(function()
    H.log(string.format("[boy] after downstairs warp: map=%d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    -- flood the grandson's region (west side, x 2..20)
    for y = 4, 24, 2 do
      local line = {}
      for x = 2, 24 do
        line[#line+1] = (x==H.fieldX() and y==H.fieldY()) and "@"
          or (H.bfsPath(x, y) and "." or " ")
      end
      H.log(string.format("gs y%2d |%s|", y, table.concat(line)))
    end
    for _, t in ipairs({ {6,10,"grandson"}, {5,10,"gs W"}, {7,10,"gs E"},
                         {6,9,"gs N"}, {6,11,"gs S"}, {4,15,"passage stairs"} }) do
      H.log(string.format("[boy]   (%d,%d)%s reach=%s", t[1], t[2], t[3],
        H.bfsPath(t[1], t[2]) and "yes" or "no"))
    end
  end),
  -- stand east of the grandson and talk to him with the merchant disguise on
  H.navTo(7, 10, { maxFrames = 12000, playBattles = true }),
  H.release(),
  H.talkToObj(20, "the grandson (merchant gate)"),
  (function()
    local ph = 0
    return H.driveUntil(function()
      return H.hasControl() and not H.dialogWaiting() and not H.eventRunning()
    end, 12000, {
      H.call(function() ph = (ph + 1) % 8; H.setPad(ph < 4 and { "a" } or {}) end),
    }, "ride the grandson's dialog")
  end)(),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[boy] AFTER talking merchant: 01F0(passed)=%d grandson(obj20)=(%d,%d) at (%d,%d) map=%d",
      sw(0x01F0), H.objX(20), H.objY(20), H.fieldX(), H.fieldY(), map()))
    -- did a passage open?  check the tiles the boy was blocking + the west
    for _, t in ipairs({ {6,10,"boy's old tile"}, {4,10,"further west"},
                         {4,4,"->town75(34,34) WEST"}, {8,25,"->town75(22,13) WEST"},
                         {7,49,"warp->(4,14)"}, {4,15,"passage stairs(needs pwd)"} }) do
      H.log(string.format("[boy]   (%d,%d)%s reach=%s", t[1], t[2], t[3],
        H.bfsPath(t[1], t[2]) and "YES" or "no"))
    end
  end),
  -- drive out the west town exit (4,4)->75(34,34) and confirm we land WEST of
  -- the gate soldier, then that the cider door (22,42) is reachable there
  H.navTo(4, 5, { maxFrames = 12000, playBattles = true }),
  H.driveUntil(function() return map() == 75 end, 3000, { H.hold({ "up" }), H.waitFrames(8) },
    "out to west town via (4,4)"),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[boy] OUT to town: map=%d at (%d,%d); cider door approach (22,43) reach=%s; "
      .. "Imperial soldier (22,47) reach=%s; grandson N door (22,13) reach=%s; "
      .. "old man house door (37,41) reach=%s",
      map(), H.fieldX(), H.fieldY(),
      H.bfsPath(22, 43) and "YES" or "no", H.bfsPath(22, 47) and "YES" or "no",
      H.bfsPath(22, 13) and "YES" or "no", H.bfsPath(37, 41) and "YES" or "no"))
  end),
  -- RICH-MAN'S-HOUSE RETURN ROUTE TEST: put on the Imperial disguise ($0103)
  -- and see whether the map-81 doors / terrace are reachable from the cider
  -- region (the return route is town75 -> 81 -> 83 -> 84 -> 87 -> old man).
  H.call(function()
    setsw(0x0103, 1)
    H.log(string.format("[end] cider region, $0103 on: map81 doorstep (23,16)=%s (15,19)=%s (24,15)=%s",
      H.bfsPath(23, 16) and "YES" or "no", H.bfsPath(15, 19) and "YES" or "no",
      H.bfsPath(24, 15) and "YES" or "no"))
  end),
  -- drive into map 81 (town 23,15 -> 81) and on toward map 83, then check the
  -- old-man region reachability (83 -> 84 -> 87 -> 86 old man)
  H.navTo(23, 16, { maxFrames = 15000, playBattles = true }),
  H.driveUntil(function() return map() == 81 end, 3000, { H.hold({ "up" }), H.waitFrames(8) },
    "into map 81"),
  H.release(), H.waitFrames(90),
  H.call(function()
    H.log(string.format("[end] into map 81: map=%d at (%d,%d)", map(), H.fieldX(), H.fieldY()))
    -- scan objects (officers?) and check the map-81 -> 83 door reachability
    for o = 16, 31 do
      local x, y = H.objX(o), H.objY(o)
      if x >= 0 and x < 128 and y >= 0 and y < 64 then
        H.log(string.format("[end]   obj %d at (%d,%d)", o, x, y))
      end
    end
    for _, t in ipairs({ {28,9,"->map83"}, {4,16,"<-town75(15,18)"}, {16,15,"<-town75(23,15)"} }) do
      H.log(string.format("[end]   m81 (%d,%d)%s reach=%s", t[1], t[2], t[3], H.bfsPath(t[1],t[2]) and "YES" or "no"))
    end
  end),
})
