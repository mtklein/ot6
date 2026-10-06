-- @manual standalone: lua tools/tests/slot_selftest.lua  (after ninja build/ot6.sfc)
-- slot_selftest.lua -- the driver's reel arithmetic (#353: M.slotStopPos,
-- M.slotIcon, M.slotResult, M.slotDriftAt, M.slotAim, M.slotPressLands) against the
-- built ROM's own tables.
--
-- No emulator.  The strips and the result table come from build/ot6.sfc at
-- the symbols ff6/rom/ff6-en.dbg gives SlotReelTbl (three strips of 16
-- words), SlotAttackTbl (8 bytes) and MagicProp (14 bytes a spell, power
-- at +6); the stop rule is UpdateMenuState_08's (btlgfx_main.asm @8000):
-- a marked reel steps 4 and stops on the first position whose low nibble
-- is 0.  Mutants: a stop that counts the press's own position (k >= 0),
-- the 7s aimed at 2 BP, the Joker Doom gate ignored at 3 BP, a reel strip
-- one icon off and a drift walked up the strip each fail an assertion below.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile("tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local function symbol(name)
  local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
  return assert(tonumber(val, 16), name .. " in ff6-en.dbg") & 0x3FFFFF
end
local REELS, ATTACKS, MAGIC = symbol("SlotReelTbl"), symbol("SlotAttackTbl"), symbol("MagicProp")
local RATES = symbol("SlotRateTbl")
local function power(a) return rom:byte(MAGIC + a * 14 + 6 + 1) end

local n = 0
local function check(ok, what) assert(ok, what); n = n + 1 end

-- the strips and the result table are the ROM's
for r = 1, 3 do
  for i = 0, 15 do
    local w = rom:byte(REELS + (r - 1) * 32 + i * 2 + 1)
    check(H.SLOT_REELS[r][i + 1] == w, string.format("reel %d icon %d: lib %d, ROM %d", r, i,
      H.SLOT_REELS[r][i + 1], w))
  end
end
for i = 0, 7 do
  check(H.SLOT_ATTACK[i] == rom:byte(ATTACKS + i + 1), string.format("SlotAttackTbl[%d]", i))
end

for i = 0, 5 do
  check(H.SLOT_RATE[i] == rom:byte(RATES + i + 1), string.format("SlotRateTbl[%d]", i))
end

-- the result (_c2b4a3): a triple is its icon + 1, 7-7-Bar 0, anything else 7
check(H.slotResult(0, 0, 0) == 1 and H.slotResult(3, 3, 3) == 4 and H.slotResult(5, 5, 5) == 6, "triples")
check(H.slotResult(0, 0, 2) == 0 and H.slotResult(0, 0, 1) == 7 and H.slotResult(3, 3, 1) == 7
  and H.slotResult(2, 0, 0) == 7, "7-7-Bar and the misses")

-- the stop: the first 16 boundary strictly after the press's step
check(H.slotStopPos(0x14) == 0x10, "$14 stops at $10")
check(H.slotStopPos(0x10) == 0x00, "$10 (on a boundary) stops one icon on, at $00")
check(H.slotStopPos(0x04) == 0x00, "$04 stops at $00")
check(H.slotStopPos(0x00) == 0xF0, "$00 wraps to $F0")
check(H.slotStopPos(0x0C) == 0x00, "$0C stops at $00")
for pos = 0, 255, 4 do
  local s = H.slotStopPos(pos)
  check(s & 0x0F == 0 and s ~= pos and (pos - s) & 0xFF <= 16, string.format("$%02X -> $%02X", pos, s))
end
check(H.slotIcon(1, 0x00) == 0 and H.slotIcon(1, 0x30) == 3 and H.slotIcon(3, 0xF0) == 5, "icons")
-- a press read a frame later is 4 positions on
check(H.slotPressLands(0x18, 4, 1) and not H.slotPressLands(0x18, 4, 2), "$18 lag 1 -> $10 (icon 4)")
check(H.slotPressLands(0x14, 0, 1), "$14 lag 1 -> $00 (the 7)")
-- every icon of reel 1 is reachable from 4 consecutive frames' positions
for icon = 0, 5 do
  local frames = 0
  for pos = 0, 255, 4 do if H.slotPressLands(pos, icon, 1) then frames = frames + 1 end end
  local count = 0
  for _, v in ipairs(H.SLOT_REELS[1]) do if v == icon then count = count + 1 end end
  check(frames == 4 * count, string.format("icon %d: %d press frames for %d on the strip", icon, frames, count))
end

-- a drifting reel: how many stops pass before the icon, pressed at `pos`
-- (reel 3's strip: 0,1,3,4,2,5,4,3,1,5,4,3,2,5,4,5; stops go down the strip)
check(H.slotDriftAt(3, 0x34, 3, 1, 4) == 0, "reel 3 at $34, lag 1 -> stop $20 (icon 3): 0 stops")
check(H.slotDriftAt(3, 0x54, 3, 1, 4) == 2, "reel 3 at $54 -> stop $40 (icon 2), $30, $20 (icon 3): 2")
check(H.slotDriftAt(3, 0x24, 3, 1, 4) == nil, "reel 3 at $24 -> stop $10 (1), $00 (0), $F0 (5), $E0 (4), $D0 (5): none")
check(H.slotDriftAt(3, 0x14, 3, 1, 4) == nil and H.slotDriftAt(3, 0x14, 5, 1, 4) == 1, "reel 3 at $14 -> stop $00 (0), $F0 (5): 1")
-- every icon of reels 2 and 3 has press frames two stops ahead of it
for r = 2, 3 do
  for icon = 0, 5 do
    local frames = 0
    for pos = 0, 255, 4 do if H.slotDriftAt(r, pos, icon, 1, 4) == 2 then frames = frames + 1 end end
    check(frames >= 4, string.format("reel %d icon %d: %d press frames two stops ahead", r, icon, frames))
  end
end

-- the aim
check(H.slotAim(3, false, power) == 0, "3 BP, Joker Doom allowed: the 7s")
check(H.slotAim(3, true, power) == 3 and H.SLOT_ATTACK[4] == 0x80, "3 BP under the gate: H-Bomb (power " .. power(0x80) .. ")")
check(H.slotAim(2, false, power) == 3, "2 BP: never the 7s; H-Bomb")
check(H.slotAim(2, true, power) == 3, "2 BP under the gate: H-Bomb")
check(H.slotAim(1, false, power) == 5 and H.slotAim(0, true, power) == 5 and H.SLOT_ATTACK[6] == 0x81,
  "below 2 BP: 7-Flush (power " .. power(0x81) .. "), the stronger of the icons every rig blesses")

print(string.format("slot_selftest: PASS -- %d checks: the strips and result table as the ROM has them, "
  .. "the stop rule, every icon's four press frames, the drift's press frames, the aim (7s at 3 BP, H-Bomb under "
  .. "the gate and at 2 BP, 7-Flush below)", n))
