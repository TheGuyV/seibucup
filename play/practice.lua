-- Seibu Cup Soccer Online - practice game (practice.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online). All rights reserved.
-- SPDX-License-Identifier: LicenseRef-SeibuCupOnline-Proprietary
--
-- 세이부 컵 사커 온라인(seibucup.online)은 비영리 팬 사이트이며, 원작사 세이부 개발(Seibu Kaihatsu) 및 원작 권리자와 관계가 없습니다.
-- Seibu Cup Soccer Online (seibucup.online) is a non-commercial fan site, not affiliated with Seibu Kaihatsu or any rights holder of the original game.
--
-- 이 파일은 세이부 컵 사커 온라인의 런처와 웹 플레이에서 쓰기 위해서만 배포됩니다.
-- 허락 없이 수정하거나 다른 곳에 재배포할 수 없습니다.
-- This file is distributed only for use with the Seibu Cup Soccer Online launcher and web play.
-- It may not be modified or redistributed without permission.
local mem = manager.machine.devices[":maincpu"].spaces["program"]
local F = {}
for _, p in pairs(manager.machine.ioport.ports) do for n, f in pairs(p.fields) do F[n] = f end end
local MEN, STEP = 0x111e54, 0xdc
local CLOCK, CREDITS, PM = 0x109ef4, 0x1093a4, 0x109c6f
local SCORE_L, SCORE_R = 0x109eff, 0x109f47
local BALL = 0x113820
local BALL_V = 0x11382c

local BALL_H, BALL_AT_FEET, BALL_FREE = 0x1138a0, 0x132ca, 0x1306c
local OWNER = 0x1138ae
local nofix = os.getenv("PR_NOFIX") == "1"
local bot = os.getenv("PR_BOT") == "1"
local out = os.getenv("PR_OUT") and io.open(os.getenv("PR_OUT") .. "/practice.txt", "w") or nil
local function log(fmt, ...) if out then out:write(string.format(fmt, ...) .. "\n"); out:flush() end end
local function fx(a) return mem:read_i32(a) / 65536 end

PR = { n = 0, clock0 = nil, tick = -1000, parked = false }

__prclock = mem:install_write_tap(CLOCK, CLOCK + 1, "prclock", function(off, data, mask)
  if PR.clock0 and data < PR.clock0 then PR.tick = PR.n; return PR.clock0 end
end)

