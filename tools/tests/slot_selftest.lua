-- @manual standalone: lua tools/tests/slot_selftest.lua  (after ninja build/ot6.sfc)
-- slot_selftest.lua -- the driver's reels (#353: M.slotLoadTables,
-- M.slotStopPos, M.slotIcon, M.slotResult, M.slotDriftAt, M.slotReelPlan,
-- M.slotAvoidStop, M.slotAim, M.slotPressLands, Driver:slotTimed) against
-- the built ROM's own tables.
--
-- No emulator.  The strips, the result table and the rates come from
-- build/ot6.sfc at the symbols ff6/rom/ff6-en.dbg gives SlotReelTbl (three
-- strips of 16 words), SlotAttackTbl (8 bytes), SlotRateTbl (6 bytes) and
-- MagicProp (14 bytes a spell, power at +6), read the way the driver reads
-- them (M.slotLoadTables); the stop rule is UpdateMenuState_08's
-- (btlgfx_main.asm @8000): a marked reel steps 4 and stops on the first
-- position whose low nibble is 0.  Driver:slotTimed runs against a model
-- of that state machine with ot6_slot.asm's hooks (the rig at the first A,
-- the drift budget, the refused pair), the lib's memory reads and pad
-- pointed at it.  Mutants (build/attempts/wt/v026-driver2/353/mutants/)
-- each fail an assertion.
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

-- in the emulator the lib names each table through a literal sym("...")
-- call, the only way compose.py injects a symbol (OT6_SYMS)
-- (comments stripped first: compose drops a name only a comment mentions;
-- SLOT_SELFTEST_LIB, when a mutant sets it, rewrites the source read)
local libSrc = slurp("tools/tests/lib/ot6.lua")
if SLOT_SELFTEST_LIB then libSrc = SLOT_SELFTEST_LIB(libSrc) end
libSrc = libSrc:gsub("%-%-%[(=*)%[.-%]%1%]", ""):gsub("%-%-[^\n]*", "")
for _, name in ipairs({ "SlotReelTbl", "SlotAttackTbl", "SlotRateTbl", "MagicProp" }) do
  check(libSrc:find('M.sym("' .. name .. '")', 1, true) ~= nil, "the lib names " .. name .. " as a literal M.sym call")
end
-- ...and its own path (M.sym on the OT6_SYMS compose.py would inject)
-- reads what this file's reader does
OT6_SYMS = { SlotReelTbl = symbol("SlotReelTbl"), SlotAttackTbl = symbol("SlotAttackTbl"),
             SlotRateTbl = symbol("SlotRateTbl") }
