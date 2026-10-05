-- @suite
-- battle_boostcap.lua -- Ot6BoostDmg's overflow arm (#359): a boosted
-- product past $FFFF saturates at $FFFF, so boosted damage never falls as
-- base damage rises.
--
-- Ot6BoostDmg doubles the 16-bit base damage $11b0 once per pip (`asl / bcs
-- @cap`, ot6_boostdmg.asm).  Until #359 the overflow arm loaded $7FFF, so x8
-- of 8191 was 65528 and x8 of 8192 was 32767, and x2 of 40000 left LESS than
-- the unboosted 40000; the rest of the engine saturates at $FFFF and the
-- per-target 9999 cap comes later.  No fixture reaches a base of 8192 at x8
-- by play (the largest the Magicite measured is Crusader's 7475 at L27,
-- build/attempts/wt/procboost-magicite/summary.txt), so this is a mechanism
-- test with a declared write (state_write_waivers.txt): the base damage is
-- injected at Ot6BoostDmg's entry, on a real boosted action through the real
-- menus, and the multiplier's output read at its rtl.
--
-- From battle_entry (TERRA and two soldiers in Magitek armor against the
-- Narshe guards): the first slot whose window opens is the actor; other
-- slots defer focus with X.  Each case pins the actor's bank (3 pips) and
-- every body's HP (so the fight neither ends nor wipes), raises pending with
-- R through the menu to the case's boost, fires the row-2 beam, and on the
-- actor's first Ot6BoostDmg call at that pending writes the case's base into
-- $11b0.  Asserted per case: the call ran at the case's boost, and left
-- min(base << boost, $FFFF).  The cases sit on each boost's overflow edge:
-- the last base that fits and the first that carries, plus 40000 at x2 and
-- $FFFF at x8.  Old ROM (a2d49b67, the $7FFF arm): x2 of $8000, x2 of
-- 40000, x4 of $4000, x8 of 8192 and x8 of $FFFF each leave $7FFF.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_entry.mss.lua"
local MSTATE, ST_CMD, ST_MAGITEK, ST_TGT = 0x7BC2, 0x05, 0x2A, 0x38
local MENU, ACTOR = 0x7BCA, 0x62CA
local BANK, PEND = 0x3E9C, 0x3E9D
local DMG = 0x11B0

local CASES = {
  { b = 1, din = 0x7FFF },  -- fits: $FFFE
  { b = 1, din = 0x8000 },  -- carries: $FFFF (old: $7FFF)
  { b = 1, din = 40000 },   -- old: $7FFF, below the unboosted 40000
  { b = 2, din = 0x3FFF },  -- fits: $FFFC
  { b = 2, din = 0x4000 },  -- carries
  { b = 3, din = 8191 },    -- fits: 65528
  { b = 3, din = 8192 },    -- carries
  { b = 3, din = 0xFFFF },  -- carries on the first doubling
}
local function want(c)
  local v = c.din << c.b
  if v > 0xFFFF then v = 0xFFFF end
  return v
end

local BD = H.sym("Ot6BoostDmg")
local BD_EXIT = H.sym("Ot6FoldCmdTbl") - 1     -- `done: plp / rtl`, the rtl
local actor, k = nil, 1                        -- the actor; the case in play
local injected, result = false, {}

local function pend(s) return H.readByte(PEND + s * 2) end
local function pin()
  for s = 0, 3 do
    if H.readWord(0x3BF4 + s * 2) > 0 then H.writeWord(0x3BF4 + s * 2, 999) end
  end
  for s = 0, 5 do
    if H.readWord(0x3BFC + s * 2) > 0 then H.writeWord(0x3BFC + s * 2, 0xF000) end
  end
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.call(function()
    H.assertEq(H.readRomByte(BD_EXIT & 0x3FFFFF), 0x6B,
      "Ot6FoldCmdTbl - 1 is Ot6BoostDmg's rtl")
    H.assertEq(H.readRomByte((BD_EXIT - 1) & 0x3FFFFF), 0x28,
      "...after its plp")
    emu.addMemoryCallback(function()
      if actor == nil or injected or k > #CASES then return end
      if (emu.getState()["cpu.x"] & 0xFF) ~= actor * 2 then return end
      local c = CASES[k]
      if pend(actor) ~= c.b then return end
      result[k] = { base = H.readWord(DMG) }
      H.writeWord(DMG, c.din)                    -- the declared injection
      injected = true
    end, emu.callbackType.exec, BD, BD)
    emu.addMemoryCallback(function()
      if not injected or result[k] == nil or result[k].out ~= nil then return end
      result[k].out = H.readWord(DMG)
    end, emu.callbackType.exec, BD_EXIT, BD_EXIT)
    pin()
  end),
  (function()
    local mf, downs, armedAt = 0, 0, nil
    return H.driveUntil(function() return k > #CASES end, 50000, {
      H.call(function()
        if result[k] and result[k].out ~= nil and pend(actor) == 0 then
          local c, r = CASES[k], result[k]
          H.log(string.format("case %d: x%d of %d ($%04X) left %d ($%04X), "
            .. "want %d ($%04X) (the beam's own base was %d)", k, 1 << c.b,
            c.din, c.din, r.out, r.out, want(c), want(c), r.base))
          k, injected, downs, armedAt = k + 1, false, 0, nil
          pin()
          H.setPad({})
          return
        end
        if H.readByte(MENU) == 0 then mf, downs = 0, 0; H.setPad({}); return end
        local act, st = H.readByte(ACTOR), H.readByte(MSTATE)
        if actor == nil then
          actor = act
          H.log("the actor: slot " .. actor)
        end
        mf = mf + 1
        if (mf - 1) % 8 >= 4 then H.setPad({}); return end
        local c, btn = CASES[k], "b"
        if act ~= actor then
          btn = st == ST_CMD and "x" or "b"   -- defer focus; back out first
        elseif st == ST_CMD then
          if armedAt ~= k then
            pin()
            H.writeByte(BANK + actor * 2, 3)  -- the case's pips (declared)
            armedAt = k
          end
          if pend(actor) < c.b then btn = "r"
          elseif pend(actor) > c.b then btn = "l"
          else btn = "a" end                  -- open the magitek list
        elseif st == ST_MAGITEK then
          -- the list keeps its cursor between turns, so only the first
          -- case walks it down to the row-2 beam (battle_boost's beam)
          if k == 1 and downs < 2 then
            if (mf - 1) % 8 == 0 then downs = downs + 1 end
            btn = "down"
          else btn = "a" end                  -- the row-2 beam
        elseif st == ST_TGT then btn = "a"    -- the default (enemy) target
        elseif st == 0x01 then H.setPad({}); return
        end
        H.setPad({ [btn] = true })
      end),
      H.waitFrames(1),
    }, "every case's boosted beam landed")
  end)(),
  H.call(function()
    local bad = 0
    for i, c in ipairs(CASES) do
      local r = result[i]
      H.assertEq(r ~= nil and r.out ~= nil, true,
        string.format("case %d reached Ot6BoostDmg at boost %d", i, c.b))
      if r.out ~= want(c) then bad = bad + 1 end
      H.log(string.format("x%d: %d -> %d%s", 1 << c.b, c.din, r.out,
        r.out == want(c) and "" or string.format("  WRONG, want %d", want(c))))
    end
    for i, c in ipairs(CASES) do
      H.assertEq(result[i].out, want(c), string.format(
        "case %d: x%d of %d saturates at $FFFF rather than falling (%d wrong)",
        i, 1 << c.b, c.din, bad))
    end
  end),
})
