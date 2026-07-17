-- probe_tekmissile.lua -- M3 evidence: THE ABILITY'S CLASS BEATS THE
-- WEAPON'S. Terra holds a slashing sword, casts TekMissile (skill
-- table: piercing), and the pierce-weak guard chips anyway -- the $02
-- on the class byte can only have come from the skill loader, because
-- the only other classed action in her repertoire here would be a
-- Fight, and she never Fights.
--
--   tools/tests/run.sh tools/tests/probe_tekmissile.lua
--
-- Runs in the guard fight (battle_doorstep), which opens with NO battle
-- dialog: its menus stage clean (battle_break asserts the rendered
-- magitek list). (Dialog-opening fights used to garble every menu; that
-- is fixed and gated by battle_dlgmenu.) Guards are authored pierce-weak, so no
-- weakness pokes are needed -- only their element rows are zeroed so
-- stray beams can't chip, and HP is pinned so nothing dies.
--
-- Menu drive: non-terra menus are spent on their row-1 beam (A-A-A,
-- classless, chips nothing); terra's walks down 7 rows to TekMissile
-- and fires at the default target (a guard). every window-opening A is
-- followed by a long settle -- input during any window-open animation
-- wedges the staged rows (see battle_break's warning and the whelk
-- probes' hard lessons).
--
-- Also screenshots the reveal moment: "Weak against piercing" in a
-- fight whose message window renders cleanly.

local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/build/states/battle_doorstep.mss.lua"

local function sram(addr) return emu.read(addr, emu.memType.snesMemory) end
local function rev1() return H.readByte(0x3E95) end   -- guard revealed elems
local function crev() return H.readByte(0x3EA9), H.readByte(0x3EAB) end

local terra
local classWrites = {}

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.call(function()
    -- fresh codex: the seed re-inits and nothing is pre-revealed
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "battle load from doorstep"),
  H.waitUntil(function() return H.battleActive() end, 900,
    "battle active", 30),
  H.waitFrames(240),

  -- lab setup
  H.call(function()
    local w1, w2 = H.readByte(0x3EA8), H.readByte(0x3EAA)
    H.assertEq(w1, 0x02, "guard 1 authored piercing-weak")
    H.assertEq(w2, 0x02, "guard 2 authored piercing-weak")
    H.writeByte(0x3BEC, 0)                 -- no element chips possible
    H.writeByte(0x3BEE, 0)
    H.writeWord(0x3C00, 5000); H.writeWord(0x3C02, 5000)
    for slot = 0, 3 do
      if H.readByte(0x3ED8 + slot * 2) == 0 then terra = slot end
    end
    H.assertEq(terra ~= nil, true, "terra found in the party")
    H.writeByte(0x3CA8 + terra * 2, 0x0A)  -- MithrilBlade: SLASHING
    H.log(string.format("terra slot %d armed with a slashing sword", terra))
    emu.addMemoryCallback(function(addr, value)
      classWrites[value] = (classWrites[value] or 0) + 1
    end, emu.callbackType.write, 0x7E57B8, 0x7E57B8)
  end),

  -- Terra's MagiTek list is a 2-column grid (Fire|Bolt / Ice|Bio /
  -- Heal|Confuser / X-fer|TekMissile) -- TekMissile is bottom-right.
  -- Rather than trust one fixed path through it, sweep the grid: each
  -- lap picks the next (down, right) offset, opens MagiTek, walks
  -- there, and fires. One offset IS TekMissile; when it fires, the
  -- skill loader stores $02 and we're done. Non-terra holders (their
  -- 4-beam list has no TekMissile) just waste a beam. battle_preview's
  -- 6-on/26-off edge cadence; goal-driven like its converging walk.
  -- Success = $02 loaded: with a slashing sword in hand and Terra
  -- never Fighting, only Ot6SkillClass (TekMissile=piercing) stores it.
  H.driveUntil(function() return (classWrites[0x02] or 0) >= 1 end, 26000,
    { H.call(function()
        H.writeWord(0x3C00, 5000); H.writeWord(0x3C02, 5000)
        local menu = H.readByte(0x7bca)
        -- wait-mode ATB FREEZES while any menu is open, so a non-terra
        -- menu left idle stalls the whole fight -- edge-tap A to fire
        -- their beam and hand time back (battle_preview's trick). reset
        -- the grid plan so terra's next turn starts a clean lap.
        if menu ~= 0 and H.readByte(0x62CA) ~= terra then
          H.vars.plan = nil
          H.vars.an = ((H.vars.an or 0) + 1) % 32
          H.setPad(H.vars.an < 6 and { "a" } or {})
          return
        end
        if menu == 0 then H.setPad({}); return end
        -- per-lap plan, rebuilt when a lap's frame budget elapses
        local p = H.vars.plan
        if p == nil or H.vars.pf > #p then
          local combos = { {0,0}, {1,0}, {2,0}, {3,0},
                           {0,1}, {1,1}, {2,1}, {3,1} }
          local c = combos[(H.vars.combo or 0) % #combos + 1]
          H.vars.combo = (H.vars.combo or 0) + 1
          -- build an edge-tapped frame plan: A (open list), c[1] downs,
          -- c[2] rights, A (confirm), then a settle. each entry is a
          -- button set held this frame ({} = released).
          p = {}
          local function tap(btn, on, off)
            for _ = 1, on do p[#p+1] = { btn } end
            for _ = 1, off do p[#p+1] = {} end
          end
          -- converge to a known state first: B backs out of any list /
          -- target-select left over from the previous lap, down to the
          -- top command menu (battle_preview's reset trick)
          tap("b", 6, 16); tap("b", 6, 16); tap("b", 6, 16)
          tap("a", 6, 4)                       -- MagiTek -> list
          p[#p+1] = "SHOT"                      -- capture the open list once
          for _ = 1, 26 do p[#p+1] = {} end
          for _ = 1, c[1] do tap("down", 6, 16) end
          for _ = 1, c[2] do tap("right", 6, 16) end
          tap("a", 6, 20)                      -- pick the cell
          tap("a", 6, 60)                      -- confirm the default target
          for _ = 1, 60 do p[#p+1] = {} end    -- let it resolve
          H.vars.plan, H.vars.pf = p, 1
        end
        local f = p[H.vars.pf]
        H.vars.pf = H.vars.pf + 1
        if f == "SHOT" then
          if not H.vars.tshot then
            H.vars.tshot = true; H.screenshot("tekmissile_openlist")
          end
          H.setPad({})
        else
          H.setPad(f)
        end
      end) },
    "tekmissile loads piercing on the class byte"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(20),
  H.call(function() H.screenshot("tekmissile_pierce_msg") end),
  H.waitFrames(45),
  H.call(function() H.screenshot("tekmissile_pierce_msg2") end),

  -- the drive stopped at the LOAD ($02 on the class byte); the missile
  -- lands frames later. UNCONDITIONAL: TekMissile carries flags3 $20
  -- ("can't dodge" -- it cannot miss) and its default target is a
  -- pierce-weak guard, so the chip and reveal MUST arrive. this assert
  -- used to be gated on the reveal having happened, which let the
  -- whole-byte $f2 gate ship a ROM where flagged skills never chipped.
  H.waitUntil(function()
    local r1, r2 = crev()
    return (r1 | r2) & 0x02 == 0x02
  end, 900, "TekMissile's chip reveals piercing on a guard", 10),

  H.call(function()
    local r1, r2 = crev()
    local s1, s2 = H.readByte(0x3E44), H.readByte(0x3E46)
    H.log(string.format("crev=%02x,%02x shields=%d,%d erev=%02x",
      r1, r2, s1, s2, rev1()))
    H.assertEq((classWrites[0x02] or 0) >= 1, true,
      "a PIERCING load hit the class byte -- with a slashing sword in " ..
      "hand, only the skill loader (TekMissile) can have stored it")
    H.assertEq(classWrites[0x01] or 0, 0,
      "and the sword's slash never loaded: terra never swung it")
    H.assertEq(s1 < 2 or s2 < 2, true,
      "the revealing TekMissile hit also chipped a shield")
    local species = H.readWord(0x57C4)
    H.assertEq(sram(0x316190 + species) & 0x02, 0x02,
      "class codex learned piercing from the ability chip")
    local parts = {}
    for v, n in pairs(classWrites) do
      parts[#parts + 1] = string.format("%02x:%d", v, n)
    end
    table.sort(parts)
    H.log("class byte writes: " .. table.concat(parts, " "))
    H.screenshot("tekmissile_final")
  end),

  -- CLEAN MESSAGE SHOT: the guard fight's windows render cleanly (no
  -- opening dialog), so switch to a guaranteed pierce chip and catch
  -- "Weak against piercing" on screen. Berserk the party with Dirks
  -- (battle_class's driver): a Dirk Fight is piercing, guards are
  -- pierce-weak, and the reveal prints the message via $3401 = $46.
  H.call(function()
    H.writeWord(0x3C00, 5000); H.writeWord(0x3C02, 5000)
    for slot = 0, 3 do
      H.writeByte(0x3CA8 + slot * 2, 0x00)      -- everyone holds a Dirk
      H.writeByte(0x202E + slot * 12, 0x00)     -- Fight-only command list
      H.writeByte(0x2031 + slot * 12, 0xFF)
      H.writeByte(0x2034 + slot * 12, 0xFF)
      H.writeByte(0x2037 + slot * 12, 0xFF)
      local st1 = 0x3EE4 + slot * 2
      H.writeByte(st1, H.readByte(st1) & 0xF7) -- clear magitek: fight, not beam
      local st2 = 0x3EE5 + slot * 2
      H.writeByte(st2, H.readByte(st2) | 0x10) -- berserk
    end
    H.log("berserk-dirk phase: hunting a clean pierce-reveal message")
  end),
  -- wait for the first pierce reveal (a guard's crev flips to $02);
  -- that same chip queues the "Weak against piercing" message, which
  -- then draws over the following ~1s. burst-screenshot across that
  -- window to land a frame with the text up.
  -- wait for the first pierce reveal (a guard's crev flips to $02);
  -- that same chip queues the "Weak against piercing" message ($3401
  -- = $46, transient within a frame -- unpollable from Lua), which the
  -- battle script then draws over the following ~1s. burst-screenshot
  -- across that window as best-effort eyeball evidence in a fight whose
  -- message window renders cleanly (unlike the whelk fight's
  -- pre-existing garbled-menu bug).
  H.driveUntil(function()
    return (H.readByte(0x3EA9) | H.readByte(0x3EAB)) & 0x02 == 0x02
  end, 12000, {
    H.call(function() H.writeWord(0x3C00, 5000); H.writeWord(0x3C02, 5000) end),
    H.waitFrames(2),
  }, "a guard's piercing class revealed"),
  H.repeatN(30, {
    H.call(function()
      H.writeWord(0x3C00, 5000); H.writeWord(0x3C02, 5000)
      H.screenshot("class_pierce_msg")
    end),
    H.waitFrames(3),
  }),
  H.call(function()
    H.log("guard pierce reveal confirmed; message-window shots captured")
  end),
})
