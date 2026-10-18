-- Seibu Cup Soccer Online - netplay script (netplay.lua)
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
local VERSION = 38

local function env(name, default)
  local v = os.getenv(name)
  if v == nil or v == "" then return default end
  return v
end

local cfg = {
  mode    = env("SCNP_MODE", "host"),
  addr    = env("SCNP_ADDR", nil),
  port    = tonumber(env("SCNP_PORT", "7000")),
  delay   = tonumber(env("SCNP_DELAY", "3")),
  players = tonumber(env("SCNP_PLAYERS", "2")),
  log     = env("SCNP_LOG", nil),
  slot    = tonumber(env("SCNP_SLOT", "0")),
  hud     = env("SCNP_HUD", "1") == "1",
  token   = env("SCNP_TOKEN", ""),
  teams   = env("SCNP_TEAMS", "1v1"),
  time    = env("SCNP_TIME", "150"),
  spectate = env("SCNP_SPECTATE", "0") == "1",
  spectators = tonumber(env("SCNP_SPECTATORS", "0")),
  web = env("SCNP_WEB", "0") == "1",
  lang    = env("SCNP_LANG", "en"),
  replay  = env("SCNP_REPLAY", nil),
  replay_dir = env("SCNP_REPLAY_DIR", nil),
}
local is_teams = (cfg.teams == "2v2")

SCNP_FREE = (cfg.mode ~= "replay")

SCNP_DIPTIME = os.getenv("SCNP_DIPTIME") == "1"
SCNP_PACE = (cfg.mode ~= "replay")
SCNP_RELOAD = nil
SCNP_FREE_ADD = 0

SCNP_PVE = { on = (cfg.teams == "pve"), dropped = {}, mark = {}, gone = {}, tries = {}, late = {}, live = {}, cur = nil, at = 0, next_try = 0,
             match = nil, base = nil, cont_at = nil }
if cfg.addr == nil then cfg.addr = (cfg.mode == "host") and "0.0.0.0" or "127.0.0.1" end
if cfg.players < 1 then cfg.players = 1 end
if cfg.players > 4 then cfg.players = 4 end

local is_replay  = (cfg.mode == "replay")
local is_relay   = (cfg.mode == "relay")
local is_host    = (cfg.mode == "host") or (is_relay and cfg.slot == 1)
local local_slot = is_host and 1 or 0
local is_spec    = cfg.spectate and not is_host
if is_spec then local_slot = cfg.slot end
local nplayers   = is_host and cfg.players or 0
if is_relay and not is_host then local_slot = cfg.slot end

local machine = manager.machine

local MAME_MINOR = tonumber((tostring(emu.app_version()):match("^%d+%.(%d+)"))) or 0
local function mame_bytes() return string.char(MAME_MINOR % 256, math.floor(MAME_MINOR / 256)) end
local function mame_str(m) return m > 0 and string.format("0.%d", m) or "?" end
local ioport  = machine.ioport
local input   = machine.input
local mem     = machine.devices[":maincpu"].spaces["program"]

local logf = cfg.log and io.open(cfg.log, "a") or nil
if cfg.log and not logf then print("[np] cannot open the log file " .. cfg.log) end
local function log(fmt, ...)
  local s = string.format("%s [np %s] ", os.date("%H:%M:%S"), cfg.mode) .. string.format(fmt, ...)
  print(s)
  if logf then logf:write(s, "\n"); logf:flush() end
end
local function status(fmt, ...)
  local s = string.format(fmt, ...)
  machine:popmessage(s)
  log("%s", s)
end

local FIELD_DEFS = {
  [1] = { {":PLAYERS12","P1 Up"},{":PLAYERS12","P1 Down"},{":PLAYERS12","P1 Left"},{":PLAYERS12","P1 Right"},
          {":PLAYERS12","P1 Shoot"},{":PLAYERS12","P1 Pass"},{":SYSTEM","1 Player Start"},{":COIN","Coin 1"} },
  [2] = { {":PLAYERS12","P2 Up"},{":PLAYERS12","P2 Down"},{":PLAYERS12","P2 Left"},{":PLAYERS12","P2 Right"},
          {":PLAYERS12","P2 Shoot"},{":PLAYERS12","P2 Pass"},{":SYSTEM","2 Players Start"},{":COIN","Coin 2"} },
  [3] = { {":PLAYERS34","P3 Up"},{":PLAYERS34","P3 Down"},{":PLAYERS34","P3 Left"},{":PLAYERS34","P3 Right"},
          {":PLAYERS34","P3 Shoot"},{":PLAYERS34","P3 Pass"},{":SYSTEM","3 Players Start"},{":PLAYERS34","Coin 3"} },
  [4] = { {":PLAYERS34","P4 Up"},{":PLAYERS34","P4 Down"},{":PLAYERS34","P4 Left"},{":PLAYERS34","P4 Right"},
          {":PLAYERS34","P4 Shoot"},{":PLAYERS34","P4 Pass"},{":SYSTEM","4 Players Start"},{":PLAYERS34","Coin 4"} },
}
local KEYSETS = {
  arrows = { "KEYCODE_UP","KEYCODE_DOWN","KEYCODE_LEFT","KEYCODE_RIGHT","KEYCODE_LCONTROL","KEYCODE_LALT","KEYCODE_1","KEYCODE_5" },
  wasd   = { "KEYCODE_W","KEYCODE_S","KEYCODE_A","KEYCODE_D","KEYCODE_F","KEYCODE_G","KEYCODE_2","KEYCODE_6" },
  ijkl   = { "KEYCODE_I","KEYCODE_K","KEYCODE_J","KEYCODE_L","KEYCODE_U","KEYCODE_O","KEYCODE_3","KEYCODE_7" },
  numpad = { "KEYCODE_8_PAD","KEYCODE_2_PAD","KEYCODE_4_PAD","KEYCODE_6_PAD","KEYCODE_0_PAD","KEYCODE_DEL_PAD","KEYCODE_4","KEYCODE_8" },
}
local keyset_name = env("SCNP_KEYSET", "own")
local key_profile = KEYSETS[keyset_name]
local CONTROL_NAMES = { "up", "down", "left", "right", "shoot", "pass", "start", "coin" }
local hud_ping = { nil, nil, nil, nil }
local hud_dev  = { 0, 0, 0, 0 }
local local_dev, local_dev_sent = 0, -1
local last_kbd_frame, last_joy_frame, dev_tick = -1000, -1000, 0

local fields = { {}, {}, {}, {} }
local extras = {}
local empty_seq = input:seq_from_tokens("NONE")

local frame = 0

SCNP_GAME = env("SCNP_GAME", "cupsoc")
if SCNP_GAME ~= "cupsocs" and SCNP_GAME ~= "cupsocs2" then SCNP_GAME = "cupsoc" end
SCNP_G = ({

  cupsoc  = { clock = 0x109d64, framectr = 0x109284, score_l = 0x109d6f, score_r = 0x109db7,
              team_l = 0x109d6e, team_r = 0x109db6, credits = 0x109294, latch = 0x100700, fpu = 72,
              pm = 0x109b37, tm = 0x109d6c, tc = 0x109d6d, pc = 0x109d55, ctl = 0x10a080 },

  cupsocs2 = { clock = 0x109ef4, framectr = 0x109394, score_l = 0x109eff, score_r = 0x109f47,
              team_l = 0x109efe, team_r = 0x109f46, credits = 0x1093a4, latch = 0x100740, fpu = 72,
              pm = 0x109c6f, tm = 0x109efc, tc = 0x109efd, pc = 0x109ee5, ctl = 0x10a230 },

  cupsocs = { clock = 0x109ef4, framectr = 0x109394, score_l = 0x109eff, score_r = 0x109f47,
              team_l = 0x109efe, team_r = 0x109f46, credits = 0x1093a4, latch = 0x100740, fpu = 60 },
})[SCNP_GAME]
local CLOCK_ADDR, FRAMECTR_ADDR, CLOCK_UNITS = SCNP_G.clock, SCNP_G.framectr, 90
if SCNP_PVE.on and not SCNP_G.pm then SCNP_PVE.on = false end

SCNP_DIFF = { v = math.max(0, math.min(3, tonumber(env("SCNP_DIFF", "3")) or 3)) }
function scnp_diff_apply(v)
  local n = 0
  for _, port in pairs(manager.machine.ioport.ports) do
    for name, f in pairs(port.fields) do
      if name == "Difficulty" and f.type_class == "dipswitch" then
        local ok = pcall(function() f.user_value = v end)
        if ok then n = n + 1 end
      end
    end
  end
  SCNP_DIFF.v = v
  log("difficulty: %s (DIP %d)%s", ({ [0] = "very hard", "hard", "easy", "normal" })[v] or "?", v, n == 0 and " - no Difficulty switch found" or "")
end
local clock_tap, beep_tap = nil, nil
local clock_secs, clock_units0, clock_spu = 150, 90, 150 / 90

local clock_run = env("SCNP_CLOCK", "stop") == "run"
clock_fpu, hud_tick_frame = 72, -100000
clock_start, clock_u0, clock_boundary, clock_ours = nil, 0, 1, false
result_written = false

local SOUND_CMD_ADDR, BEEP_CMD = SCNP_G.latch, 0x24
local beep_hold_fc = -1000
local beep_eating = false
local BEEP_KIND, BEEP_RED = 0x84, 10
beep_want, beep_inject = 0, false
local function apply_time_dips()
  local n = 0
  for _, port in pairs(ioport.ports) do
    for _, f in pairs(port.fields) do
      if f.type_class == "dipswitch" and f.name and f.name:sub(1, 4) == "Time" then
        local low = f.mask & (~f.mask + 1)
        local ok = pcall(function() f.user_value = low * 2 end)
        if ok then n = n + 1 end
      end
    end
  end
  log("time DIPs pinned to the fastest unit (%d fields)", n)
end

local BGM_TRACKS = { 0x38, 0x3a, 0x36, 0x3c }
local bgm_mode = SCNP_PVE.on and "original" or env("SCNP_BGM", "shuffle")
bgm_order, bgm_i, bgm_swap, bgm_pick, bgm_seed = {}, 0, nil, nil, 7

bgm_rand, bgm_fixed, bgm_sw, bgm_inject_mirror = nil, nil, nil, nil
BGM_CHANNELS = { 0x202a, 0x20ff, 0x214e, 0x219d, 0x21ec, 0x223b, 0x228a }

function scnp_bgm_want()
  if bgm_fixed then return bgm_fixed end
  if bgm_mode == "original" then return BGM_TRACKS[1] end
  return bgm_rand
end
local function bgm_shuffle(seed)
  local order = { table.unpack(BGM_TRACKS) }
  local s = seed & 0x7fffffff
  for i = #order, 2, -1 do
    s = (s * 1103515245 + 12345) & 0x7fffffff
    local j = (s >> 8) % i + 1
    order[i], order[j] = order[j], order[i]
  end
  return order
