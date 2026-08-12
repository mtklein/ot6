-- probe_cranes_water.lua -- read-only instrument (issue #75, the Cranes
-- vanilla-playbook re-test): measures whether the fight's designed key
-- turns it.
--
-- The wall record (gen_terra_returned_checkpoint header) reports every
-- input-driven configuration wiping by ~f8400 and describes the designed
-- counter, water (bosses-wob.md 16), as "unobtainable by the mandated
-- party".  probe_cranes_loadout falsified that premise: BISMARK ($1A69 bit
-- 7) is owned at n128_won, everyone can pay Sea Song's 50 MP, and Sea Song
-- ($3d: water 58, all enemies) hits both Cranes' shared weakness while
-- feeding neither absorb ($10D absorbs bolt $04, $10E fire $01;
-- monster_prop.dat +23).  SHIVA's Diamond Dust ($38: ice, power 34 with a
-- Slow rider, all enemies; battle_magicite's re-authoring) is also
-- absorb-clean here.
--
-- So this probe plays the fight the way a player reading the vanilla
-- playbook would:
--   * BISMARK equipped on the lead and SHIVA on the second rider, through
--     the real Skills -> Espers -> detail -> A menu (skills.asm
--     MenuState_4d @5902 "equip esper"), before stepping on the reunion
--     trigger;
--   * the fight driver's new opts.summon fires each stone's divine once
--     (engine latch $3f2e), then falls back to the measured tactical kit
--     (boosted Tools/Blitz/Fights, bank 1), all of which is element-clean,
--     so the party never feeds an absorb;
--   * medic doctrine healPercent 55 (the n128 boss split), cadence 12;
--   * the standard 3-attempt retry ladder, 37-frame phase spread, off a
--     pre-trigger savestate blob (clearGateSoldier's idiom), so a wipe
--     reloads and replays a different fight.
-- Instrumented like probe_cranes_wedge: battle open/close/periodic dumps
-- (party hp, per-Crane hp/shields, $3330 allowed-status words, so the
-- Slow question is answered by data), and a wipe detector on the battle
-- module's own HP words ($3BF4; the persistent table is stale, HANDOFF).
-- Terminates on map 219 (the flashback, meaning the ride continued past
-- the Cranes) or after 3 losses.  Not a suite test; no fixture output.
local H = dofile("tools/tests/lib/ot6.lua")
-- The ride ladder's spread and its collision check (issue #83): each
-- attempt is held until the game-time frame counter the battle seed is
-- made of reaches its own phase, and L.report() fails if two attempts drew
-- one seed, which would make this probe one Cranes fight played twice.
local L = H.newSeedLadder("cranes water")

local ZMENUSTATE, ZCURSOR = 0x26, 0x4b
local ST_MAIN, ST_CHAR, ST_SKILLS, ST_LIST, ST_DETAIL = 0x05, 0x06, 0x0a, 0x1e, 0x4d
local GENJULIST = 0x9d89
local BISMARK, SHIVA, CARBUNKL = 7, 2, 19

local function map() return H.mapId() & 0x1ff end
local function st() return H.readByte(ZMENUSTATE) end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function battleDump(tag)
  local mons = {}
  for m = 0, 5 do
    local id = H.readWord(0x57C0 + m * 2)
    if id ~= 0 and id ~= 0xFFFF then
      mons[#mons + 1] = string.format("%d:%04X hp=%d sh=%d st34=%04X",
        m, id, H.readWord(0x3BFC + m * 2), H.readByte(0x3E40 + m * 2),
        H.readWord(0x3330 + (4 + m) * 2))
    end
  end
  local hp = {}
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      hp[#hp + 1] = string.format("%d/%d", H.readWord(0x3BF4 + e * 2),
        H.readWord(0x3C1C + e * 2))
    end
  end
  H.log(string.format("[%s] f%d party %s | %s | $3f2e=%04X $1dd1=%02X",
    tag, H.frame, table.concat(hp, " "), table.concat(mons, " | "),
    H.readWord(0x3f2e), H.readByte(0x1dd1)))
end

-- drive the field menu to equip esper `idx` on char-select position `pos`
local function equipEsper(pos, idx, what)
  local seek_ph = 0
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return st() == ST_MAIN and H.readByte(ZCURSOR) == 1
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": cursor on Skills"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      what .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_CHAR and H.readByte(ZCURSOR) == pos
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": character cursor"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_SKILLS end, 300,
      what .. ": skills submenu", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_SKILLS and H.readByte(ZCURSOR) == 0
    end, 600, { H.pressButtons({ "up" }, 2), H.waitFrames(6) },
      what .. ": cursor to Espers"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_LIST end, 300,
      what .. ": esper list", 5),
    H.waitFrames(10),
    -- two-column grid seek (menu_esperdetail's idiom)
    H.driveUntil(function()
      return st() == ST_LIST
         and H.readByte(GENJULIST + H.readByte(ZCURSOR)) == idx
    end, 3000, {
      H.call(function()
        seek_ph = (seek_ph + 1) % 8
        if seek_ph >= 4 then H.setPad({}); return end
        local target
        for r = 0, 26 do
          if H.readByte(GENJULIST + r) == idx then target = r; break end
        end
        if not target then H.setPad({}); return end
        local row = H.readByte(ZCURSOR)
        local d = target - row
        if d % 2 ~= 0 then
          if row % 2 == 0 then
            H.setPad(row >= 26 and { up = true } or { right = true })
          else
            H.setPad({ left = true })
          end
        else
          H.setPad(d > 0 and { down = true } or { up = true })
        end
      end),
      H.waitFrames(1),
    }, what .. ": list cursor on the stone"),
    H.waitFrames(20),
    H.driveUntil(function() return st() == ST_DETAIL end, 600,
      { H.pressButtons({ "a" }, 3), H.waitFrames(12) }, what .. ": detail"),
    H.waitFrames(20),
    H.pressButtons({ "a" }, 3),          -- MenuState_4d @5902: equip esper
    H.waitUntil(function() return st() == ST_LIST end, 300,
      what .. ": equipped, back on the list", 5),
    H.driveUntil(function() return H.hasControl() end, 1200,
      { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, what .. ": back out"),
    H.waitFrames(20),
  })
