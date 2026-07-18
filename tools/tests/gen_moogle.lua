-- gen_moogle.lua -- from moogle_doorstep.mss (TERRA in Magitek armor at
-- (55,12), map 50, one south of the collapse trigger): step onto (55,11)
-- and ride the WHOLE opening set-piece chain to its far side, minting two
-- states on the way:
--
--   moogle_defense.mss  -- the three-party Moogle defense, first player-
--                          controlled frame (map 51, party 1 = LOCKE+3
--                          moogles at (14,14), Marshal waiting at (15,40))
--   moogle_cleared.mss  -- the far side: LOCKE leads TERRA on the Narshe
--                          streets (map 20), defense won, control returned
--
-- SEQUENCE (all one event, _cca2e5, event_trigger.asm map 50 {55,11},
-- body event_main.asm:102027-103283):
--   * bridge collapse choreography; TERRA falls (map 51 mosaic scene)
--   * Kefka slave-crown flashback (map 250), then the scripted Magitek
--     flashback fight `battle 115` (map 5, event_main.asm:102351) --
--     monsters are plain soldiers, kill-bit clears it like any wave
--   * Gestahl rally (map 244), TERRA wakes in the caves (map 51)
--   * Arvis recruits LOCKE (map 30): dialogs, then `name_menu LOCKE`
--     (event_main.asm:102678) -- the ONE beat advanceStory cannot tap
--     ($0059 flips as the menu opens; START commits the default name,
--     same split as gen_narshe_escape.lua:47-52)
--   * moogle cave scenes; choice dialog $0036 (A picks "Yes", the extra
--     info page $0037 is harmless); 11 moogles join LOCKE across three
--     parties (event_main.asm:103137-103207)
--   * defense setup: switches $0631=1 $060A..$0610=1 $012E=1 $0003=1,
--     map 51 loads with STARTUP_EVENT (its map-init _ccab6f starts the
--     six guard marches), fade in, player_ctrl_on (:103280-103283)
--
-- THE DEFENSE (why the assault below is shaped the way it is):
--   * guards NPC_4..NPC_9 spawn at (15,34)..(15,39) (npc_prop.asm map 51)
--     and march scripted paths toward TERRA at (14,12); each march tail
--     `exec _cccb82` = GAME OVER (event_main.asm:108630), so time matters
--   * touching a marching guard fires `battle 5, DEFAULT, COLLISION`
--     (their npc events _ccaadf.._ccab57 via collision_on); the kill-bit
--     idiom wins it and the win path despawns that guard ($060A..$060F=0)
--   * the Marshal (NPC_3) STANDS STILL at (15,40) facing UP with npc
--     event _ccada8 -> `battle 6` (event_main.asm:103759-103762); no
--     collision_on, so the activation is walking into him / A facing him
--   * winning battle 6 runs _ccadbf: guards despawn, switch $0631=0 (the
--     defense-won marker, :103782 -- its ONLY clear), "Thanks, Moogles!",
--     the mine switch scene, TERRA's amnesia dialogs, the secret-entrance
--     reveal on map 20, force-walk DOWN 2 + RIGHT 23 from {15,56}, then
--     max_hp/and_status on TERRA+LOCKE+MOG, player_ctrl_on, $01CC=1
--     (:103769-104188).  First calm control: map 20, LOCKE + TERRA.
--
-- Every battle in this unit dies to the kill-bit -- the waves are chaff
-- and killing the Marshal IS winning battle 6 -- so unlike gen_arvis
-- there is NO spare list anywhere; the fight logger below still names
-- every formation for the record.
--
-- Switch -> RAM derivations (event bitfield base $1E80, bit = switch&7):
--   $012E -> $1EA5 mask $40      $0631 -> $1F46 mask $02
--   $0609..$060F -> $1F41 masks $02,$04..$80    $0610 -> $1F42 mask $01
--   $012F -> $1EA5 mask $80      $01CC -> $1EB9 mask $10
--   $0003 -> $1E80 mask $08
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local DOORSTEP = "/Users/mtklein/ot6/build/states/moogle_doorstep.mss.lua"

local function collapseStarted()        -- $012E: set as the defense goes live
  return (H.readByte(0x1ea5) & 0x40) ~= 0
end
local function defenseWon()             -- $0631 cleared ONLY by the win path
  return (H.readByte(0x1f46) & 0x02) == 0
end

-- n consecutive calm frames (control, at rest), optionally an extra pred
local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

local function eventFor(n)
  local cnt = 0
  return function()
    cnt = H.eventRunning() and cnt + 1 or 0
    return cnt >= n
  end
end

