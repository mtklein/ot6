-- @suite
-- battle_levelup.lua -- v0.4 gate: FULL HP/MP RESTORE ON LEVEL UP.
--
--   tools/tests/run.sh tools/tests/battle_levelup.lua
--
-- The mechanic (docs/design/mp-economy.md "Full HP/MP restore on level up"):
-- when a character gains a level, current HP and MP refill to the new maxima.
-- OT6 implements it as a jsl at the tail of vanilla DoLevelUp
-- (battle_main.asm) into Ot6LevelUpHeal (ff6/src/battle/ot6.asm), which writes
-- the battle current-HP/MP cells ($3bf4,y / $3c08,y) -- NOT the $1600 record --
-- because the victory sequence copies those battle cells back over the record
-- (UpdateSRAM, battle_main.asm:12136-12141) right after WinBattle returns.
--
-- Both scenarios drive a REAL victory through clearBattle's kill-bit idiom, so
-- WinBattle -> CheckLevelUp -> DoLevelUp -> Ot6LevelUpHeal -> UpdateSRAM all run
-- for real; the assertions read the persistent $1600 record afterwards.
--
--   POSITIVE  slot-0 character damaged (HP 1) and MP-emptied, XP pinned one
--             threshold over -> after the win: leveled, and current HP/MP equal
--             the NEW maxima.  A record sentinel ($3FFF, an impossible real HP)
--             is planted first, so "record == new max" also proves UpdateSRAM
--             actually ran -- a quiet win that skipped the reward path would
--             leave the sentinel and fail loudly (CONTRIBUTING: a quiet test is
--             not a passing test).
--   NEGATIVE  same character damaged (HP 7 / MP 3), but level bumped to 50 with
--             XP 0 so the win's award cannot cross a threshold -> after the win:
--             level unchanged and HP/MP left at the damaged values, un-restored.
--             The battle cells (7/3), not the sentinel, must survive into the
--             record -- again proving the reward path ran while NOT refilling.
--
-- Exit codes: 0 = both scenarios pass, 1 = any assert failed / Lua error.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/first_battle.mss.lua"

-- $1600 character record fields (field-ram.txt:885-898); add the slot's record
-- pointer ($3010,slot*2) to each.  Battle cells ($3bf4/$3c08) index by slot*2.
local REC_PTR      = 0x3010
local LEVEL        = 0x1608
local CURHP, MAXHP = 0x1609, 0x160b
local CURMP, MAXMP = 0x160d, 0x160f
local XP           = 0x1611          -- 3-byte experience total
local BHP, BMP     = 0x3bf4, 0x3c08
local SLOT         = 0               -- first party member

local SENTINEL = 0x3fff              -- impossible real HP/MP; planted in the
                                     -- record to detect whether UpdateSRAM ran

-- vanilla XP thresholds: CheckLevelUp (battle_main.asm) needs
-- 8 * sum(LevelUpExp[0..L-1]) total XP to leave level L.  Table is
-- ff6/src/field/event.asm:1330 (upstream vanilla data; first 16 levels suffice
-- for the opening-battle roster).
local LEVELUP_EXP = { 4,8,14,24,34,48,62,79, 99,120,143,169,195,224,257,289 }
local function neededXp(L)
  assert(L >= 1 and L <= #LEVELUP_EXP,
    "fixture level " .. L .. " outside the embedded threshold table")
  local s = 0
  for i = 1, L do s = s + LEVELUP_EXP[i] end
  return 8 * s
end

local rec                            -- slot-0 record pointer, resolved in battle
local function ra(field) return field + rec end
local function setXp(v)
  H.writeByte(ra(XP),     v         & 0xff)
  H.writeByte(ra(XP) + 1, (v >> 8)  & 0xff)
  H.writeByte(ra(XP) + 2, (v >> 16) & 0xff)
end

local pos = {}                       -- carries starting stats across the win