end

-- drive the real Equip menu to put a specific weapon in char-select `pos`'s
-- main hand.  States (equip.asm): $36 options (cursor 0 = Equip) -> $55 slot
-- select (default slot 0 = R-Hand) -> $57 item select, whose list rows at
-- $7e9d8a are bag indexes into $1869 (MenuState_57 @992d reads that), so
-- the seek compares the id under the cursor rather than a guessed row.
-- Reason (measured 2026-08-10): H.equipOptimum armed LOCKE and EDGAR with
-- Thunder Blades ($0F, slash class, lightning element), and the Left Crane
-- absorbs lightning: every Fight healed it (a +160/+198 pair heals it to
-- full, +943 boosted) and charged its Giga Volt counter, so the party was
-- feeding the attack that wiped it one swing at a time.  The bag carries
-- daggers (Dirk/MithrilKnife/Guardian), and daggers are OT6_PIERCE, the
-- Cranes' class weakness: element-clean and shield-chipping.
local ST_EQOPT, ST_EQSLOT, ST_EQITEM = 0x36, 0x55, 0x57
local function equipWeapon(pos, itemId, what)
  return H.seqStep({
    H.driveUntil(function() return st() == ST_MAIN end, 1200,
      { H.pressButtons({ "x" }, 4), H.waitFrames(30) }, what .. ": main menu"),
    H.waitFrames(20),
    H.driveUntil(function()
      return st() == ST_MAIN and H.readByte(ZCURSOR) == 2
    end, 900, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": cursor on Equip"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_CHAR end, 300,
      what .. ": character select", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_CHAR and H.readByte(ZCURSOR) == pos
    end, 600, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": character cursor"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_EQOPT end, 300,
      what .. ": equip options", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_EQOPT and H.readByte(ZCURSOR) == 0
    end, 600, { H.pressButtons({ "left" }, 2), H.waitFrames(10) },
      what .. ": cursor on Equip option"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_EQSLOT end, 300,
      what .. ": slot select (R-Hand)", 5),
    H.waitFrames(10),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_EQITEM end, 300,
      what .. ": item list", 5),
    H.waitFrames(10),
    H.driveUntil(function()
      return st() == ST_EQITEM
         and H.readByte(0x1869 + H.readByte(0x9d8a + H.readByte(ZCURSOR)))
             == itemId
    end, 1800, { H.pressButtons({ "down" }, 2), H.waitFrames(10) },
      what .. ": list cursor on the weapon"),
    H.pressButtons({ "a" }, 2),
    H.waitUntil(function() return st() == ST_EQSLOT end, 300,
      what .. ": equipped, back on slots", 5),
    H.driveUntil(function() return H.hasControl() end, 1200,
      { H.pressButtons({ "b" }, 3), H.waitFrames(20) }, what .. ": back out"),
    H.waitFrames(20),
  })
