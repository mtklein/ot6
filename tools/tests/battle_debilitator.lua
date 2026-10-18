-- @suite slow
-- battle_debilitator.lua -- Debilitator adds a weakness and reveals it; Flash
-- and Debilitator are sold where kits.md sources them (#378).
--
-- Vanilla's Debilitator (TargetEffect_56) adds one element its target is not
-- weak to.  The break system reads the weak byte live, so that element is a
-- chip trigger at once, but the HUD drew it as '?' until an elemental hit
-- chipped it.  OT6 reveals it as it is added (Ot6DebilReveal), in the
-- target's own revealed byte: the weakness is that body's for the battle,
-- not its species', so a sibling of the same species neither shows it nor
-- (by a chip of its own) writes it into the save's codex.
--
-- Played: Continue fc-alcove-v1 (EDGAR L27; the play bought the Debilitator
-- at Vector's weapon shop on the way out of the banquet, gen_banquet_done),
-- walk onto the continent into random battles until one fields two bodies
-- of one species (a battle without a pair is fought out), and EDGAR uses
-- Debilitator on one of the pair through the real menu (H.kitBattle);
-- everyone else Defends; then the battle is fought out.  Nothing is
-- written.  Asserted, between the action's start (Debilitator's own
-- Ot6ItemClass load) and its end (EDGAR's Ot6ActionEnd):
--   1. exactly one element bit was added to the target's weak byte ($3BE0);
--   2. that bit is in the target's revealed byte ($3E89), and was not before;
--   3. the sibling's weak byte did not move, and its revealed byte did not
--      gain the bit;
--   4. the HUD's line buffer holds exactly one more cell drawing that
--      element's glyph (Ot6ElemGlyphTbl) than before: the target's line;
--   5. the species' codex cell (the save's SRAM page) did not gain the bit,
--      then or after the battle.
-- And from the ROM's own shop table (ShopProp, 9-byte records): shop 82
-- (Figaro's tool merchant) slot 4 and shop 5 (South Figaro) slot 7 sell
-- Flash ($A5), and shop 27 (Vector) slot 5 sells Debilitator ($A7).
-- Old-ROM red and mutants: build/attempts/wt/v027-kits/final-matrix/
-- (<rom>__battle_debilitator.out).
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local EDGAR, CMD_TOOLS, DEBIL, FLASH = 0x04, 0x09, 0xA7, 0xA5

local seat, rec, target, sib, species = nil, nil, nil, nil, nil
local plan = {}
local proxy = setmetatable({}, { __index = function(_, k) return plan[k] end, __len = function() return #plan end })
-- BATTLES from the pool (route_data.py pool field 394, group 112; the
-- pace's battles are all drawn there): a same-species pair is formation
-- 178 (Misfit x2) in slot 0's four, 181/182/183 (Wirey Drgn x3, Apokryphos
-- x3, Brainpan x2) in slot 1's, 183/184/186 in slot 2's and 186/187 in slot
-- 3's, so (80*1/4 + 80*3/4 + 80*3/4 + 16*2/4)/256 = 148/256 = 0.578 of
-- battles field one.  A battle without one is missed with 0.422; at
-- BATTLES = 11 all of them miss with 0.422^11 = 7.6e-5, under 1e-4.  (The
-- v0.27 runs needed 1-2.)  A pair battle that ends before the Debilitator
-- resolves also costs one; none was seen.
local battles, BATTLES, done, addedBit = 0, 11, false, 0
local function live(m) return (H.readByte(0x3AA8 + m * 2) & 1) == 1 and H.readWord(0x3BFC + m * 2) > 0 end
local function codexBase()
  local slot = H.readByte(0x021F)   -- wSaveSlotToLoad: 0 transient, 1..3 saved
  if slot < 1 or slot > 3 then return 0x316C00 end
  return 0x316000 + (slot - 1) * 0x400
end
local function codexElem(sp) return emu.read(codexBase() + 0x10 + sp, emu.memType.snesMemory) end
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
    if seat == nil or target == nil or rec ~= nil then return end
    if (emu.getState()["cpu.a"] & 0xff) ~= DEBIL or H.readByte(0x3A7C) ~= CMD_TOOLS then return end
    local t = 8 + target * 2
    local u = 8 + sib * 2
    rec = { weak0 = H.readByte(0x3BE0 + t), rev0 = H.readByte(0x3E89 + t), f = H.frame, hud0 = {},
      sweak0 = H.readByte(0x3BE0 + u), srev0 = H.readByte(0x3E89 + u), codex0 = codexElem(species) }
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

H.run({ maxFrames = 400000 }, {
  H.call(function()
    for _, c in ipairs({ { 82, 4, FLASH, "Figaro's tool merchant (WoB)" }, { 5, 7, FLASH, "South Figaro" },
                         { 27, 5, DEBIL, "Vector" } }) do
      local got = shopSlot(c[1], c[2])
      H.log(string.format("[debil] shop %d slot %d (%s): $%02X", c[1], c[2], c[4], got))
      H.assertEq(got, c[3], string.format("shop %d (%s) slot %d sells $%02X", c[1], c[4], c[2], c[3]))
    end
  end),
  H.bootCheckpoint("fc-alcove-v1"),
  H.call(function()
    H.assertEq(H.invCountOf(DEBIL) >= 1, true, "the bag holds a Debilitator (bought at Vector)")
  end),
  H.call(arm),
  H.fcAlcoveToBattle("debil"),
  -- battles until one fields two bodies of one species (the leak is to a
  -- sibling); a battle without a pair is fought out and the next taken
  H.driveUntil(function() return done end, 400000, {
    H.cond(function() return not H.battleLoadStarted() end, { H.fcPace("debil") }, {}),
    H.call(function()
      battles = battles + 1
      H.assertEq(battles <= BATTLES, true, string.format("a same-species pair within %d battles", BATTLES))
      seat, target, sib, rec = nil, nil, nil, nil
      for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == EDGAR then seat = s end end
      H.assertEq(seat ~= nil, true, "EDGAR is seated")
      local ids = H.monsterIds()
      for a2 = 0, 5 do
        for b2 = a2 + 1, 5 do
          if target == nil and live(a2) and live(b2) and ids[a2 + 1] == ids[b2 + 1]
              and H.readByte(0x3BE0 + 8 + a2 * 2) ~= 0xFF then
            target, sib, species = a2, b2, ids[a2 + 1]
          end
        end
      end
      local parts = {}
      for s2 = 0, 5 do parts[#parts + 1] = string.format("%X", ids[s2 + 1]) end
      H.log(string.format("[debil] battle %d: species %s; pair %s", battles, table.concat(parts, " "),
        target and string.format("slots %d and %d (species $%03X)", target, sib, species) or "none"))
      if target == nil then return end
      plan = { { who = EDGAR, cmd = CMD_TOOLS, row = DEBIL, boost = 0, slot = target } }
      local t = 8 + target * 2
      H.log(string.format("[debil] EDGAR seat %d, target slot %d (weak $%02X, revealed $%02X), sibling slot %d "
        .. "(weak $%02X, revealed $%02X), codex $%02X", seat, target, H.readByte(0x3BE0 + t), H.readByte(0x3E89 + t),
        sib, H.readByte(0x3BE0 + 8 + sib * 2), H.readByte(0x3E89 + 8 + sib * 2), codexElem(species)))
    end),
    H.cond(function() return target == nil end, { H.kitBattle({}, {}) }, {
      H.kitBattle(proxy,
        { untilPlanDone = true, idle = "defend", maxFrames = 60000,
          planDone = function() return rec ~= nil and rec.ended ~= nil and H.frame > rec.ended + 30 end }),
      H.call(function()
        if rec == nil or rec.ended == nil then
          H.log("[debil] the battle ended before the Debilitator resolved: the next")
          return
        end
        local t, u = 8 + target * 2, 8 + sib * 2
        local weak1, rev1 = H.readByte(0x3BE0 + t), H.readByte(0x3E89 + t)
        local added = weak1 & ~rec.weak0 & 0xFF
        H.log(string.format("[debil] f%d: weak $%02X -> $%02X (added $%02X), revealed $%02X -> $%02X", rec.f,
          rec.weak0, weak1, added, rec.rev0, rev1))
        H.assertEq(added ~= 0 and (added & (added - 1)) == 0, true, "Debilitator added exactly one element")
        H.assertEq(rec.rev0 & added, 0, "the added element was not revealed before")
        H.assertEq(rev1 & added, added, "and is revealed after the action (Ot6DebilReveal)")
        local srev, sweak = H.readByte(0x3E89 + u), H.readByte(0x3BE0 + u)
        H.log(string.format("[debil] sibling slot %d: weak $%02X -> $%02X, revealed $%02X -> $%02X", sib,
          rec.sweak0, sweak, rec.srev0, srev))
        H.assertEq(sweak, rec.sweak0, "the sibling's weaknesses did not move")
        H.assertEq(srev & added & ~rec.srev0, 0, "the sibling does not show the added element (the reveal is the "
          .. "target's alone)")
        local g, i = glyphOf(added)
        local n1 = hudCount(g)
        H.log(string.format("[debil] the HUD draws element %d's glyph $%02X in %d cell(s), %d before", i, g, n1,
          rec.hud0[i]))
        H.assertEq(n1 - rec.hud0[i], 1, "the HUD draws exactly one more cell of the added element's glyph (the "
          .. "target's line, not the sibling's)")
        local c = codexElem(species)
        H.log(string.format("[debil] codex for species $%03X: $%02X (before $%02X)", species, c, rec.codex0))
        H.assertEq(c & added & ~rec.codex0, 0, "the save's codex did not learn the added element")
        addedBit = added
        done = true
      end),
      H.cond(function() return not done and H.battleLoadStarted() end, { H.kitBattle({}, {}) }, {}),
    }),
  }, "a Debilitator on one of a same-species pair"),
  -- the battle fought out: the codex still holds no false bit
  H.kitBattle({}, {}),
  H.waitUntil(function() return not H.battleLoadStarted() and H.hasControl() end, 3000, "back on the field", 5),
  H.call(function()
    local c = codexElem(species)
    H.log(string.format("[debil] after the battle: codex for species $%03X: $%02X", species, c))
    H.assertEq(c & addedBit & ~rec.codex0, 0, "after the battle, the codex still lacks the added element")
    H.log("[debil] PASS: one element added and revealed on the target alone; the HUD marks it once; the codex "
      .. "is clean; the shops stock Flash and Debilitator")
  end),
})
