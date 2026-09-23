-- @suite savestate=kolts_cave
-- battle_naturalmp.lua -- battle MP is universal, on natural MP.
--
-- Vanilla's battle init loads every character's MP through LoadCharProp and
-- then clears it again unless a magic or lore command init set the has-mp
-- flag $f8, that is, unless the character knows a spell (InitCmdList plus
-- InitCmd_03/04/05).  Under the live MP economy that sends every spell-less
-- character into battle at 0/0 while Ot6AbilityCost prices their whole kit:
-- Blitz, Tools, Bushido and Steal fizzle through CalcAttackEffect's
-- insufficient-MP gate, and the max-0 writeback skip keeps field MP full so
-- nothing on the field shows it.  This test pins no character state.
--
-- kolts_cave.mss: map 96, party TERRA LOCKE EDGAR with whatever MP their
-- real save carries, giving one innate mage (TERRA, the unchanged-path
-- control) and two spell-less kit carriers.

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/kolts_cave.mss.lua"

local MENU, ACTOR = 0x7BCA, 0x62CA
local EDGAR = 0x04
local AUTOCROSSBOW, XBOW_COST = 0xAA, 4    -- Ot6AbilityCostTbl: $aa, 4
local ITEMLIST = 0x4005                    -- MakeToolsList's wItemList

local function CURMP(s) return 0x3C08 + s * 2 end
local function MAXMP(s) return 0x3C30 + s * 2 end
local function MHP(m)  return 0x3BFC + m * 2 end
local CHARS = { [0]="TERRA","LOCKE","CYAN","SHADOW","EDGAR","SABIN",
                "CELES","STRAGO","RELM","SETZER","MOG","GAU","GOGO","UMARO" }

local function map() return H.mapId() & 0x1ff end

local slotOf, msPresent = {}, {}
local charOfs, fieldPre = {}, {}          -- per-slot $1600 offset / field MP
local costs = {}                          -- $3620 stores while cmd $09 queues
local edgarPre, hpsumPre

local function monsterHpSum()
  local t = 0
  for _, m in ipairs(msPresent) do t = t + H.readWord(MHP(m)) end
  return t
end

-- The fight is whatever the cave deals, so the AutoCrossbow is measured by
-- what it wrote, over its own action, not by a pool and an HP sum read
-- before a fixed wait.  Every write to a party pool is kept with $b5/$b6,
-- the in-flight action's command/attack ($3a7c/$3a7d) and X (the callback
-- runs before the store, so `old` is the pool as the write found it; the
-- high byte's store completes `new`).  EDGAR's Tools action is bracketed
-- by the same cell: InitPlayerAction loads $3a7c with the queued command
-- (X = the actor) as the action starts, and the next action overwrites it
-- as it starts (ExecAction's $12 placeholder, or a counterattack's own
-- InitPlayerAction; battle_main.asm @0276/@0100/@4b7b).  So the bracket
-- opens on $3a7c := $09 with X = his offset and closes on the next write;
-- actions serialize, so what moves inside it is the tool's doing.
local poolWrites = {}
local tool = nil                          -- the bracket, once his Tools action starts
local toolArmed = false
local function writeStr(w)
  return string.format("f%d slot%d %d->%d ($b5=%02X $b6=%02X $3a7c=%04X X=%02X)",
    w.frame, w.slot, w.old, w.new, w.cmd, w.atk, w.act, w.x)
