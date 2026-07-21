-- @suite slow
-- battle_dmgnum: OT6 keeps its hands off vanilla's damage-numeral vram.
--
-- The v0.2 RC playtest bug: "the boost chevrons sometimes turn into
-- numbers".  OT6's over-character boost marks used three 16x16 sprites in
-- obj tiles 200/202/204 + 216-221 = vram words $2c80-$2dd0, which is
-- inside the block ff6/notes/battle-ram.txt:2206 labels "$2C00 Damage
-- Numeral Graphics / $2CC0 Miss Graphics".  GfxCmd_0b picks a numeral's
-- destination from a rotating counter (btlgfx_main.asm:24697, tables at
-- :24795): phases 2 and 3 land on $2c80/$2d80 and $2cc0/$2dc0, covering
-- every one of OT6's twelve tiles.  So half of all damage numbers stamped
-- digits over the chevrons -- intermittent, keyed to a counter no player
-- can see.  probe_objarrow.lua measured 2141 of 3000 frames clobbered.
--
-- The marks are retired (there is no free obj vram to move them to --
-- probe_objsentinel.lua and probe_objtail.lua), so the invariant this
-- test gates is: while a boost is pending and damage numbers are flying,
--   * oam entries 96-99 (the old mark entries) stay parked, and
--   * no oam entry ever points at a tile in the numeral block 192-223
--     wearing OT6's palette-3/priority-3 attribute.
-- Against the pre-fix ROM both fail loudly: the drawer populated entry
-- 96+slot every frame a boost was pending, with tile $c8/$ca/$cc and
-- attr $36.
--
-- Negative control (so this cannot pass by boost feedback simply being
-- gone): the party-window pip cell must still show the arrow cluster
-- while the boost is pending.
-- Positive controls: a boost really was pending, and damage numerals
-- really did fire, during the sampled window.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

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
  H.call(function()
    actor = H.readByte(0x62ca) & 3
    H.writeByte(0x3e9c + actor*2, 3)
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
    end
    watchNumerals()
  end),
  -- arm a boost: this is the state the retired drawer painted in.
  -- driven by state, not by counting presses -- a press landing in a
  -- just-opening window is silently eaten (metrics_battle.lua's lesson).
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
  -- now let the battle run so damage numerals fly
  H.driveUntil(function()
    sample()
    return frames >= 2400
  end, 30000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then
        -- keep re-arming a boost so the mark state recurs all run
        if H.readByte(0x3e9d + (H.readByte(0x62ca) & 3)*2) == 0
           and (frames // 53) % 2 == 0 then
          H.setPad({ "r" })
        else
          H.setPad({ "a" })
        end
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
    -- positive controls first: a quiet run must not pass
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
