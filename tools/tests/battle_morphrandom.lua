-- @suite savestate=fc_alcove slow
-- battle_morphrandom.lua -- a Morph the engine picks takes the 0-BP span
-- (#427).
--
-- kits.md, Terra: the boost buys Morph's duration, and only a real 3-BP pick
-- is permanent.  When the engine picks TERRA's command (Muddle, Charm, the
-- Colosseum: RandCharAction, which marks her OT6_UNCTL), RandMorph is always
-- valid (vanilla's gauge test is gone) and the pick buys nothing:
-- Ot6MorphTake drops any pending boost, so the morph is clocked at the 0-BP
-- speed and runs out after SPAN0 battle ticks, and Ot6ActionEnd charges
-- nothing for it.  (Mimic and Control never reach Cmd_03 as a character's
-- Morph: BattleCmdProp[$03] has neither GOGO nor MIMIC.)
--
-- Boots fc_alcove (TERRA L26 with Morph, LOCKE, SHADOW, EDGAR), walks onto
-- the continent into a random battle, and plays two arms, PICKS random
-- Morphs each (a battle that ends first is left and the arm goes on in the
-- next random battle):
--   plain  TERRA Muddled: each Morph she picks is clocked at the 0-BP
--          speed and lasts SPAN0 ticks;
--   stale  the same, with her pending boost held at 3 (and her bank at 5)
--          whenever she is not morphed: the engine's Morph still takes the
--          0-BP span, never the battle, and the bank pays nothing for it
--          (the stage stands off from her Morph's execution to its clock's
--          end, so what the engine did with the pending byte stands).
-- Declared unit-test expedients (tools/state_write_waivers.txt), because no
-- generated battle Muddles TERRA after Zozo: Muddle ($3EE5 bit 5) set on her
-- again whenever it clears, the party's HP put back to max every frame and
-- the monsters' HP to 30,000 (so the battle lasts for the picks), and, in
-- the stale arm, her pending boost and bank as above.  The others' windows
-- take A (a Fight).  The pick, the command and the morph are the engine's.
-- Old-ROM red (main's ROM: the engine's Morph does not morph) and mutants
-- (the 0-BP speed off by one; the engine's pick keeping its pending boost):
-- build/attempts/wt/v029-kits/r7/ (old ROM, and PACE_BURN 0-3 green) and r8/
-- (mutants).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/fc_alcove.mss.lua"

local TERRA, MORPH = 0x00, 0x03
local SPAN0, PICKS = 596, 2
local BANK, PEND = 0x3E9C, 0x3E9D

local seat, arm = nil, nil
local hold = false        -- a Morph of hers executing or running: the stale stage stands off
local battles = 0
local picks = {}          -- { f, unctl, pend, bank0, bank1 (after its ActionEnd), m0, t0, speed, t1 }
local function e() return seat * 2 end
local function ticks() return H.readByte(0x3A3E) | (H.readByte(0x3A3F) << 8) end
local function morphed() return (H.readByte(0x3EF9 + e()) & 0x08) ~= 0 end
local function alive() return (H.readByte(0x3EE4 + e()) & 0xC2) == 0 end

local function hooks()
  local take, ae = H.sym("Cmd_03"), H.sym("Ot6ActionEnd")   -- (Cmd_03: on any ROM)
  emu.addMemoryCallback(function()
    if arm == nil or seat == nil or (emu.getState()["cpu.y"] & 0xff) ~= e() then return end
    local p = { battle = battles, f = H.frame, unctl = H.readByte(0xED97), pend = H.readByte(PEND + e()), bank0 = H.readByte(BANK + e()) }
    picks[#picks + 1] = p
    hold = true
    H.log(string.format("[mrand] f%d %s: TERRA's Morph executes (OT6_UNCTL %02X, pending %d, bank %d)", H.frame,
      arm, p.unctl, p.pend, p.bank0))
  end, emu.callbackType.exec, take, take)
  emu.addMemoryCallback(function()
    local p = picks[#picks]
    if p == nil or p.bank1 ~= nil or (emu.getState()["cpu.x"] & 0xff) ~= e() or H.readByte(0x3A7C) ~= MORPH then return end
    p.ae = H.frame
  end, emu.callbackType.exec, ae, ae)
  local lastC = false
  emu.addEventCallback(function()
    if seat == nil or not H.battleActive() then lastC = false; return end
    local p = picks[#picks]
    if p ~= nil and p.ae ~= nil and p.bank1 == nil and H.frame > p.ae then p.bank1 = H.readByte(BANK + e()) end
    local c = H.readByte(0x3EE2) == e()
    if p ~= nil and p.m0 == nil and morphed() then p.m0 = H.frame end
    if c and not lastC and p ~= nil and p.t0 == nil then
      p.t0, p.speed = ticks(), H.readByte(0x3F32) | (H.readByte(0x3F33) << 8)
      H.log(string.format("[mrand] f%d tick %d: her clock starts, speed %d", H.frame, p.t0, p.speed))
    end
    if lastC and not c and p ~= nil and p.t0 ~= nil and p.t1 == nil then
      p.t1 = ticks()
      hold = false
      H.log(string.format("[mrand] f%d the clock ran out after %d ticks", H.frame, p.t1 - p.t0))
    end
    lastC = c
  end, emu.eventType.endFrame)
end

-- the stage, every frame of an arm (declared expedients, above)
local function stage(stale)
  if not H.battleActive() then return end
  if H.frame % 300 == 0 then
    local t = {}
    for m = 0, 5 do
      t[#t + 1] = string.format("%d:%d/%02X/%02X", m, H.readWord(0x3BFC + m * 2), H.readByte(0x3AA8 + m * 2),
        H.readByte(0x3EE4 + 8 + m * 2))
    end
    H.log(string.format("[mrand] f%d formation %04X monsters (slot:hp/present/status1) %s; TERRA status1 %02X/%02X",
      H.frame, H.readWord(0x11E0), table.concat(t, " "), H.readByte(0x3EE4 + e()), H.readByte(0x3EE5 + e())))
  end
  if not alive() then
    -- she fell anyway (one hit past her max): this battle is no use, so its
    -- monsters go to 1 HP and the others' Fights end it; the arm goes on in
    -- the next battle, after the walk's field care revives her
    for m = 0, 5 do
      if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 1 then
        H.writeWord(0x3BFC + m * 2, 1)
      end
    end
    return
  end
  if (H.readByte(0x3EE5 + e()) & 0x20) == 0 then
    H.writeByte(0x3EE5 + e(), H.readByte(0x3EE5 + e()) | 0x20)
  end
  for s = 0, 3 do
    local hp, mx = H.readWord(0x3BF4 + s * 2), H.readWord(0x3C1C + s * 2)
    if hp > 0 and hp < mx then H.writeWord(0x3BF4 + s * 2, mx) end
  end
  for m = 0, 5 do
    if (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) < 20000 then
      H.writeWord(0x3BFC + m * 2, 30000)
    end
  end
  if stale and not hold and not morphed() then
    H.writeByte(BANK + e(), 5)
    H.writeByte(PEND + e(), 3)
  end
end

-- a battle is up: TERRA's seat, and Morph in her list
local BATTLES = 8
local function enter()
  battles, hold = battles + 1, false
  H.assertEq(battles <= BATTLES, true, string.format("both arms within %d battles", BATTLES))
  seat = nil
  for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == TERRA then seat = s end end
  H.assertEq(seat ~= nil, true, "TERRA is in this battle")
  local has = false
  for r = 0, 3 do if H.readByte(0x202E + seat * 12 + r * 3) == MORPH then has = true end end
  H.assertEq(has, true, "TERRA's command list holds Morph (learned at Zozo)")
  H.log(string.format("[mrand] battle %d: formation %04X, TERRA seat %d", battles, H.readWord(0x11E0), seat))
end

local function playArm(name, stale)
  local from
  return H.seqStep({
    H.call(function() arm, from = name, #picks end),
    H.driveUntil(function()
      local n = 0
      for i = from + 1, #picks do
        local p = picks[i]
        if p.t1 ~= nil and not morphed() then n = n + 1 end
        -- a Morph that executed must morph her and start her clock
        if p.battle == battles and p.m0 == nil and H.frame - p.f > 600 and H.battleActive() then
          H.assertEq(false, true, string.format("%s: TERRA's Morph at f%d morphed her within 600 frames", name, p.f))
        end
        -- ...and her clock starts with it (an engine's Morph is never the battle-long one)
        if p.battle == battles and p.m0 ~= nil and p.t0 == nil and H.frame - p.m0 > 600 and H.battleActive() then
          H.assertEq(false, true, string.format("%s: TERRA's Morph at f%d is clocked within 600 frames", name, p.f))
        end
      end
      return n >= PICKS
    end, 240000, {
      -- a battle that ends first (an instant kill, a Broken body's death:
      -- HP alone does not hold it up) is left, and the arm goes on in the
      -- next random battle, up to BATTLES.  The pace starts once the party
      -- has the field again: a frame between battles with no battle loaded
      -- and no control yet sent it to wait for control while the next
      -- battle came up (build/attempts/wt/v029-narshe-route/morphrandom/:
      -- `timeout after 3000 frames waiting for morphrandom: control to
      -- pace`, a battle on screen); until then the A presses below page
      -- the victory text
      H.cond(function() return not H.battleLoadStarted() and H.hasControl() and H.tileAligned() end, {
        H.call(function() H.setPad({}) end),
        H.fcPace("morphrandom"),
        H.waitUntil(function() return H.battleActive() end, 1200, "the next battle is up", 5),
        H.call(enter),
      }, {}),
      H.call(function()
        stage(stale)
        H.setPad(H.frame % 8 < 4 and { a = true } or {})   -- the others' windows: Fight; dialogs: A
      end),
    }, string.format("%d random Morphs (arm %s)", PICKS, name)),
    H.call(function()
      H.setPad({})
      arm = nil
      local n = 0
      for i = from + 1, #picks do
        local p = picks[i]
        if p.t1 ~= nil then
          n = n + 1
          H.assertEq(p.unctl & H.readByte(0x3018 + e()) ~= 0, true, string.format("%s: Morph %d was the engine's pick (OT6_UNCTL)", name, n))
          H.assertEq(p.speed, 110, string.format("%s: Morph %d is clocked at the 0-BP speed", name, n))
          H.assertEq(p.t1 - p.t0, SPAN0, string.format("%s: Morph %d lasts the 0-BP span, in battle ticks", name, n))
          H.assertEq(p.bank1 ~= nil and p.bank1 >= p.bank0, true,
            string.format("%s: the bank paid nothing for Morph %d (%d -> %s)", name, n, p.bank0, tostring(p.bank1)))
        end
      end
      H.assertEq(n >= PICKS, true, string.format("%s: %d random Morphs ran their span", name, PICKS))
      H.log(string.format("[mrand] arm %s PASS: %d random Morphs, each clocked at the 0-BP span", name, n))
    end),
  })
end

H.run({ maxFrames = 300000 }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(hooks),
  H.fcAlcoveToBattle("morphrandom"),
  H.waitUntil(function() return H.battleActive() end, 1200, "the battle is up", 5),
  H.call(enter),
  playArm("plain", false),
  playArm("stale", true),
  H.call(function() H.log("[mrand] PASS: a Morph the engine picks takes the 0-BP span and costs nothing") end),
})