end

local summonChars = {}                   -- actor id -> mp, filled after equip
local blob, won, attempts = nil, false, 0

local function attempt(n)
  local F, loadReq
  local wiped, wipedStreak = false, 0
  return H.cond(function() return won end, {}, {
    H.logStep(function()
      return string.format("cranes-water attempt %d at f%d", n, H.frame)
    end),
    (n > 1) and H.seqStep({
      H.call(function() loadReq = H.requestLoadState(blob) end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "pre-attempt reload") end),
    }) or H.waitFrames(1),
    H.waitFrames(90),                    -- settle after the reload
    H.navTo(54, 40, { playBattles = "flee", maxFrames = 25000 }),
    (function() local ph = 0
      return H.driveUntil(function() return map() == 6 end, 9000, {
        H.call(function()
          ph = (ph + 1) % 8
          if H.battleLoadStarted() then H.setPad({ l = true, r = true }); return end
          if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
          H.setPad({ left = true })
        end),
      }, "held LEFT onto the reunion trigger -> the Blackjack deck")
    end)(),
    H.release(),
    -- Here rather than up by the reload: the navTo above flees random
    -- encounters, and the seed that decides this attempt is the Cranes'
    -- (#83).  The spread is what the first battle after it draws.
    L.spread(n),                         -- spread the battle RNG phase (#83)
    (function()
      -- attempt-1 results (2026-08-10, this file's first run): the bag is
      -- 15 Tonics / 0 Potions, so an every-actor 55% medic line heal-locks
      -- the party into a wipe at battle f+6000.  SETZER (the 4th rider the
      -- reunion adds) is the sole medic now, the n128 split; and Tools is
      -- off because AutoCrossbow's splash feeds both retal counters (the
      -- cross-heal: +329 on the Left Crane per fed threshold).  Everything
      -- left is single-target at the default slot, the Left Crane, which
      -- is the vanilla playbook's kill order.
      -- focus pins the Left Crane, the vanilla kill order.  The mask is
      -- measured by the delta logger this file carries: CONFIRM mons=01
      -- fights land -60..-90 on slot 0 ($010D), so mask 01 = Left, the
      -- cursor's own default (an earlier mask=02 reading here was a
      -- misattribution and cost three attempts).  Once Left dies the
      -- entry's liveness check drops out and the default confirm takes the
      -- Right.  bank=2 helps: a 2-BP Pummel lands -796 on the shielded Left.
      F = H.newFightDriver("cranes water", { tactical = true, boost = true,
        bank = 2, items = true, healer = 9, healPercent = 45, tools = false,
        cadence = 12, summon = summonChars, traceTgt = true,
        focus = { { slot = 0, mask = 0x01 } } })
      local ph, battN, wasBatt = 0, 0, false
      local lastSt = -1                  -- MSTATE transition trace (temp)
      return H.driveUntil(function()
        if map() == 219 then
          won = true
          H.log(string.format("[verdict] attempt %d: STORY CONTINUES -- "
            .. "map 219 at f%d", n, H.frame))
          return true
        end
        if wiped then
          H.log(string.format("[verdict] attempt %d: WIPED at f%d", n, H.frame))
          return true
        end
        return false
      end, 90000, {
        H.call(function()
          ph = (ph + 1) % 8
          battN = H.battleLoadStarted() and battN + 1 or 0
          if battN == 3 and not wasBatt then
            wasBatt = true; lastSt = {}; battleDump("battle OPEN")
          end
          if wasBatt and battN == 0 then
            wasBatt = false; battleDump("battle CLOSED")
            -- The close-edge verdict (from probe_cranes_wedge): a wipe
            -- closes the battle with the Cranes alive and hands the ride to
            -- GameOver.  Do not read the monster table at the edge itself:
            -- teardown reads $FFFF everywhere (HANDOFF trap 1), and this
            -- file's first win was discarded as a "wipe" because of that
            -- read.  The delta logger's last in-battle values are the
            -- checks to use: any Crane still above zero on its final
            -- in-battle sample means the party lost.
            if type(lastSt) == "table" then
              for m = 0, 1 do
                local hp = lastSt[m * 2 + 1]
                if hp and hp > 0 then wiped = true end
              end
            end
          end
          if battN >= 3 then
            -- per-hit attribution: log every Crane hp/shield DELTA with its
            -- frame.  The 600-frame sampled dumps cannot attribute damage
            -- (a -525 Pummel and a +294 absorb heal inside one window net
            -- to noise); the deltas, beside the driver's CONFIRM lines
            -- (opts.traceTgt), identify which mask bit is which monster and
            -- what each action did.
            for m = 0, 1 do
              local hp = H.readWord(0x3BFC + m * 2)
              local sh = H.readByte(0x3E40 + m * 2)
              if lastSt == -1 then lastSt = {} end
              local k = m * 2 + 1
              if lastSt[k] ~= hp or lastSt[k + 1] ~= sh then
                if lastSt[k] then
                  H.log(string.format("[delta] f%d b+%d slot%d hp %d -> %d "
                    .. "(%+d) sh %d -> %d", H.frame, battN, m,
                    lastSt[k], hp, hp - lastSt[k], lastSt[k + 1], sh))
                end
                lastSt[k], lastSt[k + 1] = hp, sh
              end
            end
            if battN % 600 == 0 then battleDump("battle") end
            -- the wipe detector: the battle module's own HP words, all
            -- living slots at zero for 60 straight frames (init reads 0)
            if battN > 120 then
              local alive, total = 0, 0
              for e = 0, 3 do
                if H.readWord(0x3C1C + e * 2) > 0 then
                  total = total + 1
                  if H.readWord(0x3BF4 + e * 2) > 0 then alive = alive + 1 end
                end
              end
              if total > 0 and alive == 0 then
                wipedStreak = wipedStreak + 1
                if wipedStreak >= 60 then wiped = true end
              else
                wipedStreak = 0
              end
            end
            F.frame()
            return
          end
          if battN > 0 then F.idle(); H.setPad({}); return end
          F.idle()
          if map() == 219 then
            if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {})
            else H.setPad({}) end
            return
          end
          H.setPad(ph < 4 and { "a" } or {})
        end),
      }, "the reunion/Cranes ride, vanilla playbook")
    end)(),
    H.call(function() attempts = n end),
  })