-- name every fight once on its 3rd consecutive loading frame (the
-- gen_whelk_poweron pattern: registered outside the step machine so
-- whichever phase is driving, the formation gets logged; read-only)
local fightN = 0
emu.addEventCallback(function()
  fightN = H.battleLoadStarted() and fightN + 1 or 0
  if fightN == 3 then
    local w = H.formationWords()
    H.log(string.format("fight up f%d map=%d (%04X %04X %04X %04X %04X %04X)",
      H.frame, H.mapId(), w[1], w[2], w[3], w[4], w[5], w[6]))
  end
end, emu.eventType.startFrame)

local aPhase = 0

-- the Marshal's post: npc_prop.asm map 51 NPC_3, {15,40}, static (no
-- obj_script in _ccab6f moves him)
local MX, MY = 15, 40

-- first tile adjacent to the Marshal that BFS can currently reach; the
-- candidate list prefers the head-on northern approach.  Re-resolved at
-- every navTo (re)plan, so a marching guard parking on a candidate for a
-- while just shifts us to the next one.  Memoized per frame: navTo
-- resolves tx and ty separately and BFS x8 is not a per-frame price.
local approach = { { MX, MY - 1 }, { MX - 1, MY }, { MX + 1, MY },
                   { MX, MY + 1 }, { MX - 1, MY - 1 }, { MX + 1, MY - 1 } }
local apFrame, apPick = -1000, nil
local function marshalApproach()
  -- refreshed at most every 30 frames: navTo resolves the target thunks in
  -- its every-frame done-pred, and 6 BFS probes per frame would drag the
  -- emulator for no routing benefit (guards shift on a seconds scale)
  if H.frame - apFrame >= 30 then
    apFrame = H.frame
    apPick = approach[1]
    for _, c in ipairs(approach) do
      if H.bfsPath(c[1], c[2], NAV.blocked) then apPick = c; break end
    end
  end
  return apPick
end

local function marshalAdjacent()
  local dx, dy = MX - H.fieldX(), MY - H.fieldY()
  return math.abs(dx) + math.abs(dy) == 1
end

-- one activation attempt: while adjacent, cycle 2 frames facing-press /
-- 4 frames A / 2 neutral until a battle actually loads (3-frame debounce
-- on monsters-present: the load signal lives in field-scribbled RAM) or
-- the defense is already won.  `round` only names the log line.
local function pokeStep(round)
  local battN = 0
  return H.driveUntil(function()
    battN = (H.battleLoadStarted() and H.monstersPresent() > 0)
        and battN + 1 or 0
    if battN == 3 then
      local w = H.formationWords()
      H.log(string.format("poke %d engaged: %04X %04X %04X %04X %04X %04X",
        round, w[1], w[2], w[3], w[4], w[5], w[6]))
    end
    return defenseWon() or battN >= 3
  end, 900, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if not (H.hasControl() and marshalAdjacent()) then H.setPad({}); return end
      local dx, dy = MX - H.fieldX(), MY - H.fieldY()
      local dir = dx == 1 and "right" or dx == -1 and "left"
               or dy == 1 and "down" or "up"
      if aPhase < 2 then H.setPad({ [dir] = true })
      elseif aPhase < 6 then H.setPad({ "a" })
      else H.setPad({}) end
    end),
  }, "battle 6 (or a wave) engages [round " .. round .. "]")
end

