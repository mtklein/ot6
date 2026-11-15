-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_mantrarefuse.lua -- a boost buys nothing on SABIN's Mantra, so the Blitz list refuses it (boost-rewards.md,
-- "Every player action today"; Ot6SpellNoNumber's $15, Ot6RowNoBoost's Blitz arm, Ot6BlitzPrice and Ot6ActionEnd's
-- Blitz arm, ot6_boost.asm).
--
-- Boots wor-sabin-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/wor-sabin-v1 \
--     tools/tests/run.sh tools/tests/battle_mantrarefuse.lua <log>
--
-- Mantra's attacker special effect ($15, AttackerEffect_15) sets the heal to the caster's HP over the bodies it
-- heals, after CalcDmg and Ot6BoostDmg have run, so the multiplier a boost buys is written over: before this a
-- boosted Mantra cost the pips and 2.5x the MP per point and healed what an unboosted one heals.  The case, in one
-- random battle outside Tzen (CELES Defends): at SABIN's window his Blitz list opens, R is pressed with the cursor
-- on Mantra (pending must stay 0), then on Pummel (pending goes to 1, the control), then Mantra is confirmed with
-- that point pending.  An exec callback on AttackerEffect_15 reads the heal as the effect gets it (the multiplied
-- number) and as it leaves (HP / bodies).  Asserted: the heal is SABIN's HP over the bodies (the boost reached
-- nothing), the point raised on Pummel is dropped rather than charged (the bank keeps it), and the MP charged is
-- the row's flat price.
--
-- Red on the mutant ROM with Mantra's line taken out of Ot6SpellNoNumber (R raised the boost on Mantra and the
-- turn charged the point and the escalated MP): build/attempts/wt/v045-land/mantra/.
-- No write: the Continue's SABIN knows Mantra (L23; asserted).
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_SHELL = 0x05, 0x27, 0x38, 0x30
local BANK, PEND, MPCUR = 0x3E9C, 0x3E9D, 0x3C08
local BLCOL, BLROW, ITEMLIST, KNOWN = 0x8963, 0x8967, 0x4005, 0x1D28
local CMD_BLITZ = 0x0A
local SABIN = 5
local PUMMEL, MANTRA = 0x5D, 0x61

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end
local function cmdRow(s, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + s * 12 + r * 3) == cmd then return r end
  end
