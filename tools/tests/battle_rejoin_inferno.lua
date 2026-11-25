-- @suite slow
-- battle_rejoin_inferno.lua -- an arm Inferno brings back starts fresh (#557), the second battle of the kind.
--
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-kt-factory-v1 tools/tests/run.sh tools/tests/battle_rejoin_inferno.lua
--
-- battle_rejoin plays the Piranhas; this is the same rule on another script that restores the dead.  Inferno's
-- arms (Rough, Striker) answer their own death with restore_monsters (Cmd_24's MonsterDeath_00, instant, full
-- HP), hide, and come back down on a timer.  A body that died broken came back with 0 shields and its break
-- timer running, and Ot6Tick counted it on while it was hidden.  Ot6Arrive renews it at the restore.
--
-- Continues wor-kt-factory-v1 (party 3: CYAN, SHADOW, SABIN, GOGO beside Inferno), as battle_shadowpin_edges
-- does, arms the party against the three (H.absorbSafeArms), and walks onto Inferno's trigger (event battle
-- 114).  The party plays it with the lib's fight driver through the real menus.  For every arm restored after
-- dying broken: its shields = max, OT6_BROKEN_TICKS 0, no hold, breaking-hit mark or mark, the break stays off
-- until it is hit, and its shield line never draws the broken shield before that hit (battle_rejoin's S and D).
-- Precondition, asserted: an arm died broken and was restored before the battle ended.  DECLARED SYNTHETIC SETUP
-- (tools/state_write_waivers.txt): until an arm has died broken, each living, unbroken arm's gauge is staged to 1,
-- so its first keyed hit breaks it and the party's damage does not kill it unbroken first.  On the area-dressed
-- line's draw (7b913eb1's gate) the arms died unbroken six times and the party wiped before one died broken
-- (suites/battle_rejoin_inferno-gate13.log: "slot3 died unbroken" x4, "slot1 died unbroken" x2, then GAME OVER);
-- the restore, its shields, its break state and its line are the ROM's and are read, never written, and nothing is
-- staged once an arm has died broken.
-- Mutants (build/attempts/wt/v049-prebroken/mut/): no_arrive red.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local CYAN, SHADOW, SABIN, GOGO = 2, 3, 5, 12
local INFERNO, ROUGH, STRIKER = 0x10C, 0x141, 0x142
local INFERNO_TILE = { 31, 18 }
local WATCHED = { [ROUGH] = true, [STRIKER] = true }
local SHADOWL, HOLD, HITBRK = 0x7EECF1, 0x7EEE4D, 0x7E3ECB
local STILLMARK, STILLHELD, UNDERPAINT, PINNING = 0x7EEF12, 0x7EEF13, 0x7EEF14, 0x7EEF15
local EMBLEM, GAUGE_ATTR, BROKEN_ATTR = 0x71, 0x21, 0x3D
local WANT_BROKEN = 1

-- ------------------------------------------------------------- the watch --
local function E(s) return 8 + s * 2 end
local function hp(s) return H.readWord(0x3BF4 + E(s)) end
local function shields(s) return H.readByte(0x3E38 + E(s)), H.readByte(0x3E39 + E(s)) end
local function brk(s) return H.readByte(0x3E88 + E(s)) end
local function bitOn(a, s) return (H.readByte(a) >> s) & 1 == 1 end
local function lead(s)
  local cur = H.readWord(SHADOWL + s * 14)
  if cur == 0 then return nil end
  return emu.readWord((cur - 1) * 2, emu.memType.snesVideoRam)
end
local function line(s)
  local c, m = shields(s)
  local l = lead(s)
  return string.format("hp=%d st=%02X sh=%d/%d brk=%d hold=%d hitbrk=%d marks=%d%d%d%d lead=%s", hp(s),
    H.readByte(0x3EE4 + E(s)), c, m, brk(s), bitOn(HOLD, s) and 1 or 0, bitOn(HITBRK, s) and 1 or 0,
    bitOn(STILLMARK, s) and 1 or 0, bitOn(STILLHELD, s) and 1 or 0, bitOn(UNDERPAINT, s) and 1 or 0,
    bitOn(PINNING, s) and 1 or 0, l and string.format("%04X", l) or "-")
end

