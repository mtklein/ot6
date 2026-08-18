-- probe_thamasa_names.lua -- issue #127 hazard 5: the character-naming
-- screen idiom, driven for the first time by any generator.  No -- @suite
-- marker: this is a one-shot measurement, not a suite test.
--
-- From build/states/crescent_landing.mss (world (232,150), party
-- TERRA-LOCKE-SHADOW), walk onto world (250,128) -> Thamasa, map 343
-- (23,46) (event_trigger.asm:37 -> _cbd2ee, event_main.asm:69190).  Cross
-- town to Strago's house door 343 (29,13) -> 349 (37,24)
-- (docs/design/thamasa-route.md Segment 2), talk to Strago (NPCProp::_349
-- record 0, obj $10, event _cbd982, event_main.asm:69814) and ride the
-- long scene through two naming screens (name_menu STRAGO :69871,
-- name_menu RELM :70067) to its end (load_map 343 {29,15} DOWN,
-- event_main.asm:70405-70410).
--
-- The commit idiom is not guessed here: it is gen_edgar.lua's commitName,
-- already measured and shipped for name_menu EDGAR/SABIN and reused
-- verbatim by gen_voyage.lua's rideScene for name_menu SHADOW.  A naming
-- menu suspends the field module entirely ($59 ~= 0), so advanceStory's
-- own dialog-paging cannot reach into it; START commits the pre-filled
-- default name (name_change.asm exits on START unless the name is blank)
-- and has to be pressed on repeat because a single press during the menu's
-- own fade-in is lost.  This probe's only open question is whether that
-- idiom -- proven on three single name menus -- also clears two back to
-- back in the same scene with no field frame between them.
--
-- One measured correction to the task's own framing, worth stating up
-- front: $008D is NOT a "scene complete" flag.  Reading the scene
-- (event_main.asm:69837-69854), `switch $008D=1` fires right after the
-- FIRST dialog line ("Whatcha want with me?"), a good 30+ frames BEFORE
-- either naming screen opens.  It means "Strago has been engaged", not
-- "the introduction is over".  This probe logs the frame it flips
-- separately from the frame the whole scene (both names, all the
-- dialogue, the walk back outside) actually ends.
--
-- Watch-fors from the task brief, handled below:
--   * map 343's STARTUP_EVENT town-intro scene on first entry -- ridden
--     with advanceStory before any navigation is attempted.
--   * the two magic-vignette triggers at 343 (35,15)/(25,12)
--     (event_trigger.asm:1670-1672) -- avoided via navTo's opts.avoid.
--   * the inn's pre-Strago 1500gp charge -- irrelevant, never touched.

local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function menuUp() return H.readByte(0x0059) ~= 0 end
local function seq(steps) return H.cond(function() return true end, steps) end

local function calm(n, extra)
  local cnt = 0
  return function()
    local ok = H.hasControl() and H.tileAligned() and (not extra or extra())
    cnt = ok and cnt + 1 or 0
    return cnt >= n
  end
end

-- ------------------------------------------------------- naming screen --
-- gen_edgar.lua's commitName, unchanged: advance the story until a naming
-- menu is up, wait out its fade-in, screenshot+log it, then hold-repeat
-- START until the event engine has resumed AND the menu flag is back down
-- for 10 straight frames (debounced the same way navTo debounces battle/
-- dialog signals -- a 1-frame ghost of either flag is not trustworthy).
local d8DFlips = nil
local sceneStartFrame = nil
local function commitName(tag)
  local running = 0
  return seq({
    H.advanceStory(menuUp, 20000, { playBattles = "tactical" }),
    H.waitFrames(180),
    H.call(function()
      H.log(string.format(
        "[ot6] %s: naming menu open at f%d ($59=%d menu_state=$%02X) $008D=%d",
        tag, H.frame, H.readByte(0x0059), H.readByte(0x0026), sw(0x008D)))
      if d8DFlips == nil and sw(0x008D) == 1 then
        d8DFlips = H.frame
        H.log(string.format(
          "[ot6] $008D flipped to 1 by f%d (frames since scene start: %d) " ..
          "-- NOTE: this is the 'Strago engaged' switch, set right after " ..
          "the very first dialog line, well before either naming screen",
          H.frame, H.frame - (sceneStartFrame or H.frame)))
      end
      H.screenshot(tag)
    end),
    H.driveUntil(function()
      running = (H.eventRunning() and not menuUp()) and running + 1 or 0
      return running >= 10
    end, 1800, {
      H.pressButtons({ "start" }, 8),
      H.waitFrames(12),
    }, tag .. ": name committed, event resumed"),
    H.call(function()
      H.log(string.format("[ot6] %s: confirm idiom = START held 8f / released " ..
        "12f, repeated, until eventRunning()&&!menuUp() held 10 consecutive " ..
        "frames (committed by f%d)", tag, H.frame))
    end),
  })
end

