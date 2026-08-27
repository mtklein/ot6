-- probe_thamlab_healthy_flame.lua -- thamasa fire lab, healthy-level
-- experiment agent: ONE battle-79 (FlameEater) attempt from the HEALTHY
-- fixture (thamlab_flame_healthy.mss, probe_thamlab_grind.lua: the bake's
-- own route plus a Crescent Island world grind to L22+ before the fire).
--
-- Two strategies (@STRATEGY@):
--   nuke     the owner-directive kit through the lib driver: TERRA/LOCKE
--            boosted Ice (folds to Ice2, the AoE tier), STRAGO Aqua Rake
--            (opts.nuke={Ice2,Ice}, opts.nukeLore={3}) -- Ice2 is listed
--            first per the campaign protocol; under OT6's fold system the
--            upper tier never appears in the live list, so the entry is
--            inert and the Ice entry is the one that fires.
--   control  the gen's own control driver opts (tactical/boost/items/
--            cure/healer=TERRA/healPercent=60, no attack magic).
--
-- The @HOLD@ token is the seed knob: aligned frames of standing still
-- before stepping onto the (46,53) trigger ($021e ticks 1/frame, period
-- 60; the battle seeds $be = phase*4 at InitBattle).
--
-- PASSes whether the fight is won or lost -- this file measures, it does
-- not assert.  One machine-readable line per run, the brief's shape plus
-- level=t,l,s:
--   [result] lab=flame strategy=... seed=... won=... level=t,l,s ...

local H = dofile("tools/tests/lib/ot6.lua")
local STATE = "build/states/thamlab_flame_healthy.mss.lua"

local STRATEGY = "@STRATEGY@"
local HOLD = tonumber("@HOLD@") or 0
local BANK = tonumber("@BANK@") or 2
if STRATEGY:find("@") then STRATEGY = "nuke" end

local TERRA, LOCKE, STRAGO = 0, 1, 7
local ICE_SPELL, ICE2_SPELL, AQUA_RAKE_LORE = 0x01, 0x06, 3
local TONIC, POTION, FENIX_DOWN = 0xE8, 0xE9, 0xF0
local CONFIRM_BATTLE_GONE = 90

local function sw(id)
  return (H.readByte(0x1E80 + (id >> 3)) >> (id & 7)) & 1
end
local function lvl(c) return H.readByte(0x1600 + 37 * c + 0x08) end

-- per-entity battle HP, for the deaths count
local function bhp(e) return H.readWord(0x3BF4 + e * 2) end
local function bmaxhp(e) return H.readWord(0x3C1C + e * 2) end

local function newStrategyDriver()
  if STRATEGY == "nuke" then
    return H.newFightDriver("flame-healthy-nuke", {
      tactical = true, boost = true, bank = BANK,
      items = true, cure = true, healer = TERRA, healPercent = 60,
      nuke = { ICE2_SPELL, ICE_SPELL }, nukeLore = { AQUA_RAKE_LORE },
    })
  end
  if STRATEGY == "control" then
    return H.newFightDriver("flame-healthy-control", {
      tactical = true, boost = true, bank = 3,
      items = true, cure = true, healer = TERRA, healPercent = 60,
    })
  end
  error("unknown STRATEGY " .. STRATEGY, 0)
end
local F = newStrategyDriver()

local res = {
  seed = -1, won = 0, frames = 0, bframes = 0, deaths = 0,
  fenix = 0, tonic = 0, potion = 0, standing = 0, reason = "none",
}
local bag0 = {}
local f0 = 0
local wasDown = {}