-- post-battle settle: hands off until either the won switch lands (battle
-- 6's win path fades in and clears $0631 before the epilogue walks) or
-- control returns (a wave was cleared; the fight is still on)
local function settleStep()
  return H.driveUntil(function()
    return defenseWon() or (H.hasControl() and H.tileAligned())
  end, 1200, { H.call(function() H.setPad({}) end) }, "post-battle settle")
end

H.run({ maxFrames = 90000 }, {
  H.loadState(DOORSTEP),
  H.waitFrames(10),
  H.waitUntil(function() return H.hasControl() end, 300, "doorstep control", 5),
  H.call(function()
    H.assertEq(H.mapId(), 50, "boot map is the mines chase map (50)")
    H.assertEq(H.fieldX() == 55 and H.fieldY() == 12, true,
      "at the moogle doorstep (55,12)")
    H.assertEq(collapseStarted(), false, "collapse switch $012E clear")
  end),

  -- ===================================================================== --
  -- Phase 1: the deliberate step onto (55,11).  A random encounter on the
  -- step is cleared inline (kill-bit + edge-A); the trigger fires the
  -- moment we stand on the tile, so the terminator is a sustained event.
  -- ===================================================================== --
  H.driveUntil(eventFor(30), 1200, {
    H.call(function()
      aPhase = (aPhase + 1) % 8
      if H.battleLoadStarted() then
        if H.monstersPresent() > 0 then
          for slot = 0, 5 do
            if H.readByte(0x3aa8 + slot * 2) % 2 == 1 then
              H.writeByte(0x3eec + slot * 2, H.readByte(0x3eec + slot * 2) | 0x80)
            end
          end
        end
        H.setPad(aPhase < 4 and { "a" } or {})
        return
      end
      if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then H.setPad({}); return end
      H.setPad(H.fieldY() <= 11 and { down = true } or { up = true })
    end),
  }, "collapse trigger fires"),
  H.logStep(function()
    return string.format("collapse event running at frame %d", H.frame)
  end),

  -- ===================================================================== --
  -- Phase 2: everything up to the LOCKE naming menu.  advanceStory taps
  -- dialogs, kill-bits battle 115's soldiers, and stays hands-off through
  -- the choreography.  The menu detector is NOT the $0059 idiom
  -- gen_narshe_escape used: $59 is also battle-module scratch, and run 1
  -- measured it flipping nonzero DURING battle 115 -- the pred fired
  -- mid-fight and the real menu later sat unattended forever.  The
  -- reliable signature is the menu itself: it SUSPENDS the field module,
  -- so control, the event PC, dialogs and battle all read dead at once --
  -- a combination no scene shows for long (event waits hold the PC in
  -- CA-range; ambient ev=false pulses last a frame or two) -- sustained
  -- for 120 consecutive frames on map 30 (run 1 measured the stall
  -- holding for 20k+ frames; nothing else on map 30 goes quiet at all:
  -- the walk-in choreography and the four Arvis dialogs keep ev/dlg live).
  -- ===================================================================== --
  H.advanceStory((function()
    local cnt = 0
    return function()
      local quiet = H.mapId() == 30 and not H.hasControl()
        and not H.eventRunning() and not H.dialogWaiting()
        and not H.battleLoadStarted()
      cnt = quiet and cnt + 1 or 0
      return cnt >= 120
    end
  end)(), 30000),
  H.logStep("naming menu open (field module suspended); committing LOCKE"),
  H.call(function() H.screenshot("moogle_naming") end),
  -- START commits the default name (name_change.asm exits on START unless
  -- the name is blank -- the gen_narshe_escape precedent); pressed on
  -- repeat until the event engine audibly resumes, because a single press
  -- during any residual menu fade would vanish
  H.driveUntil(eventFor(10), 1200, {
    H.pressButtons({ "start" }, 8),
    H.waitFrames(12),
  }, "naming committed, event resumed"),

  -- ===================================================================== --
  -- Phase 3: the rest of the recruitment + moogle scenes to the defense.
  -- Done = calm control on map 51 with $012E set: the switch lands three
  -- event commands before player_ctrl_on (event_main.asm:103278-103283),
  -- so calm+switch is exactly "the defense is live and ours to play".
  -- ===================================================================== --
  H.advanceStory(calm(30, function()
    return H.mapId() == 51 and collapseStarted()
  end), 25000),
  H.call(function()
    H.assertEq(H.mapId(), 51, "on the defense map (51)")
    H.assertEq(collapseStarted(), true, "defense-live switch $012E set")
    H.assertEq(defenseWon(), false, "defense not yet won ($0631 still set)")
    H.assertEq(H.readByte(0x1f41) & 0xFC, 0xFC,
      "all six guard switches $060A..$060F set")
    H.log(string.format("defense live: party 1 at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame))
    -- log the field objects the fight cares about (Marshal = NPC_3 =
    -- object 18, guards NPC_4..9 = 19..24, TERRA-down = 25; object i's
    -- pixel coords live at $086A/$086D + $29*i, tiles = >>4)
    for i = 16, 25 do
      local ox = H.readWord(0x086a + 0x29 * i) >> 4
      local oy = H.readWord(0x086d + 0x29 * i) >> 4
      H.log(string.format("object %d at (%d,%d)", i, ox, oy))
    end
    H.screenshot("moogle_defense")
  end),
  H.saveState("moogle_defense.mss"),

  -- ===================================================================== --
  -- Phase 4a: let the defense fight itself.  The corridor south is the
  -- guards' own single-file column -- at defense-live all six marchers
  -- plug (15,35)..(15,39) wall to wall and BFS correctly finds NO path to
  -- the Marshal (run 3 measured exactly that failure).  No walking is
  -- needed: the parked parties 2/3 ring TERRA, every march path collides
  -- with one of them, each collision is a `battle 5` the kill-bit wins,
  -- and the win path despawns that guard -- $060A..$060F clear one by one
  -- (run 2 measured all six dead ~7600 frames in, game-over never fired,
  -- and the map stayed quiet for 11k frames after).  advanceStory rides
  -- the storm hands-off; the cleared switches say the column is gone.
  -- ===================================================================== --
  H.advanceStory(function()
    return (H.readByte(0x1f41) & 0xFC) == 0
  end, 15000),
  H.logStep(function()
    return string.format(
      "all six wave guards down at frame %d; corridor open", H.frame)
  end),
  H.waitUntil(calm(30), 1200, "post-storm calm"),

  -- ===================================================================== --
  -- Phase 4b: the assault.  BFS to whichever tile beside the Marshal is
  -- reachable (he stands alone at (15,40) now).  arrive also accepts
  -- defenseWon in case a straggler collision with the MARSHAL starts
  -- battle 6 early -- the kill-bit wins that one too, which IS the goal,
  -- not a fight to protect.
  -- ===================================================================== --
  H.navTo(function() return marshalApproach()[1] end,
          function() return marshalApproach()[2] end, {
    arrive = function()
      return defenseWon() or (marshalAdjacent() and H.hasControl() and H.tileAligned())
    end,
    maxFrames = 15000,
  }),
  H.logStep(function()
    return string.format("beside the Marshal at (%d,%d), frame %d",
      H.fieldX(), H.fieldY(), H.frame)
  end),

  -- activate him: hold the facing direction (a blocked step both turns us
  -- and registers a push) and edge-tap A; whichever mechanism his npc
  -- event uses, battle 6 comes up.  A wave guard reaching us here instead
  -- just gets kill-bitted like the rest; the second round below walks back
  -- in and pokes again.  Two rounds are written out FLAT rather than via
  -- repeatN: cond/driveUntil/navTo steps carry no reset(), so a repeated
  -- body replays the first pass's latched branch choice and spent budgets
  -- instead of running fresh -- distinct step objects sidestep that.
  pokeStep(1),
  H.cond(function() return H.battleLoadStarted() end, {
    H.clearBattle(9000),
    settleStep(),
  }, {}),
  H.cond(function() return defenseWon() end, {}, {
    H.navTo(function() return marshalApproach()[1] end,
            function() return marshalApproach()[2] end, {
      arrive = function()
        return defenseWon() or (marshalAdjacent() and H.hasControl() and H.tileAligned())
      end,
      maxFrames = 8000,
    }),
    pokeStep(2),
    H.cond(function() return H.battleLoadStarted() end, {
      H.clearBattle(9000),
      settleStep(),
    }, {}),
  }),
  H.call(function()
    H.assertEq(defenseWon(), true, "defense won (switch $0631 cleared)")
    H.log(string.format("Marshal down at frame %d; riding the epilogue", H.frame))
  end),

  -- ===================================================================== --
  -- Phase 5: the epilogue chain (Thanks-Moogles, the mine switch, TERRA's
  -- amnesia dialogs, the secret entrance) ends with player_ctrl_on and
  -- $01CC=1 on map 20 (event_main.asm:104186-104188); no menus, so
  -- advanceStory rides all of it.
  -- ===================================================================== --
  H.advanceStory(calm(60, function()
    return H.mapId() == 20 and (H.readByte(0x1eb9) & 0x10) ~= 0
  end), 30000),

  -- ===================================================================== --
  -- Phase 6: assert the far side and mint.  Roster: char_party TERRA,1 /
  -- LOCKE,1 and every moogle-bearing slot zeroed (event_main.asm:
  -- 103810-103821); party bytes live at $1850+char (low 3 bits = party).
  -- ===================================================================== --
  H.call(function()
    H.assertEq(H.mapId(), 20, "far side is the Narshe streets (map 20)")
    H.assertEq(defenseWon(), true, "defense-won switch state")
    -- bits 1-7 = $0609..$060F (moogle-visible + the six guards); bit 0 is
    -- the unrelated $0608, which run 4 measured set on the far side
    H.assertEq(H.readByte(0x1f41) & 0xFE, 0,
      "guard/moogle switches $0609..$060F clear")
    H.assertEq((H.readByte(0x1ea5) & 0x80) ~= 0, true,
      "secret-entrance switch $012F set")
    H.assertEq(H.readByte(0x1850) & 0x07, 1, "TERRA in party 1")
    H.assertEq(H.readByte(0x1851) & 0x07, 1, "LOCKE in party 1")
    for c = 2, 12 do
      H.assertEq(H.readByte(0x1850 + c) & 0x07, 0,
        string.format("char %d out of party", c))
    end
    -- TERRA per script: max_hp + and_status NONE (event_main.asm:
    -- 104170-104175); char block $1600: +$09 cur HP, +$0B max HP
    local hp, maxhp = H.readWord(0x1609), H.readWord(0x160b)
    H.assertEq(hp > 0 and hp == (maxhp & 0x3fff), true,
      string.format("TERRA at full HP (%d/%d)", hp, maxhp & 0x3fff))
    H.log(string.format("cleared: map=%d (%d,%d) frame=%d",
      H.mapId(), H.fieldX(), H.fieldY(), H.frame))
    H.screenshot("moogle_cleared")
  end),
  H.saveState("moogle_cleared.mss"),
  H.logStep(function()
    return string.format("moogle_cleared minted at frame %d", H.frame)
  end),
})
