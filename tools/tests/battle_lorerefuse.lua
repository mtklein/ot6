-- @suite
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- battle_lorerefuse.lua -- R does not raise a boost on a Lore that moves no number (boost-rewards.md, "Every
-- player action today"; Ot6RowNoBoost's Lore-list arm, ot6_boost.asm).
--
-- Boots fire-out-v1 by cold Continue (configure.py TEST_ENV).  By hand:
--   OT6_SRAM_CHECKPOINT=build/checkpoints/fire-out-v1 \
--     tools/tests/run.sh tools/tests/battle_lorerefuse.lua <log>
--
-- A lore whose MagicProp record has no power or a fraction of HP/MP (Condemned, Roulette, Big Guard, L.5 Doom,
-- L.3 Muddle, Reflect???, ForceField, Dischord, Sour Mouth, Pep Up, Rippler) buys nothing with a boost.  Before
-- this arm the Lore window let R raise one, and the turn's end dropped it; now R buzzes on such a row the way it
-- does on a Magic row that moves no number.  The case: STRAGO's Lore window, R pressed once with the cursor on
-- the quiet lore (pending stays 0), then once on Aqua Rake, which moves a number (pending goes to 1).  Both
-- lores are chosen off the ROM as Ot6SpellNoBoost reads them (MagicProp +4 bit 7, +6).
--
-- DECLARED EXPEDIENT (tools/state_write_waivers.txt).  The route's STRAGO knows no quiet lore at fire-out, so
-- before the walk the suite teaches him the first one ($1D29 bit) and loads it into his first lore slot
-- (OT6_LORELOAD $1E27, id + 1; the free row, Aqua Rake, is offered beside any loadout), and makes sure Aqua
-- Rake is learned.  The property is the Lore window's answer to R, not play.
local H = dofile("tools/tests/lib/ot6.lua")

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_DEF, ST_TGT, ST_LORE = 0x05, 0x27, 0x38, 0x1B
local BANK, PEND, MLISTPTR = 0x3E9C, 0x3E9D, 0x302C
local LSCROLL, LROW = 0x891F, 0x8927
local LOREBITS, LORELOAD = 0x1D29, 0x1E27
local CMD_LORE = 0x0C
local STRAGO = 7
local AQUA = 3                      -- lore id of Aqua Rake, the free row

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
-- the list row (0..23) holding lore attack id `id` ($8B + lore id) in slot s's battle list, the rows
-- UpdateMenuState_1b's confirm reads (_c183f7: the caster's list at $208e, rows 55.. after the esper and 54 spells)
local function loreRow(s, id)
  local b = H.readWord(MLISTPTR + s * 2)
  if b < 0x2000 or b > 0x2600 then return nil end
  for row = 0, 23 do
    if H.readByte(b + (55 + row) * 4) == id then return row end
  end
end

local quiet           -- the first lore id that moves no number
local stragoS
local res = {}        -- [lore id] = { before, after }

local function defendPress(st)
  if st == ST_CMD then return "right" end
  if st == ST_DEF then return "a" end
  if st == ST_TGT or st == ST_LORE then return "b" end
  return nil
