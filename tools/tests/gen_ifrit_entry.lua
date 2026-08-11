-- gen_ifrit_entry.lua -- v0.6 step 7: mrf_kefka (map 263, {39,31},
-- $005F=1) -> the {36,44}/{37,44}/{38,44} chute -> map 264, the
-- Ifrit/Shiva alcove, control at {10,7}.  Generates ifrit_entry.
--
-- The Kefka scene leaves the party at {39,31} and OPENS the way south:
-- measured, the chute row went from NO PATH at the {40,30} ride exit to
-- 16-18 steps once $005F was set (census in gen_mrf_kefka's log).
--
-- _cc7581 (event_main.asm:94642) on {37,44} -- and its two neighbours
-- _cc7565/_cc7573, which just step the party onto the same tile -- falls
-- into _cc7588 (:94649):
--     DOWN 2 / LEFT 3 / DOWN_LEFT 3 / LEFT 1 / (sfx) DOWN 1
--     hide_obj / wait_90f / load_map 264, {14,0}, DOWN, STARTUP_EVENT
--     show_obj / fade_in / DOWN 3 / DOWN_LEFT 3 / jump_low DOWN_LEFT
--     player_ctrl_on
-- {14,0} + DOWN 3 = {14,3}, + DOWN_LEFT 3 = {11,6}, + DOWN_LEFT = {10,7}.
-- The recon read that landing as "approximately (10,7)"; this step asserts
-- it exactly.
--
-- WHAT IS WAITING THERE.  npc_prop.asm:12289/:12298 put Ifrit at {3,8} and
-- Shiva at {9,6} on map 264, both behind switch $0646 (1 at new game per
-- init_npc_switch.dat, cleared only at event_main.asm:95353 -- i.e. after
-- the magicite hand-off).  They stand ON the two doors out of the alcove:
-- {3,5} -> map 270 (the save room) and {9,5} -> map 269 (the way onward).
-- So the alcove is sealed until the fight is done, and `$0273` (set by
-- _cc7937 at :95313) additionally locks _cc75f6, the way back up to 263.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

local MAP_TITLE_PTRS, MAP_TITLE = 0x268400, 0x0EF100
local function mapTitleHere()
  local p = H.readRomWord(MAP_TITLE_PTRS + H.readByte(0x0520) * 2)
  local a, s = MAP_TITLE + p, ""
  for _ = 1, 24 do
    local c = H.readRomByte(a)
    if c == 0 then break end
    if     c >= 0x20 and c <= 0x39 then s = s .. string.char(65 + c - 0x20)
    elseif c >= 0x3A and c <= 0x53 then s = s .. string.char(97 + c - 0x3A)
    elseif c >= 0x54 and c <= 0x5D then s = s .. string.char(48 + c - 0x54)
    elseif c == 0x65 then s = s .. "."
    elseif c == 0x7F then s = s .. " "
    else s = s .. string.format("<%02X>", c) end
    a = a + 1
  end
  return s
end

local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }
local function partyReport(tag)
  local party, raw = {}, {}
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    raw[#raw + 1] = string.format("%s=%02X", CHARS[c + 1], b)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      party[#party + 1] = string.format("%s(order %d, L%d, weapon %02X)",
        CHARS[c + 1], (b >> 3) & 3, H.readByte(base + 0x08),
        H.readByte(base + 0x1F))
    end
  end
  return string.format("[party @ %s] party#%d = %s   | $1850: %s | $1EDE=%02X $1EDF=%02X",
    tag, cur, table.concat(party, ", "), table.concat(raw, " "),
    H.readByte(0x1EDE), H.readByte(0x1EDF))
end

local DELTA = { up = { 0, -1 }, right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 } }

-- Tap `dir` whenever the party has control, hands off while a scene owns
-- it, edge-A through dialogs.  Used to walk INTO a trigger whose scene then
-- takes over -- the tap keeps the party from sliding past the tile.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if hb % 120 == 0 then
        H.log(string.format("tapInto f%d (%d,%d) phase=%d ctl=%s algn=%s "
          .. "dlg=%s ev=%s $01B5=%d face=%d",
          H.frame, H.fieldX(), H.fieldY(), phase, tostring(H.hasControl()),
          tostring(H.tileAligned()), tostring(H.dialogWaiting()),
          tostring(H.eventRunning()), sw(0x01B5),
          H.readByte(0x087f + H.readWord(0x0803))))
      end
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        -- STOP TAPPING once we are where we were going.  The terminator
        -- wants 16 consecutive calm frames on the target, and an eager tap
        -- walks straight off it before the count gets there: the first
        -- version of this rode the chute correctly to (10,45) and then
        -- tapped itself to (10,46) and timed out.
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

