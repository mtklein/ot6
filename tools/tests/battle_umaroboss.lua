-- @suite savestate=umaro_entry slow
-- battle_umaroboss.lua -- Umaro under the boss contract (docs/design/bosses-wor.md block 9, wt/v052-tg-wor1): his
-- Green Cherry is announced, and a break in the fuse denies it for the fight.  (battle_umaro is UMARO's own kit.)
--
-- His script (ai_script.asm AIScript::_272): his first turn under 10,240 HP says "He digs out a Green Cherry!" (battle
-- dialogue $A4) with vanilla's red flash, a turn of its own, and sets battle switch 2; on his next turn the fire block,
-- which stands first, eats the cherry (command $01, the Item, item $F8): Protect, Shell, Haste and Regen, vanilla's
-- "Power 100 times up!", and battle switch 0, vanilla's "eaten".  Under the contract (Ot6FuseTbl's row $0110,
-- OT6_FUSE_SETB0) a break while it is lit cancels it, clears battle switch 2 and SETS battle switch 0: the cherry is
-- gone for the fight, and neither his line nor a Green Cherry used on him (vanilla's counter, behind the same switch)
-- brings it back.  A break before the line denies nothing.
--
-- Boots umaro_entry (gen_wor_tritoch: Umaro's battle, event battle 117, as it comes up).  From a snapshot at the
-- battle's open:
--   landed    (M.fuseLanded, lib/ot6.lua) nothing staged and nothing held: aimed Fights from the members whose hands
--             chip nothing on his row (M.quietArm: no sword or spear, no fire or poison) bring him from his full HP
--             under the 10,240 line, then the party Defends; the line comes and the cherry on his next turn, and
--             lands: Protect, Shell and Haste stand on him.
--   then the three cases from the same snapshot (M.fuseCases, where the cases and the DECLARED staging are written
--   out: the gauge, the row's classes for the breaking Fight, HP held -- his at 9,000, under the line, and in the
--   outside case at 12,000, above it, until its break ends -- and the party's at 9,999):
--   unbroken  the party Defends; the line shows on his first turn; the lit-fuse mark stands; the cherry is used on
--             his next turn; the mark goes; the line reads "He digs out a Green Cherry!" where the relocated dialogue
--             table points.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, battle switch
--             2 reads clear and battle switch 0 set, and in his next four turns back no line and no cherry: the
--             cherry is gone.
--   outside   above the line, a break before any line: nothing is cancelled and the cells stand (battle switch 0
--             clear: the cherry still his), and once he is under the line the fuse lights and fires.
-- Mutants (tools/build/mutant_rom.py; build/attempts/wt/v052-tg-wor1/mutants*/): fuse_never (Ot6FuseCancel+3=80) is red
-- at "the break during the fuse cancels it"; umaro_no_setb0 (his row's flags 0) at "umaro: no announce and no move in 4
-- of the boss's turns back: the cancelled move is gone for the fight"; umaro_row_keeps (his row keeps battle switch 2)
-- at "umaro: the move does not fire when the boss recovers"; imm_umaro (his blocked status 2 back to vanilla's $6B) at
-- check_fuse_immune.  And read from the ROM: a Green Cherry used on him does nothing once battle switch 0 is set (his
-- counter's cherry block is conditioned on it; no party here carries one to use, so it is read, not played).  A
-- mechanism test, not play (the landed case writes nothing).
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/umaro_entry.mss.lua"

local UMARO, CHERRY, LINE = 0x110, 0xF8, 0xA4
-- status 3: Haste, Shell, Protect.  (The script also sets Regen, which does not stand on him: the first run read
-- status 3 $68 after the cherry, build/attempts/wt/v052-tg-wor1/dev/dev_battle_umaroboss-3.log; vanilla's own.)
local BUFFS = 0x08 | 0x20 | 0x40

local function armByBlows(pred, max, W)
  local t0 = nil
  return H.lazy(function()
    t0 = H.frame
    local plan = {}
    for k = 1, 10 do
      for i = 0, 3 do
        local id = H.readByte(0x3ED8 + 2 * i)
        if id ~= 0xFF then plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = W.slot() } end
      end
    end
    return H.kitBattle(plan, { idle = "defend", care = true, maxFrames = max + 600,
      giveUp = function() return pred() or H.frame - t0 >= max end })
  end)
end

local S = {}
-- The cap: the landed case is about 8,000 frames; three cases of about 8,000 each; 70,000 is about 2x.
H.run({ maxFrames = 70000 }, {
  H.loadState(STATE),
  H.waitUntil(function() return H.battleActive() end, 3000, "Umaro's battle is up", 2),
  H.call(function()
    H.assertEq((H.readByte(0x3EB0) & 0x07), 0, "battle switches 0-2 read clear at the open (no cherry eaten, fed or "
      .. "announced)")
 
    -- a Green Cherry used on him: his counter's block (if_item GREEN_CHERRY) stands behind battle switch 0 clear, so
    -- once the break has set it the cherry used on him does nothing
    local SIZE = { [0] = 4, 2, 4, 3, 4, 4, 4, 2, 3, 4, 4, 3, 4, 1, 1, 1 }
    local AI, PTRS = H.sym("AIScript") & 0x3FFFFF, H.sym("AIScriptPtrs") & 0x3FFFFF
    local x = H.readRomByte(PTRS + 2 * UMARO) | (H.readRomByte(PTRS + 2 * UMARO + 1) << 8)
    while H.readRomByte(AI + x) ~= 0xFF do
      local b = H.readRomByte(AI + x); x = x + (b >= 0xF0 and SIZE[b - 0xF0] or 1)
    end
    x = x + 1
    local found, gated = false, false
    while H.readRomByte(AI + x) ~= 0xFF do
      local bstart, conds = x, {}
      while H.readRomByte(AI + x) == 0xFC do
        conds[#conds + 1] = string.format("%02X %02X %02X", H.readRomByte(AI + x + 1), H.readRomByte(AI + x + 2),
          H.readRomByte(AI + x + 3))
        x = x + 4
      end
      local c = table.concat(conds, " / ")
      if c:find("03 F8") then found = true; gated = c:find("15 00 00") ~= nil
        H.log(string.format("[umaro] his counter's cherry block at ctr: conditions [%s]", c)) end
      while H.readRomByte(AI + x) ~= 0xFE and H.readRomByte(AI + x) ~= 0xFF do
        local b = H.readRomByte(AI + x); x = x + (b >= 0xF0 and SIZE[b - 0xF0] or 1)
      end
      if H.readRomByte(AI + x) == 0xFE then x = x + 1 end
    end
    H.assertEq(found and gated, true, "umaro: a Green Cherry used on him is answered only while battle switch 0 is "
      .. "clear (his counter's cherry block): after the denial it does nothing")
    H.log(string.format("[umaro] the party carries %d Green Cherry (none to play the use with)", H.invCountOf(CHERRY)))
  end),
  H.fuseSnap(S),
  H.fuseLanded({
    tag = "umaro", species = UMARO, line = LINE, move = { cmd = 0x01, atk = CHERRY }, turns = 1,
    -- (the members whose Fight chips nothing on his row -- no sword or spear hand, no fire or poison -- bring him under
    -- the line: a first cut's every-member Fights broke him at 14,110 HP and killed him in the window, before any turn
    -- of his under the line, build/attempts/wt/v052-tg-wor1/dev/dev_battle_umaroboss-1.log)
    arm = H.quietArm(UMARO, 0x09),
    -- (the buffs are set after "Power 100 times up!" and its four lines: up to 2,400 frames)
    settle = 2400, settled = function(W) return (H.readByte(0x3EF8 + W.ent()) & BUFFS) == BUFFS end,
    landed = function(W, l, m)
      local e = W.ent()
      local st3 = H.readByte(0x3EF8 + e)
      H.log(string.format("[umaro] landed: the line at f%d; the cherry dispatched at f%d; his HP %d, his status 3 $%02X "
        .. "now; battle switches $%02X", l.f, m.f, H.readWord(0x3BF4 + e), st3, H.readByte(0x3EB0)))
      H.assertEq(st3 & BUFFS, BUFFS, "umaro landed: the cherry landed (Protect, Shell and Haste on him)")
      H.assertEq(H.readByte(0x3EB0) & 0x05, 0x01, "umaro landed: battle switch 0 (eaten) set and 2 (announced) clear")
    end,
  }),
  H.fuseRestore(S, "umaro"),
  H.fuseCases({
    tag = "umaro", species = UMARO, write = WRITE,
    line = LINE, move = { cmd = 0x01, atk = CHERRY }, turns = 1,
    lineText = "He digs out a Green Cherry!{wait}",
    arm = "idle", aim = true, plainBreaker = true,
    bossHp = 9000, outsideHp = 12000,
    -- above the line (the outside case's HP), no line yet
    partway = function(W)
      local c = W.cells()
      return c ~= nil and not W.litBit() and c.hp >= 10240
    end,
    never = { turns = 4, check = function(C, W)
      local post = C.brk.post
      H.log(string.format("[umaro] battle switches at the break $%02X, after the cancel $%02X, now $%02X; his status "
        .. "3 now $%02X", C.brk.pre.bsw, post.bsw, H.readByte(0x3EB0), H.readByte(0x3EF8 + W.ent())))
      H.assertEq(C.brk.pre.bsw & 0x04, 0x04, "umaro: battle switch 2 (announced) stood at the break")
      H.assertEq(post.bsw & 0x04, 0, "umaro: battle switch 2 is clear after the cancel")
      H.assertEq(post.bsw & 0x01, 0x01, "umaro: battle switch 0 is set after the cancel (the cherry is gone)")
      H.assertEq(H.readByte(0x3EF8 + W.ent()) & 0x08, 0, "umaro: no Haste on him four turns on: the cherry was not "
        .. "eaten")
    end },
    outside = function(C, W)
      H.assertEq(C.brk.post.bsw & 0x01, 0, "umaro: a break before the line sets no battle switch 0 (the cherry is "
        .. "still his)")
    end,
  }),
  H.logStep("[umaro] PASS: the announce, the cherry, the cancel that takes it for the fight, and a break before the "
    .. "line that takes nothing"),
})
