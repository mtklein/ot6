-- @manual standalone: lua tools/tests/blitz_gate_selftest.lua  (after ninja build/ot6.sfc)
-- blitz_gate_selftest.lua -- opts.blitzVs gates every Blitz line (#509
-- review).  The plan rules' Blitz line took the gate at 955b7f9c, but the
-- chip model's offer (bestLine, which the press rule, the spend rule and
-- the care race read) still offered "the configured Blitz, whichever it
-- is" while only the holy-absorbing goddess stood.  Synthetic contract:
-- RAM is a stub table, the ROM records come from build/ot6.sfc; no
-- emulator, no gameplay claim.
emu = { eventType = { inputPolled = 1 }, addEventCallback = function() return 1 end }
local H = dofile(arg[1] or "tools/tests/lib/ot6.lua")

local function slurp(path)
  local f = assert(io.open(path, "rb"), path)
  local s = f:read("a"); f:close(); return s
end
local rom = slurp("build/ot6.sfc")
local dbg = slurp("ff6/rom/ff6-en.dbg")
local symMemo = {}
H.sym = function(name)
  if symMemo[name] == nil then
    local val = dbg:match('sym\tid=%d+,name="' .. name .. '",addrsize=absolute,scope=%d+,def=%d+,ref=[%d+]+,val=0x(%x+),seg=%d+,type=lab')
    symMemo[name] = assert(tonumber(val, 16), name .. " in ff6-en.dbg")
  end
  return symMemo[name]
end
H.readRomByte = function(off) return rom:byte(off + 1) end
H.readRomWord = function(off) return rom:byte(off + 1) | (rom:byte(off + 2) << 8) end
local mem = {}
local function w8(a, v) mem[a] = v & 0xFF end
local function w16(a, v) mem[a] = v & 0xFF; mem[a + 1] = (v >> 8) & 0xFF end
H.readByte = function(a) return mem[a] or 0 end
H.readWord = function(a) return (mem[a] or 0) | ((mem[a + 1] or 0) << 8) end
H.log = function() end

local n = 0
local function check(ok, what) assert(ok, what); n = n + 1 end

local HP, MAXHP, CURMP, MAXMP, BCHID, CMDTBL = 0x3BF4, 0x3C1C, 0x3C08, 0x3C30, 0x3ED8, 0x202E
local MON_HP, MON_PRESENT, SPECIES = 0x3BFC, 0x3AA8, 0x57C0
local AURABOLT, AIRBLADE = 0x5E, 0x62
local DEMON, GODDESS = 0x0181, 0x0182  -- any two species ids: the gate reads only membership

-- SABIN (character 5) at entity 0, full HP and MP, Fight / Blitz / Item;
-- two monsters, each a species id at $57C0
local function battle(standing)
  for k in pairs(mem) do mem[k] = nil end
  w8(0x3403, 0xFF)
  for x = 0, 18, 2 do w8(0x32CC + x, 0xFF); w8(0x32CD + x, 0xFF) end
  w16(HP, 900); w16(MAXHP, 900); w16(CURMP, 300); w16(MAXMP, 300); w8(BCHID, 5)
  for r = 0, 3 do w8(CMDTBL + r * 3, ({ 0x00, 0x0A, 0x01, 0xFF })[r + 1]) end
  for e = 1, 3 do w8(BCHID + e * 2, 0xFF) end
  for s, sp in pairs(standing) do
    w16(MON_HP + s * 2, 5000); w8(MON_PRESENT + s * 2, 1); w16(SPECIES + s * 2, sp)
  end
end
-- the Blitz lines the chip model offers SABIN against slot 0 at 3 BP
local function blitzOffers(opts)
  local D = H.newFightDriver("blitz gate", opts).driver
  D.counterVetoed = function() return false end  -- counter_selftest covers the AI-script veto
  D:makePlanRules(0)
  assert(D._race and D._race.bestLine, "makePlanRules left the chip model's bestLine for the race")
  local _, offered = D._race.bestLine(0, 0, 3)
  local t = {}
  for _, p in ipairs(offered) do if p.cmd == 0x0A then t[#t + 1] = p end end
  return t, offered
end

for _, blitz in ipairs({ AURABOLT, AIRBLADE }) do
  local base = { tactical = true, boost = true, items = false, blitz = blitz }
  local function with(vs) local o = {} for k, v in pairs(base) do o[k] = v end o.blitzVs = vs return o end
  -- ungated: the Blitz is offered, as before
  battle({ [0] = GODDESS })
  local b = blitzOffers(with(nil))
  check(#b == 1 and b[1].skill == blitz, string.format("no blitzVs: Blitz $%02X offered", blitz))
  -- gated on the demon, the goddess alone: no Blitz offered
  battle({ [0] = GODDESS })
  b = blitzOffers(with({ [DEMON] = true }))
  check(#b == 0, string.format("blitzVs demon, the goddess alone: Blitz $%02X must not be offered (got %d)", blitz, #b))
  -- the demon standing beside her: offered again
  battle({ [0] = GODDESS, [1] = DEMON })
  b = blitzOffers(with({ [DEMON] = true }))
  check(#b == 1, string.format("blitzVs demon, the demon standing: Blitz $%02X offered", blitz))
  -- the demon fallen (HP 0): gated off
  battle({ [0] = GODDESS, [1] = DEMON }); w16(MON_HP + 2, 0)
  b = blitzOffers(with({ [DEMON] = true }))
  check(#b == 0, string.format("blitzVs demon, the demon fallen: Blitz $%02X not offered", blitz))
end
print(string.format("blitz_gate_selftest: PASS -- %d checks", n))
