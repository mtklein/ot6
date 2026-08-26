-- @suite slow
-- battle_dmgnum: OT6 must not write into vanilla's damage-numeral vram.

-- The invariant checked, while a boost is pending and damage numbers are
-- flying:
--   * oam entries 96-99 (the retired boost-mark entries) stay parked, and
--   * no oam entry ever points at a tile in the numeral block 192-223
--     wearing OT6's palette-3/priority-3 attribute.

-- Negative control, so this cannot pass because boost feedback is gone
-- altogether: the party-window pip cell must still show the arrow cluster
-- while the boost is pending.
-- Positive controls: a boost was pending, and damage numerals fired,
-- during the sampled window.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"

local NUM_LO, NUM_HI = 192, 223       -- vram $2c00-$2dff as obj tile ids
local actor
local markFrames, pendFrames, arrowFrames, frames = 0, 0, 0, 0
local badMark, badTile = nil, nil
local numerals = 0
local numRef

local function watchNumerals()
  -- w7e6316 is the "damage numeral graphics update" enable: set nonzero
  -- by GfxCmd_0b, consumed (stz) by the vram copy at btlgfx_main.asm:1019
  numRef = emu.addMemoryCallback(function(addr, value)
    if value ~= 0 then numerals = numerals + 1 end
  end, emu.callbackType.write, 0x7e6316, 0x7e6316)
end

local function sample()
  frames = frames + 1
  if H.readByte(0x3e9d + actor*2) > 0 then pendFrames = pendFrames + 1 end

  -- the retired mark entries must stay parked (y = $e0)
  for slot = 0, 3 do
    local o = 0x0300 + (96 + slot) * 4
    if H.readByte(o + 1) < 0xe0 then
      markFrames = markFrames + 1
      if not badMark then
        badMark = string.format(
          "f%d entry %d live: tile %02x attr %02x y %02x (pend=%d)",
          frames, 96 + slot, H.readByte(o+2), H.readByte(o+3),
          H.readByte(o+1), H.readByte(0x3e9d + actor*2))
      end
    end
  end

  -- nobody may point an OT6-attributed sprite into the numeral block
  for e = 0, 127 do
    local o = 0x0300 + e*4
    if H.readByte(o+1) < 0xe0 then
      local tile = H.readByte(o+2) + ((H.readByte(o+3) & 0x01) << 8)
      if tile >= NUM_LO and tile <= NUM_HI and H.readByte(o+3) == 0x36
         and not badTile then
        badTile = string.format("f%d entry %d tile %d attr 36", frames, e, tile)
      end
    end
  end

  -- negative control: boost feedback still visible in the party window
  local reg = H.readByte(0x897f)
  local base = ((reg - (reg % 4)) * 256) * 2
  for r = 0, 3 do
    if H.readByte(0x64d6 + r) == actor then
      for _, band in ipairs({ 1 + r*2, 9 + r*2 }) do
        local c = emu.readWord(base + band*0x40 + 40,
                               emu.memType.snesVideoRam) & 0xff
        if c == 0x68 or c == 0x6c or c == 0x6d then
          arrowFrames = arrowFrames + 1
        end
      end
    end
  end
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  H.call(function() watchNumerals() end),
  (function()
    local mf, downs = 0, 0
    return H.driveUntil(function()
      if H.readByte(0x7bca) == 0 then return false end
      local act = H.readByte(0x62ca)
      if actor == nil then
        actor = act & 3
        H.log("banking bp on the first active slot: " .. actor)
      end
      return (act & 3) == actor and H.readByte(0x3e9c + actor*2) >= 3
    end, 12000, {
      H.call(function()
        if H.readByte(0x7bca) == 0 then mf, downs = 0, 0; H.setPad({}); return end
        local act = H.readByte(0x62ca) & 3
        if actor ~= nil and act == actor
           and H.readByte(0x3e9c + actor*2) >= 3 then
          H.setPad({}); return
        end
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local st = H.readByte(0x7bc2)
        local btn
        if actor ~= nil and act ~= actor then
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
    }, "bank 3 bp by real beam turns")
  end)(),
  H.call(function()
    H.assertEq(H.readByte(0x3e9c + actor*2), 3,
      "3 bp banked by real turns (1 open + 2 regen)")
  end),
  H.driveUntil(function()
    return H.readByte(0x3e9d + actor*2) >= 3
  end, 900, {
    H.pressButtons({ "r" }, 6), H.waitFrames(20),
  }, "boost armed to 3"),
  H.call(function()
    H.assertEq(H.readByte(0x3e9d + actor*2), 3, "3 bp pending (marks would draw)")
  end),
  -- hold the boost up for a while, sampling, before spending it
  H.waitUntil(function() sample(); return frames >= 120 end, 300,
    "boost held and sampled", 1),
  H.driveUntil(function()
    sample()
    return frames >= 2400
  end, 30000, {
    H.call(function()
      -- re-arm only if the pending boost drops, which it should not because
      -- no action is ever submitted, so that pendFrames cannot starve
      if H.readByte(0x7bca) ~= 0
         and H.readByte(0x3e9d + (H.readByte(0x62ca) & 3)*2) == 0 then
        H.setPad({ "r" })
      else H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() sample(); H.setPad({}) end),
    H.waitFrames(12),
  }, "battle with damage numerals sampled"),
  H.call(function()
    emu.removeMemoryCallback(numRef, emu.callbackType.write, 0x7e6316, 0x7e6316)
    H.log(string.format(
      "frames %d, frames with a boost pending %d, damage numerals fired %d",
      frames, pendFrames, numerals))
    H.log(string.format("party-window arrow cell frames: %d", arrowFrames))
    -- positive controls first: a run with nothing happening must not pass
    H.assertEq(pendFrames > 200, true,
      "positive control: a boost really was pending during sampling")
    H.assertEq(numerals > 0, true,
      "positive control: damage numerals really fired")
    -- negative control: the surviving indicator still works
    H.assertEq(arrowFrames > 100, true,
      "negative control: party-window arrow cluster still drawn while boosting")
    -- the invariant
    H.assertEq(badMark, nil, "retired boost-mark oam entries stay parked")
    H.assertEq(markFrames, 0, "...on every sampled frame")
    H.assertEq(badTile, nil,
      "no OT6-attributed sprite points into vanilla's numeral tiles")
    H.screenshot("dmgnum_no_marks")
  end),
})
