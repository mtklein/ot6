-- probe_objsentinel.lua -- which OBJ tiles does vanilla never WRITE once a
-- battle is running?
--
-- probe_objsweep.lua asked "did these bytes ever change?" and that is the
-- wrong question: TfrMonsterGfx (btlgfx_main.asm:5410) blankets vram word
-- $3000 with a fixed $2000-byte transfer EVERY battle, and the init path
-- clears $2c00-$3000 (:2244) and blanket-loads $2e00-$3000 (:2347).  A
-- region written with zeros over zeros never "changes", so a
-- change-detector reports it free.  That is the same shape of mistake
-- that put OT6's boost chevrons inside the damage-numeral block in the
-- first place (ot6.asm:2032 claims they were "verified blank +
-- unreferenced"; blank they were, because init clears them).
--
-- So: fill the whole OBJ region with a sentinel AFTER battle init has
-- finished, then play a full battle.  Any byte still holding the
-- sentinel was never written by anything -- zeros included.  That is the
-- property OT6 actually needs, since it uploads its art at init and
-- re-lays it after dialogues; anything written after that point eats it.
--
-- OBJ chr base word $2000 (obsel $61) => bytes $4000-$7FFF, tile n at
-- byte $4000 + n*32.  Both name tables (n = 0..511) are swept.
local H = dofile("/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/tools/tests/lib/ot6.lua")
local STATE = "/Users/mtklein/ot6/.claude/worktrees/agent-a7ce0f4f38c2c39f7/build/states/battle_doorstep.mss.lua"

local SENT = 0xa5
local NT = 512
local frames = 0

local function fill()
  local vr = emu.memType.snesVideoRam
  for a = 0x4000, 0x7fff do emu.write(a, SENT, vr) end
end

-- a tile survives only if all 32 bytes still read the sentinel
local function survivors()
  local vr = emu.memType.snesVideoRam
  local out = {}
  for t = 0, NT-1 do
    local ok = true
    for i = 0, 31 do
      if emu.read(0x4000 + t*32 + i, vr) ~= SENT then ok = false; break end
    end
    out[t] = ok
  end
  return out
end

H.run({ maxFrames = 40000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(200),
  H.call(function()
    H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
    for s = 0, 3 do
      if H.readWord(0x3bf4 + s*2) > 0 then H.writeWord(0x3bf4 + s*2, 900) end
      H.writeByte(0x3e9c + s*2, 3)
    end
    fill()
    H.log("obj vram filled with sentinel a5 after init")
    -- immediate control: nothing should have been overwritten yet
    local s0 = survivors()
    local n = 0
    for t = 0, NT-1 do if s0[t] then n = n + 1 end end
    H.assertEq(n, NT, "positive control: sentinel took on all 512 tiles")
  end),
  H.driveUntil(function()
    frames = frames + 1
    return frames >= 3000
  end, 30000, {
    H.call(function()
      if H.readByte(0x7bca) ~= 0 then
        if (frames // 97) % 3 == 0 then H.setPad({ "r" }) else H.setPad({ "a" }) end
      else H.setPad({}) end
    end),
    H.waitFrames(3),
    H.call(function() H.setPad({}) end),
    H.waitFrames(12),
  }, "battle played over the sentinel"),
  H.call(function()
    local s = survivors()
    local runs, i = {}, 0
    local list = {}
    for t = 0, NT-1 do if s[t] then list[#list+1] = t end end
    i = 1
    while i <= #list do
      local a = list[i]; local b = a
      while i < #list and list[i+1] == b + 1 do i = i + 1; b = list[i] end
      runs[#runs+1] = (a == b) and tostring(a) or string.format("%d-%d", a, b)
      i = i + 1
    end
    H.log(string.format("tiles never written during the battle (%d of 512): %s",
      #list, table.concat(runs, ", ")))
    -- 16x16 sprites need a quad {n, n+1, n+16, n+17}
    local quads = {}
    for _, t in ipairs(list) do
      if s[t] and s[t+1] and s[t+16] and s[t+17] and (t % 16) < 15 then
        quads[#quads+1] = t
      end
    end
    H.log("usable 16x16 quad origins: " .. table.concat(quads, ", "))
    for _, t in ipairs({ 200, 202, 204 }) do
      H.log(string.format("OT6 current quad origin %d survived: %s", t,
        tostring(s[t] and s[t+1] and s[t+16] and s[t+17])))
    end
  end),
})