end
local function install_bgm_tap()
  if SCNP_PVE.on then return end
  local fixed = tonumber(bgm_mode, 16)
  if fixed then
    local known = false
    for _, t in ipairs(BGM_TRACKS) do if t == fixed then known = true end end
    if not known then log("BGM: unknown tune %s, playing the board's own", bgm_mode); fixed = nil; bgm_mode = "original" end
  end
  bgm_fixed = fixed

  bgm_seed = 7
  for i = 1, #(cfg.token or "") do bgm_seed = (bgm_seed * 31 + cfg.token:byte(i)) & 0x7fffffff end
  bgm_order = BGM_TRACKS

  scnp_bgm_tap = mem:install_write_tap(SOUND_CMD_ADDR, SOUND_CMD_ADDR + 5, "scnp_bgm", function(offset, data, mask)
    if offset == SOUND_CMD_ADDR then
      if bgm_sw then

        local w = scnp_bgm_switch_step(data == 0)
        if w then bgm_inject_mirror = ((w & 0xff) << 8) | (w >> 8); return w end
      end
      local num, kind = data & 0xff, data >> 8
      if num == BGM_TRACKS[1] and (kind == 0x84 or kind == 0x80) then
        if not bgm_rand then
          local s = (bgm_seed + mem:read_u16(FRAMECTR_ADDR) * 40503) & 0x7fffffff
          for _ = 1, 3 do s = (s * 1103515245 + 12345) & 0x7fffffff end
          bgm_rand = BGM_TRACKS[(s >> 8) % #BGM_TRACKS + 1]
          if not bgm_fixed and bgm_mode ~= "original" then log("BGM: this match plays %02x (random)", bgm_rand)
          else log("BGM: this match's random tune is %02x (not ours)", bgm_rand) end
        end
        if bgm_sw then bgm_sw = nil; log("BGM: the board restarts the round music itself - no switch needed") end
        local t = scnp_bgm_want() or num
        if t == num then bgm_swap = nil; return nil end
        bgm_swap = t
        return (kind << 8) | t
      elseif data ~= 0 then
        bgm_swap = nil
      end
    elseif offset == SOUND_CMD_ADDR + 4 then
      if bgm_inject_mirror then

        local m = bgm_inject_mirror; bgm_inject_mirror = nil
        return m
      end
      if bgm_swap and (data >> 8) == BGM_TRACKS[1] then

        local t = bgm_swap; bgm_swap = nil
        return (t << 8) | (data & 0xff)
      end
    end
  end)
  if bgm_fixed then log("BGM: fixed tune %02x", bgm_fixed)
  elseif bgm_mode == "original" then log("BGM: the board's own")
  else log("BGM: random, one tune per match") end
end

function scnp_bgm_channels()
  local ok, t = pcall(function()
    local z, r = manager.machine.devices[":audiocpu"].spaces["program"], {}
    for i, a in ipairs(BGM_CHANNELS) do r[i] = z:read_u8(a) end
    return r
  end)
  return ok and t or nil
end
function scnp_bgm_after_load()
  bgm_sw = nil; bgm_inject_mirror = nil; bgm_swap = nil
  if not scnp_bgm_tap then return end
  local ch, want = scnp_bgm_channels(), scnp_bgm_want()
  if not ch or not want then return end
  local round = false
  for _, t in ipairs(BGM_TRACKS) do if t == ch[2] then round = true end end
  local full = true
  for _, v in ipairs(ch) do if v ~= want then full = false end end
  if round and not full then
    bgm_sw = { want = want, t = 0, step = 1, tries = 1 }
    log("BGM: the loaded state plays %02x - switching to %02x", ch[2], want)
  end
end

function scnp_bgm_switch_step(idle)
  local S = bgm_sw
  S.t = S.t + 1
  if S.step <= 3 then
    if not idle or S.t < 2 then return nil end
    local w = (S.step == 1 and 0x82ff) or (S.step == 2 and 0x8022) or (0x8400 | S.want)
    S.step = S.step + 1; S.t = 0
    return w
  end
  if S.t < 20 then return nil end
  local ch, full = scnp_bgm_channels(), true
  for _, v in ipairs(ch or {}) do if v ~= S.want then full = false end end
  if full then
    log("BGM: now playing %02x on every channel (try %d)", S.want, S.tries); bgm_sw = nil
  elseif S.tries >= 3 then
    log("BGM: %02x did not take every channel after %d tries (%s) - the next kick-off restarts it", S.want, S.tries,
        table.concat((function() local r = {} for i, v in ipairs(ch or {}) do r[i] = string.format("%02x", v) end return r end)(), " "))
    bgm_sw = nil
  else
    S.tries = S.tries + 1; S.step = 1; S.t = 0
  end
  return nil
end

local SCNP_PAL = {
  TILE = 0x103000, SPR = 0x103800,
  GRASS = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x0124, 0x0000 },
  DIRT  = { 0x0CC6, 0x258C, 0x3E52, 0x5718, 0x6FDE, 0x3612, 0x3E54, 0x4695, 0x4AB7, 0x52F8, 0x5B3A, 0x637B, 0x679D, 0x6FDE, 0x0D2E, 0x0000 },

  P = {
  [0] = {
    { 0, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A68, 0x0A68, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 1, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0D70, 0x1DF4, 0x28E4, 0x3126, 0x3968, 0x41AA, 0x49EC, 0x4CE7, 0x5D6B, 0x6DEF, 0x1084, 0x0000 },
    { 6, 0x7589, 0x758A, 0x75AB, 0x75CC, 0x75ED, 0x760E, 0x762F, 0x7650, 0x7671, 0x7692, 0x76B3, 0x76D4, 0x76F5, 0x7716, 0x7737, 0x0000 },
    { 7, 0x5982, 0x5D83, 0x6184, 0x6585, 0x6986, 0x6D87, 0x7188, 0x7589, 0x7589, 0x7188, 0x6D87, 0x6986, 0x7589, 0x7188, 0x6986, 0x0000 },
    { 8, 0x5982, 0x5D83, 0x6184, 0x6585, 0x6986, 0x6585, 0x6184, 0x5D83, 0x6986, 0x6585, 0x6184, 0x5D83, 0x5982, 0x001F, 0x001F, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A68, 0x0A68, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x2CBE, 0x34FF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x02E5, 0x0327, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
    { 15, 0x029E, 0x02BF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x7A26, 0x7E47, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
  },
  [1] = {
    { 0, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A68, 0x0A68, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 1, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0D70, 0x1DF4, 0x28E4, 0x3126, 0x3968, 0x41AA, 0x49EC, 0x4CE7, 0x5D6B, 0x6DEF, 0x1084, 0x0000 },
    { 6, 0x698C, 0x61AF, 0x55D1, 0x4DF4, 0x41F7, 0x3A1A, 0x2E3C, 0x265F, 0x2E7F, 0x369F, 0x3EBF, 0x46DF, 0x4EFF, 0x571F, 0x5F3F, 0x0000 },
    { 7, 0x5982, 0x5D83, 0x5D85, 0x6186, 0x6188, 0x6589, 0x658B, 0x698C, 0x698C, 0x658B, 0x6589, 0x6188, 0x698C, 0x658B, 0x6188, 0x0000 },
    { 8, 0x5982, 0x5D83, 0x5D85, 0x6186, 0x6188, 0x6186, 0x5D85, 0x5D83, 0x6188, 0x6186, 0x5D85, 0x5D83, 0x5982, 0x001F, 0x001F, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A68, 0x0A68, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x2CBE, 0x34FF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x02E5, 0x0327, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
    { 15, 0x029E, 0x02BF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x7A26, 0x7E47, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
  },
  [2] = {
    { 0, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A71, 0x0A71, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 1, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0D70, 0x1DF4, 0x28E4, 0x3126, 0x3968, 0x41AA, 0x49EC, 0x4CE7, 0x5D6B, 0x6DEF, 0x1084, 0x0000 },
    { 6, 0x097F, 0x119F, 0x15BF, 0x1DDF, 0x21FF, 0x2A1F, 0x2E3F, 0x365F, 0x3A7F, 0x429F, 0x46BF, 0x4EDF, 0x52FF, 0x5B1F, 0x5F3F, 0x0000 },
    { 7, 0x0098, 0x00B9, 0x00DA, 0x00FB, 0x011C, 0x013D, 0x055E, 0x097F, 0x097F, 0x055E, 0x013D, 0x011C, 0x097F, 0x055E, 0x011C, 0x0000 },
    { 8, 0x0098, 0x00B9, 0x00DA, 0x00FB, 0x011C, 0x00FB, 0x00DA, 0x00B9, 0x011C, 0x00FB, 0x00DA, 0x00B9, 0x0098, 0x03FF, 0x03FF, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A71, 0x0A71, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x2CBE, 0x34FF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x02E5, 0x0327, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
    { 15, 0x029E, 0x02BF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x7A26, 0x7E47, 0x3968, 0x6F7A, 0x77BC, 0x20A2, 0x28E4, 0x3126, 0x3968, 0x0000 },
  },
  [3] = {
    { 0, 0x01B8, 0x05D9, 0x0DF9, 0x05FA, 0x0E1A, 0x163A, 0x1E5A, 0x32BB, 0x4AFC, 0x5F5D, 0x0DF9, 0x0DF9, 0x0DF9, 0x0DF9, 0x0000, 0x0000 },
    { 1, 0x01B8, 0x05D9, 0x0DF9, 0x05FA, 0x0E1A, 0x163A, 0x28E8, 0x312A, 0x396C, 0x41AE, 0x49F0, 0x4CE7, 0x5D6B, 0x6DEF, 0x1084, 0x0000 },
    { 6, 0x0097, 0x00B8, 0x00D9, 0x00FA, 0x011B, 0x013C, 0x055D, 0x097E, 0x119E, 0x15BE, 0x1DDE, 0x21FE, 0x2A1E, 0x2E3E, 0x365F, 0x0000 },
    { 7, 0x1C90, 0x1891, 0x1492, 0x1093, 0x0C94, 0x0895, 0x0496, 0x0097, 0x0097, 0x0496, 0x0895, 0x0C94, 0x0097, 0x0496, 0x0C94, 0x0000 },
    { 8, 0x1C90, 0x1891, 0x1492, 0x1093, 0x0C94, 0x1093, 0x1492, 0x1891, 0x0C94, 0x1093, 0x1492, 0x1891, 0x1C90, 0x03FF, 0x03FF, 0x0000 },
    { 10, 0x01B8, 0x05D9, 0x0DF9, 0x05FA, 0x0E1A, 0x163A, 0x1E5A, 0x32BB, 0x4AFC, 0x5F5D, 0x0DF9, 0x0DF9, 0x0DF9, 0x0DF9, 0x0000, 0x0000 },
    { 12, 0x2CBE, 0x34FF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x02E5, 0x0327, 0x396C, 0x6F7A, 0x77BC, 0x20A6, 0x28E8, 0x312A, 0x396C, 0x0000 },
    { 15, 0x029E, 0x02BF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x7A26, 0x7E47, 0x396C, 0x6F7A, 0x77BC, 0x20A6, 0x28E8, 0x312A, 0x396C, 0x0000 },
  },
  [4] = {
    { 0, 0x0140, 0x0181, 0x0183, 0x01A3, 0x0182, 0x01A4, 0x01C4, 0x1E09, 0x364E, 0x5293, 0x018A, 0x018A, 0x0180, 0x0180, 0x0000, 0x0000 },
    { 1, 0x0140, 0x0181, 0x0183, 0x01A3, 0x00C9, 0x094D, 0x1440, 0x1C81, 0x24C3, 0x2D05, 0x3547, 0x3842, 0x48C6, 0x594A, 0x0000, 0x0000 },
    { 6, 0x1C91, 0x1892, 0x1493, 0x1094, 0x0C95, 0x0896, 0x0497, 0x0098, 0x00B9, 0x00DA, 0x00FB, 0x011C, 0x013D, 0x055E, 0x097F, 0x0000 },
    { 7, 0x54EA, 0x4CEB, 0x44CC, 0x3CCD, 0x34AE, 0x2CAF, 0x2490, 0x1C91, 0x1C91, 0x2490, 0x2CAF, 0x34AE, 0x1C91, 0x2490, 0x2CAF, 0x0000 },
    { 8, 0x54EA, 0x4CEB, 0x44CC, 0x3CCD, 0x34AE, 0x6AD5, 0x6EF6, 0x7317, 0x28F4, 0x34F2, 0x40EF, 0x48ED, 0x54EA, 0x001F, 0x001F, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A71, 0x0A71, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x1819, 0x205A, 0x0216, 0x029A, 0x01C3, 0x0205, 0x0240, 0x0282, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
    { 15, 0x01F9, 0x021A, 0x0216, 0x029A, 0x01A3, 0x0205, 0x6581, 0x69A2, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
  },
  [5] = {
    { 0, 0x0140, 0x0181, 0x0183, 0x01A3, 0x0182, 0x01A4, 0x01C4, 0x1E09, 0x364E, 0x5293, 0x018A, 0x018A, 0x0180, 0x0180, 0x0000, 0x0000 },
    { 1, 0x0140, 0x0181, 0x0183, 0x01A3, 0x00C9, 0x094D, 0x1440, 0x1C81, 0x24C3, 0x2D05, 0x3547, 0x3842, 0x48C6, 0x594A, 0x0000, 0x0000 },
    { 6, 0x4CE5, 0x4D06, 0x5107, 0x5127, 0x5548, 0x5569, 0x596A, 0x598A, 0x59AB, 0x5DAC, 0x5DCD, 0x61EE, 0x620E, 0x660F, 0x6630, 0x0000 },
    { 7, 0x30E5, 0x34E5, 0x38E5, 0x3CE5, 0x40E5, 0x44E5, 0x48E5, 0x4CE5, 0x5947, 0x5D68, 0x6189, 0x65AA, 0x5527, 0x5127, 0x4927, 0x0000 },
    { 8, 0x30E5, 0x34E5, 0x38E5, 0x3CE5, 0x40E5, 0x5DAA, 0x61CB, 0x65EC, 0x4927, 0x5527, 0x6127, 0x6D48, 0x7969, 0x001F, 0x001F, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A71, 0x0A71, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x1819, 0x205A, 0x0216, 0x029A, 0x01C3, 0x0205, 0x0240, 0x0282, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
    { 15, 0x01F9, 0x021A, 0x0216, 0x029A, 0x01A3, 0x0205, 0x6581, 0x69A2, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
  },
  [6] = {
    { 0, 0x0140, 0x0181, 0x0183, 0x01A3, 0x0182, 0x01A4, 0x01C4, 0x1E09, 0x364E, 0x5293, 0x018A, 0x018A, 0x0180, 0x0180, 0x0000, 0x0000 },
    { 1, 0x0140, 0x0181, 0x0183, 0x01A3, 0x00C9, 0x094D, 0x1440, 0x1C81, 0x24C3, 0x2D05, 0x3547, 0x3842, 0x48C6, 0x594A, 0x0000, 0x0000 },
    { 6, 0x30E5, 0x34E5, 0x34E5, 0x38E5, 0x38E5, 0x3CE5, 0x3CE5, 0x40E5, 0x40E5, 0x44E5, 0x44E5, 0x48E5, 0x48E5, 0x4CE5, 0x4CE5, 0x0000 },
    { 7, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x59CE, 0x5DEF, 0x6210, 0x6631, 0x4D48, 0x5969, 0x658A, 0x0000 },
    { 8, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x30E5, 0x55CE, 0x59EF, 0x5E10, 0x5148, 0x5D48, 0x6948, 0x7569, 0x7DAB, 0x001F, 0x001F, 0x0000 },
    { 10, 0x0225, 0x0A66, 0x0E68, 0x1288, 0x0A67, 0x0E89, 0x12A9, 0x2EEE, 0x4F14, 0x6B59, 0x0A71, 0x0A71, 0x0A68, 0x0A68, 0x0000, 0x0000 },
    { 12, 0x1819, 0x205A, 0x0216, 0x029A, 0x01C3, 0x0205, 0x0240, 0x0282, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
    { 15, 0x01F9, 0x021A, 0x0216, 0x029A, 0x01A3, 0x0205, 0x6581, 0x69A2, 0x24C3, 0x5AD5, 0x6317, 0x0C00, 0x1440, 0x1C81, 0x24C3, 0x0000 },
  },
  [7] = {
    { 0, 0x3EA0, 0x42C0, 0x46E0, 0x42C0, 0x46E0, 0x4700, 0x4720, 0x5327, 0x5F4E, 0x6B55, 0x46E0, 0x46E0, 0x46E0, 0x46E0, 0x0000, 0x0000 },
    { 1, 0x3EA0, 0x42C0, 0x46E0, 0x42C0, 0x3A80, 0x3AA0, 0x2944, 0x3186, 0x39C8, 0x420A, 0x4A4C, 0x4CE7, 0x5D6B, 0x6DEF, 0x1084, 0x0000 },
    { 6, 0x7D89, 0x79AB, 0x71AC, 0x6DCE, 0x69EF, 0x6211, 0x5E12, 0x5A34, 0x5255, 0x4E57, 0x4678, 0x429A, 0x3EBB, 0x36BD, 0x32DE, 0x0000 },
    { 7, 0x6182, 0x6583, 0x6984, 0x6D85, 0x7186, 0x7587, 0x7988, 0x7D89, 0x7D89, 0x7988, 0x7587, 0x7186, 0x7D89, 0x7988, 0x7186, 0x0000 },
    { 8, 0x6182, 0x6583, 0x6984, 0x6D85, 0x7186, 0x6D85, 0x6984, 0x6583, 0x7186, 0x6D85, 0x6984, 0x6583, 0x6182, 0x001F, 0x001F, 0x0000 },
    { 10, 0x3EA0, 0x42C0, 0x46E0, 0x42C0, 0x46E0, 0x4700, 0x4720, 0x5327, 0x5F4E, 0x6B55, 0x46E0, 0x46E0, 0x46E0, 0x46E0, 0x0000, 0x0000 },
    { 12, 0x2CBE, 0x34FF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x02E5, 0x0327, 0x39C8, 0x6F7A, 0x77BC, 0x2102, 0x2944, 0x3186, 0x39C8, 0x0000 },
    { 15, 0x029E, 0x02BF, 0x02BB, 0x033F, 0x0268, 0x02AA, 0x7A26, 0x7E47, 0x39C8, 0x6F7A, 0x77BC, 0x2102, 0x2944, 0x3186, 0x39C8, 0x0000 },
  },
  },
}

SCNP_PAL.P[8] = {
    { 0, 0x3180, 0x35A0, 0x39A0, 0x35A0, 0x39A0, 0x39C0, 0x39C0, 0x41C4, 0x630D, 0x6B13, 0x39A0, 0x39A0, 0x39A0, 0x39A0, 0x0800, 0x0800 },
    { 1, 0x3180, 0x35A0, 0x39A0, 0x35A0, 0x3180, 0x3180, 0x24C2, 0x28E3, 0x3104, 0x3525, 0x3946, 0x3C84, 0x48C6, 0x5128, 0x1442, 0x0800 },
    { 6, 0x5CE5, 0x5906, 0x5506, 0x5107, 0x5128, 0x4929, 0x4929, 0x454A, 0x414B, 0x5235, 0x4A56, 0x4677, 0x4298, 0x3A9A, 0x369B, 0x0800 },
    { 7, 0x48E1, 0x4CE2, 0x50E2, 0x50E3, 0x54E3, 0x58E4, 0x58E4, 0x5CE5, 0x5CE5, 0x58E4, 0x58E4, 0x54E3, 0x5CE5, 0x58E4, 0x54E3, 0x0800 },
    { 8, 0x48E1, 0x4CE2, 0x50E2, 0x50E3, 0x54E3, 0x50E3, 0x50E2, 0x4CE2, 0x54E3, 0x50E3, 0x50E2, 0x4CE2, 0x48E1, 0x0810, 0x0810, 0x0800 },
    { 10, 0x3180, 0x35A0, 0x39A0, 0x35A0, 0x39A0, 0x39C0, 0x39C0, 0x41C4, 0x630D, 0x6B13, 0x39A0, 0x39A0, 0x39A0, 0x39A0, 0x0800, 0x0800 },
    { 12, 0x246F, 0x2C90, 0x0698, 0x06FC, 0x0964, 0x0985, 0x09A3, 0x09C4, 0x3104, 0x6F37, 0x7779, 0x1CA1, 0x24C2, 0x28E3, 0x3104, 0x0800 },
    { 15, 0x067B, 0x069C, 0x0698, 0x06FC, 0x0964, 0x0985, 0x5943, 0x5D44, 0x3104, 0x6F37, 0x7779, 0x1CA1, 0x24C2, 0x28E3, 0x3104, 0x0800 },
}
SCNP_PAL.P[9] = {
    { 0, 0x2D20, 0x2D20, 0x3140, 0x2D20, 0x3140, 0x3140, 0x3160, 0x3962, 0x630D, 0x6B13, 0x3140, 0x3140, 0x3140, 0x3140, 0x0C00, 0x0C00 },
    { 1, 0x2D20, 0x2D20, 0x3140, 0x2D20, 0x2900, 0x2920, 0x2081, 0x24A2, 0x28C3, 0x2CE3, 0x3104, 0x3462, 0x3CA4, 0x44C5, 0x1441, 0x0C00 },
    { 6, 0x50A3, 0x4CA4, 0x48A4, 0x44C5, 0x44C5, 0x40E6, 0x3CE6, 0x3CE7, 0x3907, 0x5235, 0x4A56, 0x4677, 0x4298, 0x3A9A, 0x369B, 0x0C00 },
    { 7, 0x40A1, 0x40A1, 0x44A1, 0x44A2, 0x48A2, 0x48A2, 0x4CA3, 0x50A3, 0x50A3, 0x4CA3, 0x48A2, 0x48A2, 0x50A3, 0x4CA3, 0x48A2, 0x0C00 },
    { 8, 0x40A1, 0x40A1, 0x44A1, 0x44A2, 0x48A2, 0x44A2, 0x44A1, 0x40A1, 0x48A2, 0x44A2, 0x44A1, 0x40A1, 0x40A1, 0x0C0B, 0x0C0B, 0x0C00 },
    { 10, 0x2D20, 0x2D20, 0x3140, 0x2D20, 0x3140, 0x3140, 0x3160, 0x3962, 0x630D, 0x6B13, 0x3140, 0x3140, 0x3140, 0x3140, 0x0C00, 0x0C00 },
    { 12, 0x244A, 0x286B, 0x0698, 0x06FC, 0x0D03, 0x0D23, 0x0D42, 0x0D62, 0x28C3, 0x6F37, 0x7779, 0x1C61, 0x2081, 0x24A2, 0x28C3, 0x0C00 },
    { 15, 0x067B, 0x069C, 0x0698, 0x06FC, 0x0D03, 0x0D23, 0x4CE2, 0x5102, 0x28C3, 0x6F37, 0x7779, 0x1C61, 0x2081, 0x24A2, 0x28C3, 0x0C00 },
}
SCNP_PAL.NIGHTSPR = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x0082, 0x0000 }

SCNP_NIGHT = { tex = {}, bm = {},
  LIGHTS = { { 400, 990 }, { 1008, 990 }, { 1617, 990 }, { 400, 1570 }, { 1008, 1570 }, { 1617, 1570 } },
  K = { [8] = { inside = 130, lit = 80, out = 170 }, [9] = { inside = 95, lit = 45, out = 195 },
        [12] = { inside = 70, lit = 55, out = 150, rx = 230, ry = 160, tint = 0xfff4e0,
                 lights = { { 560, 1160 }, { 1008, 1160 }, { 1456, 1160 }, { 560, 1400 }, { 1008, 1400 }, { 1456, 1400 } } } } }
function SCNP_NIGHT.build(st)
  local k = SCNP_NIGHT.K[st]
  if not k then return nil end
  if SCNP_NIGHT.tex[st] ~= nil then return SCNP_NIGHT.tex[st] or nil end
  local TW, TH = 288, 160
  local ok, bm = pcall(function() return emu.bitmap_argb32(TW, TH) end)
  if not ok or not bm then SCNP_NIGHT.tex[st] = false; log("night: no bitmap"); return nil end

  local lights, ex, ey = k.lights or SCNP_NIGHT.LIGHTS, {}, {}
  for j, p in ipairs(lights) do
    ex[j], ey[j] = {}, {}
    for tx = 0, TW - 1 do local dx = (-124 + tx * 8 - p[1]) / (k.rx or 250); ex[j][tx] = math.exp(-dx * dx) end
    for ty = 0, TH - 1 do local dy = (644 + ty * 8 - p[2]) / (k.ry or 210); ey[j][ty] = math.exp(-dy * dy) end
  end
  for ty = 0, TH - 1 do
    for tx = 0, TW - 1 do
      local wx, wy = -124 + tx * 8, 644 + ty * 8
      local ox = math.max(0, 400 - wx, wx - 1617); local oy = math.max(0, 1048 - wy, wy - 1512)
      local out = (ox == 0 and oy == 0) and 0 or math.min(1, math.sqrt(ox * ox + oy * oy) / 90)
      local L = 0
      for j = 1, #lights do L = L + ex[j][tx] * ey[j][ty] end
      local c
      if L > 0.55 and out < 0.5 then c = (math.floor(math.min(k.lit, 110 * (L - 0.55))) << 24) | (k.tint or 0xfff2d0)
      else c = math.floor(math.max(out * k.out, k.inside * (1 - math.min(1, L * 1.6)))) << 24 end
      bm:plot(tx, ty, c)
    end
  end
  local ok2, t = pcall(function() return machine.render:texture_alloc(bm) end)
  SCNP_NIGHT.bm[st] = bm; SCNP_NIGHT.tex[st] = (ok2 and t) or false
  log("night: light map for pitch %d %s", st, (ok2 and t) and "ready" or "failed")
  return (ok2 and t) or nil
end

function scnp_vignette(scr, w, h, rgb, amax)
  local n = 12
  for i = 0, n - 1 do
    local t = i / n
    local a = math.floor(amax * (1 - t) * (1 - t) / 4 + 0.5)
    if a > 0 then
      local c = (a << 24) | rgb
      local x0, y0, x1, y1 = w * 0.36 * t, h * 0.36 * t, w - w * 0.36 * t, h - h * 0.36 * t
      local dx, dy = w * 0.03, h * 0.03
      scr:draw_box(x0, y0, x1, y0 + dy, c, c); scr:draw_box(x0, y1 - dy, x1, y1, c, c)
      scr:draw_box(x0, y0 + dy, x0 + dx, y1 - dy, c, c); scr:draw_box(x1 - dx, y0 + dy, x1, y1 - dy, c, c)
    end
  end
end

function scnp_xmas_tree(scr, w, h, wx, wy, cx, cy, seed)
  local x, y = wx - cx, wy - cy
  if x < -30 or x > w + 30 or y < -10 or y > h + 70 then return end
  scr:draw_box(x - 2.5, y - 6, x + 2.5, y + 1, 0xff5a3414, 0xff5a3414)
  scr:draw_box(x - 2.5, y - 6, x - 1, y + 1, 0xff3e220c, 0xff3e220c)
  local tiers = { { 0, 13, 12 }, { 9, 11, 11 }, { 17, 8.5, 10 }, { 24, 6, 9 } }
  for t, tr in ipairs(tiers) do
    local by, hw, th = y - 5 - tr[1], tr[2], tr[3]
    for r = 0, th - 1 do
      local k = (r + 1) / th
      local half = hw * (1 - k) + 0.6
      local yy = by - r
      local dark = (r < 2) and 0xff0e3a18 or 0xff1a5a26
      scr:draw_box(x - half, yy - 1.3, x + half, yy + 0.3, dark, dark)
      scr:draw_box(x - half * 0.45, yy - 1.3, x + half * 0.15, yy + 0.3, 0xff24732f, 0xff24732f)
    end
    for r = 0, th - 1, 3 do
      local k = (r + 1) / th
      local half = hw * (1 - k) + 0.6
      scr:draw_box(x - half, by - r - 1.6, x - half + 1.8, by - r - 0.4, 0xffeef4ff, 0xffeef4ff)
    end
    scr:draw_box(x - hw + 0.5, by - 0.8, x + hw - 0.5, by + 0.4, 0xffd8e4f4, 0xffd8e4f4)
  end
  local balls = { { -7, -9, 0xffd01818 }, { 6, -12, 0xffe8b020 }, { -3, -17, 0xff2050d8 }, { 4, -22, 0xffd01818 },
                  { -5, -26, 0xffe8b020 }, { 2, -30, 0xffd01818 }, { 9, -7, 0xff2050d8 }, { -1, -12, 0xffe8b020 } }
  for i, b in ipairs(balls) do scr:draw_box(x + b[1] - 1, y + b[2] - 1, x + b[1] + 1, y + b[2] + 1, b[3], b[3]) end
  local lights = { { -9, -6 }, { 8, -10 }, { -6, -15 }, { 5, -18 }, { -3, -24 }, { 3, -27 }, { -1, -33 }, { 10, -5 }, { -10, -7 } }
  for i, l in ipairs(lights) do
    local on = math.floor(frame / 20 + i + seed) % 3
    local c = (on == 0) and 0xffffffa0 or ((on == 1) and 0xffffd040 or 0xff7a6a30)
    scr:draw_box(x + l[1] - 0.6, y + l[2] - 0.6, x + l[1] + 0.6, y + l[2] + 0.6, c, c)
  end
  local sy = y - 5 - 24 - 9 - 1
  scr:draw_box(x - 0.8, sy - 3, x + 0.8, sy + 1.5, 0xffffe040, 0xffffe040)
  scr:draw_box(x - 2.5, sy - 1.2, x + 2.5, sy + 0.2, 0xffffe040, 0xffffe040)
  scr:draw_box(x - 0.6, sy - 1.6, x + 0.6, sy + 0.6, 0xfffffff0, 0xfffffff0)
end
SCNP_PUDDLES = { { 560, 1130, 30, 9 }, { 820, 1420, 30, 9 }, { 1010, 1180, 30, 9 }, { 1190, 1350, 30, 9 },
                  { 1420, 1120, 30, 9 }, { 1500, 1440, 30, 9 }, { 700, 1290, 28, 8 }, { 1300, 1230, 26, 8 } }

function scnp_santa_suit()
  for i = 8, 13 do
    local a = 0x103800 + 9 * 32 + i * 2
    local c = mem:read_u16(a)
    if not SCNP_SANTA or SCNP_SANTA[i] ~= c then
      local g = math.max(c & 31, (c >> 5) & 31, (c >> 10) & 31)
      local r = math.min(31, math.floor(g * 1.9 + 5)); local o = math.min(31, math.floor(g * 0.22))
      local red = r | (o << 5) | (o << 10)
      if c ~= red then mem:write_u16(a, red) end
      SCNP_SANTA = SCNP_SANTA or {}; SCNP_SANTA[i] = red
    end
  end
end

function scnp_santa_hats(scr)
  for e = 0, 255 do
    local a = 0x107000 + e * 8
    local w0 = mem:read_u16(a)
    if (w0 & 0x8000) ~= 0 and (w0 & 0x3f) == 9 then
      local code = mem:read_u16(a + 2) & 0x3fff
      if code >= 4000 and code < 4100 then
        local sx, sy = ((w0 >> 10) & 7) + 1, ((w0 >> 7) & 7) + 1
        local x, y = mem:read_u16(a + 4) & 0x1ff, mem:read_u16(a + 6) & 0x1ff
        if x >= 0x180 then x = x - 0x200 end
        if y >= 0x180 then y = y - 0x200 end
        local fl = ((w0 >> 14) & 1) == 1 and -1 or 1
        local hx, hy = x + sx * 8, y + ((sy >= 3 and sx >= 3) and 13 or 4)
        for r = 0, 5 do
          local half = 4.2 - r * 0.62
          local ox = -fl * r * 0.55
          scr:draw_box(hx - half + ox, hy - r - 0.7, hx + half + ox, hy - r + 0.5, 0xffd81c1c, 0xffd81c1c)
        end
        scr:draw_box(hx - 4.8, hy - 0.2, hx + 4.8, hy + 1.6, 0xfff4f4f4, 0xfff4f4f4)
        scr:draw_box(hx - fl * 4.2 - 1.3, hy - 6.4, hx - fl * 4.2 + 1.3, hy - 4.0, 0xffffffff, 0xffffffff)
      end
    end
  end
end

function scnp_neon_boots()
  for l = 1, 6 do
    local a = 0x103800 + l * 32 + 14 * 2
    if mem:read_u16(a) ~= 0x03ea then mem:write_u16(a, 0x03ea) end
  end
end
function scnp_night_draw()
  if scnp_stage == 10 then scnp_santa_suit() elseif scnp_stage == 14 then scnp_neon_boots() end
  if scnp_stage < 8 or not clock_start then return end
  local scr = machine.screens[":screen"]
  if not scr then return end
  local w, h = scr.width or 320, scr.height or 240
  local cx, cy = 0, 0
  if SCNP_GAME ~= "cupsoc" then cx, cy = mem:read_i16(0x109450), mem:read_i16(0x109452) end
  if scnp_stage == 10 then

    for i = 1, 0 do
      local sp = 0.5 + (i % 4) * 0.22
      local x = ((i * 73 + math.sin(frame * 0.03 + i) * 6 - cx * (0.5 + sp * 0.4)) % (w + 8)) - 4
      local y = ((i * 137 + frame * sp - cy * (0.5 + sp * 0.4)) % (h + 8)) - 4
      local sz = (i % 3 == 0) and 2 or 1
      scr:draw_box(x, y, x + sz, y + sz, 0xf0ffffff, 0xf0ffffff)
    end

    if not (QC and QC.goalAt and frame - QC.goalAt < 1000) then
      for k, t in ipairs({ { 450, 1030 }, { 1086, 1030 }, { 1715, 1030 }, { 362, 1578 }, { 990, 1578 }, { 1619, 1578 } }) do
        scnp_xmas_tree(scr, w, h, t[1], t[2], cx, cy, k)
      end

    end

    return
  elseif scnp_stage == 11 then

    if not (QC and QC.goalAt and frame - QC.goalAt < 480) then
      for k, pd in ipairs(SCNP_PUDDLES) do
        local px, py = pd[1] - cx, pd[2] - cy
        if px > -40 and px < w + 40 and py > -20 and py < h + 20 then
          local rx, ry = pd[3], pd[4]

          scr:draw_box(px - rx, py - ry * 0.45, px + rx, py + ry * 0.45, 0x2a223448, 0x2a223448)
          scr:draw_box(px - rx * 0.82, py - ry * 0.78, px + rx * 0.82, py + ry * 0.78, 0x2a223448, 0x2a223448)
          scr:draw_box(px - rx * 0.5, py - ry, px + rx * 0.5, py + ry, 0x2a223448, 0x2a223448)
          local t = (frame + k * 37) % 45
          if t < 25 then
            local rr = 1 + t * 0.35
            local ox, oy = px + ((k * 13) % 9 - 4) * rx * 0.12, py + ((k * 7) % 5 - 2) * ry * 0.15
            local a = math.floor(0x70 * (1 - t / 25))
            local col = (a << 24) | 0xe8f2ff
            local prev = nil
            for q = 0, 12 do
              local an = q * math.pi / 6
              local qx, qy = ox + math.cos(an) * rr * 2, oy + math.sin(an) * rr * 0.7
              if prev then scr:draw_line(prev[1], prev[2], qx, qy, col) end
              prev = { qx, qy }
            end
          end
        end
      end
    end
    local n = math.floor(26 + 18 * math.sin(frame * 0.004) * math.sin(frame * 0.0017 + 1.3))
    for i = 1, n do
      local hx = (i * 7919 + 104729) % 1000 / 1000
      local hy = (i * 6271 + 15485) % 1000 / 1000
      local sp = 7 + ((i * 2654) % 5)
      local ln = 8 + ((i * 977) % 6)
      local x = (hx * (w + 60) - frame * sp * 0.33 - cx) % (w + 60) - 30
      local y = (hy * (h + 40) + frame * sp - cy) % (h + 40) - 20
      scr:draw_line(x, y, x - ln * 0.3, y + ln, 0x60c8dcff)
    end
    return
  elseif scnp_stage == 13 then

    return
  elseif scnp_stage == 14 then

    return
  elseif scnp_stage == 15 then
    do return end

    local cols = { { 0xffe06818, 0xff8a3a0a }, { 0xffc83a12, 0xff701c06 }, { 0xffa8580e, 0xff5a2c04 }, { 0xfff0b028, 0xff9a6810 } }
    local HW = { 1, 2, 3, 3, 2, 1 }
    for i = 1, 12 do
      local sp = 0.4 + (i % 5) * 0.15
      local ph = frame * (0.035 + (i % 3) * 0.01) + i * 1.7
      local x = ((i * 167 + math.sin(ph) * 16 - cx * (0.5 + sp * 0.4)) % (w + 16)) - 8
      local y = ((i * 263 + frame * sp * 0.8 - cy * (0.5 + sp * 0.4)) % (h + 16)) - 8
      local fw = 0.35 + 0.65 * math.abs(math.cos(ph * 1.6))
      local tilt = math.sin(ph) * 0.7
      local c = cols[(i % #cols) + 1]

      local ww, hh = 3.2 * fw, 3.4
      scr:draw_box(x - ww, y - 1.2, x + ww, y + 1.2, c[1], c[1])
      scr:draw_box(x - 1.4 * fw + tilt, y - hh, x + 1.4 * fw + tilt, y + hh, c[1], c[1])
      scr:draw_line(x - tilt, y + hh, x - tilt * 1.6, y + hh + 1.8, c[2])
    end
    return
  elseif scnp_stage == 17 then

    if SCNP_GAME ~= "cupsoc" then
      for i = 0, 21 do
        local o = 0x111e54 + i * 0xdc
        local mx, my = mem:read_i32(o + 8) / 65536, mem:read_i32(o + 4) / 65536
        do
          local spd = math.abs(mem:read_i32(o + 0x10) / 65536) + math.abs(mem:read_i32(o + 0x14) / 65536)
          local x, y = mx - cx, my - cy - 11
          if spd > 0.6 and spd < 20 and x > -10 and x < w + 10 and y > -10 and y < h + 10 then
            for d = 0, 3 do
              local t = (frame + d * 5 + i * 3) % 20
              local ang = (d / 3) * math.pi + i
              local dx, dy = math.cos(ang) * (2 + t * 0.3), -math.abs(math.sin(ang)) * (t * 0.4) + t * t * 0.02
              local a = math.floor(0x68 * (1 - t / 20))
              local sz = 0.8
              scr:draw_box(x + dx - sz, y + dy - sz, x + dx + sz, y + dy + sz, (a << 24) | 0xf4fcff, (a << 24) | 0xf4fcff)
            end
            local f = (frame + i * 4) % 12
            local r, a = 2.5 + f * 0.35, math.floor(0x38 * (1 - f / 12))
            local q0 = nil
            for q = 0, 12 do
              local an = q * math.pi / 6
              local qx, qy = x + math.cos(an) * r * 1.6, y + math.sin(an) * r * 0.55
              if q0 then scr:draw_line(q0[1], q0[2], qx, qy, (a << 24) | 0xe8f8ff) end
              q0 = { qx, qy }
            end
          end
        end
      end
    end
    return
  elseif scnp_stage == 16 then
    do return end

    for i = 1, 9 do
      local sp = 0.35 + (i % 4) * 0.12
      local ph = frame * (0.03 + (i % 3) * 0.008) + i * 2.3
      local x = ((i * 151 + math.sin(ph) * 22 - cx * (0.5 + sp * 0.4)) % (w + 16)) - 8
      local y = ((i * 239 + frame * sp * 0.55 - cy * (0.5 + sp * 0.4)) % (h + 16)) - 8
      if i % 3 == 0 then
        local a = ph * 0.8
        for k = 0, 4 do
          local t = a + k * 1.2566
          local px, py = x + math.cos(t) * 2.2, y + math.sin(t) * 2.2
          scr:draw_box(px - 1.3, py - 1.3, px + 1.3, py + 1.3, 0xffffc4da, 0xffffc4da)
        end
        scr:draw_box(x - 0.9, y - 0.9, x + 0.9, y + 0.9, 0xffff6f9c, 0xffff6f9c)
      else
        local fw = 0.4 + 0.6 * math.abs(math.cos(ph * 1.4))
        local tl = math.sin(ph) * 0.8
        scr:draw_box(x - 1.8 * fw, y - 1.1, x + 1.8 * fw, y + 1.1, 0xffffa8c8, 0xffffa8c8)
        scr:draw_box(x - 0.8 * fw + tl, y - 1.9, x + 0.8 * fw + tl, y + 1.9, 0xffffa8c8, 0xffffa8c8)
        scr:draw_box(x + tl - 0.6, y - 1.9, x + tl + 0.6, y - 0.9, 0xffffe2ee, 0xffffe2ee)
      end
    end
    return
  end
  if not SCNP_NIGHT.K[scnp_stage] or SCNP_GAME == "cupsoc" then return end
  local tx = SCNP_NIGHT.build(scnp_stage)
  if not tx then return end
  scr.container:draw_quad(tx, (-128 - cx) / w, (640 - cy) / h, (2176 - cx) / w, (1920 - cy) / h)
end

SCNP_PAL.P[10] = {
    { 0, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FDD, 0x7FDD, 0x189A, 0x189A, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7F17, 0x7F17 },
    { 1, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7F7A, 0x7F7B, 0x7F9B, 0x7FBC, 0x7FBD, 0x7F7A, 0x7F9B, 0x7FDD, 0x7F39, 0x7F17 },
    { 6, 0x7F9C, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBD, 0x7FDD, 0x7FDD, 0x7FDD, 0x7FDD, 0x189A, 0x189A, 0x189A, 0x189A, 0x189A, 0x189A, 0x7F17 },
    { 7, 0x7F7B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9C, 0x7F9C, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9C, 0x7F9B, 0x7F9B, 0x7F17 },
    { 8, 0x7F7B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F9B, 0x7F7B, 0x7F7A, 0x7F7A, 0x7F17 },
    { 10, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FDD, 0x7FDD, 0x189A, 0x189A, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7F17, 0x7F17 },
    { 12, 0x7F9C, 0x7FBC, 0x189A, 0x189A, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FDD, 0x7F9B, 0x189A, 0x189A, 0x7F59, 0x7F7A, 0x7F7B, 0x7F9B, 0x7F17 },
    { 15, 0x189A, 0x189A, 0x189A, 0x189A, 0x7FBC, 0x7FBC, 0x7FBC, 0x7FBC, 0x7F9B, 0x189A, 0x189A, 0x7F59, 0x7F7A, 0x7F7B, 0x7F9B, 0x7F17 },
}
SCNP_PAL.P[11] = {
    { 0, 0x2940, 0x2940, 0x2D60, 0x2940, 0x2D60, 0x2D60, 0x2D80, 0x3182, 0x52AB, 0x5EB1, 0x2D60, 0x2D60, 0x2D60, 0x2D60, 0x0820, 0x0820 },
    { 1, 0x2940, 0x2940, 0x2D60, 0x2940, 0x2520, 0x2540, 0x1CA1, 0x20C2, 0x24E2, 0x2903, 0x2D24, 0x3082, 0x38C3, 0x40E5, 0x1061, 0x0820 },
    { 6, 0x48C3, 0x44C3, 0x40C4, 0x40E4, 0x3CE5, 0x3905, 0x3905, 0x3506, 0x3126, 0x45F2, 0x3E13, 0x3A15, 0x3636, 0x2E37, 0x2E58, 0x0820 },
    { 7, 0x38C1, 0x3CC1, 0x3CC1, 0x40C2, 0x40C2, 0x44C2, 0x44C2, 0x48C3, 0x48C3, 0x44C2, 0x44C2, 0x40C2, 0x48C3, 0x44C2, 0x40C2, 0x0820 },
    { 8, 0x38C1, 0x3CC1, 0x3CC1, 0x40C2, 0x40C2, 0x40C2, 0x3CC1, 0x3CC1, 0x40C2, 0x40C2, 0x3CC1, 0x3CC1, 0x38C1, 0x0829, 0x0829, 0x0820 },
    { 10, 0x2940, 0x2940, 0x2D60, 0x2940, 0x2D60, 0x2D60, 0x2D80, 0x3182, 0x52AB, 0x5EB1, 0x2D60, 0x2D60, 0x2D60, 0x2D60, 0x0820, 0x0820 },
    { 12, 0x2069, 0x2489, 0x0236, 0x02B9, 0x0922, 0x0943, 0x0962, 0x0982, 0x24E2, 0x62D5, 0x6B16, 0x1881, 0x1CA1, 0x20C2, 0x24E2, 0x0820 },
    { 15, 0x0218, 0x0239, 0x0236, 0x02B9, 0x0922, 0x0943, 0x4502, 0x4922, 0x24E2, 0x62D5, 0x6B16, 0x1881, 0x1CA1, 0x20C2, 0x24E2, 0x0820 },
}
SCNP_PAL.P[12] = {
    { 0, 0x1DF7, 0x21F7, 0x21F8, 0x21F7, 0x21F8, 0x21F8, 0x2218, 0x223A, 0x7184, 0x7184, 0x21F8, 0x21F8, 0x21F8, 0x21F8, 0x154F, 0x154F },
    { 1, 0x1DF7, 0x21F7, 0x21F8, 0x21F7, 0x1DF7, 0x1DF7, 0x19B4, 0x1DB5, 0x1DD6, 0x1DF7, 0x2218, 0x19B4, 0x1DD6, 0x2218, 0x1972, 0x154F },
    { 6, 0x1DD7, 0x1DF7, 0x1DF7, 0x21F8, 0x2218, 0x2219, 0x2219, 0x2219, 0x223A, 0x7184, 0x7184, 0x7184, 0x7184, 0x7184, 0x7184, 0x154F },
    { 7, 0x1DB5, 0x1DD5, 0x1DD5, 0x1DD6, 0x1DD6, 0x1DD6, 0x1DD6, 0x1DD7, 0x1DD7, 0x1DD6, 0x1DD6, 0x1DD6, 0x1DD7, 0x1DD6, 0x1DD6, 0x154F },
    { 8, 0x1DB5, 0x1DD5, 0x1DD5, 0x1DD6, 0x1DD6, 0x1DD6, 0x1DD5, 0x1DD5, 0x1DD6, 0x1DD6, 0x1DD5, 0x1DD5, 0x1DB5, 0x1DB4, 0x1DB4, 0x154F },
    { 10, 0x1DF7, 0x21F7, 0x21F8, 0x21F7, 0x21F8, 0x21F8, 0x2218, 0x223A, 0x7184, 0x7184, 0x21F8, 0x21F8, 0x21F8, 0x21F8, 0x154F, 0x154F },
    { 12, 0x1DD7, 0x21F7, 0x7184, 0x7184, 0x1DF7, 0x21F8, 0x21F8, 0x2219, 0x1DD6, 0x7184, 0x7184, 0x1993, 0x19B4, 0x1DB5, 0x1DD6, 0x154F },
    { 15, 0x7184, 0x7184, 0x7184, 0x7184, 0x1DF7, 0x21F8, 0x21F8, 0x2218, 0x1DD6, 0x7184, 0x7184, 0x1993, 0x19B4, 0x1DB5, 0x1DD6, 0x154F },
}

SCNP_PAL.SPRX = { [8] = SCNP_PAL.NIGHTSPR, [9] = SCNP_PAL.NIGHTSPR, [10] = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x5E2E, 0x0000 }, [11] = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x0881, 0x0000 }, [12] = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x08A9, 0x0000 } }

;(function()
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b)
    r = math.max(0, math.min(31, math.floor(r + 0.5))); g = math.max(0, math.min(31, math.floor(g + 0.5))); b = math.max(0, math.min(31, math.floor(b + 0.5)))
    return r | (g << 5) | (b << 10)
  end
  local function pk(c)
    local r, g, b = sp(c); local l = (0.3 * r + 0.59 * g + 0.11 * b) / 31
    if l > 0.62 then return jn(31, 17, 3) end
    local v = 0.95
    return jn(7 * v, 4 * v, 11 * v)
  end
  local rows = {}
  for i, row in ipairs(SCNP_PAL.P[7]) do local t = { row[1] }; for w = 2, 17 do t[w] = pk(row[w]) end; rows[i] = t end
  SCNP_PAL.P[13] = rows
  local spr = {}; for w = 1, 16 do spr[w] = SCNP_PAL.NIGHTSPR[w] end
  spr[15] = jn(3, 1, 6)
  SCNP_PAL.SPRX[13] = spr
end)()

;(function()
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b)
    r = math.max(0, math.min(31, math.floor(r + 0.5))); g = math.max(0, math.min(31, math.floor(g + 0.5))); b = math.max(0, math.min(31, math.floor(b + 0.5)))
    return r | (g << 5) | (b << 10)
  end
  local function lu(c) local r, g, b = sp(c); return (0.3 * r + 0.59 * g + 0.11 * b) / 31 end
  local function ne(c)
    local l = lu(c)
    if l > 0.62 then return jn(6, 31, 31) end
    local v = 0.45 + 0.7 * l
    return jn(3 * v, 2 * v, 7 * v)
  end
  local rows = {}
  for i, row in ipairs(SCNP_PAL.P[7]) do local t = { row[1] }; for w = 2, 17 do t[w] = ne(row[w]) end; rows[i] = t end
  SCNP_PAL.P[14] = rows
  local spr = {}; for w = 1, 16 do spr[w] = SCNP_PAL.NIGHTSPR[w] end
  for w = 6, 14 do local l = lu(spr[w]); spr[w] = jn(31 * l + 6, 4 * l, 28 * l + 4) end
  spr[15] = jn(0, 0, 3)
  SCNP_PAL.SPRX[14] = spr
end)()

;(function()
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b)
    r = math.max(0, math.min(31, math.floor(r + 0.5))); g = math.max(0, math.min(31, math.floor(g + 0.5))); b = math.max(0, math.min(31, math.floor(b + 0.5)))
    return r | (g << 5) | (b << 10)
  end
  local function au(c)
    local r, g, b = sp(c); local l = (0.3 * r + 0.59 * g + 0.11 * b) / 31
    if l > 0.62 then return jn(30, 28, 22) end
    local v = 0.62 + 0.7 * l
    return jn(22 * v, 19 * v, 6 * v)
  end
  local rows = {}
  for i, row in ipairs(SCNP_PAL.P[7]) do local t = { row[1] }; for w = 2, 17 do t[w] = au(row[w]) end; rows[i] = t end
  SCNP_PAL.P[15] = rows
  local spr = {}; for w = 1, 16 do spr[w] = SCNP_PAL.GRASS[w] end
  spr[15] = jn(7, 5, 1)
  SCNP_PAL.SPRX[15] = spr
end)()

;(function()
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b)
    r = math.max(0, math.min(31, math.floor(r + 0.5))); g = math.max(0, math.min(31, math.floor(g + 0.5))); b = math.max(0, math.min(31, math.floor(b + 0.5)))
    return r | (g << 5) | (b << 10)
  end
  local function spg(c)
    local r, g, b = sp(c); local l = (0.3 * r + 0.59 * g + 0.11 * b) / 31
    if l > 0.62 then return jn(31, 31, 30) end
    local v = 0.4 + 1.45 * l
    return jn(13 * v, 25 * v, 9 * v)
  end
  local rows = {}
  for i, row in ipairs(SCNP_PAL.P[7]) do local t = { row[1] }; for w = 2, 17 do t[w] = spg(row[w]) end; rows[i] = t end
  SCNP_PAL.P[16] = rows
  local spr = {}; for w = 1, 16 do spr[w] = SCNP_PAL.GRASS[w] end
  spr[15] = jn(5, 11, 4)
  SCNP_PAL.SPRX[16] = spr
end)()

;(function()
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b)
    r = math.max(0, math.min(31, math.floor(r + 0.5))); g = math.max(0, math.min(31, math.floor(g + 0.5))); b = math.max(0, math.min(31, math.floor(b + 0.5)))
    return r | (g << 5) | (b << 10)
  end
  local function po(c)
    local r, g, b = sp(c); local l = (0.3 * r + 0.59 * g + 0.11 * b) / 31
    if l > 0.62 then return jn(30, 31, 31) end
    local v = 0.35 + 1.4 * l
    return jn(4 * v, 21 * v, 27 * v)
  end
  local rows = {}
  for i, row in ipairs(SCNP_PAL.P[7]) do local t = { row[1] }; for w = 2, 17 do t[w] = po(row[w]) end; rows[i] = t end
  SCNP_PAL.P[17] = rows
  local spr = {}; for w = 1, 16 do spr[w] = SCNP_PAL.GRASS[w] end
  spr[15] = jn(2, 8, 14)
  SCNP_PAL.SPRX[17] = spr
end)()
scnp_stage = SCNP_PVE.on and 0 or math.max(0, math.min(17, tonumber(env("SCNP_STAGE", "0")) or 0))
function scnp_install_stage_tap()

  if scnp_stage > 0 then log("stage: pitch of round %d", scnp_stage + 1) end
  if SCNP_NIGHT and SCNP_NIGHT.K[scnp_stage] then SCNP_NIGHT.build(scnp_stage) end
end

SCNP_STRIPES = { lines = nil, made = {}, w0 = {}, remap = nil, n = 0, save = nil }
;(function()
  local PO = { 0, 4, 8, 12 }
  local XO = { 3, 2, 1, 0, 19, 18, 17, 16, 515, 514, 513, 512, 531, 530, 529, 528 }
  local S = SCNP_STRIPES
  local function rd(R, code)
    local base, by = code * 128, {}
    for i = 0, 127 do by[i] = R:read_u8(base + i) end
    local px = {}
    for y = 0, 15 do
      local row = {}
      for x = 0, 15 do
        local v = 0
        for p = 1, 4 do
          local off = PO[p] + XO[x + 1] + y * 32
          v = v | (((by[off >> 3] >> (7 - (off & 7))) & 1) << (4 - p))
        end
        row[x] = v
      end
      px[y] = row
    end
    return px
  end
  local function wr(R, code, px)
    local by = {}
    for i = 0, 127 do by[i] = 0 end
    for y = 0, 15 do for x = 0, 15 do
      local v = px[y][x]
      for p = 1, 4 do
        if ((v >> (4 - p)) & 1) == 1 then local off = PO[p] + XO[x + 1] + y * 32; by[off >> 3] = by[off >> 3] | (1 << (7 - (off & 7))) end
      end
    end end
    local base = code * 128
    for i = 0, 127 do R:write_u8(base + i, by[i]) end
  end
  function scnp_stripes_make(code, bottom)
    if S.made[code] then return end
    local R = manager.machine.memory.regions[":sprite"]
    if not R then return end
    S.made[code] = true; S.n = S.n + 1
    local px = rd(R, code)
    for y = 0, 15 do for x = 0, 15 do
      local v = px[y][x]
      if v == 4 or v == 5 then px[y][x] = S.remap[v]
      elseif v >= 6 and v <= 10 then
        local bright = (v == 7 or v == 9 or v == 10)
        if (bottom and y >= 8) or ((x >> 1) & 1) == 1 then px[y][x] = bright and 4 or 5 end
      end
    end end
    wr(R, code + 0x2000, px)
  end
end)()
function scnp_stripes_install()
  local S = SCNP_STRIPES
  if S.tap or SCNP_GAME ~= "cupsocs2" or not manager.machine.memory.regions[":sprite"] then return end
  S.tap = mem:install_write_tap(0x107000, 0x1077ff, "scnp_stripes", function(offset, data, mask)
    local rel = offset - 0x107000
    local e, w = rel >> 3, (rel >> 1) & 3
    if w == 0 then S.w0[e] = data; return nil end
    if w ~= 1 or not S.lines then return nil end
    local w0 = S.w0[e] or mem:read_u16(0x107000 + e * 8)
    if (w0 & 0x8000) == 0 or not S.lines[w0 & 0x3f] then return nil end
    local code = data & 0x3fff
    if code >= 0x2000 then return nil end
    local sx, sy = ((w0 >> 10) & 7) + 1, ((w0 >> 7) & 7) + 1
    local k = 0
    for ax = 0, sx - 1 do for ay = 0, sy - 1 do scnp_stripes_make(code + k, sy >= 2 and ay == sy - 1); k = k + 1 end end
    return (data & 0xc000) | (code + 0x2000)
  end)
end

function scnp_stripes_step()
  local S = SCNP_STRIPES
  if not S.tap then return end
  local tl, tr = mem:read_u8(SCNP_G.team_l), mem:read_u8(SCNP_G.team_r)
  local function col(l, i) local c = mem:read_u16(0x103800 + l * 32 + i * 2); return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  if S.lines and ((tl ~= 8 and tr ~= 8) or mem:read_u8(0x109c75) == 2) then
    for a, v in pairs(S.save) do mem:write_u16(a, v) end
    S.lines, S.save = nil, nil
    log("stripes: off")
    return
  end
  if not S.lines then
    if mem:read_u16(CLOCK_ADDR) == 0 or mem:read_u8(0x109c75) == 2 then return end

    local cl = SCNP_COSTUME.on and SCNP_COSTUME.seat[scnp_seat_of(1)] ~= nil
    local cr = SCNP_COSTUME.on and SCNP_COSTUME.seat[scnp_seat_of(2)] ~= nil
    if tl == 8 and not cl then S.lines = { [1] = true, [2] = true, [3] = true }
    elseif tr == 8 and not cr and (not SCNP_SEL.mirror or tl ~= 8 or cl) then S.lines = { [4] = true, [5] = true, [6] = true } end
    if not S.lines then return end
    local l0 = S.lines[1] and 1 or 4
    S.remap, S.save = {}, {}
    for _, v in ipairs({ 4, 5 }) do
      local r, g, b = col(l0, v); local best, bi = 1e9, 0
      for _, j in ipairs({ 0, 1, 2, 3, 11, 12, 13, 14 }) do
        local r2, g2, b2 = col(l0, j); local d = (r - r2) ^ 2 + (g - g2) ^ 2 + (b - b2) ^ 2
        if d < best then best, bi = d, j end
      end
      S.remap[v] = bi
    end
    for l in pairs(S.lines) do for _, i in ipairs({ 4, 5 }) do local a = 0x103800 + l * 32 + i * 2; S.save[a] = mem:read_u16(a) end end
    log("stripes: Argentina on lines %d-%d (4 -> %d, 5 -> %d) at frame %d", l0, l0 + 2, S.remap[4], S.remap[5], frame)
  end
  for l in pairs(S.lines) do
    local a4, a5 = 0x103800 + l * 32 + 4 * 2, 0x103800 + l * 32 + 5 * 2
    if mem:read_u16(a4) ~= 0x7fff then mem:write_u16(a4, 0x7fff) end
    local g = 21 | (22 << 5) | (24 << 10)
    if mem:read_u16(a5) ~= g then mem:write_u16(a5, g) end
  end
end
scnp_stripes_install()

SCNP_COMIC = {
  W = {
    slide = { w = 60, h = 20, s = { 1,6,7, 2,5,7, 2,13,15, 2,22,25, 2,30,32, 2,38,43, 2,47,49, 2,54,56, 3,2,10, 3,13,15, 3,20,26, 3,30,32, 3,37,44, 3,47,49, 3,54,56, 4,2,10, 4,13,15, 4,20,22, 4,25,27, 4,30,32, 4,36,38, 4,43,45, 4,47,49, 4,54,56, 5,7,10, 5,13,15, 5,19,21, 5,25,27, 5,30,32, 5,36,38, 5,43,45, 5,47,49, 5,54,56, 6,6,9, 6,13,15, 6,19,21, 6,25,27, 6,30,32, 6,36,38, 6,43,45, 6,47,51, 6,54,56, 7,5,8, 7,13,17, 7,19,21, 7,25,27, 7,30,32, 7,36,38, 7,43,45, 7,47,51, 7,54,56, 8,4,9, 8,13,17, 8,19,21, 8,25,27, 8,30,32, 8,36,38, 8,43,45, 8,47,49, 8,54,56, 9,3,5, 9,8,10, 9,13,15, 9,19,21, 9,25,27, 9,30,34, 9,37,44, 9,47,49, 9,54,56, 10,2,4, 10,9,10, 10,13,15, 10,19,21, 10,25,27, 10,30,34, 10,38,43, 10,47,49, 10,54,56, 11,2,3, 11,6,7, 11,10,10, 11,13,15, 11,19,21, 11,25,27, 11,30,32, 11,47,49, 11,54,56, 12,2,2, 12,5,7, 12,13,15, 12,19,21, 12,25,27, 12,30,32, 12,47,49, 12,54,56, 13,5,7, 13,13,15, 13,19,21, 13,25,27, 13,30,32, 13,37,49, 13,54,56, 14,5,7, 14,13,15, 14,19,21, 14,25,27, 14,30,32, 14,37,49, 15,5,7, 15,13,15, 15,20,22, 15,25,27, 15,30,32, 15,47,49, 15,54,56, 16,2,15, 16,20,26, 16,30,32, 16,47,49, 16,54,56, 17,2,15, 17,22,25, 17,30,32, 17,47,49, 17,54,56, 18,47,48 } },
    header = { w = 26, h = 19, s = { 1,2,11, 1,14,15, 1,20,22, 2,2,11, 2,14,15, 2,20,22, 3,3,5, 3,8,9, 3,14,15, 3,20,22, 4,3,5, 4,8,9, 4,14,15, 4,20,22, 5,3,5, 5,8,9, 5,11,15, 5,20,22, 6,3,5, 6,8,9, 6,11,15, 6,20,22, 7,3,5, 7,8,9, 7,14,15, 7,20,22, 8,2,11, 8,14,15, 8,20,22, 9,2,11, 9,14,15, 9,20,22, 10,14,15, 10,20,22, 11,14,15, 11,20,22, 12,3,15, 12,20,22, 13,3,15, 14,14,15, 14,20,22, 15,13,15, 15,20,22, 16,13,15, 16,20,22, 17,13,15 } },
    shot = { w = 26, h = 19, s = { 2,2,4, 2,6,7, 2,9,11, 2,14,15, 2,20,22, 3,2,4, 3,6,7, 3,9,11, 3,14,15, 3,20,22, 4,2,11, 4,14,15, 4,20,22, 5,2,15, 5,20,22, 6,2,4, 6,6,7, 6,9,15, 6,20,22, 7,2,4, 7,6,7, 7,9,11, 7,14,15, 7,20,22, 8,2,4, 8,6,7, 8,9,11, 8,14,15, 8,20,22, 9,2,11, 9,14,15, 9,20,22, 10,2,11, 10,14,15, 10,20,22, 11,20,22, 12,4,14, 12,20,22, 13,3,15, 13,20,22, 14,3,5, 14,14,15, 15,3,5, 15,14,15, 15,20,22, 16,3,15, 16,20,22, 17,4,14, 17,20,22 } },
    overhead = { w = 43, h = 18, s = { 1,2,11, 1,13,15, 1,21,25, 1,30,32, 1,37,39, 2,2,11, 2,13,15, 2,20,26, 2,30,32, 2,37,39, 3,9,11, 3,13,15, 3,19,21, 3,25,27, 3,30,32, 3,37,39, 4,9,11, 4,13,15, 4,19,21, 4,26,27, 4,30,34, 4,37,39, 5,9,11, 5,13,15, 5,19,21, 5,26,27, 5,30,34, 5,37,39, 6,2,11, 6,13,17, 6,19,21, 6,25,27, 6,30,32, 6,37,39, 7,2,11, 7,13,17, 7,20,26, 7,30,32, 7,37,39, 8,9,11, 8,13,15, 8,21,25, 8,30,32, 8,37,39, 9,9,11, 9,13,15, 9,37,39, 10,5,6, 10,9,11, 10,13,15, 10,37,39, 11,5,6, 11,9,11, 11,13,15, 11,21,31, 11,37,39, 12,5,6, 12,13,15, 12,20,32, 12,37,39, 13,5,6, 13,13,15, 13,20,21, 13,31,32, 14,5,6, 14,13,15, 14,20,21, 14,31,32, 14,37,39, 15,2,15, 15,20,32, 15,37,39, 16,2,15, 16,21,31, 16,37,39 } },
    flykick = { w = 43, h = 20, s = { 2,6,8, 2,14,15, 2,21,25, 2,31,32, 2,37,39, 3,2,11, 3,14,15, 3,20,26, 3,31,32, 3,37,39, 4,2,11, 4,14,15, 4,19,21, 4,25,27, 4,31,32, 4,37,39, 5,3,5, 5,9,10, 5,14,15, 5,19,21, 5,25,27, 5,31,32, 5,37,39, 6,3,5, 6,9,11, 6,14,15, 6,19,21, 6,25,27, 6,31,32, 6,37,39, 7,3,5, 7,9,11, 7,14,15, 7,19,21, 7,25,27, 7,31,32, 7,37,39, 8,3,10, 8,14,15, 8,20,26, 8,31,32, 8,37,39, 9,4,9, 9,14,15, 9,21,25, 9,31,32, 9,37,39, 10,14,15, 10,31,32, 10,37,39, 11,14,15, 11,31,32, 11,37,39, 12,2,15, 12,31,32, 12,37,39, 13,2,15, 13,20,32, 13,37,39, 14,6,8, 14,14,15, 14,20,32, 15,6,8, 15,14,15, 15,31,32, 15,37,39, 16,6,8, 16,14,15, 16,30,32, 16,37,39, 17,6,8, 17,14,15, 17,30,32, 17,37,39, 18,6,7, 18,14,15, 18,30,32 } },
  },
  K = { slide =    { 0xffffffff, 0xffff781e, 0xffffd600 },
        header =   { 0xffffffff, 0xff3caaff, 0xffffd600 },
        shot =     { 0xfffff078, 0xfff02828, 0xffffffff },
        overhead = { 0xffffffff, 0xffb43cf0, 0xffffd600 },
        flykick =  { 0xffffffff, 0xff28c878, 0xffffd600 } },
  ACT = { [0xbe5c] = "slide", [0x9f9a] = "overhead", [0xa73e] = "flykick" },
  pops = {}, act = {}, toucher = nil, kick = nil, LIFE = 28, on = false,
}
SCNP_COMIC.on = env("SCNP_COMIC", "") == "1"

SCNP_COMIC.MAXDRAW = 2
for _, W in pairs(SCNP_COMIC.W) do
  local rows, rects, open = {}, {}, {}
  for i = 1, #W.s, 3 do rows[#rows + 1] = { W.s[i], W.s[i + 1], W.s[i + 2] } end
  table.sort(rows, function(p, q) if p[1] ~= q[1] then return p[1] < q[1] end return p[2] < q[2] end)
  for _, r in ipairs(rows) do
    local k = r[2] * 1000 + r[3]
    local o = open[k]
    if o and o[2] == r[1] - 1 then o[2] = r[1]
    else o = { r[1], r[1], r[2], r[3] }; rects[#rects + 1] = o; open[k] = o end
  end
  W.r = rects
end

function scnp_comic_step()
  local C = SCNP_COMIC
  if not C.on or SCNP_GAME == "cupsoc" then return end
  local function add(kind, x, y, z)
    C.pops[#C.pops + 1] = { kind = kind, f0 = frame, x = x, y = y, z = z, k = #C.pops + frame }
    if #C.pops > 6 then table.remove(C.pops, 1) end
  end
  for i = 0, 21 do
    local o = 0x111e54 + i * 0xdc
    local a = mem:read_u16(o + 0x8c)
    if a ~= C.act[i] and C.ACT[a] and C.act[i] ~= nil then
      add(C.ACT[a], mem:read_i32(o + 8) / 65536, mem:read_i32(o + 4) / 65536, mem:read_i32(o + 0xc) / 65536 + 22)
    end
    C.act[i] = a
  end
  local b = 0x11381c
  local p = mem:read_u32(0x1138ae) & 0xffffff
  local hi = mem:read_u16(b + 0xc8) >> 8
  local bz = mem:read_i32(b + 0xc) / 65536
  local bx, by = mem:read_i32(b + 8) / 65536, mem:read_i32(b + 4) / 65536
  local sp = C.bx and math.sqrt((bx - C.bx) ^ 2 + (by - C.by) ^ 2) or 0
  local kicked = C.bsp ~= nil and sp >= 6.5 and sp < 30 and sp > C.bsp + 1.5
  if C.kick ~= nil and (p ~= C.toucher or hi ~= C.kick) and p >= 0x111e54 and p < 0x111e54 + 22 * 0xdc
     and mem:read_u16(p + 0x8c) == 0xa654 and bz >= 25 then
    add("header", mem:read_i32(b + 8) / 65536, mem:read_i32(b + 4) / 65536, bz)
  elseif C.kick ~= nil and frame - (C.shotAt or -99) > 12 and (kicked or (hi ~= C.kick and (hi == 0x33 or hi == 0x4a or hi == 0x4b or hi == 0x5d))) then

    add("shot", bx, by, bz); C.shotAt = frame
  end
  C.toucher, C.kick = p, hi
  C.bx, C.by, C.bsp = bx, by, sp
end

function scnp_comic_fill(scr, pts, col, step)
  local y0, y1 = 1e9, -1e9
  for _, q in ipairs(pts) do if q[2] < y0 then y0 = q[2] end; if q[2] > y1 then y1 = q[2] end end
  local n = #pts
  for y = y0, y1, step do
    local yc = y + step / 2
    local xs = {}
    for i = 1, n do
      local a, b = pts[i], pts[i % n + 1]
      if (a[2] <= yc and b[2] > yc) or (b[2] <= yc and a[2] > yc) then
        xs[#xs + 1] = a[1] + (yc - a[2]) / (b[2] - a[2]) * (b[1] - a[1])
      end
    end
    table.sort(xs)
    for i = 1, #xs - 1, 2 do scr:draw_box(xs[i], y, xs[i + 1], y + step, col, col) end
  end
end
function scnp_comic_draw()
  local C = SCNP_COMIC
  if not C.on or #C.pops == 0 then return end
  local scr = machine.screens[":screen"]
  if not scr then return end
  local w, h = scr.width or 320, scr.height or 240
  local cx, cy = mem:read_i16(0x109450), mem:read_i16(0x109452)
  local keep = {}
  local live = 0
  for _, P in ipairs(C.pops) do local t = frame - P.f0; if t >= 0 and t < C.LIFE then live = live + 1 end end
  for _, P in ipairs(C.pops) do
    local t = frame - P.f0
    if t >= 0 and t < C.LIFE then
      keep[#keep + 1] = P
      live = live - 1
    end
    if t >= 0 and t < C.LIFE and live < C.MAXDRAW then
      local s = t < 4 and (0.35 + 0.8 * t / 4) or (t < 8 and (1.15 - 0.15 * (t - 4) / 4) or 1)
      local al = t < 18 and 1 or math.max(0, 1 - (t - 18) / 10)
      local function A(c) return (math.floor(((c >> 24) & 0xff) * al) << 24) | (c & 0xffffff) end
      local hx, hy = P.x - cx, P.y - cy - P.z
      local col = C.K[P.kind]

      if t < 8 then
        for i = 0, 7 do
          local a = i * math.pi / 4 + P.k
          local r0, r1 = 4 + t, 8 + t * 1.5
          scr:draw_line(hx + math.cos(a) * r0, hy + math.sin(a) * r0 * 0.7, hx + math.cos(a) * r1, hy + math.sin(a) * r1 * 0.7,
                        (math.floor(200 * (1 - t / 8)) << 24) | 0xffffff)
        end
      end

      local r = 12 * s
      local bx = math.min(math.max(hx + 13, r * 1.3 + 2), w - r * 1.3 - 2)
      local by = math.min(math.max(hy - 31, r + 2), h - r - 2)
      local o1, o2, o3 = {}, {}, {}
      for i = 0, 21 do
        local a = P.k * 0.7 + i * math.pi / 11
        local rr = r * ((i % 2 == 0) and 1 or (0.58 + 0.08 * math.sin(i * 1.7 + P.k)))
        o1[#o1 + 1] = { bx + math.cos(a) * rr * 1.25, by + math.sin(a) * rr }
        o2[#o2 + 1] = { bx + math.cos(a) * rr * 1.25 * 0.88, by + math.sin(a) * rr * 0.88 }
        o3[#o3 + 1] = { bx + math.cos(a) * rr * 0.86, by + math.sin(a) * rr * 0.68 }
      end
      scnp_comic_fill(scr, o1, A(0xff000000), 0.5)
      scnp_comic_fill(scr, o2, A(col[1]), 0.5)
      scnp_comic_fill(scr, o3, A(col[2]), 0.5)

      local W = C.W[P.kind]
      local u = 0.5 * s
      local x0, y0 = bx - W.w * u / 2, by - W.h * u / 2
      for pass = 1, 3 do
        local c = pass == 1 and A(0xffc81414) or (pass == 2 and A(0xff000000) or A(col[3]))
        local dx, dy, g = (pass == 1) and 1 or 0, (pass == 1) and 1 or 0, (pass == 2) and 0.75 or 0
        for _, R in ipairs(W.r) do
          scr:draw_box(x0 + R[3] * u + dx - g, y0 + R[1] * u + dy - g, x0 + (R[4] + 1) * u + dx + g, y0 + (R[2] + 1) * u + dy + g, c, c)
        end
      end
    end
  end
  C.pops = keep
end
function scnp_stage_palette()
  scnp_stage_palette_pitch()
  scnp_ball_palette()
  scnp_mirror_kit()
  scnp_costume_kit()
  scnp_costume_hud_step()
  scnp_costume_board_step()
  scnp_stripes_step()
  scnp_comic_step()
end

SCNP_PAL.KIT = { save = nil, out = nil, light = nil }

SCNP_COSTUME = { seat = {}, side = {}, save = {}, out = {}, on = false }
function scnp_costume_parse(wire)
  local C = SCNP_COSTUME
  C.seat, C.on = {}, false
  local k = 0
  for spec in ((wire or "") .. "|"):gmatch("([^|]*)|") do
    k = k + 1
    local f = {}; for x in spec:gmatch("[^,]+") do f[#f + 1] = x end
    if #f >= 6 then
      local function rgb(h) return { tonumber(h:sub(1, 2), 16) or 0, tonumber(h:sub(3, 4), 16) or 0, tonumber(h:sub(5, 6), 16) or 0 } end
      local function hx(v) return (v and v:match("^%x%x%x%x%x%x$")) and rgb(v) or nil end
      C.seat[k] = { base = tonumber(f[1]) or -1, home = { rgb(f[2]), rgb(f[3]), hx(f[9]) }, away = { rgb(f[4]), rgb(f[5]), hx(f[10]) }, abbr = f[6],
                    boots = hx(f[8]), hair = hx(f[11]), name = ((f[7] or ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) }
      C.on = true
    end
  end
  C.wire = C.on and wire or nil
  if C.on then log("costume: seat 1 %s, seat 2 %s", C.seat[1] and C.seat[1].abbr or "-", C.seat[2] and C.seat[2].abbr or "-") end
end
scnp_costume_parse(env("SCNP_COSTUME", ""))

SCNP_COSTUME.BOX = { [3] = 0, [9] = 1, [4] = 2, [10] = 3, [0] = 4, [7] = 5, [8] = 6, [5] = 7 }
function scnp_costume_lock(b, mask)
  local C, P = SCNP_COSTUME, SCNP_PICK
  if not C.on or (b ~= 1 and b ~= 2) or not P or not P.sel or not P.cur or SCNP_PVE.on then return mask end
  local c = C.seat[scnp_seat_of(b)]
  if not c or not C.BOX[c.base] then return mask end
  if mem:read_u8(P.sel) ~= 2 then return mask end

  local cur = mem:read_u16(P.cur + (b - 1) * 2)
  mask = mask & ~0x7f
  if cur == 0 or frame % 8 >= 2 then return mask end
  local i; for n = 0, 7 do if cur == (1 << n) then i = n end end
  if not i then return mask end
  local t = C.BOX[c.base]
  if i == t then return mask | 0x10 end
  if (i // 4) ~= (t // 4) then return mask | 0x02 end
  local d = (t % 4 - i % 4) % 4
  return mask | (d <= 2 and 0x08 or 0x04)
end
function scnp_costume_kit()
  local C = SCNP_COSTUME
  if not C.on then return end
  local base = SCNP_PAL.SPR
  local on = mem:read_u16(CLOCK_ADDR) > 0
  if not on then
    for a, v in pairs(C.save) do if mem:read_u16(a) == C.out[a] then mem:write_u16(a, v) end end
    C.save, C.out, C.kit = {}, {}, nil
    return
  end
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function lum(c) local r, g, b = sp(c); return 0.3 * r + 0.59 * g + 0.11 * b end
  if not C.kit then

    local L, Rt = C.seat[scnp_seat_of(1)], C.seat[scnp_seat_of(2)]
    C.kit = { [1] = L and L.home or nil, [2] = Rt and Rt.home or nil }
    C.boots = { [1] = L and L.boots or nil, [2] = Rt and Rt.boots or nil }
    C.hair = { [1] = L and L.hair or nil, [2] = Rt and Rt.hair or nil }
    if L and Rt then
      local a, b2 = L.home[1], Rt.home[1]
      if math.sqrt((a[1] - b2[1]) ^ 2 + (a[2] - b2[2]) ^ 2 + (a[3] - b2[3]) ^ 2) < 90 then C.kit[2] = Rt.away; log("costume: the right side wears its away kit") end
    end
  end
  for side = 1, 2 do
    local k = C.kit[side]
    if k then
      for line = side == 1 and 1 or 4, side == 1 and 3 or 6 do
        local la = base + line * 32

        local orig = {}
        for i = 6, 13 do local a = la + i * 2; local c = mem:read_u16(a); if c == C.out[a] then c = C.save[a] end; orig[i] = c end
        local m1, m2 = 0, 0
        for i = 6, 10 do m1 = math.max(m1, lum(orig[i])) end
        for i = 11, 13 do m2 = math.max(m2, lum(orig[i])) end
        for i = 6, 13 do
          local a = la + i * 2
          local c = mem:read_u16(a)
          if c ~= C.out[a] then
            C.save[a] = c
            local m = i <= 10 and m1 or m2
            local f = m > 0 and lum(c) / m or 1
            local t = (i <= 7 and (k[3] or k[1])) or (i <= 10 and k[1]) or k[2]
            local function ch(v) local x = v * (0.42 + 0.58 * f) + 26 * math.max(0, f - 0.85); return math.max(0, math.min(31, math.floor(x / 255 * 31 + 0.5))) end
            C.out[a] = ch(t[1]) | (ch(t[2]) << 5) | (ch(t[3]) << 10)
            mem:write_u16(a, C.out[a])
          end
        end
        local hr = C.hair and C.hair[side]
        if hr then
          for i = 4, 5 do
            local a = la + i * 2
            if mem:read_u16(a) ~= C.out[a] then
              C.save[a] = mem:read_u16(a)
              local f = i == 5 and 1 or 0.55
              local function q(v) return math.max(0, math.min(31, math.floor(v * f / 255 * 31 + 0.5))) end
              C.out[a] = q(hr[1]) | (q(hr[2]) << 5) | (q(hr[3]) << 10)
              mem:write_u16(a, C.out[a])
            end
          end
        end
        local bt = C.boots and C.boots[side]
        if bt then
          local a = la + 14 * 2
          if mem:read_u16(a) ~= C.out[a] then
            C.save[a] = mem:read_u16(a)
            local function q(v) return math.max(0, math.min(31, math.floor(v / 255 * 31 + 0.5))) end
            C.out[a] = q(bt[1]) | (q(bt[2]) << 5) | (q(bt[3]) << 10)
            mem:write_u16(a, C.out[a])
          end
        end
      end
    end
  end
end

SCNP_COSTUME.HUD = { TXT = 0x102000, PAL = 0x103680, vis = false, X = { [1] = { col = 1, px = 8 }, [2] = { col = 36, px = 288 } },
  F = {
    A = { "..##..", ".####.", "##..##", "######", "##..##", "##..##" }, B = { "#####.", "##..##", "#####.", "##..##", "##..##", "#####." },
    C = { ".####.", "##..##", "##....", "##....", "##..##", ".####." }, D = { "#####.", "##..##", "##..##", "##..##", "##..##", "#####." },
    E = { "######", "##....", "#####.", "##....", "##....", "######" }, F = { "######", "##....", "#####.", "##....", "##....", "##...." },
    G = { ".#####", "##....", "##.###", "##..##", "##..##", ".#####" }, H = { "##..##", "##..##", "######", "##..##", "##..##", "##..##" },
    I = { "######", "..##..", "..##..", "..##..", "..##..", "######" }, J = { "....##", "....##", "....##", "##..##", "##..##", ".####." },
    K = { "##..##", "##.##.", "####..", "##.##.", "##..##", "##..##" }, L = { "##....", "##....", "##....", "##....", "##....", "######" },
    M = { "##..##", "######", "######", "##..##", "##..##", "##..##" }, N = { "##..##", "###.##", "######", "##.###", "##..##", "##..##" },
    O = { ".####.", "##..##", "##..##", "##..##", "##..##", ".####." }, P = { "#####.", "##..##", "##..##", "#####.", "##....", "##...." },
    Q = { ".####.", "##..##", "##..##", "##.###", "##..##", ".###.#" }, R = { "#####.", "##..##", "##..##", "#####.", "##.##.", "##..##" },
    S = { ".#####", "##....", ".####.", "....##", "....##", "#####." }, T = { "######", "..##..", "..##..", "..##..", "..##..", "..##.." },
    U = { "##..##", "##..##", "##..##", "##..##", "##..##", ".####." }, V = { "##..##", "##..##", "##..##", "##..##", ".####.", "..##.." },
    W = { "##..##", "##..##", "##..##", "######", "######", "##..##" }, X = { "##..##", ".####.", "..##..", "..##..", ".####.", "##..##" },
    Y = { "##..##", "##..##", ".####.", "..##..", "..##..", "..##.." }, Z = { "######", "...##.", "..##..", ".##...", "##....", "######" } } }
function scnp_costume_hud_step()
  local C, H = SCNP_COSTUME, SCNP_COSTUME.HUD
  H.vis = false
  if not C.on then return end
  local T = H.TXT
  if (mem:read_u16(T + (3 * 64 + 4) * 2) >> 12) ~= 10 or (mem:read_u16(T + (3 * 64 + 32) * 2) >> 12) ~= 10 then return end
  H.vis = true
  for side = 1, 2 do
    if C.seat[scnp_seat_of(side)] then
      for k = 0, 2 do
        for r = 2, 4 do
          local a = T + (r * 64 + H.X[side].col + k) * 2
          local v = mem:read_u16(a)
          if v ~= 0 and (v >> 12) == (r == 4 and 4 or 11) then mem:write_u16(a, 0) end
        end
      end
    end
  end
end

SCNP_COSTUME.BOARD = { vis = false, X = { [1] = { col = 4, px = 33 }, [2] = { col = 30, px = 241 } } }
function scnp_costume_board_step()
  local C, B = SCNP_COSTUME, SCNP_COSTUME.BOARD
  B.vis = false
  if not C.on then return end
  local T = 0x102000
  local function led(r, c) local v = mem:read_u16(T + (r * 64 + c) * 2); return (v >> 12) == 6 and (v & 0xf00) == 0x200 end
  if not (led(14, 10) and led(19, 10) and led(14, 29) and led(19, 29)) then return end
  B.vis = true
  for side = 1, 2 do
    if C.seat[scnp_seat_of(side)] then
      for k = 0, 5 do
        for r = 15, 19 do
          local a = T + (r * 64 + B.X[side].col + k) * 2
          local v = mem:read_u16(a)
          if v ~= 0 and (v >> 12) == (r == 19 and 0 or 11) then mem:write_u16(a, 0) end
        end
      end
    end
  end
end

function scnp_flag_mid(kit)
  local function far(x, y) return x and y and math.sqrt((x[1] - y[1]) ^ 2 + (x[2] - y[2]) ^ 2 + (x[3] - y[3]) ^ 2) >= 90 end
  local s = kit[1]
  if far(s, kit[2]) then return kit[2] end
  if far(s, kit[3]) then return kit[3] end
  return (0.3 * s[1] + 0.59 * s[2] + 0.11 * s[3]) > 140 and { 32, 32, 40 } or { 255, 255, 255 }
end
function scnp_costume_hud_draw()
  local C, H = SCNP_COSTUME, SCNP_COSTUME.HUD
  if not C.on or not H.vis then return end
  local scr = machine.screens[":screen"]
  local function argb(w) local r, g, b = w & 31, (w >> 5) & 31, (w >> 10) & 31; return 0xff000000 | ((r * 255 // 31) << 16) | ((g * 255 // 31) << 8) | (b * 255 // 31) end
  local c1, c2, c3 = argb(mem:read_u16(H.PAL + 2)), argb(mem:read_u16(H.PAL + 4)), argb(mem:read_u16(H.PAL + 6))
  local dim = (mem:read_u16(H.PAL + 4) & 31) / 31
  local function team(t) local f = dim; return 0xff000000 | (math.floor(t[1] * f) << 16) | (math.floor(t[2] * f) << 8) | math.floor(t[3] * f) end
  local black = 0xff000000
  local function box(x0, y0, x1, y1, c) scr:draw_box(x0, y0, x1, y1, 0, c) end
  for side = 1, 2 do
    local s = C.seat[scnp_seat_of(side)]
    if s then
      local px = H.X[side].px
      local kit = (C.kit and C.kit[side]) or s.home
      local a, b = team(kit[1]), team(scnp_flag_mid(kit))
      box(px, 8, px + 8, 23, a); box(px + 8, 8, px + 15, 23, b); box(px + 15, 8, px + 23, 23, a)
      box(px + 23, 8, px + 24, 23, black); box(px + 1, 23, px + 24, 24, black)
      local ab = (s.abbr or ""):upper()
      for n = 1, math.min(3, #ab) do
        local g = H.F[ab:sub(n, n)]
        if g then
          local x0, y0 = px + (n - 1) * 8, 25
          local function on(x, y) return y >= 0 and y < 6 and x >= 0 and x < 6 and g[y + 1]:sub(x + 1, x + 1) == "#" end
          for y = 0, 6 do for x = 0, 6 do if on(x - 1, y - 1) and not on(x, y) then box(x0 + x, y0 + y, x0 + x + 1, y0 + y + 1, black) end end end
          for y = 0, 5 do
            local x = 0
            while x < 6 do
              if on(x, y) then
                local col = x < 2 and c3 or (x == 5 and c1 or c2)
                local e = x + 1
                while e < 6 and on(e, y) and (e < 2 and c3 or (e == 5 and c1 or c2)) == col do e = e + 1 end
                box(x0 + x, y0 + y, x0 + e, y0 + y + 1, col); x = e
              else x = x + 1 end
            end
          end
        end
      end
    end
  end
end
function scnp_mirror_kit()
  local K, base = SCNP_PAL.KIT, SCNP_PAL.SPR
  local on = not (SCNP_COSTUME.on and SCNP_COSTUME.seat[scnp_seat_of(2)]) and SCNP_SEL.mirror and mem:read_u16(CLOCK_ADDR) > 0 and mem:read_u8(SCNP_G.team_l) == mem:read_u8(SCNP_G.team_r) and mem:read_u8(SCNP_G.team_l) < 12
  if not on then
    if K.save then
      for a, v in pairs(K.save) do if mem:read_u16(a) == K.out[a] then mem:write_u16(a, v) end end
      K.save, K.out, K.light = nil, nil, nil
    end
    return
  end
  local function sp(c) return c & 31, (c >> 5) & 31, (c >> 10) & 31 end
  local function jn(r, g, b) return math.max(0, math.min(31, math.floor(r + 0.5))) | (math.max(0, math.min(31, math.floor(g + 0.5))) << 5) | (math.max(0, math.min(31, math.floor(b + 0.5))) << 10) end
  local function lum(c) local r, g, b = sp(c); return (0.3 * r + 0.59 * g + 0.11 * b) / 31 end
  if not K.save then

    K.save, K.out = {}, {}
    local ls = 0; for i = 6, 10 do ls = ls + lum(mem:read_u16(base + 4 * 32 + i * 2)) end
    K.light = ls / 5 > 0.55
    log("mirror match: the right side's kit recoloured (%s)", K.light and "dark red" or "white")
  end
  for line = 4, 6 do
    for i = 6, 13 do
      local a = base + line * 32 + i * 2
      local c = mem:read_u16(a)
      if c ~= K.out[a] then
        local l = lum(c)
        K.save[a] = c
        if i <= 10 then K.out[a] = K.light and jn(9 + 20 * l, 2 + 6 * l, 3 + 6 * l) or jn(18 + 13 * l, 18 + 13 * l, 20 + 11 * l)
        else K.out[a] = K.light and jn(2 + 8 * l, 3 + 9 * l, 9 + 16 * l) or jn(20 + 11 * l, 20 + 11 * l, 21 + 10 * l) end
        mem:write_u16(a, K.out[a])
      end
    end
  end
end

SCNP_PAL.BALLS = { orange = { 31, 15, 2 }, yellow = { 31, 28, 4 }, pink = { 31, 11, 22 }, blue = { 6, 14, 31 } }
SCNP_PAL.BALLNAME = env("SCNP_BALL", "white")
SCNP_PAL.BALL = SCNP_PAL.BALLS[SCNP_PAL.BALLNAME]
function scnp_ball_palette()
  local P, base = SCNP_PAL, SCNP_PAL.SPR
  local on = P.BALL and mem:read_u16(CLOCK_ADDR) > 0
  if not on then
    if P.BSAVE then
      for i = 0, 4 do if mem:read_u16(base + 2 * i) == P.BOUT[i] then mem:write_u16(base + 2 * i, P.BSAVE[i]) end end
      P.BSAVE, P.BOUT = nil, nil
    end
    return
  end
  local mine = P.BOUT ~= nil
  if mine then for i = 0, 4 do if mem:read_u16(base + 2 * i) ~= P.BOUT[i] then mine = false end end end
  if not mine then
    P.BSAVE, P.BOUT = {}, {}
    for i = 0, 4 do
      local g = mem:read_u16(base + 2 * i)
      P.BSAVE[i] = g
      local lum = math.max(g & 31, (g >> 5) & 31, (g >> 10) & 31) / 31
      P.BOUT[i] = (math.floor(P.BALL[3] * lum + 0.5) << 10) | (math.floor(P.BALL[2] * lum + 0.5) << 5) | math.floor(P.BALL[1] * lum + 0.5)
    end
  end
  for i = 0, 4 do mem:write_u16(base + 2 * i, P.BOUT[i]) end
end
function scnp_stage_palette_pitch()
  if scnp_stage == 0 then return end
  local set = SCNP_PAL.P[scnp_stage]
  if not set then return end
  for i = 1, #set do
    local row = set[i]
    local a = SCNP_PAL.TILE + row[1] * 32
    for w = 1, 16 do mem:write_u16(a + 2 * (w - 1), row[w + 1]) end
  end
  local spr = (scnp_stage == 3) and SCNP_PAL.DIRT or SCNP_PAL.SPRX[scnp_stage] or SCNP_PAL.GRASS
  for w = 1, 16 do mem:write_u16(SCNP_PAL.SPR + 2 * (w - 1), spr[w]) end
end
local function time_byte() local t = tonumber(cfg.time) or 150; return math.max(1, math.min(255, math.floor(t / 10 + 0.5))) end
local function install_clock_gate()
  local secs = tonumber(cfg.time) or 150
  if secs < 30 then secs = 30 end
  if secs > 900 then secs = 900 end

  local fpu = (nplayers == 1 or SCNP_PVE.on) and math.floor(SCNP_G.fpu * 52 / 72 + 0.5) or SCNP_G.fpu
  clock_fpu = fpu
  local base = CLOCK_UNITS * fpu
  if SCNP_DIPTIME then secs = 150 end
  local target = math.floor(secs * 60 + 0.5)
  if SCNP_DIPTIME then target = 91 * CLOCK_UNITS end
  local boundary = target / CLOCK_UNITS
  clock_secs = secs
  clock_units0 = target < base and math.max(10, math.floor(CLOCK_UNITS * target / base + 0.5)) or CLOCK_UNITS
  clock_spu = secs / clock_units0

  SCNP_RELOAD = nil
  if SCNP_PACE and target > base then
    local per = math.floor(target / CLOCK_UNITS + 0.5)
    if per <= 256 then SCNP_RELOAD = per - 1; clock_fpu = per end
  end
  if SCNP_RELOAD_TAP then SCNP_RELOAD_TAP:remove(); SCNP_RELOAD_TAP = nil end
  if SCNP_RELOAD then
    SCNP_RELOAD_TAP = mem:install_write_tap(CLOCK_ADDR + 2, CLOCK_ADDR + 3, "scnp_reload", function(offset, data, mask)

      if (mask & 0xff00) ~= 0 and SCNP_RELOAD then return (data & 0x00ff) | (SCNP_RELOAD << 8) end
      return nil
    end)
  end
  clock_start = nil
  result_written = false
  if clock_tap then clock_tap:remove(); clock_tap = nil end
  clock_tap = mem:install_write_tap(CLOCK_ADDR, CLOCK_ADDR + 1, "scnp_clock", function(offset, data, mask)
    local cur = mem:read_u16(CLOCK_ADDR)
    if data > cur + 5 and data >= 30 and SCNP_PVE.on and cur > 0 then

      log("PvE: the board reset the clock for a player joining (%d -> %d) - kept at %d", cur, data, cur)
      return cur
    end
    if data > cur + 5 and data >= 30 then

      if clock_start then log("clock reset by the game (%d -> %d): new match", cur, data) end
      clock_start = nil; result_written = false

      if SCNP_POSS then SCNP_POSS.a, SCNP_POSS.b, SCNP_POSS.t0 = 0, 0, nil end
      SCNP_PK.gg_n = 0; SCNP_PK.gg_end = false
      if target < base then return math.max(10, math.floor(data * target / base + 0.5)) end
      return nil
    elseif clock_ours then
      return nil
    end
    if data == 0 and cur == 1 then
      local more = scnp_gg_extend()
      if more then hud_tick_frame = frame; return more end
    end
    if data == cur - 1 then

      hud_tick_frame = frame
      if not clock_start then clock_start = frame; clock_u0 = cur; clock_boundary = target / cur end
    end
    if data == cur - 1 and clock_run then

      if not clock_start then
        clock_start = frame; clock_u0 = cur; clock_boundary = target / cur

      end
      local due = math.max(0, clock_u0 - math.floor((frame - clock_start) / clock_boundary))
      if cur > due then beep_hold_fc = -1000; return nil end
      beep_hold_fc = mem:read_u16(FRAMECTR_ADDR)
      return cur
    elseif data == cur - 1 and target > base and SCNP_RELOAD then
      return nil
    elseif data == cur - 1 and target > base then
      local fc = mem:read_u16(FRAMECTR_ADDR)
      local prev = (fc - fpu) & 0xffff
      if prev > fc then return nil end
      if math.floor(fc / boundary) ~= math.floor(prev / boundary) then beep_hold_fc = -1000; return nil end
      beep_hold_fc = fc
      return cur
    end
  end)
  if beep_tap then beep_tap:remove(); beep_tap = nil end
  beep_tap = mem:install_write_tap(SOUND_CMD_ADDR, SOUND_CMD_ADDR + 7, "scnp_beep", function(offset, data, mask)

    if beep_want > 0 then
      if offset == SOUND_CMD_ADDR and data == 0 and not beep_inject then beep_inject = true; return (BEEP_KIND << 8) | BEEP_CMD end
      if offset == SOUND_CMD_ADDR + 4 and beep_inject then beep_inject = false; beep_want = beep_want - 1; return (BEEP_CMD << 8) | BEEP_KIND end
    end
    if beep_hold_fc < 0 then return nil end
    local fc = mem:read_u16(FRAMECTR_ADDR)
    if ((fc - beep_hold_fc) & 0xffff) > 4 then return nil end
    if offset == SOUND_CMD_ADDR and (data & 0xff) == BEEP_CMD then
      beep_eating = true
      log("warning tick dropped (held clock step, clock %d)", mem:read_u16(CLOCK_ADDR))
      return 0
    end
    if beep_eating and offset == SOUND_CMD_ADDR + 4 then beep_eating = false; beep_hold_fc = -1000; return 0 end
    return nil
  end)
  log("clock: %s", clock_run and "running through stoppages (netplay 8/9)" or "stops during stoppages, like the board")
  if SCNP_RELOAD then log("clock: the board runs it, one unit per %d running frames (reload byte %d)", SCNP_RELOAD + 1, SCNP_RELOAD) end
  log("match length %d s (%s the board's %d s base: %s)", secs, target > base and "stretching" or (target < base and "shortening" or "equal to"),
      math.floor(base / 60 + 0.5), target > base and string.format("one unit per %.1f frames", boundary) or string.format("clock starts at %d", math.max(10, math.floor(CLOCK_UNITS * target / base + 0.5))))
end

local function setup_fields()
  for slot = 1, 4 do
    for bit, def in ipairs(FIELD_DEFS[slot]) do
      local port = ioport.ports[def[1]]
      local f = port and port.fields[def[2]] or nil
      if not f then
        log("WARNING: field %s / %s not found", def[1], def[2])
      else
        local orig = f:input_seq("standard")
        f:set_input_seq("standard", empty_seq)
        fields[slot][bit] = { field = f, orig = orig, seq = nil }
      end
    end
  end

  local ours = {}
  for slot = 1, 4 do for _, e in pairs(fields[slot]) do ours[e.field] = true end end
  local n = 0
  for _, port in pairs(ioport.ports) do
    for _, f in pairs(port.fields) do
      local cls = f.type_class
      if not ours[f] and not f.is_analog and cls ~= "config" and cls ~= "dipswitch" then
        local orig = f:input_seq("standard")
        if orig and not orig.empty then
          f:set_input_seq("standard", empty_seq)
          extras[#extras + 1] = { field = f, orig = orig }
          n = n + 1
        end
      end
    end
  end
  log("detached %d other live inputs for the session", n)

  local forced = 0
  for _, port in pairs(ioport.ports) do
    for _, f in pairs(port.fields) do
      if f.type_class == "dipswitch" then
        local ok = pcall(function() f.user_value = f.defvalue end)
        if ok then forced = forced + 1 end
      end
    end
  end
  log("DIP switches set to factory defaults for the session (%d fields)", forced)
  if SCNP_PVE.on and is_host and SCNP_DIFF.v ~= 3 then scnp_diff_apply(SCNP_DIFF.v) end
  apply_time_dips()
  install_clock_gate()
  install_bgm_tap()
  scnp_install_stage_tap()
end

if cfg.mode == "lib" then
  SCNP_SEL = SCNP_SEL or { mirror = false, on = false }
  install_bgm_tap()
  scnp_install_stage_tap()
  SCNP_LIB = { frame = function() frame = frame + 1; scnp_stage_palette() end, draw = function() scnp_night_draw() end }
  return
end

local function bind_local_keys()
  local names = {}
  for bit = 1, 8 do
    local e = fields[local_slot][bit]
    if e then
      local tokens = (key_profile or KEYSETS.arrows)[bit]
      if not key_profile then
        local src = fields[1][bit]
        if src and src.orig and not src.orig.empty then
          tokens = input:seq_to_tokens(src.orig) .. " OR " .. tokens
        end
      end
      e.seq = input:seq_from_tokens(tokens)

      local kbd, joy = {}, {}
      for alt in (tokens .. " OR "):gmatch("(.-) OR ") do
        if alt:find("JOYCODE") or alt:find("MOUSECODE") then joy[#joy + 1] = alt
        elseif alt:find("KEYCODE") then kbd[#kbd + 1] = alt end
      end
      e.seq_kbd = #kbd > 0 and input:seq_from_tokens(table.concat(kbd, " OR ")) or nil
      e.seq_joy = #joy > 0 and input:seq_from_tokens(table.concat(joy, " OR ")) or nil
      if e.seq_joy and not key_profile then local_dev = 2 elseif local_dev == 0 then local_dev = 1 end
      names[#names + 1] = CONTROL_NAMES[bit] .. "=" .. input:seq_name(e.seq)
    end
  end
  log("player %d controls (%s): %s", local_slot,
      key_profile and ("profile " .. keyset_name) or "own P1 bindings + stock keys", table.concat(names, "  "))
end

local function restore_fields()
  for slot = 1, 4 do
    for _, e in pairs(fields[slot]) do
      e.field:clear_value()
      if e.orig then e.field:set_input_seq("standard", e.orig) end
    end
  end
  for _, e in ipairs(extras) do e.field:set_input_seq("standard", e.orig) end
end

local function read_local_input()
  local mask = 0
  dev_tick = dev_tick + 1
  for bit, e in pairs(fields[local_slot]) do
    if e.seq and input:seq_pressed(e.seq) then
      mask = mask | (1 << (bit - 1))
      if e.seq_joy and input:seq_pressed(e.seq_joy) then last_joy_frame = dev_tick
      elseif e.seq_kbd and input:seq_pressed(e.seq_kbd) then last_kbd_frame = dev_tick end
    end
  end
  if last_joy_frame > last_kbd_frame then local_dev = 2 elseif last_kbd_frame > last_joy_frame then local_dev = 1 end
  if local_dev == 0 then local_dev = 1 end
  return mask
end

scnp_swap = (env("SCNP_SWAP", "0") == "1") and not SCNP_PVE.on

local GAME_PLAYER = is_teams and (scnp_swap and { 2, 1, 4, 3 } or { 1, 2, 3, 4 }) or (scnp_swap and { 2, 1, 3, 4 } or { 1, 2, 3, 4 })

function scnp_seat_of(b) for s = 1, 4 do if GAME_PLAYER[s] == b then return s end end return b end

SCNP_PICK = { sel = ({ cupsocs2 = 0x109c75, cupsocs = 0x109c75, cupsoc = 0x109b3d })[SCNP_GAME],
              taken = ({ cupsocs2 = 0x109c72, cupsocs = 0x109c72, cupsoc = 0x109b3a })[SCNP_GAME], t0 = nil, said = false,
              cur = ({ cupsocs2 = 0x109c76, cupsocs = 0x109c76, cupsoc = 0x109b3e })[SCNP_GAME],
              prev = 0 }
function scnp_pick_hold(b)
  local P = SCNP_PICK
  if b ~= 1 or not P.sel or not (SCNP_SEL and SCNP_SEL.on) or SCNP_PVE.on or nplayers < 2 then return false end
  if SCNP_SEL.mirror then return false end
  if mem:read_u8(P.sel) ~= 2 then P.t0 = nil; return false end
  P.t0 = P.t0 or frame
  if mem:read_u16(P.taken) ~= 0 then return false end
  if frame - P.t0 > 1200 then
    if not P.said then P.said = true; log("pick priority: the 2P side did not pick in 20 s - the 1P side may confirm") end
    return false
  end
  return true
end

function scnp_pick_push(b, mask)
  local P = SCNP_PICK
  if b ~= 2 or not P.cur or SCNP_SEL.mirror then return end
  local edge = mask & ~P.prev & 0x0f
  P.prev = mask
  if edge == 0 or not scnp_pick_hold(1) then return end
  local c1, c2 = mem:read_u16(P.cur), mem:read_u16(P.cur + 2)
  local i1, i2
  for n = 0, 7 do if c1 == (1 << n) then i1 = n end; if c2 == (1 << n) then i2 = n end end
  if not i1 or not i2 then return end
  local r, c = i2 // 4, i2 % 4
  local t
  if edge & 0x04 ~= 0 then t = r * 4 + (c + 3) % 4
  elseif edge & 0x08 ~= 0 then t = r * 4 + (c + 1) % 4
  else t = (1 - r) * 4 + c end
  if t ~= i1 then return end
  mem:write_u16(P.cur, c2)
  log("pick priority: the 2P side moves onto the 1P side's box %d - the 1P cursor goes to box %d (frame %d)", i1, i2, frame)
end

local function apply_input(slot, mask)
  mask = scnp_god_autopress(GAME_PLAYER[slot], mask)
  mask = scnp_costume_lock(GAME_PLAYER[slot], mask)
  scnp_pick_push(GAME_PLAYER[slot], mask)
  if scnp_pick_hold(GAME_PLAYER[slot]) then mask = mask & ~0x70 end
  for bit, e in pairs(fields[GAME_PLAYER[slot]]) do
    if (mask >> (bit - 1)) & 1 == 1 then e.field:set_value(1) else e.field:clear_value() end
  end
end

local function clear_all_inputs()
  for s = 1, 4 do apply_input(s, 0) end
end

local SUM_BASE, SUM_SIZE = 0x110000, 0x4000
local function ram_checksum()
  local s = 0
  for a = SUM_BASE, SUM_BASE + SUM_SIZE - 4, 4 do
    s = (s * 31 + mem:read_u32(a)) & 0xffffffff
  end
  return s
end

local function u32le(n) return string.pack("<I4", n & 0xffffffff) end

local peers = {}
local host_peer = nil
local listener = nil

local relay_sock = nil
local relay_rx = ""

local function relay_write(dst, data)
  if not relay_sock then return end
  local ok, err = pcall(function() return relay_sock:write(string.char(dst) .. string.pack("<I4", #data) .. data) end)
  if not ok then log("relay send error (dst %d): %s", dst, tostring(err)) end
end

local function send_to(p, data)
  if not p then return end
  if is_relay and is_host then relay_write(p.slot, data); return end
  if not p.sock then return end
  local ok, err = pcall(function() return p.sock:write(data) end)
  if not ok then log("send error (slot %s): %s", tostring(p.slot), tostring(err)) end
end
local function broadcast(data)
  if is_relay and is_host then relay_write(0, data); return end
  for _, p in pairs(peers) do send_to(p, data) end
end

local MSG_LEN = { M = 3, L = 2, W = 3, F = 7, H = 8, I = 6, A = 9, C = 9, P = 5, Q = 5, X = 1, R = 1, G = 1, T = 9, D = 2, J = 6, V = 2, O = 17 }
local function next_message(p)
  local b = p.rx
  if #b < 1 then return nil end
  local t = b:sub(1, 1)
  if t == "S" then
    if #b < 6 then return nil end
    local gen = b:byte(2)
    local len = string.unpack("<I4", b, 3)
    if #b < 6 + len then return nil end
    local payload = b:sub(7, 6 + len); p.rx = b:sub(7 + len)
    return t, gen, payload
  end
  local n = MSG_LEN[t]
  if not n then
    log("protocol error: unknown message %q from slot %s, dropping buffer", t, tostring(p.slot))
    p.rx = ""; return nil
  end
  if #b < 1 + n then return nil end
  local payload = b:sub(2, 1 + n); p.rx = b:sub(2 + n)
  return t, payload:byte(1), payload:sub(2)
end

local function poll(p)
  if not p.sock then return end
  local data = p.sock:read(65536)
  if data and #data > 0 then p.rx = p.rx .. data end
end

local function relay_poll()
  local data = relay_sock:read(65536)
  if data and #data > 0 then relay_rx = relay_rx .. data end
  while #relay_rx >= 5 do
    local src = relay_rx:byte(1)
    local len = string.unpack("<I4", relay_rx, 2)
    if #relay_rx < 5 + len then break end
    local payload = relay_rx:sub(6, 5 + len)
    relay_rx = relay_rx:sub(6 + len)
    if src >= 1 and src <= 12 then
      if not peers[src] then peers[src] = { sock = nil, rx = "", slot = src } end
      peers[src].rx = peers[src].rx .. payload
    end
  end
end

local STATE_NAME = "np_sync"
local function set_state_name(slot) STATE_NAME = "np_sync_s" .. tostring(slot) end
local state_dir = manager.options.entries.state_directory:value()

local PATH_SEP = package.config:sub(1, 1)
local function state_relpath(name) return machine.system.name .. PATH_SEP .. (name or STATE_NAME) .. ".sta" end
local OPEN_READ, OPEN_WRITE, OPEN_CREATE, OPEN_CREATE_PATHS = 1, 2, 4, 8
local function read_state_file(name)
  local f = emu.file(state_dir, OPEN_READ)
  local err = f:open(state_relpath(name))
  if err then return nil, tostring(err) end
  local path, size = f:fullpath(), f:size()
  local data = (size > 0) and f:read(size) or ""
  f:close()
  if #data == 0 then return nil, "empty file " .. path end
  return data, path
end

local function write_build_id(header)
  if type(header) ~= "string" or #header < 32 then return end
  local hex = string.format("%02x%02x%02x%02x", header:byte(29), header:byte(30), header:byte(31), header:byte(32))
  local f = emu.file(state_dir, OPEN_WRITE | OPEN_CREATE | OPEN_CREATE_PATHS)
  if f:open("build.id") then return end
  f:write(hex)
  f:close()
end

local function pct_decode_path(p) return (p:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

SCNP_SAFE = { TYPES = { ["1v1"] = true, ["2v2"] = true, pve = true, free = true }, MAX_REPLAY = 8 * 1024 * 1024, MAX_SEG = 64 }
function SCNP_SAFE.names(s) return (s:gsub("[\x00-\x1f\x7f\\\"]", "")) end
function SCNP_SAFE.type(t) t = tostring(t or "1v1"); return SCNP_SAFE.TYPES[t] and t or "1v1" end
local function split_path(p)
  local dir, name = p:match("^(.*)[/\\]([^/\\]+)$")
  if not dir then return ".", p end
  return dir, name
end
local function replay_write(dir, name, meta_json, segments, inputs)
  local f = emu.file(dir, OPEN_WRITE | OPEN_CREATE | OPEN_CREATE_PATHS)
  local err = f:open(name)
  if err then return nil, tostring(err) end
  local parts = { "SCNPRPL2\n", meta_json, "\n", u32le(#segments) }
  for _, sg in ipairs(segments) do parts[#parts + 1] = u32le(sg.at) .. u32le(#sg.state) .. sg.state end
  parts[#parts + 1] = u32le(#inputs)
  local buf = {}
  for i = 1, #inputs do local a = inputs[i]; buf[#buf + 1] = string.char(a[1] & 0xff, a[2] & 0xff, a[3] & 0xff, a[4] & 0xff) end
  parts[#parts + 1] = table.concat(buf)
  local data = table.concat(parts)
  local n = f:write(data)
  local path = f:fullpath()
  f:close()
  if n ~= #data then return nil, "short write" end
  return path
end
local function replay_read(path)
  local dir, name = split_path(path)
  local f = emu.file(dir, OPEN_READ)
  local err = f:open(name)
  if err then return nil, tostring(err) end
  local size = f:size()
  if size > SCNP_SAFE.MAX_REPLAY then f:close(); return nil, string.format("replay file too big (%d bytes)", size) end
  local data = f:read(size) or ""; f:close()
  if data:sub(1, 9) ~= "SCNPRPL2\n" then return nil, "not a replay file" end
  local nlpos = data:find("\n", 10, true)
  if not nlpos then return nil, "bad header" end
  local meta = data:sub(10, nlpos - 1)
  local pos = nlpos + 1
  if pos + 3 > #data then return nil, "replay file cut short (no segment count)" end
  local nseg = string.unpack("<I4", data, pos); pos = pos + 4
  if nseg < 1 or nseg > SCNP_SAFE.MAX_SEG then return nil, string.format("bad replay file (%d state segments)", nseg) end
  local segments = {}
  for i = 1, nseg do
    if pos + 7 > #data then return nil, string.format("replay file cut short (segment %d)", i) end
    local at, len = string.unpack("<I4I4", data, pos); pos = pos + 8
    if len > #data - pos + 1 then return nil, string.format("bad replay file (segment %d: %d bytes, %d left)", i, len, #data - pos + 1) end
    segments[i] = { at = at, state = data:sub(pos, pos + len - 1) }; pos = pos + len
  end
  if pos + 3 > #data then return nil, "replay file cut short (no frame count)" end
  local nfr = string.unpack("<I4", data, pos); pos = pos + 4
  if nfr > (#data - pos + 1) // 4 then return nil, string.format("bad replay file (%d frames, %d bytes left)", nfr, #data - pos + 1) end
  local inputs = {}
  for i = 1, nfr do
    local b1, b2, b3, b4 = data:byte(pos, pos + 3); pos = pos + 4
    inputs[i] = { b1 or 0, b2 or 0, b3 or 0, b4 or 0 }
  end
  return { meta = meta, segments = segments, inputs = inputs }
end

local function write_state_file(data)
  local f = emu.file(state_dir, OPEN_WRITE | OPEN_CREATE | OPEN_CREATE_PATHS)
  local err = f:open(state_relpath())
  if err then return nil, tostring(err) end
  local path = f:fullpath()
  local n = f:write(data)
  f:close()
  if n ~= #data then return nil, string.format("short write, %d of %d bytes -> %s", n, #data, path) end
  return path
end

local STATE_HEADER = 32
local PROBE_STATE = "np_probe"
local probe_header, probe_asked, probe_at = nil, false, 0
local function sig_hex(h) return string.format("%02x%02x%02x%02x", h:byte(29), h:byte(30), h:byte(31), h:byte(32)) end

local phase = "connect"
local agg_max = 0
local spec_base = nil
local sum_hist = {}
local spec_throttled = true
local gen = 0
local inputs = { {}, {}, {}, {} }
local agg = {}

rec_inputs, rec_segments, rec_written = {}, {}, false
rp, rp_phase, rp_pos, rp_seg, rp_meta = nil, "boot", 0, 1, nil

SCNP_DEVR = { last = "", hist = {}, play = nil, pi = 1 }
function scnp_devr_rec()
  local R = SCNP_DEVR
  local d = string.format("%d%d%d%d", hud_dev[1] or 0, hud_dev[2] or 0, hud_dev[3] or 0, hud_dev[4] or 0)
  if d ~= R.last then R.last = d; R.hist[#R.hist + 1] = #rec_inputs .. ":" .. d end
end
function scnp_devr_play()
  local R = SCNP_DEVR
  while R.play and R.play[R.pi] and R.play[R.pi].at <= rp_pos do
    local d = R.play[R.pi].d
    for k = 1, 4 do hud_dev[k] = tonumber(d:sub(k, k)) or 0 end
    log("replay: stick/keyboard %s from input %d", d, R.play[R.pi].at)
    R.pi = R.pi + 1
  end
end

local SCORE_LEFT, SCORE_RIGHT, TEAM_LEFT, TEAM_RIGHT = SCNP_G.score_l, SCNP_G.score_r, SCNP_G.team_l, SCNP_G.team_r

local function rec_score()
  local a, b = mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT)
  if scnp_swap then return b, a end
  return a, b
end
local function rec_save(complete)
  if rec_written or is_replay or not cfg.replay_dir or #rec_inputs < 120 or #rec_segments == 0 then
    if not rec_written and not is_replay then log("replay: nothing saved (%d input frames, %d segment(s), dir %s)", #rec_inputs, #rec_segments, tostring(cfg.replay_dir)) end
    return
  end
  rec_written = true
  local dir = pct_decode_path(cfg.replay_dir)
  local names = SCNP_SAFE.names(pct_decode_path(env("SCNP_NAMES", "")))
  local a, b = names:match("^([^,]*),([^,]*)")
  local function fn(x) x = (x or ""):gsub('[\\/:*?"<>|%s]', ""); return x ~= "" and x or "player" end
  local s1, s2 = rec_score()
  local stamp = os.date("%Y%m%d_%H%M%S")

  local name = stamp .. "_" .. fn(a) .. "_vs_" .. fn(b) .. "_" .. s1 .. "-" .. s2 .. "_p" .. local_slot .. ".scr"
  local build = ""
  do local f = emu.file(state_dir, OPEN_READ); if not f:open("build.id") then build = f:read(8) or ""; f:close() end end
  local meta = string.format('{"v":2,"game":"%s","build":"%s","date":"%s","players":%d,"type":"%s","time":%d,"delay":%d,"names":"%s","score":[%d,%d],"complete":%s,"frames":%d,"slot":%d,"swap":%d,"clock":"%s","stage":%d,"pk":%d,"free":%d,"map":"%s","pace":%d,"sel":%d,"dd":"%s","god":%d,"ball":"%s","devs":"%s","diff":%d,"pvegod":%d,"comic":%d,"costume":"%s","dip":%d}',
    SCNP_GAME, build, os.date("%Y-%m-%d %H:%M"), nplayers, SCNP_SAFE.type(cfg.teams), tonumber(cfg.time) or 150, cfg.delay, names, s1, s2, complete and "true" or "false", #rec_inputs, local_slot, scnp_swap and 1 or 0, clock_run and "run" or "stop", scnp_stage, scnp_pk_byte(), SCNP_FREE and 1 or 0, table.concat(GAME_PLAYER), SCNP_PACE and 2 or 1, scnp_sel_code(), table.concat(SCNP_DD.hist or {}, ";"), SCNP_GOD.on and (SCNP_GOD.auto and 3 or (SCNP_GOD.fix and 2 or 1)) or 0, SCNP_PAL.BALL and SCNP_PAL.BALLNAME or "white", table.concat(SCNP_DEVR.hist, ";"), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_PVEGOD.on and 1 or 0, SCNP_COMIC.on and 1 or 0, ((SCNP_COSTUME.wire or ""):gsub('"', "")), SCNP_DIPTIME and 1 or 0)
  local path, err = replay_write(dir, name, meta, rec_segments, rec_inputs)
  if not path then

    name = stamp .. "_" .. fn(a) .. "_vs_" .. fn(b) .. "_" .. s1 .. "-" .. s2 .. "_p" .. local_slot .. "_" .. (os.time() % 10000) .. ".scr"
    path, err = replay_write(dir, name, meta, rec_segments, rec_inputs)
  end
  if path then log("REPLAY %s", name); log("replay saved: %s (%d frames, %d segment(s))", path, #rec_inputs, #rec_segments)
  else log("replay not saved: %s", tostring(err)) end
end
local last_broadcast = 0
local local_sums = {}
local peer_sums = { {}, {}, {}, {} }
local save_requested_at = nil
local resync_pending = false
local reloading = false
local pending_state = nil
local wait_timeout_s = 20
local ready_timeout_s = 30
local sync_timeout_s = 60
local spec_timeout_s = 25
local spec_asked = false
local spec_saw_play = false
local phase_since = 0
local load_started = nil
local write_fail = 0

local stats = { stalls = 0, max_stall_ms = 0, desync = 0, resyncs = 0, long_stalls = 0, stall_total_ms = 0, late_ms = 0 }
local connect_tries = 0
local hs_wait = 0

local function zeros() return { 0, 0, 0, 0 } end

local rtt = { nil, nil, nil, nil }
local function now_ms() return math.floor(emu.osd_ticks() * 1000 / emu.osd_ticks_per_second()) & 0xffffffff end
local screen = machine.screens[":screen"]

local HUD_TH = 7.3
pcall(function() HUD_TH = manager.ui.line_height * (screen.height or 224) end)
if not HUD_TH or HUD_TH <= 0 then HUD_TH = 7.3 end
local FS = HUD_TH / 7.3
local HUD_H = math.floor(HUD_TH + 3.7)

local function pct_decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

SCNP_PK = {
  on = env("SCNP_PK", "0") == "1",

  gg = env("SCNP_PK", "0") == "2", gg_n = 0, gg_end = false, gg_note = 0, gg_text = nil, gg_arg = nil,

  race = ({ ["1"] = 1, ["3"] = 3, ["5"] = 5 })[env("SCNP_RACE", "0")] or 0, race_end = false,

  ED = {
    cupsoc   = { a0 = 0x109d50, br = 0x8262, br_old = 0x09ac, br_new = 0x0566, rot = 0x88de, rot_old = 0x5240, rot_new = 0x7000, ctl = 0x10a080 },
    cupsocs2 = { a0 = 0x109ee0, br = 0x8260, br_old = 0x0d36, br_new = 0x05ac, native = true },
  },
  state = nil,
  started = 0, seen = false, lastc4 = -1, a = 0, b = 0, rounds = 0,

  cap = tonumber(env("SCNP_PK_CAP", "480")) or 480,
  cut = false,
}

function scnp_pk_byte()
  if SCNP_PK.race > 0 then return 10 + SCNP_PK.race end
  return SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0)
end

function scnp_pk_decide()
  local P, E = SCNP_PK, SCNP_PK.ED[SCNP_GAME]
  P.state = "off"
  if not P.on or not E then return end
  if nplayers ~= (is_teams and 4 or 2) then return end
  if mem:read_u8(SCORE_LEFT) ~= mem:read_u8(SCORE_RIGHT) then return end
  local rg = manager.machine.memory.regions[":maincpu"]
  if not rg or rg:read_u16(E.br) ~= E.br_old or (E.rot and rg:read_u16(E.rot) ~= E.rot_old) then
    log("penalties: the program is not the one the patch was made for - no shoot-out"); return
  end
  rg:write_u16(E.br, E.br_new)
  if E.rot then rg:write_u16(E.rot, E.rot_new) end
  P.state = "run"; P.started = frame; P.seen = false; P.lastc4 = -1; P.a = 0; P.b = 0; P.rounds = 0; P.cut = false
  P.hud0 = nil; P.hud_live = false; P.ha = 0; P.hb = 0

  if (mem:read_u16(E.a0) & 0x4000) ~= 0 then P.seen = true; P.lastc4 = mem:read_u16(E.a0 + 0xc4) end
  log("penalties: level at full time (%d-%d) - shoot-out (mode %04x)", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), mem:read_u16(E.a0 + 2))
end

function scnp_pk_step()
  local P, E = SCNP_PK, SCNP_PK.ED[SCNP_GAME]
  if (mem:read_u16(E.a0) & 0x4000) ~= 0 then
    P.seen = true
    local c4 = mem:read_u16(E.a0 + 0xc4)
    if c4 ~= P.lastc4 and not E.native then

      P.lastc4 = c4
      if c4 % 2 == 0 then P.rounds = P.rounds + 1 end
      local odd = is_teams and (P.rounds - 1) % 2 == 1
      if odd then
        local c0, c2 = E.ctl, E.ctl + 2 * 0x1e
        local held = mem:read_u32(c0 + 8)
        if held ~= 0 then
          mem:write_u16(c2 + 2, mem:read_u16(c2 + 2) | 0x10); mem:write_u32(c2 + 8, held)
          mem:write_u16(c0 + 2, mem:read_u16(c0 + 2) & 0xffef); mem:write_u32(c0 + 8, 0)
        end
      end
      local man
      if c4 % 2 == 0 then man = mem:read_u32(E.a0 + 0x232) & 0xffffff
      else
        local keeper = mem:read_u32(E.a0 + 0x22e) & 0xffffff
        man = keeper ~= 0 and (mem:read_u32(keeper + 0x96) & 0xffffff) or 0
      end
      if man ~= 0 then
        local c = E.ctl + (odd and 3 or 1) * 0x1e
        mem:write_u16(c + 2, mem:read_u16(c + 2) | 0x10); mem:write_u32(c + 8, man)
      end
    end
    P.a, P.b = mem:read_u16(E.a0 + 0xd0), mem:read_u16(E.a0 + 0xd2)

    if not P.hud0 then P.hud0 = { P.a, P.b }; log("penalties: the counters read %d-%d as it begins (the HUD shows 0-0 until they move)", P.a, P.b) end
    if P.hud0 and P.hud0[1] == P.a and P.hud0[2] == P.b and not P.hud_live then P.ha, P.hb = 0, 0
    else P.hud_live = true; P.ha, P.hb = P.a, P.b end
    if frame - P.started < 60 * P.cap then return false end

    P.cut = true
    log("penalties: still going after %d s - stopped at %d-%d, counts for nobody", P.cap, P.a, P.b)
    return true
  end

  if P.seen then return true end
  if frame - P.started > 60 * 30 then log("penalties: the shoot-out never started"); return true end
  return false
end

function scnp_pk_finish()
  local P, E = SCNP_PK, SCNP_PK.ED[SCNP_GAME]
  P.state = "done"
  local rg = manager.machine.memory.regions[":maincpu"]
  if rg then rg:write_u16(E.br, E.br_old); if E.rot then rg:write_u16(E.rot, E.rot_old) end end
  log("penalties: %d-%d", P.a, P.b)
end

function scnp_gg_extend()
  local P = SCNP_PK
  if P.race > 0 then

    if P.race_end or SCNP_PVE.on or nplayers ~= (is_teams and 4 or 2) then return nil end
    if math.max(mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT)) >= P.race then return nil end
    local units = math.max(1, math.floor(30 / clock_spu + 0.5))
    P.gg_n = P.gg_n + 1
    P.gg_note = frame + 180; P.gg_text = "FIRST TO %d - 30 more seconds"; P.gg_arg = P.race
    if clock_run then clock_u0 = clock_u0 + units end
    log("first to %d: %d-%d at full time - 30 s more (%d units, extension %d)", P.race, mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), units, P.gg_n)
    return units
  end
  if not P.gg or P.gg_end or SCNP_PVE.on or nplayers ~= (is_teams and 4 or 2) then return nil end
  if mem:read_u8(SCORE_LEFT) ~= mem:read_u8(SCORE_RIGHT) then return nil end
  local units = math.max(1, math.floor(30 / clock_spu + 0.5))
  P.gg_n = P.gg_n + 1
  P.gg_note = frame + 180; P.gg_text = "GOLDEN GOAL - 30 more seconds, the first goal wins"; P.gg_arg = nil
  if clock_run then clock_u0 = clock_u0 + units end
  log("golden goal: level at %d-%d - 30 s more (%d units, extension %d)", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), units, P.gg_n)
  return units
end

function scnp_gg_step()
  local P = SCNP_PK
  if P.race > 0 then scnp_race_step(); return end
  if P.gg_n == 0 or P.gg_end then return end
  if mem:read_u8(SCORE_LEFT) == mem:read_u8(SCORE_RIGHT) then return end
  P.gg_end = true
  P.gg_note = frame + 180; P.gg_text = "GOLDEN GOAL!"; P.gg_arg = nil
  clock_ours = true; mem:write_u16(CLOCK_ADDR, 1); clock_ours = false
  mem:write_u8(CLOCK_ADDR + 3, 1)
  log("golden goal: %d-%d at frame %d - the match ends", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), frame)
end

function scnp_race_step()
  local P = SCNP_PK
  if P.race_end or SCNP_PVE.on or nplayers ~= (is_teams and 4 or 2) then return end
  if not clock_start then P.race_told = false; return end
  if not P.race_told then P.race_told = true; P.gg_note = frame + 240; P.gg_text = "FIRST TO %d GOALS - the first to score %d wins"; P.gg_arg = P.race end
  local a, b = mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT)
  if math.max(a, b) < P.race or mem:read_u16(CLOCK_ADDR) == 0 then return end
  P.race_end = true
  P.gg_note = frame + 180; P.gg_text = "FIRST TO %d - WIN!"; P.gg_arg = P.race
  clock_ours = true; mem:write_u16(CLOCK_ADDR, 1); clock_ours = false
  mem:write_u8(CLOCK_ADDR + 3, 1)
  log("first to %d: %d-%d at frame %d - the match ends", P.race, a, b, frame)
end

function scnp_pk_seats()
  if scnp_swap then return SCNP_PK.b, SCNP_PK.a end
  return SCNP_PK.a, SCNP_PK.b
end

SCNP_SEL = {
  on = false, patched = false,
  ED = {
    cupsoc   = { cd = 0x0642ce, occ = { { 0x0650dc, 2, 0xa }, { 0x0651b6, 2, 0xa }, { 0x065290, 2, 0xa }, { 0x065900, 1, 0x8 },
                                        { 0x0659da, 1, 0x8 }, { 0x065ab4, 1, 0x8 }, { 0x066124, 1, 0x8 }, { 0x0661fe, 1, 0x8 },
                                        { 0x0662d8, 1, 0x8 }, { 0x066948, 1, 0x8 }, { 0x066a22, 1, 0x8 }, { 0x066afc, 1, 0x8 } } },
    cupsocs2 = { cd = 0x06600e, occ = { { 0x066e72, 2, 0xa }, { 0x066f4c, 2, 0xa }, { 0x067026, 2, 0xa }, { 0x067742, 1, 0x8 },
                                        { 0x06781c, 1, 0x8 }, { 0x0678f6, 1, 0x8 }, { 0x068012, 1, 0x8 }, { 0x0680ec, 1, 0x8 },
                                        { 0x0681c6, 1, 0x8 }, { 0x0688e2, 1, 0x8 }, { 0x0689bc, 1, 0x8 }, { 0x068a96, 1, 0x8 } } },
  },
}
SCNP_SEL.ED.cupsocs = SCNP_SEL.ED.cupsocs2

SCNP_SEL.mirror = false

function scnp_sel_code() return SCNP_SEL.on and (SCNP_SEL.mirror and (SCNP_SEL.fix and (SCNP_SEL.fix2 and 4 or 3) or 2) or 1) or 0 end

function scnp_sel_apply(on, mirror, fix, fix2)
  local S, E = SCNP_SEL, SCNP_SEL.ED[SCNP_GAME]
  local rg = manager.machine.memory.regions[":maincpu"]
  on = on and true or false
  mirror = on and mirror and true or false
  S.fix = mirror and fix and true or false
  S.fix2 = S.fix and fix2 and true or false
  if on == S.on and mirror == S.mirror and S.done then return end
  if not E or not rg then S.on = false; S.mirror = false; return end
  local sites = { { E.cd, { 0x5368, 0x0070 }, { 0x4e71, 0x4e71 }, on } }
  for _, o in ipairs(E.occ) do
    local a, bit, off = o[1], o[2], o[3]
    local n = (bit == 1) and 0 or (bit == 2) and 1 or (bit == 4) and 2 or 3
    sites[#sites + 1] = { a,
      { 0x4268, 0x0070, 0x3029, 0x0036, 0x0240, bit, 0x6600, 0x000a, 0x3029, off, 0x8168, 0x0070 },
      { 0x3169, 0x0004, 0x0070, 0x0829, n, 0x0037, 0x6608, 0x3029, off, 0x8168, 0x0070, 0x4e71 },
      on and (mirror and 4 or 3) or 2,
      { 0x4268, 0x0070, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71, 0x4e71 } }
  end
  sites[1][4] = on and 3 or 2
  local function is(st, k) for i, v in ipairs(st[k]) do if rg:read_u16(st[1] + 2 * (i - 1)) ~= v then return false end end; return true end
  for _, st in ipairs(sites) do
    if not is(st, 2) and not is(st, 3) and not (st[5] and is(st, 5)) then
      log("country select: the program is not the one the patch was made for (%06x) - left as it is", st[1]); S.on = false; S.mirror = false; return
    end
  end
  for _, st in ipairs(sites) do
    local want = st[4] == 4 and 5 or st[4]
    for i, v in ipairs(st[want]) do rg:write_u16(st[1] + 2 * (i - 1), v) end
  end
  S.patched = on; S.on = on; S.mirror = mirror; S.done = true
  if mirror then scnp_mirror_install() end
  log("country select: %s", not on and "the board's own (countdown, same country allowed)" or mirror and "no countdown, the same country may be picked (mirror matches)" or "no countdown, a taken country cannot be picked again")
end

SCNP_MIRROR = { tap = nil, A0 = 0x109ee0, A1 = 0x10a230, A2 = 0x109efc, A3 = 0x109f44, pc = 0x7cdc, rpc = 0x8726 }
function scnp_mirror_install()
  local M = SCNP_MIRROR
  if M.tap or SCNP_GAME ~= "cupsocs2" then return end
  local cpu = manager.machine.devices[":maincpu"]
  M.tap = mem:install_read_tap(M.A2, M.A2 + 1, "scnp_mirror", function(offset, data, mask)
    if (mask & 0xff00) == 0 or not SCNP_SEL.mirror or cpu.state["CURPC"].value ~= M.pc then return end
    local am, bt = mem:read_u8(M.A2), mem:read_u8(M.A3 + 2)
    if am & 3 ~= 3 or bt ~= 0xff then return end
    local team = mem:read_u8(M.A2 + 2)
    mem:write_u8(M.A2, am & 0xfd); mem:write_u8(M.A2 + 1, mem:read_u8(M.A2 + 1) - 1)
    mem:write_u8(M.A3 + 2, team); mem:write_u8(M.A3, mem:read_u8(M.A3) | 2); mem:write_u8(M.A3 + 1, mem:read_u8(M.A3 + 1) + 1)
    mem:write_u16(M.A0, mem:read_u16(M.A0) | 2)
    mem:write_u16(M.A1 + 0x1e + 2, mem:read_u16(M.A1 + 0x1e + 2) | 2)
    log("mirror match: both picked team %d - 2P goes to the other side at frame %d", team, frame)
    return (data & 0x00ff) | ((am & 0xfd) << 8)
  end)

  M.rtap = mem:install_read_tap(M.A1, M.A1 + 4 * 0x1e - 1, "scnp_mirror_restart", function(offset, data, mask)
    if (mask & 0x00ff) == 0 or not SCNP_SEL.fix or (offset - M.A1) % 0x1e ~= 0 or cpu.state["CURPC"].value ~= M.rpc then return end

    if SCNP_SEL.fix2 and (data & 0xff) == 0xff then return end
    local team = cpu.state["D0"].value & 0xff
    local right = (cpu.state["A2"].value & 0xffffff) >= 0x111e54 + 11 * 0xdc
    local sideb = (mem:read_u16(offset + 2) & 2) ~= 0
    return (data & 0xff00) | ((right == sideb) and team or (team ~ 0xff))
  end)
end

if is_host and not is_replay and cfg.teams ~= "pve" and cfg.players >= 2 then
  scnp_sel_apply(true, env("SCNP_MIRROR", "1") ~= "0" and SCNP_GAME == "cupsocs2" and not is_teams and cfg.players == 2, true, true)
end

SCNP_NOCREDIT = {
  cupsocs2 = { { 0x00ab9c, 0x55c8, 0x0000 }, { 0x00aba4, 0x5257, 0x4e71 }, { 0x00aa30, 0x05c8, 0x0000 }, { 0x00aa38, 0x5257, 0x4e71 },
               { 0x00abe8, 0x05e7, 0x0000 }, { 0x00abfe, 0x0642, 0x7400 }, { 0x00ac00, 0x05de, 0x4e71 }, { 0x00ac0c, 0x0642, 0x7400 },
               { 0x00ac0e, 0x05de, 0x4e71 },

               { 0x00a8ea, 0x15c0, 0x0000 }, { 0x00a8f2, 0x5257, 0x4e71 }, { 0x00a90c, 0x75c2, 0x0000 }, { 0x00a914, 0x5257, 0x4e71 },
               { 0x00a968, 0x15c0, 0x0000 }, { 0x00a970, 0x5257, 0x4e71 }, { 0x00a98c, 0x75c2, 0x0000 }, { 0x00a994, 0x5257, 0x4e71 },
               { 0x00a9ac, 0x05d0, 0x0000 }, { 0x00a9c6, 0x5e57, 0x4e71 }, { 0x00a9d0, 0x5257, 0x4e71 } },
  cupsoc   = { { 0x00a5fc, 0x55c8, 0x0000 }, { 0x00a604, 0x5257, 0x4e71 }, { 0x00a490, 0x05c8, 0x0000 }, { 0x00a498, 0x5257, 0x4e71 },
               { 0x00a648, 0x05e7, 0x0000 }, { 0x00a65e, 0x0642, 0x7400 }, { 0x00a660, 0x05de, 0x4e71 }, { 0x00a66c, 0x0642, 0x7400 },
               { 0x00a66e, 0x05de, 0x4e71 },
               { 0x00a34a, 0x15c0, 0x0000 }, { 0x00a352, 0x5257, 0x4e71 }, { 0x00a36c, 0x75c2, 0x0000 }, { 0x00a374, 0x5257, 0x4e71 },
               { 0x00a3c8, 0x15c0, 0x0000 }, { 0x00a3d0, 0x5257, 0x4e71 }, { 0x00a3ec, 0x75c2, 0x0000 }, { 0x00a3f4, 0x5257, 0x4e71 },
               { 0x00a40c, 0x05d0, 0x0000 }, { 0x00a426, 0x5e57, 0x4e71 }, { 0x00a430, 0x5257, 0x4e71 } },
}
SCNP_NOCREDIT.cupsocs = SCNP_NOCREDIT.cupsocs2
function scnp_nocredit_apply()
  local P, rg = SCNP_NOCREDIT[SCNP_GAME], manager.machine.memory.regions[":maincpu"]
  if not P or not rg then return end
  for _, p in ipairs(P) do
    local v = rg:read_u16(p[1])
    if v ~= p[2] and v ~= p[3] then log("credit text: the program is not the one the patch was made for (%06x) - left as it is", p[1]); return end
  end
  for _, p in ipairs(P) do rg:write_u16(p[1], p[3]) end
  log("credit text: hidden")
end
scnp_nocredit_apply()

SCNP_GOD = { on = false, fix = false, auto = false, side = {}, ED = { cupsoc = { 0x7F2E, 0x7F45, 0x7f66, 0x7cf4 }, cupsocs2 = { 0x7F5E, 0x7F8D, 0x7fbe, 0x7d16 } } }

SCNP_PVEGOD = { on = false, stage = 0,
  G = ({ cupsocs2 = { sel = 0x109c75, round = 0x109cab, lvl = 0x109ee4, me = 0x109efe, cpu = 0x109f46, pick = { 0x109c72, 0x109c76 }, beaten = 0x109c8a, played = 0x109c90, own = true,
                      nrpc = { [0x594ce] = true, [0x59534] = true, [0x5959a] = true, [0x59600] = true, [0x59666] = true, [0x596cc] = true, [0x59732] = true } },
         cupsocs  = { sel = 0x109c75, round = 0x109cab, lvl = 0x109ee4, me = 0x109efe, cpu = 0x109f46, pick = { 0x109c72, 0x109c76 }, beaten = 0x109c8a, played = 0x109c90, own = true,
                      nrpc = { [0x594ce] = true, [0x59534] = true, [0x5959a] = true, [0x59600] = true, [0x59666] = true, [0x596cc] = true, [0x59732] = true } },
         cupsoc   = { sel = 0x109b3d, round = 0x109b73, lvl = 0x109d54, me = 0x109d6e, cpu = 0x109db6, pick = { 0x109b3a, 0x109b3e }, beaten = 0x109b52, played = 0x109b58, own = false,
                      nrpc = { [0x59696] = true, [0x596fc] = true, [0x59762] = true, [0x597c8] = true, [0x5982e] = true, [0x59894] = true, [0x598fa] = true } } })[SCNP_GAME],

  order = { 10, 5, 4, 7, 8, 9, 0, 3 },

  grid = { 3, 9, 4, 10, 0, 7, 8, 5 } }

function scnp_pvegod_seven(me)
  local P, t = SCNP_PVEGOD, {}
  for _, c in ipairs(P.order) do if c ~= me and #t < 7 then t[#t + 1] = c end end
  return t
end

function scnp_pvegod_pick()
  local P = SCNP_PVEGOD
  for _, a in ipairs(P.G.pick) do
    local m = mem:read_u16(a) & 0xff
    for b = 0, 7 do if m & (1 << b) ~= 0 then return P.grid[b + 1] end end
  end
  return -1
end
function scnp_pvegod_step()
  local P = SCNP_PVEGOD
  local G = P.G
  if not P.on or not G or P.stage >= 2 then return end
  local ph = mem:read_u8(G.sel)
  if ph == 2 then

    if mem:read_u8(G.round) ~= 7 then mem:write_u8(G.round, 7) end
    if mem:read_u8(G.lvl) ~= 7 then mem:write_u8(G.lvl, 7) end
    local last = scnp_pvegod_seven(scnp_pvegod_pick())[7]
    if mem:read_u8(G.cpu) ~= last then mem:write_u8(G.cpu, last) end
    if P.stage == 0 then P.stage = 1; log("PvE vs GOD: round 8 of 8 from the country select (frame %d)", frame) end
    return
  end
  if P.stage ~= 1 or ph ~= 3 then return end
  local me = mem:read_u8(G.me)
  if me == 0xff then return end

  P.stage = 2
  local last = scnp_pvegod_seven(me)[7]
  mem:write_u16(G.beaten, 0x00ff)

  local mine = 1 << me
  mem:write_u16(G.played, G.own and 0x07b9 or (0x07b9 & ~mine))
  mem:write_u16(G.played + 2, (1 << last) | (G.own and mine or 0))
  log("PvE vs GOD: seven rounds won (team %d), the draw goes to GOD (frame %d)", me, frame)
end
function scnp_pvegod_apply(on)
  local P = SCNP_PVEGOD
  local G = P.G
  if not on or P.on or not G or not SCNP_PVE.on then return end
  P.on = true

  local cpu = manager.machine.devices[":maincpu"]
  P.tap = mem:install_read_tap(G.round - 1, G.round, "scnp_pvegod", function(offset, data, mask)
    if (mask & 0x00ff) ~= 0 and G.nrpc[cpu.state["CURPC"].value] then return data & 0xff00 end
  end)
  log("PvE: against GOD, one match - the last round")
end
function scnp_god_apply(on, fix, auto)
  local G = SCNP_GOD
  on = on and true or false
  fix = on and fix and true or false
  auto = on and auto and true or false
  if on == G.on and fix == G.fix and auto == G.auto then return end
  G.auto = auto
  for _, k in ipairs({ "tap", "wtap", "rtap" }) do if G[k] then G[k]:remove(); G[k] = nil end end
  G.on = false; G.fix = false; G.side = {}; G.pending = nil; G.armed = false
  if not on then log("GOD: off"); return end
  local r = G.ED[SCNP_GAME]
  local port = manager.machine.ioport.ports[":PLAYERS12"]
  local pass = port and port.fields["P1 Pass"]
  if not r or not pass then log("GOD: not available for %s", tostring(SCNP_GAME)); return end
  local m, dv = pass.mask, pass.defvalue & pass.mask
  local cpu = manager.machine.devices[":maincpu"]
  local selA = SCNP_PICK and SCNP_PICK.sel
  G.tap = mem:install_read_tap(r[1], r[2], "scnp_god", function(offset, data, mask)
    if (G.auto and G.armed) or (port:read() & m) ~= dv then
      if fix and cpu.state["CURPC"].value == r[3] then
        local v = (mask == 0x00ff) and (data & 0xff) or (data >> 8)
        if v >= 1 and v <= 11 then G.pending = v - 1 end
      end
      return 0x0C0C
    end
    return data
  end)
  if fix then
    local lo, hi = TEAM_LEFT & ~1, TEAM_RIGHT | 1

    G.wtap = mem:install_write_tap(lo, hi, "scnp_god_w", function(offset, data, mask)
      for _, a in ipairs({ TEAM_LEFT, TEAM_RIGHT }) do
        local hit = (a & ~1) == offset and ((a & 1) == 0 and mask & 0xff00 ~= 0 or (a & 1) == 1 and mask & 0x00ff ~= 0)
        if hit then
          local v = (a & 1) == 0 and (data >> 8) or (data & 0xff)
          if v == 11 and G.pending then G.side[a] = G.pending; G.pending = nil; log("GOD: picked over country %d", G.side[a])
          elseif v ~= 11 then G.side[a] = nil end
          if G.armed and v ~= 0xff then G.armed = false end
        end
      end
    end)
    G.rtap = mem:install_read_tap(lo, hi, "scnp_god_r", function(offset, data, mask)
      if not next(G.side) then return data end
      local pc = cpu.state["CURPC"].value
      if pc ~= r[4] and (pc < 0x50000 or pc >= 0x60000) then return data end
      for a, c in pairs(G.side) do
        if (a & ~1) == offset then
          if (a & 1) == 0 and mask & 0xff00 ~= 0 and (data >> 8) == 11 then data = (data & 0x00ff) | (c << 8) end
          if (a & 1) == 1 and mask & 0x00ff ~= 0 and (data & 0xff) == 11 then data = (data & 0xff00) | c end
        end
      end
      return data
    end)
  end
  G.on = true; G.fix = fix
  if auto then log("GOD: 1P plays as GOD - no country to pick (the confirm is pressed by itself)")
  else log("GOD: 1P holds Pass while confirming a country to play as GOD%s", fix and " (draws on that country)" or "") end
end

function scnp_god_autopress(b, mask)
  local G, P = SCNP_GOD, SCNP_PICK
  if b ~= 1 or not G.on or not G.auto or not P or not P.sel then return mask end
  if mem:read_u8(P.sel) ~= 2 or mem:read_u16(P.taken) ~= 0 then return mask end
  if not G.armed then G.armed = true; log("GOD: the country select - confirming for 1P (frame %d)", frame) end
  mask = mask & ~0x7f
  if frame % 8 < 2 then mask = mask | 0x10 end
  return mask
end
if is_host and not is_replay and cfg.teams == "pve" and env("SCNP_GOD", "") == "1" then scnp_god_apply(true, true, true) end
if is_host and not is_replay and cfg.teams == "pve" and env("SCNP_PVEGOD", "") == "1" then scnp_pvegod_apply(true) end

function scnp_write_result()
  result_written = true
  local rs1, rs2 = rec_score()
  local rt1, rt2 = mem:read_u8(TEAM_LEFT), mem:read_u8(TEAM_RIGHT)
  if scnp_swap then rt1, rt2 = rt2, rt1 end
  local names = SCNP_SAFE.names(pct_decode(env("SCNP_NAMES", "")))
  local pks = ""

  if SCNP_PK.state == "done" and not SCNP_PK.cut then local p1, p2 = scnp_pk_seats(); pks = string.format(',"pk":[%d,%d]', p1, p2) end
  if SCNP_PVEGOD.on then pks = pks .. ',"pvegod":1' end
  log('RESULT {"score":[%d,%d],"teams":[%d,%d],"time":%d,"frames":%d,"players":%d,"type":"%s","names":"%s"%s}',
      rs1, rs2, rt1, rt2, clock_secs, frame - (clock_start or frame), nplayers, SCNP_SAFE.type(cfg.teams), names, pks)
end

SCNP_LIVE = { key = nil, at = -100000 }
function scnp_live_step()
  if not is_host or is_replay or is_spec or not clock_start then return end
  local cur = mem:read_u16(CLOCK_ADDR)
  local a, b = rec_score()
  local key = a .. ":" .. b .. ":" .. cfg.delay
  if key == SCNP_LIVE.key and frame - SCNP_LIVE.at < 600 then return end
  SCNP_LIVE.key = key; SCNP_LIVE.at = frame
  log("LIVE %d %d %d %d", a, b, cur > 0 and math.floor(cur * clock_spu + 0.5) or 0, cfg.delay)
end
hud_names = {}
do
  local i = 1
  for n in (env("SCNP_NAMES", "") .. ","):gmatch("([^,]*),") do hud_names[i] = pct_decode(n); i = i + 1 end
end

hud_kinds = {}
do
  local i = 1
  for k in (env("SCNP_KINDS", "") .. ","):gmatch("([^,]*),") do hud_kinds[i] = (k == "W" or k == "P") and k or ""; i = i + 1 end
end

local function short_name(str, maxw)
  if not str or str == "" then return "" end
  local out, w = {}, 0
  local ok = pcall(function()
    for _, cp in utf8.codes(str) do
      local cw = (cp < 128) and 1 or 2
      if w + cw > maxw then break end
      out[#out + 1] = utf8.char(cp); w = w + cw
    end
  end)
  if not ok then return str:sub(1, maxw) end
  return table.concat(out)
end
local function text_w(str)
  local w = 0
  local ok = pcall(function() for _, cp in utf8.codes(str) do w = w + ((cp < 128) and 1 or 2) end end)
  if not ok then w = #str end
  return w * 4.2 * FS
end
local function hud_col(ms)
  if not ms then return 0xffb0b0b0 end
  if ms <= 60 then return 0xfff4f4f4 end
  if ms <= 120 then return 0xffffd98a end
  return 0xffff9c9c
end
local function box(x0, y0, x1, y1, c) screen:draw_box(x0, y0, x1, y1, c, c) end

SCNP_PF = {
  ["0"] = { 7, 5, 5, 5, 7 }, ["1"] = { 2, 6, 2, 2, 7 }, ["2"] = { 7, 1, 7, 4, 7 }, ["3"] = { 7, 1, 7, 1, 7 },
  ["4"] = { 5, 5, 7, 1, 1 }, ["5"] = { 7, 4, 7, 1, 7 }, ["6"] = { 7, 4, 7, 5, 7 }, ["7"] = { 7, 1, 1, 2, 2 },
  ["8"] = { 7, 5, 7, 5, 7 }, ["9"] = { 7, 5, 7, 1, 7 },
  A = { 2, 5, 7, 5, 5 }, B = { 6, 5, 6, 5, 6 }, C = { 3, 4, 4, 4, 3 }, E = { 7, 4, 6, 4, 7 }, F = { 7, 4, 6, 4, 4 },
  I = { 7, 2, 2, 2, 7 }, L = { 4, 4, 4, 4, 7 }, N = { 6, 5, 5, 5, 5 }, O = { 7, 5, 5, 5, 7 }, P = { 6, 5, 6, 4, 4 },
  S = { 3, 4, 2, 1, 6 }, T = { 7, 2, 2, 2, 2 }, U = { 5, 5, 5, 5, 7 }, D = { 6, 5, 5, 5, 6 }, Y = { 5, 5, 2, 2, 2 },
  H = { 5, 5, 7, 5, 5 }, ["/"] = { 1, 1, 2, 4, 4 },
  ["%"] = { 5, 1, 2, 4, 5 }, [":"] = { 2, 0, 0, 0, 2, w = 1 }, ["."] = { 0, 0, 0, 0, 2, w = 1 }, [" "] = { 0, 0, 0, 0, 0, w = 2 },
}

function scnp_pf_w(t)
  local n = 0
  for ch in t:upper():gmatch(".") do local g = SCNP_PF[ch]; if g then n = n + (g.w or 3) + 1 end end
  return math.max(0, n - 1)
end

function scnp_pf_draw(x, y, u, runs)
  for pass = 1, 2 do
    local cx = x
    for _, r in ipairs(runs) do
      for ch in r[1]:upper():gmatch(".") do
        local g = SCNP_PF[ch]
        if g then
          local gw = g.w or 3
          for row = 1, 5 do
            local bits = g[row]
            for col = 0, gw - 1 do
              local on = (gw == 1) and ((bits & 2) ~= 0) or ((bits >> (gw - 1 - col)) & 1) ~= 0
              if on then
                local px, py = cx + col * u, y + (row - 1) * u
                if pass == 1 then box(px - u * 0.5, py - u * 0.5, px + u * 1.5, py + u * 1.5, (r[2] & 0xff000000) | 0x101410)
                else box(px, py, px + u, py + u, r[2]) end
              end
            end
          end
          cx = cx + (gw + 1) * u
        end
      end
    end
  end
end

local function icon_stick(x, y, c)
  box(x + 1, y + 6, x + 7, y + 7, c)
  box(x + 3, y + 3, x + 5, y + 6, c)
  box(x + 2, y + 1, x + 6, y + 3, c)
  box(x + 3, y + 0, x + 5, y + 1, c)
end
local function icon_keyboard(x, y, c)
  box(x + 0, y + 2, x + 8, y + 7, c)
  local k = 0xff202020
  box(x + 1, y + 3, x + 2, y + 4, k); box(x + 3, y + 3, x + 4, y + 4, k); box(x + 5, y + 3, x + 6, y + 4, k)
  box(x + 2, y + 5, x + 6, y + 6, k)
end
local function icon_unknown(x, y, c) box(x + 2, y + 2, x + 6, y + 6, c) end

local hud_last_units, hud_clock_seen, hud_run, hud_prev_frame = -1, false, 0, 0
local function match_clock_text()
  local cur = mem:read_u16(CLOCK_ADDR)
  if cur > 0 then hud_clock_seen = true end
  if not hud_clock_seen then return string.format("%d:%02d", clock_secs // 60, clock_secs % 60), 1.0 end
  local df = frame - hud_prev_frame; hud_prev_frame = frame
  if cur ~= hud_last_units then hud_last_units = cur; hud_run = 0
  elseif df > 0 and df < 30 and (clock_run or (frame - hud_tick_frame) <= clock_fpu + 6) then hud_run = hud_run + df end

  local inside = 0
  if cur < clock_units0 then inside = math.min(clock_spu, hud_run / 60) end
  local rem = math.max(0, cur * clock_spu - inside)
  if cur == 0 then rem = 0 end
  local r = math.floor(rem + 0.5)
  return string.format("%d:%02d", r // 60, r % 60), (clock_secs > 0) and math.max(0, math.min(1, rem / clock_secs)) or 0
end

SCNP_POSS = { a = 0, b = 0, last = 0 }

function scnp_poss_step()
  local P = SCNP_POSS
  if P.sync and frame >= P.sync.f then
    P.a, P.b = P.sync.a, P.sync.b
    if P.sync.since < 100000 then hud_tick_frame = math.max(hud_tick_frame, P.sync.f - P.sync.since) end
    P.sync = nil
  end
  if SCNP_GAME ~= "cupsocs2" or phase ~= "play" or (frame - hud_tick_frame) > clock_fpu + 6 then return end
  local o = mem:read_u32(0x1138ae) & 0xffffff
  if o >= 0x111e54 and (o - 0x111e54) % 0xdc == 0 then
    local i = (o - 0x111e54) // 0xdc
    if i < 11 then P.a = P.a + 1 elseif i < 22 then P.b = P.b + 1 end
  end
end
local function draw_hud()
  if not cfg.hud or not screen or phase ~= "play" then return end
  local w = screen.width or 320
  box(0, 0, w, HUD_H, 0x8c000000)
  box(0, HUD_H, w, HUD_H + 1, 0x40000000)
  local x = 3
  for gi = 1, nplayers do

    local g = is_teams and ({ 1, 3, 2, 4 })[gi] or gi
    local seat = scnp_seat_of(g)
    local dev = hud_dev[seat] or 0
    local col = (seat == local_slot) and 0xffffe9a8 or 0xffe4e4e4

    local glyph = (dev == 2) and "◉" or ((dev == 1) and (cfg.web and "▦" or "⌨") or "·")
    screen:draw_text(x, 1, glyph, col, 0)
    x = x + ((dev == 1) and 11 or 8) * FS
    local ms = (seat == 1) and nil or hud_ping[seat]
    local label = string.format("%dP", g)

    local nm = short_name(hud_names[seat], (nplayers <= 2) and 16 or 8)
    if nm ~= "" then label = label .. " " .. nm end
    if (hud_kinds[seat] or "") ~= "" then label = label .. "(" .. hud_kinds[seat] .. ")" end
    screen:draw_text(x, 2, label, col, 0)
    x = x + text_w(label) + 2 * FS
    local ptxt = (seat == 1) and "host" or (ms and (ms .. "ms") or "--")
    if SCNP_PVE.gone[seat] or SCNP_PVE.dropped[seat] then ptxt = "left" end
    screen:draw_text(x, 2, ptxt, (seat == 1) and 0xffd8d8d8 or hud_col(ms), 0)
    x = x + text_w(ptxt) + 8 * FS
    if is_teams and gi == 2 then x = x + 4 * FS end
  end

  local clock, frac = match_clock_text()
  local ctext = (cfg.web and "◷ " or "⏱ ") .. clock

  local stag = (SCNP_SPEC.n or 0) > 0 and ("(" .. SCNP_SPEC.n .. ")") or nil
  local cx = w - 6 - #clock * 5.4 * FS - 12 - (stag and (text_w(stag) + 2 * FS) or 0)
  local ccol = (frac > 0.5) and 0xfff4f4f4 or ((frac > 0.25) and 0xffffd98a or 0xffff9c9c)
  screen:draw_text(cx, 2, ctext, ccol, 0)
  if stag then screen:draw_text(w - 4 - text_w(stag), 2, stag, 0xffb8d8ff, 0) end

  local bw, bh, bx, by = 18, 5, cx - 3 - 18, math.max(3, math.floor(HUD_H / 2 - 2))
  local bar_from = x - 8 * FS + 2

  do
    local right = bx - 6 - ((is_replay and 7 or (is_spec and 12 or 0)) * 4.0 + ((is_replay or is_spec) and 6 or 0)) * FS
    local stxt
    if SCNP_PK.state == "run" and SCNP_PK.seen then stxt = string.format("PK %d - %d", SCNP_PK.ha or 0, SCNP_PK.hb or 0)
    else
      if scnp_series == nil then
        local ft, a, b = env("SCNP_SERIES", ""):match("^(%d+),(%d+),(%d+)$")
        scnp_series = (ft and tonumber(ft) > 1) and { tonumber(ft), tonumber(a), tonumber(b) } or false
      end
      if scnp_series then

        local l, r = scnp_series[2], scnp_series[3]
        if scnp_swap then l, r = r, l end
        stxt = string.format("FT%d  %d - %d", scnp_series[1], l, r)
      end
    end
    if stxt then
      local sx = right - text_w(stxt)
      if sx > x then screen:draw_text(sx, 2, stxt, 0xffffe28a, 0) end
    end
  end
  if is_replay then
    local tx = math.max(x, bx - 6 - 7 * 4.0 * FS)
    screen:draw_text(tx, 2, "REPLAY", 0xffd8c88a, 0)
    bar_from = math.max(bar_from, tx + text_w("REPLAY") + 2)
  end
  if is_spec then
    local tag = (agg_max - frame > 90) and "watching >>" or "watching"
    local tx = math.max(x, bx - 6 - #tag * 4.0 * FS)
    screen:draw_text(tx, 2, tag, 0xffd8c88a, 0)
    bar_from = math.max(bar_from, tx + text_w(tag) + 2)
  end
  if bx >= bar_from then
    box(bx, by, bx + bw, by + bh, 0xc0303030)
    if frac > 0 then box(bx, by, bx + math.max(1, math.floor(bw * frac + 0.5)), by + bh, ccol) end
    box(bx, by + bh, bx + bw, by + bh + 1, 0x60ffffff)
  end

  local seated = SCNP_FREE and SCNP_G.pm and (mem:read_u8(SCNP_G.pm) >> (local_slot - 1)) & 1 == 1
  if is_teams and frame < 7200 and not seated and (SCNP_FREE or mem:read_u8(SCNP_G.credits) > 0 or frame < 200) then
    local hint = ({ "2v2: YOU pick the LEFT team's country (your teammate joins automatically)",
                    "2v2: YOU pick the RIGHT team's country (your teammate joins automatically)",
                    "2v2: your teammate picks the country - you join the LEFT side automatically",
                    "2v2: your teammate picks the country - you join the RIGHT side automatically" })[GAME_PLAYER[local_slot] or 0] or ""
    screen:draw_text(4, HUD_H + 3, scnp_tr(hint), 0xffffe080, 0xc0000000)
  end
  if SCNP_PVE.on and not is_spec and not is_replay and frame < 5400 and (mem:read_u8(SCNP_G.pm) >> (local_slot - 1)) & 1 == 0 then
    local hint = (local_slot == 1) and "PvE: press start (1) and pick the country - the others join your team after kick-off"
                 or "PvE: 1P picks the country - you join 1P's team automatically after kick-off"
    screen:draw_text(4, HUD_H + 3, scnp_tr(hint), 0xffffe080, 0xc0000000)
  end
  if SCNP_PK.gg_text and frame < SCNP_PK.gg_note then
    local t = scnp_tr(SCNP_PK.gg_text)
    if SCNP_PK.gg_arg then t = string.format(t, SCNP_PK.gg_arg, SCNP_PK.gg_arg) end
    local tw = text_w(t)
    box(w / 2 - tw / 2 - 6, HUD_H + 14, w / 2 + tw / 2 + 6, HUD_H + 16 + HUD_TH + 4, 0xd0000000)
    screen:draw_text("center", HUD_H + 16, t, 0xffffd24a, 0)
  end

  if SCNP_G.credits and mem:read_u8(SCNP_G.credits) > 0 then
    local h = screen.height or 224
    local x0, x1, y0, y1 = w * 340 / 960, w * 552 / 960, h * 664 / 720, h * 703 / 720
    local u = h / 240
    local ty = (y0 + y1) / 2 - 2.5 * u

    if SCNP_PVE.on and QC.top and ty + 6 * u > QC.top then ty = QC.top - 7 * u end
    local function line(runs, k)
      local t = ""; for _, r in ipairs(runs) do t = t .. r[1] end
      if k and k < 1 then
        local f = {}
        for i, r in ipairs(runs) do f[i] = { r[1], (math.floor(((r[2] >> 24) & 0xff) * k + 0.5) << 24) | (r[2] & 0xffffff) } end
        runs = f
      end
      scnp_pf_draw((x0 + x1) / 2 - scnp_pf_w(t) * u / 2, ty, u, runs)
    end

    local pt = SCNP_POSS.a + SCNP_POSS.b
    if pt >= 120 then

      SCNP_POSS.t0 = SCNP_POSS.t0 or frame
      local c = (frame - SCNP_POSS.t0) % 780
      local site = math.max(0, math.min(1, (c - 600) / 24, (780 - c) / 24))
      local pa = math.floor(SCNP_POSS.a * 100 / pt + 0.5)
      if site < 1 then
        line({ { "BALL  ", 0xff9fd8a8 }, { string.format("%d%%", pa), pa >= 50 and 0xffffd23f or 0xffffffff },
               { " : ", 0xffb0b0b0 }, { string.format("%d%%", 100 - pa), pa <= 50 and 0xffffd23f or 0xffffffff } }, 1 - site)
      end
      if site > 0 then line({ { "https://seibucup.online", 0xffe1e6e1 } }, site) end
    elseif scnp_series then
      local l, r = scnp_series[2], scnp_series[3]
      if scnp_swap then l, r = r, l end
      line({ { "FT" .. scnp_series[1] .. "  ", 0xffffd23f }, { string.format("%d : %d", l, r), 0xffffffff } })
    else
      line({ { "seibucup.online", 0xffe1e6e1 } })
    end

    if is_replay and SCNP_RPD then
      local d = SCNP_RPD.d0
      for i = 1, #SCNP_RPD.at do if frame >= SCNP_RPD.at[i] then d = SCNP_RPD.d[i] end end
      local t = "DELAY " .. d
      scnp_pf_draw(w * 0.868 - scnp_pf_w(t) * u / 2, ty, u, { { "DELAY ", 0xff9fd8a8 }, { tostring(d), 0xffffffff } })
      if d ~= SCNP_RPD.shown then SCNP_RPD.shown = d; log("replay: delay %d shown from frame %d", d, frame) end
    end
  end

  if not is_replay then
    local dy = (screen.height or 240) - 9
    if SCNP_PVE.on and QC.top and dy + 8 > QC.top then dy = QC.top - 9 end
    screen:draw_text(2, dy, "delay " .. tostring(cfg.delay), 0x80ffffff, 0)
  end
end

local C_INFO, C_WARN, C_ERR = 0xffe8e8e8, 0xffffd040, 0xffff5050
local overlay, overlay_color, overlay_hint = nil, C_INFO, nil

local TR = {
  ["NETPLAY: starting..."] = { ko = "NETPLAY: 시작하는 중...", ja = "NETPLAY: 開始しています...", zh = "NETPLAY: 正在启动..." },
  ["GOLDEN GOAL - 30 more seconds, the first goal wins"] = { ko = "골든골! 30초 연장 - 먼저 골을 넣으면 승리", ja = "ゴールデンゴール！30秒延長 - 先に決めた方の勝ち", zh = "金球！加时30秒 - 先进球者获胜" },
  ["GOLDEN GOAL!"] = { ko = "골든골!", ja = "ゴールデンゴール！", zh = "金球！" },
  ["FIRST TO %d GOALS - the first to score %d wins"] = { ko = "선취 %d골 - 먼저 %d골 넣으면 승리", ja = "%d点先取 - 先に%d点取った方の勝ち", zh = "先进%d球 - 先进%d球者获胜" },
  ["FIRST TO %d - 30 more seconds"] = { ko = "선취 %d골 - 30초 연장", ja = "%d点先取 - 30秒延長", zh = "先进%d球 - 加时30秒" },
  ["FIRST TO %d - WIN!"] = { ko = "선취 %d골 달성!", ja = "%d点先取 達成！", zh = "先进%d球 达成！" },
  ["NETPLAY: connecting..."] = { ko = "NETPLAY: 접속하는 중...", ja = "NETPLAY: 接続しています...", zh = "NETPLAY: 正在连接..." },
  ["NETPLAY: hosting on port %d, waiting for %d more player(s)..."] = { ko = "NETPLAY: 포트 %d 에서 대기 중, %d명 더 기다립니다...", ja = "NETPLAY: ポート %d で待機中、あと %d 人待っています...", zh = "NETPLAY: 在端口 %d 等待，还差 %d 名玩家..." },
  ["NETPLAY: connecting to %s:%d ... (attempt %d of 40)"] = { ko = "NETPLAY: %s:%d 에 접속 중... (%d/40회 시도)", ja = "NETPLAY: %s:%d に接続中... (%d/40 回目)", zh = "NETPLAY: 正在连接 %s:%d ... (第 %d/40 次)" },
  ["NETPLAY: connected to the relay, waiting for %d more player(s)..."] = { ko = "NETPLAY: 서버에 접속됨, %d명 더 기다립니다...", ja = "NETPLAY: サーバーに接続、あと %d 人待っています...", zh = "NETPLAY: 已连接服务器，还差 %d 名玩家..." },
  ["NETPLAY: connected, waiting for the host's reply..."] = { ko = "NETPLAY: 접속됨, 방장의 응답을 기다립니다...", ja = "NETPLAY: 接続しました、ホストの応答を待っています...", zh = "NETPLAY: 已连接，等待房主回应..." },
  ["NETPLAY: you are player %d of %d, waiting for the host to start..."] = { ko = "NETPLAY: %d/%d번 플레이어입니다. 방장의 시작을 기다립니다...", ja = "NETPLAY: あなたは %d/%d 番プレイヤー、ホストの開始を待っています...", zh = "NETPLAY: 你是第 %d/%d 名玩家，等待房主开始..." },
  ["NETPLAY: spectator mode - waiting for the host to start..."] = { ko = "NETPLAY: 관전 모드 - 방장의 시작을 기다립니다...", ja = "NETPLAY: 観戦モード - ホストの開始を待っています...", zh = "NETPLAY: 观战模式 - 等待房主开始..." },
  ["NETPLAY: spectator mode - joining the match in progress..."] = { ko = "NETPLAY: 관전 모드 - 진행 중인 경기에 합류하는 중...", ja = "NETPLAY: 観戦モード - 進行中の試合に合流しています...", zh = "NETPLAY: 观战模式 - 正在加入进行中的比赛..." },
  ["NETPLAY: %d of %d players here, waiting for the rest..."] = { ko = "NETPLAY: %d/%d명 도착, 나머지를 기다립니다...", ja = "NETPLAY: %d/%d 人が到着、残りを待っています...", zh = "NETPLAY: 已到 %d/%d 人，等待其余玩家..." },
  ["NETPLAY: saving the game state..."] = { ko = "NETPLAY: 게임 상태를 저장하는 중...", ja = "NETPLAY: ゲーム状態を保存しています...", zh = "NETPLAY: 正在保存游戏状态..." },
  ["NETPLAY: game state received, saving it..."] = { ko = "NETPLAY: 게임 상태를 받았습니다. 저장하는 중...", ja = "NETPLAY: ゲーム状態を受信、保存しています...", zh = "NETPLAY: 已收到游戏状态，正在保存..." },
  ["NETPLAY: waiting for the other player(s) to receive the state..."] = { ko = "NETPLAY: 다른 플레이어가 상태를 받기를 기다립니다...", ja = "NETPLAY: 他のプレイヤーの受信を待っています...", zh = "NETPLAY: 等待其他玩家接收状态..." },
  ["NETPLAY: state received, waiting for the host to start..."] = { ko = "NETPLAY: 상태 수신 완료, 방장의 시작을 기다립니다...", ja = "NETPLAY: 状態を受信、ホストの開始を待っています...", zh = "NETPLAY: 状态已接收，等待房主开始..." },
  ["NETPLAY: loading the game state..."] = { ko = "NETPLAY: 게임 상태를 불러오는 중...", ja = "NETPLAY: ゲーム状態を読み込んでいます...", zh = "NETPLAY: 正在载入游戏状态..." },
  ["NETPLAY ENDED: %s"] = { ko = "NETPLAY 종료: %s", ja = "NETPLAY 終了: %s", zh = "NETPLAY 已结束: %s" },
  ["close this window, then start again from the launcher"] = { ko = "이 창을 닫고 런처에서 다시 시작하세요", ja = "このウィンドウを閉じて、ランチャーからやり直してください", zh = "关闭此窗口，然后从启动器重新开始" },
  ["%dP left - game over"] = { ko = "%dP 가 나갔습니다 - 게임 종료", ja = "%dP が退出しました - ゲーム終了", zh = "%dP 已离开 - 游戏结束" },
  ["connection lost - no input from %s for %d s (frame %d)"] = { ko = "연결 끊김 - %s 의 입력이 %d초 동안 없습니다 (프레임 %d)", ja = "接続が切れました - %s からの入力が %d 秒ありません (フレーム %d)", zh = "连接中断 - %s 在 %d 秒内没有输入 (帧 %d)" },
  ["could not connect to %s:%d"] = { ko = "%s:%d 에 접속할 수 없습니다", ja = "%s:%d に接続できません", zh = "无法连接到 %s:%d" },
  ["a different MAME build - everybody must use the same mame.exe (get it from seibucup.online)"] = { ko = "MAME 빌드가 서로 다릅니다 - 모두 같은 mame.exe 를 써야 합니다 (seibucup.online 에서 받으세요)", ja = "MAME のビルドが異なります - 全員が同じ mame.exe を使う必要があります (seibucup.online から入手)", zh = "MAME 版本构建不同 - 所有人必须使用相同的 mame.exe（请从 seibucup.online 获取）" },
  ["the host's launcher is too old to let people watch - ask the host to restart their launcher (it updates itself)"] = { ko = "방장의 런처가 구버전이라 관전 화면을 받을 수 없습니다 - 방장이 런처를 다시 실행하면 자동으로 업데이트됩니다", ja = "ホストのランチャーが古いため観戦できません - ホストがランチャーを再起動すると自動更新されます", zh = "房主的启动器版本过旧，无法观战 - 请房主重启启动器（会自动更新）" },
  ["the host is not sending the match (it may have ended already) - try again from the launcher"] = { ko = "방장이 경기 화면을 보내지 않습니다 (이미 끝난 경기일 수 있습니다) - 런처에서 다시 시도해 주세요", ja = "ホストが試合を送ってきません (すでに終了している可能性があります) - ランチャーからやり直してください", zh = "房主没有发送比赛画面（可能已经结束）- 请从启动器重试" },
  ["no game state from the host in %d s"] = { ko = "%d초 동안 방장에게서 게임 상태를 받지 못했습니다", ja = "%d 秒間ホストからゲーム状態が届きません", zh = "%d 秒内未收到房主的游戏状态" },
  ["the host did not start within %d s"] = { ko = "방장이 %d초 안에 시작하지 않았습니다", ja = "ホストが %d 秒以内に開始しませんでした", zh = "房主在 %d 秒内未开始" },
  ["MAME version differs: player %d has %s, you have %s - everybody needs the same MAME build"] = { ko = "MAME 버전이 다릅니다: %dP 는 %s, 나는 %s - 모두 같은 MAME 빌드를 써야 합니다", ja = "MAME のバージョンが違います: %dP は %s、自分は %s - 全員が同じ MAME ビルドを使う必要があります", zh = "MAME 版本不同: %dP 为 %s，你为 %s - 所有人必须使用相同的 MAME 版本" },
  ["MAME version differs (host %s, you %s) - everybody needs the same MAME build"] = { ko = "MAME 버전이 다릅니다 (방장 %s, 나 %s) - 모두 같은 MAME 빌드를 써야 합니다", ja = "MAME のバージョンが違います (ホスト %s、自分 %s) - 全員が同じ MAME ビルドを使う必要があります", zh = "MAME 版本不同（房主 %s，你 %s）- 所有人必须使用相同的 MAME 版本" },
  ["protocol version mismatch (%d vs %d) - update netplay.lua on both sides"] = { ko = "프로토콜 버전이 다릅니다 (%d / %d) - 양쪽 모두 최신 패키지로 갱신하세요", ja = "プロトコルのバージョンが違います (%d / %d) - 両方とも最新パッケージに更新してください", zh = "协议版本不一致 (%d / %d) - 请双方都更新到最新版本" },
  ["The 2P side picks its country first - wait a moment"] = { ko = "2P 진영이 먼저 나라를 고릅니다 - 잠시 기다리세요", ja = "2P側が先に国を選びます - 少しお待ちください", zh = "2P方先选择国家 - 请稍候" },
  ["You may pick the same team as the other side"] = { ko = "같은 팀을 골라도 대전이 됩니다.", ja = "同じチームを選んでも対戦できます。", zh = "选择相同的队伍也可以对战。" },
  ["Wait until the game closes by itself"] = { ko = "자동종료 될 때까지 기다려주세요.", ja = "自動で閉じるまでお待ちください。", zh = "请等待游戏自动关闭。" },
  ["[Tip!] Closing the game by hand during a match, not letting it close by itself, may bring a penalty"] = { ko = "[중요팁!] 게임 중 자동이 아닌 강제 종료 시 패널티가 부여될 수 있습니다", ja = "[重要!] 試合中に自動ではなく強制終了すると、ペナルティが科されることがあります", zh = "[重要提示!] 比赛中非自动而是强制关闭游戏，可能会受到处罚" },
  ["Closing the window now can lose the match record"] = { ko = "지금 창을 닫으면 경기 기록이 남지 않을 수 있습니다", ja = "今ウィンドウを閉じると試合の記録が残らないことがあります", zh = "现在关闭窗口可能会丢失比赛记录" },
  ["Your side picks first - choose your country"] = { ko = "2P 진영 우선권: 먼저 나라를 고르세요", ja = "2P側優先: 先に国を選んでください", zh = "2P方优先：请先选择国家" },
  ["2v2: YOU pick the LEFT team's country (your teammate joins automatically)"] = { ko = "2v2: 당신이 왼쪽 팀의 나라를 고릅니다 (팀원은 자동으로 합류)", ja = "2v2: あなたが左チームの国を選びます (チームメイトは自動で合流)", zh = "2v2: 由你选择左队的国家 (队友自动加入)" },
  ["2v2: YOU pick the RIGHT team's country (your teammate joins automatically)"] = { ko = "2v2: 당신이 오른쪽 팀의 나라를 고릅니다 (팀원은 자동으로 합류)", ja = "2v2: あなたが右チームの国を選びます (チームメイトは自動で合流)", zh = "2v2: 由你选择右队的国家 (队友自动加入)" },
  ["2v2: your teammate picks the country - you join the LEFT side automatically"] = { ko = "2v2: 팀원이 나라를 고릅니다 - 당신은 왼쪽 팀에 자동 합류", ja = "2v2: チームメイトが国を選びます - あなたは左チームに自動で合流", zh = "2v2: 队友选择国家 - 你将自动加入左队" },
  ["2v2: your teammate picks the country - you join the RIGHT side automatically"] = { ko = "2v2: 팀원이 나라를 고릅니다 - 당신은 오른쪽 팀에 자동 합류", ja = "2v2: チームメイトが国を選びます - あなたは右チームに自動で合流", zh = "2v2: 队友选择国家 - 你将自动加入右队" },
  ["PvE: press start (1) and pick the country - the others join your team after kick-off"] = { ko = "PvE: 시작(1)을 누르고 나라를 고르세요 - 다른 사람들은 킥오프 뒤 당신 팀에 합류합니다", ja = "PvE: スタート(1)を押して国を選んでください - 他の人はキックオフ後にあなたのチームへ合流します", zh = "PvE: 按开始(1)并选择国家 - 其他人会在开球后加入你的队伍" },
  ["PvE: 1P picks the country - you join 1P's team automatically after kick-off"] = { ko = "PvE: 1P가 나라를 고릅니다 - 킥오프 뒤 1P 팀에 자동으로 합류합니다", ja = "PvE: 1P が国を選びます - キックオフ後に 1P のチームへ自動で合流します", zh = "PvE: 由 1P 选择国家 - 开球后你会自动加入 1P 的队伍" },
}
local function tr(fmt)
  local t = TR[fmt]
  return (t and t[cfg.lang]) or fmt
end

function scnp_tr(fmt) return tr(fmt) end
local function set_overlay(color, fmt, ...)
  overlay, overlay_color, overlay_hint = string.format(tr(fmt), ...), color, nil
end
local function draw_overlay()
  if not screen or not overlay then return end
  screen:draw_text(4, 4, overlay, overlay_color, 0xc0000000)
  if overlay_hint then screen:draw_text(4, 13, overlay_hint, C_INFO, 0xc0000000) end
end

local function lose(fmt, ...)
  local msg = string.format(fmt, ...)
  status("%s", msg)
  set_overlay(C_ERR, "NETPLAY ENDED: %s", string.format(tr(fmt), ...))

  if fmt ~= "%dP left - game over" then log("LOST %s", string.format(tr(fmt), ...)) end
  overlay_hint = tr("close this window, then start again from the launcher")
  clear_all_inputs()
  phase = "lost"
  if SCNP_SHADOW then log("the server's watcher: the match is gone - closing"); machine:exit() end
end

local function prefill()
  for f = 1, cfg.delay do
    agg[f] = zeros()
    if is_host then for s = 1, 4 do inputs[s][f] = 0 end end
  end
  last_broadcast = cfg.delay
  SCNP_DD.hi = {}; SCNP_DD.last = {}; SCNP_DD.pw = {}
end

local CREDITS_ADDR = SCNP_G.credits
local auto = {}
local allow = { 0xff, 0xff, 0xff, 0xff }
if is_teams then allow = { 0x3f, 0x3f, 0x00, 0x00 } end
if SCNP_PVE.on then allow = { 0xff, 0x00, 0x00, 0x00 } end
local aj = { stage = SCNP_FREE and "start" or "coins", at = 0, c0 = 0, tries = 0 }
local function credits() return mem:read_u8(CREDITS_ADDR) + SCNP_FREE_ADD end
local function schedule(slot, from, len, bits)
  for X = from, from + len - 1 do
    local a = auto[X]; if not a then a = { 0, 0, 0, 0 }; auto[X] = a end
    a[slot] = a[slot] | bits
  end
end

function scnp_pve_step()
  local P, G = SCNP_PVE, SCNP_G
  local X = last_broadcast + cfg.delay + 2
  local pm = mem:read_u8(G.pm)

  if not P.saw_start then return end

  P.rsince = P.rsince or {}
  for s = 2, nplayers do
    local bit = 1 << (s - 1)
    local inside, onL, onR = pm & bit ~= 0, mem:read_u8(G.tm) & bit ~= 0, mem:read_u8(G.tm + 0x48) & bit ~= 0
    if P.dropped[s] then allow[s] = 0; P.rsince[s] = nil
    elseif inside and onL then
      P.rsince[s] = nil
      if allow[s] == 0 then
        allow[s] = 0x3f; if P.cur == s then P.cur = nil end; P.gone[s] = nil
        log("PvE: %dP is on 1P's team (left team humans %02x, right team humans %02x) at frame %d%s", s, mem:read_u8(G.tm), mem:read_u8(G.tm + 0x48), frame, P.jat and P.jat[s] and string.format(", %d frames after his START", frame - P.jat[s]) or ""); status("PvE: %dP joined 1P's team", s)
      end
    elseif inside then
      allow[s] = 0
      if onR then
        P.rsince[s] = P.rsince[s] or frame
        if frame - P.rsince[s] > 180 and not P.mark[s] then
          P.mark[s] = true; P.rsince[s] = nil
          log("PvE: %dP stayed on the CPU's team - taking him out to bring him to 1P's", s)
        end
      end
    else
      P.rsince[s] = nil
      if allow[s] ~= 0 then allow[s] = 0; log("PvE: %dP is out of the game (frame %d)", s, frame) end
    end
  end

  local clock, sl, sr = mem:read_u16(CLOCK_ADDR), mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT)
  if clock > 5 and P.match ~= "on" then P.match = "on"; P.base = { sl, sr }; P.cont_at = nil end
  if P.match == "on" and clock == 0 and clock_start then
    P.match = "over"
    local dl, dr = sl - P.base[1], sr - P.base[2]
    if dl <= dr then P.cont_at = frame; log("PvE: full time %d-%d - continuing", dl, dr)
    else log("PvE: full time %d-%d - on to the next round", dl, dr) end
  end
  if P.cont_at then
    local d = frame - P.cont_at
    if d == 300 and mem:read_u8(CREDITS_ADDR) == 0 then schedule(1, X, 6, 0x80) end
    if d >= 360 and (d - 360) % 90 == 0 then schedule(1, X, 6, 0x40) end
    if d > 3000 then P.cont_at = nil end
  end

  if P.cur and frame - P.at < 180 then return end
  P.cur = nil
  local ticking = clock_start ~= nil and clock > 0 and (frame - hud_tick_frame) <= clock_fpu + 6
  if not ticking or frame < P.next_try or pm & 1 == 0 then return end

  local k, cr = 0, mem:read_u8(CREDITS_ADDR)
  for s = 2, nplayers do

    if not P.dropped[s] and pm & (1 << (s - 1)) == 0 then
      local t = X + k * 20
      if cr <= k then schedule(s, t, 6, 0x80) end

      schedule(s, t + 30, 6, 0x40); schedule(s, t + 35, 30, 0x04)
      schedule(s, t + 75, 6, 0x10)
      P.jat = P.jat or {}; P.jat[s] = t + 30
      P.tries[s] = (P.tries[s] or 0) + 1
      log("PvE: bringing %dP onto 1P's team (try %d)", s, P.tries[s])
      k = k + 1
    end
  end
  if k > 0 then P.cur, P.at, P.next_try = true, frame, frame + 200 end
end

function scnp_pve_left(s)
  local P = SCNP_PVE
  if P.dropped[s] then return end
  P.dropped[s] = true; P.mark[s] = true; allow[s] = 0
  inputs[s] = {}
  log("PvE: %dP left - the CPU takes over his man", s); status("PvE: %dP left - the match goes on", s)
end

function scnp_pve_unlabel(s)
  local base, top = 0x102000, 0x5e8 + 4 * (s - 1)
  for a = base, base + 0xf7e - 0x80, 2 do
    if mem:read_u16(a) & 0xfff == top and mem:read_u16(a + 0x80) & 0xfff == top + 1 then
      local function mark(x) local t = mem:read_u16(x) & 0xfff; return t >= 0x5e8 and t < 0x5f8 end
      local x = a
      while mark(x + 4) do
        for r = 0, 0x80, 0x80 do
          mem:write_u16(x + r, mem:read_u16(x + 4 + r)); mem:write_u16(x + 2 + r, mem:read_u16(x + 6 + r))
        end
        x = x + 4
      end
      for r = 0, 0x80, 0x80 do mem:write_u16(x + r, 0); mem:write_u16(x + 2 + r, 0) end
      log("PvE: %dP's mark under the score taken off", s)
      return
    end
  end
end
function scnp_pve_drop(s)
  local G, bit = SCNP_G, 1 << (s - 1)
  local pm = mem:read_u8(G.pm)
  if pm & bit ~= 0 then
    mem:write_u8(G.pm, pm & ~bit)
    for _, o in ipairs({ 0, 0x48 }) do
      local tm = mem:read_u8(G.tm + o)
      if tm & bit ~= 0 then mem:write_u8(G.tm + o, tm & ~bit); mem:write_u8(G.tc + o, math.max(0, mem:read_u8(G.tc + o) - 1)) end
    end
    mem:write_u8(G.pc, math.max(0, mem:read_u8(G.pc) - 1))
    local c = G.ctl + (s - 1) * 0x1e
    local man = mem:read_u32(c + 4) & 0xffffff
    if man ~= 0 then mem:write_u8(man + 0xc8, 0) end
    mem:write_u16(c, 0x00ff); mem:write_u16(c + 2, 0); mem:write_u32(c + 4, 0); mem:write_u32(c + 8, 0)
    scnp_pve_unlabel(s)
  end
  SCNP_PVE.gone[s] = true
  log("PvE: %dP taken out of the game at frame %d", s, frame)
end

SCNP_VS = { stage = "watch", hit = nil, at = 0, tries = 0 }
SCNP_SPEC = { n = 0 }
SCNP_WAIT = { on = false, deadline = 0, t0 = 0 }
function scnp_vs_start_step()
  local V = SCNP_VS
  if V.stage == "done" then return end
  local pm = SCNP_G.pm and mem:read_u8(SCNP_G.pm)
  if V.stage == "watch" then

    if V.hit then V.stage = "press"; V.at = frame; log("versus: seat %d pressed start at frame %d - bringing the other side in", V.hit[2], V.hit[1]) end
    return
  end
  if V.stage == "press" then
    if frame - V.at < 20 then return end
    local X, n = last_broadcast + cfg.delay + 2, 0
    for b = 1, 2 do
      if not pm or pm & (1 << (b - 1)) == 0 then schedule(scnp_seat_of(b), X + n * 10, 6, 0x40); n = n + 1 end
    end
    V.stage = "check"; V.at = frame
  elseif V.stage == "check" then
    if frame - V.at < 90 then return end
    if not pm or pm & 3 == 3 then
      V.stage = "done"; log("versus: both sides are on the country select")
    else
      V.tries = V.tries + 1
      if V.tries >= 5 then V.stage = "done"; log("versus: the other side did not come in (player mask %02x)", pm)
      else V.stage = "press"; V.at = frame - 20 end
    end
  end
end

local function autojoin_step()
  if SCNP_PVE.on then if is_host then scnp_pve_step() end return end
  if is_host and not is_teams and not is_replay and nplayers >= 2 then scnp_vs_start_step() return end
  if not (is_host and is_teams) then return end

  if not aj.tick and clock_start and (frame - hud_tick_frame) <= clock_fpu + 6 then aj.tick = frame end
  if aj.stage == "done" then return end
  local X = last_broadcast + cfg.delay + 2
  local c = credits()
  if aj.stage == "coins" then
    if frame < 30 then return end
    for s = 1, 4 do schedule(s, X, 6, 0x80) end
    aj.stage, aj.at, aj.c0 = "coins_wait", frame, c
  elseif aj.stage == "coins_wait" then
    if frame - aj.at < 120 then return end
    if c >= aj.c0 + 4 then aj.stage = "start"; aj.tries = 0; log("2v2: coins accepted (%d credits)", c)
    else
      aj.stage = "coins"; aj.tries = aj.tries + 1
      log("2v2: coins try %d: credits %d -> %d (frame %d, agg %d)", aj.tries, aj.c0, c, frame, last_broadcast)
      if aj.tries > 30 then lose("2v2: the game does not accept coins") end
    end
  elseif aj.stage == "start" then
    if frame < 30 then return end
    schedule(scnp_seat_of(1), X, 6, 0x40); schedule(scnp_seat_of(2), X + 10, 6, 0x40)
    aj.stage, aj.at, aj.c0 = "start_wait", frame, c
  elseif aj.stage == "start_wait" then
    if frame - aj.at < 120 then return end
    if c <= aj.c0 - 2 then
      aj.stage = SCNP_G.tm and "join" or "join2"; aj.tries = 0
      log("2v2: seats %d and %d are picking the countries (credits %d)", scnp_seat_of(1), scnp_seat_of(2), c)
      status("2 vs 2: 1P and 2P pick the countries; 3P and 4P join their teams automatically")
    else aj.stage = "start"; aj.tries = aj.tries + 1; if aj.tries > 90 then lose("2v2: could not start the game") end end
  elseif aj.stage == "join" then

    local G = SCNP_G
    aj.js = aj.js or { [3] = { st = "wait" }, [4] = { st = "wait" } }
    local busy = aj.js[3].st == "press" or aj.js[4].st == "press"
    local all = true
    for _, b in ipairs({ 3, 4 }) do
      local s = scnp_seat_of(b)
      local j, bit = aj.js[b], 1 << (b - 1)
      local mine, other = (b == 3) and G.tm or G.tm + 0x48, (b == 3) and G.tm + 0x48 or G.tm
      if j.st ~= "in" and mem:read_u8(mine) & bit ~= 0 then
        j.st = "in"; allow[s] = 0x3f
        log("2v2: %dP is in on the %s team at frame %d%s", s, b == 3 and "left" or "right", frame, aj.tick and string.format(" (%d frames after the clock started ticking)", frame - aj.tick) or " (before kick-off)")
      elseif j.st ~= "in" and j.st ~= "wrong" and mem:read_u8(other) & bit ~= 0 then
        j.st = "wrong"; allow[s] = 0x3f
        log("2v2: %dP came in on the wrong team (left %02x, right %02x)", s, mem:read_u8(G.tm), mem:read_u8(G.tm + 0x48))
      elseif j.st == "press" then
        if c < j.c0 then
          j.st, j.at = "choose", frame
          if b == 3 then schedule(s, X, 25, 0x04) end
          schedule(s, X + 35, 6, 0x10)
          log("2v2: the board took %dP's start (frame %d)", s, j.x)
        elseif frame > j.x + 8 then j.st = "wait" end
      elseif j.st == "wait" and not busy and frame >= (j.next or 0) then
        schedule(s, X, 6, 0x40); j.st, j.x, j.c0, j.next = "press", X, c, X + 30; busy = true
      elseif j.st == "choose" and frame - j.at > 420 then j.st = "wait"
      end
      if j.st ~= "in" and j.st ~= "wrong" then all = false end
    end
    if all then aj.stage = "done"; log("2v2: everybody is in"); status("2 vs 2: everybody is in!") end
  elseif aj.stage == "join2" then
    schedule(scnp_seat_of(3), X, 6, 0x40); schedule(scnp_seat_of(3), X + 10, 25, 0x04)
    aj.stage, aj.at, aj.c0 = "join2_wait", frame, c
  elseif aj.stage == "join2_wait" then
    if frame - aj.at < 150 then return end
    if c < aj.c0 then allow[scnp_seat_of(3)] = 0x3f; aj.stage = "join4"; log("2v2: seat %d joined the left team (credits %d)", scnp_seat_of(3), c)
    else aj.stage = "join2" end
  elseif aj.stage == "join4" then
    schedule(scnp_seat_of(4), X, 6, 0x40)
    aj.stage, aj.at, aj.c0 = "join4_wait", frame, c
  elseif aj.stage == "join4_wait" then
    if frame - aj.at < 150 then return end
    if c < aj.c0 then allow[scnp_seat_of(4)] = 0x3f; aj.stage = "done"; log("2v2: seat %d joined the right team - everybody is in", scnp_seat_of(4)); status("2 vs 2: everybody is in!")
    else aj.stage = "join4" end
  end
end

SCNP_DDW = { n = 0, ms = 0, max = 0, b17 = 0, t = nil, f = nil }
function scnp_ddw_add(ms)
  local W = SCNP_DDW
  if ms > 17 then stats.late_ms = stats.late_ms + (ms - 17) end
  W.n = W.n + 1; W.ms = W.ms + ms
  if ms > W.max then W.max = ms end
  if ms >= 17 then W.b17 = W.b17 + 1 end
end
function scnp_ddw_log()
  local W = SCNP_DDW
  if is_replay or phase ~= "play" or frame % 300 ~= 0 then return end
  local t = now_ms()
  if W.t and W.f and frame > W.f then
    local ping = {}
    for s = 1, 4 do if rtt[s] then ping[#ping + 1] = string.format("%d:%d", s, rtt[s]) end end
    log("DDW frame %d %s delay %d fps %.1f waits %d total %d max %d over17 %d pings %s", frame, is_host and "host" or "guest",
        cfg.delay, (frame - W.f) * 1000 / math.max(1, (t - W.t) & 0xffffffff), W.n, math.floor(W.ms), math.floor(W.max), W.b17,
        table.concat(ping, ","))
  end
  W.t, W.f = t, frame
  W.n, W.ms, W.max, W.b17 = 0, 0, 0, 0
end
SCNP_DD = { on = env("SCNP_DYNDELAY", "1") ~= "0", hi = {}, last = {}, pw = {}, at = 0, prev = nil, calm = 0, changed = 0,
            lowered = -100000, floor = 0, floor_until = 0, min = 2, max = 8, cw = nil }
function scnp_dd_set(nd, why)
  local D = SCNP_DD
  local od = cfg.delay
  if nd == od then return end
  cfg.delay = nd; D.changed = frame; D.calm = 0

  if nd < od then D.lowered = frame; D.lowfrom = od
  elseif D.lowfrom and nd == D.lowfrom and frame - D.lowered < 3600 then D.floor = nd; D.floor_until = frame + 7200; D.lowfrom = nil
  else D.lowfrom = nil end
  broadcast("L" .. string.char(gen, nd))
  log("input delay %d -> %d frames at frame %d (%s)", od, nd, frame, why)

  D.hist = D.hist or {}
  if #D.hist < 60 then D.hist[#D.hist + 1] = string.format("%d>%d@%d", od, nd, frame) end
end
function scnp_dd_host()

  local D = SCNP_DD
  if not D.on or is_replay or phase ~= "play" then return end
  if frame - D.at < 300 then return end
  D.at = frame

  if frame < 900 then
    D.prev = stats.late_ms
    for s = 2, 4 do D.pw[s] = nil end
    return
  end
  local mine = D.prev and (stats.late_ms - D.prev) or 0
  D.prev = stats.late_ms
  local worst, who = mine, 1
  for s = 2, 4 do local w = D.pw[s]; if w and w > worst then worst, who = w, s end; D.pw[s] = nil end
  local d = cfg.delay

  local bad = worst > 150
  local raise = bad and (D.badprev or worst >= 400)
  D.badprev = bad
  if bad and not raise then
    D.calm = 0
    log("input delay: %dP lost %d ms in 5 s - held at %d unless it happens again", who, math.floor(worst), d)
  elseif raise then
    D.calm = 0

    local ping = 0
    for s = 2, nplayers do if rtt[s] and rtt[s] > ping then ping = rtt[s] end end
    local cap = math.min(D.max, math.max(3, math.ceil((ping / 2 + 10 + 16.7) / 16.7)) + 2)
    if d < cap and frame - D.changed >= 300 then scnp_dd_set(d + 1, string.format("%dP lost %d ms in 5 s", who, math.floor(worst)))
    elseif d >= cap and not D.capped then
      D.capped = true
      log("input delay: held at %d - %dP lost %d ms in 5 s but the pings (%d ms) need less: a machine running slow, not the line", d, who, math.floor(worst), ping)
    end
  elseif worst < 60 then
    D.calm = D.calm + 300
    local ping = 0
    for s = 2, nplayers do if rtt[s] and rtt[s] > ping then ping = rtt[s] end end
    local lowest = (frame < D.floor_until) and math.max(D.min, D.floor) or D.min
    if frame - D.changed >= 300 and d > lowest and ping < (d - 1) * 16.7 - 8 then
      scnp_dd_set(d - 1, string.format("5 s calm, ping %d ms", ping))
    end
  else
    D.calm = 0
  end
end
function scnp_dd_report()
  local D = SCNP_DD
  if is_host or is_spec or is_replay or phase ~= "play" or frame % 300 ~= 0 then return end
  local w = D.cw and (stats.late_ms - D.cw) or 0
  D.cw = stats.late_ms
  send_to(host_peer, "W" .. string.char(gen) .. string.pack("<I2", math.min(65535, math.max(0, math.floor(w)))))
end

local function try_broadcast()
  local guard = 0
  while guard < 64 do
    local X = last_broadcast + 1
    local masks = {}
    local a = auto[X]
    for s = 1, nplayers do
      local m = inputs[s][X]

      if m == nil and (SCNP_DD.hi[s] or 0) > X then m = SCNP_DD.last[s] or 0 end
      if m == nil then
        local lv = SCNP_PVE.late[s] and SCNP_PVE.live[s]
        if SCNP_PVE.dropped[s] or (SCNP_PVE.joining and SCNP_PVE.joining[s]) or (SCNP_PVE.late[s] and (not lv or X < lv)) then m = 0 else return end
      end
      SCNP_DD.last[s] = m
      masks[s] = (m & allow[s]) | (a and a[s] or 0)
      if SCNP_PVE.mark[s] then masks[s] = 0xff end
    end
    if SCNP_PVE.on and masks[1] & 0x40 ~= 0 then SCNP_PVE.saw_start = true end

    if SCNP_VS and SCNP_VS.stage == "watch" and not SCNP_VS.hit then
      for s2 = 1, nplayers do if masks[s2] & 0x40 ~= 0 then SCNP_VS.hit = { X, s2 } end end
    end
    for s = nplayers + 1, 4 do masks[s] = a and a[s] or 0 end

    for s = 2, 4 do if SCNP_PVE.mark[s] and masks[s] == 0xff then SCNP_PVE.mark[s] = nil end end
    auto[X] = nil
    agg[X] = masks
    broadcast("A" .. string.char(gen) .. u32le(X) .. string.char(masks[1], masks[2], masks[3], masks[4]))
    for s = 1, nplayers do inputs[s][X] = nil end
    last_broadcast = X
    guard = guard + 1
  end
end

function scnp_load_latch()
  if not SCNP_LOADIN or not reloading or not spec_base then SCNP_LOADIN = nil; return end
  local a1 = agg[spec_base + 1]
  if a1 then for s = 1, 4 do apply_input(s, (SCNP_PVE.on and s >= 2 and a1[s] == 0xff) and 0 or a1[s]) end end
end
local function begin_sync(reason)

  do local P = SCNP_PVE; if P.cont_at then P.cont_at = P.cont_at - frame end; P.cur = nil; P.next_try = 0; P.joining = nil end
  gen = (gen + 1) & 0xff
  if gen == 0 then gen = 1 end
  phase = "sync"; phase_since = os.time()
  for s = 1, 4 do inputs[s] = {} ; peer_sums[s] = {} end
  for _, p in pairs(peers) do p.loaded = false end
  agg = {}; local_sums = {}
  auto = {}; aj.stage = aj.stage:gsub("_wait$", ""); aj.at = 0
  resync_pending = false
  machine:save(STATE_NAME)
  save_requested_at = os.time()
  set_overlay(C_INFO, "NETPLAY: saving the game state...")
  log("%s: saving state (gen %d)", reason, gen)
end

local function start_load()
  phase = "loading"; phase_since = os.time()
  reloading = true
  load_started = os.time()
  clear_all_inputs()
  if spec_base then SCNP_LOADIN = true; scnp_load_latch() end
  if not SCNP_QUIET then set_overlay(C_INFO, "NETPLAY: loading the game state...") end
  machine:load(STATE_NAME)
end

local function enter_ready()
  phase = "ready"; phase_since = os.time()
  if is_host then set_overlay(C_INFO, "NETPLAY: waiting for the other player(s) to receive the state...")
  else set_overlay(C_INFO, "NETPLAY: state received, waiting for the host to start...") end
end

local function on_post_load()
  clear_all_inputs()
  scnp_bgm_after_load()
  SCNP_POPCLEAR = 3
  if is_replay then
    frame = 0; agg = {}; phase = "play"; reloading = false; load_started = nil; overlay = nil; rp_phase = "play"
    log("replay: segment %d loaded, continuing from input %d", rp_seg - 1, rp_pos)
    return
  end
  if not spec_base and not is_replay then
    local st = read_state_file(STATE_NAME)
    if st then rec_segments[#rec_segments + 1] = { at = #rec_inputs, state = st } end
  end
  if spec_base then

    frame = spec_base
    if SCNP_SPEC_HIST then for f, a in pairs(SCNP_SPEC_HIST) do if f > spec_base and not agg[f] then agg[f] = a end end end
    for f in pairs(agg) do if f <= spec_base then agg[f] = nil end end
    log("resumed at frame %d, %d aggregate frame(s) buffered", frame, (function() local n = 0 for _ in pairs(agg) do n = n + 1 end return n end)())
    spec_base = nil

    local a1 = agg[frame + 1]
    if a1 then
      if SCNP_FREE and mem:read_u8(CREDITS_ADDR) <= 3 then mem:write_u8(CREDITS_ADDR, 9) end
      if SCNP_RELOAD and mem:read_u8(CLOCK_ADDR + 2) ~= SCNP_RELOAD then mem:write_u8(CLOCK_ADDR + 2, SCNP_RELOAD) end
      if SCNP_PVE.on then for s = 2, 4 do if a1[s] == 0xff then scnp_pve_drop(s) end end end
      for s = 1, 4 do apply_input(s, (SCNP_PVE.on and s >= 2 and a1[s] == 0xff) and 0 or a1[s]) end
    else log("resumed without the input of frame %d", frame + 1) end
  else
    frame = 0
    prefill()
  end
  phase = "play"
  resync_pending = false
  reloading = false
  load_started = nil
  overlay = nil
  SCNP_QUIET = nil
  if is_spec then status("netplay synchronised: %d players, you are spectating", nplayers)
  else status("netplay synchronised: %d players, you are player %d, delay %d frames", nplayers, local_slot, cfg.delay) end
end

SCNP_NOCHAT = env("SCNP_NOCHAT", "") == "1"
QC = {
  T = {
    { ko = "안녕하세요! 잘 부탁해요", en = "Hi! Have a good game" },
    { ko = "나이스 슛!", en = "Nice shot!" },
    { ko = "아깝다~!", en = "So close!" },
    { ko = "나이스 패스!", en = "Nice pass!" },
    { ko = "감사합니다!", en = "Thanks!" },
    { ko = "미안해요 ㅠ", en = "Sorry!" },
    { ko = "한게임 더 해요!", en = "One more game!" },
    { ko = "수고하셨습니다!", en = "Good game!" },
  },

  S = {
    { ko = "인사", en = "Hi" }, { ko = "나이스 슛", en = "Nice shot" }, { ko = "아깝다", en = "Close" }, { ko = "나이스 패스", en = "Nice pass" },
    { ko = "감사", en = "Thanks" }, { ko = "미안", en = "Sorry" }, { ko = "한게임 더", en = "One more" }, { ko = "수고", en = "GG" },
  },

  GOAL = { cupsoc = { [0x12064] = true, [0x12078] = true }, cupsocs2 = { [0x12d58] = true, [0x12d6c] = true } },

  SLOW = { cupsoc = 0x109d53, cupsocs2 = 0x109ee3, cupsocs = 0x109ee3 },

  SEL = { cupsoc = 0x109b3d, cupsocs2 = 0x109c75, cupsocs = 0x109c75 },
  COL = { 0xffff4a4a, 0xff4070ff, 0xffffd23f, 0xff3ccd5f },
  IN = 8, OUT = 14, GOALWIN = 420, GAP = 180, PVEGAP = 300,
  keys = {}, prev = {}, show = { {}, {} }, last = { -99999, -99999, -99999, -99999 }, sent = false, winTill = -1, score = nil,
  over = false, open = false, ingoal = false, inslow = false, goalAt = -99999, closeAt = nil, wc = {},
}
QC.GOAL.cupsocs = QC.GOAL.cupsocs2
for i = 1, 8 do QC.keys[i] = input:code_from_token("KEYCODE_F" .. i) end
function QC.text(id) local t = QC.T[id]; return t and (t[cfg.lang] or t.en) or "" end
function QC.short(id) local t = QC.S[id]; return t and (t[cfg.lang] or t.en) or "" end

function QC.side(seat) if SCNP_PVE.on then return 1 end local gp = GAME_PLAYER[seat] or seat; return (gp == 1 or gp == 3) and 1 or 2 end
function qc_show(seat, id)
  if not seat or not id or seat < 1 or seat > 4 or not QC.T[id] then return end
  log("chat: %dP %s", seat, QC.T[id].en)
  if not QC.open then return end

  local gp = GAME_PLAYER[seat] or seat
  QC.show[QC.side(seat)][gp] = { id = id, at = frame }
end

function qc_from_peer(p, payload)
  if SCNP_NOCHAT then return end
  local seat, id = payload:byte(1, 2)
  if not seat or seat ~= p.slot or seat < 1 or seat > 4 or not QC.T[id] or not (QC.open or SCNP_PVE.on) then return end
  if frame - QC.last[seat] < (SCNP_PVE.on and QC.PVEGAP or QC.GAP) then return end
  QC.last[seat] = frame
  qc_show(seat, id)
  broadcast("M" .. string.char(gen, seat, id))
end
function qc_send(id)
  if SCNP_NOCHAT then return end
  QC.sent = true
  QC.mine = frame
  if is_host then
    if frame - QC.last[local_slot] < (SCNP_PVE.on and QC.PVEGAP or QC.GAP) then return end
    QC.last[local_slot] = frame
    qc_show(local_slot, id)
    broadcast("M" .. string.char(gen, local_slot, id))
  elseif host_peer then
    send_to(host_peer, "M" .. string.char(gen, local_slot, id))
  end
end

function qc_step()
  if phase ~= "play" then return end

  local sa = QC.SLOW[SCNP_GAME]
  local slow = sa and (mem:read_u8(sa) & 0x10) ~= 0 or false
  local g = QC.GOAL[SCNP_GAME]
  local goal = g and g[mem:read_u32(0x1138a0)] or false
  if ((slow and not QC.inslow) or (goal and not QC.ingoal)) and frame - QC.goalAt > 300 then
    QC.winTill = frame + QC.GOALWIN; QC.sent = false; QC.goalAt = frame
  end
  QC.inslow = slow; QC.ingoal = goal
  if SCNP_G.score_l and SCNP_G.score_r then
    local sc = mem:read_u8(SCNP_G.score_l) + mem:read_u8(SCNP_G.score_r)
    if QC.score and sc > QC.score and frame - QC.goalAt > 600 then QC.winTill = frame + QC.GOALWIN; QC.sent = false end
    QC.score = sc
  end

  local over = clock_start ~= nil and mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run"
  if over and not QC.over then QC.sent = false end
  QC.over = over
  local sl = QC.SEL[SCNP_GAME]
  local selecting = sl and clock_start == nil and (mem:read_u8(sl) == 2 or mem:read_u8(sl) == 3) or false
  if selecting and not QC.insel then QC.sent = false end
  QC.insel = selecting
  local open = not SCNP_NOCHAT and (over or frame <= QC.winTill or selecting)
  if open ~= QC.open then
    QC.closeAt = (not open) and frame or nil
    if open then QC.show = { {}, {} } end
    log("chat window %s at frame %d%s", open and "open" or "closed", frame, open and (over and " (full time)" or selecting and " (country select)" or " (goal)") or "")
  end
  QC.open = open
  if is_replay then return end
  for i = 1, 8 do
    local down = QC.keys[i] and input:code_pressed(QC.keys[i])

    local free = SCNP_PVE.on and frame - (QC.mine or -99999) >= QC.PVEGAP
    if down and not QC.prev[i] and ((open and not QC.sent) or free) and not is_spec and local_slot >= 1 and local_slot <= 4 then
      qc_send(i)
    end
    QC.prev[i] = down
  end
end

function QC.alpha(m)
  local a = math.min(1, (frame - m.at + 1) / QC.IN)
  if QC.closeAt then a = math.min(a, 1 - (frame - QC.closeAt) / QC.OUT) end
  return a
end
function QC.argb(col, a) return (math.floor(a * ((col >> 24) & 0xff) + 0.5) << 24) | (col & 0xffffff) end

function QC.width(s)
  local v = QC.wc[s]
  if v then return v end
  local ok, r = pcall(function()
    local ui = manager.ui
    return ui:get_string_width(s) / ui:get_string_width("가가가가가가가가가가") * 10
  end)
  if ok and r and r > 0 then v = r * 0.83 * HUD_TH
  else
    local n = 0
    pcall(function() for _, cp in utf8.codes(s) do n = n + ((cp >= 0x1100) and 0.83 or (cp == 32 and 0.26 or 0.42)) end end)
    v = n * HUD_TH
  end
  QC.wc[s] = v
  return v
end

SCNP_VOL = { bgm = tonumber(env("SCNP_VOLBGM", "")), sfx = tonumber(env("SCNP_VOLSFX", "")), file = env("SCNP_VOLFILE", ""), poll = -9999, taps = {} }
;(function()
  local V = SCNP_VOL
  if not V.bgm and not V.sfx and V.file == "" then return end
  V.bgm = math.max(0, math.min(100, V.bgm or 100)); V.sfx = math.max(0, math.min(100, V.sfx or 100))
  local OKIDB = { 0, -3.2, -6.0, -9.2, -12.0, -14.5, -18.0, -20.5, -24.0 }
  local function db(n) return n <= 0 and -1000 or 40 * math.log(n / 100, 10) end
  function V.set(bgm, sfx)
    V.bgm, V.sfx = bgm, sfx
    local d = db(sfx)
    V.oki = {}
    for a = 0, 15 do
      if a > 8 or d <= -900 then V.oki[a] = 15
      else
        local want, best, bi = OKIDB[a + 1] + d, 1e9, 15
        for i = 0, 8 do local e = math.abs(OKIDB[i + 1] - want); if e < best then best, bi = e, i end end
        if want < OKIDB[9] - 3 then bi = 15 end
        V.oki[a] = bi
      end
    end
    V.ym = bgm <= 0 and 63 or math.min(63, math.floor(-db(bgm) / 0.75 + 0.5))
  end
  V.set(V.bgm, V.sfx)
  local dev = manager.machine.devices[":audiocpu"]
  if not dev then return end
  local sp = dev.spaces["program"]
  local okiPending, ymAddr, conn = false, 0, {}
  V.taps.oki = sp:install_write_tap(0x6000, 0x6000, "scnp_vol_oki", function(offset, data, mask)
    if not okiPending then okiPending = (data & 0x80) ~= 0; return nil end
    okiPending = false
    if V.sfx >= 100 then return nil end
    return (data & 0xf0) | V.oki[data & 0x0f]
  end)
  V.taps.ym = sp:install_write_tap(0x4008, 0x4009, "scnp_vol_ym", function(offset, data, mask)
    if offset == 0x4008 then ymAddr = data; return nil end
    local a = ymAddr
    if a >= 0xc0 and a <= 0xc8 then conn[a - 0xc0] = data & 1; return nil end
    if a < 0x40 or a > 0x55 or V.ym == 0 then return nil end
    local o = a - 0x40
    local k = o & 7
    if k > 5 then return nil end
    local ch = (o >> 3) * 3 + k % 3
    if k < 3 and conn[ch] ~= 1 then return nil end
    return (data & 0xc0) | math.min(63, (data & 0x3f) + V.ym)
  end)
  V.sub = emu.register_frame_done(function()
    if V.file == "" then return end
    local f = manager.machine.screens[":screen"] and manager.machine.screens[":screen"]:frame_number() or 0
    if f - V.poll < 20 and f >= V.poll then return end
    V.poll = f
    local h = io.open(V.file, "rb")
    if not h then return end
    local l = h:read("l"); h:close()
    local b, s = (l or ""):match("^(%d+)%s+(%d+)")
    b, s = tonumber(b), tonumber(s)
    if b and s and (b ~= V.bgm or s ~= V.sfx) then
      V.set(math.max(0, math.min(100, b)), math.max(0, math.min(100, s)))
      log("volume: music %d%%, effects %d%%", V.bgm, V.sfx)
    end
  end)
  log("volume: music %d%%, effects %d%% (live%s)", V.bgm, V.sfx, V.file ~= "" and "" or ", no file")
end)()

SCNP_SC = { path = env("SCNP_SPECCHAT", ""), seq = nil, line = nil, at = -9999, poll = -9999 }
function scnp_specchat_draw()
  local S = SCNP_SC
  if S.path == "" or not screen or is_replay then return end
  if frame - S.poll >= 20 or frame < S.poll then
    S.poll = frame
    local f = io.open(S.path, "rb")
    if f then
      local l = f:read("l"); f:close()
      local sq, nk, tx = (l or ""):match("^(%d+)\t([^\t]*)\t(.*)$")
      if sq and sq ~= S.seq then
        S.seq = sq; S.at = frame
        S.line = (cfg.lang == "ko" and "[관전] " or "[watching] ") .. nk .. ": " .. tx
        log("spectator chat on screen: %s", S.line)
      end
    end
  end
  if not S.line then return end
  local age = frame - S.at
  if age < 0 or age > 360 then return end
  local a = age > 330 and math.floor(255 * (360 - age) / 30) or 255
  local w, h = screen.width or 320, screen.height or 240
  local t = S.line
  while QC.width(t) > w * 0.9 and utf8.len(t) and utf8.len(t) > 4 do t = t:sub(1, utf8.offset(t, -1) - 1) end
  local tw, lh = QC.width(t), HUD_TH + 2

  local y = QC.top and ((SCNP_PVE.on and (QC.top - 7 * h / 240) or math.min(QC.top, h * 664 / 720)) - lh - 2) or (h - lh - 1)
  box((w - tw) / 2 - 6, y - 1, (w + tw) / 2 + 6, y + lh, math.floor(a * 0.63) << 24)
  screen:draw_text((w - tw) / 2, y, t, (a << 24) | 0x9fe8ff, 0)
end
function qc_draw()
  if not screen then return end
  local w, h = screen.width or 320, screen.height or 240

  local win = QC.open and not QC.sent
  local pve = SCNP_PVE.on and phase == "play"
  QC.top = nil
  if (win or pve) and not is_spec and not is_replay and local_slot >= 1 and local_slot <= 4 then
    local dim = (not win) and frame - (QC.mine or -99999) < QC.PVEGAP
    local ka = dim and 0.4 or 1
    local kg, ig = QC.width(" "), QC.width("   ")
    if not win then kg, ig = QC.width(" ") * 0.4, QC.width(" ") * 1.6 end
    local function lw(a, b, f) local x = 0; for i = a, b do x = x + QC.width("[F" .. i .. "]") + kg + QC.width(f(i)) + (i < b and ig or 0) end; return x end
    local f, rows = QC.text, { { 1, 8 } }
    if not win and lw(1, 8, QC.short) <= w - 8 then f = QC.short
    elseif lw(1, 8, QC.text) > w - 8 then
      f = QC.short
      if lw(1, 8, QC.short) > w - 8 then f, rows = QC.text, { { 1, 4 }, { 5, 8 } } end
    end
    local lh = HUD_TH + 2
    local top = h - #rows * lh - 2
    QC.top = top - 2
    box(0, top - 2, w, h, dim and 0x90000000 or 0xc8000000)
    for r, rg in ipairs(rows) do
      local x = (w - lw(rg[1], rg[2], f)) / 2
      for i = rg[1], rg[2] do
        local k, t = "[F" .. i .. "]", f(i)
        screen:draw_text(x, top + (r - 1) * lh, k, QC.argb(0xffffd23f, ka), 0); x = x + QC.width(k) + kg
        screen:draw_text(x, top + (r - 1) * lh, t, QC.argb(0xfff4f4f4, ka), 0); x = x + QC.width(t) + ig
      end
    end
  end
  local rh, gap, y0 = h * 30 / 720, h * 6 / 720, h * 134 / 720
  local bar, pad, tgap = w * 5 / 960, w * 8 / 960, w * 7 / 960
  for side = 1, 2 do
    local y = y0
    for seat = 1, 4 do
      local m = QC.show[side][seat]
      if m then
        local a = QC.alpha(m)
        if a <= 0 then QC.show[side][seat] = nil
        else
          local tag, txt = seat .. "P", QC.text(m.id)
          local tw, gw = QC.width(txt), QC.width(tag)
          local bw = bar + pad + gw + tgap + tw + pad
          local x0 = (side == 1) and (w * 24 / 960) or (w * 936 / 960 - bw)
          local ty = y + (rh - HUD_TH) / 2
          box(x0, y, x0 + bw, y + rh, QC.argb(0xbe0a0e0c, a))
          box(x0, y, x0 + bar, y + rh, QC.argb(QC.COL[seat], a))
          screen:draw_text(x0 + bar + pad, ty, tag, QC.argb(QC.COL[seat], a), 0)
          screen:draw_text(x0 + bar + pad + gw + tgap, ty, txt, QC.argb(0xffffffff, a), 0)
          y = y + rh + gap
        end
      end
    end
  end
end

local function handle_host_message(p, t, g, payload)
  if t == "H" then
    local ver, _, want, hfl = payload:byte(1, 4)
    if p.slot >= 5 and hfl and (hfl & 1) ~= 0 then p.shadow = true end
    if ver ~= VERSION then status("player %d has protocol version %d (need %d)", p.slot, ver, VERSION); return end
    local ml, mh = payload:byte(6, 7)
    local pm = (ml or 0) + (mh or 0) * 256
    if pm > 0 and MAME_MINOR > 0 and pm ~= MAME_MINOR then

      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, scnp_pk_byte(), scnp_sel_code(), (SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0) | (SCNP_GOD.auto and 8 or 0) | (SCNP_PVEGOD.on and 4 or 0), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_DIPTIME and 1 or 0))
      if p.slot >= 5 then log("spectator %d has MAME %s (we run %s) - ignored", p.slot, mame_str(pm), mame_str(MAME_MINOR)); return end
      lose("MAME version differs: player %d has %s, you have %s - everybody needs the same MAME build", p.slot, mame_str(pm), mame_str(MAME_MINOR))
      return
    end
    if p.slot >= 5 then

      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, scnp_pk_byte(), scnp_sel_code(), (SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0) | (SCNP_GOD.auto and 8 or 0) | (SCNP_PVEGOD.on and 4 or 0), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_DIPTIME and 1 or 0))
      if not p.ready then log("spectator %d joined", p.slot) end
      p.ready = true

      if phase == "play" and not p.join_at and p.handed ~= gen then
        if is_relay then

          p.handed = gen; p.resync_base = frame
          log("spectator %d joins mid-match - the relay feeds it the match", p.slot)
        else
          p.join_at = frame + cfg.delay + 3
          log("spectator %d joins mid-match, state at frame %d", p.slot, p.join_at)
        end
      end
      return
    end
    if SCNP_PVE.on and phase == "play" and p.slot >= 2 and p.slot <= 4 and not p.ready then

      local P = SCNP_PVE
      P.dropped[p.slot] = nil; P.gone[p.slot] = nil; P.mark[p.slot] = nil; P.tries[p.slot] = nil
      P.late[p.slot] = nil; P.live[p.slot] = nil; allow[p.slot] = 0; inputs[p.slot] = {}; peer_sums[p.slot] = {}
      if p.slot > nplayers then nplayers = p.slot end
      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, scnp_pk_byte(), scnp_sel_code(), (SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0) | (SCNP_GOD.auto and 8 or 0) | (SCNP_PVEGOD.on and 4 or 0), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_DIPTIME and 1 or 0))
      p.ready = true

      P.sync_join = true; P.joining = P.joining or {}; P.joining[p.slot] = true
      log("PvE: %dP joins the running match (resync)", p.slot); status("PvE: %dP is joining the match", p.slot)
      return
    end
    if p.ready then send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, scnp_pk_byte(), scnp_sel_code(), (SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0) | (SCNP_GOD.auto and 8 or 0) | (SCNP_PVEGOD.on and 4 or 0), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_DIPTIME and 1 or 0)); return end

    if want and want >= 2 and want <= nplayers and want ~= p.slot and not peers[want] then
      peers[p.slot] = nil; peers[want] = p; p.slot = want
    end
    send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, scnp_pk_byte(), scnp_sel_code(), (SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0) | (SCNP_GOD.auto and 8 or 0) | (SCNP_PVEGOD.on and 4 or 0), SCNP_PVE.on and SCNP_DIFF.v or 3, SCNP_DIPTIME and 1 or 0))
    p.ready = true
    log("player %d joined (%d/%d)", p.slot, p.slot, nplayers)
    status("player %d joined (%d of %d)", p.slot, p.slot, nplayers)
    set_overlay(C_INFO, "NETPLAY: %d of %d players here, waiting for the rest...", p.slot, nplayers)
  elseif t == "X" then
    if g >= 5 then

      if peers[g] == p then peers[g] = nil end
      log("spectator %d left", g)
      return
    end
    if SCNP_PVE.on and g >= 2 and g <= 4 then
      if peers[g] == p then peers[g] = nil end
      scnp_pve_left(g)
      return
    end
    lose("%dP left - game over", g)
  elseif t == "P" then
    send_to(p, "Q" .. string.char(g) .. payload)
  elseif t == "Q" then
    local sent = string.unpack("<I4", payload)
    rtt[p.slot] = (now_ms() - sent) & 0xffffffff
  elseif t == "M" then
    qc_from_peer(p, payload)
  elseif g ~= gen then
    return
  elseif t == "R" then
    p.loaded = true
    log("player %d has the state (gen %d)", p.slot, g)
  elseif t == "D" then
    if p.slot >= 1 and p.slot <= 4 then hud_dev[p.slot] = payload:byte(1) or 0 end
  elseif p.slot >= 5 then
    if t == "C" then

      local f, sum = string.unpack("<I4I4", payload)
      local mine = sum_hist[f]
      if f <= (p.resync_base or -1) then mine = nil end
      if mine and mine ~= sum then

        p.resyncs = p.resyncs or 0
        if phase == "play" and not p.join_at and p.handed == gen and p.resyncs < 1 and frame - (p.resync_at or -100000) >= 600 then
          p.resyncs = p.resyncs + 1; p.resync_at = frame; p.force = true; p.agree_logged = nil

          if is_relay then send_to(p, "K" .. string.char(gen)); p.force = nil; p.resync_base = frame else p.join_at = frame + cfg.delay + 3 end
          log("spectator %d drifted from us at frame %d (host %08x, spectator %08x) - sending it the game again (%d)", p.slot, f, mine, sum, p.resyncs)
        elseif not p.drift_logged then p.drift_logged = true; log("spectator %d drifted from us at frame %d (host %08x, spectator %08x)", p.slot, f, mine, sum) end
      end
      if mine and mine == sum and not p.agree_logged then p.agree_logged = true; log("spectator %d in step with us (checksum agrees at frame %d)", p.slot, f) end
    end
    return
  elseif t == "I" then
    local f, m = string.unpack("<I4B", payload)
    if SCNP_PVE.late[p.slot] and not SCNP_PVE.live[p.slot] then

      if f + 8 < last_broadcast then return end
      SCNP_PVE.live[p.slot] = last_broadcast + 1
      log("PvE: %dP is in step from frame %d", p.slot, last_broadcast + 1)
      if f <= last_broadcast then return end
    end
    if f <= last_broadcast then return end
    inputs[p.slot][f] = m
    if f > (SCNP_DD.hi[p.slot] or 0) then SCNP_DD.hi[p.slot] = f end
  elseif t == "W" then
    SCNP_DD.pw[p.slot] = string.unpack("<I2", payload)
  elseif t == "C" then
    local f, s = string.unpack("<I4I4", payload)
    peer_sums[p.slot][f] = s
  end
end

local function handle_client_message(t, g, payload)
  if t == "F" then

    local st, pk, sel, god, df, dt = payload:byte(1, 6)
    if dt and (dt == 1) ~= SCNP_DIPTIME then SCNP_DIPTIME = (dt == 1); install_clock_gate() end
    if st and st <= 17 and st ~= scnp_stage then scnp_stage = st; scnp_install_stage_tap() end
    if pk then SCNP_PK.on = (pk == 1); SCNP_PK.gg = (pk == 2); SCNP_PK.race = (pk > 10 and pk < 20) and (pk - 10) or 0 end
    if sel then scnp_sel_apply(sel >= 1, sel >= 2, sel >= 3, sel >= 4) end
    if god then scnp_god_apply((god & 3) >= 1, (god & 3) >= 2, (god & 8) ~= 0); scnp_pvegod_apply((god & 4) ~= 0) end
    if df and df <= 3 and SCNP_PVE.on and df ~= SCNP_DIFF.v then scnp_diff_apply(df) end
    return
  end
  if t == "H" then
    if phase ~= "handshake" then return end
    local ver, delay, slot, players, tl = payload:byte(1, 5)
    if ver ~= VERSION then lose("protocol version mismatch (%d vs %d) - update netplay.lua on both sides", ver, VERSION); return end
    local ml, mh = payload:byte(6, 7)
    local hm = (ml or 0) + (mh or 0) * 256
    if hm > 0 and MAME_MINOR > 0 and hm ~= MAME_MINOR then lose("MAME version differs (host %s, you %s) - everybody needs the same MAME build", mame_str(hm), mame_str(MAME_MINOR)); return end
    cfg.delay = delay; local_slot = slot; nplayers = players; gen = g
    if tl and tl > 0 then cfg.time = tl * 10; install_clock_gate() end
    set_state_name(slot)
    if is_spec then
      log("handshake ok: spectator %d, %d players, delay %d, waiting for state", slot, players, delay)
      status("spectating (%d players), waiting for the host to start...", players)
      set_overlay(C_INFO, "NETPLAY: spectator mode - waiting for the host to start...")
    else
      bind_local_keys()
      log("handshake ok: slot %d of %d, delay %d, waiting for state", slot, players, delay)
      status("connected as player %d of %d, waiting for the host to start...", slot, players)
      set_overlay(C_INFO, "NETPLAY: you are player %d of %d, waiting for the host to start...", slot, players)
    end
    phase = "sync"; phase_since = os.time()
  elseif t == "J" then
    if is_spec and phase == "play" and ((payload:byte(5) or 0) & 0x80) == 0 then SCNP_SPEC_SKIP = true; log("a second hand-off while watching - ignored"); return end
    if is_spec and phase == "play" then log("we drifted from the match - the host sends it again"); status("back in step with the match") end
    spec_base = string.unpack("<I4", payload)
    local r = payload:byte(5); if r then r = r & 0x7f end
    bgm_rand = (r and r ~= 0) and r or nil
    if not is_spec then SCNP_PVE.catchup = true end
    set_overlay(C_INFO, "NETPLAY: spectator mode - joining the match in progress...")
    log("joining mid-match: state will be from frame %d", spec_base)
  elseif t == "S" then
    if SCNP_SPEC_SKIP and is_spec and phase == "play" then SCNP_SPEC_SKIP = nil; return end
    gen = g
    if not spec_base then agg = {} end
    pending_state = payload

    if is_spec and phase == "play" and spec_base then
      SCNP_QUIET = true
      log("received state (%d bytes, gen %d) - back in step quietly", #payload, g)
      return
    end
    write_fail = 0
    phase = "sync"; phase_since = os.time()
    set_overlay(C_INFO, "NETPLAY: game state received, saving it...")
    log("received state (%d bytes, gen %d)", #payload, g)
  elseif t == "X" then
    if SCNP_PVE.on and g >= 2 and g <= 4 then log("PvE: %dP left, the match goes on", g); return end
    lose("%dP left - game over", g)
  elseif t == "P" then
    send_to(host_peer, "Q" .. string.char(g) .. payload)
  elseif t == "Q" then
    local sent = string.unpack("<I4", payload)
    rtt[1] = (now_ms() - sent) & 0xffffffff
  elseif t == "M" then
    qc_show(payload:byte(1, 2))
  elseif g ~= gen then
    return
  elseif t == "G" then
    if phase == "ready" then start_load() else log("ignoring G in phase %s", phase) end
  elseif t == "L" then
    local d = payload:byte(1)
    if d and d >= 1 and d <= 12 and d ~= cfg.delay then
      log("input delay %d -> %d frames at frame %d (the host)", cfg.delay, d, frame)
      SCNP_DD.hist = SCNP_DD.hist or {}
      if #SCNP_DD.hist < 60 then SCNP_DD.hist[#SCNP_DD.hist + 1] = string.format("%d>%d@%d", cfg.delay, d, frame) end
      cfg.delay = d
    end
  elseif t == "A" then
    if phase == "sync" then spec_saw_play = true end
    local f, m1, m2, m3, m4 = string.unpack("<I4BBBB", payload)
    agg[f] = { m1, m2, m3, m4 }
    if f > agg_max then agg_max = f end
  elseif t == "T" then
    for i = 1, 4 do
      local q = payload:byte(i)
      hud_ping[i] = (q and q < 255) and q * 4 or nil
      hud_dev[i] = payload:byte(4 + i) or 0
    end
  elseif t == "O" then
    local a, b, f, since = string.unpack("<I4<I4<I4<I4", payload)
    SCNP_POSS.sync = { a = a, b = b, f = f, since = since }

    log("possession from the host: %d / %d frames at frame %d", a, b, f)
  elseif t == "V" then
    local nspec = payload:byte(1) or 0
    if nspec ~= SCNP_SPEC.n then log("watching now: %d", nspec) end
    SCNP_SPEC.n = nspec
  end
end

local function pump()
  if is_host then
    if is_relay and relay_sock then relay_poll() end
    for _, p in pairs(peers) do
      poll(p)
      while true do
        local t, g, payload = next_message(p)
        if not t then break end
        handle_host_message(p, t, g, payload)
      end
    end
  elseif host_peer then
    poll(host_peer)
    while true do
      local t, g, payload = next_message(host_peer)
      if not t then break end
      handle_client_message(t, g, payload)
    end
  end
end

local function check_sums()
  for f, s in pairs(local_sums) do
    local complete = true
    for slot = 2, nplayers do
      local r = peer_sums[slot][f]
      if SCNP_PVE.dropped[slot] or (SCNP_PVE.late[slot] and not SCNP_PVE.live[slot]) then r = s end
      if r == nil then complete = false
      elseif r ~= s then
        stats.desync = stats.desync + 1
        status("desync with player %d at frame %d, resynchronising...", slot, f)
        log("DESYNC slot %d frame %d (host %08x peer %08x)", slot, f, s, r)
        resync_pending = true
      end
    end
    if complete then
      local_sums[f] = nil
      for slot = 2, nplayers do peer_sums[slot][f] = nil end
    end
  end
  for f in pairs(local_sums) do if f < frame - 600 then local_sums[f] = nil end end
end

local function open_listener()
  listener = { sock = emu.file("rwc"), rx = "", slot = nil }
  local err = listener.sock:open("socket." .. cfg.addr .. ":" .. cfg.port)
  if err then lose("cannot listen on %s:%d (%s)", cfg.addr, cfg.port, tostring(err)); listener = nil; return false end
  return true
end

local players_ready_since = nil
local function host_lobby()
  local joined = 0
  for s = 2, nplayers do if (peers[s] and peers[s].ready) or SCNP_PVE.dropped[s] then joined = joined + 1 end end
  if joined == nplayers - 1 then

    local specs = 0
    for s = 5, 12 do if peers[s] and peers[s].ready then specs = specs + 1 end end
    players_ready_since = players_ready_since or os.time()
    if specs >= (cfg.spectators or 0) or os.time() - players_ready_since >= 3 then
      begin_sync("all players present")
      return
    end
    pump()
    return
  end
  if is_relay then pump(); return end
  if listener then
    poll(listener)
    if #listener.rx > 0 then
      local slot = 2
      while peers[slot] do slot = slot + 1 end
      listener.slot = slot
      peers[slot] = listener
      listener = nil
      log("connection accepted (provisional slot %d)", slot)
      if slot < nplayers then open_listener() end
    end
  end
  pump()
end

local function client_connect()
  connect_tries = connect_tries + 1
  local p = { sock = emu.file("rw"), rx = "", slot = 1 }
  local err = p.sock:open("socket." .. cfg.addr .. ":" .. cfg.port)
  if err then
    if connect_tries == 1 or connect_tries % 10 == 0 then
      status("connecting to %s:%d ... (attempt %d)", cfg.addr, cfg.port, connect_tries)
    end
    set_overlay(C_WARN, "NETPLAY: connecting to %s:%d ... (attempt %d of 40)", cfg.addr, cfg.port, connect_tries)
    if connect_tries >= 40 then lose("could not connect to %s:%d", cfg.addr, cfg.port) end
    return
  end
  if is_relay then
    p.sock:write("GAME " .. cfg.token .. " " .. local_slot .. "\n")
    if is_host then
      relay_sock = p.sock
      phase = "lobby"
      log("relay host connected to %s:%d (room token %s), waiting for %d player(s)", cfg.addr, cfg.port, cfg.token, nplayers - 1)
      status("connected to the relay, waiting for %d more player(s)...", nplayers - 1)
      set_overlay(C_INFO, "NETPLAY: connected to the relay, waiting for %d more player(s)...", nplayers - 1)
      if nplayers == 1 and (cfg.spectators or 0) == 0 then begin_sync("solo") end
      return
    end
  end
  host_peer = p
  send_to(p, "H" .. string.char(0, VERSION, 0, cfg.slot, SCNP_SHADOW and 1 or 0, 0) .. mame_bytes())
  phase = "handshake"
  hs_wait = now_ms()
  set_overlay(C_INFO, "NETPLAY: connected, waiting for the host's reply...")
  log("connected to %s:%d, handshake sent", cfg.addr, cfg.port)
end

local SPEC_STATE = "np_specjoin"
local SPEC_SAVE_LAG = tonumber(os.getenv("SCNP_SPEC_LAG") or "1")
SCNP_SPEC_POKE = tonumber(os.getenv("SCNP_SPEC_POKE") or "")
local spec_join = nil

pcall(function()
  SCNP_PRESAVE = emu.add_machine_pre_save_notifier(function()
    if spec_join and not spec_join.real then spec_join.real = frame end
    if SCNP_CKPT and SCNP_CKPT.pend and not SCNP_CKPT.pend.real then SCNP_CKPT.pend.real = frame end
    if SCNP_SHADOWQ and SCNP_SHADOWQ.pend and not SCNP_SHADOWQ.pend.real then SCNP_SHADOWQ.pend.real = frame end
  end)
end)

SCNP_CATCH = { on = false, att = nil, pct = 0 }
function scnp_catchup_step(behind)
  local C = SCNP_CATCH
  if not C.on and behind > 300 then
    C.on = true
    pcall(function() C.att = manager.machine.sound.attenuation; manager.machine.sound.attenuation = -32 end)

    pcall(function() C.fs = manager.machine.video.frameskip; manager.machine.video.frameskip = 10 end)
    log("catching up with the match: %d frame(s) behind", behind)
  elseif C.on and behind < 15 then
    C.on = false
    pcall(function() manager.machine.sound.attenuation = C.att or 0 end)
    pcall(function() manager.machine.video.frameskip = C.fs or 0 end)
    log("caught up with the match at frame %d", frame)
  end
  C.pct = agg_max > 0 and math.min(99, math.floor(frame * 100 / agg_max)) or 0
end
function scnp_catchup_draw()
  local C = SCNP_CATCH
  if not C.on or not screen then return end
  local t = cfg.lang == "ko" and string.format("관전 화면을 따라잡는 중... %d%%", C.pct) or string.format("Catching up with the match... %d%%", C.pct)
  screen:draw_text("center", 100, t, 0xffffe060, 0xc0000000)
end
function scnp_dead_ball()
  local v = mem:read_u32(0x1138a0) & 0xffffff
  return v == 0 or (v >= 0x12800 and v <= 0x12fff and v ~= 0x12a08)
end

SCNP_CKPT = { last = 0, pend = nil, dead = nil, since = 0, MIN = 600, AT = tonumber(os.getenv("SCNP_CKPT_AT") or "") }
function scnp_ckpt_step()
  local C = SCNP_CKPT
  if not is_relay or not is_host or is_replay or phase ~= "play" then return end
  if C.pend then
    local data = read_state_file(C.pend.name)
    if data then
      local at = C.pend.real or C.pend.at
      relay_write(1, "Z" .. string.char(gen) .. u32le(at) .. string.char(bgm_rand or 0) .. u32le(#data) .. data)
      log("checkpoint for the relay: frame %d (%d bytes, %s)", at, #data, C.pend.why)
      C.last = at; C.pend = nil
    elseif os.time() - C.pend.t > 5 then
      log("checkpoint: could not read the state back - skipped"); C.pend = nil
    end
    return
  end
  if spec_join or frame - C.last < C.MIN then return end
  local v = mem:read_u32(0x1138a0) & 0xffffff
  local why = (v == 0) and "half time" or ((v == 0x12d58 or v == 0x12d6c) and "a goal") or nil
  if C.AT and frame >= C.AT then why = "test"; C.dead = why; C.since = frame - 20; C.AT = nil end
  if not why then C.dead = nil; return end
  if C.dead ~= why then C.dead = why; C.since = frame end
  if frame - C.since < 20 then return end
  SCNP_SPEC_N = (SCNP_SPEC_N or 0) + 1
  local name = SPEC_STATE .. "_ck" .. SCNP_SPEC_N .. "_" .. (os.time() % 100000)
  machine:save(name)
  C.pend = { name = name, at = frame + SPEC_SAVE_LAG, t = os.time(), why = why }
end

SCNP_SHADOW = os.getenv("SCNP_SHADOW")
if SCNP_SHADOW == "" then SCNP_SHADOW = nil end
SCNP_SHADOWQ = { pend = nil, last = 0, EVERY = 300, n = 0 }
function scnp_shadow_step()
  local Q = SCNP_SHADOWQ
  if not SCNP_SHADOW or not is_spec or phase ~= "play" then return end
  if Q.pend then
    local data, fpath = read_state_file(Q.pend.name)
    if data then
      local at = Q.pend.real or Q.pend.at
      local base = SCNP_SHADOW .. "/ck_" .. gen .. "_" .. at .. "_" .. (bgm_rand or 0)
      local h = io.open(base .. ".tmp", "wb")
      if h then h:write(data); h:close(); os.rename(base .. ".tmp", base .. ".sta") end
      pcall(os.remove, fpath)
      Q.last = at; Q.pend = nil
    elseif os.time() - Q.pend.t > 5 then Q.pend = nil end
    return
  end
  if SCNP_QUIET or agg_max - frame > 15 or frame - Q.last < Q.EVERY then return end
  Q.n = Q.n + 1
  local name = "np_shadow_" .. Q.n
  machine:save(name)
  Q.pend = { name = name, at = frame + SPEC_SAVE_LAG, t = os.time() }
end
local function spec_join_step()
  if spec_join then
    local data, info = read_state_file(spec_join.name)
    if data then
      local p = spec_join.p
      if spec_join.real and spec_join.real ~= spec_join.at then
        log("spectator %d: the save landed at frame %d, not %d", p.slot, spec_join.real, spec_join.at)
        spec_join.at = spec_join.real
      end

      send_to(p, "J" .. string.char(gen) .. u32le(spec_join.at) .. string.char((bgm_rand or 0) | (p.force and 0x80 or 0)))
      p.force = nil; p.resync_base = spec_join.at
      send_to(p, "S" .. string.char(gen) .. u32le(#data) .. data)

      send_to(p, "O" .. string.char(gen) .. u32le(SCNP_POSS.a) .. u32le(SCNP_POSS.b) .. u32le(frame) .. u32le(math.min(100000, math.max(0, frame - hud_tick_frame))))
      log("spectator %d: sent state of frame %d (%d bytes), possession %d / %d", p.slot, spec_join.at, #data, SCNP_POSS.a, SCNP_POSS.b)
      p.join_at = nil; p.handed = gen
      spec_join = nil
    elseif os.time() - spec_join.t > 5 then
      log("spectator %d: could not read the hand-off state (%s), giving up", spec_join.p.slot, tostring(info))
      spec_join.p.join_at = nil
      spec_join = nil
    end
    return
  end
  for slot = 2, 12 do
    local p = peers[slot]

    if p and p.join_at and frame >= p.join_at and (slot >= 5 or SCNP_PVE.late[slot])
       and (slot < 5 or scnp_dead_ball() or frame >= p.join_at + 600) then

      SCNP_SPEC_N = (SCNP_SPEC_N or 0) + 1
      local name = SPEC_STATE .. "_" .. SCNP_SPEC_N .. "_" .. (os.time() % 100000)
      machine:save(name)
      spec_join = { p = p, at = frame + SPEC_SAVE_LAG, t = os.time(), name = name }
      return
    end
  end
end

local function step()
  if phase == "lost" or phase == "ended" then return end
  if SCNP_QUIET and pending_state and phase == "play" then
    local path, err = write_state_file(pending_state)
    if path then
      log("state written -> %s (%d bytes), loading it now (back in step)", path, #pending_state)
      pending_state = nil
      start_load()
      return
    end
    log("cannot write the state file: %s - the usual way", tostring(err))
    SCNP_QUIET = nil; phase = "sync"; phase_since = os.time()
  end
  if is_replay and rp_phase ~= "play" then
    if rp_phase == "boot" then
      if frame < 90 then frame = frame + 1; return end
      local path = pct_decode_path(cfg.replay or "")
      local r, err = replay_read(path)
      if not r then lose("replay: %s", tostring(err)); return end
      rp = r; rp_meta = r.meta
      if r.meta:match('"swap":1') then scnp_swap = true; GAME_PLAYER = { 2, 1, 3, 4 } end
      if r.meta:match('"type":"2v2"') then is_teams = true end
      local map = r.meta:match('"map":"(%d%d%d%d)"')
      if map then

        GAME_PLAYER = { tonumber(map:sub(1, 1)), tonumber(map:sub(2, 2)), tonumber(map:sub(3, 3)), tonumber(map:sub(4, 4)) }
      elseif is_teams then

        scnp_swap = false; GAME_PLAYER = { 1, 3, 2, 4 }
      end
      if r.meta:match('"type":"pve"') and SCNP_G.pm then SCNP_PVE.on = true end
      local rdf = tonumber(r.meta:match('"diff":(%d)'))
      if rdf and SCNP_PVE.on and rdf ~= 3 then scnp_diff_apply(rdf) end
      if r.meta:match('"pvegod":1') then scnp_pvegod_apply(true) end
      do local cw = r.meta:match('"costume":"([^"]*)"'); if cw and cw ~= "" then scnp_costume_parse(cw) end end
      SCNP_FREE = r.meta:match('"free":1') ~= nil
      SCNP_DIPTIME = r.meta:match('"dip":1') ~= nil
      SCNP_PACE = r.meta:match('"pace":2') ~= nil
      clock_run = not r.meta:match('"clock":"stop"')
      nplayers = tonumber(r.meta:match('"players":(%d+)')) or 2
      cfg.delay = tonumber(r.meta:match('"delay":(%d+)')) or cfg.delay

      SCNP_RPD = { at = {}, d = {} }
      for od, nd, at in (r.meta:match('"dd":"([^"]*)"') or ""):gmatch("(%d+)>(%d+)@(%d+)") do
        if not SCNP_RPD.d0 then SCNP_RPD.d0 = tonumber(od) end
        SCNP_RPD.at[#SCNP_RPD.at + 1] = tonumber(at); SCNP_RPD.d[#SCNP_RPD.d + 1] = tonumber(nd)
      end
      SCNP_RPD.d0 = SCNP_RPD.d0 or cfg.delay
      cfg.time = r.meta:match('"time":(%d+)') or cfg.time
      scnp_stage = tonumber(r.meta:match('"stage":(%d+)') or "0") or 0; scnp_install_stage_tap()
      SCNP_PK.on = r.meta:match('"pk":1[,}]') ~= nil
      SCNP_PK.gg = r.meta:match('"pk":2[,}]') ~= nil
      do local pv = tonumber(r.meta:match('"pk":(%d+)') or ""); SCNP_PK.race = (pv and pv > 10 and pv < 20) and (pv - 10) or 0 end
      local sv = tonumber(r.meta:match('"sel":(%d)') or "0") or 0; scnp_sel_apply(sv >= 1, sv >= 2, sv >= 3, sv >= 4)
      do local b = r.meta:match('"ball":"(%a+)"'); if b then SCNP_PAL.BALLNAME = b; SCNP_PAL.BALL = SCNP_PAL.BALLS[b] end end
      scnp_god_apply(r.meta:match('"god":[123]') ~= nil, r.meta:match('"god":[23]') ~= nil, r.meta:match('"god":3') ~= nil)
      SCNP_DEVR.play = {}; SCNP_DEVR.pi = 1
      for at, d in (r.meta:match('"devs":"([^"]*)"') or ""):gmatch("(%d+):(%d%d%d%d)") do SCNP_DEVR.play[#SCNP_DEVR.play + 1] = { at = tonumber(at), d = d } end
      install_clock_gate()
      log("replay: %s - %d frames, %d segment(s)", path, #r.inputs, #r.segments)
      rp_pos = 0; rp_seg = 2
      write_state_file(r.segments[1].state)
      rp_phase = "loading"; phase = "loading"; reloading = true; load_started = os.time()
      set_overlay(C_INFO, "REPLAY: loading...")
      machine:load(STATE_NAME)
      return
    end
    if rp_phase == "loading" then
      if load_started and os.time() - load_started > 8 then lose("replay: the state did not load (different MAME build?)") end
      return
    end
  end

  if phase == "connect" and is_replay then phase = "play"; rp_phase = "boot"; return end
  if phase == "connect" then
    if is_host and not is_relay then
      phase = "lobby"
      if nplayers == 1 then begin_sync("solo") return end
      if not open_listener() then return end
      status("hosting on port %d, waiting for %d more player(s)...", cfg.port, nplayers - 1)
      set_overlay(C_INFO, "NETPLAY: hosting on port %d, waiting for %d more player(s)...", cfg.port, nplayers - 1)
      return
    else
      frame = frame + 1
      if frame % 30 == 1 then client_connect() end
      return
    end
  end

  if phase == "lobby" then host_lobby(); return end

  if phase == "handshake" then
    pump()
    if phase == "handshake" and ((now_ms() - hs_wait) & 0xffffffff) > 3000 then
      if is_relay then

        log("no handshake reply in 3 s, sending it again")
        send_to(host_peer, "H" .. string.char(0, VERSION, 0, cfg.slot, 0, 0) .. mame_bytes())
        hs_wait = now_ms()
      else

        log("no handshake reply in 3 s, reconnecting")
        pcall(function() host_peer.sock:close() end)
        host_peer = nil
        phase = "connect"
        frame = 0
      end
    end
    return
  end

  if phase == "sync" then
    pump()
    if phase ~= "sync" then return end
    if pending_state and not is_host then

      if probe_header == nil and #pending_state >= STATE_HEADER then
        if not probe_asked then machine:save(PROBE_STATE); probe_asked = true; probe_at = os.time() end
        local d = read_state_file(PROBE_STATE)
        if d and #d >= STATE_HEADER then probe_header = d:sub(1, STATE_HEADER); write_build_id(probe_header)
        elseif os.time() - probe_at > 5 then probe_header = false; log("could not check the MAME build (no probe state)")
        else return end
      end
      if probe_header and pending_state:sub(1, STATE_HEADER) ~= probe_header then
        log("state header mismatch: ours %s, theirs %s", sig_hex(probe_header), sig_hex(pending_state))
        send_to(host_peer, "X" .. string.char(local_slot))
        lose("a different MAME build - everybody must use the same mame.exe (get it from seibucup.online)")
        return
      end
      local path, err = write_state_file(pending_state)
      if path then
        local nbytes = #pending_state
        pending_state = nil
        if spec_base then
          log("state written -> %s (%d bytes), loading it now (mid-match join)", path, nbytes)
          start_load()
        else
          log("state written -> %s (%d bytes), telling the host we are ready", path, nbytes)
          send_to(host_peer, "R" .. string.char(gen))
          enter_ready()
        end
      else

        write_fail = write_fail + 1
        if write_fail == 1 or write_fail % 60 == 0 then log("cannot write the state file: %s", tostring(err)) end
        if write_fail >= 180 then lose("cannot write the state file (%s)", tostring(err)) end
      end
    elseif is_spec and is_relay and not pending_state and ((now_ms() - hs_wait) & 0xffffffff) > (tonumber(os.getenv("SCNP_HS_RETRY_MS") or "") or 3000) then

      send_to(host_peer, "H" .. string.char(0, VERSION, 0, cfg.slot, 0, 0) .. mame_bytes())
      hs_wait = now_ms()
      if not spec_asked then spec_asked = true; log("no state yet - asking the host again every 3 s") end
    elseif not is_host and os.time() - phase_since > (is_spec and spec_timeout_s or sync_timeout_s) then
      if is_spec and spec_saw_play then lose("the host's launcher is too old to let people watch - ask the host to restart their launcher (it updates itself)")
      elseif is_spec then lose("the host is not sending the match (it may have ended already) - try again from the launcher")
      else lose("no game state from the host in %d s", sync_timeout_s) end
    end
    if is_host and save_requested_at then
      local data, info = read_state_file()
      if data then
        save_requested_at = nil
        write_build_id(data)
        broadcast("S" .. string.char(gen) .. u32le(#data) .. data)
        log("sent state %s (%d bytes, gen %d) to %d player(s)", info, #data, gen, nplayers - 1)
        enter_ready()
      elseif os.time() - save_requested_at > 3 then
        lose("cannot read the saved state (%s)", tostring(info))
      end
    end
    return
  end

  if phase == "ready" then
    pump()
    if phase ~= "ready" then return end
    if is_host then
      local missing = {}
      for s = 2, nplayers do if not (peers[s] and peers[s].loaded) and not SCNP_PVE.dropped[s] then missing[#missing + 1] = s end end
      if #missing == 0 then
        broadcast("G" .. string.char(gen))
        log("everybody has the state (gen %d), loading", gen)
        start_load()
      elseif os.time() - phase_since > ready_timeout_s then
        lose("player %s did not receive the state within %d s", table.concat(missing, ","), ready_timeout_s)
      end
    elseif os.time() - phase_since > ready_timeout_s then
      lose("the host did not start within %d s", ready_timeout_s)
    end
    return
  end

  if phase == "loading" then
    pump()
    if phase == "loading" and load_started and os.time() - load_started > 5 then
      lose("the game state did not load (see MAME's message; is the state folder writable?)")
    end
    return
  end

  if resync_pending and is_host then clear_all_inputs(); begin_sync(string.format("resync #%d", stats.resyncs + 1)); stats.resyncs = stats.resyncs + 1; return end
  if SCNP_PVE.sync_join and is_host then SCNP_PVE.sync_join = false; clear_all_inputs(); begin_sync("PvE: a player joins"); return end

  if cfg.web and not is_replay then
    local W = SCNP_WAIT
    if agg[frame + 2] == nil then
      pump(); if is_host then try_broadcast() end
    end
    if agg[frame + 2] == nil and phase == "play" and not reloading then
      if not W.on then W.on = true; W.deadline = os.time() + wait_timeout_s; W.t0 = os.clock(); stats.stalls = stats.stalls + 1; emu.pause() end
      if os.time() > W.deadline then
        W.on = false; emu.unpause()
        lose("connection lost - no input from %s for %d s (frame %d)", is_host and "a player" or "the host", wait_timeout_s, frame + 2)
      end
      return
    end
    if W.on then
      W.on = false; emu.unpause()
      local ms = (os.clock() - W.t0) * 1000
      if ms > stats.max_stall_ms then stats.max_stall_ms = ms end
      stats.stall_total_ms = stats.stall_total_ms + ms
      if ms >= 20 then stats.long_stalls = stats.long_stalls + 1 end
      scnp_ddw_add(ms)
    end

    if not is_spec and not SCNP_PVE.catchup then
      if phase ~= "play" or reloading then W.base = nil
      else
        local t = now_ms()
        if not W.base then W.base, W.bf = t, frame end
        local lag = ((t - W.base) & 0xffffffff) * 0.06 - (frame - W.bf)
        if lag > 30 then W.base, W.bf, lag = t, frame, 0 end
        local want = lag < 1.5
        if want ~= spec_throttled then
          spec_throttled = want; if not want then stats.catchups = (stats.catchups or 0) + 1 end
          pcall(function() machine.video.throttled = want end)
        end
      end
    end
  end
  if is_host then spec_join_step(); scnp_ckpt_step() end
  if is_spec and SCNP_SHADOW then scnp_shadow_step() end

  frame = frame + 1
  scnp_poss_step()
  scnp_stage_palette()
  scnp_live_step()

  scnp_gg_step()
  if SCNP_PK.state == "run" and scnp_pk_step() then
    scnp_pk_finish()
    if is_host and nplayers >= 2 and not result_written then scnp_write_result() end
    if not rec_written then rec_save(true) end
  end
  if clock_start then
   if clock_run then
    local due = math.max(0, clock_u0 - math.floor((frame - clock_start) / clock_boundary))

    local floor_unit = (due == 0) and 1 or due
    if mem:read_u16(CLOCK_ADDR) > floor_unit then
      clock_ours = true; mem:write_u16(CLOCK_ADDR, floor_unit); clock_ours = false
      if floor_unit <= BEEP_RED then beep_want = beep_want + 1 end
    end
   end

    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state == nil and nplayers >= 2 and not SCNP_PVE.on then scnp_pk_decide() end
    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run" and is_host and nplayers >= 2 and not result_written and not SCNP_PVE.on then
      scnp_write_result()
    end

    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PVEGOD.on and is_host and not result_written then scnp_write_result() end
    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run" and not rec_written and (not SCNP_PVE.on or SCNP_PVEGOD.on) then rec_save(true) end
  end
  local nxt = frame + 1
  local target = frame + cfg.delay
  local mask = (is_spec or is_replay) and 0 or read_local_input()

  if is_replay then

    local sg = rp.segments[rp_seg]
    if sg and sg.at == rp_pos and rp_pos > 0 then
      rp_seg = rp_seg + 1
      write_state_file(sg.state)
      frame = frame - 1; phase = "loading"; rp_phase = "loading"; reloading = true; load_started = os.time()
      machine:load(STATE_NAME)
      return
    end
    if rp_pos >= #rp.inputs then
      if phase ~= "ended" then phase = "ended"; set_overlay(C_INFO, "REPLAY: end of the recording - close this window"); status("replay finished") end
      for s2 = 1, 4 do apply_input(s2, 0) end
      return
    end
    rp_pos = rp_pos + 1
    agg[nxt] = rp.inputs[rp_pos]; scnp_devr_play()
  elseif is_host then
    if target > last_broadcast then inputs[1][target] = mask; if target > (SCNP_DD.hi[1] or 0) then SCNP_DD.hi[1] = target end end
  elseif not is_spec then
    send_to(host_peer, "I" .. string.char(gen) .. u32le(target) .. string.char(mask))
  end
  if is_spec or SCNP_PVE.catchup then

    local behind = agg_max - frame
    if is_spec then scnp_catchup_step(behind) end
    local want_throttle = behind < 15
    if behind > 90 then want_throttle = false end
    if SCNP_PVE.catchup and not is_spec and behind < 10 then SCNP_PVE.catchup = false; want_throttle = true; log("PvE: caught up at frame %d", frame) end
    if want_throttle ~= spec_throttled then
      spec_throttled = want_throttle
      pcall(function() machine.video.throttled = want_throttle end)
    end
  end

  if frame % 30 == 0 and not is_replay then
    local ping = "P" .. string.char(gen) .. u32le(now_ms())
    if is_host then
      broadcast(ping)

      hud_dev[1] = local_dev
      local q = {}
      for i = 1, 4 do q[i] = (i == 1) and 0 or (rtt[i] and math.min(254, math.floor(rtt[i] / 4)) or 255) end
      broadcast("T" .. string.char(gen, q[1], q[2], q[3], q[4], hud_dev[1] or 0, hud_dev[2] or 0, hud_dev[3] or 0, hud_dev[4] or 0))
      local nspec = 0
      for s = 5, 12 do if peers[s] and peers[s].ready and not peers[s].shadow then nspec = nspec + 1 end end
      if nspec ~= SCNP_SPEC.n then log("watching now: %d", nspec) end
      SCNP_SPEC.n = nspec
      broadcast("V" .. string.char(gen, nspec))
      for i = 1, 4 do hud_ping[i] = (q[i] < 255) and q[i] * 4 or nil end
    else
      send_to(host_peer, ping)
      if not is_spec and local_dev ~= local_dev_sent then
        send_to(host_peer, "D" .. string.char(gen, local_dev))
        local_dev_sent = local_dev
      end
    end
  end

  if frame % 60 == 0 and not is_replay then
    local s = ram_checksum()
    if is_host then local_sums[frame] = s; sum_hist[frame] = s; sum_hist[frame - 1800] = nil
    else send_to(host_peer, "C" .. string.char(gen) .. u32le(frame) .. u32le(s)) end
  end
  if is_replay and frame % 60 == 0 and cfg.log then log("replay frame %d sum %08x", frame, ram_checksum()) end

  if not is_replay then pump() end
  if is_host then autojoin_step(); try_broadcast(); scnp_dd_host() else scnp_dd_report() end
  scnp_ddw_log()
  if agg[nxt] == nil then
    local t0 = os.clock()
    local deadline = os.time() + wait_timeout_s
    stats.stalls = stats.stalls + 1
    while agg[nxt] == nil do
      pump()
      if is_host then try_broadcast() end
      if reloading or phase ~= "play" then for s = 1, 4 do apply_input(s, 0) end; return end
      if os.time() > deadline then
        local who = "the host"
        if is_host then
          local missing = {}
          for s = 2, nplayers do if inputs[s][nxt] == nil then missing[#missing + 1] = "player " .. s end end
          who = table.concat(missing, ", ")
        end
        lose("connection lost - no input from %s for %d s (frame %d)", who, wait_timeout_s, nxt)
        return
      end
    end
    local ms = (os.clock() - t0) * 1000
    if ms > stats.max_stall_ms then stats.max_stall_ms = ms end
    stats.stall_total_ms = stats.stall_total_ms + ms
    if ms >= 20 then stats.long_stalls = stats.long_stalls + 1 end
    scnp_ddw_add(ms)
  end

  local a = agg[nxt]
  if SCNP_RELOAD and mem:read_u8(CLOCK_ADDR + 2) ~= SCNP_RELOAD then mem:write_u8(CLOCK_ADDR + 2, SCNP_RELOAD) end
  if SCNP_FREE then
    local cr = mem:read_u8(CREDITS_ADDR)
    if cr <= 3 then mem:write_u8(CREDITS_ADDR, 9); SCNP_FREE_ADD = SCNP_FREE_ADD + 9 - cr end
  end
  if SCNP_PVE.on then for s = 2, 4 do if a[s] == 0xff then scnp_pve_drop(s) end end end
  for s = 1, 4 do apply_input(s, (SCNP_PVE.on and s >= 2 and a[s] == 0xff) and 0 or a[s]) end
  agg[nxt] = nil
  if not is_replay and not is_spec then rec_inputs[#rec_inputs + 1] = { a[1], a[2], a[3], a[4] }; scnp_devr_rec() end

  if is_spec then SCNP_SPEC_HIST = SCNP_SPEC_HIST or {}; SCNP_SPEC_HIST[nxt] = a; SCNP_SPEC_HIST[nxt - 180] = nil end
  if is_spec and SCNP_SPEC_POKE and nxt == SCNP_SPEC_POKE then mem:write_u32(0x113820, mem:read_u32(0x113820) ~ 0x00350000); log("test: drifted on purpose at frame %d", nxt) end

  if is_host and not is_replay then check_sums() end

  if frame % 600 == 0 then
    local by, bx = mem:read_i32(0x113820), mem:read_i32(0x113824)
    log("frame %d  stalls %d  max stall %.1f ms  desyncs %d  resyncs %d  ball=(%.1f, %.1f)  clock=%d  long stalls %d  stall ms %d",
        frame, stats.stalls, stats.max_stall_ms, stats.desync, stats.resyncs, by / 65536, bx / 65536, mem:read_u16(CLOCK_ADDR),
        stats.long_stalls, math.floor(stats.stall_total_ms))
  end
end

SCNP_FORM = { sel = ({ cupsoc = 0x109b3b, cupsocs2 = 0x109c73 })[SCNP_GAME], tex = {}, png = {
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA7UlEQVR42tVUyw6CMBAcF87GxjtpuBMJ/QM/3D8ASbgjelcb71APQCRQ1gdyoGmatJPp7s5sdqXMbWu0sO1zeCWwi4ALD/PsRHJwHLFs9S61hcJuDIAaZXKI3ukqo8Vxrtjdi29075xaGMlZDM3LtIYrG5r4TlAQAFAxRMsIcOTo51kntjdAq/BzzSntv19azfe4A+uTsPo9b6/hIAXw2GnG76bKzvK+iD0cEI0So+zgBVeWhnESoGwMtdGjvMwkk5rvhKCYl0UZPaPm3db9s9/18BiHfUC0tVn8FpulzlTeUFIJ/3lUTErN+539BPB8W/O96k/2AAAAAElFTkSuQmCC",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABCElEQVR42tWUzW7DIAzH/3M4T0W9R5R7pSi8wR68b0BWqXea9b4l6j3JDnQKA+Z2SydtKALJv/gL2zyY6W099TL3vVSvBHYRcOIxr90oDtua1TbXQvurWHQ8dgBIOcgIeIkwHeQz43u1JDR/6KmPgJcszNuSurWg7jjvV427Ye/xmKONLrYtAQC1KR1qoFCfjOvNvB8C32WiPFa3twPtY/np486f0AGPx3y9f7lTdw7AeRMDnz2FWQar/Ibv9IG43IRIc/X7dtYeMw1TNMBwKWjObe2Gg2JC00UFYSnu7bDnhUkG4I7jH2Z873oLy/4jNCCn/sv5lqt/+qaS5bFpeON1uyi08ufa741CV+qsOX50AAAAAElFTkSuQmCC",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABDUlEQVR42r1Uyw6CMBAcl56NjXcCvZsQ+gd+uH8Amniv6F0l3gEPxVBprQ+QpmnSTna3s7O7M9lclk3JXfuYnAneRcDJD/ut88gHZ2l3UQcLlu++NgBm5kU05ajO38XOAJAjMwocAJNNybdT8LZzMJQYefU2BdV6m6p7nKtqp+HaheYiWBUEAFTYaJUCQfTkXMTduTdih5ZxnXyec9r130+PnK9xBeYH7tT7r7VG2CgAt9jSO+6sW5bGCr+IbQ+INhPM5qrPVWddOwomyIGqFdQVNlXVPvJ8TQQJWEb92ja7nEmr5SfosTH01sPjNSwA7uLW9jdfTDRTNdcRCznzwzLv1/az87QYxDv83foOWL5W3C9elzMAAAAASUVORK5CYII=",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABCElEQVR42tWUzW7DIAzH/3M4T0W9R5R7pSi8wR68b0BWqXea9b4l6j3JDnQKA+Z2SydtKALJv/gL2zyY6W099TL3vVSvBHYRcOIxr90oDtua1TbXQvurWHQ8dgBIOcgIeIkwHeQz43u1JDR/6KmPgJcszNuSurWg7jjvV427Ye/xmKONLrYtAQC1KR1qoFCfjOvNvB8C32WiPFa3twPtY/np486f0AGPx3y9f7lTdw7AeRMDnz2FWQar/Ibv9IG43IRIc/X7dtYeMw1TNMBwKWjObe2Gg2JC00UFYSnu7bDnhUkG4I7jH2Z873oLy/4jNCCn/sv5lqt/+qaS5bFpeON1uyi08ufa741CV+qsOX50AAAAAElFTkSuQmCC",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA+ElEQVR42tVUSw6CMBB9Fg5g456U7k0IvYEH9wYgCXtE9ioXAFxQpEIZ/LGg6WLal/m8ee1sVHPbNSW37UtwZSAXAwoapr1jQcFRSHqrudJWCrsRAKY7k4E/gdZ2VVPy01K5zYNsyoH9KzEm5gXNzv2VaRPBsypp4dqGxtLZ5wwAWD5GqxBwhA4ufYO9DwCpkdsbOdfB+z1nyfC+6Hp+wP1VY9Ne9q3hKPic3pqlsbwPco8HhO6EO8V433vXlgfjxEClBbWlDbMqFURp0gngRszOWLdFGYdF/9i/9W6HxzQsAd5xs+jNt2udqRENq5gOHuY/leZ97/0A2FNZ6l9WW50AAAAASUVORK5CYII=",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA+ElEQVR42tVUzQ6CMAz+LDsbF+8EuRuJewMf3DdATbwP9K4S74KHgeIcRSVoXEjT8a3rz7d2oIrjuMik69tFBwK7CNjzMG+9ChhYxPPsttGQlk6qLbQOsKhvwiKz9G6Xt/mOAVBjZYQqMrnuyXfPiRHH9wOhOrElc7m+bAycO+HQm6YEAJS67b3AwbeR59mdb//JMI9eLwtt7P/76q0tcPoZY0vdal1mWVv+G76fB0RZiYeam542cpjIyjpveDCXVDQHoLENmNBCL4KIyc23kULVWv7Peow9I0JANudGcvSlmeqY593KEvOwWtX4ntg6YZ52ytv/3PoK+idXa8KylKMAAAAASUVORK5CYII=",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABAklEQVR42sVUyw6CMBAcF87GxjuB3k0I/QM/3D8ATbxX9K4S74CHFjHSFrU+GsKBYbs7Ozs7Ee1p3lbM9OzTI8F5CDi4YXd0EbvgPDMDcgcAJMZK84BDG8Dbyvvysdw5ANKdkWCPsGgrtv4Fb8X1k8TIqbewKK31tkfKeqPgxqxZsCgJAKg0xwex4XKeAMAl6XNHg3+a9Pm20Obx+6Hr+RJnYLpjRr2/OmuElbyxVIyH0Zrl3YleyD1cELoTZHP2tNe7sQxMXYb2AiS2saM0HqQIczI7W71DMRj9L3ns03qr5WGHOcA6bgZ/s9kfdqrqgecg525YFJZh0P7OSi/e0fvRV3wWU3s84A6IAAAAAElFTkSuQmCC",
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABDUlEQVR42r1Uyw6CMBAcl56NjXcCvZsQ+gd+uH8Amniv6F0l3gEPxVBprQ+QpmnSTna3s7O7M9lclk3JXfuYnAneRcDJD/ut88gHZ2l3UQcLlu++NgBm5kU05ajO38XOAJAjMwocAJNNybdT8LZzMJQYefU2BdV6m6p7nKtqp+HaheYiWBUEAFTYaJUCQfTkXMTduTdih5ZxnXyec9r130+PnK9xBeYH7tT7r7VG2CgAt9jSO+6sW5bGCr+IbQ+INhPM5qrPVWddOwomyIGqFdQVNlXVPvJ8TQQJWEb92ja7nEmr5SfosTH01sPjNSwA7uLW9jdfTDRTNdcRCznzwzLv1/az87QYxDv83foOWL5W3C9elzMAAAAASUVORK5CYII=",
} }
function SCNP_FORM.decode(s)
  local abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out, bits, n = {}, 0, 0
  for c in s:gmatch("[^=]") do
    bits = (bits << 6) | (abc:find(c, 1, true) - 1); n = n + 6
    if n >= 8 then n = n - 8; out[#out + 1] = string.char((bits >> n) & 0xff) end
  end
  return table.concat(out)
end
function SCNP_FORM.texture(i)
  local t = SCNP_FORM.tex[i]
  if t == nil then

    local ok, bm = pcall(emu.bitmap_argb32.load, SCNP_FORM.decode(SCNP_FORM.png[i + 1]))
    local ok2, tx = false, nil
    if ok and bm then ok2, tx = pcall(function() return machine.render:texture_alloc(bm) end) end
    t = (ok2 and tx) and { bm = bm, tx = tx } or false
    SCNP_FORM.tex[i] = t
  end
  return t and t.tx
end
function SCNP_FORM.draw()
  local base = SCNP_FORM.sel
  if not base or mem:read_u8(base + 2) ~= 2 then return end
  local picked = mem:read_u8(base)
  for _, off in ipairs({ 4, 6 }) do
    local cur = mem:read_u8(base + off)
    if cur ~= 0 and cur & picked == 0 then
      local i = 0
      while cur > 1 do cur = cur >> 1; i = i + 1 end
      local tx = SCNP_FORM.texture(i)
      if tx then

        local x0, y0 = 41 + 64 * (i % 4), (i < 4) and 41 or 137
        screen.container:draw_quad(tx, x0 / 320, y0 / 240, (x0 + 46) / 320, (y0 + 43) / 240)
      end
    end
  end
end

function scnp_costume_names_draw()
  local C = SCNP_COSTUME
  if not C.on then return end
  local Ls, Rs = C.seat[scnp_seat_of(1)], C.seat[scnp_seat_of(2)]
  local ln, rn = Ls and Ls.name ~= "" and Ls.name or nil, Rs and Rs.name ~= "" and Rs.name or nil
  if not ln and not rn then return end
  for i = 0, 15 do
    if mem:read_u16(0x107002 + i * 8) == 0x5eef then

      local y = mem:read_i16(0x107006 + i * 8) + 49
      if y < 0 or y > 230 then return end
      if ln then screen:draw_text(88 - text_w(ln) / 2, y, ln, 0xffffffff, 0xb0000000) end
      if rn then screen:draw_text(232 - text_w(rn) / 2, y, rn, 0xffffffff, 0xb0000000) end
      return
    end
  end
  local H = C.HUD
  if not H.vis then return end
  if (H.lastVis or -100000) < frame - 300 then H.bannerTo = frame + 240 end
  H.lastVis = frame
  if ln and rn and H.bannerTo and frame < H.bannerTo then
    screen:draw_text("center", 66, ln .. "   vs   " .. rn, 0xffffffff, 0xb0000000)
  end
end

function scnp_costume_board_draw()
  local C, B = SCNP_COSTUME, SCNP_COSTUME.BOARD
  if not C.on or not B.vis then return end
  local scr = machine.screens[":screen"]
  local F = C.HUD.F
  local function box(x0, y0, x1, y1, c) scr:draw_box(x0, y0, x1, y1, 0, c) end
  local function rgb(t, k) return 0xff000000 | (math.min(255, math.floor(t[1] * k)) << 16) | (math.min(255, math.floor(t[2] * k)) << 8) | math.min(255, math.floor(t[3] * k)) end
  for side = 1, 2 do
    local s = C.seat[scnp_seat_of(side)]
    if s then
      local x0 = B.X[side].px
      local kit = (C.kit and C.kit[side]) or s.home
      local a, b = kit[1], scnp_flag_mid(kit)
      box(x0 - 1, 111, x0 + 47, 145, 0xff101018)
      for x = 0, 45 do
        local t = (x >= 15 and x < 31) and b or a
        for y = 0, 31, 4 do box(x0 + x, 112 + y, x0 + x + 1, 116 + y, rgb(t, 0.86 + 0.14 * math.sin(x * 0.16 - y * 0.10))) end
      end
      local ab = (s.abbr or ""):upper():sub(1, 3)
      local lx, ly = x0 + 23 - (#ab * 14 - 2) // 2, 122
      local cells = {}
      for n = 1, #ab do
        local g = F[ab:sub(n, n)]
        if g then
          for y = 0, 5 do for x = 0, 5 do
            if g[y + 1]:sub(x + 1, x + 1) == "#" then cells[#cells + 1] = { lx + (n - 1) * 14 + x * 2, ly + y * 2, y } end
          end end
        end
      end
      for _, c in ipairs(cells) do box(c[1] - 1, c[2] - 1, c[1] + 3, c[2] + 3, 0xff000000) end
      for _, c in ipairs(cells) do box(c[1], c[2], c[1] + 2, c[2] + 2, c[3] < 2 and 0xfff7ce00 or (c[3] == 5 and 0xffffff94 or 0xffffff00)) end
      local nm = s.name or ""
      if nm ~= "" then
        local tw = 6 * #nm
        pcall(function() tw = manager.ui:get_string_width(nm) * scr.width end)
        local tx = x0 + 23 - tw / 2
        if side == 1 then tx = math.min(tx, 79 - tw - 2) else tx = math.max(tx, 243) end
        box(tx - 3, 144, tx + tw + 3, 153, 0xd80a0c14)
        scr:draw_text(tx, 145, nm, 0xff7af2fa, 0x00000000)
      end
    end
  end
end

function scnp_pick_draw()
  local P = SCNP_PICK
  if not P.sel or not (SCNP_SEL and SCNP_SEL.on) or SCNP_SEL.mirror or SCNP_PVE.on or nplayers < 2 or local_slot > 4 then return end
  if mem:read_u8(P.sel) ~= 2 or mem:read_u16(P.taken) ~= 0 then return end
  local b = GAME_PLAYER[local_slot]
  local t
  if b == 1 and scnp_pick_hold(1) then t = scnp_tr("The 2P side picks its country first - wait a moment")
  elseif b == 2 then t = scnp_tr("Your side picks first - choose your country") end
  if t then screen:draw_text("center", HUD_H + 3, t, 0xffffe080, 0xc0000000) end
end

function scnp_mirror_note_draw()
  local P = SCNP_PICK
  if not screen or not P.sel or not (SCNP_SEL and SCNP_SEL.on and SCNP_SEL.mirror) or SCNP_PVE.on or nplayers < 2 then return end
  if mem:read_u8(P.sel) ~= 2 then return end
  local t, w = scnp_tr("You may pick the same team as the other side"), screen.width
  local half = 88
  pcall(function() half = math.max(60, math.min(w / 2 - 4, manager.ui:get_string_width(t) * w / 2 + 6)) end)
  screen:draw_box(w / 2 - half, 21, w / 2 + half, 31, 0xffffd600, 0xe0101018)
  screen:draw_text("center", 22, t, 0xffffe060, 0x00000000)
end

SCNP_ENDWAIT = {}
SCNP_ENDWAIT.KO = {
  { w = 104, h = 11, r = "54,0,6,1 13,0,9,1 94,0,6,2 0,0,6,2 82,0,7,2 25,0,9,2 70,0,5,2 37,0,9,2 54,1,2,1 13,1,2,1 44,2,2,1 30,2,2,1 54,2,6,1 27,2,2,1 8,0,2,4 78,0,2,4 61,0,2,4 76,0,1,4 90,0,2,4 2,2,2,2 13,2,9,2 96,2,2,2 31,3,3,1 56,3,2,1 25,3,3,1 37,3,9,1 87,2,2,3 84,2,2,3 37,4,2,1 17,4,2,1 29,4,2,1 53,4,10,1 90,4,3,2 76,4,4,2 8,4,3,2 12,5,11,1 24,5,11,1 86,5,3,1 1,4,4,3 95,4,4,3 37,5,9,2 54,6,9,1 73,2,1,6 70,2,2,6 83,5,2,3 86,6,2,2 26,7,7,1 94,7,6,1 0,7,6,1 43,7,2,1 38,7,2,1 58,7,5,1 14,7,7,1 32,8,2,1 85,8,3,1 54,8,4,1 25,8,2,1 20,8,2,1 13,8,2,1 82,8,2,2 70,8,5,2 4,8,2,2 94,8,2,2 98,8,2,2 0,8,2,2 36,8,11,2 85,9,2,1 25,9,9,1 13,9,9,1 102,0,2,11 8,6,2,5 78,6,2,5 76,6,1,5 90,6,2,5 54,9,9,2 26,10,7,1 14,10,7,1" },
  { w = 74, h = 11, r = "62,0,7,1 24,0,6,2 32,0,2,2 0,0,6,2 12,0,6,2 37,0,9,2 61,1,9,1 50,0,2,3 54,0,1,3 39,2,5,1 20,0,2,4 68,2,2,2 61,2,2,2 28,2,6,2 50,3,5,1 37,3,4,1 42,3,4,1 4,2,2,3 24,4,6,1 32,4,2,1 49,4,6,1 43,4,3,1 61,4,9,1 37,4,3,1 20,4,3,2 3,5,3,1 24,5,10,1 62,5,7,1 54,5,1,2 49,5,4,2 30,6,4,1 3,6,2,1 12,2,2,6 24,6,2,2 62,6,2,2 67,6,2,2 36,6,11,2 48,7,7,1 2,7,3,1 0,8,4,1 48,8,2,2 12,8,7,2 52,8,3,2 60,8,11,2 24,8,7,2 0,9,3,1 56,0,2,11 8,0,2,11 20,6,2,5 32,7,2,4 41,8,2,3 72,9,2,2 54,10,1,1" },
}
function scnp_endwait_draw()
  if is_replay or is_spec or local_slot < 1 or local_slot > 4 or nplayers < 2 or not screen then return end
  if SCNP_PVE.on and not SCNP_PVEGOD.on then return end
  if clock_start == nil or mem:read_u16(CLOCK_ADDR) ~= 0 then return end
  if not SCNP_PVEGOD.on and SCNP_PK.state ~= "off" and SCNP_PK.state ~= "done" then return end
  local E, u, w, h = SCNP_ENDWAIT, 2, screen.width, screen.height or 240
  local sub = tr("Closing the window now can lose the match record")
  local tip = tr("[Tip!] Closing the game by hand during a match, not letting it close by itself, may bring a penalty")
  if cfg.lang == "ko" then
    if not E.rs then
      E.rs = {}
      for i, L in ipairs(E.KO) do
        local t = {}
        for x, y, a, b in L.r:gmatch("(%d+),(%d+),(%d+),(%d+)") do t[#t + 1] = { tonumber(x), tonumber(y), tonumber(a), tonumber(b) } end
        E.rs[i] = t
      end
    end
    local hh = 0; for _, L in ipairs(E.KO) do hh = hh + L.h * u + 6 end
    local y = math.floor(h / 2 - (hh + 12) / 2)
    screen:draw_box(w / 2 - 120, y - 10, w / 2 + 120, y + hh + 23, 0xffffd600, 0xe8101018)
    for i, L in ipairs(E.KO) do
      local x0 = math.floor(w / 2 - L.w * u / 2)
      for _, R in ipairs(E.rs[i]) do screen:draw_box(x0 + R[1] * u, y + R[2] * u, x0 + (R[1] + R[3]) * u, y + (R[2] + R[4]) * u, 0, 0xffffe040) end
      y = y + L.h * u + 6
    end
    screen:draw_text("center", y + 1, sub, 0xffd8d8d8, 0x00000000)
    screen:draw_text("center", y + 10, tip, 0xffffc060, 0x00000000)
  else
    local y = math.floor(h / 2 - 16)
    screen:draw_box(w / 2 - 120, y - 6, w / 2 + 120, y + 37, 0xffffd600, 0xe8101018)
    screen:draw_text("center", y + 2, tr("Wait until the game closes by itself"), 0xffffe040, 0x00000000)
    screen:draw_text("center", y + 14, sub, 0xffd8d8d8, 0x00000000)
    screen:draw_text("center", y + 23, tip, 0xffffc060, 0x00000000)
  end
end
local function on_frame_done()
  step()

  local W = SCNP_WAIT
  if W.on then if W.drawn then return end; W.drawn = true else W.drawn = false end
  if phase == "play" then scnp_pvegod_step(); qc_step(); SCNP_FORM.draw(); scnp_night_draw(); scnp_comic_draw(); scnp_costume_hud_draw(); scnp_costume_names_draw(); scnp_costume_board_draw(); draw_hud(); scnp_pick_draw(); scnp_mirror_note_draw(); qc_draw(); scnp_specchat_draw(); scnp_catchup_draw(); scnp_endwait_draw() elseif SCNP_QUIET then scnp_night_draw() else draw_overlay() end
end

if cfg.mode == "probe" then
  local pf = 0
  scnp_probe_sub = emu.register_frame_done(function()
    pf = pf + 1
    if pf == 30 then machine:save(PROBE_STATE) end
    if pf > 30 then
      local d = read_state_file(PROBE_STATE)
      if d and #d >= STATE_HEADER then write_build_id(d:sub(1, STATE_HEADER)); log("build id: %s", sig_hex(d)); machine:exit()
      elseif pf > 900 then log("probe: no state was written"); machine:exit() end
    end
  end)
  return
end

setup_fields()
if is_host then set_state_name(1); bind_local_keys() end
set_overlay(C_INFO, is_host and "NETPLAY: starting..." or "NETPLAY: connecting...")
log("state dir: %s | cfg dir: %s", state_dir, manager.options.entries.cfg_directory:value())

frame_sub    = emu.register_frame_done(on_frame_done)
SCNP_LOADSUB = emu.register_frame_done(function() if SCNP_LOADIN then scnp_load_latch(); SCNP_LOADIN = nil end end)

if cfg.web then
  SCNP_WAIT.sub = emu.register_periodic(function()
    if phase == "play" and not is_replay then pump(); if is_host then try_broadcast() end end
  end)
end
postload_sub = emu.add_machine_post_load_notifier(on_post_load)
stop_sub     = emu.add_machine_stop_notifier(function()
  rec_save(false)
  restore_fields()
  log("stopped at frame %d: stalls %d, max stall %.1f ms, desyncs %d, resyncs %d, long stalls %d, stall ms %d, catch-ups %d",
      frame, stats.stalls, stats.max_stall_ms, stats.desync, stats.resyncs, stats.long_stalls, math.floor(stats.stall_total_ms), stats.catchups or 0)
  if logf then logf:close() end
end)

SCNP_POPCLEAR = 0
SCNP_POPSUB = emu.register_frame_done(function()
  if SCNP_POPCLEAR > 0 then SCNP_POPCLEAR = SCNP_POPCLEAR - 1; machine:popmessage() end
end)

log("netplay.lua v%d loaded: game=%s mode=%s addr=%s port=%d delay=%d players=%s",
    VERSION, SCNP_GAME, cfg.mode, cfg.addr, cfg.port, cfg.delay, is_host and tostring(nplayers) or "?")
log("MAME %s", mame_str(MAME_MINOR))
