-- @suite savestate=battle_entry
-- battle_magitekboost.lua -- MagiTek's Confuser and X-fer buy nothing with a
-- boost, so the boost refuses them (#469)
--
-- A MagiTek beam with a number (Fire Beam, Heal Force, TekMissile...) takes
-- Ot6BoostDmg's multiplier.  Confuser and X-fer move no number (power 0:
-- MagicProp $88 and $89), so before #469 a boost raised for them was spent
-- for nothing.  Now R is refused with the cursor on either row of the MagiTek
-- list (Ot6RowNoBoost's MagiTek arm: the cell + $83, Ot6SpellNoBoost), and a
-- boost raised on the command window before the row was picked is dropped at
-- the queue (Ot6QueueFold's MagiTek arm), never charged.
--
-- From battle_entry (TERRA and two soldiers in Magitek armor against the
-- Narshe guards; only TERRA's list holds the two beams, TerraMagitekAttackTbl):
-- the soldiers defer focus with X, and TERRA, who opens with one pip, plays:
--   1. her MagiTek list: R on Confuser and on X-fer leaves the pending at 0
--      (refused); R on Fire Beam raises it to 1 (the control), and L takes it
--      back;
--   2. R on the command window raises one pip, then Confuser is picked and
--      confirmed at the default target: at the pick the pending is 1, and six
--      frames after her Ot6ActionEnd the bank stands where an unboosted turn
--      leaves it (the pip she held plus the regen pip), not spent.
-- Nothing is written.  Old ROM: R raises on both rows and the boosted
-- Confuser spends the pip (the bank ends at 0).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local MSTATE, ST_CMD, ST_MAGITEK, ST_TGT = 0x7BC2, 0x05, 0x2A, 0x38
local MENU, ACTOR = 0x7BCA, 0x62CA
local BANK, PEND = 0x3E9C, 0x3E9D
local TERRA = 0x00
-- the MagiTek list's cells (TerraMagitekAttackTbl: cell = row * 2 + column)
local CELL = { fire = 0, confuser = 5, xfer = 6 }

local function pend(s) return H.readByte(PEND + s * 2) end
local function bank(s) return H.readByte(BANK + s * 2) end

local terra
local plan = {
  { cell = "confuser", r = true },
  { cell = "xfer", r = true },
  { cell = "fire", r = true, control = true },
  { cell = "confuser", commit = true },
}
local k, res, triedR, endF, done = 1, {}, false, nil, false
local bank0

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) == TERRA then terra = s end
    end
    assert(terra, "TERRA is in the battle (battle_entry)")
    emu.addMemoryCallback(function()
      if (emu.getState()["cpu.x"] & 0xFF) == terra * 2 and res.committed and endF == nil then
        endF = H.frame
        H.log(string.format("[magitek] f%d TERRA's Ot6ActionEnd: queued $%02X $%02X, bank %d pending %d",
          H.frame, H.readByte(0x3A7C), H.readByte(0x3A7D), bank(terra), pend(terra)))
      end
    end, emu.callbackType.exec, H.sym("Ot6ActionEnd"), H.sym("Ot6ActionEnd"))
  end),
  (function()
    local mf = 0
    return H.driveUntil(function() return done end, 30000, {
      H.call(function()
        if endF and H.frame >= endF + 6 and res.bankEnd == nil then
          res.bankEnd = bank(terra)
          done = true
          H.setPad({})
          return
        end
        if H.readByte(MENU) == 0 then mf = 0; H.setPad({}); return end
        local act, st = H.readByte(ACTOR), H.readByte(MSTATE)
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local btn = "b"
        if act ~= terra then
          btn = st == ST_CMD and "x" or "b"
        elseif res.committed then
          btn = st == ST_TGT and "a" or nil   -- until the confirm lands
        else
          local p = plan[k]
          if st == ST_CMD then
            if p.commit then
              if pend(terra) < 1 then btn = "r"
              else
                bank0 = bank0 or bank(terra)
                btn = "a"
              end
            elseif pend(terra) > 0 then btn = "l"
            else btn = "a" end
          elseif st == ST_MAGITEK then
            local want = CELL[p.cell]
            local col, row = H.readByte(0x893F + terra), H.readByte(0x8943 + terra)
            if row < want // 2 then btn = "down"
            elseif row > want // 2 then btn = "up"
            elseif col < want % 2 then btn = "right"
            elseif col > want % 2 then btn = "left"
            elseif p.r then
              if not triedR then
                triedR = true
                res[k] = { before = pend(terra) }
                btn = "r"
              elseif res[k].after == nil then
                res[k].after = pend(terra)
                H.log(string.format("[magitek] R on %s: pending %d -> %d", p.cell, res[k].before, res[k].after))
                btn = pend(terra) > 0 and "l" or nil
                if btn == nil then k, triedR = k + 1, false end
              else
                if pend(terra) > 0 then btn = "l" else k, triedR = k + 1, false; btn = nil end
              end
            elseif pend(terra) < 1 then
              btn = "b"                  -- back to the command window to raise it
            else
              res.pendAtPick = pend(terra)
              btn = "a"
            end
          elseif st == ST_TGT then
            res.committed = true
            res.pendAtConfirm = pend(terra)
            H.log(string.format("[magitek] Confuser confirmed at pending %d, bank %d", pend(terra), bank(terra)))
            btn = "a"
          elseif st == 0x01 then btn = nil
          end
        end
        H.setPad(btn and { [btn] = true } or {})
      end),
      H.waitFrames(1),
    }, "TERRA's MagiTek plan resolves")
  end)(),
  H.call(function()
    local bad = {}
    local function check(ok, msg)
      H.log(string.format("[magitek] %s %s", ok and "ok:" or "FAIL:", msg))
      if not ok then bad[#bad + 1] = msg end
    end
    for i = 1, 3 do
      local p, r = plan[i], res[i]
      H.assertEq(r ~= nil and r.after ~= nil, true, "R was pressed on " .. p.cell)
      local want = p.control and 1 or 0
      check(r.after == want, string.format("R on %s left the pending at %d (want %d: %s)", p.cell, r.after, want,
        p.control and "the beam has a number" or "refused: it buys nothing"))
    end
    H.assertEq(res.pendAtConfirm, 1, "the boosted Confuser was confirmed with one pip pending")
    -- an unboosted turn: the pip held stays and the regen pip lands (capped at 5)
    local want = math.min(5, bank0 + 1)
    check(res.bankEnd == want, string.format("the boosted Confuser left the bank at %d (from %d; want %d: the boost "
      .. "dropped, never charged, and the regen pip earned)", res.bankEnd, bank0, want))
    assert(#bad == 0, #bad .. " MagiTek assertion(s) failed: " .. table.concat(bad, "; "))
    H.log("[magitek] VERDICT: R refused on Confuser and X-fer, raised on Fire Beam; a boost raised before Confuser "
      .. "is dropped, not charged")
  end),
})
