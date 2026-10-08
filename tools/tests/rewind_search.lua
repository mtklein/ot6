-- @manual splice: tools/tests/gen_sabin_trench.lua with REWIND = { char = 5, species = { 0x59 } }
-- (the qualification smoke above; real runs go through tools/tests/rewind_search.py)
-- rewind_search.lua -- the rewind-search lab instrument (#375).  A lab
-- tool: it never enters the route chain or any balance evidence.
--
-- This file is not a script of its own.  tools/tests/rewind_search.py
-- splices it into a host script (a leg's generator) right after the
-- host's `local H = dofile(".../lib/ot6.lua")` line, with a `REWIND = {...}`
-- table in front of it, and runs the result with retries off and nothing
-- published.  The host plays as it always does.  At each DECISION -- a
-- fight driver's makePlan for the named character, in a battle whose
-- formation holds one of the named species -- the instrument:
--
--   1. lets the driver decide (its own plan, P0), then saves a whole
--      emulator snapshot (H.requestSaveState) and a copy of the driver's
--      own memory (the fight driver's Lua table: what it has measured this
--      battle), both on the same frame boundary;
--   2. plays the driver's own choice out to the fight's end from the live
--      state (branch "own"), then, for every option that command window
--      offers (each command the driver can execute through the menu: Fight
--      on each standing monster, each known Blitz, each heal item on each
--      member it can help; each at every boost the bank and the MP pay
--      for), restores the snapshot and the driver's memory, swaps in that
--      plan, and plays it out to the fight's end with the same driver;
--   3. restores once more and lets the driver's own plan continue as the
--      run, so later decisions are reached by plain play; when that
--      continuation reaches the fight's end it must match branch "own"
--      exactly (frame, HP, MP, deaths, outcome) -- the instrument's own
--      check that a restore is a coherent restart ([rewind] control).
--
-- One decision deep: only the decision itself is swapped; every later
-- turn is the driver's.  Restores are whole machine states (never selected
-- RAM), and the driver's memory is restored with them so no branch knows
-- another's future.  Everything a branch does is through the menu: the
-- swapped plan is executed by the driver's own button() walk.
--
-- Scoring, per branch, from the decision to the fight's end (the battle's
-- outcome record, or a wipe): outcome, party deaths, members down at the
-- end, HP lost, MP spent, items spent and their gil value, frames, and the
-- monster actions taken (attack ids), one `[rewind] branch` line each.
--
-- REWIND fields (rewind_search.py writes them):
--   char       the character whose command windows are searched (5 = SABIN)
--   species    list of species words; a decision counts only in a
--              formation holding one (nil: any battle)
--   decisions  list of decision numbers to search (nil: every one)
--   when       function(driver, actor, plan) -> true for a decision to
--              search (nil: every one); a host may set REWIND.when after
--              the splice, e.g. the care race's disagreements (#415)
--   extra      function(driver, actor) -> a plan to play as one more
--              branch, said "race: ..." (nil: none), e.g. the care race's
--              own choice where the window's options do not hold it
--   capFrames  a branch not over after this many frames is scored "open"
--   boosts     boost levels offered (default 0..3, capped by the bank)
do
  assert(type(REWIND) == "table", "rewind_search.lua needs a REWIND table "
    .. "(run it through tools/tests/rewind_search.py)")
  local RW = REWIND
  RW.capFrames = RW.capFrames or 12000
  local function log(fmt, ...) H.log("[rewind] " .. string.format(fmt, ...)) end

  -- battle-RAM addresses, as lib/ot6.lua's BATTLE table names them
  local CMDTBL, BP, CURMP, BCHID, BATTINV = 0x202E, 0x3E9C, 0x3C08, 0x3ED8, 0x2686
  local HP, MAXHP, MONHP = 0x3BF4, 0x3C1C, 0x3BFC
  local CMD_FIGHT, CMD_ITEM, CMD_BLITZ = 0x00, 0x01, 0x0A
  local FENIX = 0xF0
  local CARE_ITEMS = { 0xE8, 0xE9, 0xEA, 0xEE, FENIX }   -- Tonic, Potion, X-Potion, Elixir, Fenix Down

  local function cmdRow(actor, cmd)
    for row = 0, 3 do
      if H.readByte(CMDTBL + actor * 12 + row * 3) == cmd
         and (H.readByte(CMDTBL + actor * 12 + row * 3 + 1) & 0x80) == 0 then
        return row
      end
    end
    return nil
  end
  local function monAlive(s)
    return H.readWord(MONHP + s * 2) > 0 and (H.readByte(0x3AA8 + s * 2) & 1) == 1
  end
  local function seated(e)
    local mx = H.readWord(MAXHP + e * 2)
    return H.readByte(BCHID + e * 2) ~= 0xFF and mx > 0 and mx < 10000
  end
  local function invCount(id)
    local n = 0
    for i = 0, 251 do
      if H.readByte(BATTINV + i * 5) == id then n = n + H.readByte(BATTINV + i * 5 + 3) end
    end
    return n
  end

  -- the battle key, the way the trench study counts draws: $be at
  -- InitBattle's seed store and the battle group $11E0
  local battleKey = "?"
  emu.addMemoryCallback(function()
    battleKey = string.format("be%02X-g%04X", emu.getState()["cpu.a"] & 0xff, H.readWord(0x11e0))
  end, emu.callbackType.exec, H.seedStoreAddr(), H.seedStoreAddr())

  local function formationHas()
    if RW.species == nil then return true end
    for s = 0, 5 do
      if (H.readByte(0x3AA8 + s * 2) & 1) == 1 then
        local w = H.readWord(H.FORMATION + s * 2)
        for _, sp in ipairs(RW.species) do if w == sp then return true end end
      end
    end
    return false
  end
  local function formationStr()
    local t = {}
    for s = 0, 5 do
      if (H.readByte(0x3AA8 + s * 2) & 1) == 1 then
        t[#t + 1] = string.format("s%d:$%03X:%d", s, H.readWord(H.FORMATION + s * 2),
          H.readWord(MONHP + s * 2))
      end
    end
    return table.concat(t, " ")
  end

  -- ---- the script's memory: a whole-heap rollback ---------------------
  -- The machine snapshot holds the game; the harness's memory (the fight
  -- driver's measurements, the lib's observers, the segment runner, the
  -- host's own step state) lives in Lua.  Restoring only the machine would
  -- hand a branch a driver that remembers another branch's future (the
  -- first cut of this instrument did that: the lib's end-hook record from
  -- branch "own" made every later branch's driver believe its battle had
  -- already ended).  So the Lua side is rolled back with it: every table
  -- and every closure upvalue reachable from the lib's module table
  -- (which reaches the runner, its step tree and so the host's closures)
  -- is recorded shallowly at the decision -- each table's own key/value
  -- pairs, each upvalue's binding -- and a restore puts every one back in
  -- place, so every reference keeps its identity.  The instrument's own
  -- functions (MINE) are not walked, so what it learns survives a restore.
  local MINE = {}
  local function isC(f)
    local info = debug.getinfo(f, "S")
    return info == nil or info.what == "C"
  end
  local function heapSnapshot(roots)
    local tabs, ups, seenU, stack = {}, {}, {}, {}
    local seenF = {}
    local function visit(v)
      local t = type(v)
      if t == "table" then
        if tabs[v] == nil and v ~= _G then tabs[v] = false; stack[#stack + 1] = v end
      elseif t == "function" then
        if not seenF[v] and not MINE[v] then seenF[v] = true; stack[#stack + 1] = v end
      end
    end
    for _, r in ipairs(roots) do visit(r) end
    local nT, nE = 0, 0
    while #stack > 0 do
      local x = stack[#stack]
      stack[#stack] = nil
      if type(x) == "table" then
        local c = {}
        local k, v = next(x)
        while k ~= nil do
          c[k] = v
          nE = nE + 1
          visit(k); visit(v)
          k, v = next(x, k)
        end
        tabs[x] = c
        nT = nT + 1
        local mt = debug.getmetatable(x)
        if mt then visit(mt) end
      elseif not isC(x) then
        local i = 1
        while true do
          local name, val = debug.getupvalue(x, i)
          if name == nil then break end
          if name ~= "_ENV" then
            local id = debug.upvalueid(x, i)
            if not seenU[id] then
              seenU[id] = true
              ups[#ups + 1] = { x, i, val }
              visit(val)
            end
          end
          i = i + 1
        end
      end
    end
    return { tabs = tabs, ups = ups, nT = nT, nE = nE }
  end
  local function heapRestore(h)
    for _, u in ipairs(h.ups) do debug.setupvalue(u[1], u[2], u[3]) end
    local keys = {}
    for T, c in next, h.tabs do
      local n = 0
      local k = next(T)
      while k ~= nil do n = n + 1; keys[n] = k; k = next(T, k) end
      for i = 1, n do rawset(T, keys[i], nil); keys[i] = nil end
      for k2, v in next, c do rawset(T, k2, v) end
    end
  end
  local function copyPlan(p)
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    return c
  end

  -- ---- what the command window offers ------------------------------------
  local describe
  function describe(p)
    if p.rwRace then
      local q = {}
      for k, v in pairs(p) do q[k] = v end
      q.rwRace = nil
      return "race: " .. describe(q)
    end
    if p.kind == "fight" then
      return string.format("Fight bp%d%s", p.boostLeft or 0,
        p.rwTarget and string.format(" -> s%d", p.rwTarget) or " (driver's aim)")
    elseif p.kind == "skill" then
      return string.format("%s $%02X bp%d%s", p.cmd == CMD_BLITZ and "Blitz" or
        string.format("cmd$%02X", p.cmd or 0), p.skill or 0, p.boostLeft or 0,
        p.rwTarget and string.format(" -> s%d", p.rwTarget) or "")
    elseif p.kind == "item" then
      return string.format("Item $%02X -> e%d", p.item or 0, p.target or -1)
    elseif p.spell ~= nil then
      return string.format("%s $%02X%s", p.kind, p.spell, p.target and string.format(" -> e%d", p.target) or "")
    end
    return p.kind
  end
  local function options(D, actor)
    local out = {}
    local bank = H.readByte(BP + actor * 2)
    local top = math.min(bank, 3)
    local boosts = {}
    for b = 0, top do
      if RW.boosts == nil then boosts[#boosts + 1] = b
      else for _, x in ipairs(RW.boosts) do if x == b then boosts[#boosts + 1] = b end end end
    end
    local live = {}
    for s = 0, 5 do if monAlive(s) then live[#live + 1] = s end end
    local fight = cmdRow(actor, CMD_FIGHT)
    if fight then
      for _, s in ipairs(live) do
        for _, b in ipairs(boosts) do
          out[#out + 1] = { kind = "fight", row = fight, boostLeft = b, rwTarget = s }
        end
      end
    end
    local blitz = cmdRow(actor, CMD_BLITZ)
    if blitz and H.readByte(BCHID + actor * 2) == 5 then
      local known = H.readByte(0x1D28)
      local MP = H.sym("MagicProp") & 0x3FFFFF
      for i = 0, 7 do
        if (known >> i) & 1 == 1 then
          local id = 0x5D + i
          local tgt = H.readRomByte(MP + id * 14)
          for _, b in ipairs(boosts) do
            local paid = H.kitBoost(actor, id, b)
            if paid == b then
              if (tgt & 0x10) ~= 0 or (tgt & 0x01) == 0 then
                -- auto-confirm (or no moveable cursor): the engine aims it
                out[#out + 1] = { kind = "skill", cmd = CMD_BLITZ, skill = id, row = blitz, boostLeft = b }
              else
                for _, s in ipairs(live) do
                  out[#out + 1] = { kind = "skill", cmd = CMD_BLITZ, skill = id, row = blitz,
                                    boostLeft = b, rwTarget = s }
                end
              end
            end
          end
        end
      end
    end
    local item = cmdRow(actor, CMD_ITEM)
    if item then
      for _, id in ipairs(CARE_ITEMS) do
        local idx = D:battInvIdx(id)
        if idx ~= nil then
          for e = 0, 3 do
            if seated(e) then
              local hp, mx = H.readWord(HP + e * 2), H.readWord(MAXHP + e * 2)
              if (id == FENIX and hp == 0) or (id ~= FENIX and hp > 0 and hp < mx) then
                out[#out + 1] = { kind = "item", item = id, target = e, row = item, idx = idx }
              end
            end
          end
        end
      end
    end
    if RW.extra then
      local p = RW.extra(D, actor)
      if p then
        local q = {}
        for key, v in pairs(p) do q[key] = v end
        q.rwRace = true
        out[#out + 1] = q
      end
    end
    return out
  end

  -- ---- reading a branch ----------------------------------------------------
  local function reading(D)
    local r = { hp = {}, mp = {}, inv = {}, deaths = #(D.battleDeaths or {}) }
    for e = 0, 3 do
      if seated(e) then r.hp[e] = H.readWord(HP + e * 2); r.mp[e] = H.readWord(CURMP + e * 2) end
    end
    for _, id in ipairs(CARE_ITEMS) do r.inv[id] = invCount(id) end
    return r
  end
  local IP = H.sym("ItemProp") & 0x3FFFFF
  local function score(dec, last, how)
    local s = { how = how, frames = H.frame - dec.frame }
    local hpLost, mpSpent, down, gil = 0, 0, 0, 0
    for e, hp in pairs(dec.r0.hp) do
      local now = last.hp[e] or 0
      hpLost = hpLost + math.max(0, hp - now)
      mpSpent = mpSpent + math.max(0, (dec.r0.mp[e] or 0) - (last.mp[e] or 0))
      if now == 0 then down = down + 1 end
    end
    local spent = {}
    for id, n in pairs(dec.r0.inv) do
      local d = n - (last.inv[id] or 0)
      if d > 0 then
        spent[#spent + 1] = string.format("%02X:%d", id, d)
        gil = gil + d * H.readRomWord(IP + id * 30 + 0x1C)
      end
    end
    table.sort(spent)
    s.deaths, s.down, s.hpLost, s.mpSpent, s.gil = last.deaths - dec.r0.deaths, down, hpLost, mpSpent, gil
    s.items = #spent > 0 and table.concat(spent, ",") or "-"
    local acts = {}
    for _, a in ipairs(dec.acts) do acts[#acts + 1] = a end
    s.acts = #acts > 0 and table.concat(acts, ",") or "-"
    s.actorDied = dec.actorDied
    s.hpEnd = {}
    for e = 0, 3 do if last.hp[e] then s.hpEnd[#s.hpEnd + 1] = tostring(last.hp[e]) end end
    s.sig = string.format("%s f%d hp%s mp%s d%d", how, s.frames, table.concat(s.hpEnd, "/"),
      mpSpent, s.deaths)
    return s
  end

  -- ---- the search ----------------------------------------------------------
  local nDecision = 0
  local cur = nil          -- the decision being searched (nil: plain play)
  local pending = {}       -- decisions whose control waits for this battle's end
  local saveFlag = nil     -- a decision asking for its snapshot this frame
  local outcomesAt = 0

  local function wanted(n)
    if RW.decisions == nil then return true end
    for _, d in ipairs(RW.decisions) do if d == n then return true end end
    return false
  end

  local function hook(D)
    local orig = D.makePlan
    D.makePlan = function(self, actor)
      local care = self.careActor
      local p = orig(self, actor)
      if cur ~= nil or saveFlag ~= nil then return p end
      if H.readByte(BCHID + actor * 2) ~= RW.char or not formationHas() then return p end
      nDecision = nDecision + 1
      if not wanted(nDecision) or (RW.when ~= nil and not RW.when(self, actor, p)) then
        log("D%d f%d key %s actor %d: %s (not searched)", nDecision, H.frame, battleKey,
          actor, describe(p))
        return p
      end
      saveFlag = { n = nDecision, D = self, actor = actor, own = copyPlan(p), care = care }
      return p
    end
    local origFocus = D.focusList
    D.focusList = function(self)
      if self.plan and self.plan.rwTarget then
        return { { slot = self.plan.rwTarget, mask = 1 << self.plan.rwTarget } }
      end
      return origFocus(self)
    end
    local origDrop = D.dropPlan
    D.dropPlan = function(self, reason)
      if cur and self.plan and self.plan.rwForced and not self.plan.rwSaid
         and reason ~= "confirm_attempt" then
        self.plan.rwSaid = true
        cur.dropped = reason
        log("D%d branch %d: the swapped plan was dropped before its confirm (%s); "
          .. "the driver re-planned", cur.n, cur.k, tostring(reason))
      end
      return origDrop(self, reason)
    end
    MINE[D.makePlan], MINE[D.focusList], MINE[D.dropPlan] = true, true, true
  end
  local origNew = H.newFightDriver
  H.newFightDriver = function(tag, opts)
    local F = origNew(tag, opts)
    hook(F.driver)
    return F
  end
  MINE[H.newFightDriver] = true

  local function startBranch(dec, k)
    local plan = dec.branches[k]
    dec.k, dec.acts, dec.actorDied, dec.dropped, dec.lastMon = k, {}, false, nil, nil
    dec.last = dec.r0
    if k == 0 then return end  -- branch "own": the live continuation
    heapRestore(dec.heap)
    local req = H.requestLoadState(dec.blob)
    local D = dec.D
    local p = copyPlan(plan)
    p.rwForced = true
    D.plan, D.planActor, D.tgtSpin = p, dec.actor, 0
    D.planPulses, D.steerTrail = 0, {}
    D.careActor = (p.kind == "heal" or p.kind == "item") and dec.actor or dec.care
    dec.req = req
  end

  local function finishBranch(dec, how)
    local s = score(dec, dec.last, how)
    dec.results[dec.k] = s
    local plan = dec.k == 0 and dec.own or dec.branches[dec.k]
    log("D%d branch %d/%d %s%s: %s deaths=%d down=%d actorDied=%s hpLost=%d mpSpent=%d "
      .. "items=%s gil=%d frames=%d monacts=%s%s", dec.n, dec.k, #dec.branches,
      dec.k == 0 and "own " or "", describe(plan), how, s.deaths, s.down,
      tostring(s.actorDied), s.hpLost, s.mpSpent, s.items, s.gil, s.frames, s.acts,
      dec.dropped and (" DROPPED(" .. dec.dropped .. ")") or "")
  end

  local function nextOrResume(dec)
    if dec.k < #dec.branches then
      startBranch(dec, dec.k + 1)
      return
    end
    -- every branch played: restore and let the driver's own plan go on as
    -- the run; its end is checked against branch "own"
    heapRestore(dec.heap)
    dec.req = H.requestLoadState(dec.blob)
    dec.k, dec.acts, dec.actorDied, dec.last, dec.lastMon = "control", {}, false, dec.r0, nil
    pending[#pending + 1] = dec
    cur = nil
    log("D%d: all %d branches played; restored, the driver's own plan continues as the run",
      dec.n, #dec.branches)
  end

  local function after()
    -- 1. a decision asked for its snapshot this frame
    if saveFlag ~= nil then
      local f = saveFlag
      saveFlag = nil
      local D = f.D
      local dec = { n = f.n, D = D, actor = f.actor, own = f.own, care = f.care,
                    frame = H.frame, key = battleKey, outcomes = #H.outcomes,
                    lastOutcome = H.lastOutcome, results = {} }
      dec.heap = heapSnapshot({ H })
      dec.req = H.requestSaveState()
      dec.r0 = reading(D)
      dec.branches = options(D, f.actor)
      local hp, mp = {}, {}
      for e = 0, 3 do if dec.r0.hp[e] then hp[#hp + 1] = dec.r0.hp[e]; mp[#mp + 1] = dec.r0.mp[e] end end
      log("D%d f%d key %s form %s actor %d char %d bank %d hp %s mp %s: own plan %s; "
        .. "%d branches", dec.n, dec.frame, dec.key, formationStr(), dec.actor, RW.char,
        H.readByte(BP + dec.actor * 2), table.concat(hp, "/"), table.concat(mp, "/"),
        describe(dec.own), #dec.branches)
      log("D%d: snapshot requested; the script's memory recorded (%d tables, %d entries, "
        .. "%d upvalues)", dec.n, dec.heap.nT, dec.heap.nE, #dec.heap.ups)
      for k, b in ipairs(dec.branches) do log("D%d option %d: %s", dec.n, k, describe(b)) end
      cur = dec
      startBranch(dec, 0)
      return
    end
    local dec = cur
    -- while a decision is being searched only its branch is watched; the
    -- decisions waiting on this battle's end watch the run itself
    local watch = {}
    if dec then watch[1] = dec else for _, p in ipairs(pending) do watch[#watch + 1] = p end end
    if #watch == 0 then return end
    -- 2. collect the snapshot blob once the trampoline has fired
    if dec and dec.blob == nil and dec.req and dec.req.done then
      H.checkReq(dec.req, "rewind snapshot D" .. dec.n)
      dec.blob = dec.req.blob
    end
    -- 3. watch the fight: monster actions, the actor's death, the last
    --    in-battle reading
    local inBattle = H.battleLoadStarted()
    for _, d in ipairs(watch) do
      local D = d.D
      -- an action is known by its slot, tick and attack (a restore hands
      -- the driver a copy of the open one, which is not a new action)
      local m = D.monAct
      local mk = m and string.format("%s:%s:%s", tostring(m.slot), tostring(m.tick), tostring(m.atk))
      if mk ~= nil and mk ~= d.lastMon then
        d.lastMon = mk
        d.acts[#d.acts + 1] = string.format("s%d:$%02X", D.monAct.slot or -1, D.monAct.atk or 0)
      end
      if inBattle then
        d.last = reading(D)
        if (d.last.hp[d.actor] or 1) == 0 then d.actorDied = true end
      end
    end
    -- 4. a fight's end: its outcome record, or a wipe
    local how = nil
    if #H.outcomes > (dec and dec.outcomes or pending[1].outcomes) then
      how = H.outcomes[#H.outcomes].kind or "over"
    elseif H.partyWipedInBattle() then
      how = "wiped"
    end
    if dec then
      if how == nil and H.frame - dec.frame >= RW.capFrames then how = "open" end
      if how ~= nil then
        if dec.k ~= 0 and dec.blob == nil then error("rewind: snapshot never captured", 0) end
        finishBranch(dec, how)
        nextOrResume(dec)
      end
      return
    end
    if how ~= nil then
      for _, d in ipairs(pending) do
        local s = score(d, d.last, how)
        local own = d.results[0]
        log("D%d control: the run's continuation ended %s; branch own ended %s -- %s",
          d.n, s.sig, own.sig, s.sig == own.sig and "MATCH" or "MISMATCH")
      end
      pending = {}
    end
  end

  -- runs after the segment runner's own frame (registered from inside the
  -- first frame, so it sits behind the runner's callback)
  local armed = false
  emu.addEventCallback(function()
    if armed then return end
    armed = true
    emu.addEventCallback(function()
      local ok, err = pcall(after)
      if not ok then
        H.log("FAIL: rewind_search: " .. tostring(err))
        emu.stop(1)
      end
    end, emu.eventType.startFrame)
  end, emu.eventType.startFrame)
  log("armed: char %d, species %s, decisions %s, cap %d frames", RW.char,
    RW.species and table.concat((function() local t = {} for _, s in ipairs(RW.species) do
      t[#t + 1] = string.format("$%03X", s) end return t end)(), ",") or "any",
    RW.decisions and table.concat(RW.decisions, ",") or "all", RW.capFrames)
end