local TEXT, SPR = 0x102000, 0x107000
local function tcell(row, col) return TEXT + (row * 64 + col) * 2 end
PR_round = {}
__prjoin = mem:install_write_tap(tcell(5, 28), tcell(6, 38) + 1, "prjoin", function(off, data, mask)
  local col = ((off - TEXT) // 2) % 64
  if col < 28 or col > 38 or mask ~= 0xffff then return end

  if data ~= 0 and (data & 0xf000) ~= 0x8000 then return PR_round[off] or 0 end
  PR_round[off] = data
end)
__prcoin = mem:install_write_tap(tcell(29, 10), tcell(29, 30) + 1, "prcoin", function(off, data, mask)
  if mask == 0xffff and (data & 0xf000) == 0x7000 then return 0 end
end)
__prdots = mem:install_write_tap(SPR, SPR + 32 * 8 - 1, "prdots", function(off, data, mask)
  if not PR.parked or (off - SPR) % 8 ~= 6 or mask ~= 0xffff then return end
  if (data & 0x1ff) == 8 and mem:read_u16(off - 4) == 0xdf20 then return (data & 0xfe00) | 0x1f0 end
end)

local function home_cpu()
  for i = 11, 21 do
    local a = MEN + i * STEP
    if mem:read_u8(a + 0xc5) ~= 0x21 then
      mem:write_i32(a + 4, mem:read_u16(a + 0xd0) * 65536)
      mem:write_i32(a + 8, mem:read_u16(a + 0xd2) * 65536)
    end
  end
end

local function park_cpu()
  local own = mem:read_u32(OWNER) & 0xffffff

  if own >= MEN + 11 * STEP and own < MEN + 22 * STEP and mem:read_u32(BALL_H) == BALL_AT_FEET and not nofix
     and mem:read_u8(own + 0xc5) ~= 0x21 then
    PR.wait = (PR.wait or 0) + 1
    if PR.wait == 1 then log("%d CPU man %d has the ball: waiting for his pass", PR.n, (own - MEN) // STEP) end
    if PR.wait <= 90 then return end
  else
    if PR.wait and PR.wait <= 90 then log("%d the ball left the CPU man after %d frames: the men go", PR.n, PR.wait) end
    PR.wait = nil
  end
  for i = 11, 21 do
    local a = MEN + i * STEP
    if mem:read_u8(a + 0xc5) ~= 0x21 then
      if own == a and mem:read_u32(BALL_H) == BALL_AT_FEET and not nofix then
        log("%d CPU man %d had the ball at his feet (action %04x): set free at (%.0f,%.0f)", PR.n, i, mem:read_u16(a + 0x8c), fx(BALL), fx(BALL + 4))
        mem:write_u32(BALL_H, BALL_FREE)
        mem:write_u16(a + 0x8c, 0x8da6)
        mem:write_i32(BALL_V, 0); mem:write_i32(BALL_V + 4, 0); mem:write_i32(BALL_V + 8, 0)

        local me = mem:read_u32(0x10a230 + 4) & 0xffffff
        if me ~= 0 then mem:write_u32(OWNER, (mem:read_u32(OWNER) & 0xff000000) | me) end
        PR.rel = { x = fx(BALL), y = fx(BALL + 4), left = 20 }
      end
      mem:write_i32(a + 4, 300 * 65536)
      mem:write_i32(a + 8, (700 + (i - 11) * 60) * 65536)
      mem:write_i32(a + 0xc, 0)
    end
  end
end

__pr = emu.register_frame_done(function()
  local P = PR
  P.n = P.n + 1
  if P.rel and not nofix then
    local R = P.rel
    R.left = R.left - 1

    if (fx(BALL) < 900 or fx(BALL) > 1660) and math.abs(fx(BALL) - R.x) + math.abs(fx(BALL + 4) - R.y) > 30 then
      log("%d the ball jumped to (%.0f,%.0f) after the release: put back", P.n, fx(BALL), fx(BALL + 4))
      mem:write_u32(BALL_H, BALL_FREE)
      mem:write_i32(BALL, math.floor(R.x * 65536)); mem:write_i32(BALL + 4, math.floor(R.y * 65536)); mem:write_i32(BALL + 8, 0)
      mem:write_i32(BALL_V, 0); mem:write_i32(BALL_V + 4, 0); mem:write_i32(BALL_V + 8, 0)
    end
    R.x, R.y = fx(BALL), fx(BALL + 4)
    if R.left <= 0 then P.rel = nil end
  end

  if not P.clock0 then if mem:read_u8(CREDITS) < 3 then mem:write_u8(CREDITS, 3) end
  elseif mem:read_u8(CREDITS) ~= 0 then mem:write_u8(CREDITS, 0) end
  local start = (P.n >= 240 and P.n < 246)
  if bot then

    local n = P.n
    local sh, U, D, L, R = (n >= 420 and n < 424), false, false, false, false
    local man = mem:read_u32(0x10a230 + 4) & 0xffffff
    if n > 1300 and man ~= 0 then
      local mx, my, bx, by = fx(man + 4), fx(man + 8), fx(BALL), fx(BALL + 4)
      local dx, dy = bx - mx, by - my
      if math.abs(dx) + math.abs(dy) > 14 then
        U, D, L, R = dx < -6, dx > 6, dy < -6, dy > 6
      else
        R = true; U, D = mx > 1300, mx < 1260
        if my > 1450 and n % 20 == 0 then sh = true end
      end
    end
    F["P1 Shoot"]:set_value(sh and 1 or 0)
    F["P1 Up"]:set_value(U and 1 or 0); F["P1 Down"]:set_value(D and 1 or 0)
    F["P1 Left"]:set_value(L and 1 or 0); F["P1 Right"]:set_value(R and 1 or 0)
  end
  F["1 Player Start"]:set_value(start and 1 or 0)
  local clock = mem:read_u16(CLOCK)
  local inmatch = (mem:read_u8(PM) & 1) ~= 0 and clock > 0
  if inmatch then
    if not P.clock0 then P.clock0 = clock; log("match on at frame %d, clock %d", P.n, clock) end

    local bx, by = fx(BALL), fx(BALL + 4)
    local moved = P.spot and (math.abs(bx - P.spot[1]) + math.abs(by - P.spot[2]) > 12)
    if moved then P.tick = P.n end
    local play = (P.n - P.tick < 100)
    if os.getenv("PR_OUT") then
      if play and (bx < 985 or bx > 1575) and not P.out then P.out = true; log("%d ball over the touchline at x %.0f (score %d-%d) handler %05x owner %06x", P.n, bx, mem:read_u8(SCORE_L), mem:read_u8(SCORE_R), mem:read_u32(BALL_H), mem:read_u32(OWNER) & 0xffffff) end
      if bx >= 985 and bx <= 1575 then P.out = nil end
    end
    if play then park_cpu(); P.parked = true; P.spot = nil
    elseif P.parked then home_cpu(); P.parked = false; P.spot = nil; log("%d stoppage: CPU men back on their spots", P.n)
    elseif not P.spot and P.n - P.tick > 40 then P.spot = { bx, by } end
  end
  if P.n % 300 == 0 then
    log("%d clock=%d score=%d-%d ball=(%.0f,%.0f)", P.n, mem:read_u16(CLOCK), mem:read_u8(SCORE_L), mem:read_u8(SCORE_R), fx(BALL), fx(BALL + 4))
  end
  local snaps = os.getenv("PR_SNAPS")
  if snaps and (("," .. snaps .. ","):find("," .. P.n .. ",", 1, true)) then manager.machine.video:snapshot() end
  local stop = tonumber(os.getenv("PR_STOP") or "")
  if stop and P.n >= stop then manager.machine:exit() end
end)
