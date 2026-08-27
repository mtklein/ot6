-- OT6_CHECKPOINT_LAYOUT: ot6-codex-o8-v1
-- probe_ifritlab_bake.lua -- Ifrit & Shiva lab (battle 70), fixture baker.
--
-- Hand-run instrument (probe_): a faithful copy of gen_ifrit_magicite.lua's
-- own boot from the mrf-save-room-v1 checkpoint down to the battle-70 entry
-- point at map 264 (3,7), where it
--   1. dumps recon (bag, equipment, espers, spell rows, levels),
--   2. tops up with the gen's own fieldCare threshold (0.95),
--   3. banks ifritlab_entry.mss (weapons UNCHANGED from the checkpoint --
--      strategies equip their own from the fixture), reload-verified,
--   4. runs ONE instrumented recon fight: the class-correct loadout
--      (pierce for Ifrit's 6 pierce shields, slash for Shiva's 6 slash
--      shields, all non-elemental -- both siblings null everything but
--      fire/ice) + lib newFightDriver {tactical, boost, bank=3, items,
--      healer=LOCKE, nuke={Ice}}, with per-300-frame sibling telemetry,
--      shield-chip edges, swap edges, and the absorb-guard question
--      (does the driver refuse Celes' Ice because off-stage SHIVA $0108
--      is a formation species?) answered by the driver's own log lines.
-- PASSes whether the recon fight wins or loses; only the fixture bank
-- itself is load-bearing.  One [result] line either way.
--
-- Run:
--   OT6_SRAM_CHECKPOINT=tools/tests/checkpoints/mrf-save-room-v1 \
--   OT6_TIMEOUT=1800 tools/tests/run.sh tools/tests/probe_ifritlab_bake.lua \
--   build/ifritlab/bake.log

local H = dofile("tools/tests/lib/ot6.lua")

local LOCKE, EDGAR, SABIN, CELES = 1, 4, 5, 6
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local ICE_SPELL = 0x01
local IFRIT, SHIVA = 0x0109, 0x0108
local CHARS = { "TERRA", "LOCKE", "CYAN", "SHADOW", "EDGAR", "SABIN",
                "CELES", "STRAGO", "RELM", "SETZER", "MOG", "GAU",
                "GOGO", "UMARO" }

local function map() return H.mapId() & 0x1ff end
local function bright() return emu.getState()["ppu.screenBrightness"] or 0 end
local function sw(id) return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1 end
local function seq(steps) return H.cond(function() return true end, steps) end
local function settled()
  return H.hasControl() and H.tileAligned() and bright() >= 15
     and not H.dialogWaiting() and not H.battleLoadStarted() and not H.worldMode()
end

-- gen_ifrit_magicite's tapInto, verbatim: tap `dir` while the party has
-- control, hands off in scenes, edge-A through dialogs, flee battles.
local function tapInto(dir, pred, maxFrames, what)
  local phase, n, ph, calm, hb = 0, 0, 0, 0, 0
  return H.driveUntil(function()
    calm = (pred() and settled()) and calm + 1 or 0
    return calm >= 16
  end, maxFrames or 12000, {
    H.call(function()
      ph = (ph + 1) % 8
      hb = hb + 1
      if H.battleLoadStarted() then
        H.setPad({ l = true, r = true }); phase = 0; return
      end
      if H.dialogWaiting() then
        H.setPad(ph < 4 and { "a" } or {}); phase = 0; return
      end
      if phase == 0 then
        H.setPad({})
        if pred() then return end
        if settled() then phase, n = 1, 0 end
        return
      end
      if phase == 1 then
        n = n + 1
        H.setPad({ [dir] = true })
        if n >= 8 then phase, n = 2, 0 end
        return
      end
      H.setPad({})
      n = n + 1
      if n >= 24 then phase = 0 end
    end),
  }, what)
end

