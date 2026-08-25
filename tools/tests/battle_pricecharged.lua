-- battle_pricecharged.lua -- #79
-- @suite savestate=worldmap_narshe
--
-- The price the battle menu PUBLISHES for a spell is the price the cast
-- actually DEBITS.  battle_costtable pins
-- all 54 published prices against the design table; this closes the other
-- half -- publish vs charge -- which is the check #76 believed it had and
-- turned out not to (it was measuring a spell nobody had learned).
--
-- Method: boot worldmap_narshe (codex_saveas' proven base: encounters
-- land from it and TERRA casts from a real list), walk into a live
-- encounter, and sweep her battle magic list: for every enabled entry the
-- current MP can pay, steer to the cell, cast at the default target, and
-- assert the MP delta equals the byte the menu itself displays (the
-- +3 cost byte of the $302C list entry -- the same byte the menu draws).
-- The battle may end mid-sweep; two encounters are chained.  The premise
-- assertion is >= 2 distinct spells measured with zero discrepancies --
-- portable against loadout drift, strict about the property (all 54
-- published prices are battle_costtable's job; this file pins
-- publish == charge on the spells a real fixture can afford).
--
-- Reads and pad presses only (issue #75).
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/worldmap_narshe.mss.lua"
local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW = 0x202E, 0x890F
local ST_CMD, ST_TGT, ST_TRANS, ST_MAGIC = 0x05, 0x38, 0x01, 0x0E
local MLISTPTR, CURMP = 0x302C, 0x3C08
local CMD_MAGIC = 0x02

local function mp(a) return H.readWord(CURMP + a * 2) end
local function listEntry(a, cell)
  local base = H.readWord(MLISTPTR + a * 2)
  if base < 0x2000 or base > 0x2600 then return nil end
  local at = base + (cell + 1) * 4
  return H.readByte(at), H.readByte(at + 1), H.readByte(at + 3)
end
local function cmdRowOf(a, cmd)
  for i = 0, 3 do
    if H.readByte(CMDTBL + a * 12 + i * 3) == cmd then return i end
  end
  return nil
end

-- the sweep record: measured[id] = { want = published, got = delta }
local measured, discrepancies = {}, {}
local function nextTarget(a)
  -- the first enabled, affordable, not-yet-measured cell
  for cell = 0, 53 do
    local id, flags, cost = listEntry(a, cell)
    if id == nil then return nil end
    if id ~= 0xFF and (flags & 0x80) == 0 and cost > 0
       and measured[id] == nil and mp(a) >= cost then
      return cell, id, cost
    end
  end
  return nil
end

-- one battle's worth of sweeping; returns a driveUntil step
local function sweepBattle(n)
  local mf, caster = 0, nil
  local pendingId, pendingCost, mpAt = nil, nil, nil
  local doneHere = false
  return H.driveUntil(function()
    -- a pending cast resolves when MP moves (the debit is the signal)
    if pendingId and caster and mp(caster) ~= mpAt then
      local got = mpAt - mp(caster)
      measured[pendingId] = { want = pendingCost, got = got }
      if got ~= pendingCost then
        discrepancies[#discrepancies + 1] =
          string.format("$%02X published %d charged %d",
            pendingId, pendingCost, got)
      end
      H.log(string.format("[price] $%02X published %d charged %d %s",
        pendingId, pendingCost, got,
        got == pendingCost and "ok" or "MISMATCH"))
      pendingId = nil
    end
    if not H.battleActive() and not H.battleLoadStarted() then return true end
    return doneHere
  end, 30000, {
    H.call(function()
      mf = mf + 1
      if mf % 600 == 0 then
        H.log(string.format("  [sweep %d] mf=%d menu=%02X st=%02X act=%d done=%s",
          n, mf, H.readByte(MENU), H.readByte(MSTATE), H.readByte(ACTOR),
          tostring(doneHere)))
      end
      if H.readByte(MENU) == 0 then
        -- battle-end fanfare and exp screens advance on A (the standard
        -- idiom); the transitional-state guard below covers the reopen
        H.setPad(mf % 8 < 4 and { a = true } or {})
        return
      end
      if mf % 10 >= 5 then H.setPad({}); return end
      local a = H.readByte(ACTOR)
      local st = H.readByte(MSTATE)
      if st == ST_TRANS then H.setPad({}); return end
      if doneHere then
        -- sweep complete: everyone plain-Fights to finish the battle
        if st == ST_CMD then
          local cur = H.readByte(CMDROW + a) & 3
          H.setPad(cur == 0 and { a = true } or { up = true })
        elseif st == ST_TGT then H.setPad({ a = true })
        else H.setPad({ b = true }) end
        return
      end
      -- the caster is whoever holds the deepest list; latch the first
      -- actor that has a Magic row at all
      if caster == nil and cmdRowOf(a, CMD_MAGIC) then caster = a end
      if a ~= caster then
        -- a bystander's open command window freezes the Wait-mode clock
        -- (#72's hazard): X passes the menu to the next ready actor; B
        -- backs out of any list
        H.setPad(st == ST_CMD and (mf % 8 < 4 and { x = true } or {})
                 or { b = true })
        return
      end
      local btn = nil
      if st == ST_CMD then
        if pendingId then H.setPad({}); return end
        local cell = nextTarget(a)
        if cell == nil then doneHere = true; H.setPad({}); return end
        local row = cmdRowOf(a, CMD_MAGIC)
        local cur = H.readByte(CMDROW + a) & 3
        btn = (cur == row) and "a" or (cur < row and "down" or "up")
      elseif st == ST_MAGIC then
        local cell, id, cost = nextTarget(a)
        if cell == nil then btn = "b"
        else
          local wantRow, wantCol = cell // 2, cell % 2
          local absRow = H.readByte(0x8913 + a) + H.readByte(0x891B + a)
          local col = H.readByte(0x8917 + a)
          if absRow ~= wantRow then
            btn = (absRow < wantRow) and "down" or "up"
          elseif col ~= wantCol then
            btn = (col < wantCol) and "right" or "left"
          else
            pendingId, pendingCost, mpAt = id, cost, mp(a)
            btn = "a"
          end
        end
      elseif st == ST_TGT then
        btn = "a"       -- #111: offensive/heal confirm, engine's default
      else
        btn = "b"       -- #90: B in unrecognised states
      end
      H.setPad(btn and { [btn] = true } or {})
    end),
  }, "price sweep, battle " .. n)
end

local steps = {
  H.loadState(STATE),
  H.waitFrames(60),
}
local function patrolIntoBattle(n)
  -- codex_saveas' grass patrol: enterEncounter's field-style held-up walk
  -- does nothing on the world engine, so walk the (82,56)<->(82,50) grass
  -- lane until an encounter fires
  local plan, idx, goal = nil, 1, { 82, 56 }
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 20000, {
      H.call(function()
        if not H.worldMode() then H.setPad({}); return end
        if not H.worldHasControl() then plan = nil; H.setPad({}); return end
        if not H.worldAligned() then return end
        if not plan or idx > #plan then
          if H.worldX() == goal[1] and H.worldY() == goal[2] then
            goal = (goal[2] == 56) and { 82, 50 } or { 82, 56 }
          end
          plan = H.worldBfs(goal[1], goal[2]); idx = 1
          if not plan or #plan == 0 then plan = nil; H.setPad({}); return end
        end
        local dir = plan[idx]; idx = idx + 1
        if not dir then H.setPad({}); return end
        H.setPad({ [dir] = true })
      end),
    }, "grass encounter " .. n),
    H.release(),
    H.waitUntil(function() return H.battleActive() end, 900,
      "battle active " .. n, 30),
  })
end
for n = 1, 2 do
  steps[#steps + 1] = patrolIntoBattle(n)
  steps[#steps + 1] = sweepBattle(n)
  steps[#steps + 1] = H.waitFrames(240)
end
steps[#steps + 1] = H.call(function()
  local count, lines = 0, {}
  for id, r in pairs(measured) do
    count = count + 1
    lines[#lines + 1] = string.format("$%02X:%d", id, r.want)
  end
  table.sort(lines)
  H.log(string.format("[price] %d spells measured: %s", count,
    table.concat(lines, " ")))
  H.assertEq(#discrepancies, 0, "every published price was the price " ..
    "charged" .. (#discrepancies > 0
      and (" -- " .. table.concat(discrepancies, "; ")) or ""))
  H.assertEq(count >= 2, true,
    "at least two distinct spells measured (premise: the fixture's " ..
    "caster knows an affordable list)")
end)
H.run({ maxFrames = 150000 }, steps)