local watching, done = false, false
local stagedOff = rawget(_G, "REJOIN_NO_STAGE") == true   -- (a lab's global: the staging off, the negative)
local last, died, back = {}, {}, {}    -- per slot: last line; state at death; the restored body's watch
local restored, brokenBack, failures = 0, 0, {}
local function fail(msg)
  failures[#failures + 1] = msg
  H.log("[rejoin] FAIL " .. msg)
end

local function watchFrame()
  if not watching or done then return end
  for s = 0, 5 do
    if WATCHED[H.readWord(0x57C0 + s * 2)] then
      local l = line(s)
      if l ~= last[s] then H.log(string.format("[rejoin] f%d slot%d %s", H.frame, s, l)) end
      last[s] = l
      local h = hp(s)
      -- the DECLARED staging (header): until an arm has died broken, a living, unbroken arm outside a restored
      -- body's window has its gauge staged to 1, so its first keyed hit breaks it and its death lands broken
      if not stagedOff and h > 0 and not died[s] and back[s] == nil and brk(s) == 0 and select(1, shields(s)) > 1 then
        H.writeByte(0x3E38 + E(s), 1)
        H.log(string.format("[rejoin] f%d slot%d gauge staged to 1 (no arm has died broken yet)", H.frame, s))
      end
      if h == 0 and not died[s] then
        died[s] = { f = H.frame, broken = brk(s) ~= 0 or select(1, shields(s)) == 0 }
        if died[s].broken then stagedOff = true end
        H.log(string.format("[rejoin] f%d slot%d died %s", H.frame, s, died[s].broken and "BROKEN" or "unbroken"))
        back[s] = nil
      elseif h ~= 0 and died[s] then
        -- S: the frame it is restored
        local c, m = shields(s)
        local wasBroken = died[s].broken
        died[s] = nil
        restored = restored + 1
        if wasBroken then brokenBack = brokenBack + 1 end
        H.log(string.format("[rejoin] f%d slot%d RESTORED (died %s): %s", H.frame, s,
          wasBroken and "broken" or "unbroken", l))
        if c ~= m or m == 0 then fail(string.format("f%d slot%d restored with shields %d/%d", H.frame, s, c, m)) end
        if brk(s) ~= 0 then fail(string.format("f%d slot%d restored Broken (OT6_BROKEN_TICKS %d)", H.frame, s, brk(s))) end
        if bitOn(HOLD, s) or bitOn(HITBRK, s) then
          fail(string.format("f%d slot%d restored held or marked as broken (%s)", H.frame, s, l))
        end
        if bitOn(STILLMARK, s) or bitOn(STILLHELD, s) or bitOn(UNDERPAINT, s) or bitOn(PINNING, s) then
          fail(string.format("f%d slot%d restored carrying a mark (%s)", H.frame, s, l))
        end
        back[s] = { f = H.frame, hp = h, emblem = 0, sh = c, broken = wasBroken }
      elseif back[s] then
        local b = back[s]
        local c = shields(s)
        if h ~= b.hp or c ~= b.sh then
          -- something hit it: the restored body's own window is over
          H.log(string.format("[rejoin] f%d slot%d first hit since restore (%d frames): %s", H.frame, s,
            H.frame - b.f, l))
          if b.emblem == 0 and H.readByte(0x3EE4 + E(s)) & 0x80 == 0 then
            fail(string.format("slot%d restored at f%d: its line never drew the emblem before the next hit", s, b.f))
          end
          back[s] = nil
          if brokenBack >= WANT_BROKEN then done = true end
        else
          -- S: no break it never took
          if brk(s) ~= 0 and not b.brkSeen then
            b.brkSeen = true
            fail(string.format("f%d slot%d (restored f%d) is Broken with no hit on it", H.frame, s, b.f))
          end
          -- D: what the line draws
          local w = H.readByte(0x3EE4 + E(s)) & 0x80 == 0 and lead(s) or nil
          if w then
            if (w >> 8) == BROKEN_ATTR and not b.drawnBroken then
              b.drawnBroken = true
              fail(string.format("f%d slot%d (restored f%d) draws the broken shield (lead $%04X)", H.frame, s,
                b.f, w))
              H.screenshot(string.format("rejoin_broken_slot%d", s))
            elseif w == (GAUGE_ATTR << 8 | EMBLEM) then
              if b.emblem == 0 then
                H.log(string.format("[rejoin] f%d slot%d draws the emblem, %d frames after its restore", H.frame,
                  s, H.frame - b.f))
              end
              b.emblem = b.emblem + 1
            end
          end
        end
      end
    end
  end
end

local F = nil
H.run({ maxFrames = 400000 }, {
  H.bootCheckpoint("wor-kt-factory-v1"),
  H.call(function()
    H.assertEq(H.activeParty(), 3, "party 3 walks (gen_wor_kt_factory left it on the factory's save point)")
    for _, c in ipairs({ CYAN, SHADOW, SABIN, GOGO }) do
      H.assertEq(H.readByte(0x1850 + c) & 7, 3, string.format("%s is in party 3", H.SPLIT_NAMES[c]))
    end
  end),
  H.splitBegin({ shares = { [1] = 1, [2] = 1, [3] = 2 } }),
  H.absorbSafeArms(nil, { INFERNO, STRIKER, ROUGH }, { tag = "arms for Inferno" }),
  H.fieldCare({ threshold = 1.0, tag = "before Inferno" }),
  H.navTo(INFERNO_TILE[1], INFERNO_TILE[2], { maxFrames = 6000, playBattles = "tactical", fight = {},
    spare = { INFERNO },
    arrive = function()
      return (H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }))
        or (H.fieldX() == INFERNO_TILE[1] and H.fieldY() == INFERNO_TILE[2])
    end }),
  H.waitUntil(function() return H.battleLoadStarted() and H.formationHas({ [INFERNO] = true }) end, 3000,
    "Inferno's battle"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 2),
  H.call(function()
    watching = true
    F = H.newFightDriver("rejoin", { tactical = true, boost = true, items = true, healPercent = 40,
      focus = { { species = ROUGH }, { species = STRIKER }, { species = INFERNO } } })
  end),
  H.driveUntil(function() return done or not H.battleActive() end, 150000, {
    H.call(function()
      watchFrame()
      F.frame()
    end),
  }, "Inferno, until an arm comes back from a broken death"),
  H.call(function()
    H.log(string.format("[rejoin] %d arm(s) restored, %d of them had died broken; %d failure(s)", restored,
      brokenBack, #failures))
    if #failures > 0 then error(failures[1] .. (#failures > 1 and string.format(" (+%d more)", #failures - 1) or ""), 0) end
    if brokenBack < WANT_BROKEN then
      error(string.format("precondition: no arm died broken and came back before the battle ended (%d restored)",
        restored), 0)
    end
  end),
})
