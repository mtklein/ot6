-- @suite savestate=wor_grave slow
-- battle_jackpot.lua -- SETZER's divine, Jackpot (#319, kits.md "Setzer" and
-- "Divines"): a full 3-BP boost buys a throw of two rolls, each the Fixed
-- Dice coming up a triple, 99 MP, no chip, and no once-a-battle limit.
--
-- Played, not staged: wor_grave is gen_wor_falcon's own frame on Daryl's
-- grave (the party armed and cared for, the gil's digit settled, before
-- the press), reached by play from the wor-tomb-v1 battery; SETZER rejoined
-- in the World of Ruin there (event switch $00CA), so Jackpot is learned.
-- Passes from that frame, each pressing the grave and playing SETZER
-- through the real menu (H.setzerBattle) against Dullahan (23,450 HP, ten
-- shields):
--   pass 1: Defend twice (the bank to 3), Jackpot at 3 BP; three Defends
--     (the bank back to 3), and Jackpot at 3 BP again in the same battle;
--   pass 2: Jackpot at 0, 1 and 2 BP: each refused at the list (three A
--     presses, the list stays up, nothing queued);
--   pass 3: Jackpot picked at 3 BP, taken back to 2 at target select (L):
--     it rolls nothing, charges no MP and no points, and no HP moves;
--   then a staged redraw (below: $be written, a declared expedient) and
--     a bounded search for the draws the passes above may not meet: a
--     roll that meets a table byte past 251 and draws again (held when met),
--     and a pass that finds no body (the throw's first roll felled
--     Dullahan, whom the throw before had worn down).  Every
--     candidate that throws is held to everything below; one whose party
--     falls before its first Jackpot executes (no Ot6SetzerExec for it)
--     throws nothing, and is counted and logged as such.
-- What it holds, per Jackpot (at Ot6SetzerExec's entry and SETZER's
-- Ot6ActionEnd; each pass at Ot6JackpotDice's entry and the dice effect's
-- return; each roll as the effect sets the dice animation):
--   * two passes (the full boost's fixed throw, M.JACKPOT_ROLLS); a pass
--     that finds a body rolls once, its face the first byte of the battle
--     RNG table below 252 after $be, mod 6, and $be stops on that byte; a
--     pass that finds none (the roll before felled the last body) rolls
--     nothing, queues no dice and draws no Rand ($be unmoved);
--   * each roll three dice of one face (b7 = face-1 in both nybbles, b6 =
--     face-1), the face 1-6, its damage face^3 x level x 2 times the face
--     (vanilla's Fixed Dice arithmetic, saturating at 65,535), and what it
--     landed: that, halved while the body's shields hold, doubled once
--     Broken, capped at 9,999 and at the HP the roll found;
--   * null-break: every roll's class is special | null-break ($88) and no
--     monster's shields move;
--   * 99 MP, no gil, and the bank less the three points.
-- A pass with no body left: Dullahan's 23,450 HP outlast one throw (two
-- rolls, 9,999 each at most), but not two -- the first throw leaves him
-- low, and when the second throw's first roll fells him its second pass
-- finds no body (this branch's mx7 run met it at searches 4, 8, 11 and 19:
-- build/attempts/wt/v027-kits/mx7/new__battle_jackpot.out).
-- The face odds are a distribution: measured by the labs in
-- build/attempts/wt/kit-setzer/ (jackpot-dist/, labs-r3/), not by these
-- draws; these hold each roll to the draw rule that makes them.
-- The run ends once the plan is spent; Dullahan's fight is not finished.
-- Old-ROM red (main's ROM on main's fixtures): build/attempts/wt/v027-kits/
-- mx1/; mutants: build/attempts/wt/v027-kits/final-matrix/ (<rom>__battle_jackpot.out);
-- the earlier controls in build/attempts/wt/kit-setzer/.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/wor_grave.mss.lua"

local JACKPOT = 0x5B
local DULLAHAN = 0x11C

-- Ot6Tick's shield restore (`sta OT6_SHIELD_CUR,x` once the broken timer
-- reaches 0), found by its bytes in the proc, and every Ot6ActionEnd: the
-- frames checkJackpot's shield excuse reads.  x is the entity's doubled
-- index, a monster slot's 8 + 2 * slot.
local TICK = { restores = {}, ends = {}, installed = false }
local function installTick()
  if TICK.installed then return end
  TICK.installed = true
  local cur = H.sym("OT6_SHIELD_CUR") & 0xFFFF
  TICK.max = H.sym("OT6_SHIELD_MAX") & 0xFFFF
  local base = H.sym("Ot6Tick")
  local at = nil
  for o = 0, 31 do
    local a = (base & 0x3FFFFF) + o
    if H.readRomByte(a) == 0x9D and H.readRomByte(a + 1) == (cur & 0xFF) and H.readRomByte(a + 2) == (cur >> 8) then
      at = base + o; break
    end
  end
  H.assertEq(at ~= nil, true, "Ot6Tick stores OT6_SHIELD_CUR,x (the restore on recovery)")
  emu.addMemoryCallback(function()
    local x = emu.getState()["cpu.x"] & 0xFFFF
    -- the max it restores to, read as it restores: read after the battle
    -- (a 4-6 Defend search candidate whose last roll felled Dullahan) the
    -- cleared slot reads $FF (v029 jackpot4: `got 10, want 255`)
    if x >= 8 then TICK.restores[#TICK.restores + 1] = { f = H.frame, slot = (x - 8) // 2,
      max = H.readByte(TICK.max + x) } end
  end, emu.callbackType.exec, at, at)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    TICK.ends[#TICK.ends + 1] = { f = H.frame, x = emu.getState()["cpu.x"] & 0xFFFF }
  end, emu.callbackType.exec, ae, ae)
  H.log(string.format("[jackpot] Ot6Tick's shield restore hooked at $%06X; shield max at $%04X", at, TICK.max))
