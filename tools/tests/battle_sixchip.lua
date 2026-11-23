-- @suite slow
-- battle_sixchip.lua -- each of the six weapon classes chips and reveals, and
-- shows its own "Weak against ..." line (#566).
--
-- For each class -- Sword $01, Dagger $02, Blunt $04, Ranged $08, Katana $10,
-- Spear $20 -- a member of a party the line really fields makes one real
-- attack of that class through the battle menu (H.kitBattle: an unboosted
-- Fight with the weapon in the hand, or a Tools row), twice, each time from a
-- whole-machine snapshot of the battle:
--
--   weak   at a body whose class row ($3EA4 + 2*slot) holds the class.  Each
--          landed hit takes exactly one shield, written by Ot6ClassChip; the
--          body's revealed byte ($3EA5 + 2*slot) gains exactly that class's
--          bit, first written by the hit's own event (Ot6EvApply, whose class
--          byte keeps the pin mark in bits 6-7: the mark shown stays 0); the
--          save's codex byte for the species gains exactly that bit;
--          Ot6ClassMsg loads the class's message ($45 swords, $46 daggers,
--          $47 blunt, $48 ranged, $4A katanas, $4B spears), the battle script
--          shows that message (GfxCmd_02's GetAttackMsgPtr), its text in the
--          ROM is "Weak against <class>", and no other class's line shows;
--          and the body's HUD line turns the class's '?' into the class's
--          glyph (sword $D9, dagger $D8, blunt $DC, ranged $DE, katana $DB,
--          spear $DA), read from the BG3 tilemap in VRAM.
--   cold   the same attack at a body whose row lacks the class: a hit of
--          that class lands (so the control is not an empty run), no shield
--          moves, no revealed byte and no codex byte changes, Ot6ClassMsg
--          loads nothing and no "Weak against" line shows.
--
-- The design's numbers (the class bits, messages, glyph cells, lines) are
-- written once, in CLASSES below; everything else is read from the built ROM
-- and the live battle: who holds a weapon of the class (Ot6WeapClassTbl over
-- the hands, H.handClass; else a Tools owner with a tool of the class in the
-- bag), which body is weak to it (the row the seed gave it), the formation.
-- No species row is pinned: the visits below are where the line fields each
-- class, and the log says what each run's rows gave.
--   sword   vargas_entry    a sword in a hand, at VARGAS's fight
--   ranged  vargas_entry    EDGAR's AutoCrossbow (Tools), at VARGAS once he
--                           stands alone (the tool reaches every monster)
--   blunt   vargas_entry    a member whose weapon went back to the bag
--                           through Equip -> Rmove: an empty hand is Blunt
--                           (Ot6WeapClassTbl[$FF]; GAU's is not: battle_sixgau)
--   dagger  kolts_cave      a dagger in a hand (or put there from the bag,
--                           through Equip); the cave's first encounter
--   spear   ultros1_entry   a spear in a hand, at ULTROS
--   katana  cyan_defence    CYAN's katana at the Doma soldiers
-- At VARGAS's fight the target select does not reach him while an Ipooh
-- stands, so a side that needs him is played from a second snapshot, taken
-- once the party has fought both Ipoohs down; which side that is follows the
-- two species' rows as the battle seeded them.
--
-- Staging, declared (tools/state_write_waivers.txt).  A formation does not
-- always hold both bodies: one ULTROS cannot be weak and not weak to the same
-- class, two Soldiers share a row.  Where the live formation has no body on
-- one side, that side is staged on a standing body by writing its class row
-- (the class's bit set for `weak`, cleared for `cold`) after the snapshot is
-- restored; the log's `[six] <class> <side>: natural` / `staged` line says
-- which, and the suite ends red unless every class had a natural body on at
-- least one side.  A class the save's codex already knew for the body's
-- species (an earlier fight of the line's taught it) is forgotten the same
-- way first, revealed bytes and codex byte, so the reveal under test is a
-- first reveal.  Nothing else is written: the command, the swing, the chip,
-- the reveal, the codex and the message are the game's own.
--
-- What it relies on other suites for: the species' rows themselves
-- (battle_breaktbl, battle_breakwob_*, tools/check_shield_rows.py), every
-- weapon's class byte (tools/check_six_classes.py), a reveal's timing against
-- its numeral (battle_reveal), the break at zero shields (battle_break), the
-- null-break and heal gates (battle_class), the pin mark (battle_shadowpin_*).
--
-- OT6_LEVERS=SIX_SWORD,... (a lab's or a mutant run's lever) plays only the
-- classes named; the graph never sets it.
-- Mutants and the runs behind this file: build/attempts/wt/v051-six-classes/newsuites/.
local H = dofile("tools/tests/lib/ot6.lua")

-- ---- the design ------------------------------------------------------------
local CLASSES = {
  { bit = 0x01, name = "sword",  msg = 0x45, text = "Weak against swords",  glyph = 0xD9 },
  { bit = 0x02, name = "dagger", msg = 0x46, text = "Weak against daggers", glyph = 0xD8 },
  { bit = 0x04, name = "blunt",  msg = 0x47, text = "Weak against blunt",   glyph = 0xDC },
  { bit = 0x08, name = "ranged", msg = 0x48, text = "Weak against ranged",  glyph = 0xDE },
  { bit = 0x10, name = "katana", msg = 0x4A, text = "Weak against katanas", glyph = 0xDB },
  { bit = 0x20, name = "spear",  msg = 0x4B, text = "Weak against spears",  glyph = 0xDA },
}
local BY_NAME, CLASS_MSG = {}, {}
for _, c in ipairs(CLASSES) do BY_NAME[c.name] = c; CLASS_MSG[c.msg] = c.name end
local TERRA, LOCKE, CYAN, EDGAR = 0, 1, 2, 4
local CMD_FIGHT, CMD_TOOLS = 0x00, 0x09
local QMARK, WHITE = 0xBF, H.HUD_GAUGE_ATTR

local only = {}
for _, c in ipairs(CLASSES) do
  if H.lever("SIX_" .. c.name:upper()) then only[c.name] = true; only.any = true end
end
local function wanted(name) return not only.any or only[name] == true end

-- ---- the ROM's symbols and the battle's cells -------------------------------
local SH_CUR, ROW, REV = 0x3E40, 0x3EA4, 0x3EA5       -- per monster slot, stride 2
local SPECIES = H.sym("OT6_SPECIES")                  -- a word per slot
local ATKCLASS, SHOWN, SHADOW = H.sym("OT6_ATKCLASS"), H.sym("OT6_SHOWN"), H.sym("OT6_SHADOW")
local CODEX_CLASS, CODEX_TEMP = H.sym("OT6_CODEX_CLASS"), H.sym("OT6_CODEX_TEMP")
local P_CHIP, P_CHIP_END = H.sym("Ot6ClassChip"), H.sym("Ot6ClassMsgTbl")
local P_MSG, P_MSG_END = H.sym("Ot6ClassMsg"), H.sym("Ot6RevealCommit")
local P_EVAPPLY, P_COMMIT, P_END = H.sym("Ot6EvApply"), H.sym("Ot6RevealCommit"), H.sym("Ot6ActionEnd")
local P_SHOW = H.sym("GetAttackMsgPtr")
assert(P_CHIP < P_CHIP_END and P_CHIP_END - P_CHIP < 0x100, "Ot6ClassMsgTbl follows Ot6ClassChip (the chip's pc range)")
assert(P_MSG < P_MSG_END and P_MSG_END - P_MSG < 0x40, "Ot6RevealCommit follows Ot6ClassMsg (the message load's pc range)")

local function species(s) return H.readWord(SPECIES + s * 2) end
local function shields(s) return H.readByte(SH_CUR + s * 2) end
local function row(s) return H.readByte(ROW + s * 2) end
local function rev(s) return H.readByte(REV + s * 2) end
local function mhp(s) return H.readWord(0x3BFC + s * 2) end
local function broken(s) return H.readByte(0x3E90 + s * 2) ~= 0 end
local function weakElems(s) return H.readByte(0x3BE8 + s * 2) end
local function standing(s)
  return (H.readByte(0x3AA8 + s * 2) & 1) == 1 and mhp(s) > 0 and (H.readByte(0x3A75) >> s) & 1 == 1
end
local function bits(v) local n = 0; while v ~= 0 do n = n + (v & 1); v = v >> 1 end; return n end
-- the save's class codex byte for a species (Ot6CodexActive: the page of the
-- slot loaded, $021F 1..3, else the transient page)
local function codexAddr(sp)
  local slot = H.readByte(0x021F)
  local page = (slot >= 1 and slot <= 3) and (slot - 1) * 0x400 or CODEX_TEMP
  return CODEX_CLASS + page + sp
end
local function codex(sp) return emu.read(codexAddr(sp), emu.memType.snesMemory) end

-- an attack message's text in the ROM, as letters
local function msgText(id)
  local ptrs, base = H.sym("AttackMsgPtrs") & 0x3FFFFF, H.sym("AttackMsg") & 0x3F0000
  local p, out = base | H.readRomWord(ptrs + id * 2), {}
  for i = 0, 40 do
    local b = H.readRomByte(p + i)
    if b == 0x00 then break end
    if b >= 0x80 and b <= 0x99 then out[#out + 1] = string.char(65 + b - 0x80)
    elseif b >= 0x9A and b <= 0xB3 then out[#out + 1] = string.char(97 + b - 0x9A)
    elseif b == 0xFF or b == 0xFE then out[#out + 1] = " "
    else out[#out + 1] = string.format("{%02X}", b) end
  end
  return table.concat(out)
end

-- a body's HUD line as the screen has it: the four weakness cells after the
-- count (the BG3 tilemap words at the line's anchor + 1..4), nil while the
-- line is off
local function hudCells(s)
  local addr = H.readWord(SHADOW + s * 14)
  if addr == 0 then return nil end
  local t = {}
  for i = 1, 4 do t[i] = emu.readWord((addr + i) * 2, emu.memType.snesVideoRam) end
  return t
end
local function hudText(t)
  if t == nil then return "off" end
  local p = {}
  for i = 1, 4 do p[i] = string.format("%04X", t[i]) end
  return table.concat(p, " ")
end
-- which weakness cell a class takes on a body: its elements first, then its
-- classes in bit order (ot6_hud.asm @slots); 1..4, or more when the line has
-- no cell left for it.  A body every class breaks has one cell for them all,
-- the any-weapon mark (ot6_hud.asm @cls).
local ALL, ANYWEAPON = 0x3F, 0xDF
local function everyClass(s) return (row(s) & ALL) == ALL end
local function hudCellOf(s, bit)
  if everyClass(s) then return bits(weakElems(s)) + 1 end
  return bits(weakElems(s)) + bits(row(s) & (bit - 1)) + 1
end

-- ---- what one attack did, read at the ROM's own stores ----------------------
local rec = nil          -- the record of the branch being played, nil outside one
local lastWriter = "none"
local function pcNow()
  local st = emu.getState()
  return ((st["cpu.k"] & 0xFF) << 16) | (st["cpu.pc"] & 0xFFFF), st
end
local function armWatches()
  -- every landed hit passes Ot6ClassChip (Ot6HitJoin): x = attacker, y = target
  emu.addMemoryCallback(function()
    if rec == nil then return end
    local st = emu.getState()
    local x, y = st["cpu.x"] & 0xFF, st["cpu.y"] & 0xFF
    if x ~= rec.actor * 2 or y < 8 then return end
    local s = (y - 8) // 2
    rec.passes[#rec.passes + 1] = { slot = s, cls = H.readByte(ATKCLASS), sh = shields(s),
      elems = H.readByte(0x11A1) & H.readByte(0x3BE0 + y), brk = broken(s), f = H.frame }
  end, emu.callbackType.exec, P_CHIP, P_CHIP)
  -- a shield written from inside Ot6ClassChip is one class chip
  emu.addMemoryCallback(function(addr)
    if rec == nil or (addr - 0x7E0000 - SH_CUR) % 2 ~= 0 then return end
    local pc = pcNow()
    local s = (addr - 0x7E0000 - SH_CUR) // 2
    if pc >= P_CHIP and pc < P_CHIP_END then rec.chips[s] = (rec.chips[s] or 0) + 1
    else rec.otherShield[s] = (rec.otherShield[s] or 0) + 1 end
  end, emu.callbackType.write, 0x7E0000 + SH_CUR, 0x7E0000 + SH_CUR + 11)
  -- the message Ot6ClassMsg loads
  emu.addMemoryCallback(function(_, value)
    if rec == nil then return end
    local pc = pcNow()
    if pc >= P_MSG and pc < P_MSG_END then rec.loaded[#rec.loaded + 1] = value end
  end, emu.callbackType.write, 0x7E3401, 0x7E3401)
  -- the message the battle script shows: GfxCmd_02's index, ($76),1
  emu.addMemoryCallback(function()
    if rec == nil then return end
    local id = H.readByte(H.readWord(0x76) + 1)
    rec.shown[#rec.shown + 1] = id
    if rec.shotAt == nil and id == rec.class.msg then rec.shotAt = H.frame + 20 end
  end, emu.callbackType.exec, P_SHOW, P_SHOW)
  -- who writes a revealed byte: the hit's event, or the end-of-action commit
  emu.addMemoryCallback(function() lastWriter = "event" end, emu.callbackType.exec, P_EVAPPLY, P_EVAPPLY)
  emu.addMemoryCallback(function() lastWriter = "commit" end, emu.callbackType.exec, P_COMMIT, P_COMMIT)
  emu.addMemoryCallback(function(addr, value)
    if rec == nil or (addr - 0x7E0000 - REV) % 2 ~= 0 then return end
    local s = (addr - 0x7E0000 - REV) // 2
    if s == rec.slot and (value & rec.class.bit) ~= 0 and rec.revealedBy == nil then
      rec.revealedBy, rec.revealedAt = lastWriter, H.frame
    end
  end, emu.callbackType.write, 0x7E0000 + REV, 0x7E0000 + REV + 10)
  -- the mark each hit's event leaves shown (the odd byte of OT6_SHOWN)
  emu.addMemoryCallback(function(addr, value)
    if rec == nil or (addr - 0x7E0000 - SHOWN) % 2 ~= 1 then return end
    if value > rec.mark then rec.mark = value end
  end, emu.callbackType.write, 0x7E0000 + SHOWN, 0x7E0000 + SHOWN + 11)
  -- the actor's action is over
  emu.addMemoryCallback(function()
    if rec == nil or rec.endFrame ~= nil or rec.confirmAt == nil then return end
    if (emu.getState()["cpu.x"] & 0xFF) == rec.actor * 2 then rec.endFrame = H.frame end
  end, emu.callbackType.exec, P_END, P_END)
end

-- ---- the battle as it opens --------------------------------------------------
local B = {}             -- the visit's battle: blob, formation text
local RESULT = {}        -- per class: { weak = "natural"/"staged", cold = ..., hud = bool }

local function formationText()
  local p = {}
  for s = 0, 5 do
    if standing(s) then
      p[#p + 1] = string.format("s%d:$%03X row$%02X rev$%02X sh%d hp%d elems$%02X", s, species(s), row(s), rev(s),
        shields(s), mhp(s), weakElems(s))
    end
  end
  return table.concat(p, ", ")
end
local function bagHas(id)
  for q = 0, 255 do
    if H.readByte(0x1869 + q) == id and H.readByte(0x1969 + q) > 0 then return true end
  end
  return false
end
local function cmdRow(e, cmd)
  for r = 0, 3 do if H.readByte(0x202E + e * 12 + r * 3) == cmd then return r end end
  return nil
end
local function seated(e)
  return H.readByte(0x3ED8 + e * 2) < 16 and (H.readByte(0x3AA0 + e * 2) & 1) == 1
    and (H.readByte(0x3EE4 + e * 2) & 0xC2) == 0
end
-- an attack of the class this party can make now: a seated member's Fight
-- with a main hand of the class (an empty hand has the fist's, GAU's the
-- fangs': H.handClass), else a Tools owner's row for a tool of the class in
-- the bag that his MP pays (Ot6AbilityCostTbl: the confirm refuses a row the
-- pool cannot cover; EDGAR reaches ULTROS with 1 MP on main's line,
-- build/attempts/wt/v051-six-classes/newsuites/dev/chip5.log).  nil when the
-- party has neither.
local function attackFor(bit)
  for e = 0, 3 do
    if seated(e) and cmdRow(e, CMD_FIGHT) then
      local c, r = H.readByte(0x3ED8 + e * 2), H.readByte(0x3CA8 + e * 2)
      if H.handClass(c, r, (H.readByte(0x3EF9 + e * 2) & 1) ~= 0) == bit then
        return { e = e, c = c, cmd = CMD_FIGHT, item = r, what = string.format("Fights with hand $%02X", r) }
      end
    end
  end
  for e = 0, 3 do
    if seated(e) and cmdRow(e, CMD_TOOLS) then
      for id = 0xA3, 0xAA do
        if H.weaponClass(id) == bit and bagHas(id) and (H.abilityCost(id) or 0) <= H.readWord(0x3C08 + e * 2) then
          return { e = e, c = H.readByte(0x3ED8 + e * 2), cmd = CMD_TOOLS, row = id, item = id,
            what = string.format("uses Tools row $%02X", id) }
        end
      end
    end
  end
  return nil
end
local function canAim(s) return B.canAim == nil or B.canAim(s) end
local function pickBody(bit, wantWeak)
  local best = nil
  for s = 0, 5 do
    if standing(s) and canAim(s) and shields(s) > 0 and not broken(s)
       and ((row(s) & bit) ~= 0) == wantWeak and (best == nil or mhp(s) > mhp(best)) then
      best = s
    end
  end
  return best
end

local SETTLE, TRIES = 200, 5
-- one branch: restore the opening, stage what the formation lacks, attack,
-- and hold the result to `side`'s rule
local function branch(cls, side)
  local plan = { { who = 0, cmd = CMD_FIGHT, boost = 0, slot = 0 } }
  local r = nil
  local steps = {
    H.call(function()
      -- (a visit with two snapshots says which one this side is played from)
      local when = B.whenFor and B.whenFor(cls.bit, side == "weak") or "blob"
      -- (a Tools row reaches every monster: played from the snapshot where one stands, when the visit has one)
      local atk = attackFor(cls.bit)
      if atk ~= nil and atk.cmd == CMD_TOOLS and B.late ~= nil then when = "late" end
      B.load = H.requestLoadState(B[when])
    end),
    H.waitFrames(3),
    H.call(function() H.checkReq(B.load, cls.name .. " " .. side .. ": the opening restored") end),
    H.waitUntil(function() return H.battleActive() end, 900, "the battle is up again", 5),
    H.waitFrames(20),
    H.call(function()
      local bit = cls.bit
      local atk = attackFor(bit)
      H.assertEq(atk ~= nil, true, string.format("the party can make a %s attack: a main hand of the class, or a "
        .. "Tools owner with a tool of it in the bag and the MP for it (hands: %s)", cls.name, (function()
          local p = {}
          for q = 0, 3 do p[#p + 1] = string.format("c%d:$%02X", H.readByte(0x3ED8 + q * 2), H.readByte(0x3CA8 + q * 2)) end
          return table.concat(p, " ")
        end)()))
      local e, c, item = atk.e, atk.c, atk.item
      local wantWeak = side == "weak"
      local s, how = pickBody(bit, wantWeak), "natural"
      if s == nil then
        -- staged: the live formation has no body on this side
        s = pickBody(bit, not wantWeak)
        H.assertEq(s ~= nil, true, "a shielded, unbroken body stands to stage the class row on")
        local was = row(s)
        H.writeByte(ROW + s * 2, wantWeak and (was | bit) or (was & ~bit & 0xFF))
        how = string.format("staged (slot %d's class row $%02X -> $%02X, a declared write)", s, was, row(s))
      end
      RESULT[cls.name] = RESULT[cls.name] or {}
      RESULT[cls.name][side] = how == "natural" and "natural" or "staged"
      local sp = species(s)
      if wantWeak and ((rev(s) | codex(sp)) & bit) ~= 0 then
        -- the save already knew it: forgotten, so this is a first reveal
        for q = 0, 5 do
          if species(q) == sp then H.writeByte(REV + q * 2, rev(q) & ~bit & 0xFF) end
        end
        emu.write(codexAddr(sp), codex(sp) & ~bit & 0xFF, emu.memType.snesMemory)
        H.log(string.format("[six] %s weak: species $%03X's %s was already in the codex -- forgotten (declared "
          .. "writes: revealed bytes, codex byte) so the reveal is a first one", cls.name, sp, cls.name))
      end
      H.log(string.format("[six] %s %s: %s -- c%d (seat %d) %s at slot %d ($%03X row $%02X rev $%02X "
        .. "shields %d hp %d); formation: %s", cls.name, side, how, c, e, atk.what, s, sp, row(s), rev(s), shields(s),
        mhp(s), formationText()))
      H.assertEq((row(s) & bit) ~= 0, wantWeak, string.format("the body's class row %s the %s bit", wantWeak
        and "holds" or "lacks", cls.name))
      plan[1].who, plan[1].cmd, plan[1].row, plan[1].slot = c, atk.cmd, atk.row, s
      if atk.cmd == CMD_TOOLS then
        -- a tool's reach is its own (the AutoCrossbow's is every monster): played where one body stands
        local n = 0
        for q = 0, 5 do if standing(q) then n = n + 1 end end
        H.assertEq(n, 1, "a Tools row is played where one body stands")
        plan[1].slot = nil
      end
      r = { class = cls, side = side, actor = e, slot = s, sp = sp, passes = {}, chips = {}, otherShield = {},
        loaded = {}, shown = {}, mark = 0, sh0 = shields(s), codex0 = {}, rev0 = {}, shAll0 = {} }
      for q = 0, 5 do r.rev0[q], r.shAll0[q], r.codex0[q] = rev(q), shields(q), codex(species(q)) end
      rec = r
    end),
    H.waitFrames(12),                  -- (the HUD line rebuilt from a staged row)
    H.call(function() r.hud0 = hudCells(r.slot) end),
  }
  -- the attack, again while it has not landed (a swing can miss)
  for try = 1, TRIES do
    steps[#steps + 1] = H.cond(function() return #r.passes == 0 and H.battleLoadStarted() end, {
      H.call(function() r.endFrame, r.confirmAt = nil, nil end),
      H.kitBattle(plan, { idle = "defend", care = false, untilPlanDone = true, maxFrames = 9000,
        planDone = function()
          -- (asked only once the entry is confirmed: the action that ends after this is the Fight)
          if r.confirmAt == nil then r.confirmAt = H.frame end
          if type(r.shotAt) == "number" and H.frame >= r.shotAt then
            r.shotAt = false
            H.screenshot("sixchip_" .. cls.name .. "_msg")
          end
          return r.endFrame ~= nil and H.frame - r.endFrame >= SETTLE
        end }),
      H.call(function()
        if #r.passes == 0 then H.log(string.format("[six] %s %s: try %d did not land", cls.name, side, try)) end
      end),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    rec = nil
    local bit, s, name = cls.bit, r.slot, cls.name .. " " .. side
    local onBody, classes = 0, {}
    for _, p in ipairs(r.passes) do
      if p.slot == s then
        onBody = onBody + 1
        classes[#classes + 1] = string.format("$%02X", p.cls)
        H.assertEq(p.cls, bit, name .. ": the hit that landed on the body carried the class (OT6_ATKCLASS at "
          .. "Ot6ClassChip)")
        H.assertEq(p.elems, 0, name .. ": the hit carried no element the body is weak to (so no element chip "
          .. "moves the gauge beside the class's)")
      end
    end
    local shown, loaded = {}, {}
    for _, id in ipairs(r.shown) do shown[#shown + 1] = string.format("$%02X", id) end
    for _, id in ipairs(r.loaded) do loaded[#loaded + 1] = string.format("$%02X", id) end
    local alive = standing(s)
    H.log(string.format("[six] %s: %d hit(s) landed on slot %d (class %s); shields %d -> %d, Ot6ClassChip wrote the "
      .. "gauge %d time(s), other writers %d; revealed $%02X -> $%02X (first by %s); codex[$%03X] $%02X -> $%02X; "
      .. "Ot6ClassMsg loaded [%s]; shown [%s]; mark shown %d; body %s; HUD cells %s -> %s", name, onBody, s,
      table.concat(classes, " "), r.sh0, shields(s), r.chips[s] or 0, r.otherShield[s] or 0, r.rev0[s], rev(s),
      tostring(r.revealedBy), r.sp, r.codex0[s], codex(r.sp), table.concat(loaded, " "), table.concat(shown, " "),
      r.mark, alive and "stands" or "fell", hudText(r.hud0), hudText(hudCells(s))))
    H.assertEq(onBody >= 1, true, string.format("%s: a %s hit landed on the body within %d attacks", name,
      cls.name, TRIES))
    H.assertEq(r.mark, 0, name .. ": no hit's event showed a pin mark (the class bits stay out of the event "
      .. "byte's mark bits 6-7)")
    if side == "weak" then
      local take = math.min(onBody, r.sh0)
      H.assertEq(r.chips[s] or 0, take, name .. ": Ot6ClassChip took one shield a landed hit")
      H.assertEq(shields(s), r.sh0 - take, name .. ": the body's shields fell by exactly that")
      H.assertEq(r.otherShield[s] or 0, 0, name .. ": nothing else wrote the body's gauge")
      H.assertEq(rev(s) & ~r.rev0[s] & 0xFF, bit, name .. ": the revealed byte gained exactly the class's bit")
      H.assertEq(r.revealedBy, "event", name .. ": the bit was first written by the hit's own event (Ot6EvApply), "
        .. "not left to the end-of-action commit")
      H.assertEq(codex(r.sp) & ~r.codex0[s] & 0xFF, bit, name .. ": the species' codex byte gained exactly the "
        .. "class's bit")
      H.assertEq(codex(r.sp), r.rev0[s] | bit, name .. ": the codex byte is what the body shows now (the "
        .. "classes it showed and this one)")
      for q = 0, 5 do
        if q ~= s and species(q) == r.sp then
          H.assertEq(rev(q) & bit, bit, string.format("%s: slot %d, the same species, shows it too", name, q))
        elseif q ~= s then
          H.assertEq(rev(q), r.rev0[q], string.format("%s: slot %d, another species, shows nothing new", name, q))
          H.assertEq(codex(species(q)), r.codex0[q], string.format("%s: slot %d's species' codex is untouched", name, q))
        end
        if q ~= s then
          H.assertEq(r.chips[q] or 0, 0, string.format("%s: no class chip on slot %d", name, q))
        end
      end
      H.assertEq(#r.loaded, 1, name .. ": Ot6ClassMsg loaded one message")
      H.assertEq(r.loaded[1], cls.msg, string.format("%s: it is the class's ($%02X)", name, cls.msg))
      local mine, others = 0, 0
      for _, id in ipairs(r.shown) do
        if id == cls.msg then mine = mine + 1 elseif CLASS_MSG[id] then others = others + 1 end
      end
      H.assertEq(mine, 1, string.format("%s: the battle script showed message $%02X once", name, cls.msg))
      H.assertEq(others, 0, name .. ": and no other class's line")
      H.assertEq(msgText(cls.msg), cls.text, string.format("%s: message $%02X reads the class's line", name, cls.msg))
      -- the HUD: the class's cell, on the body or (if the hit felled it) on
      -- a standing body of its species
      local at = alive and s or nil
      for q = 0, 5 do
        if at == nil and standing(q) and species(q) == r.sp and (row(q) & bit) ~= 0 then at = q end
      end
      local cell = at and hudCellOf(at, bit) or nil
      if at ~= nil and cell <= 4 and hudCells(at) ~= nil then
        local w = hudCells(at)[cell]
        if at == s and r.hud0 ~= nil then
          H.assertEq(r.hud0[cell], (H.HUD_QMARK_ATTR << 8) | QMARK, string.format("%s: before the hit the HUD's "
            .. "weakness cell %d was the grey '?'", name, cell))
        end
        local glyph = everyClass(at) and ANYWEAPON or cls.glyph
        H.assertEq(w, (WHITE << 8) | glyph, string.format("%s: after it, cell %d of slot %d's HUD line is the "
          .. "%s glyph $%02X, white", name, cell, at, everyClass(at) and "any-weapon" or cls.name, glyph))
        RESULT[cls.name].hud = true
        H.screenshot("sixchip_" .. cls.name .. "_hud")
      else
        H.log(string.format("[six] %s: the HUD cell was not read -- %s", name, at == nil
          and "no body of the species stands" or cell > 4 and string.format("the class would take weakness cell %d "
          .. "and the line has four", cell) or "the line is off"))
      end
    else
      H.assertEq(r.chips[s] or 0, 0, name .. ": Ot6ClassChip took nothing")
      for q = 0, 5 do
        H.assertEq(shields(q), r.shAll0[q], string.format("%s: slot %d's shields did not move", name, q))
        H.assertEq(rev(q), r.rev0[q], string.format("%s: slot %d's revealed byte did not change", name, q))
        H.assertEq(codex(species(q)), r.codex0[q], string.format("%s: slot %d's species' codex did not change", name, q))
      end
      H.assertEq(#r.loaded, 0, name .. ": Ot6ClassMsg loaded nothing")
      local lines = 0
      for _, id in ipairs(r.shown) do if CLASS_MSG[id] then lines = lines + 1 end end
      H.assertEq(lines, 0, name .. ": no \"Weak against\" line showed")
    end
    H.log(string.format("[six] %s OK", name))
  end)
  steps[#steps + 1] = H.waitFrames(4)     -- (a screenshot is of the next frame drawn: before the next restore)
  return H.seqStep(steps)
end

-- ---- the visits ---------------------------------------------------------------
local function openBattle(tag)
  return H.seqStep({
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 3000, tag .. ": the battle is up", 10),
    H.waitFrames(150),
    H.call(function()
      H.log(string.format("[six] %s: formation $%03X: %s", tag, H.readWord(0x11E0) & 0x3FF, formationText()))
      B.req = H.requestSaveState()
    end),
    H.waitFrames(5),
    H.call(function() H.checkReq(B.req, tag .. ": the opening snapshot"); B.blob = B.req.blob end),
  })
end
local function cases(names)
  local t = {}
  for _, n in ipairs(names) do
    if wanted(n) then
      t[#t + 1] = branch(BY_NAME[n], "weak")
      t[#t + 1] = branch(BY_NAME[n], "cold")
    end
  end
  return H.seqStep(t)
end
local function any(names)
  for _, n in ipairs(names) do if wanted(n) then return true end end
  return false
end
local function hand(c) return H.readByte(0x1600 + 37 * c + 0x1F) end
local function inParty(c) return (H.readByte(0x1850 + c) & 0x07) == H.readByte(0x1A6D) and (H.readByte(0x1850 + c) & 0x07) ~= 0 end

-- VARGAS's ledge: one A at him, the scene, battle 66 (a fixed formation).
-- The target select does not reach VARGAS while an Ipooh stands (measured:
-- "the target select never reached monster 0 (15 presses)",
-- build/attempts/wt/v051-six-classes/newsuites/dev/chip2.log; and
-- battle_vargas's control waits for both Ipoohs down), so a side that needs
-- him is played from a second snapshot, B.late, taken once the party has
-- fought both Ipoohs down (the library's fight driver, Tools off).  Which
-- snapshot a side takes follows the rows the battle seeded: the opening's
-- when an Ipooh is on that side, the later one when only VARGAS is.
local VARGAS = 0x103
local function vargasAlone()
  local n, v = 0, false
  for s = 0, 5 do
    if standing(s) then n = n + 1; v = v or species(s) == VARGAS end
  end
  return n == 1 and v
end
local function vargasSides()
  local others, vrow = {}, nil
  for s = 0, 5 do
    if standing(s) then
      if species(s) == VARGAS then vrow = row(s) else others[#others + 1] = row(s) end
    end
  end
  H.assertEq(vrow ~= nil and #others > 0, true, "VARGAS and his Ipoohs stand as the battle opens")
  B.canAim = function(s) return species(s) ~= VARGAS or vargasAlone() end
  B.whenFor = function(bit, wantWeak)
    for _, r in ipairs(others) do if ((r & bit) ~= 0) == wantWeak then return "blob" end end
    if ((vrow & bit) ~= 0) == wantWeak then return "late" end
    return "blob"
  end
end
local function vargas(tag, prep, names)
  local aPh = 0
  return H.cond(function() return any(names) end, {
    H.loadState("build/states/vargas_entry.mss.lua"),
    H.waitFrames(30),
    H.call(function() H.assertEq(H.mapId() & 0x1ff, 98, tag .. ": booted on map 98, VARGAS's ledge") end),
    prep,
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function() aPh = (aPh + 1) % 8; H.setPad(aPh < 4 and { "a" } or {}) end),
    }, tag .. ": the VARGAS scene reaches its battle"),
    openBattle(tag),
    H.call(vargasSides),
    (function()
      -- the ordinary fight driver, Tools off so nothing but a hand reaches VARGAS's gauge
      local F = H.newFightDriver(tag, { tactical = true, boost = true, items = true, bank = 0, healPercent = 55,
        tools = false })
      return H.driveUntil(function() return vargasAlone() or not H.battleLoadStarted() end, 30000, {
        H.call(function() F.frame() end),
      }, tag .. ": the Ipoohs fought down")
    end)(),
    H.release(),
    H.call(function()
      H.assertEq(vargasAlone() and H.battleLoadStarted(), true, tag .. ": both Ipoohs are down and VARGAS stands alone")
    end),
    H.waitFrames(90),
    H.call(function()
      H.log(string.format("[six] %s, the Ipoohs down: %s", tag, formationText()))
      B.lreq = H.requestSaveState()
    end),
    H.waitFrames(5),
    H.call(function() H.checkReq(B.lreq, tag .. ": the later snapshot"); B.late = B.lreq.blob end),
    cases(names),
    H.call(function() B.canAim, B.whenFor, B.late = nil, nil, nil end),
  }, {})
end

-- the Mt. Kolts cave's lane (gen_kolts_cave's own pool walk), to its first encounter
local function kolts(names)
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  local lane, pick = nil, {}
  return H.cond(function() return any(names) end, {
    H.loadState("build/states/kolts_cave.mss.lua"),
    H.waitFrames(30),
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, 96, "kolts: booted in the Mt. Kolts cave (map 96)")
      -- a dagger in a hand; else one from the bag, on a member who can hold it
      local bit = BY_NAME.dagger.bit
      for _, c in ipairs({ TERRA, LOCKE, EDGAR }) do
        if inParty(c) and H.weaponClass(hand(c)) == bit then pick.held = c end
      end
      if pick.held == nil then
        for id = 0, 0x59 do
          if pick.item == nil and H.weaponClass(id) == bit and bagHas(id) then pick.item = id end
        end
        H.assertEq(pick.item ~= nil, true, "kolts: a dagger-class weapon is in a hand or the bag (gen_kolts and the "
          .. "South Figaro shop stop supply one)")
        pick.who = inParty(LOCKE) and LOCKE or TERRA
      end
      H.log(string.format("[six] kolts: dagger %s", pick.held and string.format("in c%d's hand ($%02X)", pick.held,
        hand(pick.held)) or string.format("$%02X in the bag: c%d takes it through Equip", pick.item, pick.who)))
    end),
    H.cond(function() return pick.held == nil end, {
      -- (built when the step list runs: the item is read from the bag above)
      { tick = function(self)
          self.inner = self.inner or H.equipLoadout(pick.who, { { 0, pick.item } }, { tag = "kolts dagger" })
          return self.inner:tick()
        end, reset = function(self) self.inner = nil end },
    }, {}),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}); return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] }; break end
          end
          if lane == nil then H.setPad({}); return end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "kolts: the lane's first encounter"),
    openBattle("kolts"),
    cases(names),
  }, {})
end

-- the dialog before ULTROS, paged into his battle
local function ultros(names)
  local n = 0
  return H.cond(function() return any(names) end, {
    H.loadState("build/states/ultros1_entry.mss.lua"),
    H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function()
        n = H.dialogWaiting() and n + 1 or 0
        H.setPad((n > 0 and n % 8 < 4) and { "a" } or {})
      end),
    }, "ultros: the dialog paged into his battle"),
    openBattle("ultros"),
    cases(names),
  }, {})
end

-- CYAN on Doma's battlements: the two soldiers beside him (obj 17)
local function doma(names)
  return H.cond(function() return any(names) end, {
    H.loadState("build/states/cyan_defence.mss.lua"),
    H.waitFrames(30),
    H.call(function() H.assertEq(inParty(CYAN), true, "doma: CYAN is this fixture's party") end),
    H.talkToObj(17, "doma: the soldiers engaged", 20000),
    H.driveUntil(function() return H.battleLoadStarted() end, 3000, {
      H.call(function() H.setPad(H.frame % 8 < 4 and { a = true } or {}) end),
    }, "doma: the soldiers' battle starts"),
    openBattle("doma"),
    cases(names),
  }, {})
end

local strip = {}
H.run({ maxFrames = 400000 }, {
  H.waitFrames(20),
  H.call(function()
    armWatches()
  end),
  vargas("vargas", H.waitFrames(1), { "sword", "ranged" }),
  -- blunt: one member's weapon goes back to the bag through Equip -> Rmove
  vargas("vargas, a hand emptied", H.seqStep({
    H.call(function()
      strip.who = inParty(LOCKE) and LOCKE or TERRA
      H.log(string.format("[six] blunt: c%d's weapon ($%02X) goes back to the bag through Equip -> Rmove", strip.who,
        hand(strip.who)))
    end),
    { tick = function(self)
        self.inner = self.inner or H.removeEquip(strip.who, 0, { tag = "blunt: the hand emptied" })
        return self.inner:tick()
      end, reset = function(self) self.inner = nil end },
    H.call(function() H.assertEq(hand(strip.who), 0xFF, "blunt: the main hand is empty") end),
  }), { "blunt" }),
  kolts({ "dagger" }),
  ultros({ "spear" }),
  doma({ "katana" }),
  H.call(function()
    local said, n = {}, 0
    for _, c in ipairs(CLASSES) do
      local r = RESULT[c.name]
      if wanted(c.name) then
        H.assertEq(r ~= nil and r.weak ~= nil and r.cold ~= nil, true, c.name .. ": both branches were played")
        H.assertEq(r.weak == "natural" or r.cold == "natural", true, c.name .. ": at least one side was a body "
          .. "the ROM's own rows gave (not both staged)")
        said[#said + 1] = string.format("%s weak %s cold %s hud %s", c.name, r.weak, r.cold, r.hud and "read" or "not read")
        n = n + 1
      end
    end
    H.log(string.format("[six] %d class(es): %s", n, table.concat(said, "; ")))
    H.log(string.format("[six] PASS%s", only.any and " (a subset: OT6_LEVERS)" or ""))
  end),
})