end
local function installWatches()
  for slot = 0, 3 do
    local lo = 0x7E0000 + CURMP(slot)
    emu.addMemoryCallback(function(_, v)
      local old = H.readWord(lo)
      poolWrites[#poolWrites + 1] = { frame = H.frame, slot = slot, old = old,
        new = (old & 0xFF00) | v, cmd = H.readByte(0xB5), atk = H.readByte(0xB6),
        act = H.readWord(0x3A7C), x = emu.getState()["cpu.x"] & 0xFFFF }
    end, emu.callbackType.write, lo, lo)
    emu.addMemoryCallback(function(_, v)
      local w = poolWrites[#poolWrites]
      if w and w.slot == slot and w.frame == H.frame and w.hi == nil then
        w.hi = v
        w.new = (v << 8) | (w.new & 0xFF)
      end
    end, emu.callbackType.write, lo + 1, lo + 1)
  end
  emu.addMemoryCallback(function(_, v)
    if tool and not tool.done then
      tool.done, tool.doneFrame = true, H.frame
      tool.mp1, tool.hp1, tool.w1 = H.readWord(CURMP(slotOf[EDGAR])), monsterHpSum(), #poolWrites
      return
    end
    if not toolArmed or tool ~= nil or v ~= 0x09 then return end
    if (emu.getState()["cpu.x"] & 0xFFFF) ~= slotOf[EDGAR] * 2 then return end
    tool = { frame = H.frame, mp0 = H.readWord(CURMP(slotOf[EDGAR])),
             hp0 = monsterHpSum(), w0 = #poolWrites }
  end, emu.callbackType.write, 0x7E3A7C, 0x7E3A7C)
  emu.addMemoryCallback(function(_, v)
    if tool and tool.atk == nil and tool.frame == H.frame then tool.atk = v end
  end, emu.callbackType.write, 0x7E3A7D, 0x7E3A7D)
end
-- a slot's pool as the battle last held it: the last write before the
-- teardown's $FFFF, or the pool it loaded with when nothing wrote it
local function battleExitPool(s)
  for i = #poolWrites, 1, -1 do
    local w = poolWrites[i]
    if w.slot == s and w.new < 10000 then return w.new, w end
  end
  return fieldPre[s], nil
end

-- wait for a character's menu, consuming other characters' turns with a
-- real Defend (right swaps Fight->Def, then A); Defend is unpriced so it
-- cannot move anyone's MP.  Monsters take their own turns; their damage
-- lands on party HP, which nothing in this test asserts on.
local function menuFor(charId, what)
  local ph = 0
  local function up()
    return H.readByte(MENU) ~= 0 and H.readByte(ACTOR) == slotOf[charId]
  end
  return H.driveUntil(up, 20000, {
    H.call(function()
      ph = ph + 1
      if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[charId] then
        local step = ph % 40
        if step < 4 then H.setPad({ right = true })
        elseif step >= 20 and step < 24 then H.setPad({ a = true })
        else H.setPad({}) end
      else
        H.setPad({})
      end
    end),
  }, what)
end

local function tap(btn, gap)
  return H.repeatN(1, {
    H.pressButtons({ btn }, 4),
    H.waitFrames(gap or 16),
  })
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(20),
  H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 3000,
    "field control in cave 96"),
  H.call(function() H.assertEq(map(), 96, "kolts_cave on map 96") end),

  (function()
    local battN, waited, lane = 0, 0, nil
    local BACK = { left = "right", right = "left", up = "down", down = "up" }
    return H.driveUntil(function()
      waited = waited + 1
      battN = H.battleLoadStarted() and battN + 1 or 0
      if battN >= 1 then H.setPad({}) return true end
      if map() ~= 96 then error("paced off map 96 (now " .. map() .. ")", 0) end
      return waited >= 8000
    end, 8600, {
      H.call(function()
        if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
        local x, y = H.fieldX(), H.fieldY()
        if lane == nil then
          for _, d in ipairs({ "right", "left", "up", "down" }) do
            if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
          end
        end
        H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
      end),
      H.waitFrames(1),
    }, "a cave encounter fires")
  end)(),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle armed", 5),
  H.waitFrames(240),

  -- ------------------------- 1. universal load: battle MP == field MP --
  H.call(function()
    for s = 0, 3 do
      local id = H.readByte(0x3ED8 + s * 2)
      if id ~= 0xFF then
        slotOf[id] = s
        charOfs[s] = H.readWord(0x3010 + s * 2)
        fieldPre[s] = H.readWord(0x160d + charOfs[s])
        local cur, max = H.readWord(CURMP(s)), H.readWord(MAXMP(s))
        H.log(string.format("[slot %d] %s battle MP=%d/%d field MP=%d", s,
          CHARS[id] or tostring(id), cur, max, fieldPre[s]))
        H.assertEq(max > 0, true, string.format(
          "%s enters battle with a real max MP (got %d; the vanilla "
          .. "spell-less clear zeroes it)", CHARS[id] or tostring(id), max))
        H.assertEq(cur, fieldPre[s], string.format(
          "%s enters battle with the save's own MP", CHARS[id] or tostring(id)))
      end
    end
    for m = 0, 5 do
      if H.readByte(0x3AA8 + m * 2) % 2 == 1 then msPresent[#msPresent + 1] = m end
    end
    assert(slotOf[EDGAR], "EDGAR present (kolts party)")
    assert(slotOf[0x00], "TERRA present (the innate-mage control)")
    H.assertEq(fieldPre[slotOf[EDGAR]] >= XBOW_COST, true,
      "positive control: Edgar's save MP can afford an AutoCrossbow")
    -- mp-cost queue store (CreateAction), filtered to Tools (cmd $09)
    emu.addMemoryCallback(function(_, v)
      if H.readByte(0x3A7A) == 0x09 then costs[#costs + 1] = v end
    end, emu.callbackType.write, 0x7E3620, 0x7E3620 + 0xFE)
    installWatches()
  end),

  -- --------------- 2. a priced verb executes and charges, naturally --
  menuFor(EDGAR, "edgar_menu"),
  H.waitFrames(30),
  H.call(function()
    costs = {}
    edgarPre = H.readWord(CURMP(slotOf[EDGAR]))
    hpsumPre = monsterHpSum()
    tool, toolArmed = nil, true
    H.log(string.format("[edgar pre] MP=%d hpsum=%d", edgarPre, hpsumPre))
  end),
  tap("down", 20),                        -- Fight -> Tools (row 1, cmd $09)
  tap("a", 60),                           -- the Tools submenu opens
  -- wItemList holds 3-byte records (id, usage flags, targeting); the drawn
  -- grid is 2 columns, row-major, so tool index i sits at row i//2, col i%2.
  H.call(function()
    H.log(string.format("[edgar] mstate=%02X after Tools A", H.readByte(0x7BC2)))
    local list, idx = {}, nil
    for i = 0, 7 do
      local id = H.readByte(ITEMLIST + i * 3)
      list[#list + 1] = string.format("%02X", id)
      if id == 0xFF then break end            -- end of the packed list
      if id == AUTOCROSSBOW and not idx then idx = i end
    end
    H.log("[edgar] tool ids = { " .. table.concat(list, " ") .. " }")
    assert(idx, "AutoCrossbow in the tools list")
    H.log(string.format("[edgar] AutoCrossbow at tools index %d", idx))
    H.vars.xbowRow, H.vars.xbowRight = math.floor(idx / 2), (idx % 2) == 1
    H.screenshot("naturalmp_tools_open")
  end),
  H.cond(function() return H.vars.xbowRight end, { tap("right", 16) }, {}),
  (function()
    local steps = {}
    for _ = 1, 3 do
      steps[#steps + 1] = H.cond(function()
        if (H.vars.xbowSteps or 0) < H.vars.xbowRow then
          H.vars.xbowSteps = (H.vars.xbowSteps or 0) + 1
          return true
        end
        return false
      end, { tap("down", 16) }, {})
    end
    return H.repeatN(1, steps)
  end)(),
  tap("a", 30),                           -- pick AutoCrossbow
  tap("a", 30),                           -- confirm target
  -- his tool runs whenever the queue reaches it: the others' turns are
  -- still spent on Defends meanwhile (a bystander window left open would
  -- freeze a Wait-mode clock under it), and the wait is on the action's own
  -- end, not a frame count
  (function()
    local ph = 0
    return H.driveUntil(function() return tool ~= nil and tool.done end, 20000, {
      H.call(function()
        ph = ph + 1
        if H.readByte(MENU) ~= 0 and H.readByte(ACTOR) ~= slotOf[EDGAR] then
          local step = ph % 40
          if step < 4 then H.setPad({ right = true })
          elseif step >= 20 and step < 24 then H.setPad({ a = true })
          else H.setPad({}) end
        else
          H.setPad({})
        end
      end),
    }, "EDGAR's AutoCrossbow runs, start to end")
  end)(),
  H.call(function()
    toolArmed = false
    local e = slotOf[EDGAR]
    local inside = {}
    for i = tool.w0 + 1, tool.w1 do
      if poolWrites[i].slot == e then inside[#inside + 1] = poolWrites[i] end
    end
    local desc, moved = {}, {}
    for _, w in ipairs(inside) do desc[#desc + 1] = writeStr(w) end
    for i = 1, tool.w0 do
      if poolWrites[i].slot == e then moved[#moved + 1] = writeStr(poolWrites[i]) end
    end
    local c = {}
    for _, v in ipairs(costs) do c[#c + 1] = string.format("%d", v) end
    H.log(string.format(
      "[edgar autocrossbow] ($3a7c=%02X09) f%d..f%d: MP %d -> %d, hpsum %d -> %d "
      .. "(dmg %d), costq={%s}; his pool's writes inside it: %s; before it (since "
      .. "the window, pool %d): %s", tool.atk or 0xFF, tool.frame, tool.doneFrame,
      tool.mp0, tool.mp1, tool.hp0, tool.hp1, tool.hp0 - tool.hp1, table.concat(c, ","),
      #desc > 0 and table.concat(desc, ", ") or "none", edgarPre,
      #moved > 0 and table.concat(moved, ", ") or "none"))
    H.assertEq(tool.atk, AUTOCROSSBOW,
      "the action measured is his AutoCrossbow ($3a7c/$3a7d = $09/$AA)")
    H.assertEq(costs[1], XBOW_COST,
      "Ot6AbilityCost priced the AutoCrossbow at 4 MP")
    H.assertEq(#inside, 1, "one write to his pool inside the tool's own action")
    H.assertEq(inside[1].cmd == 0x09 and inside[1].x == e * 2, true,
      "...made under his own Tools command ($b5 = $09, X = his slot)")
    H.assertEq(inside[1].old - inside[1].new, XBOW_COST,
      "the AutoCrossbow charged exactly its price from NATURAL MP, from the "
      .. "pool the charge found (pre-fix: the 0/0 fizzle charges nothing)")
    H.assertEq(tool.hp0 - tool.hp1 > 0, true,
      "the AutoCrossbow dealt damage (pre-fix: the fizzle deals nothing)")
    H.screenshot("naturalmp_xbow_resolved")
  end),

  -- ----------------------------------- 3. writeback: field MP correct --
  -- End the fight the way a player can, by fleeing with held L+R: the flee
  -- exit runs the same character writeback, so asserting on it here covers
  -- the exit path a real escape takes.  (A pack the tool already finished
  -- ends in a win instead, through the same writeback.)  What the field
  -- must hold is the pool the battle last held for each slot -- the
  -- AutoCrossbow's charge, and whatever else the fight wrote there, which
  -- is listed -- not the pre-battle pool less a price.  A pack that cannot
  -- be run from ($b1 bit 1, the flag the run command itself tests, or the
  -- formation's own no-L+R bit $2f4b bit 0 -- the lib's cantRun reading)
  -- is fought out through the Fight menu instead: measured at two ledge
  -- fights and a 37-frame idle before the walk (build/lab/mpb/nm_sweep1/
  -- {orig,fix}_prior2_idle37.log), the held L+R met "Can't run away!!"
  -- for 12000 frames while the pack KO'd EDGAR.
  H.cond(function()
    return (H.readByte(0x00B1) & 0x02) ~= 0 or (H.readByte(0x2F4B) & 0x01) ~= 0
  end, {
    H.call(function()
      H.log(string.format("[exit] this pack cannot be run from ($b1=%02X $2f4b=%02X): "
        .. "fighting it out; the win runs the same writeback", H.readByte(0x00B1),
        H.readByte(0x2F4B)))
    end),
    H.fightBattleByMenu(30000),
  }, {
    H.fleeBattle(12000),
  }),
  H.waitFrames(120),
  H.call(function()
    for s = 0, 3 do
      if charOfs[s] then
        local want, last = battleExitPool(s)
        local now = H.readWord(0x160d + charOfs[s])
        local moves = {}
        for _, w in ipairs(poolWrites) do
          if w.slot == s and w.new < 10000 then moves[#moves + 1] = writeStr(w) end
        end
        H.log(string.format("[writeback slot %d] field MP %d -> %d; the battle's "
          .. "writes to this pool: %s", s, fieldPre[s], now,
          #moves > 0 and table.concat(moves, ", ") or "none"))
        H.assertEq(now, want,
          "post-battle field MP = the pool the battle ended on (pre-battle "
          .. "minus exactly what was spent)")
        if s == slotOf[EDGAR] then
          H.assertEq(last ~= nil, true,
            "...and EDGAR's is a pool the battle wrote (the AutoCrossbow's charge "
            .. "or later), not the one he walked in with")
        end
      end
    end
  end),

  H.logStep(function() return "battle_naturalmp complete" end),
})
