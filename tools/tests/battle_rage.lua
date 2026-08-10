-- @suite frontier=gau_joined slow
-- battle_rage.lua -- issue #40: Gau's 8-slot rage loadout, asserted at the ONE
-- choke point the design ruled on (docs/design/kit-gau.md §2.2, §8.3, §8.7),
-- plus the trance economy (#34's rule on the other possess-verb) and the tier
-- ladder's coin.
--
-- The Ochette model keeps Veldt learning unlimited -- LearnRage and the
-- 32-byte $1d2c-$1d4b bitfield are untouched -- and narrows only the BATTLE
-- menu, to eight slots the player configures in the field.  The narrowing
-- happens in exactly one place: the flat list InitSkills builds at $257e once
-- per battle (battle_main.asm:14656+).  Everything downstream reads that
-- list: the window draw, the confirm, the scroll cap, RandRage's
-- confused-rager pick.  So this test asserts the list, byte for byte.
--
-- ISSUE #75 CONVERSION -- a REAL GAU, and the InitRage floor.  This file
-- used to install CHAR::GAU into the magitek doorstep, teach the bitfield by
-- hand, write loadouts, pin MP/HP/bp/pending, stop and floor the monsters,
-- wound the bench, poke cursors, and seed $be.  It now boots gau_joined --
-- the honest post-join mint (world (214,149) on the Veldt, CYAN + SABIN +
-- GAU) -- and earns everything:
--   * the learned set is InitRage's NINE at New Game (ids 11 14 19 21 25 46
--     54 57 66; field/init.asm:355 -- the plan-doc correction that killed
--     the collection-mint tier), read from the save, floor-asserted;
--   * the MANUAL loadout's honest writer is the field Rage page: the real
--     Skills -> GAU -> Rage path (menu_ragepage's drive), and EIGHT R
--     presses on slot 0 cycle it K1 -> ... -> K9 -- the ninth learned id,
--     which is NOT in AUTO's frozen window, so the stored slots are eight
--     DISTINCT ids in the player's order, not id order;
--   * trances start from the real four-row menu (battle_gaufight's drive),
--     the rage window's cursor is READ and steered by d-pad, the bench is
--     parked with X, and pending tiers are real R presses on EARNED bp
--     (open at 1, +1 per unboosted action -- Item turns on the Veldt, where
--     row 0 is Leap and a Fight row does not exist);
--   * THE DRAIN IS ARITHMETIC: Gau's real pool is 72 = 9 x 8, so nine real
--     rage-starts across nine Veldt battles land him on EXACTLY ZERO, which
--     makes the refusal gate (Ot6RageStartGate) and the Leap-at-zero floor
--     honest play instead of a poked pool;
--   * the tier coin is DECODED, not seeded (battle_steal's pattern, per the
--     dispatch): an exec callback at Ot6RageCoin's entry reads $be, the
--     roll it is about to draw is computed from RNGTbl, and every observed
--     coin must match the model -- tier 1 special iff draw >= $40, tier 2
--     iff draw >= $10, tier 0 draws NOTHING, tier 3 draws nothing and
--     forces the special.  The old both-sides boundary pins ($3f/$40,
--     $0f/$10) become verified predictions over the draws the stream really
--     dealt (logged); the width-restore contract rides the same crossings.
--
-- What is asserted:
--   1. AUTO TRUNCATES + THE FILL.  All eight save bytes zero (as minted),
--      NINE species learned -> the battle list is the FIRST EIGHT in id
--      order, and the region past them is $ff to the dance list at $267e.
--      (The old 40-species "wall" arm asserted the same truncation at a
--      grind-only size; the ruling is proven at the real save's 9 > 8.)
--   2. MANUAL.  The field-configured loadout appears in SLOT order -- slot
--      0 carries K9, above K2..K8 -- eight ids then $ff (the FULL EIGHT arm
--      folded in: every slot filled through the page's own freeze).
--   6. THE TRANCE'S PRICE.  Rage-start debits the flat 8 from the REAL
--      pool; every possessed turn after it debits 0 (ridden, counted); a
--      Gau at zero MP is REFUSED -- the RAGE status never sets and the pool
--      is not driven negative.
--   7. THE TIER LATCH.  Pending 3 (banked: two real Item turns + three real
--      R's) is copied into OT6_RAGETIER at Cmd_10 and OUTLIVES the action
--      it was spent on across possessed re-entries; every tier-3 roll is
--      the special with zero draws (certainty, not a better coin).
--   8. THE LADDER'S ODDS, decoded per roll at tiers 0/1/2 (see above), with
--      the width contract checked either side of RandRage's jsl.
--   9. LEAP IS FREE (owner reversal 2026-07-29): on the Veldt row 0 IS
--      Leap; a real Leap stages cost 0 (CreateAction watch), resolves
--      through CalcAttackEffect (counted), and the live pool never dips --
--      at a full pool AND at the drained zero, where a free Veldt action is
--      the whole point of #47's shared row.
--
-- *** ONE LABELED ISOLATION ARM (issue #75) -- one write site STAYS ***
-- Two sub-eight-collection claims are UNREACHABLE BY PLAY: InitRage's floor
-- is nine and hunting only adds, so no real save can hold <= 8 species
-- (1b: below the window AUTO is the whole vanilla walk byte-for-byte), and
-- Ot6RageCycleCore only stores learned ids, so no real save can hold a
-- stored-but-unlearned slot (3: such a slot must be dropped, order kept).
-- Both live in one tail arm that writes the $1d2c bitfield / loadout bytes
-- and says so loudly.  It MAY NEVER PRODUCE FIXTURES.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/gau_joined.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TGT, ST_RAGE = 0x05, 0x38, 0x1E
local GAU = 0x0B
local RAGES = 0x1D2C                 -- learned-rage bitfield, 32 bytes
local RAGELOAD = 0x1E1F              -- OT6_RAGELOAD: 8 bytes, id+1, 0 = unset
local LIST, COUNT = 0x257E, 0x3A9A   -- the flat battle list and its length
local DANCELIST = 0x267E             -- the dance list starts here: our ceiling
local RAGETIER = 0xED73              -- OT6_RAGETIER ($7eed73, ot6_memory.inc)
local VELDT = 0x11E4

local function CURMP(s) return 0x3C08 + s * 2 end
local function ST4(e)   return 0x3EF9 + e end
local function bpOf(s)  return H.readByte(0x3E9C + s * 2) end
local function pendOf(s) return H.readByte(0x3E9D + s * 2) end

local gauSlot = nil
local function raging() return (H.readByte(ST4(gauSlot * 2)) & 0x01) ~= 0 end
local function mp() return H.readWord(CURMP(gauSlot)) end

-- the save's own collection, in id order
local function learnedIds()
  local ids = {}
  for id = 0, 254 do
    if (H.readByte(RAGES + (id >> 3)) & (1 << (id & 7))) ~= 0 then
      ids[#ids + 1] = id
    end
  end
  return ids
end

local function cell(i) return H.readByte(LIST + i) end
local function assertList(want, tag)
  H.assertEq(H.readByte(COUNT), #want,
    string.format("%s: $3a9a = %d rages", tag, #want))
  for i, id in ipairs(want) do
    H.assertEq(cell(i - 1), id,
      string.format("%s: list[%d] = rage %d", tag, i - 1, id))
  end
  H.assertEq(cell(#want), 0xFF,
    string.format("%s: list[%d] terminates ($ff)", tag, #want))
end

-- ======================= instruments (all read-only) ======================
local RNGTBL   = H.sym("RNGTbl") & 0x3FFFFF
local MONRAGE  = H.sym("MonsterRage")
local COINPROC = H.sym("Ot6RageCoin")
local RANDRAGE = H.sym("RandRage")

local cmd10Hits = 0
local coins = {}        -- per possessed roll: {tier, draws, be0, draw, coin, id}
local widthChecks = {}
local psAtEntry, yAtEntry = nil, nil
local drawsThisRoll, be0, tierAtEntry = 0, nil, nil
local instrumented = false

local PS_KEY, Y_KEY
local function resolveCpuKeys()
  local s = emu.getState()
  for _, cand in ipairs({ "cpu.ps", "cpu.p", "cpu.flags", "cpu.status" }) do
    if s[cand] ~= nil then PS_KEY = cand break end
  end
  for _, cand in ipairs({ "cpu.y", "cpu.Y" }) do
    if s[cand] ~= nil then Y_KEY = cand break end
  end
  H.assertEq(PS_KEY ~= nil and Y_KEY ~= nil, true,
    "Mesen exposes the CPU flag byte and Y (needed for the width contract)")
end
local function cpu()
  local s = emu.getState()
  return s[PS_KEY], s[Y_KEY]
end

local function instrument()
  if instrumented then return end
  instrumented = true
  resolveCpuKeys()
  -- RNGTbl must be a permutation, or the decode's "the roll it is about to
  -- draw" is fiction
  local seen = {}
  for i = 0, 255 do seen[H.readRomByte(RNGTBL + i)] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  H.assertEq(n, 256, "RNGTbl is a permutation of 0..255")

  -- locate `jsl Ot6RageCoin` inside RandRage, by opcode (cannot go stale)
  local site = nil
  for i = 0, 96 do
    local a = (RANDRAGE & 0x3FFFFF) + i
    if H.readRomByte(a) == 0x22
       and H.readRomWord(a + 1) == (COINPROC & 0xFFFF)
       and H.readRomByte(a + 3) == ((COINPROC >> 16) & 0xFF) then
      site = RANDRAGE + i
      break
    end
  end
  H.assertEq(site ~= nil, true, "found `jsl Ot6RageCoin` inside RandRage")

  -- the proc's ONE `inc $be` -- ot6_rand's rolling index bump
  local randSite = nil
  for i = 0, 160 do
    local a = (COINPROC & 0x3FFFFF) + i
    if H.readRomByte(a) == 0xE6 and H.readRomByte(a + 1) == 0xBE then
      randSite = COINPROC + i
      break
    end
  end
  H.assertEq(randSite ~= nil, true,
    "found ot6_rand's `inc $be` inside Ot6RageCoin")
  H.log(string.format("RandRage=%06x jsl=%06x Ot6RageCoin=%06x inc$be=%06x",
    RANDRAGE, site, COINPROC, randSite))

  -- DECODE, not seed: read $be at the proc's entry -- the next draw is
  -- RNGTbl[$be+1] -- and snapshot the caller's CPU state for the width
  -- contract
  emu.addMemoryCallback(function()
    be0 = H.readByte(0xBE)
    drawsThisRoll = 0
    tierAtEntry = H.readByte(RAGETIER)
    psAtEntry, yAtEntry = cpu()
  end, emu.callbackType.exec, COINPROC, COINPROC)

  emu.addMemoryCallback(function()
    drawsThisRoll = drawsThisRoll + 1
  end, emu.callbackType.exec, randSite, randSite)

  emu.addMemoryCallback(function() cmd10Hits = cmd10Hits + 1 end,
    emu.callbackType.exec, H.sym("Cmd_10"), H.sym("Cmd_10"))

  emu.addMemoryCallback(function()
    local ps, y = cpu()
    if psAtEntry then
      widthChecks[#widthChecks + 1] = {
        pre = psAtEntry, post = ps, ypre = yAtEntry, ypost = y,
      }
    end
  end, emu.callbackType.exec, site + 4, site + 4)

  -- the coin, read straight off the MonsterRage index (entry 0 = Fight,
  -- entry 1 = the special; X = monsterId*2 + coin)
  emu.addMemoryCallback(function(addr)
    local off = addr - MONRAGE
    coins[#coins + 1] = {
      coin = off & 1,
      id = off >> 1,
      draws = drawsThisRoll,
      be0 = be0,
      draw = be0 and H.readRomByte(RNGTBL + ((be0 + 1) & 0xFF)) or nil,
      tier = tierAtEntry,
    }
  end, emu.callbackType.read, MONRAGE, MONRAGE + 0x1FF)
end

-- assert every recorded roll against the ladder's model
local function judgeCoins(tag, tier)
  H.assertEq(#coins >= 2, true, string.format(
    "%s: the trance rolled more than once (got %d)", tag, #coins))
  for i, e in ipairs(coins) do
    H.log(string.format("  %s roll %d: tier=%s draws=%d be=%s draw=%s coin=%d"
      .. " (rage %d)", tag, i, tostring(e.tier), e.draws, tostring(e.be0),
      tostring(e.draw), e.coin, e.id))
    H.assertEq(e.tier, tier, string.format(
      "%s: every roll saw the latched tier %d -- the START turn included "
      .. "(it is rolled at action load)", tag, tier))
    if tier == 0 then
      H.assertEq(e.draws, 0,
        tag .. ": tier 0 takes NO extra RNG draw -- byte-vanilla stream")
    elseif tier == 3 then
      H.assertEq(e.draws, 0,
        tag .. ": tier 3 takes no roll at all (certainty, not a better coin)")
      H.assertEq(e.coin, 1, tag .. ": the special, every turn")
    else
      H.assertEq(e.draws, 1, string.format(
        "%s: the tilted coin took exactly one extra RNG draw", tag))
      local threshold = (tier == 1) and 0x40 or 0x10
      local want = (e.draw >= threshold) and 1 or 0
      H.assertEq(e.coin, want, string.format(
        "%s: DECODED -- the stream drew $%02x against threshold $%02x, so "
        .. "the coin must be %d (special unless draw < threshold)",
        tag, e.draw, threshold, want))
    end
  end
end

-- ============================ field + battle drives =======================
local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

local function findGauBattleSlot()
  gauSlot = nil
  for s = 0, 3 do
    if H.readByte(0x3ED8 + s * 2) == GAU then gauSlot = s end
  end
  assert(gauSlot, "GAU is in the battle party")
end

-- walk into a Veldt encounter (battle_gaufight's pacing)
local function walkIntoEncounter(what)
  local flip = false
  local hb = -1200
  return {
    (function()
      local hb2 = -900
      local stuck = 0
      return H.driveUntil(function()
        if H.frame - hb2 >= 900 then
          hb2 = H.frame
          H.log(string.format("[%s wait f%d] mode=%s ctl=%s aligned=%s zm=%02x "
            .. "(%d,%d) e7=%02x e8=%02x 19=%02x bls=%s", what, H.frame,
            tostring(H.worldMode()), tostring(H.worldHasControl()),
            tostring(H.worldAligned()), H.readByte(0x26), H.worldX(),
            H.worldY(), H.readByte(0xE7), H.readByte(0xE8), H.readByte(0x19),
            tostring(H.battleLoadStarted())))
        end
        -- a battle already loading IS an acceptable outcome: the post-battle
        -- world return can roll a fresh encounter before control ever comes
        -- back, and the walk's own driveUntil takes it from there
        if H.battleLoadStarted() then return true end
        local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
        stuck = ok and 0 or stuck + 1
        return ok
      end, 12000, {
      H.call(function()
        -- after a stuck second, nudge: A pages an undismissed victory line
        -- (a trance win under held L+R leaves one -- measured e8=$bb wedge),
        -- B backs out anything half-opened; both inert on the bare world
        if stuck < 60 then H.setPad({}); return end
        local ph = stuck % 16
        if ph < 4 then H.setPad({ a = true })
        elseif ph >= 8 and ph < 12 then H.setPad({ b = true })
        else H.setPad({}) end
      end),
      }, what .. ": world control")
    end)(),
    H.driveUntil(function() return H.battleLoadStarted() end, 40000, {
      H.call(function()
        if H.frame - hb >= 1200 then
          hb = H.frame
          H.log(string.format("[%s walk f%d] mode=%s ctl=%s aligned=%s "
            .. "(%d,%d)", what, H.frame, tostring(H.worldMode()),
            tostring(H.worldHasControl()), tostring(H.worldAligned()),
            H.worldX(), H.worldY()))
        end
        if H.battleLoadStarted() then H.setPad({}) return end
        if not H.worldHasControl() then H.setPad({}) return end
        if not H.worldAligned() then return end
        flip = not flip
        H.setPad({ [flip and "left" or "right"] = true })
      end),
    }, what .. ": a Veldt encounter fires"),
    H.call(function() H.setPad({}) end),
    H.waitUntil(function() return H.battleActive() end, 1200,
      what .. ": battle armed", 5),
    H.waitFrames(90),
    H.call(findGauBattleSlot),
  }
end

-- resolve an unwanted/finished battle: flee, then win through the menus if
-- the Veldt roster dealt an unrunnable set-piece draw (measured hazard;
-- Veldt wins award no XP, so a win cannot refill the drained pool)
local function resolveBattle(tag)
  local n, F = 0, nil
  return H.repeatN(1, {
    H.driveUntil(function() return not H.battleLoadStarted() end, 30000, {
      H.call(function()
        n = n + 1
        if n < 1200 then
          H.setPad({ l = true, r = true })
        else
          if not F then
            F = H.newFightDriver(tag .. "-win", { items = true, healPercent = 40 })
            H.log(tag .. ": flee stalled (unrunnable roster draw) -- winning")
          end
          F.frame()
        end
      end),
    }, tag .. ": battle resolved"),
    H.call(function() H.setPad({}) end),
    H.waitFrames(30),
  })
end

-- park a bench menu with X, vanilla's own turn-cycling key (the
-- battle_gaufight-proven shape).  A Defend-consume was tried and wedged on
-- kit windows (Cyan's bushido gauge does not B-cancel -- measured flap);
-- the survivability the Defends were for comes from the pre-ride cares and
-- the short rides instead.
local function deferBench()
  if H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) ~= gauSlot then
    if H.readByte(MSTATE) == ST_CMD then H.setPad({ x = true })
    else H.setPad({ b = true }) end
    return true
  end
  return false
end

local function menuForGau(what)
  local hb4 = -900
  return H.driveUntil(function()
    if H.frame - hb4 >= 900 then
      hb4 = H.frame
      H.log(string.format("[%s f%d] menu=%02x act=%02x st=%02x cur=%d "
        .. "live=%s", what, H.frame, H.readByte(MENU), H.readByte(ACTOR),
        H.readByte(MSTATE), H.readByte(0x890F + (H.readByte(ACTOR) & 3)) & 3,
        tostring(H.battleLoadStarted())))
    end
    return H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot
  end, 20000, {
    H.call(function()
      if not deferBench() then H.setPad({}) end
    end),
    H.waitFrames(2),
  }, what)
end

-- start a rage from the real menu: row 1, window, cursor steered to entry
-- 0 by d-pad, confirm through the follow-up state
local function rageStart(tag)
  return {
    menuForGau(tag .. ": gau's menu"),
    H.waitFrames(20),
    tap("down", 24),                  -- row 0 (Leap here) -> row 1 Rage
    H.driveUntil(function() return H.readByte(MSTATE) == ST_RAGE end, 1500, {
      H.call(function() H.setPad({ a = true }) end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(14),
    }, tag .. ": the rage window opens from row 1"),
    H.driveUntil(function()
      return H.readByte(MSTATE) == ST_RAGE
         and H.readByte(0x892B + gauSlot) + H.readByte(0x8933 + gauSlot) == 0
         and H.readByte(0x892F + gauSlot) == 0
    end, 1500, {
      H.call(function()
        if H.readByte(MSTATE) ~= ST_RAGE then H.setPad({}); return end
        if H.readByte(0x892F + gauSlot) > 0 then H.setPad({ left = true })
        elseif H.readByte(0x892B + gauSlot) + H.readByte(0x8933 + gauSlot) > 0
          then H.setPad({ up = true })
        else H.setPad({}) end
      end),
      H.waitFrames(2),
      H.call(function() H.setPad({}) end),
      H.waitFrames(8),
    }, tag .. ": rage cursor steered to entry 0 (d-pad, no pokes)"),
  }
end

-- confirm the start and wait for the RAGE status (or a refusal window)
local function rageLatch(tag)
  return H.driveUntil(function() return raging() end, 4000, {
    H.call(function()
      H.setPad((H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot)
               and { a = true } or {})
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(16),
  }, tag .. ": the RAGE status latches (Cmd_10 ran)")
end

-- ride the trance with the bench X-cycled, until Cmd_10 has re-entered n
-- times (a fixed 150-cycle ride measured only 2 re-entries -- the count is
-- the claim, so the count is the exit condition)
local function rideUntilTurns(tag, n, budget)
  local hb = -900
  return H.driveUntil(function()
    if H.frame - hb >= 900 then
      hb = H.frame
      local mhp = {}
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          mhp[#mhp + 1] = tostring(H.readWord(0x3BFC + m * 2))
        end
      end
      local php = {}
      for e = 0, 3 do php[#php + 1] = tostring(H.readWord(0x3BF4 + e * 2)) end
      H.log(string.format("[%s ride f%d] cmd10=%d menu=%02x act=%02x "
        .. "st=%02x raging=%s live=%s mhp=%s php=%s gauSt=%02x,%02x,%02x,%02x",
        tag, H.frame, cmd10Hits,
        H.readByte(MENU), H.readByte(ACTOR), H.readByte(MSTATE),
        tostring(raging()), tostring(H.battleLoadStarted()),
        table.concat(mhp, ","), table.concat(php, ","),
        H.readByte(0x3EE4 + gauSlot * 2), H.readByte(0x3EE5 + gauSlot * 2),
        H.readByte(0x3EF8 + gauSlot * 2), H.readByte(0x3EF9 + gauSlot * 2)))
    end
    return cmd10Hits >= n
  end, budget or 12000, {
    H.call(function()
      if H.readByte(MENU) == 0 then
        -- battle MESSAGES block the queue until dismissed (battle_slots'
        -- result-banner lesson, re-learned on this ride: a t1 trance sat at
        -- 2 re-entries for 9000 frames behind one banner)
        H.setPad(H.frame % 8 < 4 and { a = true } or {})
      elseif not deferBench() then
        H.setPad({})
      end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, tag .. ": the trance rides " .. n .. " possessed turns")
end

-- one real unboosted ITEM turn (a consumable on self): the Veldt's bankable
-- action (row 0 is Leap -- pressing it would cost us Gau; row 3 is Item).
-- The battle-item cursor is STEERED to a live Tonic/Potion row against the
-- battle inventory ($2686, 5 bytes/entry, qty at +3) -- the bag's row 0 is
-- the single Potion, and once a field care spends it a blind A on row 0
-- buzzes an empty line forever (measured, 20000-frame wedge).
local ST_ITEM = 0x0A
local USABLE = { [0xE8]=true, [0xE9]=true,   -- Tonic, Potion
                 [0xF2]=true, [0xF3]=true, [0xF5]=true }  -- Antidote,
                 -- Eyedrop, Remedy: a status cure on a healthy target is
                 -- still a real unboosted ACTION (+1 bp), and it saves the
                 -- healing bag for the healing
local function usableItemRow()
  for i = 0, 251 do
    local id = H.readByte(0x2686 + i * 5)
    if USABLE[id] and H.readByte(0x2686 + i * 5 + 3) > 0 then
      return i
    end
  end
  return nil
end
local function itemTurn(tag)
  local bp0, hb = nil, -900
  return H.repeatN(1, {
    menuForGau(tag .. ": gau's menu (item turn)"),
    H.call(function() bp0 = bpOf(gauSlot) end),
    H.driveUntil(function()
      if H.frame - hb >= 900 then
        hb = H.frame
        H.log(string.format("[%s item f%d] bp=%d menu=%02x st=%02x cur=%d "
          .. "itemcur=%d want=%s", tag, H.frame, bpOf(gauSlot),
          H.readByte(MENU), H.readByte(MSTATE),
          H.readByte(0x890F + gauSlot) & 3,
          H.readByte(0x8947 + gauSlot) + H.readByte(0x894F + gauSlot),
          tostring(usableItemRow())))
      end
      return bpOf(gauSlot) == (bp0 or 0) + 1
    end, 20000, {
      H.call(function()
        if H.readByte(MENU) == 0 then
          H.setPad(H.frame % 8 < 4 and { a = true } or {})
          return
        end
        if deferBench() then return end
        local st = H.readByte(MSTATE)
        local btn
        if st == ST_CMD then
          local cur = H.readByte(0x890F + gauSlot) & 3
          btn = (cur == 3) and "a" or "down"
        elseif st == ST_ITEM then
          local want = usableItemRow()
          if want == nil then error(tag .. ": no usable consumable left", 0) end
          local cur = H.readByte(0x8947 + gauSlot) + H.readByte(0x894F + gauSlot)
          if cur < want then btn = "down"
          elseif cur > want then btn = "up"
          else btn = "a" end
        elseif st == ST_TGT then
          btn = "a"
        else
          btn = "a"
        end
        H.setPad({ [btn] = true })
      end),
      H.waitFrames(3),
      H.call(function() H.setPad({}) end),
      H.waitFrames(9),
    }, tag .. ": a real Item turn regens +1 bp"),
  })
end

-- ============================ the field Rage page =========================
-- menu_ragepage's player path: X -> Skills -> GAU -> the Rage row -> A.
local ZMENUSTATE, ZCURSOR, ZCHARID = 0x26, 0x4B, 0x69
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_RAGELOAD = 0x05, 0x06, 0x0A, 0x7C
local SKILLS_ROW_RAGE = 5
local function st() return H.readByte(ZMENUSTATE) end

local function openRagePage(tag)
  local gauMenuSlot = nil
  return {
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, tag .. ": main menu"),
    H.waitFrames(20),
    H.call(function()
      for s = 0, 3 do
        if H.readByte(ZCHARID + s) == GAU then gauMenuSlot = s end
      end
      H.assertEq(gauMenuSlot ~= nil, true, tag .. ": GAU on the menu roster")
    end),
    H.pressButtons({ "down" }, 2),            -- Items -> Skills
    H.waitFrames(6),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      tag .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function() return H.readByte(ZCURSOR) == gauMenuSlot end, 900,
      { H.pressButtons({ "down" }, 2), H.waitFrames(8) },
      tag .. ": cursor onto GAU"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300,
      tag .. ": skills submenu", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_SKILLS and H.readByte(ZCURSOR) == SKILLS_ROW_RAGE
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(6) },
      tag .. ": skills cursor to Rage"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_RAGELOAD end, 300,
      tag .. ": rage configurator open via the player path", 5),
    H.waitFrames(60),
  }
end

-- close the field menu with the WORLD care-close discipline (ot6_field's
-- careClose, 9660a9f): a single worldHasControl frame mid-handoff is a
-- stale-live coincidence -- the world menu module keeps $26 at 05 through
-- the half-close and the position cells read garbage until the module is
-- genuinely back -- so the close is believed only when control + alignment
-- + a non-menu $26 HOLD for 30 consecutive frames.  (The first draft
-- exited on the first true frame and the follow-up walk sat inside the
-- live menu for 40000 frames pressing arrows at nothing -- measured,
-- aligned=false at garbage (175,0) the whole way.)
local function closeFieldMenu(tag)
  local calm, ph = 0, 0
  return H.driveUntil(function()
    local zm = H.readByte(0x26)
    local ok = H.worldMode() and H.worldHasControl() and H.worldAligned()
           and zm ~= 0x05 and zm ~= 0x08
    calm = ok and calm + 1 or 0
    return calm >= 30
  end, 2400, {
    H.call(function()
      ph = (ph + 1) % 12
      H.setPad(ph < 4 and { b = true } or {})
    end),
  }, tag .. ": back to the world (care-close, 30 calm frames)")
end

-- ================================ the run ================================
local KNOWN = {}                     -- the save's learned set, id order
local steps = {}
local function add(t) for _, s in ipairs(t) do steps[#steps + 1] = s end end

add({
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    KNOWN = learnedIds()
    local names = {}
    for _, id in ipairs(KNOWN) do names[#names + 1] = tostring(id) end
    H.log("$1d2c as saved: " .. #KNOWN .. " rages -- "
      .. table.concat(names, " "))
    H.assertEq(#KNOWN, 9,
      "InitRage grants NINE rages at New Game and this fixture has hunted "
      .. "none beyond them (field/init.asm:355)")
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        "OT6_RAGELOAD+" .. i .. " is $00 AS SAVED -- AUTO by inaction")
    end
  end),
})

-- step WEST off the doorstep first: the fixture parks beside Crescent
-- Mountain's entrance, and a post-victory world reload that lands on the
-- entrance tile walks straight into the cave (measured: map 0x13 mid-drain)
add({
  H.waitUntil(function()
    return H.worldMode() and H.worldHasControl() and H.worldAligned()
  end, 4000, "world control at the doorstep"),
  (function()
    return H.driveUntil(function()
      return H.worldX() <= 208 and H.worldAligned()
    end, 2400, {
      H.call(function()
        if H.battleLoadStarted() then H.setPad({}) return end
        H.setPad({ left = true })
      end),
    }, "six tiles west of the doorstep")
  end)(),
  H.call(function() H.setPad({}) end),
})

-- ---- 1. AUTO TRUNCATES + THE FILL, on the real save --------------------
add(walkIntoEncounter("arm 1 (AUTO)"))
add({
  H.call(function()
    local AUTO8 = {}
    for i = 1, 8 do AUTO8[i] = KNOWN[i] end
    assertList(AUTO8, "auto")
    H.assertEq(#learnedIds(), 9,
      "auto: and the COLLECTION is untouched -- $1d2c still holds all 9")
    -- the fill, swept to the dance list: InitBattle's $ff carpet
    local bad = nil
    for i = 8, (DANCELIST - LIST) - 1 do
      if cell(i) ~= 0xFF then bad = i break end
    end
    H.assertEq(bad, nil, string.format(
      "$257e+8..$267d is $ff-filled (first non-$ff at index %s)",
      tostring(bad)))
    H.log("AUTO: 9 learned, 8 offered -- the first eight in id order; the "
      .. "vanilla wall is unreachable by inaction (the ruling, at the real "
      .. "save's size)")
  end),
  resolveBattle("arm 1"),
  H.fieldCare({ tag = "care after arm 1", threshold = 0.55 }),
})

-- ---- 2. MANUAL, configured on the real field page ----------------------
add(openRagePage("manual config"))
add({
  -- EIGHT R presses on slot 0: freeze AUTO's window (K1..K8), then cycle
  -- slot 0 K1 -> K2 -> ... -> K9.  K9 is not in the window, so the eight
  -- stored slots are distinct and slot 0 is out of id order.
  H.repeatN(8, { H.pressButtons({ "r" }, 3), H.waitFrames(24) }),
  H.call(function()
    H.assertEq(H.readByte(RAGELOAD + 0), KNOWN[9] + 1,
      "eight R's cycled slot 0 to the NINTH learned rage (stored id+1)")
    for i = 2, 8 do
      H.assertEq(H.readByte(RAGELOAD + i - 1), KNOWN[i] + 1,
        string.format("the first edit froze AUTO's window into slot %d",
          i - 1))
    end
    H.log("MANUAL configured by play: slot 0 = K9 above K2..K8")
  end),
  closeFieldMenu("manual config"),
})
add(walkIntoEncounter("arm 2 (MANUAL)"))
add({
  H.call(function()
    local want = { KNOWN[9] }
    for i = 2, 8 do want[#want + 1] = KNOWN[i] end
    assertList(want, "manual")
    H.log("MANUAL: eight distinct ids in the player's order -- slot 0's "
      .. "K9 leads, so the list is NOT the id-order walk; and FULL EIGHT: "
      .. "exactly eight then $ff")
  end),
  resolveBattle("arm 2"),
  H.fieldCare({ tag = "care after arm 2", threshold = 0.55 }),
})

-- back to AUTO with the page's own Y (no zeroing writes)...
add(openRagePage("revert"))
add({
  H.pressButtons({ "y" }, 3),
  H.waitFrames(30),
  H.call(function()
    for i = 0, 7 do
      H.assertEq(H.readByte(RAGELOAD + i), 0,
        "Y cleared OT6_RAGELOAD+" .. i .. ": AUTO again, by the page's own "
        .. "control")
    end
  end),
  -- ...then pick the DRAIN's rage, by play: slot 0 cycled to id 25.  Rage
  -- selection is the player's own volatility control -- an early timeline
  -- rode entry 0 = rage 11 and its special wiped a 729-HP board in ONE
  -- possessed action (measured: 3x243 -> 0,0,0 inside the start action),
  -- which ends a ride battle long before "several turns" can be counted.
  -- Rage 25's species is the pool's 27-hp gnat; its special is proportionate
  -- and the rides live.  Four R presses walk the frozen window 11 -> 14 ->
  -- 19 -> 21 -> 25, verified against the live byte.
  H.driveUntil(function()
    return H.readByte(RAGELOAD + 0) == 25 + 1
  end, 1200, {
    H.pressButtons({ "r" }, 3),
    H.waitFrames(24),
  }, "drain loadout: slot 0 cycled to rage 25 (the tame special)"),
  closeFieldMenu("revert"),
})

-- a RIDE battle needs to stay alive for several possessed turns, so its
-- draw is CHOSEN: < 2 bodies or < 500 total HP is resolved and re-walked
-- (battle_gaufight's gate; Veldt wins award no XP, so resolving by a win
-- cannot refill the drained pool)
local function gatedEncounter(what)
  local steps2 = { H.call(function() H.vars.suitable = false end) }
  for n = 1, 8 do
    local w = {}
    for _, st2 in ipairs(walkIntoEncounter(what .. " draw " .. n)) do
      w[#w + 1] = st2
    end
    w[#w + 1] = H.call(function()
      local bodies, mhp, minHp = 0, 0, nil
      for m = 0, 5 do
        if H.readByte(0x3AA8 + m * 2) % 2 == 1 then
          bodies = bodies + 1
          local hp = H.readWord(0x3BFC + m * 2)
          mhp = mhp + hp
          if minHp == nil or hp < minHp then minHp = hp end
        end
      end
      -- >= 3 bodies, >= 500 total: a 2-body draw died to the start action
      -- on one timeline; the party-wipe timeline predated the field care
      -- and the tame slot-0 rage, which together carry the wilder mixes.
      -- (The roster MUTATES as resolved battles add their formations, so
      -- the gate has to describe a shape, not a formation.)
      H.vars.suitable = (bodies >= 3 and mhp >= 500)
      H.log(string.format("%s draw %d: %d bodies, %d total HP, min %s -> %s",
        what, n, bodies, mhp, tostring(minHp),
        H.vars.suitable and "FIGHT" or "resolve"))
    end)
    w[#w + 1] = H.cond(function() return not H.vars.suitable end, {
      resolveBattle(what .. " draw " .. n),
      -- care between draws: the resolve battles chew the party, and a ride
      -- entered at 0,0,43 hp wiped (measured) -- top up before re-walking
      H.fieldCare({ tag = what .. " care " .. n, threshold = 0.9 }),
    }, {})
    if n == 1 then
      for _, st2 in ipairs(w) do steps2[#steps2 + 1] = st2 end
    else
      steps2[#steps2 + 1] =
        H.cond(function() return not H.vars.suitable end, w, {})
    end
  end
  steps2[#steps2 + 1] = H.call(function()
    H.assertEq(H.vars.suitable, true,
      what .. ": the Veldt dealt a ride-sized formation within eight draws")
  end)
  return steps2
end

-- ---- 6/7/8: the trance drain -- nine starts, 72 -> 0 -------------------
-- battle 1: tier 0 (charge + free turns + byte-vanilla coins)
add(gatedEncounter("drain 1 (t0)"))
add({
  H.call(function()
    instrument()
    coins, cmd10Hits = {}, 0
    H.vars.mp0 = mp()
    H.assertEq(H.vars.mp0, 72, "Gau's real pool opens at 72 = 9 x 8 -- the "
      .. "drain's arithmetic")
  end),
})
add(rageStart("t0"))
add({
  H.call(function() coins, cmd10Hits = {}, 0 end),
  rageLatch("t0"),
  H.call(function()
    H.assertEq(mp(), H.vars.mp0 - 8,
      "the trance costs a flat 8 at the start (the Dance rule, one price "
      .. "for both possess-verbs), debited from the REAL pool")
    H.assertEq(H.readByte(RAGETIER), 0, "unboosted start latched tier 0")
    H.vars.afterStart = mp()
  end),
  rideUntilTurns("t0", 3),
  H.call(function()
    H.assertEq(raging(), true, "still possessed after riding the trance")
    H.assertEq(cmd10Hits >= 3, true, string.format(
      "the trance actually took several turns (Cmd_10 re-entered %d times)",
      cmd10Hits))
    H.assertEq(mp(), H.vars.afterStart,
      "every possessed turn after the start is FREE -- one payment, whole "
      .. "battle")
    H.assertEq(H.readByte(RAGETIER), 0,
      "the latched tier survived the mid-trance re-entries")
    judgeCoins("t0", 0)
    H.log("t0: 8 once then nothing; tier 0 byte-vanilla (zero extra draws)")
  end),
  resolveBattle("drain 1"),
  H.fieldCare({ tag = "care after drain 1", threshold = 0.55 }),
})

-- battle 2: tier 1 -- one real R press, coins decoded at threshold $40
add(gatedEncounter("drain 2 (t1)"))
add({ menuForGau("t1: gau's menu"),
  H.call(function()
    H.assertEq(bpOf(gauSlot) >= 1, true, "opens with 1 bp (Ot6InitBP)")
  end),
  H.pressButtons({ "r" }, 6), H.waitFrames(20),
  H.call(function()
    H.assertEq(pendOf(gauSlot), 1, "one real R banks pending 1")
    H.vars.mp0 = mp()
  end),
})
add(rageStart("t1"))
add({
  H.call(function() coins, cmd10Hits = {}, 0 end),
  rageLatch("t1"),
  H.call(function()
    H.assertEq(mp(), H.vars.mp0 - 8, "t1: the same flat 8")
    H.assertEq(H.readByte(RAGETIER), 1, "Cmd_10 latched the pending 1")
  end),
  rideUntilTurns("t1", 2),
  H.call(function()
    H.assertEq(H.readByte(RAGETIER), 1, "t1: the latch held")
    judgeCoins("t1", 1)
    H.log("t1: every roll's coin matched its decoded draw against $40")
  end),
  resolveBattle("drain 2"),
  H.fieldCare({ tag = "care after drain 2", threshold = 0.55 }),
})

-- battle 3: tier 2 -- one real Item turn banks 2, two R's, threshold $10
add(gatedEncounter("drain 3 (t2)"))
add({ itemTurn("t2") })
add({ menuForGau("t2: gau's menu"),
  H.repeatN(2, { H.pressButtons({ "r" }, 6), H.waitFrames(20) }),
  H.call(function()
    H.assertEq(pendOf(gauSlot), 2, "two real R's bank pending 2")
    H.vars.mp0 = mp()
  end),
})
add(rageStart("t2"))
add({
  H.call(function() coins, cmd10Hits = {}, 0 end),
  rageLatch("t2"),
  H.call(function()
    H.assertEq(mp(), H.vars.mp0 - 8, "t2: the same flat 8")
    H.assertEq(H.readByte(RAGETIER), 2, "Cmd_10 latched the pending 2")
  end),
  rideUntilTurns("t2", 2),
  H.call(function()
    H.assertEq(H.readByte(RAGETIER), 2, "t2: the latch held")
    judgeCoins("t2", 2)
  end),
  resolveBattle("drain 3"),
  H.fieldCare({ tag = "care after drain 3", threshold = 0.55 }),
})

-- battle 4: tier 3 -- two real Item turns bank 3, three R's, certainty
add(gatedEncounter("drain 4 (t3)"))
add({ itemTurn("t3 bank a") })
add({ itemTurn("t3 bank b") })
add({ menuForGau("t3: gau's menu"),
  H.repeatN(3, { H.pressButtons({ "r" }, 6), H.waitFrames(20) }),
  H.call(function()
    H.assertEq(pendOf(gauSlot), 3, "three real R's bank pending 3")
    H.vars.mp0 = mp()
  end),
})
add(rageStart("t3"))
add({
  H.call(function() coins, cmd10Hits = {}, 0 end),
  rageLatch("t3"),
  H.call(function()
    H.assertEq(mp(), H.vars.mp0 - 8, "t3: the same flat 8")
    H.assertEq(H.readByte(RAGETIER), 3, "Cmd_10 latched the pending 3")
  end),
  rideUntilTurns("t3", 2),
  H.call(function()
    H.assertEq(H.readByte(RAGETIER), 3,
      "STILL 3 after possessed re-entries -- the mid-trance Cmd_10s did not "
      .. "re-latch the consumed pending byte")
    H.assertEq(pendOf(gauSlot), 0,
      "the pending boost itself was consumed by the start action")
    judgeCoins("t3", 3)
    -- the width contract, on the crossings the tier rides really took
    H.assertEq(#widthChecks > 0, true, "the width probe fired")
    local badW, badY = 0, 0
    for _, w in ipairs(widthChecks) do
      if (w.pre & 0x10) ~= (w.post & 0x10) then badW = badW + 1 end
      if w.ypre ~= w.ypost then badY = badY + 1 end
    end
    H.assertEq(badW, 0, "Ot6RageCoin handed the caller's INDEX WIDTH back "
      .. "on every crossing")
    H.assertEq(badY, 0, "and Y came back unchanged")
    H.log("t3: certainty (entry 1, zero draws) and the width contract held "
      .. "over " .. #widthChecks .. " crossings")
  end),
  resolveBattle("drain 4"),
  H.fieldCare({ tag = "care after drain 4", threshold = 0.55 }),
})

-- battles 5-9: quick drains -- five more real starts, 40 -> 0
for n = 5, 9 do
  add(walkIntoEncounter("drain " .. n))
  add({ H.call(function() H.vars.mp0 = mp() end) })
  add(rageStart("drain " .. n))
  add({
    rageLatch("drain " .. n),
    H.call(function()
      H.assertEq(mp(), H.vars.mp0 - 8, string.format(
        "drain %d: 8 more gone (%d left)", n, mp()))
    end),
    resolveBattle("drain " .. n),
    H.fieldCare({ tag = "care after drain " .. n, threshold = 0.85 }),
  })
end

-- ---- 6b + 9b: the ZERO battle -- refusal, then the free Leap ------------
local COSTQ = 0x3620
local CMD_LEAP = 0x11
local leapCosts, caeHits, mpSeen = {}, 0, {}
local leapWatch = false

add(walkIntoEncounter("the zero battle"))
add({
  H.call(function()
    H.assertEq(mp(), 0,
      "nine real starts drained the real 72-MP pool to EXACTLY ZERO -- the "
      .. "refusal and the Leap floor are now play, not pokes")
    emu.addMemoryCallback(function(_, v)
      if leapWatch and H.readByte(0x3A7A) == CMD_LEAP then
        leapCosts[#leapCosts + 1] = v
      end
    end, emu.callbackType.write, 0x7E0000 + COSTQ, 0x7E0000 + COSTQ + 0xFE)
    emu.addMemoryCallback(function() caeHits = caeHits + 1 end,
      emu.callbackType.exec, H.sym("CalcAttackEffect"),
      H.sym("CalcAttackEffect"))
  end),
})
add(rageStart("refuse"))
add({
  -- the confirm: A on the rage window at 0 MP.  The gate must refuse --
  -- ride a window and assert the status never set.
  H.repeatN(40, {
    H.call(function()
      H.setPad((H.readByte(MENU) ~= 0 and (H.readByte(ACTOR) & 3) == gauSlot
                and H.readByte(MSTATE) == ST_RAGE) and { a = true } or {})
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }),
  H.call(function()
    H.assertEq(raging(), false,
      "an unpayable rage START never sets the whole-battle RAGE status -- "
      .. "the #34 lesson, re-applied (Ot6RageStartGate)")
    H.assertEq(mp(), 0, "and MP was not driven negative")
    H.log("REFUSED at zero, honestly earned zero")
  end),
  -- back out of the rage window to the command row
  H.driveUntil(function() return H.readByte(MSTATE) ~= ST_RAGE end, 900, {
    H.call(function() H.setPad({ b = true }) end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(10),
  }, "refuse: rage window backed out"),
  -- 9b. LEAP AT ZERO: row 0 IS Leap on the Veldt (battle_gaufight's rule);
  -- it must stage cost 0, resolve through CalcAttackEffect, and leave the
  -- pool at 0 across every live sample.
  H.call(function()
    leapCosts, mpSeen, caeHits = {}, {}, 0
    leapWatch = true
  end),
  H.driveUntil(function() return #leapCosts > 0 end, 8000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      if deferBench() then return end
      local st = H.readByte(MSTATE)
      local btn
      if st == ST_CMD then
        local cur = H.readByte(0x890F + gauSlot) & 3
        btn = (cur == 0) and "a" or "up"
      elseif st == ST_TGT then
        btn = "a"
      else
        btn = "a"
      end
      H.setPad({ [btn] = true })
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(9),
  }, "leap-zero: CreateAction stages a cost for command $11"),
  H.repeatN(40, {
    H.call(function()
      if H.battleLoadStarted() then mpSeen[#mpSeen + 1] = mp() end
      if not deferBench() then H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }),
  H.call(function()
    leapWatch = false
    local lo = nil
    for _, v in ipairs(mpSeen) do if not lo or v < lo then lo = v end end
    H.log(string.format("leap-zero: staged=%s cae=%d floor=%s samples=%d",
      tostring(leapCosts[1]), caeHits, tostring(lo), #mpSeen))
    H.assertEq(leapCosts[1], 0,
      "an EMPTY pool stages 0 for command $11: Ot6AbilityCost has no "
      .. "cmd-$11 arm (owner reversal 2026-07-29) -- pre-change this staged "
      .. "2 and the short-pool arm ate the turn")
    H.assertEq(caeHits > 0, true,
      "positive control: CalcAttackEffect actually RAN on the empty pool")
    H.assertEq(#mpSeen > 0, true, "the pool was sampled inside a LIVE battle")
    H.assertEq(lo, 0,
      "and the pool is still 0 across every live sample -- nothing spent, "
      .. "nothing negative: a Gau at zero MP still takes the Veldt's action, "
      .. "which is what makes sharing the FIGHT row safe (#47)")
  end),
})

-- ---- 9a. LEAP AT A FULL POOL (fresh reload -- the drain is spent) --------
add({
  H.loadState(STATE),
  H.waitFrames(20),
})
add(walkIntoEncounter("leap (full pool)"))
add({
  H.call(function()
    H.vars.mp0 = mp()
    H.assertEq(H.vars.mp0, 72, "the reloaded pool is full again")
    leapCosts, mpSeen, caeHits = {}, {}, 0
    leapWatch = true
  end),
  H.driveUntil(function() return #leapCosts > 0 end, 8000, {
    H.call(function()
      if H.readByte(MENU) == 0 then H.setPad({}); return end
      if deferBench() then return end
      local st = H.readByte(MSTATE)
      local btn
      if st == ST_CMD then
        local cur = H.readByte(0x890F + gauSlot) & 3
        btn = (cur == 0) and "a" or "up"
      elseif st == ST_TGT then
        btn = "a"
      else
        btn = "a"
      end
      H.setPad({ [btn] = true })
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(9),
  }, "leap: CreateAction stages a cost for command $11"),
  H.repeatN(40, {
    H.call(function()
      if H.battleLoadStarted() then mpSeen[#mpSeen + 1] = mp() end
      if not deferBench() then H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }),
  H.call(function()
    leapWatch = false
    local lo = nil
    for _, v in ipairs(mpSeen) do if not lo or v < lo then lo = v end end
    H.log(string.format("leap: staged=%s cae=%d floor=%s samples=%d",
      tostring(leapCosts[1]), caeHits, tostring(lo), #mpSeen))
    H.assertEq(leapCosts[1], 0,
      "CreateAction staged 0 for command $11 at a full pool -- the price "
      .. "does not depend on affordability.  Pre-change this read 2 "
      .. "(Ot6LeapCost)")
    H.assertEq(caeHits > 0, true, "positive control: CalcAttackEffect RAN")
    H.assertEq(#mpSeen > 0, true, "the pool was sampled inside a LIVE battle")
    H.assertEq(lo, H.vars.mp0,
      "and the universal charge took NOTHING: the pool never dipped below "
      .. "where it started.  Pre-change its floor was 70 -- the flat 2")
  end),
})

-- ======================================================================= --
-- *** LABELED ISOLATION ARM (issue #75) -- see the header. ***
-- The two sub-floor collection claims, unreachable by play: 1b VANILLA-WALK
-- EQUIVALENCE below the eight-wide window, and 3 VALIDATION of a
-- stored-but-unlearned slot.  The writes below (the $1d2c bitfield set to
-- six species; loadout bytes carrying an unlearned id) exist only here and
-- MAY NEVER PRODUCE FIXTURES.
-- ======================================================================= --
local SIX = { 11, 14, 19, 21, 25, 46 }
add({
  H.loadState(STATE),
  H.waitFrames(20),
  H.call(function()
    H.log("*** LABELED ISOLATION ARM: sub-floor collection states ***")
    for i = 0, 31 do H.writeByte(RAGES + i, 0) end
    for _, id in ipairs(SIX) do
      local a = RAGES + (id >> 3)
      H.writeByte(a, H.readByte(a) | (1 << (id & 7)))
    end
  end),
})
add(walkIntoEncounter("isolation arm (vanilla equiv)"))
add({
  H.call(function()
    local ids = learnedIds()
    H.assertEq(#ids, #SIX, "isolation arm: six species in the bitfield")
    assertList(ids, "vanilla-equiv")   -- the WHOLE walk, byte for byte
    H.log("[isolation arm] VANILLA-WALK EQUIVALENCE: with 6 learned (<= 8) "
      .. "the AUTO list is the full id-order walk -- the truncation only "
      .. "bites past eight")
  end),
  resolveBattle("isolation arm 1b"),
})
add({
  H.call(function()
    -- 3. VALIDATION: a stored id whose $1d2c bit is clear must be dropped
    -- from the list while the surviving slots keep their order.
    H.writeByte(RAGELOAD + 0, 66 + 1)   -- learned?  no: only SIX are now
    H.writeByte(RAGELOAD + 1, 54 + 1)   -- no again
    H.writeByte(RAGELOAD + 2, 11 + 1)   -- yes
    H.writeByte(RAGELOAD + 3, 19 + 1)   -- yes
    for i = 4, 7 do H.writeByte(RAGELOAD + i, 0) end
  end),
})
add(walkIntoEncounter("isolation arm (validation)"))
add({
  H.call(function()
    assertList({ 11, 19 }, "validate")
    H.log("[isolation arm] VALIDATION: unlearned stored ids are dropped and "
      .. "the surviving slots keep their order")
    H.log("PASSED: list filter + AUTO truncation, the field-configured "
      .. "MANUAL order, the flat-8 trance with free possessed turns, the "
      .. "earned-zero refusal, the tier latch and the decoded ladder, the "
      .. "width contract, and Leap free at 72 and at 0")
  end),
})

H.run({ maxFrames = 500000 }, steps)