end
local function members()
  local p, t = H.readByte(0x1A6D) & 7, {}
  for c = 0, 13 do
    if (H.readByte(0x1850 + c) & 7) == p and p ~= 0 then t[#t + 1] = c end
  end
  return t
end
-- the Blitz list cell (two columns, the tools shell's) holding attack id `id`
local function cellOf(id)
  for i = 0, 7 do if H.readByte(ITEMLIST + i * 3) == id then return i end end
end
local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT or st == ST_SHELL then return "b" end
  return nil
end

local sabinS
local r = {}          -- what the turn showed
local heals = {}      -- AttackerEffect_15: { enter, leave, hp, bodies } per firing

H.run({ maxFrames = 60000 }, {
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.worldMode() and bright() >= 15 and H.worldHasControl() end,
      6000, {
      H.call(function()
        ph = (ph + 1) % 48
        if bright() < 15 then H.setPad({}); return end
        H.setPad(ph < 8 and { "a" } or {})
      end),
    }, "cold Continue -> world map control")
  end)(),
  H.release(),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("wor-sabin-v1")
    local have = false
    for _, c in ipairs(members()) do if c == SABIN then have = true end end
    assert(have, "SABIN is in the party (wor-sabin-v1: he joins at Tzen)")
    assert((H.readByte(KNOWN) & (1 << (MANTRA - 0x5D))) ~= 0, "SABIN knows Mantra (Blitz bit 4, learned at L23)")
    local mpb = H.sym("MagicProp") & 0x3FFFFF
    H.assertEq(H.readRomByte(mpb + MANTRA * 14 + 9), 0x15, "Mantra's MagicProp +9: attacker special effect $15")
    -- the heal as AttackerEffect_15 gets it ($11b0 after CalcDmg and Ot6BoostDmg) and as it leaves (sta $11b0 /
    -- rts, located in the ROM's own bytes)
    local entry = H.sym("AttackerEffect_15")
    local off, at = entry & 0x3FFFFF, nil
    for i = 0, 63 do
      if H.readRomByte(off + i) == 0x8D and H.readRomByte(off + i + 1) == 0xB0 and H.readRomByte(off + i + 2) == 0x11
         and H.readRomByte(off + i + 3) == 0x60 then at = entry + i + 3; break end
    end
    assert(at, "AttackerEffect_15 ends sta $11b0 / rts")
    emu.addMemoryCallback(function()
      heals[#heals + 1] = { enter = H.readWord(0x11B0) }
    end, emu.callbackType.exec, entry, entry)
    emu.addMemoryCallback(function()
      local h = heals[#heals]
      if h == nil then return end
      local y = emu.getState()["cpu.y"] & 0xFF
      h.leave, h.hp, h.bodies = H.readWord(0x11B0), H.readWord(0x3BF4 + y), H.readByte(0x3EC9)
    end, emu.callbackType.exec, at, at)
  end),
  (function()
    local P = H.newPacer({ tag = "mantrarefuse pace" })
    local sx, sy
    return H.seqStep({
      H.waitUntil(function() return H.worldMode() and H.worldHasControl() and H.worldSettled() end,
        1500, "the world map settled", 5),
      H.call(function() sx, sy = P.findStart(8) end),
      H.worldNavTo(function() return sx end, function() return sy end,
        { maxFrames = 4000, playBattles = "mustflee", care = false }),
      H.waitUntil(function() return H.worldSettled() end, 1500, "settled on the stretch", 5),
      H.call(function() P.plan() end),
      H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
        H.call(function() H.setPad(P.pad()) end),
      }, "a random encounter"),
      H.release(),
      H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5),
      H.waitFrames(60),
    })
  end)(),
  H.call(function()
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == SABIN then sabinS = s end end
    assert(sabinS, "SABIN is seated in the battle")
    assert(cmdRow(sabinS, CMD_BLITZ), "SABIN's battle list has Blitz")
  end),
  (function()
    local tick, held = 0, nil
    local order = nil     -- the rows to press R on, in turn, then the confirm
    local phase = 0
    local waitUntil = 0
    return H.driveUntil(function() return r.confirmed ~= nil end, 30000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 12
        if ph ~= 0 then H.setPad((held and ph < 6) and { [held] = true } or {}) return end
        held = nil
        if H.readByte(MENU) == 0 then H.setPad({}) return end
        local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
        if a ~= sabinS then held = defendPress(st); H.setPad({}) return end
        if order == nil then
          if st ~= ST_CMD then held = "b"; return end
          if pend(sabinS) ~= 0 then held = "l"; return end
          assert(bank(sabinS) >= 1, "SABIN has a pip banked at his window")
          order = { MANTRA, PUMMEL }
          r.bank0 = bank(sabinS)
          H.log(string.format("[mantrarefuse] f%d SABIN's window: bank %d, pending %d, MP %d", H.frame,
            bank(sabinS), pend(sabinS), H.readWord(MPCUR + sabinS * 2)))
        end
        if st == ST_CMD then
          local want, cur = cmdRow(sabinS, CMD_BLITZ), H.readByte(CMDROW + sabinS) & 3
          held = cur ~= want and (cur < want and "down" or "up") or "a"
          return
        end
        if st ~= ST_SHELL then return end
        if phase == 1 then
          if H.frame < waitUntil then return end
          local id = table.remove(order, 1)
          r[id] = pend(sabinS)
          H.log(string.format("[mantrarefuse] f%d R on $%02X's row: pending %d (bank %d)", H.frame, id, r[id],
            bank(sabinS)))
          phase = 0
          return
        end
        local id = order[1] or MANTRA
        local want = cellOf(id)
        assert(want, string.format("the Blitz list holds $%02X", id))
        local cc, cr = H.readByte(BLCOL + sabinS), H.readByte(BLROW + sabinS)
        if cc ~= want % 2 then held = want % 2 > cc and "right" or "left"; return end
        if cr ~= want // 2 then held = want // 2 > cr and "down" or "up"; return end
        if #order > 0 then
          held = "r"
          phase, waitUntil = 1, H.frame + 20
          return
        end
        r.pend, r.bank1, r.mp0 = pend(sabinS), bank(sabinS), H.readWord(MPCUR + sabinS * 2)
        H.log(string.format("[mantrarefuse] f%d Mantra confirmed at %d pending (bank %d, MP %d)",
          H.frame, r.pend, r.bank1, r.mp0))
        held = "a"
        r.confirmed = H.frame
      end),
    }, "R on Mantra and Pummel, then Mantra")
  end)(),
  H.waitUntil(function() return #heals > 0 and heals[#heals].leave ~= nil end, 3000, "Mantra's effect ran", 5),
  H.waitFrames(240),
  H.call(function()
    H.screenshot("mantrarefuse_after")
    local h = heals[1]
    local mp1, bank2 = H.readWord(MPCUR + sabinS * 2), bank(sabinS)
    local base = H.abilityCost(MANTRA)
    H.log(string.format("[mantrarefuse] Mantra: $11b0 %d as the effect got it, %d as it left (SABIN HP %d over %d "
      .. "bodies less himself); MP %d -> %d (row base %d); bank %d -> %d, pending now %d", h.enter, h.leave, h.hp,
      h.bodies, r.mp0, mp1, base, r.bank1, bank2, pend(sabinS)))
    H.assertEq(h.leave, h.hp // math.max(1, h.bodies - 1),
      "Mantra heals SABIN's HP over the bodies it heals, whatever the boost (AttackerEffect_15 writes it last)")
    H.assertEq(r[MANTRA], 0, "R on Mantra raises no boost (Ot6RowNoBoost's Blitz arm refuses it)")
    H.assertEq(r[PUMMEL], 1, "R on Pummel, which moves a number, raises the boost to 1")
    H.assertEq(r.pend, 1, "Mantra was confirmed with the point raised on Pummel pending")
    H.assertEq(r.mp0 - mp1, base, "the turn charged Mantra's flat price, not 2.5x for the point (Ot6BlitzPrice)")
    H.assertEq(bank2 >= r.bank1, true, "the point pending on Mantra was dropped, not charged (Ot6ActionEnd's Blitz arm)")
    H.log("[mantrarefuse] PASS: R refused on Mantra, taken on Pummel; a pending point on Mantra kept and its price flat")
  end),
})
