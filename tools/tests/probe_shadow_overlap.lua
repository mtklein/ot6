-- @suite slow
-- probe_shadow_overlap.lua -- asserts OT6_SHADOW ($ecf1+) is written only
-- from bank F0, and that vanilla's old buffer ($5762+) sees no bank-F0 write.
local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/whelk_entry.mss.lua"
local WHELK = { [0x0134] = true }
local function whelk()
  return H.battleLoadStarted() and H.formationHas(WHELK)
end

local NEW_LO, NEW_HI = 0x7EECF1, 0x7EECFE   -- new line 0 (checkpoint+prev+cells)
local OLD_LO, OLD_HI = 0x7E5762, 0x7E576F   -- old line 0, now vanilla's alone

local hits = {}           -- addr -> { count, pcs = {pcstr -> n} }
local vanillaOldHome, ot6NewHome = 0, 0
-- write callback PC is the instruction after the store; only the bank matters
local function watch(lo, hi)
  emu.addMemoryCallback(function(addr, value)
    local h = hits[addr]
    if not h then h = { count = 0, pcs = {} } ; hits[addr] = h end
    h.count = h.count + 1
    pcall(function()
      local s = emu.getState()
      local bank = s["cpu.k"]
      local pc = string.format("%02X:%04X v=%02X", bank, s["cpu.pc"], value)
      h.pcs[pc] = (h.pcs[pc] or 0) + 1
      if bank ~= 0xF0 and addr >= OLD_LO and addr <= OLD_HI then
        vanillaOldHome = vanillaOldHome + 1
      end
      if bank == 0xF0 and addr >= NEW_LO and addr <= NEW_HI then
        ot6NewHome = ot6NewHome + 1
      end
    end)
  end, emu.callbackType.write, lo, hi)
end

watch(NEW_LO, NEW_HI)
watch(OLD_LO, OLD_HI)
watch(0x7E57B9, 0x7E57B9)   -- control: above vanilla's write ceiling

local foreign = {}          -- writers from banks other than F0

H.run({ maxFrames = 30000 }, {
  H.waitFrames(20),
  H.loadState(STATE),
  H.waitFrames(10),
  H.driveUntil(whelk, 8000, {
    H.call(function()
      if H.dialogWaiting() then
        local n = (H.vars.an or 0) + 1 ; H.vars.an = n
        H.setPad(n % 8 < 4 and { "a" } or {})
        return
      end
      if not H.hasControl() then H.setPad({}) ; return end
      if not H.tileAligned() then H.setPad({}) ; return end
      H.setPad(H.fieldY() <= 5 and { down = true } or { up = true })
    end),
  }, "whelk battle reached"),
  H.call(function() H.setPad({}) end),
  H.waitUntil(function() return H.battleActive() end, 900, "whelk up", 30),
  H.waitFrames(240),

  -- edge-tap A until the first command menu appears
  H.driveUntil(function() return H.readByte(0x7bca) ~= 0 end, 4000, {
    H.call(function()
      local n = (H.vars.mn or 0) + 1 ; H.vars.mn = n
      H.setPad(n % 60 < 4 and { "a" } or {})
    end),
  }, "first menu opens"),
  H.call(function() H.setPad({}) end),
  H.waitFrames(120),

  -- The magitek list drawer stops at $5761, below OT6_SHADOW; force an Item
  -- list instead by clearing magitek status and repointing top commands.
  H.call(function()
    for c = 0, 3 do
      local st = 0x3ee4 + c*2
      H.writeByte(st, H.readByte(st) & 0xf7)      -- clear magitek
      H.writeByte(0x202e + c*12, 0x01)            -- command 0 := Item
      H.writeByte(0x2031 + c*12, 0x02)            -- command 1 := Magic
    end
    H.log("repointed all four command slots: 0=Item, 1=Magic")
  end),
  H.waitFrames(60),
  H.call(function()
    H.log(string.format("old-home writes before any list is opened: %d "
      .. "(must be 0 for the control below to mean anything)", vanillaOldHome))
    H.assertEq(vanillaOldHome, 0, "old home untouched before the list drive")
  end),

  -- Open a command list, closed-loop, cycling A/B/down until the old home
  -- is written; stops at the first list, whose Item template reaches deepest.
  H.driveUntil(function() return vanillaOldHome > 0 end, 2400, {
    H.pressButtons({ "a" }, 4), H.waitFrames(90),
    H.pressButtons({ "b" }, 4), H.waitFrames(45),
    H.pressButtons({ "down" }, 4), H.waitFrames(30),
  }, "a vanilla command-list drawer writes the old shadow home"),
  H.waitFrames(120),

  H.call(function()
    local addrs = {}
    for a in pairs(hits) do addrs[#addrs + 1] = a end
    table.sort(addrs)
    for _, a in ipairs(addrs) do
      local h = hits[a]
      H.log(string.format("$%06X: %d writes", a, h.count))
      for pc, n in pairs(h.pcs) do
        H.log(string.format("    %s x%d", pc, n))
        local bank = tonumber(pc:sub(1, 2), 16)
        if bank ~= 0xF0 and a >= NEW_LO and a <= NEW_HI then
          foreign[#foreign + 1] = string.format("FOREIGN into new home: $%06X <- %s", a, pc)
        end
        if bank == 0xF0 and a >= OLD_LO and a <= OLD_HI then
          foreign[#foreign + 1] = string.format("OT6 still writing OLD home: $%06X <- %s", a, pc)
        end
      end
    end
    H.log(string.format("new anchor $ecf1 = $%04X   old $5762 = $%04X (vanilla's now)",
      H.readWord(0xecf1), H.readWord(0x5762)))
    H.log(string.format("exercised: vanilla wrote the old home %dx, "
      .. "bank F0 wrote the new home %dx", vanillaOldHome, ot6NewHome))
    if vanillaOldHome == 0 then
      error("no vanilla write reached $7E5762+ -- the fixture never opened a " ..
            "command list whose text template is long enough to touch the old " ..
            "shadow home (item = $13 bytes, magic = $10; magitek stops at " ..
            "$5761), so 'OT6 vacated it' would be vacuously clean")
    end
    if ot6NewHome == 0 then
      error("bank F0 never wrote $7EECF1+ -- the OT6 hud never drew into " ..
            "OT6_SHADOW's new home, so 'nothing foreign writes it' would be " ..
            "vacuously clean")
    end
    if #foreign > 0 then
      for _, f in ipairs(foreign) do H.log("  " .. f) end
      error(#foreign .. " shadow-buffer violation(s) -- see log")
    end
    H.log("ok: new home bank-F0 only, old home fully vacated")
  end),
}, "shadow overlap probe")
