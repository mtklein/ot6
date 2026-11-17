-- @suite slow
-- battle_limitbreak.lua -- Bahamut's signature, Limit Break (#550; docs/design/esper-rework.md "Limit Break";
-- ot6_esper.asm Ot6DmgCap, ot6_numeral.asm): the holder's damage caps at 42,069 instead of 9999, everyone else's
-- and every heal stay at 9999, and the damage numerals draw every value up to the cap, five digits looking like four.
--
-- Continue wor-ragnarok-v1 (the play's save outside Narshe; one member wears Ragnarok, so can cast Ultima: H below).
-- A snapshot on the world map; then one branch per case from it, each staging H's count on Bahamut (the live esper
-- page, SRAM $317C00: 500, the signature, or 499, one short) and walking into a random battle (the same one every
-- branch: the same snapshot, the same steps), where every present monster's HP and max HP are staged to 60,000 (so a
-- hit lands whole in HP rather than past it), and H casts Ultima at 2 BP through the real menu while the others
-- Defend.  Ultima from Ragnarok's list takes the boost's multiplier (battle_ragnarok): x4 at 2 BP, about 11,600 a
-- monster at this save's levels (at 3 BP this save's cast landed on nobody: build/attempts/wt/v049-limitbreak/);
-- the precondition, asserted per hit, is that the amount reaching the cap is past 9999.  The staging (the
-- count, the HP; the synthetic arms' bytes below) is declared in state_write_waivers.txt: a mechanism test, not play.
--   holder      count 500: each monster's total is the amount (or 42,069), its HP falls by exactly that, and its
--               numeral (single-target: one to four monsters) carries that value and draws its digits: the thread's
--               VRAM tiles are the digit glyphs, and its sprites are A, B and (five digits) C at +16 and +24
--   other       count 499: each total is 9999 and the HP falls by 9999; four digits, two sprites
--   multi       count 500, and at the pass's display (_c262ef) each seated member gets a heal entry (2345, 9999, 88,
--               1): five or more numerals, so the multi-target path draws them: each monster's five digits (its four
--               slots and the ten-thousands digit's glyph-row sprite), each member's heal in green
--   doubling    count 500; the first present monster is marked Broken (OT6_BROKEN_TICKS) and its amount set to
--               33,333 where Ot6BrokenDmg doubles it; the second (or the first again, from a fresh restore) is made
--               weak to the spell's element and its amount set to 33,333 where Ot6WeakDouble doubles it: each total
--               must be 42,069 (x2 saturates and the cap takes it; vanilla's skip left 33,333)
--   heal        count 500; the first monster's pass is turned to the heal side ($F2 bit 0 at CalcMaxDmg): a holder's
--               heal of ~23,000 caps at 9999
-- Screenshots (3x for the report) of the holder's four single numerals and of the multi numerals.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local RAGNAROK, BAHAMUT_SLOT = 16, 12
local CMD_MAGIC, ULTIMA = 0x02, 0x14
local LIVE = 0x317C00
local LIMIT, STD = 42069, 9999
local HP = 60000
local HEAL, MISS = 0xC000, 0xF000
local function hex(v) return string.format("$%02X", v) end
local function rom(a) return emu.read(a & 0x3FFFFF, emu.memType.snesPrgRom) end
local function vram(w) return emu.readWord(w * 2, emu.memType.snesVideoRam) end
local function wram7f(a) return emu.read(0x7F0000 + a, emu.memType.snesMemory) end
local function stageCount(who, n)
  local a = LIVE + 0x10 + (who * 26 + BAHAMUT_SLOT) * 2
  emu.write(a, n & 0xFF, emu.memType.snesMemory)
  emu.write(a + 1, n >> 8, emu.memType.snesMemory)
end

local who, seat                         -- H (Ragnarok's wearer) and its battle slot
local snap, A0, B0, A, B
local cur                               -- the case being recorded
local inj                               -- the synthetic arm's injection, per case

-- the single numeral layout (ot6_numeral.asm): per thread the A pair's and the B triple's first tile
local TILE_A = { [0] = 0xC0, 0xC5, 0xEC, 0xEE }
local TILE_B = { [0] = 0xC2, 0xC7, 0xCA, 0xCD }
local TILE_C = { [0] = 0xC3, 0xC8, 0xCB, 0xCE }
local function tileWord(t) return 0x2000 + t * 16 end
-- slot i's tile for thread k: slots 0-1 the A pair, 2-4 the B triple
local function slotTile(k, i) if i < 2 then return TILE_A[k] + i end return TILE_B[k] + i - 2 end
-- the glyph for digit d, from the battle's decompressed status graphics ($7F:BC40, 32 bytes a digit)
local function glyphIs(w, d)
  for b = 0, 15 do
    local g = wram7f(0xBC40 + d * 32 + b * 2) | (wram7f(0xBC40 + d * 32 + b * 2 + 1) << 8)
    if vram(w + b) ~= g then return false end
  end
  return true
end
local function blankIs(w)
  for b = 0, 15 do if vram(w + b) ~= 0 then return false end end
  return true
end
local function digits(v)
  local s = tostring(v)
  local t = {}
  for i = 1, #s do t[i] = tonumber(s:sub(i, i)) end
  return t
end

-- the OAM buffer as the battle NMI found it last (the frame's sprites, complete), and the entries (y < $E0) on a
-- tile, with x (9 bits, signed: past 255 wraps to the left edge) and attribute
local OAM = nil
local function oamSnap()
  local t = {}
  for i = 0, 0x21F do t[i] = H.readByte(0x0300 + i) end
  OAM = t
end
local function oamOn(tile)
  local out = {}
  if not OAM then return out end
  for e = 0, 127 do
    local o = e * 4
    if OAM[o + 1] < 0xE0 and OAM[o + 2] == tile and (OAM[o + 3] & 1) == 0 then
      local hi = (OAM[0x200 + (e >> 2)] >> ((e & 3) * 2)) & 1
      local x = OAM[o] + hi * 256
      if x >= 256 then x = x - 512 end
      out[#out + 1] = { e = e, x = x, y = OAM[o + 1], a = OAM[o + 3] }
    end
  end
  return out
end

local function arm()
  local CAP = H.sym("Ot6DmgCap")
  -- the store after Ot6DmgCap: CalcMaxDmg's `jsl Ot6DmgCap / bra / .res 7 / sta $33d0,y`, found by its bytes
  local maxd = H.sym("CalcMaxDmg") & 0x3FFFFF
  local store
  for o = 0, 0x80 do
    if rom(maxd + o) == 0x22 and rom(maxd + o + 1) == (CAP & 0xFF) and rom(maxd + o + 2) == ((CAP >> 8) & 0xFF)
       and rom(maxd + o + 3) == (CAP >> 16) then store = (H.sym("CalcMaxDmg") & 0xFF0000) | ((maxd + o + 13) & 0xFFFF) end
  end
  H.assertEq(store ~= nil and rom(store) == 0x99, true, "CalcMaxDmg's jsl Ot6DmgCap, and its sta $33d0,y 13 bytes on")
  local pendCap = nil
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local s = emu.getState()
    local x, y = s["cpu.x"] & 0xFF, s["cpu.y"] & 0xFF
    pendCap = { x = x, y = y, pre = (s["cpu.a"] & 0xFFFF) + H.readWord(0xF0) }
  end, emu.callbackType.exec, CAP, CAP)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not pendCap then return end
    local s = emu.getState()
    local p = pendCap
    pendCap = nil
    p.total = s["cpu.a"] & 0xFFFF
    if p.x ~= seat * 2 then return end
    cur.caps[#cur.caps + 1] = p
  end, emu.callbackType.exec, store, store)
  -- the synthetic arms
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.broken then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.broken then emu.write(0x7E00F0, 33333 & 0xFF, emu.memType.snesMemory)
      emu.write(0x7E00F1, 33333 >> 8, emu.memType.snesMemory); inj.brokenHit = true end
  end, emu.callbackType.exec, H.sym("Ot6BrokenDmg"), H.sym("Ot6BrokenDmg"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.weak then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.weak then emu.write(0x7E00F0, 33333 & 0xFF, emu.memType.snesMemory)
      emu.write(0x7E00F1, 33333 >> 8, emu.memType.snesMemory); inj.weakHit = true end
  end, emu.callbackType.exec, H.sym("Ot6WeakDouble"), H.sym("Ot6WeakDouble"))
  -- the weak arm: the spell's element and the target's weakness, at the pass's start (CalcTargetDmg)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if inj.weak and y == inj.weak then
      inj.elem = inj.elem or H.readByte(0x11A1)
      emu.write(0x7E11A1, 0x01, emu.memType.snesMemory)
      emu.write(0x7E3BE0 + y, H.readByte(0x3BE0 + y) | 0x01, emu.memType.snesMemory)
      emu.write(0x7E3BCC + y, H.readByte(0x3BCC + y) & 0xFE, emu.memType.snesMemory)
      emu.write(0x7E3BCD + y, H.readByte(0x3BCD + y) & 0xFE, emu.memType.snesMemory)
    elseif inj.elem then
      emu.write(0x7E11A1, inj.elem, emu.memType.snesMemory)
    end
  end, emu.callbackType.exec, H.sym("CalcTargetDmg"), H.sym("CalcTargetDmg"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.heal then return end
    local y = emu.getState()["cpu.y"] & 0xFF
    if y == inj.heal then emu.write(0x7E00F2, H.readByte(0xF2) | 0x01, emu.memType.snesMemory); inj.healHit = true end
  end, emu.callbackType.exec, H.sym("CalcMaxDmg"), H.sym("CalcMaxDmg"))
  -- the multi arm: heal entries for the seated members, at the display of H's pass
  emu.addMemoryCallback(function()
    if not cur or not cur.live or not inj or not inj.multi or inj.multiDone then return end
    if #cur.caps == 0 then return end
    local hv = { 2345, 9999, 88, 1 }
    for s = 0, 3 do
      if H.readByte(0x3ED8 + s * 2) ~= 0xFF then
        emu.write(0x7E33E4 + s * 2, hv[s + 1] & 0xFF, emu.memType.snesMemory)
        emu.write(0x7E33E5 + s * 2, hv[s + 1] >> 8, emu.memType.snesMemory)
        inj.heals[s * 2] = hv[s + 1]
      end
    end
    inj.multiDone = true
  end, emu.callbackType.exec, H.sym("_c262ef"), H.sym("_c262ef"))
  -- the single numerals: the value each command carries, then its tiles and sprites once drawn
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local p = H.readWord(0x76)
    local n = { tgt = H.readByte(p + 1), v = H.readWord(p + 2), k = H.readByte(0x632E) & 3, f = H.frame }
    cur.nums[#cur.nums + 1] = n
  end, emu.callbackType.exec, H.sym("Ot6NumSingle_ext"), H.sym("Ot6NumSingle_ext"))
  emu.addMemoryCallback(function()
    if not cur or not cur.live then return end
    local y = emu.getState()["cpu.y"] & 0xFFFF
    cur.mnums[#cur.mnums + 1] = { t = H.readByte(0x20), v = H.readWord(0x2BCE + y), f = H.frame }
  end, emu.callbackType.exec, H.sym("Ot6NumMulti_ext"), H.sym("Ot6NumMulti_ext"))
end

-- read a single numeral's drawn state: its five slots' tiles, and its sprites
local function readSingle(n)
  if n.seen then return end
  local k = n.k
  if (H.readByte(0x631A + k) & 0x7F) == 0 then return end          -- not up yet
  n.up = n.up or H.frame
  if H.frame < n.up + 4 then return end                             -- its tiles and sprites a few frames on
  n.seen = H.frame
  n.slots = {}
  for i = 0, 4 do
    local w = tileWord(slotTile(k, i))
    local g = nil
    for d = 0, 9 do if glyphIs(w, d) then g = d end end
    n.slots[i] = g or (blankIs(w) and "_" or "?")
  end
  n.sprA, n.sprB, n.sprC = oamOn(TILE_A[k]), oamOn(TILE_B[k]), oamOn(TILE_C[k])
  n.green = (H.readByte(0x631A + k) & 0x80) ~= 0
end

local function readMulti(m)
  if m.seen or H.readByte(0x7B3E) == 0 then return end
  m.up = m.up or H.frame
  if H.frame < m.up + 4 then return end
  m.seen = H.frame
  local t = m.t
  local base = ({ [0] = 0x60, 0x64, 0x68, 0x6C, 0x80, 0x84, 0x88, 0x8C, 0xA0, 0xA4 })[t]
  m.slots = {}
  for i = 0, 3 do
    local w = tileWord(base + i)
    local g = nil
    for d = 0, 9 do if glyphIs(w, d) then g = d end end
    m.slots[i] = g or (blankIs(w) and "_" or "?")
  end
  m.d0 = H.readByte(0x7B5D + t)
  m.row = {}
  for i, tile in ipairs({ 0xA9, 0xAA, 0xAC, 0xAD, 0xAF }) do m.row[i] = glyphIs(tileWord(tile), i) end
  m.sprA, m.sprB = oamOn(base), oamOn(base + 2)
  m.green = (H.readByte(0x7B3F + t) & 0x80) ~= 0
  m.sprX = {}
  for i, tile in ipairs({ 0xA8, 0xAA, 0xAB, 0xAD, 0xAE }) do m.sprX[i] = oamOn(tile) end
end

local function open(tag)
  return H.seqStep({
    H.driveUntil(function() return H.battleLoadStarted() end, 60000, {
      H.worldNavTo(function() return B[1] end, function() return B[2] end,
        { maxFrames = 4000, arrive = function() return H.battleLoadStarted() end }),
      H.call(function() A, B = B, A end),
    }, tag .. ": a random battle"),
    H.waitUntil(function() return H.battleActive() end, 1200, tag .. ": the battle is up", 2),
    H.waitFrames(30),
  })
end

local results = {}
local CASES = {
  { name = "holder", count = 500, shot = "limitbreak_single" },
  { name = "other", count = 499 },
  { name = "multi", count = 500, multi = true, shot = "limitbreak_multi" },
  { name = "broken", count = 500, broken = true },
  { name = "weak", count = 500, weak = true },
  { name = "heal", count = 500, heal = true },
}

local function branch(cs, restore)
  local r = { name = cs.name, count = cs.count, shot = cs.shot, multi = cs.multi, caps = {}, nums = {}, mnums = {}, hp0 = {}, hp1 = {}, mons = {} }
  results[#results + 1] = r
  local steps = {}
  if restore then
    local req
    steps[#steps + 1] = H.call(function() H.setPad({}); req = H.requestLoadState(snap.blob) end)
    steps[#steps + 1] = H.waitFrames(2)
    steps[#steps + 1] = H.call(function() H.checkReq(req, "the snapshot on the map"); H.rearmInputInjection() end)
  end
  steps[#steps + 1] = H.call(function()
    A, B = A0, B0
    stageCount(who, cs.count)
    H.log(string.format("[limit] %s: $%02X's count on Bahamut staged at %d", cs.name, who, cs.count))
  end)
  steps[#steps + 1] = open(cs.name)
  steps[#steps + 1] = H.call(function()
    seat = nil
    for s = 0, 3 do if H.readByte(0x3ED8 + s * 2) == who then seat = s end end
    H.assertEq(seat ~= nil, true, cs.name .. ": H is in the battle")
    r.mask = H.readByte(H.sym("OT6_LIMITBREAK") & 0xFFFF)
    for s = 0, 5 do
      if H.monStanding(s) then
        local e = 8 + s * 2
        r.mons[#r.mons + 1] = e
        H.writeWord(0x3BF4 + e, HP)
        H.writeWord(0x3C1C + e, HP)
      end
    end
    H.assertEq(#r.mons >= 1, true, cs.name .. ": a monster stands")
    inj = { heals = {} }
    if cs.broken then
      inj.broken = r.mons[1]
      emu.write(0x7E0000 + H.sym("OT6_BROKEN_TICKS") + inj.broken, 8, emu.memType.snesMemory)
    end
    if cs.weak then inj.weak = r.mons[1] end
    if cs.heal then inj.heal = r.mons[1] end
    if cs.multi then inj.multi = true end
    H.log(string.format("[limit] %s: seat %d, OT6_LIMITBREAK %s, monsters %s staged at %d HP", cs.name, seat,
      hex(r.mask), table.concat(r.mons, ","), HP))
    cur = r
  end)
  steps[#steps + 1] = H.kitBattle({ { who = who, cmd = CMD_MAGIC, spell = ULTIMA, boost = 2 } }, {
    untilPlanDone = true, idle = "defend", maxFrames = 60000,
    planDone = function() return r.ended ~= nil end,
  })
  -- the kit's step ends once the cast is confirmed; the cast resolves and its numerals draw after
  steps[#steps + 1] = H.driveUntil(function() return r.ended ~= nil end, 6000, {
    H.call(function() H.setPad({}) end), H.waitFrames(1),
  }, cs.name .. ": H's Ultima resolved and its numerals drawn")
  steps[#steps + 1] = H.call(function()
    for _, e in ipairs(r.mons) do r.hp1[e] = H.readWord(0x3BF4 + e) end
    r.heals = inj.heals
    r.injHit = inj.brokenHit or inj.weakHit or inj.healHit
    r.injBroken = inj.broken
    cur = nil
  end)
  return H.seqStep(steps)
end

-- the window around H's action: live from H's turn (its command executes) to its end, then 90 frames for the
-- numerals to draw
local function watch()
  local ae = H.sym("Ot6ActionEnd")
  emu.addMemoryCallback(function()
    if not cur or cur.live or seat == nil then return end
    if H.readByte(0x3A7C) == CMD_MAGIC and H.readByte(0x3A7D) == ULTIMA then
      cur.live = true
      for _, e in ipairs(cur.mons) do cur.hp0[e] = H.readWord(0x3BF4 + e) end
    end
  end, emu.callbackType.write, 0x7E3410, 0x7E3410)
  emu.addMemoryCallback(function()
    if not cur or not cur.live or cur.endF then return end
    if (emu.getState()["cpu.x"] & 0xFF) == seat * 2 then cur.endF = H.frame end
  end, emu.callbackType.exec, ae, ae)
  local nmi = H.sym("BattleNMI")
  emu.addMemoryCallback(function()
    if cur and cur.live then oamSnap() end
  end, emu.callbackType.exec, nmi, nmi)
  emu.addEventCallback(function()
    if not cur or not cur.live then return end
    for _, n in ipairs(cur.nums) do readSingle(n) end
    for _, m in ipairs(cur.mnums) do readMulti(m) end
    if cur.shot and not cur.shotDone then
      local up = (cur.multi and #cur.mnums > 0 and cur.mnums[1].seen) or (not cur.multi and #cur.nums > 0
        and #cur.nums == #cur.mons and cur.nums[#cur.nums].seen)
      if up then cur.shotAt = cur.shotAt or (H.frame + 6) end
      if cur.shotAt and H.frame >= cur.shotAt then H.screenshot(cur.shot); cur.shotDone = true end
    end
    if cur.endF and H.frame > cur.endF + 90 and not cur.ended then cur.ended = H.frame end
  end, emu.eventType.endFrame)
end

local function claims()
  local bad = 0
  local function claim(ok, what)
    H.log(string.format("[limit] %s %s", ok and "ok:" or "NOT:", what))
    if not ok then bad = bad + 1 end
  end
  for _, r in ipairs(results) do
    local holder = r.count >= 500
    claim(((r.mask >> seat) & 1) == (holder and 1 or 0), string.format("%s: OT6_LIMITBREAK %s at the open (H's bit %s)",
      r.name, hex(r.mask), holder and "set" or "clear"))
    local byY = {}
    for _, p in ipairs(r.caps) do byY[p.y] = p end
    for _, e in ipairs(r.mons) do
      local side = byY[e] or byY[e + 0x14]
      claim(side ~= nil, string.format("%s: H's Ultima reached the cap for entity %d", r.name, e))
      if side then
        local pre, total = side.pre, side.total
        local heal = side.y >= 0x14
        local want
        if r.name == "broken" and e == r.injBroken then want = LIMIT
        elseif r.name == "weak" and e == r.mons[1] then want = 0x7FFF   -- x2 saturated at $FFFF, then an unbroken
                                                                          --   body's half (vanilla's skip: 16,666)
        elseif heal then want = math.min(pre, STD)
        elseif holder then want = math.min(pre, LIMIT) else want = math.min(pre, STD) end
        claim(pre > STD, string.format("%s: entity %d's amount %d is past 9999 (the precondition)", r.name, e, pre))
        claim(total == want, string.format("%s: entity %d's %s total %d (amount %d; want %d)", r.name, e,
          heal and "heal" or "damage", total, pre, want))
        if heal then
          claim(r.hp1[e] == math.min(HP, r.hp0[e] + total), string.format("%s: entity %d's HP %d -> %d, healed %d",
            r.name, e, r.hp0[e], r.hp1[e], total))
        else
          claim(r.hp0[e] - r.hp1[e] == total, string.format("%s: entity %d's HP %d -> %d, down %d (the total %d)",
            r.name, e, r.hp0[e], r.hp1[e], r.hp0[e] - r.hp1[e], total))
        end
        -- the numeral
        local code = heal and (HEAL + total) or total
        local found = false
        for _, n in ipairs(r.nums) do
          if n.tgt == e // 2 and n.v == code then
            found = true
            local ds = digits(total)
            local shown = {}
            for i = 0, 4 do shown[#shown + 1] = tostring(n.slots and n.slots[i]) end
            local okd = n.slots ~= nil
            for i = 0, 4 do
              local want_d = ds[i + 1]
              if want_d == nil then want_d = "_" end
              if not n.slots or n.slots[i] ~= want_d then okd = false end
            end
            claim(okd, string.format("%s: entity %d's numeral (thread %d) draws %s in its five slots: %s", r.name, e,
              n.k, tostring(total), table.concat(shown, " ")))
            local a, b, c = n.sprA and n.sprA[1], n.sprB and n.sprB[1], n.sprC and n.sprC[1]
            local five = #ds == 5
            claim(a ~= nil and b ~= nil and b.x - a.x == 16 and b.y == a.y and ((not five and #n.sprC == 0)
              or (c ~= nil and c.x - b.x == 8 and c.y == a.y)), string.format("%s: entity %d's sprites A x%s, B x%s%s",
              r.name, e, a and a.x or "-", b and b.x or "-", five and (", C x" .. (c and c.x or "-")) or " (no C)"))
            claim(n.green == heal, string.format("%s: entity %d's numeral is %s", r.name, e,
              n.green and "green" or "white"))
          end
        end
        for _, m in ipairs(r.mnums) do
          if m.t == e // 2 and m.v == code then
            found = true
            local ds = digits(total)
            local slots = {}
            local five = #ds == 5
            local okd = m.slots ~= nil and (five and m.d0 == ds[1] or (not five and m.d0 == 0))
            local first = five and 2 or 1
            for i = 0, 3 do
              local want_d = ds[first + i]
              if want_d == nil then want_d = "_" end
              slots[#slots + 1] = tostring(m.slots and m.slots[i])
              if not m.slots or m.slots[i] ~= want_d then okd = false end
            end
            claim(okd, string.format("%s: entity %d's multi numeral draws %d: digit %d by the glyph row, slots %s",
              r.name, e, total, m.d0 or -1, table.concat(slots, " ")))
            local rowOk = true
            for i = 1, 5 do if not m.row[i] then rowOk = false end end
            claim(rowOk, string.format("%s: the glyph row holds 1-5 at $A9 $AA $AC $AD $AF", r.name))
            local a, b = m.sprA[1], m.sprB[1]
            local dx = ({ -16, -8, -16, -8, -16 })[ds[1]]
            local x = nil                           -- the glyph row's tiles are shared: the entry beside A
            if five and a then
              for _, o in ipairs(m.sprX[ds[1]] or {}) do if o.y == a.y and o.x - a.x == dx then x = o end end
            end
            claim(a ~= nil and b ~= nil and b.x - a.x == 16 and (not five or (x ~= nil and x.x - a.x == dx and x.y == a.y)),
              string.format("%s: entity %d's multi sprites A x%s, B x%s%s", r.name, e, a and a.x or "-",
                b and b.x or "-", five and (", ten-thousands x" .. (x and x.x or "-")) or ""))
          end
        end
        claim(found, string.format("%s: a numeral for entity %d carries %s", r.name, e, hex(code)))
      end
    end
    if r.name == "multi" then
      claim(#r.mnums >= 5, string.format("multi: %d multi-target numerals (five or more)", #r.mnums))
      for s = 0, 3 do
        local hv = r.heals and r.heals[s * 2]
        if hv then
          local seen = false
          for _, m in ipairs(r.mnums) do
            if m.t == s and m.v == HEAL + hv then
              seen = true
              local ds = digits(hv)
              local okd = m.green and m.d0 == 0
              for i = 0, 3 do
                local want_d = ds[i + 1] or "_"
                if m.slots[i] ~= want_d then okd = false end
              end
              claim(okd, string.format("multi: seat %d's heal %d draws green in four slots", s, hv))
            end
          end
          claim(seen, string.format("multi: seat %d's heal %d has its numeral", s, hv))
        end
      end
    end
    if r.name == "broken" then claim(r.injHit == true, "broken: Ot6BrokenDmg doubled the staged 33,333") end
    if r.name == "weak" then claim(r.injHit == true, "weak: Ot6WeakDouble doubled the staged 33,333") end
    if r.name == "heal" then claim(r.injHit == true, "heal: the pass went to the heal side") end
  end
  H.assertEq(bad, 0, "every claim above holds")
end

H.run({ maxFrames = 900000 }, {
  H.bootCheckpoint("wor-ragnarok-v1"),
  H.call(function()
    for ch = 0, 15 do
      if H.readByte(0x1600 + 37 * ch + 0x1E) == RAGNAROK then who = ch end
    end
    H.assertEq(who ~= nil and who < 12, true, "precondition: a member who can hold espers wears Ragnarok")
    local x, y = H.worldX(), H.worldY()
    A0 = { x, y }
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
      if B0 == nil and H.worldPassable(x + d[1], y + d[2]) then B0 = { x + d[1], y + d[2] } end
    end
    H.assertEq(B0 ~= nil, true, "a passable world tile beside the save")
    H.log(string.format("[limit] H = $%02X; pacing (%d,%d) <-> (%d,%d)", who, A0[1], A0[2], B0[1], B0[2]))
    arm()
    watch()
  end),
  H.call(function() H.setPad({}); snap = H.requestSaveState() end),
  H.waitFrames(2),
  H.call(function() H.checkReq(snap, "the snapshot on the map") end),
  H.lazy(function()
    local steps = {}
    for i, cs in ipairs(CASES) do
      steps[#steps + 1] = branch(cs, i > 1)
    end
    return H.seqStep(steps)
  end),
  H.call(claims),
  H.logStep("[limit] PASS: a holder's damage passes 9999 to 42,069, everyone else's and every heal stay at 9999, "
    .. "and five-digit numerals draw like four"),
})
