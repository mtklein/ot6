-- probe_leo.lua -- one-shot survey instrument for the massacre's Leo fight.
-- NOT a suite member.
--
-- Boots the nearest checkpoint before the massacre (ultros-won-v1, map 375
-- (8,44)) and records what the fight's surface is: the reachability of the
-- massacre trigger 375 (15,17) from the save point (live, via BFS), and
-- Leo's kit/mechanics (derived from ROM/event data, logged below).
--
-- 375 (15,17) is NOT a short walk from (8,44).  It sits in map-375
-- compartment 2, a pocket reachable only by warping in at 375 (16,9) from
-- map 372 -- a full Esper-Mountain-exit traversal (371->373->372) from the
-- save point, whose only walkable exit is the west door (2,45)->371.  This
-- probe does not drive that traversal; it BFS-confirms the wall and
-- records the survey from data.
--
-- Run:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/ultros-won-v1 \
--     tools/tests/run.sh tools/tests/probe_leo.lua
--
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local LEO_REC = 14                              -- CHAR::WEDGE party record index
local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function frec(off) return 0x1600 + 37 * LEO_REC + off end

H.run({ maxFrames = 300000, allowGameOver = true }, {
  -- ---- cold Continue to the map-375 save tile ----------------------------
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  (function() local cnt = 0
    return H.waitUntil(function()
      local ok = map() == 375 and H.tileAligned() and bright() >= 15
             and not H.dialogWaiting() and not H.battleLoadStarted()
      cnt = ok and cnt + 1 or 0
      return cnt >= 10
    end, 4000, "cold Continue to the map-375 save tile (ultros-won-v1)", 10)
  end)(),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("[probe_leo] boot f%d map=%d (%d,%d) $0095=%d $0099=%d",
      H.frame, map(), H.fieldX(), H.fieldY(), sw(0x0095), sw(0x0099)))
    H.assertEntryContract("ultros-won-v1")
  end),

  -- ---- the crux: is the massacre trigger 375 (15,17) walkable-reachable? --
  H.call(function()
    local p = H.bfsPath(15, 17)
    H.log(string.format("[probe_leo] Q-geography: bfs (8,44)->(15,17) on 375: "
      .. "%s", p and (#p .. " steps") or "NO PATH (a far compartment)"))
    H.log("[probe_leo]   -> (15,17) is map-375 comp 2 (probe_massacre_map): "
      .. "reached only via 375 (16,9) from map 372.  The massacre approach is "
      .. "the Esper-Mountain-exit traversal 371->373->372, the route "
      .. "generator's job; this probe does not drive it.")
  end),

  -- ---- record Leo's kit from the char_prop record the fight will load -----
  -- (the record is dressed only at the massacre, so at ultros-won-v1 slot 14
  -- holds no Leo yet; the kit is read from ROM/char_prop.asm and logged for
  -- the survey, with the live-read offsets named.)
  H.call(function()
    H.log("[probe_leo] Q2 Leo kit (char_prop.asm:332, onto CHAR::WEDGE=14 at "
      .. "the massacre): FIGHT/SHOCK/NONE/ITEM; weapon Crystal (item $14, "
      .. "slash, element $00); level_mod VERY_HIGH (save-relative).")
    H.log(string.format("[probe_leo]   live-arm offsets: level frec+8=$%04X "
      .. "HP frec+9 MP frec+13 weapon frec+$1F",
      frec(8) & 0xffff))
    H.log("[probe_leo] Q3 boost/HUD: gauge $3E38+8+s*2, class $3E9C+8+s*2, "
      .. "party boost $3E9C+s*2 -- all battle-SLOT state, so they seed/bank "
      .. "for a WEDGE-slot solo party at slot 0 like any other.")
    H.log("[probe_leo] Q10 LOSS = GAME OVER: battle-124 tail calls _ca5ea9 "
      .. "(if_b_switch $40 return; call GameOver), event_main.asm:76471/14171.")
    H.log("[probe_leo] $173 shields: old = formula floor 2 (2+level/8 at L1); "
      .. "new = authored Ot6ShieldTbl 4, OT6_SLASH; NO element add (kit is "
      .. "non-elemental).  See battle_leo.lua for the ROM assertions.")
  end),
  H.logStep(function()
    return string.format("[probe_leo] survey recorded at f%d -- the live "
      .. "battle-124 arm attaches when the route generator lands its entry "
      .. "savestate", H.frame)
  end),
})