end

H.run({ maxFrames = 320000 }, {
  H.loadState("build/states/n128_won.mss.lua"),
  H.waitFrames(150),
  H.call(function()
    H.assertEq(map(), 240, "booted on boundary E (n128_won)")
    H.assertEq(H.readByte(0x1A69) & 0x84, 0x84,
      "BISMARK (bit 7) and SHIVA (bit 2) owned")
  end),

  -- Char-select order at this boundary (measured): pos 0 = EDGAR, pos 1 =
  -- SABIN, pos 2 = LOCKE.  SETZER joins in the reunion scene after the last
  -- menu access, so only three stones can ride in.  CARBUNKL is the
  -- defensive key: its divine reflects the party, and the Cranes' normal
  -- rotation (Bolt/Bolt2, Fire/Fire2) is all reflectable spells, so only
  -- Magnitude8 and the physical counters come through.
  equipEsper(0, BISMARK, "equip BISMARK"),
  equipEsper(1, SHIVA, "equip SHIVA"),
  equipEsper(2, CARBUNKL, "equip CARBUNKL"),
  -- remove the lightning weapons: daggers (pierce, the Cranes' class
  -- weakness) in both swingers' main hands, replacing the Thunder Blades
  -- that healed and charged the Left Crane on every Fight (see
  -- equipWeapon's header)
  equipWeapon(0, 0x01, "EDGAR MithrilKnife"),
  equipWeapon(2, 0x02, "LOCKE Guardian"),
  H.call(function()
    for _, spec in ipairs({ { 4, "EDGAR" }, { 1, "LOCKE" } }) do
      for c = 0, 13 do
        local base = 0x1600 + 37 * c
        if (H.readByte(base) & 0x3f) == spec[1]
           and (H.readByte(0x1850 + c) & 0x07) ~= 0 then
          H.log(string.format("[weapon] %s main hand = %02X",
            spec[2], H.readByte(base + 31)))
        end
      end
    end
  end),
  -- Back row for all three riders (M.setRows drives the real Order screen).
  -- The measured cause of every wipe is the Cranes' physical specials and
  -- counters (~300 a hit against 312-457 pools); back row halves physical
  -- damage taken and costs this party little, because Blitz, summons and
  -- the medic Items are all row-exempt ($B3 bit $20, battle_main.asm:3131),
  -- so only the -66 Fights halve.  SETZER joins mid-scene and keeps his row.
  H.setRows({ [1] = true, [4] = true, [5] = true },
    { tag = "cranes back row" }),
  H.call(function()
    -- read back who wears what; key the summon table off the scan
    -- rather than assuming the char-select order
    local pid = H.readByte(0x1A6D)
    for c = 0, 13 do
      local b = H.readByte(0x1850 + c)
      if b ~= 0 and (b & 0x07) == pid then
        local base = 0x1600 + 37 * c
        local actor, esper = H.readByte(base) & 0x3f, H.readByte(base + 30)
        H.log(string.format("[equipped] c%d actor=%d esper=%02X mp=%d",
          c, actor, esper, H.readWord(base + 13)))
        if esper == BISMARK then summonChars[actor] = { mp = 50 } end
        if esper == SHIVA then summonChars[actor] = { mp = 27 } end
        if esper == CARBUNKL then summonChars[actor] = { mp = 36 } end
      end
    end
    local n = 0
    for _ in pairs(summonChars) do n = n + 1 end
    H.assertEq(n, 3, "all three stones landed on riders (the equip drive worked)")
    -- the bag the medic line will draw from
    local counts = { [0xE8] = 0, [0xE9] = 0, [0xF0] = 0 }
    for i = 0, 255 do
      local id = H.readByte(0x1869 + i)
      if counts[id] then counts[id] = counts[id] + H.readByte(0x1969 + i) end
    end
    H.log(string.format("[bag] Tonic=%d Potion=%d FenixDown=%d",
      counts[0xE8], counts[0xE9], counts[0xF0]))
  end),

  -- the retry blob: field control, stones equipped, pre-trigger
  -- (clearGateSoldier's idiom)
  (function()
    local req
    return H.seqStep({
      H.call(function() req = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(req, "retry blob")
        blob = req.blob
      end),
    })
  end)(),

  L.watch(),
  attempt(1), attempt(2), attempt(3),

  H.call(function()
    H.log(string.format("[final] won=%s after %d attempt(s)",
      tostring(won), attempts))
    H.screenshot("cranes_water_end")
  end),
  -- Before the verdict, not after: this probe's answer on whether the
  -- playbook turns the encounter is only worth something if the attempts it
  -- counted were different fights (#83).
  L.report(),
  H.call(function()
    H.assertEq(won, true,
      "the Cranes fall to the vanilla playbook within 3 attempts "
      .. "(Sea Song + Diamond Dust + the tactical kit)")
  end),
})
