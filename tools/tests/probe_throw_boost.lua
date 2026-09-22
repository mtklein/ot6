-- @manual
-- probe_throw_boost.lua -- does a boosted Throw multiply?  (v0.21 release
-- question about 468b08ae / #237)
--
-- Ot6BoostDmg skips its x2/x4/x8 for a "tier-folded spell".  Up to v0.20 the
-- test was "is the queued attack byte $3a7d in Ot6FoldTbl"; since 468b08ae it
-- is "is the command one of the four fold commands AND is $b6 in Ot6FoldTbl".
-- Under Throw ($08), $3a7d is the thrown item's id, and item ids $00-$0b,
-- $19, $1f, $27, $28, $2d-$31 are also spell ids in Ot6FoldTbl, so a boosted
-- Throw of e.g. a Dirk ($00 = Fire) or a MithrilKnife ($01 = Ice) skipped the
-- multiplier on the old test.  This probe measures it on whatever ROM it runs
-- on (OT6_ROM / OT6_DBG pick the ROM and its symbols).
--
-- Fixtures, both route states with SHADOW in the party and the throwables
-- already in the bag, so nothing is written: MithrilKnife ($01) and Dirk
-- ($00) collide with Ot6FoldTbl; Shuriken ($41) does not and is the control.
--   crescent_landing  TERRA / LOCKE / SHADOW (L22), WoB world map
--   fc_alcove         TERRA / LOCKE / SHADOW (L25) / EDGAR, Floating
--                     Continent: sturdier monsters, so a boosted hit is less
--                     likely to be capped by the target's remaining HP
-- Each: walk to a random encounter, everyone Defends until Shadow's bank holds
-- BOOST pips, snapshot Shadow's command window, and from that one snapshot
-- throw each case through the real menus: R presses at the command window,
-- Throw, the item row, the default target.  Observed, never written:
-- Ot6BoostDmg's entry and its two return sites ($11b0 in and out, $b5/$b6/
-- $3a7c/$3a7d, pending and bank), the damage numeral each monster is dealt
-- ($33d0,y), and each monster's HP before the throw and after it settles.

local H = dofile("tools/tests/lib/ot6.lua")
local FIXTURES = {
  { path = "build/states/crescent_landing.mss.lua" },
  -- the alcove draws no encounters: leave by its exit, 358 (8,8) north of
  -- the SavePoint, onto the continent (394), as gen_fc_escape does
  { path = "build/states/fc_alcove.mss.lua", leave = function()
      return {
        H.navTo(8, 9, { maxFrames = 3000 }),
        H.driveUntil(function() return (H.mapId() & 0x3FF) == 394 end, 1800, {
          H.call(function()
            if not H.hasControl() then H.setPad({}) return end
            H.setPad({ up = true })
          end),
        }, "alcove -> 394"),
        H.release(),
        H.waitUntil(function() return H.hasControl() and H.tileAligned() end, 900,
          "control on 394", 10),
      }
    end },
}

