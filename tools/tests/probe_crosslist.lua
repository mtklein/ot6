-- probe_crosslist.lua -- measurement instrument for issue #36:
-- "Tools shows Cure 2" cross-list contamination.
--
-- HYPOTHESIS UNDER TEST: Ot6RestageGate_ext (ot6_hud.asm) restages the open
-- magic list through the SHARED 4-line staging state $7ba5/$7ba6 when boost
-- moves (OT6_RESTAGE=$57d4).  If the player leaves magic browse ($7bc2=$0e)
-- mid-cycle (a B press within ~3 frames of the R edge), the gate @drop path
-- clears OT6_RESTAGE but leaves $7ba5 stranded at $81-$83.  Every vanilla
-- window-open state (OpenToolsWindow's MakeToolsList_04, OpenMagicWindow,
-- OpenItemWindow, ...) does `lda $7ba5 / bmi skip-init`, so the NEXT window
-- to open skips its own init: it draws only the remaining 4-(stranded&3)
-- lines, starting from the magic list's stale $7ba6 row, and the first
-- screen line(s) of the window keep the PREVIOUS list's tiles -- the magic
-- row the gate had just restaged.
--
-- This probe: Terra (Magic + Tools commands), open magic browse, press R
-- (boost -> restage request), press B at a swept delay, log the whole
-- $7bc2/$57d4/$7ba5/$7ba6/$7ba9 interleaving per frame, then open Tools and
-- scan VRAM for magic-list names inside the tools window.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/battle_doorstep.mss.lua"

local MENU, ACTOR, MSTATE = 0x7BCA, 0x62CA, 0x7BC2
local ST_SPELL, ST_TOOLS = 0x0E, 0x30
local STAGE, ROW, QUEUED, RESTAGE = 0x7BA5, 0x7BA6, 0x7BA9, 0x57D4

local TOOLS = {
  { 0xA3, "NoiseBlaster" }, { 0xA4, "BioBlaster" }, { 0xA5, "Flash" },
  { 0xA6, "ChainSaw" }, { 0xA7, "Debilitator" }, { 0xA8, "Drill" },
  { 0xA9, "AirAnchor" }, { 0xAA, "AutoCrossbow" },
}

local function up(c)  return 0x80 + (c:byte() - ("A"):byte()) end
local function lo(c)  return 0x9a + (c:byte() - ("a"):byte()) end
local function glyphs(s)
  local t = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    t[i] = (c >= "A" and c <= "Z") and up(c) or lo(c)
  end
  return t
end

local function findName(seq)
  local vr = emu.memType.snesVideoRam
  for w = 0x6000, 0x7FF0 do
    local hit = true
    for i = 1, #seq do
      if (emu.readWord((w + i - 1) * 2, vr) & 0xFF) ~= seq[i] then hit = false break end
    end
    if hit then return w end
  end
  return nil
end

local actor
local tracing = false
local tag = ""
emu.addEventCallback(function()
  if not tracing then return end
  H.log(string.format("[%s] st=%02x restage=%02x stage=%02x row=%02x q=%02x pend=%d",
    tag, H.readByte(MSTATE), H.readByte(RESTAGE), H.readByte(STAGE),
    H.readByte(ROW), H.readByte(QUEUED),
    actor and H.readByte(0x3e9d + actor*2) or -1))
end, emu.eventType.startFrame)

