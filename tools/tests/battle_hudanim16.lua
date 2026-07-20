-- battle_hudanim16: the under-enemy hud must never render while the
-- battlefield BG3 is in 16x16 tile mode.
--
-- THE BUG (the owner's residual v0.2 sighting, surviving both the fly-in
-- gate and the dialogue font-clobber veil): "junk showing up every once in
-- a while during battle, drawing over and around the enemies -- break
-- icons amongst other things that look like junk memory ... happening in
-- fights with no dialog too, just ordinary random battles."
--
-- MECHANISM (probe_junk16 / probe_bg3anim / probe_aurabolt).  Battle
-- animation inits flip the battlefield's $2105 shadow ($896F) to 16x16
-- BG3 tiles while an effect uses BG3 as its canvas or color-math mask
-- (InitAnimType btlgfx_main.asm:26304/:26348, circle families :47410/
-- :48362).  Vanilla clears the field map first and its $01EE fill is
-- priority-clear -- invisible under the battle bg -- but OT6's hud cells
-- are priority-set, and a 16x16 map cell renders at doubled size/position
-- pulling three neighbor tiles.  Any live hud line inside the effect's
-- scroll window becomes doubled break-icon blocks flanked by neighbor
-- junk.  A plain CURE in the map-96 Cirpius x3 pool (hud rows 5/8, both
-- inside the idle (0,0) window) showed it for 42 straight frames; Fire's
-- $51 phase (priority flag dropped) and plain Fights ($19, bg1-only) are
-- invisible, which is why the sighting was intermittent.  No dialogue, no
-- boss, no fly-in required.
--
-- THE FIX (Ot6BgHudFlush_ext): while $896F bit $40 is up, the flush veils
-- every live line with vanilla's $01EE fill -- the same veil entry/exit
-- effects and dialogue windows get -- and repaints the instant the mode
-- comes back.
--
-- THE GATE, frontier-gated on kolts_cave.mss (battle_flyin's fixture --
-- the natural pool IS the sighting's formation class): pace into the
-- Cirpius fight, let the entry finish, then run ~2 player turns with
-- TERRA CASTING (her spells carry the 16x16-with-priority anims) under a
-- per-frame watch:
--   * INVARIANT: on every mid-fight frame with $896F bit6 set and BG3 on
--     the battlefield main screen, no live hud line cell in vram holds a
--     painted OT6 glyph (attr $21 + claimed char).  Pre-fix this fails in
--     the first Cure window (424 flagged frames on the probe).
--   * POSITIVE CONTROLS: >= 24 such 16x16 frames actually sampled, at
--     least one with a live veiled line ($01EE at cur, proving the veil
--     painted rather than the lines being disabled); the dialogue latch
--     $64D5 stays 0 the whole run (this is the no-dialogue clause); the
--     hud is present before and after; glyphCanary at the end.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom
local DANGER = 0x1f6e
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CHARIX = 0x3ED9
local CMDTBL = 0x202E
local ST_SPELL, ST_TGT = 0x0e, 0x38

local function map() return H.mapId() & 0x1ff end

-- OT6-claimed glyph chars, read from rom (battle_flyin's technique)
local claimed = nil
local function claimedCharSet()
  local function findSig(sig)
    for base = 0x300000, 0x303FF0 do
      local hit = true
      for i = 1, 16 do
        if emu.read(base + i - 1, ROM) ~= sig[i] then hit = false break end
      end
      if hit then return base end
    end
    return nil
  end
  local bg = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                      0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(bg ~= nil, true, "OT6 bg glyph data found in rom")
  local set = { [0xbf] = true }
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do set[c] = true end
  for k = 1, 16 do set[emu.read(bg - 17 + k, ROM)] = true end
  return set
end

-- ------------------------------------------------------------- watcher --
local frames16, veiled16, violations, dlgSeen = 0, 0, 0, 0
local violShots = 0
local function watchFrame()
  if H.readByte(0x64d5) ~= 0 then dlgSeen = dlgSeen + 1 end
  if H.readByte(0x57be) ~= 0 then return end          -- entry/exit veil: not ours
  local m2105 = H.readByte(0x896f)
  local main = H.readByte(0x898d)
  if m2105 % 128 < 64 or (main % 8) < 4 then return end
  frames16 = frames16 + 1
  for s = 0, 5 do
    local cur = H.readWord(H.shadowLine(s))
    if cur ~= 0 then
      local lineVeiled = true
      for k = 0, 4 do
        local lo = emu.read((cur + k) * 2, VR)
        local hi = emu.read((cur + k) * 2 + 1, VR)
        if hi == 0x21 and claimed[lo] then
          violations = violations + 1
          if violations <= 6 then
            H.log(string.format(
              "VIOLATION: 16x16 frame (2105=%02x main=%02x) but hud line %d "
              .. "cell +%d at %04x holds painted glyph %02x", m2105, main, s,
              k, cur + k, lo))
          end
          if violShots < 3 then
            violShots = violShots + 1
            H.screenshot(string.format("hudanim16_viol%d", violShots))
          end
        end
        if not (hi == 0x01 and lo == 0xee) then lineVeiled = false end
      end
      if lineVeiled then veiled16 = veiled16 + 1 end
    end
  end
end

-- --------------------------------------------------------- menu driver --
-- TERRA casts her first spell every turn; everyone else Fights.  Command
-- cursor skips blank ($ff) rows.  12-frame cadence: hold 4, release 8.
local function bcmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local lastSt, lastActor, phase = -1, -1, 0
local function driveMenus()
  if H.readByte(MENU) == 0 then lastSt, lastActor, phase = -1, -1, 0 return nil end
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if st ~= lastSt or actor ~= lastActor then lastSt, lastActor, phase = st, actor, 0 end
  phase = phase + 1
  local step = math.floor((phase - 1) / 12) + 1
  if ((phase - 1) % 12) >= 4 then return nil end
  if H.readByte(CHARIX + actor*2) == 0x00 then
    if st == ST_SPELL or st == ST_TGT then return {"a"} end
    local downs, seen = nil, 0
    for i = 0, 3 do
      local c = bcmd(actor, i)
      if c == 0x02 then downs = seen end
      if c ~= 0xff then seen = seen + 1 end
    end
    if downs == nil then return {"a"} end
    if step <= downs then return {"down"} end
    return {"a"}
  end
  return {"a"}
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  -- pace the auto-detected lane until an encounter loads (battle_flyin's pacer)
  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        H.writeWord(DANGER, 0xff00)
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.call(function() claimed = claimedCharSet() end),

  -- let the entry (and its veil) finish; the hud must be up before the watch
  H.waitUntil(function()
    return H.readByte(0x57be) == 0 and H.fieldHudPresent()
  end, 1200, "entry done, hud painted", 5),

  -- ~2 player rounds under the per-frame watch
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return n >= 2600
    end, 3200, {
      H.call(function()
        watchFrame()
        local b = driveMenus()
        if b then H.setPad(b) else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "watched rounds")
  end)(),
  H.call(function() H.setPad({}) end),

  H.call(function()
    H.log(string.format("[hudanim16] frames16=%d veiled16=%d violations=%d dlgSeen=%d",
      frames16, veiled16, violations, dlgSeen))
    H.assertEq(dlgSeen, 0,
      "no dialogue window all run -- this is the no-dialogue reproduction")
    H.assertEq(frames16 >= 24, true,
      "sampled >= 24 mid-fight bg3-16x16 frames (got " .. frames16 ..
      ") -- else the invariant never ran")
    H.assertEq(violations, 0,
      "no hud cell rendered from a painted glyph during bg3-16x16 frames (" ..
      violations .. " violations)")
    H.assertEq(veiled16 >= 1, true,
      "at least one live line read veiled ($01EE) inside the window -- the " ..
      "veil painted, the lines were not merely disabled")
  end),

  -- the hud must come back once the effect ends
  H.waitUntil(function()
    return H.readByte(0x896f) % 128 < 64 and H.fieldHudPresent()
  end, 900, "hud repaints after the effect", 5),
  H.call(function()
    H.glyphCanary()
    H.screenshot("hudanim16_settled")
  end),
})
