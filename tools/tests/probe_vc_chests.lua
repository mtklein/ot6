-- probe_vc_chests.lua -- NOT a suite test.  Measure the four #84 chests on
-- map 384's east half from gen_vector_crash's own traverse (issue #84):
--   Genji Glove (47,11) bit 125 -- behind the (58,18) span switch ($01F9,
--     _cb2fe7, event_main.asm:45071; the event scripts a 6-tile descent),
--   Elixir (88,23) bit 126 and Ether (71,30) bit 128 -- behind the (71,15)
--     lever ($0174),
--   Magicite (113,6) bit 127 -- behind the lever or the (104,17) toggle
--     ($01F5); this probe answers which.
-- Boots the gate_cave_save fixture, walks the generator's own opening
-- (386 save room -> 384 (64,12)), then runs the candidate insertion order:
-- span -> Genji -> lever -> Ether -> Elixir -> toggle -> Magicite, with a
-- bfsPath report before each stage and a final reachability check on the
-- (121,22) teleport approach the real traverse needs next.  Chest stands
-- are picked adaptively (first bfs-reachable neighbor) and logged, so the
-- generator edit can hardcode the measured stand/face.
-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
local H = dofile("tools/tests/lib/ot6.lua")

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end

local function landed(m, n)
  local cnt = 0
  return function()
    local ok = map() == m and H.hasControl() and H.tileAligned()
           and bright() >= 15 and not H.battleLoadStarted()
           and not H.dialogWaiting() and not H.worldMode()
    cnt = ok and cnt + 1 or 0
    return cnt >= (n or 15)
  end
end

local function pressWalk(dir, pred, maxFrames, what)
  local ph = 0
  return H.driveUntil(pred, maxFrames, {
    H.call(function()
      ph = (ph + 1) % 8
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); return
      end
      if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
      H.setPad({ [dir] = true })
    end),
  }, what)
end

local function switchLine(tag)
  return H.call(function()
    H.log(string.format("[%s] (%d,%d) $01F5=%d $01F9=%d $01FA=%d $0173=%d "
      .. "$0174=%d", tag, H.fieldX(), H.fieldY(), sw(0x01F5), sw(0x01F9),
      sw(0x01FA), sw(0x0173), sw(0x0174)))
  end)
end

-- every stand candidate for the four chests, plus the traverse waypoints
local TARGETS = {
  { 46, 11, "genji L (46,11)" }, { 47, 12, "genji B (47,12)" },
  { 48, 11, "genji R (48,11)" }, { 47, 10, "genji A (47,10)" },
  { 71, 31, "ether128 B (71,31)" }, { 70, 30, "ether128 L (70,30)" },
  { 72, 30, "ether128 R (72,30)" }, { 71, 29, "ether128 A (71,29)" },
  { 88, 24, "elixir B (88,24)" }, { 87, 23, "elixir L (87,23)" },
  { 89, 23, "elixir R (89,23)" }, { 88, 22, "elixir A (88,22)" },
  { 113, 7, "magicite B (113,7)" }, { 112, 6, "magicite L (112,6)" },
  { 114, 6, "magicite R (114,6)" }, { 113, 5, "magicite A (113,5)" },
  { 58, 18, "span switch (58,18)" }, { 71, 15, "lever (71,15)" },
  { 104, 17, "toggle (104,17)" }, { 121, 22, "teleport (121,22)" },
}