H.run({ maxFrames = 60000 }, {
  ---------------------------------------------------------------- POSITIVE --
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (pos)", 30),
  H.call(function()
    rec = H.readWord(REC_PTR + SLOT * 2)
    pos.level = H.readByte(ra(LEVEL))
    local mhp = H.readWord(ra(MAXHP))
    local mmp = H.readWord(ra(MAXMP))
    -- precondition: no HP/MP-boost relic, so effective max == the low-14-bit
    -- base and "current == (max & $3fff)" is the exact full-refill check.
    H.assertEq(mhp & 0xc000, 0, "slot-0 max HP carries no boost tier (pos)")
    H.assertEq(mmp & 0xc000, 0, "slot-0 max MP carries no boost tier (pos)")
    -- go in damaged and MP-spent; plant the record sentinel.
    H.writeWord(BHP + SLOT * 2, 1)          -- battle current HP: near-dead
    H.writeWord(BMP + SLOT * 2, 0)          -- battle current MP: empty
    H.writeWord(ra(CURHP), SENTINEL)        -- record sentinel (UpdateSRAM proof)
    H.writeWord(ra(CURMP), SENTINEL)
    local xp = neededXp(pos.level) + 4      -- one threshold over -> ~one level
    setXp(xp)
    H.log(string.format(
      "[levelup+] slot0 rec=$%03X L=%d maxHP=%d maxMP=%d xp:=%d (need %d)",
      rec, pos.level, mhp & 0x3fff, mmp & 0x3fff, xp, neededXp(pos.level)))
  end),
  H.clearBattle(14000),
  H.waitFrames(30),
  H.call(function()
    local L1  = H.readByte(ra(LEVEL))
    local chp = H.readWord(ra(CURHP))
    local mhp = H.readWord(ra(MAXHP)) & 0x3fff
    local cmp = H.readWord(ra(CURMP))
    local mmp = H.readWord(ra(MAXMP)) & 0x3fff
    H.log(string.format("[levelup+] after win: L %d->%d  HP %d/%d  MP %d/%d",
      pos.level, L1, chp, mhp, cmp, mmp))
    H.assertEq(L1 > pos.level, true, "slot-0 gained at least one level")
    H.assertEq(chp, mhp, "HP refilled to the NEW max on level up")
    H.assertEq(cmp, mmp, "MP refilled to the NEW max on level up")
  end),

  ---------------------------------------------------------------- NEGATIVE --
  H.loadState(STATE),
  H.waitFrames(10),
  H.waitUntil(function() return H.battleActive() end, 900, "battle active (neg)", 30),
  H.call(function()
    rec = H.readWord(REC_PTR + SLOT * 2)
    local mhp = H.readWord(ra(MAXHP)) & 0x3fff
    local mmp = H.readWord(ra(MAXMP)) & 0x3fff
    local DHP, DMP = 7, 3
    H.assertEq(DHP < mhp, true, "damaged HP below max (control is meaningful)")
    H.assertEq(DMP < mmp, true, "damaged MP below max (control is meaningful)")
    H.writeWord(BHP + SLOT * 2, DHP)        -- battle cells: what UpdateSRAM keeps
    H.writeWord(BMP + SLOT * 2, DMP)
    H.writeWord(ra(CURHP), SENTINEL)        -- record sentinel (UpdateSRAM proof)
    H.writeWord(ra(CURMP), SENTINEL)
    H.writeByte(ra(LEVEL), 50)              -- huge threshold; XP 0 can't cross
    setXp(0)
    H.log(string.format("[levelup-] slot0 rec=$%03X L:=50 xp:=0  damaged HP=%d MP=%d",
      rec, DHP, DMP))
  end),
  H.clearBattle(14000),
  H.waitFrames(30),
  H.call(function()
    local L1  = H.readByte(ra(LEVEL))
    local chp = H.readWord(ra(CURHP))
    local cmp = H.readWord(ra(CURMP))
    H.log(string.format("[levelup-] after win: L=%d  curHP=%d  curMP=%d", L1, chp, cmp))
    H.assertEq(L1, 50, "no level gained (negative control)")
    H.assertEq(chp, 7, "HP left un-restored without a level up")
    H.assertEq(cmp, 3, "MP left un-restored without a level up")
    H.log("[levelup] both scenarios passed")
  end),
})