local SHADOW = 3
local BOOST = 3
-- boost 1 as well as 3: x2 leaves an FC monster standing, so the HP it
-- loses is not capped by what it had left
local CASES = {}
for _, it in ipairs({ { 0x01, "MithrilKnife" }, { 0x00, "Dirk" }, { 0x41, "Shuriken" } }) do
  for _, b in ipairs({ 0, 1, BOOST }) do
    CASES[#CASES + 1] = { item = it[1], name = it[2], boost = b }
  end
end

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local CMDTBL, CMDROW, BCHID = 0x202E, 0x890F, 0x3ED8
local ST_CMD, ST_DEF, ST_THROW, ST_TGT = 0x05, 0x27, 0x2D, 0x38
local ITEMLIST, BATTINV = 0x4005, 0x2686
-- the Throw list is one column (UpdateMenuState_2d, LANG_EN): the cursor's
-- row is scroll $8953,slot + in-window row $895B,slot (get_throw_poi)
local THROW_SCROLL, THROW_ROW = 0x8953, 0x895B
local BANK, PEND = 0x3E9C, 0x3E9D            -- OT6_BP_CLASS / OT6_BOOST_REVEALED
local MON_HP, TGTMONS, DMG_TAKEN = 0x3BFC, 0x7B7E, 0x33D0
local CMD_THROW = 0x08

local fixture                                -- the state's basename
local slot                                   -- Shadow's battle slot (0-3)
local snap                                   -- the savestate request at his window
local armed = nil                            -- the case being measured
local results = {}

local function ent() return slot * 2 end
-- in battle the bag is the battle inventory: 5-byte rows, id +0, count +3
local function battleCount(id)
  for i = 0, 255 do
    if H.readByte(BATTINV + i * 5) == id then return H.readByte(BATTINV + i * 5 + 3) end
  end
  return 0
end
local function fieldCount(id)
  for s = 0, 255 do
    if H.readByte(0x1869 + s) == id then return H.readByte(0x1969 + s) end
  end
  return 0
end
local function monHps()
  local t = {}
  for s = 0, 5 do t[s] = H.readWord(MON_HP + s * 2) end
  return t
end
local function cmdRow(actor, cmd)
  for r = 0, 3 do
    if H.readByte(CMDTBL + actor * 12 + r * 3) == cmd then return r end
  end
end
local function throwCall(c)
  for _, k in ipairs(c.calls) do
    if k.x == ent() and k.b5 == CMD_THROW then return k end
  end
end

-- which tier test this ROM's Ot6BoostDmg carries: `cmp $3a7d` (CD 7D 3A,
-- v0.20) or `cmp $b6` (C5 B6, since 468b08ae)
local function procVariant()
  local base = H.sym("Ot6BoostDmg") & 0x3FFFFF
  local hex, seen = {}, {}
  for i = 0, 159 do
    local b = H.readRomByte(base + i)
    hex[#hex + 1] = string.format("%02X", b)
    local b1, b2 = H.readRomByte(base + i + 1), H.readRomByte(base + i + 2)
    if b == 0xCD and b1 == 0x7D and b2 == 0x3A then seen.a7d = i end
    if b == 0xC5 and b1 == 0xB6 then seen.b6 = i end
  end
  return seen, table.concat(hex, " ")
end

local installed = false
local function installObservers()
  if installed then return end
  installed = true
  local bd = H.sym("Ot6BoostDmg")
  local b0, b1, b2 = bd & 0xFF, (bd >> 8) & 0xFF, (bd >> 16) & 0xFF
  local sites = {}
  for off = 0x020000, 0x02FFFC do
    if H.readRomByte(off) == 0x22 and H.readRomByte(off + 1) == b0
       and H.readRomByte(off + 2) == b1 and H.readRomByte(off + 3) == b2 then
      sites[#sites + 1] = 0xC00000 + off + 4
    end
  end
  H.assertEq(#sites, 2, "Ot6BoostDmg has two call sites in bank $C2")
  local seen, hex = procVariant()
  H.log(string.format("[rom] Ot6BoostDmg at $%06X, returns to $%06X/$%06X; "
    .. "tier test: %s", bd, sites[1], sites[2],
    seen.a7d and string.format("cmp $3a7d at +%d (v0.20 shape)", seen.a7d)
    or seen.b6 and string.format("cmp $b6 at +%d (468b08ae shape)", seen.b6)
    or "NEITHER"))
  H.log("[rom] Ot6BoostDmg bytes: " .. hex)

  emu.addMemoryCallback(function()
    if armed == nil then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    armed.calls[#armed.calls + 1] = {
      x = x, b5 = H.readByte(0xB5), b6 = H.readByte(0xB6),
      a7c = H.readByte(0x3A7C), a7d = H.readByte(0x3A7D), b1 = H.readByte(0xB1),
      pend = x < 8 and H.readByte(PEND + x) or -1,
      bank = x < 8 and H.readByte(BANK + x) or -1,
      din = H.readWord(0x11B0), hp = monHps() }
  end, emu.callbackType.exec, bd, bd)
  for _, ret in ipairs(sites) do
    emu.addMemoryCallback(function()
      if armed == nil or #armed.calls == 0 then return end
      local c = armed.calls[#armed.calls]
      if c.dout == nil then c.dout = H.readWord(0x11B0) end
    end, emu.callbackType.exec, ret, ret)
  end
  -- the numeral: $33d0,y is stored low byte then high, and the callback
  -- sees each byte's value before it lands, so the word is assembled from
  -- the two written values.  Only while Shadow's throw is the action (its
  -- Ot6BoostDmg call seen, its Ot6ActionEnd not yet).
  local lowByte = {}
  emu.addMemoryCallback(function(addr, v)
    if armed == nil or armed.endF or throwCall(armed) == nil then return end
    local off = (addr & 0xFFFF) - DMG_TAKEN - 8
    local s = off // 2
    if (off & 1) == 0 then lowByte[s] = v return end
    local w = (lowByte[s] or 0) | (v << 8)
    if w ~= 0xFFFF then armed.numeral[s] = w end
  end, emu.callbackType.write, 0x7E0000 + DMG_TAKEN + 8, 0x7E0000 + DMG_TAKEN + 19)
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if armed == nil or armed.endF then return end
    local x = emu.getState()["cpu.x"] & 0xFFFF
    if x == ent() and throwCall(armed) then
      armed.endF = H.frame
      armed.endPend, armed.endBank = H.readByte(PEND + x), H.readByte(BANK + x)
    end
  end, emu.callbackType.exec, ae, ae)
end

-- one button per 12-frame pulse, 6 on / 6 off
local tick = 0
local function pulse(btn)
  tick = tick + 1
  local ph = tick % 12
  H.setPad((btn and ph < 6) and { [btn] = true } or {})
end

-- everyone but the measured actor Defends: RIGHT opens Def., A commits it
local function defendOthers(except)
  local st = H.readByte(MSTATE)
  if H.readByte(MENU) == 0 then pulse(nil) return end
  local a = H.readByte(ACTOR) & 3
  if a == except then pulse(nil) return end
  if st == ST_CMD then pulse("right")
  elseif st == ST_DEF then pulse("a")
  else pulse(nil) end
end

-- pace a lane until an encounter: on the world map turn back every 24
-- frames (rotate when blocked); on a field map pace between the start tile
-- and its first open neighbour
local function walkToEncounter()
  local dirs = { "left", "right", "up", "down" }
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  local di, lastPos, held, lane = 1, nil, 0, nil
  return H.driveUntil(function() return H.battleLoadStarted() end, 30000, {
    H.call(function()
      if H.worldMode() then
        if not H.worldHasControl() then H.setPad({}) return end
        held = held + 1
        local pos = H.worldX() * 256 + H.worldY()
        if held >= 24 then
          if pos == lastPos then di = di % 4 + 1
          else di = (di % 2 == 1) and di + 1 or di - 1 end
          lastPos, held = pos, 0
        end
        H.setPad({ [dirs[di]] = true })
        return
      end
      if not (H.hasControl() and H.tileAligned()) then H.setPad({}) return end
      local x, y = H.fieldX(), H.fieldY()
      if lane == nil then
        for _, d in ipairs(dirs) do
          if H.canStep(x, y, d) then lane = { ax = x, ay = y, out = d, back = BACK[d] } break end
        end
        if lane == nil then H.setPad({}) return end
      end
      H.setPad({ [(x == lane.ax and y == lane.ay) and lane.out or lane.back] = true })
    end),
  }, "a random encounter")
end

local phase, held = "idle", nil

-- the next button for this case's menu walk, or nil to wait
local function decide(c)
  local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
  if phase == "boost" then
    if st ~= ST_CMD or a ~= slot then return nil end
    if H.readByte(PEND + ent()) < c.boost then return "r" end
    phase = "cmd"
  end
  if phase == "cmd" then
    if st ~= ST_CMD then return nil end
    local want = cmdRow(slot, CMD_THROW)
    assert(want, "Shadow has a Throw row")
    local cur = H.readByte(CMDROW + slot) & 3
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "list"
    return "a"
  end
  if phase == "list" then
    if st == ST_CMD then return "a" end            -- the A was not taken
    if st ~= ST_THROW then return nil end
    local want
    for i = 0, 63 do
      local id = H.readByte(ITEMLIST + i * 3)
      if id == c.item then want = i break end
      if id == 0xFF then break end
    end
    assert(want, string.format("item $%02X is in the Throw list", c.item))
    local cur = H.readByte(THROW_SCROLL + slot) + H.readByte(THROW_ROW + slot)
    if cur ~= want then return cur < want and "down" or "up" end
    phase = "target"
    return "a"
  end
  if phase == "target" then
    if st == ST_THROW then return "a" end          -- the A was not taken
    if st ~= ST_TGT then return nil end
    c.tgt = H.readByte(TGTMONS)
    assert(c.tgt ~= 0, "the target cursor is on a monster")
    c.pendAtConfirm = H.readByte(PEND + ent())
    armed = c
    phase = "confirmed"
    return "a"
  end
  return nil
end

local function report(c)
  for _, k in ipairs(c.calls) do
    H.log(string.format("[call] %s %s b%d: x=$%02X b5=$%02X b6=$%02X 3a7c=$%02X "
      .. "3a7d=$%02X b1=$%02X pending=%d bank=%d dmg %d -> %s", fixture,
      c.name, c.boost, k.x, k.b5, k.b6, k.a7c, k.a7d, k.b1, k.pend, k.bank,
      k.din, tostring(k.dout)))
  end
  local first = throwCall(c)
  local hit = {}
  for s = 0, 5 do
    local h0 = first and first.hp[s] or 0
    if c.numeral[s] or h0 ~= c.hp1[s] then
      hit[#hit + 1] = string.format("slot%d numeral %s, HP %d->%d (lost %d)", s,
        tostring(c.numeral[s]), h0, c.hp1[s], h0 - c.hp1[s])
    end
  end
  H.log(string.format("[throw] %s %s($%02X) boost=%d: pending at confirm %d, "
    .. "Ot6BoostDmg %s, target mask $%02X, %s, battle bag %d->%d, "
    .. "ActionEnd pending=%s bank=%s", fixture,
    c.name, c.item, c.boost, c.pendAtConfirm,
    first and string.format("dmg %d -> %s (b5=$%02X 3a7d=$%02X b6=$%02X)",
      first.din, tostring(first.dout), first.b5, first.a7d, first.b6) or "NOT REACHED",
    c.tgt or 0, #hit > 0 and table.concat(hit, "; ") or "no monster hit",
    c.bag0, c.bag1, tostring(c.endPend), tostring(c.endBank)))
end

-- one case, from the snapshot: boost, Throw, the item, the default target
local function runCase(c)
  local req
  return {
    H.call(function()
      H.setPad({})
      req = H.requestLoadState(snap.blob)
    end),
    H.waitFrames(2),
    H.call(function()
      H.checkReq(req, "snapshot load")
      H.rearmInputInjection()
      tick = 0
      H.assertEq(H.readByte(ACTOR) & 3, slot, "the snapshot is at Shadow's window")
      c.fixture, c.bag0, c.calls, c.numeral = fixture, battleCount(c.item), {}, {}
      phase, held = "boost", nil
    end),
    H.driveUntil(function() return phase == "sent" end, 3000, {
      H.call(function()
        -- a button is chosen at the head of each 12-frame pulse, held 6
        -- frames and released 6, so every press is a fresh edge
        tick = tick + 1
        local ph = tick % 12
        if ph == 0 then held = decide(c) end
        if phase == "confirmed" and ph == 11 then phase = "sent" end
        H.setPad((held and ph < 6) and { [held] = true } or {})
      end),
    }, "Throw " .. c.name .. " at boost " .. c.boost),
    H.driveUntil(function() return c.endF ~= nil and H.frame >= c.endF + 150 end, 6000, {
      H.call(function() defendOthers(slot) end),
    }, "the throw resolves"),
    H.call(function()
      armed = nil
      H.setPad({})
      c.hp1 = monHps()
      c.bag1 = battleCount(c.item)
      results[#results + 1] = c
      report(c)
    end),
  }
end

local steps = { H.waitFrames(20) }
local function add(s) steps[#steps + 1] = s end
for _, fx in ipairs(FIXTURES) do
  add(H.call(function()
    snap, slot, armed = nil, nil, nil
    fixture = fx.path:match("([^/]+)%.mss%.lua$")
  end))
  add(H.loadState(fx.path))
  add(H.waitFrames(20))
  add(H.call(function()
    installObservers()
    H.log(string.format("[bag] %s: MithrilKnife x%d, Dirk x%d, Shuriken x%d",
      fixture, fieldCount(0x01), fieldCount(0x00), fieldCount(0x41)))
  end))
  if fx.leave then for _, s in ipairs(fx.leave()) do add(s) end end
  add(walkToEncounter())
  add(H.release())
  add(H.waitUntil(function() return H.battleActive() end, 900, "battle up", 5))
  add(H.call(function()
    for s = 0, 3 do
      if H.readByte(BCHID + s * 2) == SHADOW then slot = s end
    end
    assert(slot, "Shadow is in the battle")
    local f, hp = {}, {}
    for _, w in ipairs(H.formationWords()) do f[#f + 1] = string.format("%04X", w) end
    for s = 0, 5 do hp[#hp + 1] = tostring(H.readWord(MON_HP + s * 2)) end
    H.log(string.format("[battle] %s: Shadow in slot %d; formation %s; monster HP %s",
      fixture, slot, table.concat(f, " "), table.concat(hp, " ")))
  end))
  -- everyone Defends (Shadow too) until his window opens with BOOST pips
  add(H.driveUntil(function() return snap ~= nil end, 30000, {
    H.call(function()
      local st, a = H.readByte(MSTATE), H.readByte(ACTOR) & 3
      if H.readByte(MENU) ~= 0 and st == ST_CMD and a == slot
         and H.readByte(BANK + ent()) >= BOOST and H.readByte(PEND + ent()) == 0 then
        H.setPad({})
        snap = H.requestSaveState()
        return
      end
      defendOthers(-1)
    end),
  }, "Shadow's window with " .. BOOST .. " pips banked"))
  add(H.waitFrames(2))
  add(H.call(function()
    H.checkReq(snap, "snapshot at Shadow's window")
    H.log(string.format("[snap] %s f%d Shadow's window: bank %d, pending %d, monster HP %s",
      fixture, H.frame, H.readByte(BANK + ent()), H.readByte(PEND + ent()),
      (function()
        local t = {}
        for s = 0, 5 do t[#t + 1] = tostring(H.readWord(MON_HP + s * 2)) end
        return table.concat(t, " ")
      end)()))
  end))
  for _, proto in ipairs(CASES) do
    for _, s in ipairs(runCase({ item = proto.item, name = proto.name, boost = proto.boost })) do
      add(s)
    end
  end
end
add(H.call(function()
  for _, c in ipairs(results) do
    local first = nil
    for _, k in ipairs(c.calls) do
      if k.b5 == CMD_THROW and k.x < 8 then first = k break end
    end
    local num = {}
    for s = 0, 5 do if c.numeral[s] then num[#num + 1] = string.format("slot%d %d", s, c.numeral[s]) end end
    H.log(string.format("[summary] %-16s %-12s $%02X boost %d: Ot6BoostDmg %s; numeral %s",
      c.fixture, c.name, c.item, c.boost,
      first and string.format("%d -> %s (x%s)", first.din, tostring(first.dout),
        first.din > 0 and first.dout and string.format("%.2f", first.dout / first.din) or "?")
      or "no Throw damage call",
      #num > 0 and table.concat(num, ", ") or "none"))
  end
end))

H.run({ maxFrames = 200000 }, steps)