end

local function checkJackpot(r, i)
  H.log(string.format("[jackpot] %d at %d BP, L%d: %d roll(s); MP %d -> %d, purse %d -> %d, bank %d -> %d", i,
    r.boost, r.level, #r.dice, r.mp0, r.mp1, r.gil0, r.gil1, r.bank0, r.bank1))
  H.assertEq(r.mp0 - r.mp1, 99, string.format("Jackpot %d: 99 MP, whatever the boost", i))
  H.assertEq(r.gil1, r.gil0, string.format("Jackpot %d: no gil", i))
  H.assertEq(r.boost, 3, string.format("Jackpot %d: at the full 3 BP a divine takes", i))
  H.assertEq(r.bank1, r.bank0 - 3, string.format("Jackpot %d: the bank less the three points", i))
  H.assertEq(r.targets ~= 0, true, string.format("Jackpot %d was aimed at the monsters", i))
  local alive = 0
  for b = 0, 5 do if r.mon1[b].present and r.mon1[b].alive then alive = alive + 1 end end
  -- the passes: the fixed throw's two; one that finds a body rolls once, by the
  -- draw rule (the first byte of the battle RNG table below 252 after $be,
  -- mod 6; $be stops there), and one that finds none -- the rolls before it
  -- felled the last body -- rolls nothing and draws nothing
  H.assertEq(#r.passes, H.JACKPOT_ROLLS, string.format("Jackpot %d: the throw's %d passes", i, H.JACKPOT_ROLLS))
  local rng = H.sym("RNGTbl") & 0x3FFFFF
  local aimed, empty, redraws = 0, 0, 0
  for k, q in ipairs(r.passes) do
    if q.mask == 0 then
      empty = empty + 1
      H.assertEq(alive, 0, string.format("Jackpot %d, pass %d found no body: the last one has fallen", i, k))
      H.assertEq(q.rolled, 0, string.format("Jackpot %d, pass %d found no body: no roll, no dice", i, k))
      H.assertEq(q.be1, q.be0, string.format("Jackpot %d, pass %d found no body: no Rand drawn ($be)", i, k))
      H.log(string.format("[jackpot]   pass %d: no body left -- no roll, $be stays %02X", k, q.be0))
    else
      aimed = aimed + 1
      H.assertEq(empty, 0, string.format("Jackpot %d, pass %d: no body-less pass before a roll", i, k))
      H.assertEq(q.rolled, 1, string.format("Jackpot %d, pass %d: one roll", i, k))
      local idx, v, n = q.be0, nil, 0
      repeat
        idx = (idx + 1) & 0xff
        v = H.readRomByte(rng + idx)
        n = n + 1
      until v < 252
      redraws = redraws + n - 1
      local d = r.dice[aimed]
      H.assertEq(d ~= nil and d.b6, v % 6, string.format("Jackpot %d, pass %d: the face is the first table byte "
        .. "below 252 after $be %02X (byte %d at %02X, %d draw(s)), mod 6", i, k, q.be0, v, idx, n))
      H.assertEq(q.be1, idx, string.format("Jackpot %d, pass %d: $be stops on the byte it used", i, k))
      if n > 1 then
        H.log(string.format("[jackpot]   pass %d: $be %02X drew %d past 251, redrawn %d time(s) onto %d at %02X: "
          .. "face %d", k, q.be0, H.readRomByte(rng + ((q.be0 + 1) & 0xff)), n - 1, v, idx, v % 6 + 1))
      end
    end
  end
  H.assertEq(#r.dice, aimed, string.format("Jackpot %d: one roll a pass that found a body", i))
  if alive > 0 then H.assertEq(empty, 0, string.format("Jackpot %d: a body stands, so every pass rolled", i)) end
  for k, d in ipairs(r.dice) do
    local f = d.b6 + 1
    H.assertEq(d.b7, (d.b6 << 4) | d.b6, string.format("Jackpot %d, roll %d: three dice of one face", i, k))
    H.assertEq(f >= 1 and f <= 6, true, string.format("Jackpot %d, roll %d: a face 1-6 (%d)", i, k, f))
    local dmg = math.min(65535, f * f * f * r.level * 2 * f)
    H.assertEq(d.dmg, dmg, string.format("Jackpot %d, roll %d: the triple's damage, face %d^4 x level %d x 2", i, k,
      f, r.level))
    H.assertEq(d.class, 0x88, string.format("Jackpot %d, roll %d: special | null-break", i, k))
    -- what it landed: the HP the roll found against the next roll's (or the end's)
    local post = r.dice[k + 1] and r.dice[k + 1].hp or (function()
      local t = {} for b = 0, 5 do t[b] = r.mon1[b].hp end return t end)()
    local hit, drop = nil, 0
    for b = 0, 5 do
      if d.hp[b] ~= post[b] then H.assertEq(hit, nil, "one body a roll"); hit, drop = b, d.hp[b] - post[b] end
    end
    H.assertEq(hit ~= nil, true, string.format("Jackpot %d, roll %d landed on a body", i, k))
    if k == 1 then
      H.assertEq((r.targets >> hit) & 1, 1, string.format("Jackpot %d: the first roll lands inside the aimed mask "
        .. "$%02X (slot %d)", i, r.targets, hit))
    end
    local o = r.mon0[hit]
    local want = dmg
    if o.brk == 0 and o.sh > 0 then want = (want * 8) >> 4 elseif o.brk ~= 0 and want < 32768 then want = want * 2 end
    want = math.min(want, 9999, d.hp[hit])
    H.log(string.format("[jackpot]   roll %d: face %d, dmg %d, slot %d HP %d -> %d (want -%d), shields %d, broken %d",
      k, f, d.dmg, hit, d.hp[hit], post[hit], want, o.sh, o.brk))
    H.assertEq(drop, want, string.format("Jackpot %d, roll %d: what it landed on slot %d", i, k, hit))
  end
  -- (after the rolls' class check, so a mutant that loses null-break fails
  -- there, on the class, before it fails here, on what the class did)
  -- A body whose break ran out inside the action is the one excuse: Ot6Tick
  -- (ot6_break.asm) puts its shields back to max on the status tick its
  -- timer reaches 0, whatever the roll did.  The excuse holds only where
  -- that store was SEEN for that slot between the exec and SETZER's
  -- Ot6ActionEnd (TICK, above); any other way a break ends or the shields
  -- move inside a Jackpot (a death path, the Jackpot itself) still fails.
  local endF = nil
  for _, e in ipairs(TICK.ends) do
    if e.f >= r.f and e.x == r.entity then endF = e.f; break end
  end
  H.assertEq(endF ~= nil, true, string.format("Jackpot %d: SETZER's Ot6ActionEnd seen after the exec", i))
  for b = 0, 5 do
    local restored = nil
    for _, t in ipairs(TICK.restores) do
      if t.slot == b and t.f >= r.f and t.f <= endF then restored = t end
    end
    if r.mon0[b].present and restored then
      H.assertEq(r.mon0[b].brk ~= 0 and r.mon1[b].brk == 0, true, string.format("Jackpot %d: slot %d's "
        .. "shields were restored by Ot6Tick at f%d, inside the action: Broken at the exec (%d ticks) and "
        .. "not after", i, b, restored.f, r.mon0[b].brk))
      H.assertEq(r.mon1[b].sh, restored.max, string.format("Jackpot %d: slot %d's break "
        .. "ran out inside the action (Ot6Tick at f%d), and its shields came back to max", i, b, restored.f))
      H.log(string.format("[jackpot]   slot %d: its break ran out at f%d inside the action (exec f%d, end "
        .. "f%d): shields %d -> %d by Ot6Tick's restore", b, restored.f, r.f, endF, r.mon0[b].sh,
        r.mon1[b].sh))
    elseif r.mon0[b].present then
      H.assertEq(r.mon1[b].sh, r.mon0[b].sh, string.format("Jackpot %d: slot %d's shields do not move", i, b))
    end
  end
  return { empty = empty, redraws = redraws }
end

-- A fixed pass (1-3) from the grave at the first battle key whose fight the
-- party lives through to the plan's end.  The grave moves with the route's
-- play, and a key whose Dullahan wipes the party before the plan is done
-- has nothing to hold: at 96e745f0's grave (SABIN a level lower than
-- main's) pass 1's own key, beE8-g01C7, wiped the four between its two
-- Jackpots ('party 06:0/1798 ... Death', the canary's game over at f9551:
-- build/attempts/wt/v036-driver/qual-96e745f0.log, and the same on main's
-- lib from that grave, lab/jp_old_branchgrave).  The lib's wipe predicate
-- held 90 frames (the search's, below) ends a try short of the canary's
-- 300; the next try reloads the grave and stands 4 frames longer on it
-- first (its $be steps $10 every four frames), up to 16 keys, each lost one
-- said.  build(wait) returns the try's step; wait nil is the grave's own
-- frame, as before.
-- A try is lost when no Jackpot has executed in it (Ot6SetzerExec with
-- Jackpot's row in $b6, the search's lost-candidate rule below), or when
-- every Jackpot that executed resolved (its record is in H.vars.setzer)
-- and the party stood KEYED_STOOD frames past the last one: Dullahan's
-- wipe, not the throw's.  At the branch's grave pass 1's first key threw
-- at f2361 and Dullahan wiped the four at f9342, during the three Defends
-- before the second throw (lab/jp3_branchgrave).  Any other wipe after a
-- throw fails the pass by name: the control that writes the party's HP to
-- 0 at Jackpot's exec wipes at f2451 (lab/jp3_mut_branchgrave).  The held
-- line says how many tries were lost.
local KEYED_STOOD = 600
local keyedExec = { hooked = false, f = nil }
local function keyed(n, build)
  local i, cur, wipedN, lost = 0, nil, 0, 0
  return {
    tick = function(self)
      if not keyedExec.hooked then
        keyedExec.hooked = true
        local a = H.sym("Ot6SetzerExec")
        emu.addMemoryCallback(function()
          if H.readByte(0xB6) == JACKPOT then
            keyedExec.f, keyedExec.last, keyedExec.n = keyedExec.f or H.frame, H.frame, (keyedExec.n or 0) + 1
          end
        end, emu.callbackType.exec, a, a)
      end
      if cur == nil then
        i = i + 1
        H.assertEq(i <= 16, true, string.format("pass %d: a battle key the party lives through, within 16 (%d "
          .. "lost to a wipe)", n, lost))
        cur, wipedN = build(i > 1 and 4 * (i - 1) or nil), 0
        keyedExec.f, keyedExec.last, keyedExec.n, keyedExec.wipeF = nil, nil, 0, nil
      end
      wipedN = H.battleLoadStarted() and H.partyWipedInBattle() and wipedN + 1 or 0
      if wipedN == 1 then keyedExec.wipeF = H.frame end
      if wipedN >= 90 then
        local why = "before any Jackpot executed"
        if keyedExec.f ~= nil then
          local resolved = #(H.vars.setzer or {})
          H.assertEq(resolved >= keyedExec.n and keyedExec.wipeF - keyedExec.last >= KEYED_STOOD, true,
            string.format("pass %d: try %d's party wiped (f%d) after a Jackpot executed (f%d, %d executed, %d "
              .. "resolved): not a lost key", n, i, keyedExec.wipeF, keyedExec.last, keyedExec.n, resolved))
          why = string.format("%d frames after its last Jackpot (f%d) resolved", keyedExec.wipeF - keyedExec.last,
            keyedExec.last)
        end
        lost = lost + 1
        H.log(string.format("[jackpot] pass %d: try %d (the grave's frame + %d) lost: the party wiped %s (the "
          .. "lib's wipe predicate, 90 frames, from f%d); the next key", n, i, 4 * (i - 1), why, keyedExec.wipeF))
        H.setPad({})
        cur = nil
        return "frame"
      end
      local r = cur:tick()
      if r ~= "frame" then
        H.log(string.format("[jackpot] pass %d held at try %d: %d tr%s lost to a wipe (Dullahan's, not a throw's)",
          n, i, lost, lost == 1 and "y" or "ies"))
      end
      return r
    end,
    reset = function(self) i, cur, wipedN, lost = 0, nil, 0, 0 end,
  }
end

local function pass(n, plan, wantN, o)
  return keyed(n, function(wait)
  -- a try plays the plan afresh (setzerBattle keeps its per-entry progress on the entries)
  for _, p in ipairs(plan) do p.aim, p.presses, p.lPresses, p.tookBack, p.refusedSeen = nil, nil, nil, nil, nil end
  o = o or {}
  local recs
  -- wait: frames stood on the grave before the press (the battle key: keyed,
  -- above); o.stand: frames the party stands in the battle before acting (a
  -- player slow to the menu; Dullahan's turns go on).  Both are inputs, and
  -- pick the draw a pass needs; passes 1-3 take no stand.
  local steps = {
    H.loadState(STATE),
    H.call(function()
      H.assertEq(H.mapId() & 0x1ff, 299, "wor_grave stands in the grave's room (map 299)")
      H.assertEq(H.readByte(0x1E99) & 0x04, 0x04, "SETZER has rejoined in the World of Ruin (switch $00CA)")
    end),
  }
  if wait then steps[#steps + 1] = H.waitFrames(wait) end
  steps[#steps + 1] = H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000,
    "the grave (100,14): face up, A")
  steps[#steps + 1] = H.release()
  if o.stand then steps[#steps + 1] = H.waitFrames(o.stand) end
  steps[#steps + 1] = H.setzerBattle(plan, { untilPlanDone = true, shot = "jackpot_table_" .. n })
  steps[#steps + 1] = H.call(function()
      local ids = {}
      for _, s in ipairs(H.formationSpecies()) do ids[#ids + 1] = s.species end
      H.assertEq(ids[1], DULLAHAN, "the grave's fight is Dullahan")
      recs = H.vars.setzer
      H.assertEq(#recs, wantN, string.format("pass %d: %d Jackpot(s) resolved", n, wantN))
      local faces = {}
      for k, r in ipairs(recs) do
        H.assertEq(r.row, JACKPOT, string.format("pass %d: Jackpot %d's row is Jackpot", n, k))
        checkJackpot(r, n * 10 + k)
        for _, d in ipairs(r.dice) do faces[#faces + 1] = d.b6 + 1 end
      end
      for k, p in ipairs(plan) do
        if p.refused then
          H.assertEq(p.refusedSeen == true, true, string.format("pass %d: entry %d (Jackpot at %d BP) was refused "
            .. "at the list", n, k, p.boost or 0))
        end
      end
      H.log(string.format("[jackpot] pass %d held: %d Jackpot(s), faces %s", n, #recs, table.concat(faces, ",")))
    end)
  return H.seqStep(steps)
  end)
end

-- ---- the search for the two draws ------------------------------------
-- A throw is a fixed function of its battle's state, and the state is
-- picked by inputs: frames stood on the grave before the press (the battle
-- key: from this grave $be steps $10 every four frames, so 16 waits are the
-- 16 keys), frames the party stands in the battle before acting (Dullahan's
-- turns go on, moving the draws), SETZER's Defends before the throw, and
-- whether the others Defend or Fight meanwhile.  Candidates, in order:
-- stand 0 then 640 (a stand under ~300 ends inside the load and changes
-- nothing, labs-r4; 330-520 mostly repeat stand 0), each over 2 then 3
-- Defends, each over the others Defending then Fighting, each over the 16
-- keys -- 128 -- and then the same over 4, 5 and 6 Defends: 320 at most.
-- v029's grave (wt/v029-shield-grants) threw no redraw in the first 128 at
-- entry shifts 0, 13 and 29 (jackpot2/), nor over the other 48 keys (the
-- wait one to three frames longer, jackpot3/): a pass redraws only when it
-- starts on one of the four positions before a byte past 251 ($37, $50,
-- $91, $B5), and the throws' first pass started on 134 positions in 914
-- throws, none of them $35/$4E/$8F/$B3 or those four -- the keys repeat the
-- fight's Rand history, so its "distinct" throws are far from independent.
-- More Defends play more of Dullahan's turns before the throw, which moves
-- it; a candidate lost to a wipe is counted, not failed (below).  The
-- entry shift (OT6_SEED_SHIFT, the runner's own
-- idle at the boot point) is added to every wait, so a varied entry walks
-- the same keys in another order.  Each candidate is a full throw at 3 BP,
-- checked by checkJackpot like the passes above; the search stops once it
-- meets the empty pass (the redraw is staged above, and held here too when
-- a throw meets it).  A 760-frame stand and 4 Defends each wiped the party
-- on one key (labs-r5, search_all-r8, search_all-r9): a wipe before the
-- throw is a lost candidate, counted (below).
--
-- The bound the redraw had, when the search was its only source (it no
-- longer gates the run; see the staged redraw): the table holds 4 bytes past 251
-- of 256, a throw is four rolls, so a throw redraws with p = 1 - (252/256)^4
-- = 6.1%.  Throws that repeat one state repeat one outcome, so what counts
-- is the distinct throws among the candidates: with D distinct, the chance
-- none redraws is 0.939^D.  The whole set, played at entry shifts 0, 13 and
-- 29 (labs-r5/search_all-r10, JACKPOT_SEARCH_ALL): 99 distinct throws of
-- 127 played at each (the 128th was skipped by a predicate fixed since),
-- 6 of them redrawing (6.1%, as the model has it) and 33 with an empty
-- pass, no wipe -- so a fixture whose 99 distinct throws hold no redraw has
-- p = 0.939^99 = 0.2%, and then the suite fails by name, as it does if the
-- empty pass (a third of the throws) is not met.
--
-- A candidate the party does not survive: the measured set had no wipe on
-- its grave, but the grave moves with the route's timing, and on
-- wt/walker-after-menu's (the fixture gen_wor_falcon played at 67303338)
-- search 39 (wait 25, stand 0, 3 Defends, the others Defend) ended in a
-- party wipe before its throw, and the run failed on the canary's game over
-- (build/attempts/wt/walker-after-menu/round4/jackpot/).  The candidates are
-- experiments branched from one snapshot; one the party loses before its
-- Jackpot executes has no throw to check, so the lib's wipe predicate held
-- 90 frames (as gen_esper_tubes reads it) ends that candidate, the next one
-- reloads the grave, and the lost ones are counted in the search's last
-- line and its asserts (an all-lost search fails saying so).  Lost means
-- no Ot6SetzerExec for the Jackpot was seen: a wipe after the throw began
-- is held to "one Jackpot resolved" and fails.  90 frames is under the
-- canary's 300, so no game over is counted and allowGameOver stays off: a
-- wipe anywhere else still fails the run.
local ENTRY = (type(OT6_SEED_SHIFT) == "number" and OT6_SEED_SHIFT or 0)
local CAND = {}
for _, ds in ipairs({ { 2, 3 }, { 4, 5, 6 } }) do
  for _, st in ipairs({ 0, 640 }) do
    for _, d in ipairs(ds) do
      for _, of in ipairs({ false, true }) do
        for i = 0, 15 do CAND[#CAND + 1] = { wait = ENTRY + 1 + 4 * i, stand = st, defends = d, othersFight = of } end
      end
    end
  end
end
local S = { i = 0, played = 0, cur = nil, found = {}, seen = {}, distinct = 0 }

local function waitFor(fn)
  local c, n = 0, nil
  return { tick = function()
    if n == nil then n = fn() end
    if c < n then c = c + 1; return "frame" end
    return "done"
  end, reset = function() c, n = 0, nil end }
end

-- the Jackpot's Ot6SetzerExec (the row in $b6), seen per candidate; one
-- callback for the run, registered at the first candidate
local execHooked = false
local function hookExec()
  if execHooked then return end
  execHooked = true
  local a = H.sym("Ot6SetzerExec")
  emu.addMemoryCallback(function()
    if S.cur and H.readByte(0xB6) == JACKPOT then S.execF = S.execF or H.frame end
  end, emu.callbackType.exec, a, a)
end

local function candidateBattle()
  local step, wipedN
  return { tick = function()
    if step == nil then
      hookExec()
      local plan = {}
      for _ = 1, S.cur.defends do plan[#plan + 1] = { row = "defend" } end
      plan[#plan + 1] = { row = JACKPOT, boost = 3 }
      for _ = 1, 3 do plan[#plan + 1] = { row = "defend" } end
      plan[#plan + 1] = { row = JACKPOT, boost = 3 }
      step = H.setzerBattle(plan, { untilPlanDone = true, othersFight = S.cur.othersFight })
      wipedN, S.lost, S.execF, S.alive, S.wipeSeen, S.partyHP = 0, nil, nil, nil, nil, nil
    end
    -- the live-monster mask ($3A75) while the battle is up: 0 at the end
    -- means Dullahan fell (to the others' Fights, or the first Jackpot)
    if H.battleActive() then
      S.alive = H.readByte(0x3A75)
      local hp = {}
      for e = 0, 3 do hp[#hp + 1] = H.readWord(0x3BF4 + e * 2) end
      S.partyHP = table.concat(hp, "/")
    end
    wipedN = H.partyWipedInBattle() and wipedN + 1 or 0
    -- a wipe the game ends faster than the 90-frame predicate still lost it
    if wipedN > 0 then S.wipeSeen = H.frame end
    if wipedN >= 90 then
      S.lost = string.format("the party wiped (the lib's wipe predicate, 90 frames, at f%d)", H.frame)
      H.setPad({})
      return "done"
    end
    return step:tick()
  end, reset = function() step, wipedN = nil, 0 end }
end

-- pass 3: Jackpot picked at 3 BP and taken back to 2 at target select (L):
-- it executes at 2, so Ot6JackpotDice zeroes the pending and rolls
-- nothing, Ot6AbilityCost priced it at 2 (no MP), and the bank pays nothing
local takeBack = keyed(3, function(wait) return H.seqStep({
  H.loadState(STATE),
  wait and H.waitFrames(wait) or H.call(function() end),
  H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave (100,14): face up, A"),
  H.release(),
  H.setzerBattle({ { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3, takeBack = 2 } },
    { untilPlanDone = true }),
  H.call(function()
    local recs = H.vars.setzer
    H.assertEq(#recs, 1, "pass 3: the taken-back Jackpot executed once")
    local r = recs[1]
    H.log(string.format("[jackpot] pass 3: row $%02X at %d BP, MP %d -> %d, bank %d -> %d, %d roll(s)", r.row,
      r.boost, r.mp0, r.mp1, r.bank0, r.bank1, #r.dice))
    H.assertEq(r.row, JACKPOT, "pass 3: the row is Jackpot")
    H.assertEq(r.boost, 2, "pass 3: it executed at the 2 BP it was taken back to")
    H.assertEq(#r.dice, 0, "pass 3: a Jackpot taken back under 3 BP rolls nothing")
    H.assertEq(r.mp1, r.mp0, "pass 3: and charges no MP")
    H.assertEq(r.bank1 >= r.bank0, true, string.format("pass 3: and no points (bank %d -> %d)", r.bank0, r.bank1))
    for b, m in pairs(r.mon0) do
      H.assertEq(r.mon1[b].hp, m.hp, string.format("pass 3: slot %d's HP did not move", b))
    end
  end),
}) end)

-- ---- the redraw, staged ------------------------------------------------
-- The draw rule's second branch (a roll that meets a byte past 251 draws
-- again) is a property of the battle RNG table and a pass's $be, and a
-- fight reaches it only when a pass starts on one of the four positions
-- before such a byte.  v029's grave fight never did: no redraw over every
-- key (512 candidates) or 2-6 Defends (320) at entry shifts 0, 13 and 29,
-- the throws' first pass starting on 139 of the 256 positions and never on
-- one of the eight that lead to a redraw (build/attempts/wt/
-- v029-shield-grants/jackpot2/ to jackpot4/).  So the redraw is staged, a
-- declared mechanism expedient (state_write_waivers.txt), never play: the
-- grave's battle is played twice from the same frame with the same inputs
-- (two Defends, Jackpot at 3 BP), once to read how many Rands the action
-- draws between Ot6SetzerExec and its first pass, and once with $be written
-- at Ot6SetzerExec so that the first pass starts on a position before a
-- byte past 251.  That throw is held to everything checkJackpot holds, the
-- redraw included.  A redraw the search meets in play is held to the same
-- rule.
local RS = { phase = nil, be = nil, n = nil, trig = nil, hooked = false }
local function stagedPlay(phase)
  return H.seqStep({
    H.call(function()
      RS.phase, RS.be = phase, nil
      if RS.hooked then return end
      RS.hooked = true
      local rng = H.sym("RNGTbl") & 0x3FFFFF
      for t = 0, 255 do
        if RS.trig == nil and H.readRomByte(rng + ((t + 1) & 0xFF)) >= 252 then RS.trig = t end
      end
      H.assertEq(RS.trig ~= nil, true, "the battle RNG table holds a byte past 251")
      local a = H.sym("Ot6SetzerExec")
      emu.addMemoryCallback(function()
        if RS.phase == nil or RS.be ~= nil or H.readByte(0xB6) ~= JACKPOT then return end
        if RS.phase == "write" then H.writeByte(0xBE, (RS.trig - RS.n) & 0xFF) end
        RS.be = H.readByte(0xBE)
      end, emu.callbackType.exec, a, a)
    end),
    H.loadState(STATE),
    H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave (100,14): face up, A"),
    H.release(),
    H.setzerBattle({ { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 } }, { untilPlanDone = true }),
    H.call(function()
      local recs = H.vars.setzer
      H.assertEq(#recs, 1, "staged (" .. phase .. "): the Jackpot executed once")
      local q = recs[1].passes[1]
      H.assertEq(RS.be ~= nil and q ~= nil, true, "staged (" .. phase .. "): Ot6SetzerExec and the first pass seen")
      if phase == "measure" then
        RS.n = (q.be0 - RS.be) & 0xFF
        H.log(string.format("[jackpot] staged: $be %02X at Ot6SetzerExec, %02X at the first pass: %d Rand(s) "
          .. "between; a pass on %02X meets the byte past 251 at %02X", RS.be, q.be0, RS.n, RS.trig,
          (RS.trig + 1) & 0xFF))
        return
      end
      RS.phase = nil
      H.assertEq(q.be0, RS.trig, string.format("staged: the first pass starts on $%02X ($be written to %02X at "
        .. "Ot6SetzerExec, %d Rand(s) before it)", RS.trig, RS.be, RS.n))
      local g = checkJackpot(recs[1], 900)
      H.assertEq(g.redraws >= 1, true, "staged: a roll that meets a byte past 251 draws again")
      H.log(string.format("[jackpot] staged: the first pass on %02X redrew (%d redraw(s)), held to the draw rule",
        RS.trig, g.redraws))
    end),
  })
end
local staged = H.seqStep({ stagedPlay("measure"), stagedPlay("write") })

local search = H.seqStep({
  H.driveUntil(function()
    return S.found.empty or S.played >= #CAND
  end, 2000000, {
    H.call(function()
      S.i = S.i + 1
      S.cur = CAND[S.i]
    end),
    H.loadState(STATE),
    waitFor(function() return S.cur.wait end),
    H.faceAndHoldA("up", function() return H.battleLoadStarted() end, 3000, "the grave (100,14): face up, A"),
    H.release(),
    waitFor(function() return S.cur.stand end),
    candidateBattle(),
    H.call(function()
      S.played = S.played + 1
      local c, recs = S.cur, H.vars.setzer
      local label = string.format("search %d (wait %d, stand %d, %d Defends, the others %s)", S.i, c.wait, c.stand,
        c.defends, c.othersFight and "Fight" or "Defend")
      if S.lost and #recs == 0 and S.execF == nil then
        S.lostN = (S.lostN or 0) + 1
        H.log(string.format("[jackpot] %s: no throw -- %s before the Jackpot resolved (%d lost so far)", label,
          S.lost, S.lostN))
        return
      end
      H.log(string.format("[jackpot] %s: %d throw(s); at the end live monsters $%02X, party HP %s%s", label, #recs,
        S.alive or 0, tostring(S.partyHP), S.wipeSeen and string.format(", the party wiped (seen at f%d)", S.wipeSeen) or ""))
      if S.lost == nil and S.wipeSeen and #recs < 2 then
        S.lost = string.format("the party wiped (seen at f%d; the game ended the battle inside the 90-frame "
          .. "predicate)", S.wipeSeen)
      end
      if #recs == 1 and S.alive == 0 then
        H.log(string.format("[jackpot] %s: Dullahan fell before the second Jackpot", label))
      end
      H.assertEq(#recs >= 1 and (#recs == 2 or S.lost ~= nil or S.alive == 0), true, label .. ": both Jackpots "
        .. "resolved, or the party or Dullahan fell after the first" .. (S.lost and string.format(
        " (exec seen at f%s, then %s)", tostring(S.execF), S.lost) or ""))
      H.assertEq(S.execF ~= nil, true, label .. ": the exec hook saw this Jackpot (the lost-candidate check reads it)")
      local got = { empty = 0, redraws = 0 }
      local sig = {}
      for k, r in ipairs(recs) do
        H.assertEq(r.row == JACKPOT and r.boost == 3, true, label .. ": a Jackpot at 3 BP")
        local g = checkJackpot(r, (S.i + 3) * 10 + k)
        got.empty, got.redraws = got.empty + g.empty, got.redraws + g.redraws
        for _, q in ipairs(r.passes) do sig[#sig + 1] = string.format("%04X:%02X", q.mask, q.be0) end
      end
      sig = table.concat(sig, " ")
      if not S.seen[sig] then S.seen[sig] = true; S.distinct = S.distinct + 1 end
      H.log(string.format("[jackpot] %s: %d empty pass(es), %d redraw(s) | %s | %d distinct of %d", label,
        got.empty, got.redraws, sig, S.distinct, S.i))
      if got.empty > 0 and not S.found.empty then S.found.empty = label end
      if got.redraws > 0 and not S.found.redraw then S.found.redraw = label end
      if JACKPOT_SEARCH_ALL then S.found = {} ; S.foundAll = S.foundAll or {}
        if got.empty > 0 then S.foundAll.empty = (S.foundAll.empty or 0) + 1 end
        if got.redraws > 0 then S.foundAll.redraw = (S.foundAll.redraw or 0) + 1 end
      end
    end),
  }, "the search for an empty pass and a redraw"),
  H.call(function()
    if JACKPOT_SEARCH_ALL then
      H.log(string.format("[jackpot] search, the whole set: %d candidates, %d distinct throws, %d with an empty "
        .. "pass, %d with a redraw (entry shift %d)", S.played, S.distinct, (S.foundAll or {}).empty or 0,
        (S.foundAll or {}).redraw or 0, ENTRY))
      return
    end
    H.assertEq(S.found.empty ~= nil, true, string.format("the search met a pass that finds no body within its %d "
      .. "candidates (%d distinct)", #CAND, S.distinct))
    H.log(string.format("[jackpot] search: an empty pass at %s; a redraw in play %s; %d candidate(s), %d "
      .. "distinct, %d lost to a wipe before the first throw (entry shift %d)", S.found.empty,
      S.found.redraw and ("at " .. S.found.redraw) or "not met (the staged one holds the rule)", S.played,
      S.distinct, S.lostN or 0, ENTRY))
  end),
})

H.run({ maxFrames = 2500000 }, {
  H.call(installTick),
  pass(1, { { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 },
    { row = "defend" }, { row = "defend" }, { row = "defend" }, { row = JACKPOT, boost = 3 } }, 2),
  pass(2, { { row = JACKPOT, boost = 0, refused = true }, { row = JACKPOT, boost = 1, refused = true },
    { row = JACKPOT, boost = 2, refused = true } }, 0),
  takeBack,
  staged,
  search,
  H.call(function()
    H.log("[jackpot] PASSED: refused under 3 BP, two rolls at 3 BP, twice in one battle, the draw rule (a "
      .. "redraw past 251 included), 99 MP, no chip")
  end),
})