local function bfsReport(tag)
  return H.call(function()
    for _, t in ipairs(TARGETS) do
      local p = H.bfsPath(t[1], t[2])
      H.log(string.format("[bfs %s] %s: %s", tag, t[3],
        p and ("path " .. #p) or "NO PATH"))
    end
  end)
end

local script = {}
local function add(...)
  for _, s in ipairs({ ... }) do script[#script + 1] = s end
end

-- adaptive pickup: the first bfs-reachable candidate opens the chest
local function tryOpen(bit, what, cands)
  for _, c in ipairs(cands) do
    add(H.cond(function()
      return (not H.chestOpen(bit)) and H.bfsPath(c[1], c[2]) ~= nil
    end, {
      H.call(function()
        H.log(string.format("[pick] %s: stand (%d,%d) face %s",
          what, c[1], c[2], c[3]))
      end),
      H.openChest{ stand = { c[1], c[2] }, face = c[3], bit = bit,
                   what = what,
                   nav = { playBattles = "flee", maxFrames = 25000 } },
    }, {}))
  end
  add(H.call(function()
    H.log(string.format("[pick] %s: final open=%s", what,
      tostring(H.chestOpen(bit))))
  end))
end

-- ---- boot and the generator's own opening ---------------------------------
add(
  H.loadState("build/states/gate_cave_save.mss.lua"),
  H.waitFrames(120),
  H.call(function()
    H.assertEq(map(), 386, "booted in the save room (map 386)")
  end),
  H.navTo(73, 58, { playBattles = "flee", maxFrames = 9000 }),
  pressWalk("down", function() return map() == 384 end, 1200,
    "held DOWN off 386 (73,59) -> 384 (64,12)"),
  H.waitUntil(landed(384, 10), 2400, "384 landing", 5),
  H.waitFrames(30),
  switchLine("pre-span"),
  bfsReport("pre-span")
)

-- ---- the (58,18) span switch and the Genji shelf --------------------------
add(
  H.navTo(58, 18, { playBattles = "flee", maxFrames = 20000 }),
  -- the retrying up+A loop the retired probe_v07_384west measured this
  -- switch with (the event scripts a descent, so the sw read is the exit)
  (function() local ph = 0
    return H.driveUntil(function() return sw(0x01F9) == 1 end, 3000, {
      H.call(function()
        ph = (ph + 1) % 8
        if H.battleLoadStarted() then
          H.setPad({ l = true, r = true }); return
        end
        if H.dialogWaiting() then H.setPad(ph < 4 and { "a" } or {}); return end
        H.setPad(ph < 4 and { up = true, a = true } or { up = true })
      end),
    }, "face-UP+A on (58,18) -> $01F9 (the west span); scripted descent")
  end)(),
  H.waitUntil(landed(384, 15), 3600, "post-span control", 5),
  H.waitFrames(30),
  switchLine("post-span"),
  bfsReport("post-span")
)
tryOpen(125, "Genji Glove", {
  { 46, 11, "right" }, { 47, 12, "up" }, { 48, 11, "left" },
  { 47, 10, "down" },
})
add(switchLine("post-genji"), bfsReport("post-genji"))

-- ---- the (71,15) lever and the east half ----------------------------------
add(
  H.navTo(71, 15, { playBattles = "flee", maxFrames = 20000 }),
  H.tapLever(0x0174, 900, "tap-once UP+A on (71,15) -> $0174"),
  H.stepOff({ "down", "left", "right", "up" }, 2400,
    "step off the (71,15) re-entry trigger"),
  switchLine("post-lever"),
  bfsReport("post-lever")
)
tryOpen(128, "Ether (71,30)", {
  { 71, 31, "up" }, { 70, 30, "right" }, { 72, 30, "left" },
  { 71, 29, "down" },
})
tryOpen(126, "Elixir (88,23)", {
  { 88, 24, "up" }, { 87, 23, "right" }, { 89, 23, "left" },
  { 88, 22, "down" },
})
tryOpen(127, "Magicite (113,6) pre-toggle", {
  { 113, 7, "up" }, { 112, 6, "right" }, { 114, 6, "left" },
  { 113, 5, "down" },
})
add(switchLine("post-east"), bfsReport("post-east"))

-- ---- the (104,17) toggle, then Magicite again if it was walled ------------
add(
  H.navTo(104, 17, { playBattles = "flee", maxFrames = 30000 }),
  H.tapLever(0x01F5, 900, "tap-once UP+A on (104,17) -> $01F5"),
  H.release(),
  H.stepOff({ "down", "left", "right" }, 2400,
    "step off the (104,17) toggle"),
  switchLine("post-toggle"),
  bfsReport("post-toggle")
)
tryOpen(127, "Magicite (113,6) post-toggle", {
  { 113, 7, "up" }, { 112, 6, "right" }, { 114, 6, "left" },
  { 113, 5, "down" },
})

-- ---- the traverse's next waypoint must still be reachable -----------------
add(
  switchLine("final"),
  bfsReport("final"),
  H.call(function()
    H.log(string.format("[final] bits 125=%s 126=%s 127=%s 128=%s",
      tostring(H.chestOpen(125)), tostring(H.chestOpen(126)),
      tostring(H.chestOpen(127)), tostring(H.chestOpen(128))))
    H.assertEq(H.bfsPath(121, 22) ~= nil, true,
      "the (121,22) teleport approach is still reachable")
  end),
  H.logStep(function()
    return string.format("vc chest probe complete at frame %d", H.frame)
  end)
)

H.run({ maxFrames = 150000 }, script)
