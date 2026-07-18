-- probe_shadow_overlap.lua -- does vanilla actually write into OT6_SHADOW?
--
-- OT6_SHADOW ($5762, 6 lines x stride 14) is annotated "trace-verified
-- free", but it sits 13 bytes inside vanilla's `ram_res w7e5755, 128`
-- (btlgfx/btlgfx_ram.inc:71).  The battle command-list text drawers
-- (DrawMagicListText / DrawItemListText / DrawToolsListText / ... in
-- btlgfx_main.asm) write $5755-$576a -- exactly line 0 of the buffer.
-- The original trace almost certainly ran a Fight-only fixture, where no
-- command list is ever opened, so it never saw them.
--
-- This drives the whelk doorstep into a battle and OPENS THE MAGITEK LIST
-- (battle_dlgmenu's flow), watching $7E5762-$7E576F -- line 0's anchor,
-- prev pointer, and cells.  A write from any bank other than $F0 proves
-- the overlap is live.  $7E57B9 rides along as the negative control: it
-- is inside the same vanilla reservation but ABOVE where vanilla's writes
-- stop ($576b), so it must stay bank-F0-only.
--
-- Severity note: the anchor is latched (`bne @keep` at Ot6BgHudLine's
-- @done), so a nonzero garbage anchor is never recomputed -- corruption
-- persists for the rest of the battle rather than blinking once.
--
-- RESULT 2026-07-18: CONFIRMED LIVE.  With the party's top command
-- repointed at Item, DrawItemListText ran 8x and bank C1 wrote
-- $7E5762-$7E5767 from C1:4C90 -- line 0's anchor, prev pointer and
-- cells 0-1.  The anchor came out $00FF (item-name bytes read as an
-- address); the magitek-only path leaves a valid $55E7.  Latched, so
-- $00FF then drives every NMI flush for the rest of the battle.
--
-- NOTE the magitek list drawer alone does NOT reproduce this: it writes
-- only +5/+11, stopping at $5761, one byte short.  That is why the
-- original trace came back clean, and why this probe forces a real Item
-- list.  A fixture that only ever opens the magitek menu proves nothing.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local hits = {}           -- addr -> { count, pcs = {pcstr -> n} }
local function watch(lo, hi)
  emu.addMemoryCallback(function(addr, value)
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} } ; hits[addr] = h end
    h.count = h.count + 1
    pcall(function()
      local s = emu.getState()
      local pc = string.format("%02X:%04X v=%02X", s["cpu.k"], s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
    end)
  end, emu.callbackType.write, lo, hi)
end

watch(0x7E5755, 0x7E576F)   -- vanilla buffer base THROUGH OT6_SHADOW line 0
watch(0x7E57B9, 0x7E57B9)   -- control: above vanilla's write ceiling

local foreign = {}          -- writers from banks other than F0

-- Positive control: did a command-list text drawer actually run at all?
-- Without this a quiet result is ambiguous -- it could mean "no overlap"
-- or "my menu drive never opened a list".
local drawers = {}
local function watchDrawer(name, addr)
  emu.addMemoryCallback(function()
    drawers[name] = (drawers[name] or 0) + 1
  end, emu.callbackType.exec, addr, addr)
end
watchDrawer("DrawItemListText", 0xC14C7A)
watchDrawer("DrawMagicListText", 0xC14DC4)

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(whelk, 8000, {
    H.call(function()
      if H.dialogWaiting() then
        local n = (H.vars.an or 0) + 1 ; H.vars.an = n
        H.setPad(n % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}) ; return end
      if not H.tileAligned() then H.setPad({}) ; return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk battle reached"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),

  -- edge-tap A until the first command menu appears
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
    H.call(function()
      local n = (H.vars.mn or 0) + 1 ; H.vars.mn = n
      H.setPad(n % 60 < 4 and { "a" } or {})
    end),
  }, "first menu opens"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(120),

  -- The whelk/doorstep party rides magitek armor, and the MAGITEK list
  -- drawer is not one of the overlapping ones -- it writes only +5/+11,
  -- stopping at $5761, one byte below OT6_SHADOW.  The drawers that reach
  -- into the buffer are the Item/Magic/Tools family (indexed loops bounded
  -- `cpx #$0013` = offsets 0-18, plus explicit stores to +21).  So force a
  -- real Item list: clear magitek status and repoint every character's
  -- top command at Item, the way battle_fold repoints Terra's at Magic.
  H.call(function()
    for c = 0, 3 do
      local st = 0x3ee4 + c*2
      H.writeByte(st, H.readByte(st) & 0xf7)      -- clear magitek
      H.writeByte(0x202e + c*12, 0x01)            -- command 0 := Item
      H.writeByte(0x2031 + c*12, 0x02)            -- command 1 := Magic
    end
    H.log("repointed all four command slots: 0=Item, 1=Magic")
  end),
  H.waitFrames(60),

  -- open the top command's list, then back out and open the second
  H.pressButtons({ "a" }, 4), H.waitFrames(90),
  H.pressButtons({ "b" }, 4), H.waitFrames(45),
  H.pressButtons({ "down" }, 4), H.waitFrames(30),
  H.pressButtons({ "a" }, 4), H.waitFrames(90),
  H.waitFrames(120),

  H.call(function()
    local addrs = {}
    for a in pairs(hits) do addrs[#addrs + 1] = a end
    table.sort(addrs)
    for _, a in ipairs(addrs) do
      local h = hits[a]
      H.log(string.format("$%06X: %d writes", a, h.count))
      for pc, n in pairs(h.pcs) do
        H.log(string.format("    %s x%d", pc, n))
        local bank = tonumber(pc:sub(1, 2), 16)
        if bank ~= 0xF0 and a >= 0x7E5762 and a <= 0x7E576F then
          foreign[#foreign + 1] = string.format("$%06X <- %s", a, pc)
        end
      end
    end
    H.log(string.format("anchor $5762 now reads $%04X", H.readWord(0x5762)))
    local ranDrawer = false
    for name, n in pairs(drawers) do
      H.log(string.format("drawer %s ran %dx", name, n))
      ranDrawer = true
    end
    if not ranDrawer then
      H.log("NO command-list drawer ran -- this path proves NOTHING about " ..
            "the overlap; the menu drive needs work")
    end

    if #foreign > 0 then
      H.log("OVERLAP CONFIRMED LIVE -- non-bank-F0 writers into OT6_SHADOW:")
      for _, f in ipairs(foreign) do H.log("  " .. f) end
    else
      H.log("no foreign writers observed on this path")
    end
  end),
}, "shadow overlap probe")
