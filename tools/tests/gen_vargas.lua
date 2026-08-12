-- gen_vargas.lua -- from vargas_entry.mss: fight Vargas with real input, ride
-- the reunion, and generate vargas_won.mss on the first controllable frame
-- after it.  This is the last tier-2 link in the generated chain, and the
-- first boss in the chain of generated savestates won by a played strategy
-- under issue #75's rule: inputs in, observations out, no writes to emulated
-- game state.  The old generator pinned party HP/MP every frame, clamped
-- Vargas to 10300 to force his phase-2 event, and poked the Blitz cursor
-- cells; all of that is gone.
--
-- The fight (bosses-wob.md section 3, which both human playtests rated well):
-- Vargas (11600 hp, 5 shields, weak poison|holy + bludgeoning) plus two
-- Ipoohs (360 hp, 2 shields, slash-weak).  Two phases; only the second
-- has SABIN in it.  His turns start after Vargas's own reaction script
-- runs `battle_event $07` at hp <= 10880 and `$08` at hp <= 10368
-- (ai_script.asm:4392-4404), so real damage has to cross those thresholds.
-- The kill is Pummel: the script answers `if_attack PUMMEL` with
-- `battle_event $09 / kill_monsters ALL` (:4385-4388), so he dies to the
-- script rather than to hp, which is the intended design ("Jank: the Blitz
-- gate stays").
--
-- The strategy, all closed-loop on readable menu state (every cell below
-- was located in btlgfx_main.asm and verified live by probe runs):
--   * the trio spends Boost Points on Fights: R presses raise pending
--     ($3E9D+slot, bank $3E9C+slot, cap 3) and a boosted Fight is what
--     killed both Ipoohs in about a round each, measured;
--   * Potions (bag carries 3; battle inventory $2686, 5 bytes/entry, qty
--     at +3) go to whoever is under 30% -- selected in the item window
--     (mstate $0A, row cursor $894F), aimed through the real target
--     cursor ($38: char mask $7B7D / monster mask $7B7E, walked with the
--     pad until the mask is the wanted ally);
--   * TERRA plays medic once the potions thin out: Magic (her cmd cell,
--     found in $202E and reached by the command cursor $890F+slot) ->
--     Cure.  Her battle spell list is packed at $2092+$0278 (4
--     bytes/entry: id, flags bit7=disabled, targeting, cost), Cure ($2D)
--     is entry 0, grid cell (idx//2, idx%2) via the magic cursor triple
--     $8913/$8917/$891B+slot -- aimed at the weakest hurt ally;
--   * SABIN, phase 2: Blitz (cmd $0A) opens the v0.3 tools-shell menu
--     (mstate $30), PUMMEL ($5D) is found by scanning wItemList ($4005)
--     and reached by walking the real cursor triple $895F/$8963/$8967 --
--     pad edges only, then A, then A on the target.  No cell is ever
--     written; every press is verified by re-reading the cursor.
-- Timing note the whole machine depends on: submenus (item/magic/tools/
-- target) freeze battle time (wait-mode) and the command list does not,
-- so menu navigation is safe however long it takes, and the fight's
-- risk is confined to the open field between menus.
--
-- Measured (probe_vargas_win2/win5 off the tier-2 fixture): the policy
-- wins in ~13000 battle frames.  Both Ipoohs die to boosted Fights by
-- ~f3300; three potions and two Cures carry the trio through Gale Cut;
-- Vargas crosses his own script's gates at real hp (11600 -> 10304); the
-- trio is blown offstage; Sabin's first menu picks Pummel from the real
-- blitz list and the script ends the fight.  Terra fell to a Gale Cut
-- burst in both winning runs; the fixture keeps that outcome if it happens,
-- and the roster dump below records what the party looked like.
--
-- The retry ladder is the game's own defeat flow made explicit: the
-- entry point is captured once at boot (a savestate blob in memory, with no
-- writes); a party wipe tears the battle down into Game Over instead of
-- the reunion, the attempt's post-fight ride ends there rather than on
-- "map 98, calm, SABIN in the party", and the next attempt reloads the entry
-- point blob and takes a different battle RNG phase before the opening
-- A-press, shifting every RNG draw downstream.  Three attempts, then fail.
-- The ride is passed wipeEndsRide because the shared wipe canary otherwise
-- raises on the first loss and no ladder here ever reaches rung two.
--
-- The generate is verified by reload (gen_sabin_gau's discipline): capture,
-- reload the capture as the consumer timeline, give it 300 frames, and
-- require the same calm map-98 field before accepting the blob.
local H = dofile("tools/tests/lib/ot6.lua")
-- The VARGAS ladder's spread and its collision check (issue #83): each
-- attempt is held until the game-time frame counter the battle seed is
-- made of reaches its own phase, and L.report() fails if two attempts drew
-- one seed, which would make this ladder one fight replayed.  Three
-- attempts, 20 phases apart, which is the widest even spacing the 60-phase
-- cycle allows and the doctrine's count (#74).
local L = H.newSeedLadder("battle 66")
local DOOR = "build/states/vargas_entry.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_CMD, ST_TOOLS, ST_TGT, ST_ITEM, ST_MAGIC = 0x05, 0x30, 0x38, 0x0A, 0x0E
local ITEMLIST = 0x4005                 -- wItemList: tools-shell rows, 3/entry
local BATTINV  = 0x2686                 -- battle inventory, 5 bytes/entry
local CMDTBL   = 0x202E                 -- in-battle commands, slot*12 + i*3
local POTION, TONIC, PUMMEL = 0xE9, 0xE8, 0x5D
local CURE_ID  = 0x2D
-- packed per-character battle spell lists: $2092 + ptr[slot] + idx*4
local SPELL_PTR = { [0] = 0x0000, [1] = 0x013C, [2] = 0x0278, [3] = 0x03B4 }
local SABIN_E, TERRA_E = 3, 2
local VARGAS = 0x0103

local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function hp(e) return H.readWord(0x3BF4 + e * 2) end
local function maxhp(e) return H.readWord(0x3C1C + e * 2) end
local function mp(e) return H.readWord(0x3C08 + e * 2) end
local function bp(e) return H.readByte(0x3E9C + e * 2) end
local function pend(e) return H.readByte(0x3E9D + e * 2) end
local function alive(e) return hp(e) > 0 end
local function vHp() return H.readWord(0x3BFC) end

local function itemSlot(id)
  for i = 0, 15 do
    if H.readByte(BATTINV + i * 5) == id
       and H.readByte(BATTINV + i * 5 + 3) > 0 then return i end
  end
  return nil
end
local function spellIndexOf(slot, id)
  for i = 0, 15 do
    local a = 0x2092 + SPELL_PTR[slot] + i * 4
    if H.readByte(a) == id and (H.readByte(a + 1) & 0x80) == 0 then return i end
  end
  return nil
end

local healBusy = {}                      -- target -> frame a heal was queued
local function needsHeal(thresh)
  local best, bestR = nil, 1.0
  for e = 0, 2 do
    if alive(e) and maxhp(e) > 0 then
      local r = hp(e) / maxhp(e)
      if r < thresh and r < bestR
         and (not healBusy[e] or H.frame - healBusy[e] > 900) then
        best, bestR = e, r
      end
    end
  end
  return best
end

local function hpLine()
  local s = ""
  for e = 0, 3 do
    s = s .. string.format(" e%d=%d/%d(b%d,%dmp)", e, hp(e), maxhp(e),
      bp(e), mp(e))
  end
  local pot = itemSlot(POTION)
  return s .. string.format(" V=%d pots=%d", vHp(),
    pot and H.readByte(BATTINV + pot * 5 + 3) or 0)
end

-- ------------------------------------------------- the per-menu machine --
-- One pulse per frame while a menu is up.  M resets on every actor change
-- and whenever the menu closes; the plan is decided once per fresh menu
-- from live reads.  Presses are 5-on/5-off edges; every cursor move is
-- verified by re-reading the cell it targets, and a watchdog backs out
-- with B and falls back to a plain Fight rather than stalling.
local M = {}
local function resetM()
  M.actor, M.n, M.plan, M.via, M.d = nil, 0, nil, nil, 0
  M.lastCur, M.dirI = nil, nil
end
resetM()
local sabinPummeled = false
-- VARGAS's hp the last time the fight was live, latched per frame so a
-- lost attempt can say how far it got after the battle RAM is gone
local lastVargasHp = 0

local function decidePlan(a)
  if a == SABIN_E then return { kind = "pummel" } end
  local emerg = needsHeal(0.30)
  if emerg then
    local slot = itemSlot(POTION) or itemSlot(TONIC)
    if slot then return { kind = "potion", target = emerg, slot = slot } end
  end
  if a == TERRA_E and mp(TERRA_E) >= 10 then
    local t = needsHeal(0.60)
    if t then return { kind = "cure", target = t } end
  end
  return { kind = "fight" }
end

local function pulse()
  local a = H.readByte(ACTOR)
  if M.actor ~= a then
    resetM()
    M.actor, M.plan = a, decidePlan(a)
    if M.plan.kind ~= "fight" then
      H.log(string.format("[vargas plan f%d] actor=%d %s tgt=%s |%s",
        H.frame, a, M.plan.kind, tostring(M.plan.target), hpLine()))
    end
  end
  M.n = M.n + 1
  local ph = M.n % 10
  local st = H.readByte(MSTATE)
  if M.n > 1200 then                     -- wedge watchdog: back out, Fight
    H.log(string.format("[vargas wd f%d] actor=%d st=%02X plan=%s",
      H.frame, a, st, M.plan.kind))
    M.n, M.via, M.d = 0, nil, 0
    M.plan = { kind = "fight" }
    return { "b" }
  end
  if st == ST_CMD then
    M.via = nil
    local wantCmd = 0x00                                    -- Fight
    if M.plan.kind == "potion" then wantCmd = 0x01 end      -- Item
    if M.plan.kind == "cure" then wantCmd = 0x02 end        -- Magic
    if M.plan.kind == "pummel" then wantCmd = 0x0A end      -- Blitz
    local wantCell = nil
    for i = 0, 3 do
      if H.readByte(CMDTBL + a * 12 + i * 3) == wantCmd then wantCell = i end
    end
    if wantCell == nil then M.plan = { kind = "fight" }; wantCell = 0 end
    local cur = H.readByte(0x890F + a)
    if cur == wantCell then
      if M.plan.kind == "fight" then
        local want = math.min(bp(a), 3)
        if pend(a) < want then return (ph < 5) and { "r" } or {} end
      end
      return (ph < 5) and { "a" } or {}
    end
    -- move the command cursor; a direction that is measured not to move
    -- rotates to the next, so the window's d-pad semantics are not
    -- assumed
    local DIRS = { "down", "up", "left", "right" }
    if ph == 0 then
      if M.lastCur == cur then M.dirI = ((M.dirI or 0) % 4) + 1
      else M.dirI = M.dirI or 1 end
      M.lastCur = cur
    end
    return (ph < 5) and { DIRS[M.dirI or 1] } or {}
  end
  if st == ST_ITEM then
    M.d = 0
    if M.plan.kind ~= "potion" then return (ph < 5) and { "b" } or {} end
    M.via = "item"
    local cr = H.readByte(0x894F)
    if cr ~= M.plan.slot then
      return (ph < 5) and { (cr < M.plan.slot) and "down" or "up" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_MAGIC then
    M.d = 0
    if M.plan.kind ~= "cure" then return (ph < 5) and { "b" } or {} end
    M.via = "magic"
    local idx = spellIndexOf(a, CURE_ID)
    if idx == nil then
      M.plan = { kind = "fight" }
      return (ph < 5) and { "b" } or {}
    end
    local wantRow, wantCol = idx // 2, idx % 2
    local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
    local col = H.readByte(0x8917 + a)
    if absRow ~= wantRow then
      return (ph < 5) and { (absRow < wantRow) and "down" or "up" } or {}
    end
    if col ~= wantCol then
      return (ph < 5) and { (col < wantCol) and "right" or "left" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TOOLS then
    M.d = 0
    if M.plan.kind ~= "pummel" then return (ph < 5) and { "b" } or {} end
    M.via = "blitz"
    local row, col = nil, nil
    for i = 0, 7 do
      if H.readByte(ITEMLIST + i * 3) == PUMMEL then row, col = i // 2, i % 2 end
    end
    if row == nil then return {} end     -- list still building
    local cr, cc = H.readByte(0x8967 + a), H.readByte(0x8963 + a)
    if cr ~= row then return (ph < 5) and { (cr < row) and "down" or "up" } or {} end
    if cc ~= col then return (ph < 5) and { (cc < col) and "right" or "left" } or {} end
    -- The confirm on the PUMMEL row itself is where the choice is made, and
    -- it is the only place that is true on every path.  Pummel does not
    -- always route through the target window -- measured 2026-08-11, a
    -- winning run where SABIN's turn at f26022 planned pummel, spent 4 MP
    -- and took VARGAS from 10863 to 10743 with the script then ending the
    -- fight, while ST_TGT was never entered -- so a flag set only there
    -- reported pummeled=false on a fight the Pummel had just won.  That
    -- reads as "the drive never reached the ability", which is the exact
    -- wrong conclusion, and it was in the log of the failing run this
    -- branch was sent to diagnose.
    if not sabinPummeled then
      sabinPummeled = true
      H.log(string.format("[vargas] PUMMEL chosen at f%d, V=%d", H.frame, vHp()))
    end
    return (ph < 5) and { "a" } or {}
  end
  if st == ST_TGT then
    if M.plan.kind == "potion" or M.plan.kind == "cure" then
      if M.via ~= "item" and M.via ~= "magic" then
        return (ph < 5) and { "b" } or {}   -- reached via a stray Fight
      end
      local want = 1 << M.plan.target
      if H.readByte(0x7B7E) ~= 0 then
        return (ph < 5) and { "left" } or {}
      end
      if H.readByte(0x7B7D) ~= want then
        M.d = M.d + 1
        if M.d > 40 then                    -- take whoever is under it
          healBusy[M.plan.target] = H.frame
          return (ph < 5) and { "a" } or {}
        end
        return (ph < 5) and { "down" } or {}
      end
      healBusy[M.plan.target] = H.frame
      return (ph < 5) and { "a" } or {}
    end
    if M.plan.kind == "pummel" then
      if M.via ~= "blitz" then return (ph < 5) and { "b" } or {} end
      -- the target window, when Pummel opens one at all; the flag is
      -- already set by the row confirm above, which every path passes
      return (ph < 5) and { "a" } or {}
    end
    return (ph < 5) and { "a" } or {}
  end
  return {}                              -- transient open/close: hands off
end

-- --------------------------------------------------- the retry ladder --
local entryBlob = nil                 -- captured once, below
local fightWon = false

local function fightAttempt(n)
  local aPh = 0
  local loadReq
  return H.cond(function() return not fightWon end, {
    H.logStep(function()
      return string.format("[vargas] attempt %d begins at f%d", n, H.frame)
    end),
    -- attempts past the first rewind to the entry point; every attempt then
    -- takes its own battle RNG phase, below, before the opening A-press
    H.cond(function() return n > 1 end, {
      H.call(function()
        loadReq = H.requestLoadState(entryBlob)
      end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(loadReq, "attempt " .. n .. ": entry point reload")
      end),
      -- The wait this replaces was 30 + n * 37, so a reloaded attempt had at
      -- least 104 frames before it pressed anything.  Part of that number was
      -- the RNG stagger and part of it was letting the loaded state settle;
      -- only the stagger moved to L.spread, which can legitimately wait zero
      -- frames.  90 is the settle every other reload in the tree uses.
      H.waitFrames(90),
    }, {}),
    -- Outside the n > 1 branch, unlike the wait it replaces: attempt 1 needs
    -- a phase of its own too, or it sits wherever the route left it and can
    -- land on another attempt's seed (#83).
    L.spread(n),                        -- spread the battle RNG phase (#83)
    H.call(function()
      resetM()
      sabinPummeled = false
      lastVargasHp = 0
      for k in pairs(healBusy) do healBusy[k] = nil end
    end),
    -- one interaction -> the scene -> battle 66
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        aPh = (aPh + 1) % 8
        H.setPad(aPh < 4 and { "a" } or {})
      end),
    }, "the VARGAS scene reaches battle 66"),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 3000, "battle up", 10),
    H.waitFrames(120),
    H.call(function()
      H.assertEq(H.readWord(0x57C0), VARGAS, "VARGAS ($0103) leads the formation")
      H.log("[vargas seed]" .. hpLine())
    end),
    -- play it to teardown; the pred is the same for a win or a wipe
    (function()
      local hb = -600
      return H.driveUntil(function()
        return not H.battleLoadStarted()
      end, 120000, {
        H.call(function()
          lastVargasHp = vHp()
          if H.frame - hb >= 600 then
            hb = H.frame
            H.log(string.format("[vargas f%d]%s", H.frame, hpLine()))
          end
          local aP = H.frame % 8
          if H.readByte(MENU) == 0 then
            resetM()
            H.setPad(aP < 4 and { "a" } or {})
            return
          end
          H.setPad(pulse())
        end),
      }, "battle 66 tears down (win or wipe)")
    end)(),
    H.call(function()
      H.setPad({})
      H.log(string.format("[vargas] teardown at f%d (pummeled=%s)",
        H.frame, tostring(sabinPummeled)))
    end),
    -- the verdict: a win rides _ca828f's tail to a settled map-98 field with
    -- SABIN in the party; a wipe rides the defeat flow to Game Over, and
    -- wipeEndsRide is what lets this attempt end there and the next one
    -- start.  Without it the shared wipe canary raises on the first lost
    -- attempt and the ladder never reaches its second rung: measured
    -- 2026-08-11 on the v0.10 tip, attempt 1 wiped with VARGAS at 11065 of
    -- 11600 and the run ended with no "attempt 2 begins" line in the log, so
    -- this generator had a four-rung ladder that could only ever run one.
    -- The soft giveUp bound below stays as the backstop for a lost attempt
    -- that does not wipe (a stalled reunion, say); the wipe path just no
    -- longer costs 28000 frames to notice.
    (function()
      local calmN, giveUp = 0, 0
      return H.advanceStory(function()
        giveUp = giveUp + 1
        if giveUp > 28000 then return true end       -- soft timeout: no win
        local ok = (H.mapId() & 0x1ff) == 98 and H.hasControl()
          and H.tileAligned() and bright() >= 15
          and not H.battleLoadStarted()
          and (H.readByte(0x1855) & 0x07) ~= 0       -- SABIN joined
        calmN = ok and calmN + 1 or 0
        if calmN >= 30 then fightWon = true; return true end
        return false
      end, 30000, { playBattles = true, wipeEndsRide = true })
    end)(),
    H.logStep(function()
      -- no hpLine() here: the battle module has handed its RAM back by now,
      -- so $3BF4 would read whatever the field module put there
      return string.format("[vargas] attempt %d verdict: %s (VARGAS was at " ..
        "%d when the fight tore down, pummeled=%s)", n,
        fightWon and "WON -- reunion settled" or "lost (retrying)",
        lastVargasHp, tostring(sabinPummeled))
    end),
  }, {})
end

-- ------------------------------------- reload-verified generation (gau) --
local genBlob, genDone = nil, false
local function genAttempt(n)
  local tag = string.format("[vargas_won] generation attempt %d", n)
  local saveReq, loadReq
  local mx, my
  return H.cond(function() return not genDone end, {
    H.call(function()
      mx, my = H.fieldX(), H.fieldY()
      saveReq = H.requestSaveState()
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(saveReq, tag .. ": capture")
      genBlob = saveReq.blob
      H.log(string.format("%s: captured %d bytes at (%d,%d) f%d -- " ..
        "reloading to verify the consumer's boot", tag, #genBlob, mx, my,
        H.frame))
      loadReq = H.requestLoadState(genBlob)
    end),
    H.waitFrames(2),
    H.call(function() H.checkReq(loadReq, tag .. ": verify reload") end),
    H.waitFrames(300),
    H.cond(function()
      return (H.mapId() & 0x1ff) == 98 and H.hasControl() and H.tileAligned()
         and not H.battleLoadStarted()
         and H.fieldX() == mx and H.fieldY() == my
    end, {
      H.call(function()
        genDone = true
        H.log(tag .. ": reload stayed calm on map 98 -- verified")
      end),
    }, {
      H.logStep(function()
        return string.format("%s: reload NOT calm (map=%d ctl=%s at %d,%d)",
          tag, H.mapId() & 0x1ff, tostring(H.hasControl()),
          H.fieldX(), H.fieldY())
      end),
      H.advanceStory(function()
        return H.hasControl() and H.tileAligned()
           and not H.battleLoadStarted()
      end, 9000, { playBattles = true }),
      H.waitFrames(60),
    }),
  }, {})
end

H.run({ maxFrames = 700000 }, {
  H.loadState(DOOR),
  H.waitFrames(30),
  -- capture the entry point once: the retry ladder's rewind point.  The blob
  -- is this boot's own state, and nothing is written to the game.
  (function()
    local req
    return H.cond(function() return true end, {
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "entry point capture")
        entryBlob = req.blob
        H.log(string.format("entry point captured (%d bytes) for the retry ladder",
          #entryBlob))
      end),
    }, {})
  end)(),

  L.watch(),
  fightAttempt(1),
  fightAttempt(2),
  fightAttempt(3),
  -- Before the verdict, not after: the attempts are evidence only if they
  -- were DIFFERENT fights, and if they were not, that is what this run should
  -- report rather than "lost all three" (#83).
  L.report(),
  H.call(function()
    H.assertEq(fightWon, true,
      "VARGAS beaten within 3 attempts (real damage, real menus)")
  end),
  H.waitFrames(30),

  -- ===================================================================== --
  -- Heal the party.  TERRA falls to a Gale Cut burst in most winning
  -- runs, and this generator keeps that outcome, but leaving her down was
  -- only ever a consequence of an empty bag: until gen_kolts
  -- started shopping there was no Fenix Down within three chapters of
  -- here, so the party walked into the Returner caves with her dead
  -- because nothing could raise her, not because a player would leave her.
  -- A player raises her immediately.  H.fieldCare does that through the real
  -- Item windows, threshold 0.9, and it is a no-op that does not open the
  -- menu if the fight ended with no casualties.
  H.fieldCare({ tag = "post-vargas care", threshold = 0.9 }),

  -- ===================================================================== --
  -- Assert the reunion's outcome and generate, reload-verified.
  -- ===================================================================== --
  H.call(function()
    H.assertEq(H.mapId() & 0x1ff, 98, "back on map 98 after the reunion")
    H.assertEq(H.hasControl(), true, "controllable")
    H.assertEq(H.tileAligned(), true, "tile-aligned")
    H.assertEq(H.battleLoadStarted(), false, "no battle")
    H.assertEq((H.readByte(0x1855) & 0x07) ~= 0, true,
      "SABIN is in the party ($1855)")
    -- and the whole party leaves here alive
    for _, c in ipairs(H.partyMembers()) do
      H.assertEq(H.charHp(c) > 0, true,
        string.format("char %d leaves Mt. Kolts alive", c))
    end
    for c = 0, 15 do
      if (H.readByte(0x1850 + c) & 0x07) ~= 0 then
        local base = 0x1600 + 37 * c
        H.log(string.format("char %2d actor=%02X level=%d hp=%d/%d mp=%d/%d",
          c, H.readByte(base), H.readByte(base + 8),
          H.readWord(base + 9), H.readWord(base + 11),
          H.readWord(base + 13), H.readWord(base + 15)))
      end
    end
    H.log(string.format("vargas_won: map=%d at (%d,%d)",
      H.mapId() & 0x1ff, H.fieldX(), H.fieldY()))
    H.screenshot("vargas_won")
  end),
  genAttempt(1),
  genAttempt(2),
  genAttempt(3),
  H.call(function()
    H.assertEq(genDone, true,
      "a reload-verified calm vargas_won capture within 3 attempts")
    H.emitBlob("vargas_won.mss", genBlob)
  end),
  H.logStep(function()
    return string.format("vargas_won generated at frame %d", H.frame)
  end),
})