-- ------------------------------------------------------------- doors --
-- gen_edgar.lua's crossDoor, ported with an opts.avoid passthrough for the
-- two vignette tiles this town carries.  A door is a wall until CheckDoor
-- opens it (HANDOFF trap 6: navTo lands at rest, so the tile that takes the
-- party away must be crossed with a held press), so this is navTo-a-
-- neighbour, then hold into the door.
local DIAGSTAGE = {
  { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" },
  { -1, 1, "upright" }, { -1, -1, "downright" },
  { 1, -1, "downleft" }, { 1, 1, "upleft" },
}
local function crossDoor(sx, sy, dm, dx, dy, what, opts)
  opts = opts or {}
  local pick, startMap
  local function stage()
    if not pick then
      for _, c in ipairs(DIAGSTAGE) do
        local cx, cy, move = sx + c[1], sy + c[2], c[3]
        local press = H.movePress(move)
        if H.bfsPath(cx, cy) and (press == move or H.canStep(cx, cy, move)) then
          pick = { cx, cy, press }; break
        end
      end
      pick = pick or { sx, sy + 1, "up" }
      H.log(string.format("%s: staging (%d,%d), hold %s into (%d,%d)",
        what, pick[1], pick[2], pick[3], sx, sy))
    end
    return pick
  end
  local settled = calm(20)
  local aPhase = 0
  return seq({
    H.call(function() pick, startMap = nil, map() end),
    H.navTo(function() return stage()[1] end, function() return stage()[2] end,
      { maxFrames = 9000, playBattles = "flee", avoid = opts.avoid,
        arrive = function() return map() ~= startMap end }),
    H.driveUntil(function()
      return map() ~= startMap or (H.fieldX() == dx and H.fieldY() == dy)
    end, 1800, {
      H.call(function()
        aPhase = (aPhase + 1) % 8
        if H.dialogWaiting() then H.setPad(aPhase < 4 and { "a" } or {}); return end
        H.setPad({ [stage()[3]] = true })
      end),
    }, what),
    H.release(),
    H.waitUntil(settled, 1800, what .. ": far-side control"),
    H.waitUntil(function()
      return (emu.getState()["ppu.screenBrightness"] or 0) >= 15
    end, 900, what .. ": fade-in", 10),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(map(), dm, what .. ": landed on the right map")
      H.log(string.format("[ot6] %s: DONE (%d,%d) frame=%d", what,
        H.fieldX(), H.fieldY(), H.frame))
    end),
  })
end

-- ------------------------------------------------------------- steps --
local steps = {
  H.loadState("build/states/crescent_landing.mss.lua"),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format(
      "[ot6] boot f%d world=%s (%d,%d) party0=%02X party1=%02X party2=%02X",
      H.frame, tostring(H.worldMode()), H.worldX(), H.worldY(),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1852) & 7))
    H.assertEq(H.worldMode(), true, "on the world map")
    H.assertEq(H.worldX(), 232, "landing x")
    H.assertEq(H.worldY(), 150, "landing y")
  end),

  -- ---- 1. world walk onto the Thamasa trigger --------------------------
  H.worldNavTo(249, 128, { maxFrames = 6000, playBattles = "flee" }),
  H.call(function()
    H.log(string.format("[ot6] at (249,128) staging tile, f%d", H.frame))
  end),
  H.driveUntil(function() return not H.worldMode() end, 2000, {
    H.call(function()
      if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
      H.setPad({ right = true })
    end),
  }, "held RIGHT onto (250,128) -> Thamasa 343 (23,46)"),
  H.release(),
  H.waitUntil(function() return map() == 343 and H.hasControl() end, 3000,
    "Thamasa map loaded", 5),
  H.call(function()
    H.log(string.format("[ot6] town entry f%d map=%d (%d,%d)",
      H.frame, map(), H.fieldX(), H.fieldY()))
  end),

  -- ---- 2. ride the first-entry STARTUP_EVENT scene, if any -------------
  H.advanceStory(calm(30), 20000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "still on Thamasa town map")
    H.log(string.format("[ot6] town entry settled f%d (%d,%d) $007D=%d",
      H.frame, H.fieldX(), H.fieldY(), sw(0x007D)))
    H.screenshot("thamasa_town_entry")
  end),

  -- ---- 3. cross town to Strago's house door -----------------------------
  -- avoid the two magic-vignette tiles (35,15)/(25,12); optional side
  -- content this probe has no reason to trigger.
  crossDoor(29, 13, 349, 37, 24, "Strago house door 343(29,13)->349(37,24)",
    { avoid = { { 35, 15 }, { 25, 12 } } }),

  -- ---- 4. talk to Strago (obj $10) -> ride into the naming scene -------
  H.call(function()
    sceneStartFrame = H.frame
    H.log(string.format("[ot6] approaching Strago (obj $10) f%d", H.frame))
  end),
  H.chaseTalk(0x10, 20000, "talk Strago -> scene begins (STRAGO naming menu)",
    { done = menuUp }),
  H.call(function()
    H.log(string.format(
      "[ot6] STRAGO naming menu reached f%d (%d frames from talk) $008D=%d",
      H.frame, H.frame - sceneStartFrame, sw(0x008D)))
  end),

  -- ---- 5. commit both naming screens ------------------------------------
  commitName("thamasa_naming_strago"),
  commitName("thamasa_naming_relm"),

  -- ---- 6. ride the rest of the scene to control-return ------------------
  H.advanceStory(calm(30), 30000, { playBattles = "tactical" }),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(map(), 343, "control returned on Thamasa town map")
    H.assertEq(sw(0x008D), 1, "$008D set")
    H.log(string.format(
      "[ot6] SCENE END f%d map=%d (%d,%d) $008D=%d " ..
      "party[TERRA LOCKE CYAN SHADOW EDGAR SABIN CELES STRAGO RELM]=" ..
      "%d %d %d %d %d %d %d %d %d total frames from savestate: %d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x008D),
      H.readByte(0x1850) & 7, H.readByte(0x1851) & 7, H.readByte(0x1852) & 7,
      H.readByte(0x1853) & 7, H.readByte(0x1854) & 7, H.readByte(0x1855) & 7,
      H.readByte(0x1856) & 7, H.readByte(0x1857) & 7, H.readByte(0x1858) & 7,
      H.frame))
    H.screenshot("thamasa_scene_end")
  end),
}

H.run({ maxFrames = 150000 }, steps)
