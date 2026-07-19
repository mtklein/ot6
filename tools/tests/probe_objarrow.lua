-- probe_objarrow.lua -- do vanilla's damage numerals land on OT6's
-- boost-mark sprite tiles?
--
-- RETAINED AS EVIDENCE, AND IT NO LONGER RUNS ON A CURRENT ROM: the
-- boost marks and their art tables are gone, so findArrowData below
-- fails its assert.  Point it at a ROM built before that removal to
-- reproduce the original measurement.  battle_dmgnum.lua is the live
-- regression gate.
--
-- Static read (btlgfx_main.asm:24795-24798): damage numeral graphics are
-- DMA'd to a vram word address picked from two 4-entry tables indexed by
-- the rotating numeral counter w7e632e (GfxCmd_0b, :24697/:24781):
--     _c1a5cb  bottom of tiles: $2d00,$2d40,$2d80,$2dc0
--     _c1a5d3  top of tiles:    $2c00,$2c40,$2c80,$2cc0
-- each transfer is $80 bytes = $40 words (:1021).
-- OT6's boost chevrons (Ot6ObjArrowAddrTbl, ot6.asm:2085-2088) sit at
--     boost-1 $2c80,$2c90,$2d80,$2d90
--     boost-2 $2ca0,$2cb0,$2da0,$2db0
--     boost-3 $2cc0,$2cd0,$2dc0,$2dd0
-- so counter phase 2 covers boost-1+boost-2 and phase 3 covers boost-3.
-- Half of every four damage numbers shown should therefore overwrite
-- chevron art with digit art -- "the boost chevrons sometimes turn into
-- numbers", with a period the player cannot see.
--
-- This probe does not trust that read.  It samples all 12 arrow tiles in
-- vram every frame against their ROM source bytes (the glyphCanary
-- idiom), during a battle that actually deals damage, and reports the
-- first divergence together with the numeral counter at that moment.
--
-- Positive control: the run asserts the tiles were correct at least once
-- (right after battle init), so "never diverged" cannot pass because the
-- probe was looking at the wrong address the whole time.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

-- vram WORD addresses of the 12 arrow tiles, in Ot6ObjArrowData order
local ARROW_W = { 0x2c80,0x2c90,0x2d80,0x2d90,
                  0x2ca0,0x2cb0,0x2da0,0x2db0,
                  0x2cc0,0x2cd0,0x2dc0,0x2dd0 }

local romBase, everMatched, firstBad, badCount, frames = nil, false, nil, 0, 0

local function findArrowData()
  -- first 16 bytes of Ot6ObjArrowData (boost-one TL)
  local sig = {0x00,0x00,0x00,0x00,0x00,0x00,0x08,0x08,
               0x0e,0x0e,0x0f,0x0f,0x0f,0x0f,0x0f,0x0f}
  local rom = emu.memType.snesPrgRom
  for base = 0x300000, 0x303FF0 do
    local hit = true
    for i = 1, 16 do
      if emu.read(base+i-1, rom) ~= sig[i] then hit = false; break end
    end
    -- the signature is all-zero-ish at its head; require the NEXT tile to
    -- match too so a run of zeroes elsewhere cannot masquerade
    if hit then
      local ok = true
      for i = 1, 16 do
        if emu.read(base+16+i-1, rom) ~= sig[i] then ok = false; break end
      end
      if ok then return base end
    end
  end
  return nil
end

-- compare all 12 tiles (32 bytes each, 4bpp) against rom; return
-- nil when clean, else "tile i byte j: got/want"
local function checkTiles()
  local vr, rom = emu.memType.snesVideoRam, emu.memType.snesPrgRom
  for t = 1, 12 do
    local v = ARROW_W[t] * 2               -- word addr -> byte addr
    local r = romBase + (t-1) * 32
    for i = 0, 31 do
      local got, want = emu.read(v+i, vr), emu.read(r+i, rom)
      if got ~= want then
        return string.format("tile%d(%04x) byte%d got %02x want %02x",
          t, ARROW_W[t], i, got, want)
      end
    end
  end
  return nil
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load"),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active", 30),
  H.waitFrames(180),
  H.call(function()
    romBase = findArrowData()
    H.assertEq(romBase ~= nil, true, "Ot6ObjArrowData found in rom bank F0")
    H.log(string.format("Ot6ObjArrowData at rom %06x", romBase))
    local bad = checkTiles()
    H.log("arrow tiles right after init: " .. (bad or "all 12 match rom"))
    H.assertEq(bad, nil, "positive control: tiles start correct")
    everMatched = true
    -- long fight, plenty of damage numbers
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
      H.writeByte(0x3e9c + s*2, 3)
    end
  end),
  H.driveUntil(function()
    frames = frames + 1
    local bad = checkTiles()
    if bad then
      badCount = badCount + 1
      if not firstBad then
        firstBad = string.format("f%05d %s | numeral counter=%d, dmgnum enable=%d, dest=%04x",
          frames, bad, H.readByte(0x632e), H.readByte(0x6316), H.readWord(0x6317))
        H.log("FIRST DIVERGENCE: " .. firstBad)
      end
    end
    return frames >= 3000
  end, 30000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then H.setPad({ "a" }) else H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(12),
  }, "battle with damage sampled"),
  H.call(function()
    H.log(string.format("frames sampled %d, frames with clobbered arrow art: %d",
      frames, badCount))
    H.assertEq(everMatched, true, "positive control ran")
    if firstBad then
      H.log("VERDICT: vanilla overwrites OT6 boost-mark tiles. " .. firstBad)
    else
      H.log("VERDICT: arrow tiles survived the whole battle")
    end
  end),
})
