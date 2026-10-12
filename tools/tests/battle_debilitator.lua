-- @suite slow
-- battle_debilitator.lua -- Debilitator adds a weakness and reveals it; Flash
-- and Debilitator are sold where kits.md sources them (#378).
--
-- Vanilla's Debilitator (TargetEffect_56) adds one element its target is not
-- weak to.  The break system reads the weak byte live, so that element is a
-- chip trigger at once, but the HUD drew it as '?' until an elemental hit
-- chipped it.  OT6 reveals it as it is added (Ot6DebilReveal: the bit
-- banked as a pending reveal, landed on the action's frame), so the HUD
-- draws the element's glyph, and keeps it out of the species codex.
--
-- Played: Continue fc-alcove-v1 (EDGAR L27; Debilitator is in the bag),
-- walk onto the continent into a random battle, and EDGAR uses Debilitator
-- on the first live monster through the real menu (H.kitBattle); everyone
-- else Defends.  Nothing is written.  Asserted, between the action's start
-- (Debilitator's own Ot6ItemClass load) and its end (EDGAR's Ot6ActionEnd):
--   1. exactly one element bit was added to the target's weak byte ($3BE0);
--   2. that bit is in the target's revealed byte ($3E89), and was not before;
--   3. the HUD's line buffer holds one more cell drawing that element's
--      glyph (Ot6ElemGlyphTbl) than it did before the action.
-- And from the ROM's own shop table (ShopProp, 9-byte records): shop 82
-- (Figaro's tool merchant) slot 4 and shop 5 (South Figaro) slot 7 sell
-- Flash ($A5), and shop 27 (Vector) slot 5 sells Debilitator ($A7).
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/debilitator/.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, CMD_TOOLS, DEBIL, FLASH = 0x04, 0x09, 0xA7, 0xA5

local seat, rec, target = nil, nil, nil
local plan = { { who = EDGAR, cmd = CMD_TOOLS, row = DEBIL, boost = 0 } }
local GLYPHS = H.sym("Ot6ElemGlyphTbl") & 0x3FFFFF
local function glyphOf(bit)
  local i = 0
  while (1 << i) ~= bit do i = i + 1 end
  return H.readRomByte(GLYPHS + i), i
end
local function hudCount(g)
  local n = 0
  for line = 0, 5 do
    local base = H.shadowLine(line) + 4
    for c = 0, 4 do if H.readByte(base + c * 2) == g then n = n + 1 end end
  end
  return n
end

local function arm()
  local ic = H.sym("Ot6ItemClass")
  emu.addMemoryCallback(function()
    if seat == nil or rec ~= nil then return end
    if (emu.getState()["cpu.a"] & 0xff) ~= DEBIL or H.readByte(0x3A7C) ~= CMD_TOOLS then return end
    local t = 8 + target * 2
    rec = { weak0 = H.readByte(0x3BE0 + t), rev0 = H.readByte(0x3E89 + t), f = H.frame, hud0 = {} }
    for b = 0, 7 do rec.hud0[b] = hudCount(H.readRomByte(GLYPHS + b)) end
  end, emu.callbackType.exec, ic, ic)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if rec == nil or rec.ended or seat == nil then return end
    if (emu.getState()["cpu.x"] & 0xff) == seat * 2 then rec.ended = H.frame end
  end, emu.callbackType.exec, ae, ae)
end

local function shopSlot(shop, slot)
  return H.readRomByte((H.sym("ShopProp") & 0x3FFFFF) + shop * 9 + slot)
end

H.run({ maxFrames = 200000 }, {
  H.call(function()
    for _, c in ipairs({ { 82, 4, FLASH, "Figaro's tool merchant (WoB)" }, { 5, 7, FLASH, "South Figaro" },
                         { 27, 5, DEBIL, "Vector" } }) do
      local got = shopSlot(c[1], c[2])
      H.log(string.format("[debil] shop %d slot %d (%s): $%02X", c[1], c[2], c[4], got))
      H.assertEq(got, c[3], string.format("shop %d (%s) slot %d sells $%02X", c[1], c[4], c[2], c[3]))
    end
  end),
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(arm),
  H.fcAlcoveToBattle("debil"),
  H.call(function()
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == EDGAR then seat = s end end
    H.assertEq(seat ~= nil, true, "EDGAR is seated")
    for s = 0, 5 do
      if target == nil and (H.readByte(0x3AA8 + s * 2) & 1) == 1 and H.readWord(0x3BFC + s * 2) > 0 then target = s end
    end
    H.assertEq(target ~= nil, true, "a live monster")
    local t = 8 + target * 2
    H.assertEq(H.readByte(0x3BE0 + t) ~= 0xFF, true, "it is not already weak to every element")
    plan[1].slot = target
    H.log(string.format("[debil] EDGAR seat %d, target slot %d (weak $%02X, revealed $%02X)", seat, target,
      H.readByte(0x3BE0 + t), H.readByte(0x3E89 + t)))
  end),
  H.kitBattle(plan,
    { untilPlanDone = true, idle = "defend", maxFrames = 60000,
      planDone = function() return rec ~= nil and rec.ended ~= nil and H.frame > rec.ended + 30 end }),
  H.call(function()
    local t = 8 + target * 2
    local weak1, rev1 = H.readByte(0x3BE0 + t), H.readByte(0x3E89 + t)
    local added = weak1 & ~rec.weak0 & 0xFF
    H.log(string.format("[debil] f%d: weak $%02X -> $%02X (added $%02X), revealed $%02X -> $%02X", rec.f,
      rec.weak0, weak1, added, rec.rev0, rev1))
    H.assertEq(added ~= 0 and (added & (added - 1)) == 0, true, "Debilitator added exactly one element")
    H.assertEq(rec.rev0 & added, 0, "the added element was not revealed before")
    H.assertEq(rev1 & added, added, "and is revealed after the action (Ot6DebilReveal)")
    local g, i = glyphOf(added)
    local n1 = hudCount(g)
    H.log(string.format("[debil] the HUD draws element %d's glyph $%02X in %d cell(s), %d before", i, g, n1,
      rec.hud0[i]))
    H.assertEq(n1 > rec.hud0[i], true, "the HUD draws one more cell of the added element's glyph")
    H.log("[debil] PASS: one element added and revealed; the HUD marks it; the shops stock Flash and Debilitator")
  end),
})
