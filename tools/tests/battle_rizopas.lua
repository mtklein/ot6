-- @suite savestate=falls_jump slow
-- battle_rizopas.lua -- Rizopas under the boss contract (docs/design/bosses-wob.md block 9, wt/v051-tg-wob2): El
-- Nino is its telegraph, and a break cancels it.
--
-- Rizopas's script (ai_script.asm AIScript::_341): vanilla's two turns were (A) Battle, Special or Mega Volt and
-- Battle or Ice, then (B) El Nino or Battle, El Nino one in three and unannounced.  Now the one-in-three is rolled
-- on turn A (if_roll 85, 85 in 256: Ot6AICondRoll), a turn before anything is announced; armed (monster switch 0),
-- its next turn announces it -- "Waters swell!" (battle dialogue $9A) and a glow -- in place of turn B, and El Nino
-- (attack $6F, command $02) comes on the turn after.  Unarmed, turn B is its Battle.  Under the contract
-- (ot6_fuse.asm, Ot6FuseTbl's row $0155) a break while it is lit cancels it: the script waits nowhere, switches 0
-- and 1 are clear, and the rotation starts again at turn A, roll and all.
--
-- Boots falls_jump (gen_sabin_falls: SABIN and CYAN at the top of Baren Falls after the arrival scene), jumps
-- (battle 18, formation 79: the Piranha school, Rizopas surfacing in slot 5 once the battle timer passes 60), fights
-- the school through the menu (everyone Fights) until Rizopas surfaces, and plays his phase three times from a
-- snapshot taken there (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the
-- gauge, the row's classes for the breaking Fight, and HP held):
--   unbroken  the party Defends; the line shows on the turn after a roll under the chance; the lit-fuse mark stands
--             before his shield emblem; El Nino is dispatched on his next turn, a glow between; the mark goes.
--   broken    one member's aimed Fight is confirmed once the mark is up and breaks him: the cancel fires, the mark
--             goes with the hit, switches 0 and 1 read clear, no El Nino on his first turns back, and the line
--             returns only after another roll under the chance; El Nino follows.
--   outside   a break as he surfaces, before any line: nothing is cancelled and the cells stand, two Fights in the window wind
--             nothing, and the fuse then lights and fires as in the first case.
-- Every roll is read where it is made (Ot6AIRolled: the roll in A, the chance in $3A2E); the announce must follow a
-- roll under the chance and the arming exactly the rolls under it.  The school and the surfacing are vanilla's.
-- Mutants (tools/build/mutant_rom.py, on the branch's ROM; build/attempts/wt/v051-tg-wob2/mutants/): fuse_never
-- (Ot6FuseCancel+3=80) is red at "the break during the fuse cancels it"; rizopas_no_trigger (its row keeps every
-- bit: Ot6FuseTbl+125=FF on the merged table; +85 before) at "switches 0 and 1 are clear after the cancel"; roll_always (every roll arms:
-- Ot6AICondRoll+6=3860EA) at "a roll under the chance came between the cancel and the second line".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/falls_jump.mss.lua"

local RIZOPAS, SLOT = 0x155, 5
local function map() return H.mapId() & 0x1ff end
local function up() return H.readByte(0x3AA8 + SLOT * 2) & 1 == 1 and H.readWord(0x57C0 + SLOT * 2) == RIZOPAS end

-- every roll as it is made: { f, r, n, gen, armed } (only Rizopas rolls in this battle: the Piranhas' script has no
-- if_roll); armed = monster switch 0 read set before the next roll
local rolls, gen = {}, 0
local ENT = 8 + 2 * SLOT

-- The party's part while his roll is to be won: Defend, and after each roll he misses one member's Fight aimed at
-- him (the library holds his gauge at 63, so it only chips).  With the party only Defending every cycle of his two
-- turns took the same frames and the same draws, so the roll fell on the same few values: on wt/v052-tg-wob3's
-- replayed draw 15 turn-A rolls in a row missed and the case's 40,000 frames ran out ("rizopas: the announce shows
-- (dlg $9A) -- the trigger earned again: got false", build/attempts/wt/v052-tg-wob3/regen2/suites/
-- battle_rizopas-red.log).  A Fight's own draws move the phase, as a player's turns do.
local function armVaried(pred, max, W)
  local t0, plan, lastMiss = nil, {}, 0
  return H.lazy(function()
    t0, plan, lastMiss = H.frame, {}, H.frame
    return H.kitBattle(plan, { idle = "defend", care = false, maxFrames = max + 600,
      giveUp = function()
        local r = rolls[#rolls]
        if r ~= nil and r.gen == gen and r.r >= r.n and r.f > lastMiss then
          lastMiss = r.f
          for i = 0, 3 do
            local id = H.readByte(0x3ED8 + 2 * i)
            if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and (H.readByte(0x3EE4 + 2 * i) & 0xC2) == 0 then
              plan[#plan + 1] = { who = id, cmd = 0x00, boost = 0, slot = SLOT }
              break
            end
          end
        end
        return pred() or H.frame - t0 >= max
      end })
  end)
end

-- The cap: its run ended at f26,663 on the merged ROM (wt/v051-tg-wob1), so 55,000 is about 2x the longest.
H.run({ maxFrames = 55000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control at the falls' top"),
  H.call(function()
    H.assertEq(map(), 156, "falls_jump stands at the top of Baren Falls (map 156)")
    local ro = H.sym("Ot6AIRolled")
    emu.addMemoryCallback(function()
      rolls[#rolls + 1] = { f = H.frame, r = emu.getState()["cpu.a"] & 0xFF, n = H.readByte(0x3A2E), gen = gen,
        armed = false }
    end, emu.callbackType.exec, ro, ro)
    emu.addEventCallback(function()
      local r = rolls[#rolls]
      if r ~= nil and r.gen == gen and H.readByte(0x3DAC + ENT) & 0x01 ~= 0 then r.armed = true end
    end, emu.eventType.endFrame)
  end),
  -- the jump: onto the jump row and up, the dialogs (and "Jump?", whose first row is yes) answered with A
  H.navTo(13, 11, { maxFrames = 5000, playBattles = "tactical" }),
  (function()
    local ph = 0
    return H.driveUntil(function() return H.battleLoadStarted() end, 8000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        if not H.hasControl() then H.setPad({}); return end
        H.setPad({ "up" })
      end),
    }, "the jump -> battle 18")
  end)(),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 3000, "battle 18 is up", 2),
  H.call(function()
    H.assertEq(H.readWord(0x11E0) & 0x3FF, 79, "battle 18 is formation 79 (the school, Rizopas in slot 5)")
  end),
  -- the school, fought through the menu, until he surfaces
  H.kitBattle({}, { care = true, maxFrames = 20000, giveUp = function() return up() end }),
  H.waitUntil(function() return up() and H.battleActive() end, 3000, "Rizopas surfaces in slot 5", 2),
  H.call(function()
    H.log(string.format("[rizopas] f%d Rizopas surfaced: HP %d/%d, shields %d", H.frame, H.readWord(0x3BF4 + ENT),
      H.readWord(0x3C1C + ENT), H.readByte(0x3E38 + ENT)))
    rolls = {}
  end),
  H.fuseCases({
    tag = "rizopas", species = RIZOPAS, write = WRITE,
    line = 0x9A, move = { cmd = 0x02, atk = 0x6F }, turns = 1, glows = 1,
    arm = armVaried, aim = true,
    bossHp = 775,
    onOpen = function() gen = gen + 1 end,
    -- at once, before his first turn: the cases share the snapshot and the party's input, so the draw that armed
    -- the unbroken case's fuse on his first turn A arms this one's too, and only a break before it is outside
    partway = function(W) return true end,
    earned = function(C, W)
      local post = C.brk.post
      H.assertEq(post.mvar & 0x03, 0, "rizopas: switches 0 and 1 are clear after the cancel (turn A comes next)")
      local won = 0
      for _, r in ipairs(rolls) do
        if r.gen == gen and r.f > C.brk.f and r.f < C.lines[2].f and r.r < r.n then won = won + 1 end
      end
      H.assertEq(won >= 1, true, "rizopas: a roll under the chance came between the cancel and the second line")
    end,
    -- each announce follows a roll under the chance, on the turn before it
    fired = function(C, W, n)
      local l, last = C.lines[n], nil
      for _, r in ipairs(rolls) do if r.gen == gen and r.f < l.f then last = r end end
      H.assertEq(last ~= nil and last.r < last.n, true, string.format("rizopas: the announce followed a roll under the "
        .. "chance (%s)", last and string.format("%d against %d", last.r, last.n) or "no roll"))
    end,
  }),
  H.call(function()
    local t, under = {}, 0
    for i, r in ipairs(rolls) do
      t[#t + 1] = string.format("%d/%d%s", r.r, r.n, r.armed and "*" or "")
      if r.r < r.n then under = under + 1 end
      -- (a case's last roll is not judged: the next case's snapshot can come before its turn's switch is set)
      if rolls[i + 1] ~= nil and rolls[i + 1].gen == r.gen then
        H.assertEq(r.armed, r.r < r.n, string.format("rizopas: the roll at f%d (%d against a chance of %d in 256) %s "
          .. "the fuse", r.f, r.r, r.n, r.r < r.n and "arms" or "does not arm"))
      end
    end
    H.log(string.format("[rizopas] the rolls (roll/chance, * armed): %s -- %d under the chance of %d", table.concat(t,
      " "), under, #rolls))
    H.assertEq(#rolls >= 3, true, "rizopas: his turn A rolled in every case (three or more rolls seen)")
  end),
  H.logStep("[rizopas] PASS: the roll, the announce, the schedule, the cancel and the rotation earned again"),
})
