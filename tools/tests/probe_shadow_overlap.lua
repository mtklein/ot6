-- @suite slow
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
-- THE FIXTURE MATTERS.  The magitek list drawer writes only $5755..$5761
-- (`cpx #$000d`, madou_line_mess_set), one byte short of the old buffer --
-- so a Fight-only or magitek-only battle sees nothing and reads as an
-- all-clear.  That is exactly how the original trace got it wrong.  This
-- probe therefore clears magitek status, repoints the party's commands at
-- Item/Magic, and FAILS LOUDLY if the overlap path was not exercised: a
-- quiet result must never be mistaken for a clean one.
--
-- HOW THE POSITIVE CONTROL IS DERIVED, and why it is not an exec watch.
-- Until 2026-07-19 the control was two exec callbacks on hand-copied bank-C1
-- instruction addresses, `DrawItemListText` at $C14C7A and
-- `DrawMagicListText` at $C14DC4, transcribed from ff6/notes/ff3u.asm.  Both
-- were wrong, because THIS ROM'S bank C1 sits 11 bytes below the vanilla
-- notes: DrawMagicListText is at C1/4DC0 (ff6/rom/ff6-en.map:539, and the
-- built image reads 5A 0A 85 40 there = phy/asl/sta $40) and
-- DrawItemListText at C1/4C76, whose row loop head is C1/4C85.  So $C14C7A
-- was the OPERAND byte of `sta $40` at C1/4C79 -- never an opcode fetch, so
-- that half of the control could never fire on any ROM, and never did.
-- $C14DC4 landed on `lda $62ca` four bytes into DrawMagicListText purely by
-- luck, which left "did a drawer run?" secretly meaning "did the MAGIC list
-- open?".  That is a coin flip: only TERRA carries a Magic command in this
-- fight (measured, $202e+slot*12: Terra reads 1d,ff,02,01 and VICKS reads
-- 1d,ff,ff,01), and which of them holds the first menu follows from the
-- battle RNG seed, which battle init takes from the game-time frame counter
-- (`lda $021e / asl2 / sta $be`, battle_main.asm:6092-6094).  On
-- release-0.2.1 the roll gave VICKS, the magic list never opened, and this
-- probe failed -- while the ITEM list had drawn EIGHT rows into $5762-$5767
-- and exercised the overlap path more thoroughly than the runs it passed.
--
-- So the control now keys on the DATA the mechanism touches instead of the
-- ADDRESS of the code that touches it: ROM code layout moves under you (the
-- +11 above), vanilla's RAM reservations do not.  Both assertions get one,
-- derived from the assertion itself:
--   * "OT6 vacated the old home" is vacuous unless VANILLA wrote it, so
--     require >= 1 write into $7e5762+ from a bank other than F0.
--   * "nothing foreign writes the new home" is vacuous unless OT6 wrote it,
--     so require >= 1 write into $7eecf1+ from bank F0.
-- Both fall out of the write watch this probe already keeps, so there is no
-- second mechanism to keep in sync.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/whelk_doorstep.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

-- OT6_SHADOW now lives at $ecf1 (see ot6.asm). Two assertions:
--   1. nothing but bank F0 writes the NEW home
--   2. nothing from bank F0 writes the OLD home -- i.e. we really vacated
local NEW_LO, NEW_HI = 0x7EECF1, 0x7EECFE   -- new line 0 (anchor+prev+cells)
local OLD_LO, OLD_HI = 0x7E5762, 0x7E576F   -- old line 0, now vanilla's alone

local hits = {}           -- addr -> { count, pcs = {pcstr -> n} }
-- Live tallies for the two positive controls (see the header).  Kept here
-- rather than recomputed from `hits` at the end because the drive below
-- needs `vanillaOldHome` as a predicate while it runs.
local vanillaOldHome, ot6NewHome = 0, 0
-- The PC a write callback reports is the instruction AFTER the store: the
-- item row loop's `sta $5755,x` sits at C1/4C89 and every one of its writes
-- logs as C1:4C8C, the following `inx`.  Only the BANK is load-bearing here,
-- and that is unaffected.
local function watch(lo, hi)
  emu.addMemoryCallback(function(addr, value)
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} } ; hits[addr] = h end
    h.count = h.count + 1
    pcall(function()
      local s = emu.getState()
      local bank = s["cpu.k"]
      local pc = string.format("%02X:%04X v=%02X", bank, s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
      if bank ~= 0xF0 and addr >= OLD_LO and addr <= OLD_HI then
        vanillaOldHome = vanillaOldHome + 1
      end
      if bank == 0xF0 and addr >= NEW_LO and addr <= NEW_HI then
        ot6NewHome = ot6NewHome + 1
      end
    end)
  end, emu.callbackType.write, lo, hi)