H.run({ maxFrames = 400000, allowGameOver = true }, {
  H.loadState(STATE),
  H.waitFrames(30),
  H.call(function()
    H.log(string.format("[flame-healthy] booted at (%d,%d) map=%d phase=%d "
      .. "HOLD=%d BANK=%d strategy=%s levels T/L/S=%d/%d/%d hp %d/%d %d/%d "
      .. "%d/%d mp %d,%d,%d", H.fieldX(), H.fieldY(), H.mapId() & 0x1ff,
      H.readByte(0x021E), HOLD, BANK, STRATEGY,
      lvl(TERRA), lvl(LOCKE), lvl(STRAGO),
      H.charHp(TERRA), H.charMaxHp(TERRA), H.charHp(LOCKE), H.charMaxHp(LOCKE),
      H.charHp(STRAGO), H.charMaxHp(STRAGO),
      H.charMp(TERRA), H.charMp(LOCKE), H.charMp(STRAGO)))
    H.assertEq(sw(0x0090), 0, "$0090 clear: FlameEater not fought yet")
    for _, it in ipairs({ TONIC, POTION, FENIX_DOWN }) do
      bag0[it] = H.invCountOf(it)
    end
    f0 = H.frame
  end),
  -- the seed stagger: stand still HOLD frames; $021e keeps ticking
  H.waitFrames(HOLD),

  -- walk onto the trigger tile; the seed is read on the engage edge
  H.driveUntil(function()
    if H.battleLoadStarted() then
      if res.seed < 0 then
        res.seed = H.readByte(0x021E)
        H.log(string.format("[flame-healthy] engaged: seeded from $021e=%d",
          res.seed))
      end
      return true
    end
    return false
  end, 8000, {
    (function()
      local ph = 0
      return H.call(function()
        ph = (ph + 1) % 8
        if H.dialogWaiting() then
          H.setPad(ph < 4 and { a = true } or {})
        else
          H.setPad({ up = true })
        end
      end)
    end)(),
  }, "walk onto (46,53) -> battle 79"),

  -- the fight, played out by the driver; deaths counted on the 0-HP edge
  (function()
    local notBattle = 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then H.setPad({}); return true end
      if H.battleLoadStarted() or H.battleActive() then
        notBattle = 0
      else
        notBattle = notBattle + 1
      end
      return notBattle >= CONFIRM_BATTLE_GONE
    end, 200000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        res.bframes = res.bframes + 1
        for e = 0, 3 do
          if bmaxhp(e) > 0 then
            if bhp(e) == 0 and not wasDown[e] then
              wasDown[e] = true
              res.deaths = res.deaths + 1
            elseif bhp(e) > 0 then
              wasDown[e] = nil
            end
          end
        end
        F.frame()
      end),
    }, "FlameEater fight (" .. STRATEGY .. ", healthy levels)")
  end)(),
  H.call(function() F.idle() end),

  -- win tail: tap A until $0090 flips; a loss shows itself as the
  -- GameOver read-watch firing
  (function()
    local giveUp = 0
    return H.driveUntil(function()
      if H.gameOverFired > 0 then H.setPad({}); return true end
      giveUp = giveUp + 1
      return sw(0x0090) == 1 or giveUp >= 11800
    end, 12000, {
      H.call(function()
        if H.gameOverFired > 0 then H.setPad({}); return end
        local ph = giveUp % 8
        if not H.hasControl() then H.setPad(ph < 4 and { "a" } or {})
        else H.setPad({}) end
      end),
    }, "the win tail flips $0090 (or GameOver shows itself)")
  end)(),

  H.call(function()
    H.setPad({})
    res.frames = H.frame - f0
    res.won = sw(0x0090) == 1 and 1 or 0
    res.fenix = bag0[FENIX_DOWN] - H.invCountOf(FENIX_DOWN)
    res.tonic = bag0[TONIC] - H.invCountOf(TONIC)
    res.potion = bag0[POTION] - H.invCountOf(POTION)
    local standing = true
    for _, c in ipairs({ TERRA, LOCKE, STRAGO }) do
      if H.charHp(c) == 0 then standing = false end
    end
    res.standing = standing and 1 or 0
    res.reason = res.won == 1 and "win"
      or (H.gameOverFired > 0 and "gameover" or "tail-timeout")
    H.log(string.format(
      "[result] lab=flame strategy=healthy-%s seed=%d won=%d frames=%d "
      .. "bframes=%d deaths=%d fenix=%d tonic=%d potion=%d mp=%d,%d,%d "
      .. "standing=%d attempts=1 level=%d,%d,%d phase=%d reason=%s",
      STRATEGY, HOLD, res.won, res.frames, res.bframes, res.deaths, res.fenix,
      res.tonic, res.potion, H.charMp(TERRA), H.charMp(LOCKE),
      H.charMp(STRAGO), res.standing, lvl(TERRA), lvl(LOCKE), lvl(STRAGO),
      res.seed, res.reason))
  end),
})
