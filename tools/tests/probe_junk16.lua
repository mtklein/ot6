-- probe_junk16.lua -- reproduction attempt for the owner's "junk over and
-- around the enemies" in a PLAIN random battle (no dialogue, no boss, no
-- fly-in dependence): boot kolts_cave.mss (map 96, the Cirpius-x3 pool --
-- 93.75% of draws, hud lines measured at row 5-6 of the bg3 field map) and
-- fight it out with plain Fight commands.  probe_aurabolt measured that
-- ORDINARY attack animations (any with bg1 graphics, and every bg3-scripted
-- one) set $2105 = $59: battlefield BG3 in 16x16 tile mode for 15-70 frames
-- while BG3 stays on the main screen and the under-enemy hud cells stay
-- painted in the $5400 map with the PRIORITY attr bit set (attr $21).
-- Vanilla's own junk fill ($01EE) is priority-CLEAR, invisible behind the
-- battle bg -- OT6's hud cells are the only priority-set content besides
-- the effect's own cells, so any hud cell inside the scrolled 16x16 window
-- renders as a doubled-size block: the glyph tile plus three neighbor
-- tiles.  Cirpius hud rows 5-6 sit inside the window rows 0-9 at scroll 0.
--
-- Detector, every frame of every battle:
--   * dangerous-display flag: $2105 bit $40 (bg3 16x16) AND $898D bit 2
--     (bg3 on main screen) AND any live hud line cell inside the visible
--     window given the live bg3 scroll ($4AF5/$4AF7) -> log + screenshot.
--   * borrowed-font canary (tiles $64/$6D/$71/$EB vs ROM, 4 bytes each).
--   * quadrant uploads ($7B21/$62C9) that would stomp map rows in vram.
-- Every animation logs its attack number ($626A) -- events name themselves.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/kolts_cave.mss.lua"
local VR  = emu.memType.snesVideoRam
local ROM = emu.memType.snesPrgRom

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CHARIX = 0x3ED9
local CMDTBL = 0x202E
local ST_BLITZ, ST_TGT, ST_CMD = 0x3D, 0x38, 0x05
local DANGER = 0x1f6e

-- ---------------------------------------------------------------- canary --
local iconsBase, bgBase, bgCells = nil, nil, {}
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
local function initCanary()
  iconsBase = findSig({0x10,0x10,0x30,0x38,0x38,0x3c,0x6c,0x7c,
                       0x6e,0x7e,0xee,0xfe,0x7e,0x7c,0x3c,0x00})
  bgBase = findSig({0x7e,0x00,0x91,0x7e,0xb1,0x7e,0x91,0x7e,
                    0x52,0x3c,0x3c,0x38,0x18,0x00,0x00,0x00})
  H.assertEq(iconsBase ~= nil and bgBase ~= nil, true, "OT6 glyph data in rom")
  for k = 1, 16 do bgCells[k] = emu.read(bgBase - 17 + k, ROM) end
end
-- quick canary: 3 sampled tiles, 4 bytes each; returns "" or a mismatch tag
local function quickCanary()
  local checks = {
    { cell = 0xEB, rom = iconsBase },          -- fire icon
    { cell = bgCells[1], rom = bgBase },       -- shield-1 glyph
    { cell = bgCells[14], rom = bgBase + 13*16 },
  }
  for _, c in ipairs(checks) do
    for i = 0, 12, 4 do
      if emu.read(0xB000 + c.cell*16 + i, VR) ~= emu.read(c.rom + i, ROM) then
        return string.format("cell %02X byte %d", c.cell, i)
      end
    end
  end
  return ""
end

-- ------------------------------------------------------------- detector --
local claimed = { [0xbf] = true }
local function initClaimed()
  for _, c in ipairs({0xeb,0xec,0xed,0x64,0xef,0xfb,0xfc,0xfd}) do claimed[c] = true end
  for k = 1, 16 do claimed[bgCells[k]] = true end
end

local function mapBase() -- word address
  local reg = H.readByte(0x897b)
  return (reg - (reg % 4)) * 256
end

-- is 16x16 map cell (r,c) inside the battlefield window at scroll (x,y)?
local function cellVisible16(r, c, x, y)
  local dx = (c*16 - x) % 512
  local dy = (r*16 - y) % 512
  return (dx < 256 or dx > 512 - 16) and (dy < 152 or dy > 512 - 16)
