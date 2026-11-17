-- @suite
-- battle_rejoin_reraise.lua -- a monster Reraise brings back starts fresh (#557), a mechanism case.
--
--   tools/tests/run.sh tools/tests/battle_rejoin_reraise.lua
--
-- battle_rejoin covers the bodies the AI restores (Cmd_24); this covers the other way back, Life on a monster
-- (ReraiseEffect's Life, the Life family's wound clear, _c2469c), which Ot6Revive renews.  No fight on the
-- tracked line has a monster raise another or itself by Life on cue (Madam's, Curley's and the magic urn's
-- Life spells are random picks in the World of Ruin), so this is a mechanism case with one declared write:
-- at the open of Baren Falls' battle 18 (battle_rejoin's route and driver) every Piranha slot is given Life 3
-- (status 4 bit 2, $3EF9).  The party's Fight breaks and kills one in a swing, the Reraise raises it, and the
-- raised body must be fresh: battle_rejoin's S and D (shields = max, not Broken, no hold, mark or pin; the
-- line never draws the broken shield before the next hit on it).
-- Precondition, asserted: a Piranha that died broken came back by its Reraise (below full HP: the AI's restore
-- is at full).
-- Mutants (build/attempts/wt/v049-prebroken/mut/): no_revive (Ot6Revive's dead test always misses) red at S
-- and D.
local H = dofile("tools/tests/lib/ot6.lua")

local DOOR = "build/states/train_done.mss.lua"
local PIRANHA = 0x0154
local SHADOWL, HOLD, HITBRK = 0x7EECF1, 0x7EEE4D, 0x7E3ECB
local STILLMARK, STILLHELD, UNDERPAINT, PINNING = 0x7EEF12, 0x7EEF13, 0x7EEF14, 0x7EEF15
local EMBLEM, GAUGE_ATTR, BROKEN_ATTR = 0x71, 0x21, 0x3D
local WANT_BROKEN, WANT_ALL = 2, 4

local function mapIdx() return H.readWord(0x1f64) & 0x3FF end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1e80 + (id >> 3)) >> (id & 7)) & 1 end

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
local last, died, back = {}, {}, {}    -- per slot: last line; state at death; the restored body's watch
local restored, brokenBack, failures = 0, 0, {}
local reraised, armed = 0, false
local function fail(msg)
  failures[#failures + 1] = msg
  H.log("[rejoin] FAIL " .. msg)
end

local function watchFrame()
  if not watching or done then return end
  for s = 0, 4 do
    if H.readWord(0x57C0 + s * 2) == PIRANHA then
      local l = line(s)
      if l ~= last[s] then H.log(string.format("[rejoin] f%d slot%d %s", H.frame, s, l)) end
      last[s] = l
      local h = hp(s)
      if h == 0 and not died[s] then
        died[s] = { f = H.frame, broken = brk(s) ~= 0 or select(1, shields(s)) == 0,
          life3 = H.readByte(0x3EF9 + E(s)) & 0x04 ~= 0 }
        H.log(string.format("[rejoin] f%d slot%d died %s", H.frame, s, died[s].broken and "BROKEN" or "unbroken"))
        back[s] = nil
      elseif h ~= 0 and died[s] then
        -- S: the frame it is restored
        local c, m = shields(s)
        local wasBroken = died[s].broken
        -- raised by Life (Reraise's Life leaves it a sliver of HP; the AI's restore is at full) or its Life 3
        -- bit spent since its death
        local raised = h < H.readWord(0x3C1C + E(s))
          or (died[s].life3 and H.readByte(0x3EF9 + E(s)) & 0x04 == 0)
        died[s] = nil
        if raised and wasBroken then reraised = reraised + 1 end
        if raised then H.log(string.format("[rejoin] f%d slot%d came back by its Reraise", H.frame, s)) end
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
          if reraised >= 1 then done = true end
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
  if H.readWord(0x57C0 + 10) ~= 0xFFFF and (H.readByte(0x3AA8 + 10) & 1) == 1 and restored > 0 then
    if not done then H.log(string.format("[rejoin] f%d Rizopas surfaced: the school is over", H.frame)) end
    done = true
  end
end

-- ------------------------------------------------------------ the route --
-- the walk and the jump: gen_sabin_falls's own, cut to what the school needs
local function inBattle()
  for i = 0, 3 do
    local v = H.readWord(0x3bf4 + i * 2)
    if v == 0xFFFF or v == 0 then
    elseif v < 10000 then return true
    else return false end
  end
  return false
end

local F = nil
local function ride(dir, pred, what, budget, fight)
  local phase = 0
  return H.driveUntil(pred, budget or 30000, {
    H.call(function()
      phase = (phase + 1) % 8
      if inBattle() or H.battleLoadStarted() then
        if fight then
          watching = true
          if not armed and H.battleActive() then
            armed = true
            -- the declared write: Life 3 on every Piranha slot (status 4 bit 2)
            for s = 0, 4 do
              if H.readWord(0x57C0 + s * 2) == PIRANHA then
                H.writeByte(0x7E3EF9 + E(s), H.readByte(0x3EF9 + E(s)) | 0x04)
              end
            end
            H.log(string.format("[rejoin] f%d Life 3 written on every Piranha slot (the declared write)", H.frame))
          end
          watchFrame()
          if not F then F = H.newFightDriver("rejoin", { tactical = false, boost = true, bank = 99,
            items = true, healPercent = 40 }) end
          F.frame()
        else
          H.setPad({})
        end
        return
      end
      if H.dialogWaiting() then H.setPad(phase < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      H.setPad(dir and { [dir] = true } or {})
    end),
  }, what)
end

local function settle(toMap, what)
  local phase = 0
  return H.driveUntil(function()
    return mapIdx() == toMap and H.hasControl() and H.tileAligned() and bright() >= 15
  end, 5000, {
    H.call(function()
      phase = (phase + 1) % 8
      H.setPad(H.dialogWaiting() and phase < 4 and { "a" } or {})
    end),
  }, what)
end

H.run({ maxFrames = 60000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  H.call(function()
    H.assertEq(H.worldMode(), true, "boot on the World of Balance (train_done)")
    H.assertEq(sw(0x3B), 1, "$003B set: the train is behind us (gen_sabin_train)")
    H.assertEq(sw(0x3C), 0, "$003C clear: Baren Falls not yet played")
  end),
  H.worldNavTo(185, 93, { maxFrames = 20000, playBattles = "tactical",
    arrive = function() return not H.worldMode() end }),
  settle(166, "cave 166"),
  H.navTo(7, 5, { maxFrames = 6000, playBattles = "tactical" }),
  ride("up", function() return mapIdx() == 155 end, "-> 155", 3000),
  settle(155, "overlook 155"),
  H.navTo(10, 5, { maxFrames = 6000, playBattles = "tactical" }),
  ride("up", function() return mapIdx() == 156 end, "-> 156", 3000),
  settle(156, "falls top 156"),
  ride("up", function() return sw(0x3C) == 1 and H.hasControl() and H.tileAligned() end,
    "arrival scene ($003C)", 15000),
  H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
  ride("up", function() return done end, "the jump and the school", 30000, true),
  H.call(function()
    H.log(string.format("[rejoin] %d Piranhas restored, %d of them had died broken, %d raised by Reraise after a " ..
      "broken death; %d failure(s)", restored, brokenBack, reraised, #failures))
    if #failures > 0 then error(failures[1] .. (#failures > 1 and string.format(" (+%d more)", #failures - 1) or ""), 0) end
    if reraised < 1 then
      error("precondition: no Piranha that died broken came back by its Reraise", 0)
    end
  end),
})
