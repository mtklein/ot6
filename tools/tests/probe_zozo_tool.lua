-- probe_zozo_tool.lua -- does EDGAR's Tool decide the Zozo climb?
--
-- The climb's random encounters were losing, and the reason on the record
-- was that Zozo's four species carry an Ot6ShieldTbl row with two shields
-- and no class byte at all (ff6/src/battle/ot6_hud.asm:2086-2097), so
-- nothing a weapon or an ability does ever takes a shield off.  The block
-- comment over those four rows says the answer is not a weapon: "the answer
-- is the tool rather than the A button" (:2084-2085), meaning the vanilla
-- poison weakness all four already carry (monster_prop.dat +25 = $08) and
-- EDGAR's Bio Blaster, item $a4 -> attack $7d, element $08, all enemies
-- (ot6_break.asm:203-204, :279-281; battle_main.asm:6577).  Until
-- opts.tool, newFightDriver could only ever reach for AutoCrossbow.
--
-- This measures that claim rather than repeating it.  One boot of
-- zozo_arrival, a care stop so HP is not the variable, a checkpoint, then
-- the SAME pacing walk twice with the SAME input -- the emulator is
-- deterministic, so both halves draw the same formation on the same frame
-- off the same battle seed -- and the only difference between them is which
-- Tool the driver names.  It reports, per half: the formation, the shield
-- counts frame by frame, monster HP, party HP, and how the fight ended.
--
-- It asserts nothing about which half wins.  A probe that demanded the
-- answer it expected would agree with itself; the numbers are the output.
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted()
end

local function monHp(i) return H.readWord(0x3BFC + i * 2) end
local function monShields(i) return H.readByte(0x3E40 + i * 2) end
local function monPresent(i) return H.readByte(0x3AA8 + i * 2) % 2 == 1 end
local function partyLine()
  local p = {}
  for e = 0, 3 do
    p[#p + 1] = string.format("%d/%d", H.readWord(0x3BF4 + e * 2),
      H.readWord(0x3C1C + e * 2))
  end
  return table.concat(p, " ")
end
local function monsterLine()
  local m = {}
  for i = 0, 5 do
    if monPresent(i) then
      m[#m + 1] = string.format("$%04X hp=%d sh=%d",
        H.readWord(0x57C0 + i * 2), monHp(i), monShields(i))
    end
  end
  return table.concat(m, " | ")
end
local function shieldSum()
  local s = 0
  for i = 0, 5 do if monPresent(i) then s = s + monShields(i) end end
  return s
end
local function partyAllZero()
  for e = 0, 3 do
    if H.readWord(0x3BF4 + e * 2) ~= 0 then return false end
  end
  return true
end

local RESULT = {}
local blob = nil

-- Wander the street until a battle fires, fight it, and stop.  The walk is a
-- pure function of the tile, so the two halves present identical input to
-- the engine and draw the same encounter.
local DIRS = { "left", "right", "up", "down" }
local function half(name, tool)
  local hb, battN, done, minShield, startShield = 0, 0, nil, nil, nil
  local dirI, lastX, lastY = 1, -1, -1
  local F = H.newFightDriver(name, { tactical = true, boost = true, bank = 3,
    items = true, healPercent = 60, cadence = 12, tool = tool })
  local f0 = nil
  -- Record at the moment the half ends, not on a later frame: driveUntil
  -- tests its pred BEFORE ticking the body, so once `done` is set the body
  -- never runs again.
  local function finish(why)
    done = why
    RESULT[name] = string.format(
      "%s: %s after %d frames; shields %s -> %s; party [%s]; %s",
      name, done, f0 and (H.frame - f0) or -1,
      tostring(startShield), tostring(minShield), partyLine(), monsterLine())
    H.log("[result] " .. RESULT[name])
  end
  -- One H.call, not two: driveUntil runs its step list as a SEQUENCE, one
  -- step per frame, so a second step would only see every other frame and
  -- the pad would be set on half of them.
  return H.driveUntil(function() return done ~= nil end, 40000, {
    H.call(function()
      hb = hb + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 3 then
        if f0 == nil then
          f0 = H.frame
          local w = H.formationWords()
          H.log(string.format("[%s] battle up f%d (%04X %04X %04X %04X %04X %04X)",
            name, H.frame, w[1], w[2], w[3], w[4], w[5], w[6]))
          H.log(string.format("[%s] opening: party [%s] vs %s",
            name, partyLine(), monsterLine()))
          startShield = shieldSum()
          minShield = startShield
        end
        local s = shieldSum()
        if s < minShield then
          minShield = s
          H.log(string.format("[%s] f+%d shields %d -> %d: %s", name,
            H.frame - f0, startShield, s, monsterLine()))
        end
        if (H.frame - f0) % 600 == 0 then
          H.log(string.format("[%s] f+%d party [%s] vs %s", name,
            H.frame - f0, partyLine(), monsterLine()))
        end
        F.frame()
        return
      end
      if f0 ~= nil then
        -- the battle module has let go: either the party won or it is dead
        if partyAllZero() and not H.hasControl() then
          if hb % 600 == 0 then
            H.log(string.format("[%s] f+%d all four battle-HP words 0, no control",
              name, H.frame - f0))
          end
          if (H.frame - f0) > 3000 then
            finish("WIPED")
          end
          H.setPad({})
          return
        end
        if settled() then
          finish("WON")
          F.idle()
          H.setPad({})
          return
        end
        F.idle()
        H.setPad(hb % 8 < 4 and { "a" } or {})
        return
      end
      F.idle()
      if H.dialogWaiting() then H.setPad(hb % 8 < 4 and { "a" } or {}); return end
      if not H.hasControl() then H.setPad({}); return end
      if not H.tileAligned() then return end
      if hb > 30000 then finish("NO ENCOUNTER"); H.setPad({}); return end
      local x, y = H.fieldX(), H.fieldY()
      if x == lastX and y == lastY then
        dirI = dirI % #DIRS + 1              -- refused or blocked: try another
      end
      lastX, lastY = x, y
      for k = 0, #DIRS - 1 do
        local mv = DIRS[(dirI - 1 + k) % #DIRS + 1]
        if H.canStep(x, y, mv) then
          dirI = (dirI - 1 + k) % #DIRS + 1
          H.setPad({ [H.movePress(mv)] = true })
          return
        end
      end
      H.setPad({})
    end),
  }, name)
end

H.run({ maxFrames = 200000 }, {
  H.loadState("build/states/zozo_arrival.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 221, "booted on the Zozo street (map 221)")
    H.assertEq(H.invCountOf(H.BIO_BLASTER) > 0, true, "Bio Blaster in the bag")
    H.assertEq(H.invCountOf(H.AUTOCROSSBOW) > 0, true, "AutoCrossbow in the bag")
  end),
  H.fieldCare({ tag = "care before the probe", threshold = 0.95 }),
  H.waitUntil(settled, 2400, "settled after the care stop", 5),
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "probe checkpoint")
        blob = req.blob
        H.log(string.format("[probe] checkpoint at (%d,%d), party [%s]",
          H.fieldX(), H.fieldY(), partyLine()))
      end),
    })
  end)(),

  half("autocrossbow", H.AUTOCROSSBOW),

  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestLoadState(blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(req, "reload for the second half") end),
      H.waitFrames(90),
    })
  end)(),

  half("bioblaster", H.BIO_BLASTER),

  H.call(function()
    H.log("[probe] ---- both halves ----")
    H.log("[probe] " .. tostring(RESULT["autocrossbow"]))
    H.log("[probe] " .. tostring(RESULT["bioblaster"]))
  end),
})