local function census(tag, targets)
  local sx, sy = H.fieldX(), H.fieldY()
  local xm, ym = H.readByte(0x0086), H.readByte(0x0087)
  local seen, q, qi = { [(sy & ym) * 256 + (sx & xm)] = true }, { { sx, sy } }, 1
  while qi <= #q and qi <= 3000 do
    local x, y = q[qi][1], q[qi][2]; qi = qi + 1
    for d, v in pairs(DELTA) do
      if H.canStep(x, y, d) then
        local nx, ny = (x + v[1]) & xm, (y + v[2]) & ym
        local k = ny * 256 + nx
        if not seen[k] then seen[k] = true; q[#q + 1] = { nx, ny } end
      end
    end
  end
  H.log(string.format("[census %s] from (%d,%d) on map %d: %d tiles reachable",
    tag, sx, sy, map(), #q))
  for _, t in ipairs(targets or {}) do
    local p = H.bfsPath(t[1], t[2])
    H.log(string.format("[census %s] -> (%d,%d) %-34s : %s", tag, t[1], t[2],
      t[3] or "", p and (#p .. " steps: " .. table.concat(p, " ")) or "NO PATH"))
  end
end


H.run({ maxFrames = 60000 }, {
  H.loadState("build/states/mrf_kefka.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 263, "booted on map 263")
    H.assertEq(H.fieldX(), 39, "boot x")
    H.assertEq(H.fieldY(), 31, "boot y")
    H.assertEq(sw(0x005F), 1, "$005F SET at boot -- the esper drain has run")
    H.assertEq(sw(0x0646), 1, "$0646 SET -- the dying Ifrit/Shiva pair is placed")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR -- battle 70 has not been fought")
    H.assertEq(sw(0x0273), 0, "$0273 CLEAR -- the alcove is not locked yet")
    H.log(partyReport("mrf_kefka"))
  end),

  -- 1. south to the chute row.  Any of {36,44}/{37,44}/{38,44} fires it,
  --    so navTo aims at the middle one and terminates on the map change.
  H.navTo(37, 44, { maxFrames = 40000, playBattles = "flee",
    arrive = function() return map() == 264 end }),
  H.waitUntil(function() return map() == 264 end, 12000,
    "the chute -> map 264", 5),
  H.waitUntil(function() return map() == 264 and settled() end, 9000,
    "map 264 control", 5),
  H.waitFrames(90),

  H.call(function()
    H.assertEq(map(), 264, "the Ifrit/Shiva alcove is map 264")
    H.assertEq(H.fieldX(), 10, "264 landing x (_cc7588 obj_script)")
    H.assertEq(H.fieldY(), 7, "264 landing y")
    H.assertEq(sw(0x0646), 1, "$0646 still SET -- both espers are standing")
    H.assertEq(sw(0x0060), 0, "$0060 still CLEAR")
    -- CORRECTION to the route recon's esper-alcove decode, which says the
    -- pair "sit on the two doors ... Ifrit (3,8) is under 264 (3,5)->270,
    -- Shiva (9,6) is under 264 (9,5)->269".  Only the second is load
    -- bearing: Shiva at {9,6} is the tile directly below the {9,5} door
    -- and does block it, but Ifrit at {3,8} is THREE tiles below the {3,5}
    -- save-room door and does not -- the save room is reachable before the
    -- fight.  Measured here rather than assumed, and asserted in the
    -- direction that is actually true, because this is the positive
    -- control for the fight step: if {9,5} were already walkable, "the
    -- fight opened the way onward" would prove nothing.
    H.log(string.format("[doors] bfsPath (3,5) save room = %s ; (9,5) onward = %s",
      H.bfsPath(3, 5) and (#H.bfsPath(3, 5) .. " steps") or "NO PATH",
      H.bfsPath(9, 5) and (#H.bfsPath(9, 5) .. " steps") or "NO PATH"))
    H.assertEq(H.bfsPath(9, 5), nil,
      "CONTROL: the way onward (9,5) is blocked -- Shiva stands on (9,6)")
    H.log(string.format("[264 landing] f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
    census("264 landing", {
      { 3, 7, "above Ifrit" },
      { 9, 7, "below Shiva" },
      { 6, 6, "_cc75f6, the way back up to 263" },
      { 3, 5, "door -> map 270 (save room)" },
      { 9, 5, "door -> map 269 (onward)" },
    })
    H.screenshot("mrf_264_landing")
  end),

  -- 1b. THE BOUNDARY DETOUR (issue #25).  This step is A->B's terminal, so
  --     before parking on the fight's entry point it walks the {3,5} door
  --     into the map-270 save room, stands on the save point, and asserts
  --     the mrf-save-room-v1 boundary table -- the same table
  --     gen_mrf_save_room_checkpoint saves under and gen_ifrit_magicite's
  --     checkpoint boot asserts as its ENTRY contract.  The sram witnesses
  --     are products of the boundary save itself, so the step asserts the
  --     pre-save variant (lib/ot6_contract.lua, assertExitContractPreSave).
  --     Standing on a save tile re-enters SavePoint every frame and
  --     hasControl() flickers (the same trap gen_esper_tubes measured on
  --     {10,9}), so arrival is judged on position + $01BF + alignment.
  H.navTo(3, 6, { maxFrames = 12000, playBattles = "flee" }),
  tapInto("up", function() return map() == 270 end, 9000,
    "door 264 (3,5) -> map 270 (the save room)"),
  H.waitFrames(60),
  H.navTo(25, 11, { maxFrames = 12000, playBattles = "flee" }),
  (function() local calm = 0
    return H.driveUntil(function()
      calm = (H.fieldX() == 25 and H.fieldY() == 10 and sw(0x01BF) == 1
              and H.tileAligned() and not H.dialogWaiting()
              and not H.battleLoadStarted()) and calm + 1 or 0
      return calm >= 8
    end, 9000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        if H.dialogWaiting() then H.setPad({ "a" }); return end
        if H.fieldX() == 25 and H.fieldY() == 10 then H.setPad({}); return end
        H.setPad({ up = true })
      end),
    }, "onto the save tile 270 (25,10)")
  end)(),
  H.waitFrames(45),
  H.call(function()
    H.assertEq(sw(0x01BF), 1, "$01BF SET -- the save-enable flow ran")
    H.assertEq(sw(0x01B5), 1, "$01B5 SET -- the once-per-tile latch took")
    H.assertExitContractPreSave("mrf-save-room-v1")
    H.screenshot("mrf_save_room")
  end),
  tapInto("down", function() return map() == 264 end, 12000,
    "back down through the door -> 264"),
  H.waitFrames(60),

  -- 2. park ON THE ENTRY POINT OF THE FIGHT: {3,7}, directly above Ifrit's
  --    {3,8}, facing DOWN.  One A-press from _cc7937 and `battle 70`, the
  --    same shape as opera_entry.  A DOWN press here cannot step (his
  --    object occupies {3,8}) so it only turns the party.
  H.navTo(3, 7, { maxFrames = 24000, playBattles = "flee" }),
  H.hold({ "down" }), H.waitFrames(8), H.release(), H.waitFrames(20),
  (function() local calm = 0
    return H.driveUntil(function()
      local ok = H.fieldX() == 3 and H.fieldY() == 7 and settled()
             and H.readByte(0x087f + H.readWord(0x0803)) == 2
      calm = ok and calm + 1 or 0
      if calm >= 20 then H.setPad({}); return true end
      return false
    end, 3000, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
        H.setPad({})
      end) }, "twenty settled frames above IFRIT")
  end)(),

  H.call(function()
    H.assertEq(map(), 264, "on map 264")
    H.assertEq(H.fieldX(), 3, "Ifrit entry point x")
    H.assertEq(H.fieldY(), 7, "Ifrit entry point y")
    H.assertEq(H.readByte(0x087f + H.readWord(0x0803)), 2,
      "facing DOWN toward IFRIT (EVENT_DIR 2)")
    H.assertEq(settled(), true, "the entry point is QUIET")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR -- battle 70 is still ahead")
    H.assertEq(sw(0x0273), 0, "$0273 CLEAR")
    H.assertEq(H.readByte(0x1A69) & 0x02, 0, "IFRIT not yet owned ($1A69 bit1)")
    H.assertEq(H.readByte(0x1A69) & 0x04, 0, "SHIVA not yet owned ($1A69 bit2)")
    H.assertEq(H.readByte(0x1A69) & 0x01, 0x01, "RAMUH owned from Zozo ($1A69 bit0)")
    H.log(string.format("[ifrit_entry] f%d map=%d (%d,%d) face=%d $1A69=%02X",
      H.frame, map(), H.fieldX(), H.fieldY(),
      H.readByte(0x087f + H.readWord(0x0803)), H.readByte(0x1A69)))
    H.log(partyReport("ifrit_entry"))
    H.screenshot("ifrit_entry")
  end),
  H.saveState("ifrit_entry.mss"),

  -- 3. VERIFY the banked state is genuinely one A-press from battle 70.
  --    Runs AFTER the state is generated, so the saved blob is untouched.
  --    Without this an entry point can be a dead one-press-short state and
  --    nothing notices until the fight step fails far away from the cause.
  (function() local hb, aPh = 0, 0
    return H.driveUntil(function()
      return H.battleLoadStarted() and H.formationHas({ [0x0109] = true })
    end, 9000, {
      H.call(function() hb = hb + 1; aPh = (aPh + 1) % 8
        if hb % 300 == 0 then
          H.log(string.format("[verify f%d] batt=%s $0060=%d",
            hb, tostring(H.battleLoadStarted()), sw(0x0060)))
        end
        H.setPad(aPh < 4 and { "a", "down" } or { "down" })
      end) }, "one A-press fires _cc7937 -> battle 70")
  end)(),
  H.call(function()
    local w = H.formationWords()
    H.assertEq(H.formationHas({ [0x0109] = true }), true,
      "VERIFIED: one A-press opened battle 70 with species $0109 (Ifrit)")
    H.log(string.format("[verify] formation = %04X %04X %04X %04X %04X %04X",
      w[1], w[2], w[3], w[4], w[5], w[6]))
    H.screenshot("ifrit_entry_verify")
  end),
  H.logStep(function()
    return string.format("ifrit_entry generated at frame %d -- map 264 (3,7) "
      .. "facing IFRIT, one A-press from battle 70", H.frame)
  end),
})