end

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
    H.assertEntryContract("fire-out-v1")
    local have = false
    for _, c in ipairs(members()) do if c == STRAGO then have = true end end
    assert(have, "STRAGO is in the party")
    -- the lores, off the ROM as Ot6SpellNoBoost reads them
    local mpb = H.sym("MagicProp") & 0x3FFFFF
    local function none(j)
      local r = mpb + (0x8B + j) * 14
      return (H.readRomByte(r + 4) & 0x80) ~= 0 or H.readRomByte(r + 6) == 0
    end
    local tags = {}
    for j = 0, 23 do
      tags[#tags + 1] = string.format("%d%s", j, none(j) and "-" or "+")
      if quiet == nil and none(j) then quiet = j end
    end
    H.log("[lorerefuse] lores (- moves no number, + moves one): " .. table.concat(tags, " "))
    assert(quiet ~= nil, "a lore that moves no number")
    assert(not none(AQUA), "Aqua Rake moves a number")
    -- the declared staging (see the header)
    local a = LOREBITS + (quiet >> 3)
    H.writeByte(a, H.readByte(a) | (1 << (quiet & 7)))
    a = LOREBITS + (AQUA >> 3)
    H.writeByte(a, H.readByte(a) | (1 << (AQUA & 7)))
    H.writeByte(LORELOAD, quiet + 1)
    H.log(string.format("[lorerefuse] staged: STRAGO knows lore %d (quiet) and %d (Aqua Rake); slot 1 = %d",
      quiet, AQUA, quiet))
  end),
  (function()
    local P = H.newPacer({ tag = "lorerefuse pace" })
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
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == STRAGO then stragoS = s end end
    assert(stragoS, "STRAGO is seated in the battle")
    assert(cmdRow(stragoS, CMD_LORE), "STRAGO's battle list has Lore")
    local q, w = loreRow(stragoS, 0x8B + quiet), loreRow(stragoS, 0x8B + AQUA)
    H.log(string.format("[lorerefuse] STRAGO slot %d: the quiet lore on row %s, Aqua Rake on row %s",
      stragoS, tostring(q), tostring(w)))
    assert(q and w, "both lores are offered in STRAGO's Lore window")
  end),
  (function()
    local tick, held = 0, nil
    local order = nil     -- the lores to press R on, in turn
    local phase = 0       -- 0 to the row, 1 R pressed, waiting; then the next
    local waitUntil = 0
    return H.driveUntil(function() return order ~= nil and #order == 0 end, 30000, {
      H.call(function()
        tick = tick + 1
        local ph = tick % 12
        if ph ~= 0 then H.setPad((held and ph < 6) and { [held] = true } or {}) return end
        held = nil
        if H.readByte(MENU) == 0 then H.setPad({}) return end
        local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
        if a ~= stragoS then held = defendPress(st); H.setPad({}) return end
        if order == nil then
          if st ~= ST_CMD then held = "b"; return end
          if pend(stragoS) ~= 0 then held = "l"; return end
          assert(bank(stragoS) >= 1, "STRAGO has a pip banked at his window")
          order = { quiet, AQUA }
          H.log(string.format("[lorerefuse] f%d STRAGO's window: bank %d, pending %d", H.frame, bank(stragoS),
            pend(stragoS)))
        end
        if st == ST_CMD then
          local want, cur = cmdRow(stragoS, CMD_LORE), H.readByte(CMDROW + stragoS) & 3
          held = cur ~= want and (cur < want and "down" or "up") or "a"
          return
        end
        if st ~= ST_LORE then return end
        local id = order[1]
        if phase == 1 then
          if H.frame < waitUntil then return end
          res[id].after = pend(stragoS)
          H.log(string.format("[lorerefuse] f%d R on lore %d's row: pending %d -> %d (bank %d)", H.frame, id,
            res[id].before, res[id].after, bank(stragoS)))
          table.remove(order, 1)
          phase = 0
          return
        end
        local want = loreRow(stragoS, 0x8B + id)
        local cur = H.readByte(LSCROLL + stragoS) + H.readByte(LROW + stragoS)
        if cur ~= want then held = cur < want and "down" or "up"; return end
        res[id] = { before = pend(stragoS) }
        held = "r"
        phase, waitUntil = 1, H.frame + 20
      end),
    }, "R on both lore rows")
  end)(),
  H.call(function()
    H.screenshot("lorerefuse_after")
    local q, w = res[quiet], res[AQUA]
    H.assertEq(q.before, 0, "nothing pending before R on the quiet lore")
    H.assertEq(q.after, 0, "R on a lore that moves no number raises no boost (Ot6RowNoBoost refuses it)")
    H.assertEq(w.after, 1, "R on Aqua Rake, which moves a number, raises the boost to 1")
    H.log("[lorerefuse] PASS: R refused on the quiet lore, taken on Aqua Rake")
  end),
})