end

-- hud cells visible under 16x16 display? returns descriptive string or nil
local function hudVisible16()
  local m2105 = H.readByte(0x896f)
  local main = H.readByte(0x898d)
  if m2105 % 128 < 64 or (main % 8) < 4 then return nil end -- need $40 and bit2
  local x = H.readWord(0x4af5)
  local y = H.readWord(0x4af7)
  local base = mapBase()
  local hits = {}
  for s = 0, 5 do
    local cur = H.readWord(H.shadowLine(s))
    if cur ~= 0 then
      local off = cur - base
      local r = math.floor(off / 32)
      local c = off % 32
      for k = 0, 4 do
        -- painted glyph in vram at this cell? (veil writes $01EE, blanks $21FF)
        local lo = emu.read((cur + k) * 2, VR)
        local hi = emu.read((cur + k) * 2 + 1, VR)
        if hi == 0x21 and claimed[lo] and cellVisible16(r, (c + k) % 32, x, y) then
          hits[#hits + 1] = string.format("s%d(%d,%d)=%02x", s, r, c + k, lo)
        end
      end
    end
  end
  if #hits > 0 then
    return string.format("16x16 scroll=%04x,%04x %s", x, y, table.concat(hits, " "))
  end
  return nil
end

-- ------------------------------------------------------------ reporting --
local battleN, flags, shots = 0, 0, 0
local lastShotFrame = -999
local function shot(tag)
  if shots >= 40 then return end
  local ok, png = pcall(emu.takeScreenshot)
  if ok and type(png) == "string" and #png > 0 then
    shots = shots + 1
    H.emitBlob(string.format("j16_%s.png", tag), png)
  end
end

local frameN = 0
local wasBusy, cur2105, curMain = 0, -1, -1
local function watchFrame()
  frameN = frameN + 1
  local busy = H.readByte(0x57bf)
  if busy ~= 0 and wasBusy == 0 then
    H.log(string.format("[ab] b=%d f=%d anim starts attack=$%02X", battleN,
      frameN, H.readByte(0x626a)))
  end
  wasBusy = busy
  local m = H.readByte(0x896f)
  local s = H.readByte(0x898d)
  if m ~= cur2105 or s ~= curMain then
    H.log(string.format("[ab] b=%d f=%d 2105=%02x main=%02x scroll=%04x,%04x atk=$%02X curs=%04x,%04x,%04x,%04x,%04x,%04x",
      battleN, frameN, m, s, H.readWord(0x4af5), H.readWord(0x4af7),
      H.readByte(0x626a),
      H.readWord(H.shadowLine(0)), H.readWord(H.shadowLine(1)),
      H.readWord(H.shadowLine(2)), H.readWord(H.shadowLine(3)),
      H.readWord(H.shadowLine(4)), H.readWord(H.shadowLine(5))))
    cur2105, curMain = m, s
    if m % 128 >= 64 then shot(string.format("b%d_f%d_mode", battleN, frameN)) end
  end
  local q = quickCanary()
  if q ~= "" then
    flags = flags + 1
    H.log(string.format("[ab] FLAG b=%d f=%d CANARY %s atk=$%02X", battleN, frameN, q,
      H.readByte(0x626a)))
    if frameN - lastShotFrame > 10 then lastShotFrame = frameN shot(string.format("b%d_f%d_canary", battleN, frameN)) end
  end
  local vis = hudVisible16()
  if vis then
    flags = flags + 1
    H.log(string.format("[ab] FLAG b=%d f=%d HUDVIS %s atk=$%02X", battleN, frameN, vis,
      H.readByte(0x626a)))
    if frameN - lastShotFrame > 2 then lastShotFrame = frameN shot(string.format("b%d_f%d_hudvis", battleN, frameN)) end
  end
  local up = H.readByte(0x7b21)
  if up ~= 0 then
    H.log(string.format("[ab] b=%d f=%d bg3 tile upload quad=%d atk=$%02X",
      battleN, frameN, H.readByte(0x62c9), H.readByte(0x626a)))
  end
end

-- --------------------------------------------------------- battle drive --
-- TERRA casts FIRE every turn (Magic $02 -> first spell -> confirm);
-- everyone else Fights.  Fire's animation carries bg1 graphics, and
-- InitAnimType's bg1-gfx path sets $2105 |= $50 -- battlefield BG3 to
-- 16x16 -- which against the Cirpius pool (hud rows 5-6) puts painted hud
-- cells inside the 16x16 window.  Phased edge driver: 3 on / 3 off.
local ST_SPELL = 0x0e
local function bcmd(slot, i) return H.readByte(CMDTBL + slot*12 + i*3) end
local lastSt, lastActor, phase = -1, -1, 0
local function driveMenus()
  if H.readByte(MENU) == 0 then lastSt, lastActor, phase = -1, -1, 0 return nil end
  local st = H.readByte(MSTATE)
  local actor = H.readByte(ACTOR)
  if st ~= lastSt or actor ~= lastActor then
    H.log(string.format("[ab] b=%d f=%d menu actor=%d charix=%02x state %02x -> %02x cmds=%02x,%02x,%02x,%02x",
      battleN, frameN, actor, H.readByte(CHARIX + actor*2), lastSt, st,
      bcmd(actor,0), bcmd(actor,1), bcmd(actor,2), bcmd(actor,3)))
    lastSt, lastActor, phase = st, actor, 0
  end
  phase = phase + 1
  local step = math.floor((phase - 1) / 12) + 1   -- 12-frame cadence
  local hold = ((phase - 1) % 12) < 4             -- hold 4, release 8
  if not hold then return nil end
  local cix = H.readByte(CHARIX + actor*2)
  if cix == 0x00 then -- TERRA: Magic -> Fire
    if st == ST_SPELL then return {"a"} end          -- Fire is first
    if st == ST_TGT then return {"a"} end
    -- command menu: walk to the Magic row ($02), then A.  the cursor
    -- SKIPS blank ($ff) rows, so count the non-blank rows above it.
    local downs = nil
    local seen = 0
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

local function monstersGone()
  for s = 0, 5 do
    if (H.readByte(0x3aa8 + s*2) % 2) == 1
       and (H.readByte(0x3eec + s*2) % 4) < 2 then return false end
  end
  return true
end

-- ------------------------------------------------------------------ run --
H.run({ maxFrames = 90000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    initCanary()
    initClaimed()
    H.log(string.format("[ab] boot map=%04x world=%s", H.readWord(0x1f64),
      tostring(H.worldMode())))
  end),
  -- pace into an encounter (world or field, adaptive)
  (function()
    local waited, lastX, lane = 0, nil, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      if H.battleLoadStarted() then H.setPad({}) return true end
      return waited >= 12000
    end, 12600, {
      H.call(function()
        if H.worldMode() then
          if not (H.worldHasControl() and H.worldAligned()) then H.setPad({}) return end
          local x = H.worldX()
          if lastX == nil then lastX = x end
          H.setPad({ [(x >= lastX) and "left" or "right"] = true })
        else
          if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
          H.writeWord(DANGER, 0xff00)
          local x, y = H.fieldX(), H.fieldY()
          if lane == nil then
            for _, d in ipairs({ "right", "left", "up", "down" }) do
              if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
            end
          end
          if lane then
            H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
          end
        end
      end),
      H.waitFrames(1),
    }, "an encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle up", 10),
  H.call(function()
    battleN = battleN + 1
    local fw = H.formationWords()
    H.log(string.format("[ab] b=%d formation %04X %04X %04X %04X %04X %04X",
      battleN, fw[1], fw[2], fw[3], fw[4], fw[5], fw[6]))
    shot(string.format("b%d_start", battleN))
  end),
  -- fight it out under the detector: cap ~6000 frames
  (function()
    local n = 0
    return H.driveUntil(function()
      n = n + 1
      return n >= 6000 or (n > 600 and monstersGone())
    end, 6600, {
      H.call(function()
        watchFrame()
        local b = driveMenus()
        if b then H.setPad(b) else H.setPad({}) end
      end),
      H.waitFrames(1),
    }, "battle runs under detector")
  end)(),
  H.call(function()
    shot("end")
    H.log(string.format("[ab] done frames=%d flags=%d shots=%d", frameN, flags, shots))
  end),
})
