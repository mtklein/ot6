-- probe_reveal_trace.lua -- LIVE trace of who writes the revealed-weakness
-- bytes on the first battle, under Random RAM on HEAD, with a WIPED codex.
-- Answers the coordinator's discriminator: with NO codex entry, does a fresh
-- Guard show revealed? If yes -> a real garbage source (trace the writer). If
-- '?' -> the reveal the user sees comes from their populated codex (correct
-- persistence), not RAM.
--
-- Boots from POWER-ON (no state load, so Random RAM actually reaches battle
-- init). Watches WRITES to the monster revealed-elems ($7E3E91-9B), revealed-
-- classes ($7E3EA5-AF) and weak-elems ($7E3BE8-F2) ranges, logging each
-- writer's bank:PC and value. Snapshots masks + codex at the seed entry.
local H = dofile("/Users/mtklein/ot6/tools/tests/lib/ot6.lua")

local hits = {}
local watching = false
local function watch(lo, hi)
  emu.addMemoryCallback(function(addr, value)
    if not watching then return end
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} }; hits[addr] = h end
    h.count = h.count + 1
    pcall(function()
      local s = emu.getState()
      local pc = string.format("%02X:%04X v=%02X", s["cpu.k"], s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
    end)
  end, emu.callbackType.write, lo, hi)
end
watch(0x7E3E91, 0x7E3E9B)   -- revealed elements, all 6 monster slots
watch(0x7E3EA5, 0x7E3EAF)   -- revealed classes
watch(0x7E3BE8, 0x7E3BF2)   -- weak elements

local seedRef, snap = nil, nil
local function armSeedSnapshot()
  seedRef = emu.addMemoryCallback(function()
    if snap then return end
    snap = { e = {}, c = {}, w = {}, magic = 0, cdxE = {}, cdxC = {} }
    for slot = 0, 5 do
      snap.e[slot] = emu.read(0x3e91 + slot * 2, emu.memType.snesWorkRam)
      snap.c[slot] = emu.read(0x3ea5 + slot * 2, emu.memType.snesWorkRam)
      snap.w[slot] = emu.read(0x3be8 + slot * 2, emu.memType.snesWorkRam)
    end
    snap.magic = emu.read(0x316000, emu.memType.snesMemory)
      | (emu.read(0x316001, emu.memType.snesMemory) << 8)
    for sp = 0, 5 do  -- codex bytes for species 0..5 (Guard is species 0)
      snap.cdxE[sp] = emu.read(0x316010 + sp, emu.memType.snesMemory)
      snap.cdxC[sp] = emu.read(0x316190 + sp, emu.memType.snesMemory)
    end
    emu.removeMemoryCallback(seedRef, emu.callbackType.exec, 0xF00000, 0xF00000)
  end, emu.callbackType.exec, 0xF00000, 0xF00000)
end

H.run({ maxFrames = 70000 }, {
  H.call(function()
    armSeedSnapshot()
    -- WIPE the codex so no species has a learned weakness: the discriminator's
    -- clean condition. Under power-on the seed re-checks the magic; a 0 magic
    -- forces the wipe path (codex all 0), guaranteeing no merge source.
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
  end),
  H.waitFrames(355),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.logStep("title handled; waiting out the opening..."),
  H.waitUntil(function() return H.frame >= 15400 end, 16000, "intro to finish"),
  H.call(function()
    -- re-wipe just before the battle (in case boot/intro touched sram), then
    -- start watching battle-init writers.
    emu.write(0x316000, 0, emu.memType.snesMemory)
    emu.write(0x316001, 0, emu.memType.snesMemory)
    watching = true
    H.log(string.format("pre-battle: $3E91=%02X $3E95=%02X $3BEC=%02X (field, pre-InitBattle)",
      H.readByte(0x3e91), H.readByte(0x3e95), H.readByte(0x3bec)))
  end),
  H.driveUntil(function() return H.battleLoadStarted() end, 24000, {
    H.hold({ "up" }), H.waitFrames(20), H.release(), H.waitFrames(2),
    H.pressButtons({ "a" }, 4),
  }, "first battle load"),
  H.waitUntil(function() return H.battleActive() end, 1200, "battle active", 30),
  H.waitFrames(240),

  H.call(function()
    if snap then
      H.log(string.format("SEED-ENTRY codex magic=%04X (374F='O7' means merge-active)", snap.magic))
      for sp = 0, 2 do
        H.log(string.format("  codex[species %d] elem=%02X class=%02X", sp, snap.cdxE[sp], snap.cdxC[sp]))
      end
      for slot = 0, 5 do
        H.log(string.format("  seed-entry slot%d revE=%02X revC=%02X weakE=%02X",
          slot, snap.e[slot], snap.c[slot], snap.w[slot]))
      end
    else
      H.log("WARNING: seed entry never fired")
    end

    local revealed = false
    for slot = 0, 5 do
      if (H.readByte(0x3aa8 + slot * 2) & 1) == 1 then
        local relm = H.readByte(0x3e91 + slot * 2)
        local rcls = H.readByte(0x3ea5 + slot * 2)
        local welm = H.readByte(0x3be8 + slot * 2)
        local c0 = H.readByte(H.shadowLine(slot) + 6)
        local c1 = H.readByte(H.shadowLine(slot) + 8)
        H.log(string.format("BATTLE slot%d sp=%04X weakE=%02X revE=%02X revC=%02X cell0=%02X cell1=%02X",
          slot, H.readWord(0x57c0 + slot * 2), welm, relm, rcls, c0, c1))
        if relm ~= 0 or rcls ~= 0 then revealed = true end
      end
    end

    H.log("--- WRITERS to revealed/weak bytes during battle init -> HUD ---")
    local addrs = {}
    for a in pairs(hits) do addrs[#addrs + 1] = a end
    table.sort(addrs)
    for _, a in ipairs(addrs) do
      local h = hits[a]
      local pcs = {}
      for pc, n in pairs(h.pcs) do pcs[#pcs + 1] = pc .. " x" .. n end
      table.sort(pcs)
      H.log(string.format("W $%06X: %d writes | %s", a, h.count, table.concat(pcs, " | ")))
    end
    if next(hits) == nil then H.log("no writes observed to any watched byte") end

    H.log(string.format("DISCRIMINATOR (wiped codex, Random RAM): anyRevealed=%s -> %s",
      tostring(revealed),
      revealed and "REAL BUG (garbage source, see writers above)"
                or "'?' (no reveal; user's reveals come from their populated codex)"))
    H.screenshot("reveal_trace")
  end),
})
