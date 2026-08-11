-- @suite slow
-- hud_stability: the under-monster HUD must be rock-solid across TIME.
-- single-frame snapshots can pass while the HUD strobes (it happened);
-- this test watches the actual cell words frame by frame.
--   1. both guards' lines present after settle
--   2. 600 idle frames: the visible cell set never changes at all
--   3. an attack may contest BG3, but within 120 frames of the action
--      landing the HUD is back and stays put for 300 more frames
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local GLYPH = {[0x65]=1,[0x66]=1,[0x67]=1,[0x69]=1,[0x6a]=1,[0x6b]=1,[0x71]=1,
               [0xbf]=1,[0xeb]=1,[0xec]=1,[0xed]=1,[0x64]=1,[0xef]=1,
               [0xfb]=1,[0xfc]=1,[0xfd]=1}
local function cellset()
  local vr = emu.memType.snesVideoRam
  local reg = H.readByte(0x897b)
  local base = ((reg - (reg % 4)) * 256) * 2
  local t = {}
  for off = 0, 0x7FE, 2 do
    local lo = emu.read(base+off, vr)
    if emu.read(base+off+1, vr) == 0x21 and GLYPH[lo] then
      t[#t+1] = string.format("%04x:%02x", (base+off)//2, lo)
    end
  end
  return table.concat(t, " ")
end
local function lineCount(set)
  -- distinct map rows represented in the cell set
  local rows, n = {}, 0
  for addr in set:gmatch("(%x+):") do
    local row = math.floor(tonumber(addr, 16) / 32)
    if not rows[row] then rows[row] = true; n = n + 1 end
  end
  return n
end
local baseline, changes = nil, 0
local actorSlot, bpBefore
local function stableWatch(tag, nframes)
  local count = 0
  return H.waitUntil(function()
    count = count + 1
    local now = cellset()
    if now ~= baseline then
      changes = changes + 1
      if changes <= 8 then
        H.log(string.format("%s CHANGE f%d: %s", tag, H.frame,
          now == "" and "(NONE)" or now))
        if changes <= 3 then H.screenshot(string.format("%s_chg%d", tag, changes)) end
      end
      baseline = now
    end
    return count >= nframes
  end, nframes + 120, tag, 1)
end
H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  -- issue #75: this call used to pin both guards' HP to 500 ("fight
  -- longevity").  The pin bought nothing: during the idle watch the party
  -- takes no action (no input is pressed), so nothing can damage a guard,
  -- and the attack round below is ONE beam into shielded guards -- which
  -- battle_boost measured cannot end the fight even twice over (shielded
  -- damage is halved).  Enemy damage lands on party HP, which this test
  -- never asserts on.
  H.call(function()
    baseline = cellset()
    H.log("idle cells: " .. baseline)
    H.assertEq(lineCount(baseline) >= 2, true, "both guards' hud lines present")
    changes = 0
  end),
  stableWatch("idle", 600),
  H.call(function()
    H.assertEq(changes, 0, "idle hud perfectly stable for 600 frames")
  end),
  -- one attack round: BG3 is contested during the effect, then must
  -- heal.  Issue #75: this used to berserk the whole party ($3EE5 |= $10,
  -- forced menu-less auto-actions) and un-berserk after -- a status write
  -- both ways.  Now ONE beam is fired through the live menu, driven BY
  -- MENU STATE ($7BC2) -- battle_boost's measured driver, lifted whole:
  -- a fixed button sequence lands its downs in whatever window holds the
  -- cursor, so every press is chosen from the state byte.  The action is
  -- the ROW-2 BEAM, not the no-damage Heal Force the burn-down plan
  -- suggested -- battle_boost measured that dead end on this same fixture
  -- (the v0.8 wallet prices Heal Force out of the opening MP; A is
  -- refused forever).  A beam is exactly the effect art that contests
  -- BG3, which is what this phase exists to sample, and one beam into a
  -- shielded guard cannot end the fight.  Any OTHER ready character
  -- defers focus with X (vanilla's own turn-cycling key), so exactly one
  -- action ever fires; "lands" is the actor's bp moving (Ot6ActionEnd's
  -- +1 regen on an unboosted action).
  (function()
    local mf, downs = 0, 0
    return H.driveUntil(function()
      return actorSlot ~= nil
        and H.readByte(0x3e9c + actorSlot*2) ~= bpBefore
    end, 12000, {
      H.call(function()
        if H.readByte(0x7bca) == 0 then mf, downs = 0, 0; H.setPad({}); return end
        local act = H.readByte(0x62ca)
        if actorSlot == nil then
          actorSlot = act
          bpBefore = H.readByte(0x3e9c + act*2)
          H.log("firing one real beam from the first active slot: " .. act)
        end
        if H.readByte(0x3e9c + actorSlot*2) ~= bpBefore then
          H.setPad({}); return
        end
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local st = H.readByte(0x7bc2)
        local btn
        if act ~= actorSlot then
          btn = st == 0x05 and "x" or "b"   -- defer focus; back out first
        elseif st == 0x05 then btn = "a"    -- open the magitek list
        elseif st == 0x2a then
          if downs < 2 then
            if (mf - 1) % 8 == 0 then downs = downs + 1 end
            btn = "down"
          else btn = "a" end                -- the row-2 beam
        elseif st == 0x38 then btn = "a"    -- confirm the default target
        elseif st == 0x01 then H.setPad({}); return
        else btn = "b" end
        H.setPad({ [btn] = true })
      end),
    }, "one real beam lands")
  end)(),
  H.waitFrames(120),   -- recovery window
  -- an instantaneous check raced the queue: submitting cancels no
  -- already-queued animation, so effect art could still land between a
  -- one-shot "hud is back" sample and the baseline.  require the settled
  -- state -- no animation script, bg3 in 8x8, hud painted -- to hold for
  -- 60 CONSECUTIVE frames before baselining.
  (function()
    local calm = 0
    return H.waitUntil(function()
      local ok = H.readByte(0x57bf) == 0
        and H.readByte(0x896f) % 128 < 64
        and H.fieldHudPresent()
      calm = ok and calm + 1 or 0
      return calm >= 60
    end, 2400, "queue drained, bg3 8x8, hud repainted, 60 frames calm", 1)
  end)(),
  H.call(function()
    baseline = cellset()
    H.log("post-attack cells: " .. baseline)
    H.assertEq(lineCount(baseline) >= 2, true, "hud recovered after the attack")
    changes = 0
  end),
  stableWatch("post-attack", 300),
  H.call(function()
    H.assertEq(changes, 0, "hud stable after recovery")
  end),
})