H.slotLoadTables(function(o) return rom:byte(o + 1) end)
local viaSym = { H.SLOT_REELS[2][5], H.SLOT_ATTACK[4], H.SLOT_RATE[1] }
OT6_SYMS = nil
-- the tables, read from the ROM as the driver reads them (M.slotLoadTables
-- with this file's ROM reader); the words of SlotReelTbl are icons 0-5
H.slotLoadTables(function(o) return rom:byte(o + 1) end, symbol)
for r = 1, 3 do
  local seen = {}
  for i = 0, 15 do
    check(rom:byte(REELS + (r - 1) * 32 + i * 2 + 2) == 0, string.format("reel %d entry %d: a word under 256", r, i))
    local v = H.SLOT_REELS[r][i + 1]
    check(v >= 0 and v <= 5, string.format("reel %d entry %d: icon %d", r, i, v))
    seen[v] = true
  end
  for icon = 0, 5 do check(seen[icon], string.format("reel %d holds icon %d (every icon on every reel)", r, icon)) end
end
check(viaSym[1] == H.SLOT_REELS[2][5] and viaSym[2] == H.SLOT_ATTACK[4] and viaSym[3] == H.SLOT_RATE[1],
  "the lib's own symbol path reads the same tables")
check(H.SLOT_REELS[1][1] == 0 and H.SLOT_REELS[1][4] == 3 and H.SLOT_REELS[3][16] == 5,
  "reel words where btlgfx_main.asm's listing has them")
for i = 0, 7 do
  check(H.SLOT_ATTACK[i] == rom:byte(ATTACKS + i + 1), string.format("SlotAttackTbl[%d]", i))
end
check(H.SLOT_ATTACK[1] == 0x94 and H.SLOT_ATTACK[4] == 0x80 and H.SLOT_ATTACK[7] == 0xFE, "Joker Doom, H-Bomb, Lagomorph")
for i = 0, 5 do
  check(H.SLOT_RATE[i] == rom:byte(RATES + i + 1), string.format("SlotRateTbl[%d]", i))
end
check(H.SLOT_RATE[0] == 0x1F and H.SLOT_RATE[4] == 0 and H.SLOT_RATE[5] == 0, "the 7s cursed by most rigs, 4 and 5 by none")

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

-- what the machine does with reels 2 and 3 (M.slotReelPlan)
local plan = H.slotReelPlan
check(plan(2, 3, nil, 0x00, 2, false).aim == 3 and plan(2, 3, nil, 0x00, 2, false).drift == 4, "2 BP: reel 2 drifts 4 to 3")
check(plan(2, 0, nil, 0x00, 3, false).drift == 0xFF, "3 BP: reel 2 drifts the strip")
check(plan(2, 3, nil, 0x37, 1, false).drift == 0, "a rig that curses reel 1's icon: reel 2 does not drift")
check(plan(2, 5, nil, 0x37, 0, false).drift == 4, "icon 5 is blessed under every rig")
check(next(plan(3, 3, 4, 0x00, 2, false)) == nil, "no pair: reel 3 has nothing to complete")
check(plan(3, 3, 3, 0x37, 1, false).aim == 3 and plan(3, 3, 3, 0x37, 1, false).drift == 4, "1 BP buys off the refused pair")
check(plan(3, 3, 3, 0x37, 0, false).avoid == 3, "0 BP: a cursed pair is refused")
check(plan(3, 0, 0, 0x3C, 3, true).avoid == 0, "the 7 pair under the gate is refused at any tier")
-- a refused 7 pair: reel 3 skips the 7s; the Bar there is Joker Doom on the party
check(H.slotAvoidStop(0x54, 0, 1) == 2 and H.slotAvoidStop(0x24, 0, 1) == 1, "the stop past a refused 7")

-- Driver:slotTimed against a model of UpdateMenuState_08 with ot6_slot.asm's
-- hooks: the game reads A `lag` frames after the pad (measured 2-3, 353/cal
-- and 353/lag), marks and stops the reels as the asm does, and the driver
-- sees each frame's bytes before that frame runs.
local function simulate(o)
  local m = { pos = { o.p1, o.p2, o.p3 }, stop = { 0, 0, 0 }, press = { 0, 0, 0 }, rig = 0, tier = 0,
              aim2 = 0, aim3 = 0, drift = 0, commit = false }
  local pad, logs, dropped = {}, {}, 0
  local frame = 0
  local real = { readByte = H.readByte, readWord = H.readWord, setPad = H.setPad, log = H.log, sym = H.sym,
                 readRomByte = H.readRomByte }
  H.readByte = function(a)
    if a == 0x7BC2 then return 0x08 end
    if a == 0x62CA then return o.actor end
    if a >= 0x7B8C and a <= 0x7B8E then return m.pos[a - 0x7B8C + 1] end
    if a >= 0x7B8F and a <= 0x7B91 then return m.stop[a - 0x7B8F + 1] end
    if a >= 0x7B92 and a <= 0x7B94 then return m.press[a - 0x7B92 + 1] end
    if a == 0x3E9D + o.actor * 2 or a == 0x3E9C + o.actor * 2 then return o.pending end
    if a == 0x2F49 then return o.gate and 0x04 or 0 end
    if a == 0x57BA then return m.tier end
    if a == 0x6179 then return m.rig end
    if a == 0x617C then return m.aim3 end
    if a == 0x617D then return m.drift end
    return 0
  end
  H.readWord = function() return 0 end
  H.setPad = function(b) pad[frame] = (b ~= nil and b[1] == "a") end
  H.log = function(l) logs[#logs + 1] = l end
  H.sym = function(name) return symbol(name) end
  H.readRomByte = function(off) return rom:byte(off + 1) end
  local D = H.newFightDriver("sim", {}).driver
  D.plan = { kind = "slot", aimIcon = o.aim, boostPlanned = o.pending }
  local icon = H.slotIcon
  local function blessed(i) return (m.rig & H.SLOT_RATE[i]) == 0 end
  local function budget() return m.tier >= 3 and 0xFF or 4 end
  for f = 0, 3000 do
    frame = f
    H.frame = f
    D:slotTimed(o.actor)
    local edge = pad[f - o.lag] and not pad[f - o.lag - 1]
    if edge and o.drop and dropped < o.drop then dropped = dropped + 1; edge = false end
    if edge then
      if m.press[1] == 0 then
        m.tier = math.min(o.pending, 3)
        m.rig = m.tier >= 2 and (o.gate and 0x3C or 0) or o.rig
        m.press[1] = 1
      elseif m.press[2] == 0 then
        if m.stop[1] ~= 0 then
          local i1 = icon(1, m.pos[1])
          if blessed(i1) then m.aim2, m.drift = i1, budget() else m.aim2 = 0xFF end
          m.press[2] = 1
        end
      elseif m.press[3] == 0 then
        if m.stop[2] ~= 0 then
          local i1, i2 = icon(1, m.pos[1]), icon(2, m.pos[2])
          if i1 ~= i2 then m.aim3 = 0xFF
          elseif blessed(i1) then m.aim3, m.drift = i1, budget()
          elseif m.tier == 0 or (i1 == 0 and o.gate) then m.aim3 = i1 | 0x80
          else m.aim3, m.drift = i1, budget() end
          m.press[3] = 1
        end
      end
    end
    if m.stop[1] == 0 then
      m.pos[1] = (m.pos[1] - 4) & 0xFF
      if m.press[1] ~= 0 and m.pos[1] & 0x0F == 0 then m.stop[1] = 1 end
    end
    if m.stop[2] == 0 then
      m.pos[2] = (m.pos[2] - 4) & 0xFF
      if m.press[2] ~= 0 and m.pos[2] & 0x0F == 0 then
        if m.aim2 == 0xFF or icon(2, m.pos[2]) == m.aim2 or m.drift == 0 then m.stop[2] = 1
        else m.drift = m.drift - 1 end
      end
    end
    if m.stop[3] == 0 then
      m.pos[3] = (m.pos[3] - 4) & 0xFF
      if m.press[3] ~= 0 and m.pos[3] & 0x0F == 0 then
        local i3 = icon(3, m.pos[3])
        if m.aim3 == 0xFF then m.stop[3] = 1
        elseif m.aim3 & 0x80 ~= 0 then
          if i3 ~= m.aim3 & 0x7F then m.stop[3] = 1 end
        elseif i3 == m.aim3 or m.drift == 0 then m.stop[3] = 1
        else m.drift = m.drift - 1 end
      end
    end
    if m.stop[3] ~= 0 then break end
  end
  for k, v in pairs(real) do H[k] = v end
  return icon(1, m.pos[1]), icon(2, m.pos[2]), icon(3, m.pos[3]), logs
end
local function triple(o)
  local a, b, c, logs = simulate(o)
  return a == o.want and b == o.want and c == o.want, string.format("%d-%d-%d", a, b, c), logs
end
local function saidIn(logs, text)
  for _, l in ipairs(logs) do if l:find(text, 1, true) then return true end end
  return false
end
-- 2 BP aimed at H-Bomb (3), reel phases across the strip, the game reading the pad 2 or 3 frames on
local sims = 0
for _, lag in ipairs({ 2, 3 }) do
  for p1 = 0, 252, 44 do
    for p2 = 4, 252, 88 do
      for p3 = 8, 252, 128 do
        local ok, got = triple({ actor = 1, pending = 2, rig = 0x37, gate = false, aim = 3, want = 3,
                                 lag = lag, p1 = p1, p2 = p2, p3 = p3 })
        check(ok, string.format("2 BP, lag %d, reels at $%02X $%02X $%02X: 3-3-3, got %s", lag, p1, p2, p3, got))
        sims = sims + 1
      end
    end
  end
end
-- 3 BP: the 7s
local ok, got = triple({ actor = 0, pending = 3, rig = 0, gate = false, aim = 0, want = 0, lag = 2,
                         p1 = 0x40, p2 = 0x80, p3 = 0xC0 })
check(ok, "3 BP: 0-0-0, got " .. got)
-- an R the menu did not take: planned 2, pending 1, a rig cursing icon 3 -- the
-- driver re-aims on 7-Flush (5), which every rig blesses
local logs
ok, got, logs = triple({ actor = 1, pending = 1, rig = 0x37, gate = false, aim = 3, want = 5, lag = 2,
                         p1 = 0x80, p2 = 0x40, p3 = 0x20 })
check(ok, "pending 1 under a cursing rig: re-aimed 5-5-5, got " .. got)
check(saidIn(logs, "will latch tier 1"), "the re-aim is said")
-- reel 1 lands an icon the rig curses (the aim forced onto 3 at tier 1): reel 2
-- does not drift, so it is timed onto 3 itself, and 1 BP blesses the pair
do
  local realAim = H.slotAim
  H.slotAim = function() return 3 end
  for _, p2 in ipairs({ 0x00, 0x40, 0x84, 0xC8 }) do
    ok, got = triple({ actor = 1, pending = 1, rig = 0x37, gate = false, aim = 3, want = 3, lag = 2,
                       p1 = 0x80, p2 = p2, p3 = 0x20 })
    check(ok, string.format("a cursed reel-1 icon, reel 2 at $%02X: timed onto it with no drift, 3-3-3, got %s", p2, got))
  end
  H.slotAim = realAim
end
-- a first A the game does not read: released, timed again, and still the triple
ok, got, logs = triple({ actor = 1, pending = 2, rig = 0, gate = false, aim = 3, want = 3, lag = 2, drop = 1,
                         p1 = 0x80, p2 = 0x40, p3 = 0x20 })
check(ok, "a dropped first A: 3-3-3 on the retry, got " .. got)
check(saidIn(logs, "was not read; timing again"), "the retry is said ('was not read; timing again')")

print(string.format("slot_selftest: PASS -- %d checks: the tables as the ROM has them, the stop rule, every "
  .. "icon's four press frames, the drift's press frames, the aim (7s at 3 BP, H-Bomb under the gate and at "
  .. "2 BP, 7-Flush below), the machine's reel plans, and Driver:slotTimed on a model of the reels: %d aimed "
  .. "spins at 2 BP over reel phases and a 2-3 frame read, the 7s at 3 BP, the re-aim at a lower tier, a "
  .. "cursed reel-1 icon, and a dropped first A", n, sims))
