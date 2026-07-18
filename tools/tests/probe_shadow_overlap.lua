-- probe_shadow_overlap.lua -- regression gate for the OT6_SHADOW overlap.
--
-- HISTORY.  OT6_SHADOW used to live at $5762, annotated "trace-verified
-- free".  It was not: $5762 sits 13 bytes inside vanilla's `ram_res
-- w7e5755, 128` (btlgfx/btlgfx_ram.inc:71), and the battle command-list
-- text drawers write $5755-$576a.  This probe reproduced it -- with the
-- party's top command repointed at Item, DrawItemListText ran and bank C1
-- wrote $7E5762-$7E5767, leaving the HUD line-0 anchor at $00FF, which the
-- latch at Ot6BgHudLine's @done then made permanent for the battle.
-- OT6_SHADOW now lives at $ecf1, past the end of vanilla's battle-graphics
-- RAM chain.  See the block comment at the symbol for the evidence.
--
-- WHAT THIS ASSERTS NOW, both directions:
--   1. nothing but bank F0 writes the NEW home ($7eecf1+)
--   2. nothing from bank F0 writes the OLD home ($7e5762+) -- we vacated
--
-- THE FIXTURE MATTERS.  The magitek list drawer writes only +5/+11 and
-- stops at $5761, one byte short of the old buffer -- so a Fight-only or
-- magitek-only battle sees nothing and reads as an all-clear.  That is
-- exactly how the original trace got it wrong.  This probe therefore
-- clears magitek status, repoints the party's commands at Item/Magic, and
-- FAILS LOUDLY if no command-list drawer actually ran: a quiet result must
-- never be mistaken for a clean one.
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

-- OT6_SHADOW now lives at $ecf1 (see ot6.asm). Two assertions:
--   1. nothing but bank F0 writes the NEW home
--   2. nothing from bank F0 writes the OLD home -- i.e. we really vacated
local NEW_LO, NEW_HI = 0x7EECF1, 0x7EECFE   -- new line 0 (anchor+prev+cells)
local OLD_LO, OLD_HI = 0x7E5762, 0x7E576F   -- old line 0, now vanilla's alone
watch(NEW_LO, NEW_HI)
watch(OLD_LO, OLD_HI)
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
        if bank ~= 0xF0 and a >= NEW_LO and a <= NEW_HI then
          foreign[#foreign + 1] = string.format("FOREIGN into new home: $%06X <- %s", a, pc)
        end
        if bank == 0xF0 and a >= OLD_LO and a <= OLD_HI then
          foreign[#foreign + 1] = string.format("OT6 still writing OLD home: $%06X <- %s", a, pc)
        end
      end
    end
    H.log(string.format("new anchor $ecf1 = $%04X   old $5762 = $%04X (vanilla's now)",
      H.readWord(0xecf1), H.readWord(0x5762)))
    local ranDrawer = false
    for name, n in pairs(drawers) do
      H.log(string.format("drawer %s ran %dx", name, n))
      ranDrawer = true
    end
    if not ranDrawer then
      error("no command-list drawer ran -- the fixture did not exercise the " ..
            "overlap path, so a clean result would be meaningless")
    end
    if #foreign > 0 then
      for _, f in ipairs(foreign) do H.log("  " .. f) end
      error(#foreign .. " shadow-buffer violation(s) -- see log")
    end
    H.log("ok: new home bank-F0 only, old home fully vacated")
  end),
}, "shadow overlap probe")
