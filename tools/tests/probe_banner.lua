-- probe_banner.lua -- MEASUREMENT probe for the combat banner flash/tear.
--
--   tools/tests/run.sh tools/tests/probe_banner.lua
--
-- Hypothesis under test: vanilla's "show attack name" scratch string lives
-- at $7E57D5 (ram_res w7e57d5,128 -- GfxCmd_01/GfxCmd_11/swdtech/esper name
-- loaders all write it) and OT6 claimed that same byte as OT6_FONTDIRTY.
-- Every named-attack banner then spuriously triggers the ~768-byte PIO font
-- re-upload inside the NMI tail, on exactly the frames vanilla's banner
-- uploads make the NMI heaviest -> vblank overrun -> tear/flash.
--
-- Instrument: exec callbacks at fixed bank-C1 addresses sample the PPU
-- scanline/dot via emu.getState() at four points in every battle NMI:
--   $C10BA7  BattleNMI entry            (vblank start reference)
--   $C10C17  jsl Ot6BgHudFlush_ext      (start of OT6 tail work)
--   $C10C1B  return from the flush      (end of OT6 tail work)
--   $C10CA4  after sta hINIDISP         (end of the PPU-critical section)
-- Alongside: $57D5 (OT6_FONTDIRTY / vanilla banner string byte 0), $8000/
-- $8006 (large-transfer flag/size for PartialTfrVRAM), $62AC (msg flag).
--
-- Drive: battle_doorstep -> walk into the guard fight -> MagiTek Fire Beam
-- (A/A/A), which announces via the attack-name banner.  ~40 per-frame
-- screenshots bracket the confirm press for visual tear inspection.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local rec = {}          -- per-frame records, appended at NMI entry
local armed = false

-- NOTE: emu.getState() returns a FLAT table with dotted string keys
-- ("ppu.scanline"), not nested tables.  There is no dot/hclock field in
-- this build; cpu.cycleCount supplies sub-scanline deltas when needed.
local function ppu()
  local s = emu.getState()
  return s["ppu.scanline"], s["cpu.cycleCount"]
end

local cur = nil
emu.addMemoryCallback(function()
  if not armed then return end
  local v, c = ppu()
  cur = { f = H.frame, nmi = v, nmic = c,
          fd = H.readByte(0x57D5), tfr = H.readByte(0x8000),
          sz = H.readWord(0x8006), msg = H.readByte(0x62AC) }
  rec[#rec + 1] = cur
end, emu.callbackType.exec, 0xC10BA7, 0xC10BA7)

emu.addMemoryCallback(function()
  if not armed or not cur then return end
  cur.fs = ppu()
end, emu.callbackType.exec, 0xC10C17, 0xC10C17)

emu.addMemoryCallback(function()
  if not armed or not cur then return end
  local v, c = ppu()
  cur.fe, cur.fec = v, c
end, emu.callbackType.exec, 0xC10C1B, 0xC10C1B)

emu.addMemoryCallback(function()
  if not armed or not cur then return end
  local v, c = ppu()
  cur.id, cur.idc = v, c
end, emu.callbackType.exec, 0xC10CA4, 0xC10CA4)

local shotN = 0
local function snapFrame()
  return H.call(function()
    local ok, png = pcall(emu.takeScreenshot)
    if ok and type(png) == "string" and #png > 0 then
      H.emitBlob(string.format("bn_f%03d.png", shotN), png)
    end
    shotN = shotN + 1
  end)
end

local function snapBurst(n)
  local steps = {}
  for i = 1, n do
    steps[#steps + 1] = snapFrame()
    steps[#steps + 1] = H.waitFrames(1)
  end
  return H.repeatN(1, steps)
end

H.run({ maxFrames = 12000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),

  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),

  H.waitUntil(function() return H.battleActive() end, 900,
    "battle to become active (screen rendering)", 30),
  H.waitFrames(240),

  -- baseline: quiet battle, menu open, 120 frames
  H.call(function() armed = true; H.log("ARMED baseline @f" .. H.frame) end),
  H.waitFrames(120),

  -- A: MagiTek submenu
  H.pressButtons({ "a" }, 6),
  H.waitFrames(24),
  -- A: pick Fire Beam -> target cursor
  H.pressButtons({ "a" }, 6),
  H.waitFrames(24),

  -- A: confirm target -> banner + beam.  Screenshot every frame.
  H.call(function() H.log("CONFIRM @f" .. H.frame) end),
  H.pressButtons({ "a" }, 6),
  snapBurst(44),
  H.waitFrames(260),
  H.call(function() armed = false; H.log("DISARMED @f" .. H.frame) end),

  H.call(function()
    H.log("records: " .. #rec)
    local worst = nil
    for _, r in ipairs(rec) do
      -- normalize: scanlines < 100 mean we wrapped past vblank into the
      -- next frame's active display (spill).  express as 262 + sl.
      local fe = r.fe or -1
      local feN = (fe >= 0 and fe < 100) and fe + 262 or fe
      local id = r.id or -1
      local idN = (id >= 0 and id < 100) and id + 262 or id
      if not worst or idN > worst then worst = idN end
      H.log(string.format(
        "SL f=%d nmi=%d.%d fs=%s fe=%s.%s id=%s.%s fd=%02X tfr=%d sz=%04X msg=%d",
        r.f, r.nmi, r.nmic, tostring(r.fs), tostring(fe), tostring(r.fec),
        tostring(id), tostring(r.idc), r.fd, r.tfr, r.sz, r.msg))
    end
    H.log("worst normalized post-INIDISP scanline: " .. tostring(worst))
  end),
})