-- ---------------------------------------------------------------- recon --
local function reconDump(tag)
  -- party + levels + hp/mp + full equipment row per member
  local cur = H.readByte(0x1A6D)
  for c = 0, 13 do
    local b = H.readByte(0x1850 + c)
    if (b & 0x07) == cur and b ~= 0 then
      local base = 0x1600 + 37 * c
      H.log(string.format(
        "[recon %s] %s L%d hp=%d/%d mp=%d/%d esper=%02X wpn=%02X shld=%02X "
        .. "helm=%02X armor=%02X relics=%02X,%02X",
        tag, CHARS[c + 1], H.readByte(base + 0x08),
        H.readWord(base + 0x09), H.readWord(base + 0x0B) & 0x3FFF,
        H.readWord(base + 0x0D), H.readWord(base + 0x0F) & 0x3FFF,
        H.readByte(base + 0x1E), H.readByte(base + 0x1F),
        H.readByte(base + 0x20), H.readByte(base + 0x21),
        H.readByte(base + 0x22), H.readByte(base + 0x23),
        H.readByte(base + 0x24)))
    end
  end
  -- espers owned ($1A69.. bit = esper id - $36)
  H.log(string.format("[recon %s] espers owned $1A69..6C = %02X %02X %02X %02X",
    tag, H.readByte(0x1A69), H.readByte(0x1A6A),
    H.readByte(0x1A6B), H.readByte(0x1A6C)))
  -- the bag: every occupied slot as id:count
  local bag = {}
  for i = 0, 254 do
    local id = H.readByte(0x1869 + i)
    local n = H.readByte(0x1969 + i)
    if id ~= 0xFF and n > 0 then
      bag[#bag + 1] = string.format("%02X:%d", id, n)
    end
  end
  H.log(string.format("[recon %s] bag(%d slots) = %s", tag, #bag,
    table.concat(bag, " ")))
  -- known-spell rows for the two possible casters: $1A6E + 54*char,
  -- byte per spell 0..53, $FF = learned
  for _, c in ipairs({ LOCKE, CELES }) do
    local known = {}
    for s = 0, 53 do
      if H.readByte(0x1A6E + 54 * c + s) == 0xFF then
        known[#known + 1] = string.format("%02X", s)
      end
    end
    H.log(string.format("[recon %s] %s knows spells: %s", tag, CHARS[c + 1],
      #known > 0 and table.concat(known, " ") or "NONE"))
  end
end

-- ------------------------------------------------- loss + seed watches --
-- Same rationale as probe_thamlab_template.lua: the lib's own canary
-- never arms in a composed run (pcall'd sym literals invisible to
-- compose.py), so the lab arms its own, with literals compose collects.
local function armLossWatch()
  local ok, addr = pcall(function() return H.sym("GameOver") end)
  if ok then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.read, addr, addr)
  end
  local ok2, addr2 = pcall(function() return H.sym("TitleScreen") end)
  if ok2 then
    emu.addMemoryCallback(function()
      H.gameOverFired = H.gameOverFired + 1
    end, emu.callbackType.exec, addr2, addr2)
  end
  H.log(string.format("[lab] loss watch armed: GameOver(read)=%s TitleScreen(exec)=%s",
    tostring(ok), tostring(ok2)))
end

local res = { seeds = {}, deaths = 0, bframes = 0 }
local function armSeedWatch()
  local addr = H.seedStoreAddr()
  emu.addMemoryCallback(function()
    local seed = emu.getState()["cpu.a"] & 0xff
    res.seeds[#res.seeds + 1] = seed
    H.log(string.format("[lab] battle seeded $be=$%02X from $021e=%d at f%d",
      seed, H.readByte(0x021E), H.frame))
  end, emu.callbackType.exec, addr, addr)
end

local wasAlive = {}
local function trackDeaths()
  for e = 0, 3 do
    if H.readWord(0x3C1C + e * 2) > 0 then
      local alive = H.readWord(0x3BF4 + e * 2) > 0
      if wasAlive[e] and not alive then
        res.deaths = res.deaths + 1
        H.log(string.format("[lab] slot %d (char $%02X) DOWN at f%d (death #%d)",
          e, H.readByte(0x3ED8 + e * 2), H.frame, res.deaths))
      end
      wasAlive[e] = alive
    else
      wasAlive[e] = nil
    end
  end
end

-- -------------------------------------------------- per-strategy equip --
-- Equip the first candidate weapon actually in the bag (checkpoint arms
-- LOCKE/CELES bare-handed; which pierce/slash pieces exist is only
-- knowable from the recon dump, so this seeks down a preference list).
local function wornWeapon(c) return H.readByte(0x1600 + 37 * c + 0x1F) end
local function charPos(charId)
  return function() return (H.readByte(0x1850 + charId) >> 3) & 0x03 end
end
local function equipPref(charId, cands, tag)
  local steps = {}
  for _, id in ipairs(cands) do
    steps[#steps + 1] = H.cond(function()
      for _, w in ipairs(cands) do
        if wornWeapon(charId) == w then return false end
      end
      return H.invCountOf(id) > 0
    end, {
      H.equipWeapon(charPos(charId), id,
        { slot = 0, tag = string.format("%s $%02X", tag, id) }),
    }, {})
  end
  steps[#steps + 1] = H.call(function()
    H.log(string.format("[equipPref] %s ends holding $%02X",
      tag, wornWeapon(charId)))
  end)
  return seq(steps)
end

-- ------------------------------------------------------- battle reads --
local function eoff(m) return 8 + m * 2 end
local function mshields(m) return H.readByte(0x3E38 + eoff(m)) end
local function mticks(m)   return H.readByte(0x3E88 + eoff(m)) end
local function mhp(m)      return H.readWord(0x3BFC + m * 2) end
local function onfield(m)  return H.readByte(0x3AA8 + m * 2) & 1 end
local function mspecies(m) return H.readWord(0x57C0 + m * 2) end

local function partyLevels()
  local out = {}
  for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
    out[#out + 1] = H.readByte(0x1600 + 37 * c + 0x08)
  end
  return table.concat(out, ",")
end

-- ------------------------------------------------------------------------
H.run({ maxFrames = 260000, allowGameOver = true }, {
  -- 1. cold Continue, the gen's own boot
  H.waitFrames(350),
  H.repeatN(5, { H.pressButtons({ "start" }, 8), H.waitFrames(25) }),
  H.waitFrames(120),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(40) }),
  H.waitFrames(300),
  H.repeatN(3, { H.pressButtons({ "a" }, 8), H.waitFrames(60) }),
  H.waitUntilSoft(function()
    return map() == 270 and H.tileAligned() and bright() >= 15
  end, 3000, "landed_at_b"),
  H.waitFrames(60),
  H.call(function()
    H.assertEntryContract("mrf-save-room-v1")
    H.log(string.format("[lab] checkpoint boot done f%d map=%d", H.frame, map()))
  end),

  -- 2. down through the door to map 264, then the battle-70 entry point
  tapInto("down", function() return map() == 264 end, 12000,
    "save room -> door -> map 264"),
  H.waitFrames(60),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(map(), 264, "at the Ifrit/Shiva alcove")
    H.assertEq(H.fieldX(), 3, "entry point x")
    H.assertEq(H.fieldY(), 7, "entry point y")
    H.assertEq(sw(0x0060), 0, "$0060 CLEAR at the entry point")
    H.assertEq(H.readByte(0x1A69) & 0x06, 0,
      "neither IFRIT nor SHIVA owned yet")
    reconDump("pre-care")
  end),

  -- 3. the gen's own care (0.95), then bank the fixture, arms untouched
  H.fieldCare({ tag = "care before fixture", threshold = 0.95 }),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 3 and H.fieldY() == 7, true,
      "back at the entry point after care")
    reconDump("fixture")
  end),
  H.saveState("ifritlab_entry.mss"),
  -- reload-verify: capture-calm does not imply reload-calm
  (function()
    local saveReq, loadReq
    return seq({
      H.call(function() saveReq = H.requestSaveState() end),
      H.waitFrames(2),
      H.call(function()
        H.checkReq(saveReq, "fixture verify: capture")
        loadReq = H.requestLoadState(saveReq.blob)
      end),
      H.waitFrames(2),
      H.call(function() H.checkReq(loadReq, "fixture verify: reload") end),
      H.waitFrames(180),
      H.call(function()
        H.assertEq(map(), 264, "reload: still on map 264")
        H.assertEq(H.battleLoadStarted(), false, "reload: no battle pending")
        H.assertEq(H.dialogWaiting(), false, "reload: no dialog pending")
        H.assertEq(H.hasControl() and H.tileAligned(), true,
          "reload: controllable at rest")
        H.log(string.format(
          "[lab] ifritlab_entry.mss banked and reload-verified, f%d phase=%d",
          H.frame, H.readByte(0x021E)))
      end),
    })
  end)(),

  -- 4. recon fight: class-correct loadout, then battle 70 once
  H.call(function()
    armSeedWatch()
    armLossWatch()
  end),
  -- pierce for Ifrit's phase, slash (non-elemental) for Shiva's; the gen's
  -- own non-weapon slots (bag holds them: it equips these ids today)
  equipPref(LOCKE, { 0x04, 0x02, 0x01, 0x00 }, "LOCKE pierce dagger"),
  H.equipLoadout(LOCKE, { { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
    { tag = "LOCKE armor" }),
  equipPref(EDGAR, { 0x1F, 0x1D, 0x01, 0x00 }, "EDGAR pierce spear"),
  H.equipLoadout(EDGAR, { { 1, 0x5A }, { 2, 0x69 }, { 3, 0x84 } },
    { tag = "EDGAR armor" }),
  H.equipLoadout(SABIN, { { 0, 0x53 }, { 1, 0x5A }, { 2, 0x73 }, { 3, 0x86 } },
    { tag = "SABIN kit (MetalKnuckle: slash, non-elem)" }),
  equipPref(CELES, { 0x0B, 0x0A }, "CELES slash sword"),
  H.equipLoadout(CELES, { { 2, 0x6A }, { 3, 0x84 } }, { tag = "CELES armor" }),
  H.fieldCare({ tag = "care before recon fight", threshold = 0.95 }),
  H.navTo(3, 7, { maxFrames = 9000, playBattles = "flee" }),
  H.call(function()
    H.assertEq(H.fieldX() == 3 and H.fieldY() == 7, true,
      "at the entry point, armed for recon")
    reconDump("recon-armed")
    res.t0 = H.frame
    res.fenix0 = H.invCountOf(FENIX_DOWN)
    res.tonic0 = H.invCountOf(TONIC)
    res.potion0 = H.invCountOf(POTION)
    H.log(string.format("[lab] recon set-off phase=%d bag f/t/p=%d/%d/%d",
      H.readByte(0x021E), res.fenix0, res.tonic0, res.potion0))
  end),

  -- A into IFRIT -> battle 70 (the gen's own engage)
  H.driveUntil(function() return H.battleLoadStarted() end, 6000, {
    H.hold({ "a", "down" }), H.waitFrames(4), H.hold({ "down" }), H.waitFrames(4),
  }, "A into IFRIT -> battle 70"),
  H.release(),
  H.waitUntil(function() return H.battleActive() end, 900, "battle 70 active", 30),

  -- the instrumented fight
  (function()
    local ISLOT, SSLOT = nil, nil
    local F = H.newFightDriver("recon", { tactical = true, boost = true,
      bank = 3, items = true, healer = LOCKE, healPercent = 60, cadence = 12,
      nuke = { ICE_SPELL } })
    local hb = 0
    local lastSh, lastFld = {}, {}
    local sawBreak, swaps = false, 0
    local lost = nil
    local fightF, notBattle = 0, 0
    local MAXBATT = 90000
    return seq({
      H.call(function()
        local w = H.formationWords()
        H.log(string.format("[recon] formation = %04X %04X %04X %04X %04X %04X",
          w[1], w[2], w[3], w[4], w[5], w[6]))
        for m = 5, 0, -1 do
          if mspecies(m) == IFRIT then ISLOT = m end
          if mspecies(m) == SHIVA then SSLOT = m end
        end
        H.assertEq(ISLOT ~= nil, true, "an IFRIT slot resolved")
        H.assertEq(SSLOT ~= nil, true, "a SHIVA slot resolved")
        -- the absorb-guard question, answered directly at the source:
        -- which species does M.formationSpecies() list right now?
        local fs = {}
        for _, s in ipairs(H.formationSpecies()) do
          fs[#fs + 1] = string.format("s%d=$%04X", s.slot, s.species)
        end
        H.log(string.format(
          "[recon] formationSpecies at open: %s  (mask $3F45=%02X)",
          table.concat(fs, " "), H.readByte(0x3F45)))
      end),
      H.waitUntil(function() return onfield(ISLOT) == 1 end, 3600,
        "ifrit takes the stage", 10),
      H.waitFrames(90),
      H.driveUntil(function()
        if H.gameOverFired > 0 then lost = "gameover"; return true end
        if fightF >= MAXBATT then lost = "fight-timeout"; return true end
        if H.battleLoadStarted() or H.battleActive() then
          notBattle = 0
        else
          notBattle = notBattle + 1
        end
        return notBattle >= 90
      end, MAXBATT + 20000, {
        H.call(function()
          if H.gameOverFired > 0 then H.setPad({}); return end
          if H.battleLoadStarted() or H.battleActive() then
            fightF = fightF + 1
            res.bframes = res.bframes + 1
            trackDeaths()
          end
          hb = hb + 1
          -- shield-chip and swap edges, logged on change
          for _, mm in ipairs({ { ISLOT, "IFR" }, { SSLOT, "SHV" } }) do
            local m, nm = mm[1], mm[2]
            local s, f = mshields(m), onfield(m)
            if lastSh[m] ~= nil and s ~= lastSh[m] then
              H.log(string.format("[recon] %s shields %d -> %d at f%d "
                .. "(hp=%d tk=%d fld=%d)", nm, lastSh[m], s, H.frame,
                mhp(m), mticks(m), f))
            end
            if lastFld[m] ~= nil and f ~= lastFld[m] then
              swaps = swaps + 1
              H.log(string.format("[recon] %s %s the stage at f%d "
                .. "(hp=%d sh=%d tk=%d; swap edge #%d)", nm,
                f == 1 and "TAKES" or "LEAVES", H.frame,
                mhp(m), mshields(m), mticks(m), swaps))
            end
            lastSh[m], lastFld[m] = s, f
            if not sawBreak and s == 0 and mticks(m) ~= 0 then
              sawBreak = true
              H.log(string.format("[recon] first BREAK: %s at f%d "
                .. "(hp=%d tk=%d fld=%d)", nm, H.frame, mhp(m), mticks(m), f))
            end
          end
          if hb % 300 == 0 then
            H.log(string.format(
              "[recon] f%d ifr %d/sh%d/tk%d/fld%d | shv %d/sh%d/tk%d/fld%d "
              .. "| party %d,%d,%d,%d | bp %d,%d,%d,%d",
              H.frame, mhp(ISLOT), mshields(ISLOT), mticks(ISLOT), onfield(ISLOT),
              mhp(SSLOT), mshields(SSLOT), mticks(SSLOT), onfield(SSLOT),
              H.readWord(0x3BF4), H.readWord(0x3BF6),
              H.readWord(0x3BF8), H.readWord(0x3BFA),
              H.readByte(0x3E9C), H.readByte(0x3E9E),
              H.readByte(0x3EA0), H.readByte(0x3EA2)))
          end
          F.frame()
        end),
      }, "recon battle 70"),
      H.call(function()
        F.idle(); H.setPad({})
        res.fenix1 = H.invCountOf(FENIX_DOWN)
        res.tonic1 = H.invCountOf(TONIC)
        res.potion1 = H.invCountOf(POTION)
        H.log(string.format(
          "[recon] battle gone at f%d (lost=%s break=%s swaps=%d "
          .. "ifr end %d/sh%d shv end %d/sh%d)",
          H.frame, tostring(lost), tostring(sawBreak), swaps,
          mhp(ISLOT), mshields(ISLOT), mhp(SSLOT), mshields(SSLOT)))
      end),
      -- win tail: page dialogs until $0060 or give up
      (function()
        local giveUp, ph = 0, 0
        return H.driveUntil(function()
          if H.gameOverFired > 0 then lost = lost or "gameover"; return true end
          giveUp = giveUp + 1
          return sw(0x0060) == 1 or giveUp >= 3000
        end, 3200, {
          H.call(function()
            if H.gameOverFired > 0 then H.setPad({}); return end
            ph = (ph + 1) % 8
            if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
            else H.setPad({}) end
          end),
        }, "the win tail flips $0060 (or the loss shows itself)")
      end)(),
      H.call(function()
        H.setPad({})
        local won = H.gameOverFired == 0 and lost == nil and sw(0x0060) == 1
        local reason = won and "win" or (lost or "verify-failed")
        local standing = 1
        for _, c in ipairs({ LOCKE, EDGAR, SABIN, CELES }) do
          local hp, mx = H.charHp(c), H.charMaxHp(c)
          if not (hp > 0 and (H.charStatus1(c) & 0xC6) == 0 and hp > (mx >> 3)) then
            standing = 0
          end
        end
        local be = #res.seeds > 0 and string.format("$%02X", res.seeds[#res.seeds])
          or "none"
        H.log(string.format(
          "[result] lab=b70 strategy=recon-classfix seed=0 won=%d frames=%d "
          .. "bframes=%d deaths=%d fenix=%d tonic=%d potion=%d "
          .. "mp=%d,%d,%d,%d standing=%d attempts=1 be=%s nseeds=%d "
          .. "level=%s reason=%s",
          won and 1 or 0, H.frame - res.t0, res.bframes, res.deaths,
          res.fenix0 - (res.fenix1 or res.fenix0),
          res.tonic0 - (res.tonic1 or res.tonic0),
          res.potion0 - (res.potion1 or res.potion0),
          H.charMp(LOCKE), H.charMp(EDGAR), H.charMp(SABIN), H.charMp(CELES),
          standing, be, #res.seeds, partyLevels(), reason))
      end),
    })
  end)(),
})
