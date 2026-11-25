-- @suite savestate=n024_entry slow
-- battle_number024.lua -- Number 024 under the boss contract (docs/design/bosses-wob.md block 14,
-- wt/v052-tg-wob2): the wall's spell is his telegraph, the wall holds while it is named, and a break cancels it.
--
-- His script (ai_script.asm AIScript::_266): his clock's WallChange (the monster timer at 30) now ARMS the fuse
-- (monster switch 0).  On his next turn, on a wall whose vanilla answer holds a tier-2 spell -- weak to fire (Ice 2,
-- attack $06), to ice (Fire 2, $05) or to water (Bolt 2, $07) -- he says "Its wall glows!" (battle dialogue $95),
-- glows and holds the wall (monster switch 1: his counters change no wall while it is set), and the spell, on every
-- standing member (command $02), comes on the turn after.  On any other wall the arming lapses.  Under the contract
-- (Ot6FuseTbl's three rows $010A) a break while it is lit cancels it: the script waits nowhere, both switches are
-- clear, and the next WallChange of his clock arms it again.
--
-- Boots n024_entry (gen_n024_entry: map 273, one A press below him), opens battle 72 and plays it from a snapshot
-- at its open (M.fuseCases, lib/ot6.lua, where the cases and the DECLARED staging are written out: the gauge, the
-- row's classes for the breaking Fight, HP held -- his at 3,000):
--   unbroken  the party Defends; the line shows on the turn after a WallChange of his clock onto one of the three
--             walls; the lit-fuse mark stands; the spell that wall names is dispatched on his next turn, a glow
--             between; the mark goes.
--   broken    an aimed Fight confirmed once the mark is up breaks him: the cancel fires, the mark goes, switches 0
--             and 1 read clear, no spell on his first turns back, and the line returns only after another WallChange
--             of his clock; the spell follows.
--   outside   a break after his first turn, before any line: nothing is cancelled and the cells stand, two aimed
--             Fights in the window wind nothing, and the fuse then lights and fires as in the first case.
-- Every announce is checked against the wall: the spell is the one the wall at the line names, and the wall did not
-- change between the line and the spell.  Then, held: a seated member who knows the spell of the wall's weakness
-- (Fire on a fire wall, Ice on an ice wall) casts it at him after a line, his gauge staged so the cast cannot break
-- him: the counter that would have changed the wall (vanilla's `if_element` / `if_weak_element` / WallChange) does
-- not, and the named spell comes.
-- Mutants (build/attempts/wt/v052-tg-wob2/mutants/): fuse_never (Ot6FuseCancel+3=80) is red at "the break during
-- the fuse cancels it"; n024_no_hold (the announce sets monster switch 7, not 1) at "the wall did not change between
-- the line and the spell -- held: a weakness cast inside the fuse".  A mechanism test, not play.
local H = dofile("tools/tests/lib/ot6.lua")
-- the suite's declared writers (M.fuseCases stages the gauge, the row and held HP through them, and nothing else;
-- the held case stages the gauge through them too)
local WRITE = { byte = function(a, v) H.writeByte(a, v) end, word = function(a, v) H.writeWord(a, v) end }
local STATE = "build/states/n024_entry.mss.lua"

local N024 = 0x10A
local SPELL_OF = { [0x01] = 0x06, [0x02] = 0x05, [0x80] = 0x07 }  -- weak to fire: Ice 2; ice: Fire 2; water: Bolt 2
local CAST_FOR = { [0x01] = 0x00, [0x02] = 0x01 }                  -- the weakness cast at him: Fire, Ice
local function map() return H.mapId() & 0x1ff end
local function slot()
  for s = 0, 5 do
    if H.readByte(0x3AA8 + s * 2) & 1 == 1 and H.readWord(0x57C0 + s * 2) == N024 then return s end
  end
  return nil
end
-- his wall ($3BE0: the weak elements), frame by frame
local wall, wallOn = {}, false
local function wallAt(f) return wall[f] end

local function checkWall(W, l, mvI, what)
  local mv = W.cmds[mvI]
  local w0 = wallAt(l.f)
  H.assertEq(w0 ~= nil and SPELL_OF[w0] ~= nil, true, string.format("number024: the line came on a fire, ice or water "
    .. "wall (%s) -- %s", w0 and string.format("$%02X", w0) or "unread", what))
  local changed = nil
  for f = l.f, mv.f do if wall[f] ~= nil and wall[f] ~= w0 and changed == nil then changed = f end end
  H.assertEq(changed, nil, string.format("number024: the wall did not change between the line and the spell -- %s",
    what))
  H.assertEq(mv.arg, SPELL_OF[w0], string.format("number024: the spell ($%02X) is the one the wall at the line ($%02X) "
    .. "names ($%02X) -- %s", mv.arg, w0, SPELL_OF[w0], what))
end

-- The cap: three cases of about 10,000 frames each and the held tries, so 100,000 is about 2x.
H.run({ maxFrames = 100000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(30),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000, "field control below Number 024"),
  H.call(function()
    emu.addEventCallback(function()
      if not wallOn then return end
      local s = slot()
      if s then wall[H.frame] = H.readByte(0x3BE0 + 8 + 2 * s) end
      wall[H.frame - 60000] = nil
    end, emu.eventType.endFrame)
  end),
  H.fuseEngage(function()
    H.assertEq(map(), 273, "n024_entry stands on map 273")
    return H.driveUntil(function() return H.battleLoadStarted() end, 4000, {
      H.pressButtons({ "a" }, 4), H.waitFrames(6),
    }, "one A press -> battle 72")
  end, N024, "Number 024"),
  H.call(function() wallOn = true end),
  H.fuseCases({
    tag = "number024", species = N024, write = WRITE,
    line = 0x95, move = { cmd = 0x02, atks = { [0x05] = true, [0x06] = true, [0x07] = true } }, turns = 1, glows = 1,
    arm = "idle", aim = true, allTargets = true,
    bossHp = 3000,
    partway = function(W)
      local c = W.cells()
      return c ~= nil and #W.turns >= 1 and (c.mvar & 0x03) == 0
    end,
    fired = function(C, W, n)
      checkWall(W, C.lines[n], C.lines[n].move.i, string.format("case %s, announce %d", C.name, n))
    end,
    earned = function(C, W)
      local post, l2 = C.brk.post, C.lines[2]
      H.assertEq(post.mvar & 0x03, 0, "number024: switches 0 and 1 are clear after the cancel")
      -- a WallChange of his clock (attack $C1 on his own turn, not his counter's) between the cancel and the line
      local wc = 0
      for _, c in ipairs(W.cmds) do
        if c.f > C.brk.f and c.f < l2.f and c.cmd == 0x0C and c.arg == 0xC1 and not c.retal then wc = wc + 1 end
      end
      H.assertEq(wc >= 1, true, string.format("number024: a WallChange of his clock came between the cancel and the "
        .. "second line (%d)", wc))
    end,
  }),
  -- held: a weakness cast at him while his spell is named, up to six announces
  (function()
    local W = nil
    local tries, done, from = 0, false, 1
    local function one()
      return H.cond(function() return not done and tries < 6 end, {
        H.call(function() tries = tries + 1 end),
        -- the next announce on a wall the party can cast at
        H.lazy(function()
          return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 20000,
            giveUp = function() return W.find(0x21, 0x95, from) ~= nil or not H.battleLoadStarted() end })
        end),
        H.lazy(function()
          local li, lc = W.find(0x21, 0x95, from)
          H.assertEq(li ~= nil, true, "held: an announce came")
          local w = wallAt(lc.f)
          local sp = CAST_FOR[w or 0]
          local who = nil
          if sp then
            for i = 0, 3 do
              local id = H.readByte(0x3ED8 + 2 * i)
              if id ~= 0xFF and H.readWord(0x3BF4 + 2 * i) > 0 and H.readByte(0x1A6E + 54 * id + sp) == 0xFF then
                who = id
              end
            end
          end
          H.log(string.format("[number024] held try %d: the line at f%d on wall $%02X; %s", tries, lc.f, w or 0,
            who and string.format("character %d casts spell $%02X", who, sp) or "no member casts its weakness"))
          if who == nil then
            from = li + 1
            return H.kitBattle({}, { idle = "defend", care = true, maxFrames = 8000,
              giveUp = function() return W.find(0x02, nil, li) ~= nil or not H.battleLoadStarted() end })
          end
          local e = 8 + 2 * slot()
          WRITE.byte(0x3E38 + e, 63)   -- (DECLARED: the gauge held, so the cast chips and cannot break him)
          local plan = { { who = who, cmd = 0x02, spell = sp, boost = 0, slot = slot() } }
          local cast = false
          return H.seqStep({
            H.kitBattle(plan, { idle = "defend", care = false, maxFrames = 8000, untilPlanDone = true,
              giveUp = function() return W.find(0x02, nil, li) ~= nil or not H.battleLoadStarted() end }),
            H.kitBattle({}, { idle = "defend", care = false, maxFrames = 8000,
              giveUp = function() return W.find(0x02, nil, li) ~= nil or not H.battleLoadStarted() end }),
            H.call(function()
              local mi = W.find(0x02, nil, li)
              if mi == nil then
                H.log("[number024] held: no spell after the line within the wait; another announce")
                from = li + 1
                return
              end
              -- the party's cast, dispatched between the line and the spell (W.party: the Magic commands)
              local landed = nil
              for _, p in ipairs(W.party) do if p.f > lc.f and p.f < W.cmds[mi].f then landed = p.f end end
              if landed == nil then
                H.log("[number024] held: the cast did not land inside the fuse; another announce")
                from = mi + 1
                return
              end
              local counters = 0
              for _, c in ipairs(W.cmds) do
                if c.retal and c.f > landed and c.f < W.cmds[mi].f then counters = counters + 1 end
              end
              H.log(string.format("[number024] held: the cast at f%d, inside the fuse (line f%d, spell f%d); %d "
                .. "counter command(s) between", landed, lc.f, W.cmds[mi].f, counters))
              checkWall(W, { f = lc.f }, mi, "held: a weakness cast inside the fuse")
              done = true
            end),
          })
        end),
      }, {})
    end
    local steps = { H.call(function() W = H.fuseWatch(N024, WRITE); W.partyCmd = 0x02; W.on = true end) }
    for k = 1, 6 do steps[#steps + 1] = one() end
    steps[#steps + 1] = H.call(function()
      H.assertEq(done, true, "held: a weakness cast landed inside a fuse within six announces (the case's "
        .. "precondition: a member knows Fire or Ice and the wall named one)")
      W.on = false
    end)
    return H.seqStep(steps)
  end)(),
  H.logStep("[number024] PASS: the wall's spell announced, held, cancelled by a break and earned again"),
})