end

watch(NEW_LO, NEW_HI)
watch(OLD_LO, OLD_HI)
watch(0x7E57B9, 0x7E57B9)   -- control: above vanilla's write ceiling

local foreign = {}          -- writers from banks other than F0

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
  -- Nothing before this point may have written the old home, or the control
  -- below would be satisfied by something other than a command list -- the
  -- field walk and the battle intro both run with this watch armed.  Logged
  -- rather than assumed; it reads 0 on every ROM measured so far.
  H.call(function()
    H.log(string.format("old-home writes before any list is opened: %d "
      .. "(must be 0 for the control below to mean anything)", vanillaOldHome))
    H.assertEq(vanillaOldHome, 0, "old home untouched before the list drive")
  end),

  -- Open a command list -- CLOSED-LOOP, until the buffer is actually
  -- written.  This used to be four open-loop presses (A, B, down, A) on the
  -- assumption that row 0 and row 1 are both live commands for whoever holds
  -- the menu.  They are not: InitCmdList REMOVES commands a character does
  -- not have (`lda #$ff / sta $fc,x`, battle_main.asm:13778-13780), the
  -- cursor skips the removed rows, and VICKS reads 1d,ff,ff,01 where TERRA
  -- reads 1d,ff,02,01.  On a VICKS roll `down` therefore walked to the Item
  -- row again and the second A re-opened the list the first A had just
  -- opened -- harmless in itself, but it is what made the old exec-address
  -- control read as "no drawer ran".  So cycle A / B / down instead and stop
  -- the moment vanilla has written the old home, which is the only thing
  -- this probe actually needs and is true for every roll.
  --
  -- Stopping at the first list costs no coverage: the ITEM template is the
  -- deepest-reaching of the three ($5755-$5767 against magic's $5764 and
  -- magitek's $5761), so it covers strictly more of the old home than the
  -- Item-then-Magic pair the open-loop sequence was aiming for.
  H.driveUntil(function() return vanillaOldHome > 0 end, 2400, {
    H.pressButtons({ "a" }, 4), H.waitFrames(90),
    H.pressButtons({ "b" }, 4), H.waitFrames(45),
    H.pressButtons({ "down" }, 4), H.waitFrames(30),
  }, "a vanilla command-list drawer writes the old shadow home"),
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
    -- POSITIVE CONTROLS, one per assertion (see the header).  Each says
    -- "the thing I claim nobody else touches was actually touched by the
    -- one who should".  A run that fails either is not clean, it is blind.
    H.log(string.format("exercised: vanilla wrote the old home %dx, "
      .. "bank F0 wrote the new home %dx", vanillaOldHome, ot6NewHome))
    if vanillaOldHome == 0 then
      error("no vanilla write reached $7E5762+ -- the fixture never opened a " ..
            "command list whose text template is long enough to touch the old " ..
            "shadow home (item = $13 bytes, magic = $10; magitek stops at " ..
            "$5761), so 'OT6 vacated it' would be vacuously clean")
    end
    if ot6NewHome == 0 then
      error("bank F0 never wrote $7EECF1+ -- the OT6 hud never drew into " ..
            "OT6_SHADOW's new home, so 'nothing foreign writes it' would be " ..
            "vacuously clean")
    end
    if #foreign > 0 then
      for _, f in ipairs(foreign) do H.log("  " .. f) end
      error(#foreign .. " shadow-buffer violation(s) -- see log")
    end
    H.log("ok: new home bank-F0 only, old home fully vacated")
  end),
}, "shadow overlap probe")