-- pinned every frame until the menu opens, so the command window is BUILT
-- from this list (writing $202e after the window opened does nothing)
local function pinParty()
  -- only Terra's slot: the others keep Fight so the menu can pass on
  for s = 0, 3 do
    if H.readByte(0x3ed8 + s*2) == 0 then
      local s1 = 0x3ee4 + s*2                   -- clear magitek
      H.writeByte(s1, H.readByte(s1) & 0xf7)
      -- commands: Magic, Tools, blank, blank
      H.writeByte(0x202e + s*12 + 0*3, 0x02)
      H.writeByte(0x202e + s*12 + 1*3, 0x09)
      H.writeByte(0x202e + s*12 + 2*3, 0xff)
      H.writeByte(0x202e + s*12 + 3*3, 0xff)
      H.writeWord(0x3c08 + s*2, 99)             -- mp
    end
  end
  -- the eight tools into the battle item buffer (battle_toolslist's pin)
  for i, t in ipairs(TOOLS) do
    local b = 0x2686 + (i - 1) * 5
    H.writeByte(b + 0, t[1])
    H.writeByte(b + 1, 0x40)
    H.writeByte(b + 2, 0x00)
    H.writeByte(b + 3, 1)
  end
end

local function setup()
  actor = H.readByte(ACTOR) & 3
  H.writeByte(0x3e9c + actor*2, 5)              -- bp to spend
  H.writeByte(0x3e9d + actor*2, 0)
  H.writeWord(0x3C00, 3000); H.writeWord(0x3C02, 3000)
  H.writeByte(0x3f04, H.readByte(0x3f04) | 0x10)   -- quiet the guards
  H.writeByte(0x3f06, H.readByte(0x3f06) | 0x10)
end

local strandedAt = nil

-- one strand attempt: (re)open magic browse, R edge, B after `delay` frames.
local function attempt(delay)
  return {
    -- get back to / stay at the command window with the menu up
    H.driveUntil(function()
      return H.readByte(MENU) ~= 0 and H.readByte(MSTATE) ~= ST_SPELL
        and H.readByte(MSTATE) ~= 0x0d
    end, 600, {
      H.call(function() H.setPad({ "b" }) end), H.waitFrames(2),
      H.call(function() H.setPad({}) end), H.waitFrames(10),
    }, "command window up (pre-attempt)"),
    -- open the magic list (cursor sits on cmd row 0 = Magic)
    H.driveUntil(function() return H.readByte(MSTATE) == ST_SPELL end, 600, {
      H.pressButtons({ "a" }, 4), H.waitFrames(16),
    }, "spell list open"),
    H.call(function()
      -- park the list at the top for a deterministic scroll base
      H.writeByte(0x8913 + actor, 0)
      H.writeByte(0x8917 + actor, 0)
      H.writeByte(0x891b + actor, 0)
    end),
    H.waitFrames(20),
    H.call(function()
      tag = "d" .. delay
      tracing = true
      H.log(string.format("attempt delay=%d: stage=%02x restage=%02x",
        delay, H.readByte(STAGE), H.readByte(RESTAGE)))
    end),
    H.hold({ "r" }), H.waitFrames(2), H.release(),
    H.waitFrames(delay),
    H.hold({ "b" }), H.waitFrames(4), H.release(),
    H.waitFrames(14),
    H.call(function()
      tracing = false
      local s = H.readByte(STAGE)
      H.log(string.format("after attempt d=%d: stage=%02x row=%02x st=%02x",
        delay, s, H.readByte(ROW), H.readByte(MSTATE)))
      if s ~= 0 and strandedAt == nil then strandedAt = delay end
    end),
  }
end

H.run({ maxFrames = 60000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.enterEncounter(),
  H.waitFrames(240),
  -- menu must belong to Terra (char index 0): she owns a real spell list.
  -- pin the party's command lists every frame until her window is BUILT.
  H.driveUntil(function()
    if H.readByte(MENU) == 0 then pinParty(); return false end
    return H.readByte(0x3ed8 + (H.readByte(ACTOR) & 3)*2) == 0
  end, 8000, {
    H.call(function()
      pinParty()
      if H.readByte(MENU) ~= 0 then H.setPad({ "a" }) end
    end),
    H.waitFrames(4),
    H.call(function() H.setPad({}) end),
    H.waitFrames(24),
  }, "terra holds the menu"),
  H.call(setup),

  -- sweep the B delay until a strand is caught
  H.repeatN(1, attempt(0)),
  H.cond(function() return strandedAt == nil end, attempt(1), {}),
  H.cond(function() return strandedAt == nil end, attempt(2), {}),
  H.cond(function() return strandedAt == nil end, attempt(3), {}),

  H.call(function()
    H.log(string.format("strand sweep done: strandedAt=%s stage=%02x",
      tostring(strandedAt), H.readByte(STAGE)))
  end),

  -- now open the Tools window with whatever $7ba5 holds
  H.call(function() tag = "tools"; tracing = true end),
  -- park the command cursor (w7e890f,slot) on Tools (row 1) and open it
  H.driveUntil(function() return H.readByte(MSTATE) == ST_TOOLS end, 600, {
    H.call(function()
      local s = H.readByte(MSTATE)
      if s == ST_SPELL or s == 0x0d then
        H.setPad({ "b" })
      elseif s == 0x05 or s == 0x01 then
        H.writeByte(0x890f + actor, 1)
        -- clear the disable bit on the Tools row ($202f = cmd flags;
        -- check_command @7a4e treats bit7 as "cursor may not rest here")
        H.writeByte(0x202e + actor*12 + 1*3 + 1, 0x00)
        H.setPad({ "a" })
      else
        H.setPad({})
      end
    end),
    H.waitFrames(2),
    H.call(function() H.setPad({}) end),
    H.waitFrames(6),
  }, "tools window open"),
  H.waitFrames(12),
  H.call(function()
    tracing = false
    H.screenshot("crosslist_tools")
    -- what does the tools window actually show?
    for _, nm in ipairs({ "Fire", "Cure", "NoiseBlaster", "BioBlaster",
                          "Flash", "ChainSaw", "Drill", "AutoCrossbow" }) do
      local w = findName(glyphs(nm))
      H.log(string.format("  vram scan %-14s : %s", nm,
        w and string.format("FOUND at word $%04x", w) or "absent"))
    end
    local ids = {}
    for i = 0, 7 do ids[i+1] = string.format("%02x", H.readByte(0x4005 + i*3)) end
    H.log("wItemList ids: " .. table.concat(ids, " "))
    H.log(string.format("final: stage=%02x row=%02x", H.readByte(STAGE), H.readByte(ROW)))
  end),

  -- SEVERITY: select the top row -- the one DISPLAYING "Cure 2" -- and watch
  -- what actually executes.  $3410 sees the resolved attack id at execution;
  -- $2baf+cmdptr region carries the queued command/item.  If the stale text
  -- drove the ACTION, Cure 2 ($2e) executes; if the list data is sound, the
  -- real row-0 tool (NoiseBlaster $a3) does.
  H.call(function()
    -- park the tools cursor on row 0 (scroll/col/row triple, per-slot)
    H.writeByte(0x895f + actor, 0)
    H.writeByte(0x8963 + actor, 0)
    H.writeByte(0x8967 + actor, 0)
    emu.addMemoryCallback(function(_, v)
      H.log(string.format("  $3410 write: %02x", v))
    end, emu.callbackType.write, 0x7e3410, 0x7e3410)
    tag = "sel"; tracing = true
  end),
  -- A to pick the cell, A again to confirm the target
  H.driveUntil(function() return H.readByte(MENU) == 0 end, 900, {
    H.call(function() H.setPad({ "a" }) end), H.waitFrames(2),
    H.call(function() H.setPad({}) end), H.waitFrames(10),
  }, "contaminated row selected and menu closed"),
  H.call(function() tracing = false end),
  H.waitFrames(180),
  H.call(function()
    H.screenshot("crosslist_executed")
    -- the queued action for the actor: $2bab is slot ptrs? log the item bank
    H.log(string.format("post-exec: pend=%d bp=%d",
      H.readByte(0x3e9d + actor*2), H.readByte(0x3e9c + actor*2)))
  end),
})
