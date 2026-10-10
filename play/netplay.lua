-- Seibu Cup Soccer Online - netplay script (netplay.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online)
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
-- Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public License for
-- details (the package's bin\legal\GPL-3.0.txt, the site's legal/GPL-3.0.txt, or <https://www.gnu.org/licenses/>).
-- Additional terms under section 7 of the GPL: a modified version must be marked as changed from the original,
-- and it may not use the name "Seibu Cup Soccer Online" (세이부 컵 사커 온라인).

local VERSION = 23     -- 23: quick chat F1-F8 (the M message, after a goal and at full time); no game change - the relay's random 2 vs 2 draws all four (the room's owner too, he keeps its controls from any seat, ROOMINFO says where) and swaps the country pickers inside each team every match of an FT series (user 2026-10-10); 22: the 2 vs 2 bottom line (1P/2P marks and PUSH START / CREDIT from the status routine at cupsocs2 $a8a8, cupsoc $a308) is blanked like the CREDIT text - 11 more ROM words (user 2026-10-10 "2:2 PUSH START도 지워줘"); 21: a level series match can go to golden goal instead of penalties (F pk 2, replays "pk":2); 20: GOD's tournament draws run on the country 1P pointed at (F god 2, replays "god":2); 19: the input delay follows the connection during a match (the host sends L, the others report their waits in W); 18: PvE may let 1P pick GOD (hold pass while confirming; the host says so in F, replays in "god"); 17: the host tells everybody how many are watching (V), shown right of the HUD clock; 16: a versus country select has no countdown and a country one side took cannot be taken by the other
                       --     (two ROM patches every peer must have: the host says so in F, replays in "sel")
                       -- 15: 2v2 seats are the board's players (1P+3P vs 2P+4P) and an FT series swaps 2v2 sides too;
                       --     a stretched match clock is run by the board itself (its tick reload byte, see install_clock_gate)
                       -- 14: free play - every screen keeps the credits topped up (a RAM write all peers make)
                       -- 13: PvE rooms (humans on 1P's team against the CPU; a guest may leave mid-match)
                       -- 12: the host also says whether a level match goes to penalties (FT) - a peer without it would carry on differently
                       -- 11: the host picks the pitch (SCNP_STAGE, sent in the handshake) - both sides must draw the same

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
  web = env("SCNP_WEB", "0") == "1",       -- the browser build: never wait in a loop (the page must get its turn to deliver the socket data)
  lang    = env("SCNP_LANG", "en"),
  replay  = env("SCNP_REPLAY", nil),           -- playback: the .scr file (percent-encoded path)
  replay_dir = env("SCNP_REPLAY_DIR", nil),    -- recording: where finished matches are kept
}
local is_teams = (cfg.teams == "2v2")
-- free play: the board has no such DIP, so the credits are kept topped up (replays: only if their header says so)
SCNP_FREE = (cfg.mode ~= "replay")
-- the board runs a stretched clock itself (its tick reload byte); replays only if their header says so
SCNP_PACE = (cfg.mode ~= "replay")
SCNP_RELOAD = nil          -- the reload byte's value while that is on (frames per unit - 1)
SCNP_FREE_ADD = 0          -- credits free play put in: the 2v2 start sees every credit that is used up
-- PvE: every human on 1P's team against the CPU. One global table (the main chunk is at the 200-local limit)
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

local frame = 0          -- lockstep frame counter (declared here: the clock gate below needs it)
-- Which edition of the game are we driving? The original (cupsoc) and :Selection: (cupsocs)
-- share the board, the object RAM and the palette buffer, but their variables sit at different
-- addresses and :Selection: runs its match clock faster. Every number below was confirmed on a
-- running machine. A global table, not locals: the main chunk is at Lua's 200-local limit.
SCNP_GAME = env("SCNP_GAME", "cupsoc")
if SCNP_GAME ~= "cupsocs" and SCNP_GAME ~= "cupsocs2" then SCNP_GAME = "cupsoc" end
SCNP_G = ({
  -- clock, frame counter, score/team pair, credits, sound latch, frames per clock tick
  cupsoc  = { clock = 0x109d64, framectr = 0x109284, score_l = 0x109d6f, score_r = 0x109db7,
              team_l = 0x109d6e, team_r = 0x109db6, credits = 0x109294, latch = 0x100700, fpu = 72,
              pm = 0x109b37, tm = 0x109d6c, tc = 0x109d6d, pc = 0x109d55, ctl = 0x10a080 },
  -- :Selection:, the set with Korea in the team list. Same variables as cupsocs; it paces its
  -- clock like the original, 72 frames to a unit, where cupsocs uses 60.
  cupsocs2 = { clock = 0x109ef4, framectr = 0x109394, score_l = 0x109eff, score_r = 0x109f47,
              team_l = 0x109efe, team_r = 0x109f46, credits = 0x1093a4, latch = 0x100740, fpu = 72,
              pm = 0x109c6f, tm = 0x109efc, tc = 0x109efd, pc = 0x109ee5, ctl = 0x10a230 },
  -- kept for the rooms and replays v1.5.19 made before the other set replaced it
  cupsocs = { clock = 0x109ef4, framectr = 0x109394, score_l = 0x109eff, score_r = 0x109f47,
              team_l = 0x109efe, team_r = 0x109f46, credits = 0x1093a4, latch = 0x100740, fpu = 60 },
})[SCNP_GAME]
local CLOCK_ADDR, FRAMECTR_ADDR, CLOCK_UNITS = SCNP_G.clock, SCNP_G.framectr, 90
if SCNP_PVE.on and not SCNP_G.pm then SCNP_PVE.on = false end        -- the old :Selection: set has no PvE
local clock_tap, beep_tap = nil, nil
local clock_secs, clock_units0, clock_spu = 150, 90, 150 / 90
-- The clock behaves like the board's: it stops while the game celebrates a goal or lines up a
-- kick-off (players found a clock that kept running through goals awkward). SCNP_CLOCK=run brings back
-- the continuous clock of netplay 8/9 (the game's own decrements held, the script paces it by lockstep
-- frame count); replays recorded with it say so in their header and play back that way.
local clock_run = env("SCNP_CLOCK", "stop") == "run"
clock_fpu, hud_tick_frame = 72, -100000     -- the game tries a clock tick every clock_fpu frames while its clock runs
clock_start, clock_u0, clock_boundary, clock_ours = nil, 0, 1, false
result_written = false      -- the host logs the final score once, when the clock runs out

local SOUND_CMD_ADDR, BEEP_CMD = SCNP_G.latch, 0x24
local beep_hold_fc = -1000
local beep_eating = false
local BEEP_KIND, BEEP_RED = 0x84, 10        -- the board's beep word is 0x8424; it beeps from 10 units down
beep_want, beep_inject = 0, false           -- beeps owed for clock units the script took down itself
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
-- Round BGM. Every netplay match is "round 1" to the board, so it always plays the same tune; the
-- sound CPU has all four round tunes (0x38 rounds 1/5, 0x3a 2/6, 0x36 3/7, 0x3c 4/8). Whenever the
-- game asks for the round-1 tune, this player's own choice goes out instead: SCNP_BGM=shuffle (the
-- match's random tune), <hex command> (that one tune), original (the board's). Each player hears
-- their own; sound is not part of the synchronised state, so nothing can desync over it.
local BGM_TRACKS = { 0x38, 0x3a, 0x36, 0x3c }
local bgm_mode = SCNP_PVE.on and "original" or env("SCNP_BGM", "shuffle")      -- PvE: the board's own round music
bgm_order, bgm_i, bgm_swap, bgm_pick, bgm_seed = {}, 0, nil, nil, 7
-- bgm_rand: the match's random tune (nil until its first round-tune request); bgm_fixed: this player's fixed pick;
-- bgm_sw: a switch of the round tune owed after a state load (scnp_bgm_after_load); bgm_inject_mirror: the
-- mirror word of a command put in place of an idle write, due at +4 in the same frame
bgm_rand, bgm_fixed, bgm_sw, bgm_inject_mirror = nil, nil, nil, nil
BGM_CHANNELS = { 0x202a, 0x20ff, 0x214e, 0x219d, 0x21ec, 0x223b, 0x228a }   -- the sound CPU's RAM: the tune on each channel
-- the tune this player wants for the round (nil: random, not settled yet)
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
  if SCNP_PVE.on then return end                    -- PvE: the board's own round music (it changes round by round)
  local fixed = tonumber(bgm_mode, 16)
  if fixed then
    local known = false
    for _, t in ipairs(BGM_TRACKS) do if t == fixed then known = true end end
    if not known then log("BGM: unknown tune %s, playing the board's own", bgm_mode); fixed = nil; bgm_mode = "original" end
  end
  bgm_fixed = fixed
  -- The match's random tune is worked out whatever this player's own choice is: the host tells a spectator who
  -- joins later (J), so everybody on "random" - players and spectators - hears the same tune.
  bgm_seed = 7
  for i = 1, #(cfg.token or "") do bgm_seed = (bgm_seed * 31 + cfg.token:byte(i)) & 0x7fffffff end
  bgm_order = BGM_TRACKS
  -- the game writes a word: low byte = number, high byte = kind; the pending word is the same
  -- pair swapped. Both writes are patched so the sound CPU sees a consistent command.
  -- One tune per match: the first round-tune request settles it (room token + the game's own frame counter,
  -- which every peer shares, and which differs from match to match); the requests that follow (every kick-off
  -- after a goal restarts the music) get the same tune, as the board restarts its own.
  scnp_bgm_tap = mem:install_write_tap(SOUND_CMD_ADDR, SOUND_CMD_ADDR + 5, "scnp_bgm", function(offset, data, mask)
    if offset == SOUND_CMD_ADDR then
      if bgm_sw then
        -- a switch owed after a state load: one step per frame (this write comes once a frame); a command goes in
        -- place of the game's idle write only, so a step waits while the game has a command of its own
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
        bgm_swap = nil            -- another command: a swap still pending belongs to nothing now
      end
    elseif offset == SOUND_CMD_ADDR + 4 then
      if bgm_inject_mirror then
        -- the injected command's mirror, whatever the game writes there this frame (as the clock beep does)
        local m = bgm_inject_mirror; bgm_inject_mirror = nil
        return m
      end
      if bgm_swap and (data >> 8) == BGM_TRACKS[1] then
        -- only the round tune's own mirror, never the mirror of some other command
        local t = bgm_swap; bgm_swap = nil
        return (t << 8) | (data & 0xff)
      end
    end
  end)
  if bgm_fixed then log("BGM: fixed tune %02x", bgm_fixed)
  elseif bgm_mode == "original" then log("BGM: the board's own")
  else log("BGM: random, one tune per match") end
end
-- After a state load (a spectator's hand-off, a resync, a replay segment): the sound CPU comes with the state, so
-- it goes on with what the saving machine played - the host's own choice - until the next kick-off. MrKei
-- (2026-09-25) watched on "random" and heard 1/5 (the host's fixed 38) for a few seconds, then 3/7. So if a round
-- tune is on and it is not this player's, switch at once.
-- The sound CPU's RAM holds the tune of each of its seven channels (BGM_CHANNELS; 0 = none), on both editions.
-- A bare "0x84 <tune>" while another tune plays starts it on four channels only; stop (82ff), a short sound two
-- frames later (8022, the select cursor tick) and the tune two frames after that take all seven most of the time
-- (11-13 in 14), so each try is checked 20 frames on and made again if it fell short (three tries at most).
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
-- one call per frame from the latch tap; idle = the game writes nothing this frame. Returns the word to send, or nil.
function scnp_bgm_switch_step(idle)
  local S = bgm_sw
  S.t = S.t + 1
  if S.step <= 3 then
    if not idle or S.t < 2 then return nil end        -- two frames apart, and never over the game's own command
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
-- Stage (pitch). A pitch is only colour: the tilemap never changes, and eight lines of the
-- tile palette carry the ground, the goal and the markings. Writing those lines is enough, so
-- nothing here depends on a program address and the same code serves every edition of the game.
-- Lines 2-5 and 9 also differ from round to round - those are the CPU side's kit - and are left
-- alone. The players' shadows are sprite palette line 0, which the game only ever loads for
-- round 1; the dirt pitch has its own in the ROM and it is written here too, which is why the
-- shadows stop being grass-green on dirt.
-- The COP copies this buffer to the palette device every frame, so the lines are rewritten every
-- frame. It lies outside the checksummed region and both sides write the same values.
-- One table, because the main chunk is at Lua's 200-local limit.
local SCNP_PAL = {
  TILE = 0x103000, SPR = 0x103800,
  GRASS = { 0x18C6, 0x318C, 0x4A52, 0x6318, 0x7BDE, 0x4210, 0x4A52, 0x5294, 0x56B5, 0x5EF7, 0x6739, 0x6F7B, 0x739C, 0x7BDE, 0x0124, 0x0000 },
  DIRT  = { 0x0CC6, 0x258C, 0x3E52, 0x5718, 0x6FDE, 0x3612, 0x3E54, 0x4695, 0x4AB7, 0x52F8, 0x5B3A, 0x637B, 0x679D, 0x6FDE, 0x0D2E, 0x0000 },
  -- P[pitch] = { { line, 16 words }, ... }
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
scnp_stage = SCNP_PVE.on and 0 or math.max(0, math.min(7, tonumber(env("SCNP_STAGE", "0")) or 0))   -- PvE: the board's own pitch
function scnp_install_stage_tap()
  -- kept under its old name: the handshake calls it whenever the host's pitch arrives
  if scnp_stage > 0 then log("stage: pitch of round %d", scnp_stage + 1) end
end
function scnp_stage_palette()
  scnp_stage_palette_pitch()
  scnp_ball_palette()
end
-- The ball's colour (user 2026-10-07, launcher 카페전용 > 공 색상, for the nicknames the relay unlocks it for): the
-- launcher says which in SCNP_BALL. The ball is drawn with sprite palette line 0, colours 0-4 (greys, dark to white;
-- found by painting each colour of a frame magenta - the same line's 5-13 are the goal posts and net, 14 the
-- players' shadows, and stay). During a match (the board's clock above 0) each grey becomes the colour at the grey's
-- brightness, from the game's own greys (kept in BSAVE whenever the game or the pitch code wrote them); out of a match
-- they go back, so the menus keep theirs. This screen only: nothing in the game reads the palette, and the others
-- see their own pick.
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
  if scnp_stage == 0 then return end          -- round 1's own colours, nothing to do
  local set = SCNP_PAL.P[scnp_stage]
  if not set then return end
  for i = 1, #set do
    local row = set[i]
    local a = SCNP_PAL.TILE + row[1] * 32
    for w = 1, 16 do mem:write_u16(a + 2 * (w - 1), row[w + 1]) end
  end
  local spr = (scnp_stage == 3) and SCNP_PAL.DIRT or SCNP_PAL.GRASS
  for w = 1, 16 do mem:write_u16(SCNP_PAL.SPR + 2 * (w - 1), spr[w]) end
end
local function time_byte() local t = tonumber(cfg.time) or 150; return math.max(1, math.min(255, math.floor(t / 10 + 0.5))) end
local function install_clock_gate()
  local secs = tonumber(cfg.time) or 150
  if secs < 30 then secs = 30 end
  if secs > 900 then secs = 900 end
  -- solo against the CPU ticks faster than a versus match, in the same proportion
  local fpu = (nplayers == 1 or SCNP_PVE.on) and math.floor(SCNP_G.fpu * 52 / 72 + 0.5) or SCNP_G.fpu
  clock_fpu = fpu
  local base = CLOCK_UNITS * fpu
  local target = math.floor(secs * 60 + 0.5)
  local boundary = target / CLOCK_UNITS
  clock_secs = secs
  clock_units0 = target < base and math.max(10, math.floor(CLOCK_UNITS * target / base + 0.5)) or CLOCK_UNITS
  clock_spu = secs / clock_units0
  -- A stretched match (protocol 15, 2026-09-25): clock + 2 is the value the board reloads its tick counter (clock + 3)
  -- from at every tick - 70 as it comes, a unit being 71 running frames. Holding the wanted frames per unit there, the
  -- board runs the clock at the right pace itself and every one of its ticks goes through; holding ticks back by
  -- a frame-counter window missed unit after unit when the ticks came irregularly (the clock stood at 2 for 12 s).
  -- One byte: up to 256 frames a unit (6:24); a longer match keeps the old pacing.
  SCNP_RELOAD = nil
  if SCNP_PACE and target > base then
    local per = math.floor(target / CLOCK_UNITS + 0.5)
    if per <= 256 then SCNP_RELOAD = per - 1; clock_fpu = per end
  end
  if SCNP_RELOAD_TAP then SCNP_RELOAD_TAP:remove(); SCNP_RELOAD_TAP = nil end
  if SCNP_RELOAD then
    SCNP_RELOAD_TAP = mem:install_write_tap(CLOCK_ADDR + 2, CLOCK_ADDR + 3, "scnp_reload", function(offset, data, mask)
      -- the board setting the reload byte (the word's high byte): ours instead
      if (mask & 0xff00) ~= 0 and SCNP_RELOAD then return (data & 0x00ff) | (SCNP_RELOAD << 8) end
      return nil
    end)
  end
  clock_start = nil                       -- a new match (or a resync) starts the clock afresh
  result_written = false
  if clock_tap then clock_tap:remove(); clock_tap = nil end
  clock_tap = mem:install_write_tap(CLOCK_ADDR, CLOCK_ADDR + 1, "scnp_clock", function(offset, data, mask)
    local cur = mem:read_u16(CLOCK_ADDR)
    if data > cur + 5 and data >= 30 then
      -- the game sets the clock for a match: the first one, or the next after CONTINUE. Pacing
      -- starts over from its first tick (or the old schedule would pin the new clock at 1)
      if clock_start then log("clock reset by the game (%d -> %d): new match", cur, data) end
      clock_start = nil; result_written = false
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
      -- the game is running its clock: the HUD counts on only while these keep coming (see match_clock_text)
      hud_tick_frame = frame
      if not clock_start then clock_start = frame; clock_u0 = cur; clock_boundary = target / cur end
    end
    if data == cur - 1 and clock_run then
      -- The script paces the game's OWN tick rather than replacing it: the board only ends the
      -- match (TIME UP) on a tick it made itself, so blocking every tick left the game running
      -- for ever with the clock stuck. Behind schedule: let this tick through. On schedule: hold.
      if not clock_start then
        clock_start = frame; clock_u0 = cur; clock_boundary = target / cur
        -- after CONTINUE the 2P side's goal byte keeps counting from the previous match (the site showed
        -- 0-5, 0-10, 1-12 ... 0-39): what counts is the difference from the start of THIS match. Not
        -- re-sampled on a resync (that also clears clock_start), only after the game reset the clock.
      end
      local due = math.max(0, clock_u0 - math.floor((frame - clock_start) / clock_boundary))
      if cur > due then beep_hold_fc = -1000; return nil end
      beep_hold_fc = mem:read_u16(FRAMECTR_ADDR)
      return cur
    elseif data == cur - 1 and target > base and SCNP_RELOAD then
      return nil                            -- the board paces it (the reload byte): every tick of its own goes through
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
    -- a beep the script owes: put it in place of the game's idle (zero) write, both words
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
  apply_time_dips()
  install_clock_gate()
  install_bgm_tap()
  scnp_install_stage_tap()
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

-- SCNP_SWAP=1 (1v1 rematches): seat 1 plays the game's 2P side (attacking right to left), seat 2
-- the 1P side. Seats, host role and the lockstep are untouched - only this mapping flips.
scnp_swap = (env("SCNP_SWAP", "0") == "1") and not SCNP_PVE.on
-- seat -> the board's player. A 2v2 room's seats ARE the board's players (protocol 15, user 2026-09-25): 1P+3P
-- the left team, 2P+4P the right, 1P and 2P pick the countries. An FT series swaps the sides every match, a 2v2
-- as well as a 1v1: then team 1 plays the right side as the board's 2P+4P.
local GAME_PLAYER = is_teams and (scnp_swap and { 2, 1, 4, 3 } or { 1, 2, 3, 4 }) or (scnp_swap and { 2, 1, 3, 4 } or { 1, 2, 3, 4 })
-- the seat that plays the board's player b (a global: the main chunk is at the 200-local limit)
function scnp_seat_of(b) for s = 1, 4 do if GAME_PLAYER[s] == b then return s end end return b end

local function apply_input(slot, mask)
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

local MSG_LEN = { M = 3, L = 2, W = 3, F = 5, H = 8, I = 6, A = 9, C = 9, P = 5, Q = 5, X = 1, R = 1, G = 1, T = 9, D = 2, J = 6, V = 2 }   -- F: gen, pitch, penalties (12), versus select (16), GOD (18); J: gen, frame, random tune (16); V: gen, spectators (17); L: gen, delay; W: gen, ms waited (19)
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
    if src >= 1 and src <= 8 then
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
-- The save-state signature identifies the MAME build (see the header note above). Drop it next to
-- the states so the launcher can show it: two people can then compare three characters instead of
-- discovering the hard way that their builds cannot exchange states.
local function write_build_id(header)
  if type(header) ~= "string" or #header < 32 then return end   -- 32 = the state header (see STATE_HEADER below)
  local hex = string.format("%02x%02x%02x%02x", header:byte(29), header:byte(30), header:byte(31), header:byte(32))
  local f = emu.file(state_dir, OPEN_WRITE | OPEN_CREATE | OPEN_CREATE_PATHS)
  if f:open("build.id") then return end
  f:write(hex)
  f:close()
end

-- ---------------------------------------------------------------- replay files
-- Layout: "SCNPRPL2\n" <json meta> "\n" u32 nseg { u32 at, u32 len, state } u32 nframes { 4 bytes per frame }
local function pct_decode_path(p) return (p:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end
-- Hardening (2026-10-09). Text from outside goes into the replay header (one JSON line) and the RESULT line: names lose
-- every control character (a newline would break the line) besides \ and ", and the room type is one the relay knows.
-- A replay file is checked before it is believed: at most 8 MB, 1-64 state segments, each inside the file, and no more
-- input frames than the bytes left. One global table (the main chunk is at the 200-local limit); nothing here touches the match.
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

-- A MAME save state starts with a 32-byte header: "MAMESAVE", format version, flags, the game's
-- name (18 bytes) and a 4-byte signature at offset 28 of everything the build registers as saveable. Two MAME
-- builds that differ at all (patched vs stock, different source) produce different signatures and
-- refuse each other's states with "invalid header", so compare it before handing one to MAME.
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
-- replay recording (every peer) / playback (SCNP_MODE=replay)
rec_inputs, rec_segments, rec_written = {}, {}, false
rp, rp_phase, rp_pos, rp_seg, rp_meta = nil, "boot", 0, 1, nil
-- Each seat's stick / keyboard (hud_dev) in the recording too, so a replay's HUD shows them like the match did
-- (user 2026-09-29): "<input index>:<four digits>" whenever they change, in the header as "devs". Older
-- recordings have none and show the dot as before.
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
-- in SEAT order (seat 1's goals first), whichever side of the pitch the seat plays on
-- The two team records sit at 0x109d6e (the side on the LEFT of the pitch, the game's 1P) and
-- 0x109db6 (RIGHT, the game's 2P): byte 0 = team id, byte 1 = goals. Found by dumping work RAM
-- against the score shown on screen; the earlier pair (0x109db7 as "1P", 0x10a091 as "2P") had the
-- right-hand team on the wrong side and a counter that is not a score at all.
local SCORE_LEFT, SCORE_RIGHT, TEAM_LEFT, TEAM_RIGHT = SCNP_G.score_l, SCNP_G.score_r, SCNP_G.team_l, SCNP_G.team_r
-- in SEAT order (seat 1's goals first), whichever side of the pitch the seat plays on
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
  -- the seat keeps peers on the SAME PC from writing the same file at once (a Windows sharing
  -- violation showed up as "Permission denied" when host and guest ran on one machine)
  local name = stamp .. "_" .. fn(a) .. "_vs_" .. fn(b) .. "_" .. s1 .. "-" .. s2 .. "_p" .. local_slot .. ".scr"
  local build = ""
  do local f = emu.file(state_dir, OPEN_READ); if not f:open("build.id") then build = f:read(8) or ""; f:close() end end
  local meta = string.format('{"v":2,"game":"%s","build":"%s","date":"%s","players":%d,"type":"%s","time":%d,"delay":%d,"names":"%s","score":[%d,%d],"complete":%s,"frames":%d,"slot":%d,"swap":%d,"clock":"%s","stage":%d,"pk":%d,"free":%d,"map":"%s","pace":%d,"sel":%d,"dd":"%s","god":%d,"ball":"%s","devs":"%s"}',
    SCNP_GAME, build, os.date("%Y-%m-%d %H:%M"), nplayers, SCNP_SAFE.type(cfg.teams), tonumber(cfg.time) or 150, cfg.delay, names, s1, s2, complete and "true" or "false", #rec_inputs, local_slot, scnp_swap and 1 or 0, clock_run and "run" or "stop", scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_FREE and 1 or 0, table.concat(GAME_PLAYER), SCNP_PACE and 2 or 1, SCNP_SEL.on and 1 or 0, table.concat(SCNP_DD.hist or {}, ";"), SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0, SCNP_PAL.BALL and SCNP_PAL.BALLNAME or "white", table.concat(SCNP_DEVR.hist, ";"))
  local path, err = replay_write(dir, name, meta, rec_segments, rec_inputs)
  if not path then
    -- a stray lock (antivirus, a leftover handle): try once more with a unique suffix
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
-- stalls: frames that had to wait for the other side's input at all (over the internet that is nearly
-- every frame). long_stalls: waits of a frame or more (>= 20 ms) - those are the hitches a player feels,
-- the launcher reads them to say when the input delay should go up.
local stats = { stalls = 0, max_stall_ms = 0, desync = 0, resyncs = 0, long_stalls = 0, stall_total_ms = 0, late_ms = 0 }
local connect_tries = 0
local hs_wait = 0

local function zeros() return { 0, 0, 0, 0 } end

local rtt = { nil, nil, nil, nil }
local function now_ms() return math.floor(emu.osd_ticks() * 1000 / emu.osd_ticks_per_second()) & 0xffffffff end
local screen = machine.screens[":screen"]

-- The HUD is drawn with MAME's UI font, whose height comes from ui.ini (font_rows); measure it
-- once and scale every width that was tuned for the default size (7.3 px tall, 4.2 px per char).
local HUD_TH = 7.3
pcall(function() HUD_TH = manager.ui.line_height * (screen.height or 224) end)
if not HUD_TH or HUD_TH <= 0 then HUD_TH = 7.3 end
local FS = HUD_TH / 7.3
local HUD_H = math.floor(HUD_TH + 3.7)
-- names arrive percent-encoded (UTF-8): os.getenv on Windows hands Lua the ANSI code page
-- version of the environment, which turned every Korean nickname into blanks on the HUD
local function pct_decode(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

-- ---------------------------------------------------------------- penalties (FT)
-- One table and global functions: the main chunk is at Lua's 200-local limit.
SCNP_PK = {
  on = env("SCNP_PK", "0") == "1",
  -- golden goal instead (SCNP_PK=2, user 2026-09-28): a level match at full time gets 30 s more, again and again,
  -- and the first goal ends it. gg_n: extensions so far; gg_end: the goal that ended it; gg_note: the notice's end
  gg = env("SCNP_PK", "0") == "2", gg_n = 0, gg_end = false, gg_note = 0, gg_text = nil,
  -- per edition: the match block (A0), the ROM words with their original and patched values, and
  -- the four human controller blocks ($1e apart).
  --   cupsoc   the shoot-out is for one side of humans: the rotation is pinned to P1 and P2 is given
  --            the 2P side's man each kick (below)
  --   cupsocs2 :Selection: rewrote the routine for humans on both sides - each side has its own
  --            rotation over its own humans ($1c / $64 bitmasks, $d4 / $d5), which also takes
  --            2v2 teammates in turn - so only the versus branch at $825e (bra $8f96) is pointed at it
  ED = {
    cupsoc   = { a0 = 0x109d50, br = 0x8262, br_old = 0x09ac, br_new = 0x0566, rot = 0x88de, rot_old = 0x5240, rot_new = 0x7000, ctl = 0x10a080 },
    cupsocs2 = { a0 = 0x109ee0, br = 0x8260, br_old = 0x0d36, br_new = 0x05ac, native = true },
  },
  state = nil,          -- nil: full time not reached; "off": no shoot-out; "run"; "done"
  started = 0, seen = false, lastc4 = -1, a = 0, b = 0, rounds = 0,
  -- a shoot-out that has not ended after this long is stopped. Every peer, spectator and replay
  -- must stop at the same frame, so SCNP_PK_CAP is only ever set by tests, for all of them alike.
  cap = tonumber(env("SCNP_PK_CAP", "480")) or 480,
  cut = false,          -- stopped by the cap: possibly mid-round, so it decides nothing
}

-- At full time: a level 1v1 in a series plays the board's shoot-out.
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
  -- somebody joining while it already runs (a spectator) leaves the kick in progress alone
  if (mem:read_u16(E.a0) & 0x4000) ~= 0 then P.seen = true; P.lastc4 = mem:read_u16(E.a0 + 0xc4) end
  log("penalties: level at full time (%d-%d) - shoot-out (mode %04x)", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), mem:read_u16(E.a0 + 2))
end

-- Every lockstep frame while it runs. True once it is over.
function scnp_pk_step()
  local P, E = SCNP_PK, SCNP_PK.ED[SCNP_GAME]
  if (mem:read_u16(E.a0) & 0x4000) ~= 0 then
    P.seen = true
    local c4 = mem:read_u16(E.a0 + 0xc4)
    if c4 ~= P.lastc4 and not E.native then
      -- a new kick: P2 takes the 2P side's man (the routine gave P1 the 1P side's). In 2v2 the
      -- teammates take the rounds in turn, a round being one kick each way: P1 and P2 on even
      -- rounds, P3 and P4 on odd ones - so on an odd round the routine's pick moves from P1 to P3.
      -- Rounds are counted as they come, not read off the kick number: that one starts again at
      -- sudden death, and Selection's own routine keeps alternating there.
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
      if c4 % 2 == 0 then man = mem:read_u32(E.a0 + 0x232) & 0xffffff          -- 1P side kicks: the 2P keeper
      else
        local keeper = mem:read_u32(E.a0 + 0x22e) & 0xffffff                    -- 2P side kicks: the man facing the 1P keeper
        man = keeper ~= 0 and (mem:read_u32(keeper + 0x96) & 0xffffff) or 0
      end
      if man ~= 0 then
        local c = E.ctl + (odd and 3 or 1) * 0x1e
        mem:write_u16(c + 2, mem:read_u16(c + 2) | 0x10); mem:write_u32(c + 8, man)
      end
    end
    P.a, P.b = mem:read_u16(E.a0 + 0xd0), mem:read_u16(E.a0 + 0xd2)          -- 1P side, 2P side
    -- the HUD: the counters hold something else (10 - 10 was seen) until the routine first sets them,
    -- so as long as they still read what they read when the shoot-out began, it is 0 - 0
    if not P.hud0 then P.hud0 = { P.a, P.b }; log("penalties: the counters read %d-%d as it begins (the HUD shows 0-0 until they move)", P.a, P.b) end
    if P.hud0 and P.hud0[1] == P.a and P.hud0[2] == P.b and not P.hud_live then P.ha, P.hb = 0, 0
    else P.hud_live = true; P.ha, P.hb = P.a, P.b end
    if frame - P.started < 60 * P.cap then return false end
    -- the cap can fall between a kick and its answer, so the score it stops at is not a result
    P.cut = true
    log("penalties: still going after %d s - stopped at %d-%d, counts for nobody", P.cap, P.a, P.b)
    return true
  end
  -- the flag drops when there is a winner; one that never came up is given up on
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

-- Golden goal. The clock gate asks this when the board's own tick would take the clock to 0: level in a series
-- match between humans - 30 s more (in clock units), and the notice at the top for 3 s.
function scnp_gg_extend()
  local P = SCNP_PK
  if not P.gg or P.gg_end or SCNP_PVE.on or nplayers ~= (is_teams and 4 or 2) then return nil end
  if mem:read_u8(SCORE_LEFT) ~= mem:read_u8(SCORE_RIGHT) then return nil end
  local units = math.max(1, math.floor(30 / clock_spu + 0.5))
  P.gg_n = P.gg_n + 1
  P.gg_note = frame + 180; P.gg_text = "GOLDEN GOAL - 30 more seconds, the first goal wins"
  if clock_run then clock_u0 = clock_u0 + units end      -- the paced clock's schedule moves with it
  log("golden goal: level at %d-%d - 30 s more (%d units, extension %d)", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), units, P.gg_n)
  return units
end

-- Every lockstep frame: a goal in extra time ends the match. The board changes the score at the restart after
-- the celebration; the clock goes to 1 with the tick counter (clock + 3) at 1, so the board's own tick takes it to
-- 0 at once and the board ends the match (TIME UP only comes from its own tick).
function scnp_gg_step()
  local P = SCNP_PK
  if P.gg_n == 0 or P.gg_end then return end
  if mem:read_u8(SCORE_LEFT) == mem:read_u8(SCORE_RIGHT) then return end
  P.gg_end = true
  P.gg_note = frame + 180; P.gg_text = "GOLDEN GOAL!"
  clock_ours = true; mem:write_u16(CLOCK_ADDR, 1); clock_ours = false
  mem:write_u8(CLOCK_ADDR + 3, 1)
  log("golden goal: %d-%d at frame %d - the match ends", mem:read_u8(SCORE_LEFT), mem:read_u8(SCORE_RIGHT), frame)
end

-- in seat order, like the score: with the sides swapped seat 1 is the 2P side
function scnp_pk_seats()
  if scnp_swap then return SCNP_PK.b, SCNP_PK.a end
  return SCNP_PK.a, SCNP_PK.b
end

-- ---------------------------------------------------------------- versus country select
-- The user (2026-09-25): in a versus (1v1 / 2v2 - not PvE, not solo) the country select has no countdown, and
-- a country one side took cannot be taken by the other. The board lets both sides pick the same country, and its
-- countdown (a 3-2-1 beside Korea at the end) picks for whoever has not chosen. Two ROM patches, the same on every
-- peer (the host decides and says so in F) and in replays that carry "sel":1:
--   cd   the step that counts the select clock down is taken out (two NOPs): it never runs out and never shows
--   occ  each cursor already skips a box another cursor sits on; that check now starts from the taken countries
--        ($4 of the select block) instead of from nothing, so a taken box is skipped the same way - the cursor
--        can never rest on one, so neither the shoot button nor anything else can pick it:
--          clr.w ($70,A0) / move.w ($36,A1),D0 / andi.w #bit,D0 / bne +10 / move.w (off,A1),D0 / or.w D0,($70,A0)
--        becomes
--          move.w ($4,A1),($70,A0) / btst #n,($37,A1) / bne.s +8 / move.w (off,A1),D0 / or.w D0,($70,A0) / nop
--        (12 words both; the first of the three "other cursor" checks of each of the 12 move routines)
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
SCNP_SEL.ED.cupsocs = SCNP_SEL.ED.cupsocs2          -- the old :Selection: set has the same code there

-- on = true patches, false puts the board's code back; every site is checked first (stock or ours)
function scnp_sel_apply(on)
  local S, E = SCNP_SEL, SCNP_SEL.ED[SCNP_GAME]
  local rg = manager.machine.memory.regions[":maincpu"]
  on = on and true or false
  if on == S.patched then S.on = on; return end
  if not E or not rg then S.on = false; return end
  local sites = { { E.cd, { 0x5368, 0x0070 }, { 0x4e71, 0x4e71 } } }
  for _, o in ipairs(E.occ) do
    local a, bit, off = o[1], o[2], o[3]
    local n = (bit == 1) and 0 or (bit == 2) and 1 or (bit == 4) and 2 or 3
    sites[#sites + 1] = { a,
      { 0x4268, 0x0070, 0x3029, 0x0036, 0x0240, bit, 0x6600, 0x000a, 0x3029, off, 0x8168, 0x0070 },
      { 0x3169, 0x0004, 0x0070, 0x0829, n, 0x0037, 0x6608, 0x3029, off, 0x8168, 0x0070, 0x4e71 } }
  end
  local from, to = on and 2 or 3, on and 3 or 2
  for _, st in ipairs(sites) do
    for i, v in ipairs(st[from]) do
      if rg:read_u16(st[1] + 2 * (i - 1)) ~= v then
        log("country select: the program is not the one the patch was made for (%06x) - left as it is", st[1]); S.on = false; return
      end
    end
  end
  for _, st in ipairs(sites) do for i, v in ipairs(st[to]) do rg:write_u16(st[1] + 2 * (i - 1), v) end end
  S.patched = on; S.on = on
  log("country select: %s", on and "no countdown, a taken country cannot be picked again" or "the board's own (countdown, same country allowed)")
end
-- the host decides at once: a versus of two or more (the others follow its F, replays their "sel")
if is_host and not is_replay and cfg.teams ~= "pve" and cfg.players >= 2 then scnp_sel_apply(true) end

-- The board's "CREDIT:09" at the bottom centre (user 2026-10-08: gone, cleanly). A status routine writes it into the
-- text layer (RAM 0x102000, row 29) every 4 frames: 5 label tiles from $55c8 ($05c8 before a game), then two digits
-- from $5de (or $5e7 twice above 99). Nine words per program make every one of those writes tile 0 (blank), so the
-- old text is wiped too: the label's tile goes to 0 and its +1 step becomes a NOP, the digits' "addi #$5de,D2" become
-- "moveq #0,D2 / nop". Display only - the text RAM is not in ram_checksum and the game never reads it, so peers or
-- spectators with an older script stay in step (they just still see it). Every peer, spectator, replay and the web
-- run it; solo play (no script) keeps the board's own. { address, board's word, ours }
SCNP_NOCREDIT = {
  cupsocs2 = { { 0x00ab9c, 0x55c8, 0x0000 }, { 0x00aba4, 0x5257, 0x4e71 }, { 0x00aa30, 0x05c8, 0x0000 }, { 0x00aa38, 0x5257, 0x4e71 },
               { 0x00abe8, 0x05e7, 0x0000 }, { 0x00abfe, 0x0642, 0x7400 }, { 0x00ac00, 0x05de, 0x4e71 }, { 0x00ac0c, 0x0642, 0x7400 },
               { 0x00ac0e, 0x05de, 0x4e71 },
               -- (22) the 2 vs 2 bottom line: the status routine at $a8a8 prints 1P/2P marks (tiles $15c0 / $75c2, two each) and a
               -- 7-tile word from $05d0 (PUSH START, CREDIT) over the line we draw there - each first tile -> 0, each "next tile" -> nop
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
SCNP_NOCREDIT.cupsocs = SCNP_NOCREDIT.cupsocs2      -- not checked on that set: the guard below leaves it alone if it differs
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

-- GOD (the final boss team, grey kit) for 1P in a PvE room whose host ticked "GOD" (SCNP_GOD=1; user, 2026-09-27).
-- The select screen turns the chosen box into a team through an 8-byte table of team id + 1 (cupsoc reads the one at
-- $7F36, cupsocs2 the one at $7F5E; GOD's id 11 -> $0C). While 1P's Pass is held - as the board sees it, which is
-- the same input on every screen - every read of those tables answers GOD, so holding Pass while confirming picks
-- it. The host says so in F, replays carry "god":1.
-- GOD has no place in the tournament's draw (it is the final boss): with 1P's team byte at 11 the draw kept giving
-- teams already played (Italy again and again) and a won round came back (user report 2026-09-28). From protocol 20
-- (F god 2, replays "god":2) the draw and the tournament screens - the draw's start (ED[4]) and the map / intro code
-- at $50000-$5FFFF - read the country 1P pointed at when confirming; everything else, the match itself, sees GOD.
SCNP_GOD = { on = false, fix = false, side = {}, ED = { cupsoc = { 0x7F2E, 0x7F45, 0x7f66, 0x7cf4 }, cupsocs2 = { 0x7F5E, 0x7F8D, 0x7fbe, 0x7d16 } } }
function scnp_god_apply(on, fix)
  local G = SCNP_GOD
  on = on and true or false
  fix = on and fix and true or false
  if on == G.on and fix == G.fix then return end
  for _, k in ipairs({ "tap", "wtap", "rtap" }) do if G[k] then G[k]:remove(); G[k] = nil end end
  G.on = false; G.fix = false; G.side = {}; G.pending = nil
  if not on then log("GOD: off"); return end
  local r = G.ED[SCNP_GAME]
  local port = manager.machine.ioport.ports[":PLAYERS12"]
  local pass = port and port.fields["P1 Pass"]
  if not r or not pass then log("GOD: not available for %s", tostring(SCNP_GAME)); return end
  local m, dv = pass.mask, pass.defvalue & pass.mask
  local cpu = manager.machine.devices[":maincpu"]
  G.tap = mem:install_read_tap(r[1], r[2], "scnp_god", function(offset, data, mask)
    if (port:read() & m) ~= dv then
      if fix and cpu.state["CURPC"].value == r[3] then     -- the select reading the confirmed box: remember its country
        local v = (mask == 0x00ff) and (data & 0xff) or (data >> 8)
        if v >= 1 and v <= 11 then G.pending = v - 1 end
      end
      return 0x0C0C
    end
    return data
  end)
  if fix then
    local lo, hi = TEAM_LEFT & ~1, TEAM_RIGHT | 1
    -- the select stores GOD in a side's team byte: that side's draws use the country; any other team there ends it
    G.wtap = mem:install_write_tap(lo, hi, "scnp_god_w", function(offset, data, mask)
      for _, a in ipairs({ TEAM_LEFT, TEAM_RIGHT }) do
        local hit = (a & ~1) == offset and ((a & 1) == 0 and mask & 0xff00 ~= 0 or (a & 1) == 1 and mask & 0x00ff ~= 0)
        if hit then
          local v = (a & 1) == 0 and (data >> 8) or (data & 0xff)
          if v == 11 and G.pending then G.side[a] = G.pending; G.pending = nil; log("GOD: picked over country %d", G.side[a])
          elseif v ~= 11 then G.side[a] = nil end
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
  log("GOD: 1P holds Pass while confirming a country to play as GOD%s", fix and " (draws on that country)" or "")
end
if is_host and not is_replay and cfg.teams == "pve" and env("SCNP_GOD", "") == "1" then scnp_god_apply(true, true) end

-- The host's full-time line: the launcher picks it up and reports it to the relay while MAME is
-- still open (score and team bytes: see SCORE_LEFT / SCORE_RIGHT / TEAM_LEFT / TEAM_RIGHT).
-- Seat order (seat 1 first), so the relay's "nick1 s1 - s2 nick2" holds with the sides swapped;
-- after a shoot-out it carries "pk" too.
function scnp_write_result()
  result_written = true
  local rs1, rs2 = rec_score()
  local rt1, rt2 = mem:read_u8(TEAM_LEFT), mem:read_u8(TEAM_RIGHT)
  if scnp_swap then rt1, rt2 = rt2, rt1 end
  local names = SCNP_SAFE.names(pct_decode(env("SCNP_NAMES", "")))
  local pks = ""
  -- a shoot-out cut off by the cap is left out: level at full time and no "pk" counts for nobody
  if SCNP_PK.state == "done" and not SCNP_PK.cut then local p1, p2 = scnp_pk_seats(); pks = string.format(',"pk":[%d,%d]', p1, p2) end
  log('RESULT {"score":[%d,%d],"teams":[%d,%d],"time":%d,"frames":%d,"players":%d,"type":"%s","names":"%s"%s}',
      rs1, rs2, rt1, rt2, clock_secs, frame - (clock_start or frame), nplayers, SCNP_SAFE.type(cfg.teams), names, pks)
end
-- The host's live score for the lobby (user 2026-10-02): "LIVE <seat 1's side> <other side> <seconds left> <input delay>"
-- when the score or the delay changes and every 10 s; the launcher / web page hands it to the relay. The delay is the
-- dynamic delay's value now (user 2026-10-03: the room list shows it). A log line only - nothing in the match.
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
-- at most 8 columns of a name, a wide (non-ASCII) character taking two
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

-- A 3x5 dot font for the small line at the bottom centre (user 2026-10-08: smaller than the UI font, which has no
-- size of its own). Rows top to bottom, bit 4 = left column; w = columns. Unknown characters are skipped.
SCNP_PF = {
  ["0"] = { 7, 5, 5, 5, 7 }, ["1"] = { 2, 6, 2, 2, 7 }, ["2"] = { 7, 1, 7, 4, 7 }, ["3"] = { 7, 1, 7, 1, 7 },
  ["4"] = { 5, 5, 7, 1, 1 }, ["5"] = { 7, 4, 7, 1, 7 }, ["6"] = { 7, 4, 7, 5, 7 }, ["7"] = { 7, 1, 1, 2, 2 },
  ["8"] = { 7, 5, 7, 5, 7 }, ["9"] = { 7, 5, 7, 1, 7 },
  A = { 2, 5, 7, 5, 5 }, B = { 6, 5, 6, 5, 6 }, C = { 3, 4, 4, 4, 3 }, E = { 7, 4, 6, 4, 7 }, F = { 7, 4, 6, 4, 4 },
  I = { 7, 2, 2, 2, 7 }, L = { 4, 4, 4, 4, 7 }, N = { 6, 5, 5, 5, 5 }, O = { 7, 5, 5, 5, 7 }, P = { 6, 5, 6, 4, 4 },
  S = { 3, 4, 2, 1, 6 }, T = { 7, 2, 2, 2, 2 }, U = { 5, 5, 5, 5, 7 }, D = { 6, 5, 5, 5, 6 }, Y = { 5, 5, 2, 2, 2 },
  ["%"] = { 5, 1, 2, 4, 5 }, [":"] = { 2, 0, 0, 0, 2, w = 1 }, ["."] = { 0, 0, 0, 0, 2, w = 1 }, [" "] = { 0, 0, 0, 0, 0, w = 2 },
}
-- width of a string in dots (1 dot between characters)
function scnp_pf_w(t)
  local n = 0
  for ch in t:upper():gmatch(".") do local g = SCNP_PF[ch]; if g then n = n + (g.w or 3) + 1 end end
  return math.max(0, n - 1)
end
-- draws runs = { {text, colour}, ... } with its top-left at x, y; u = native pixels per dot. A dark rim first, so
-- it reads on grass and on the white lines alike
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
                if pass == 1 then box(px - u * 0.5, py - u * 0.5, px + u * 1.5, py + u * 1.5, 0xff101410)
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

-- The seconds between two clock units are interpolated from lockstep frames that passed WHILE the
-- game was ticking its clock, so the HUD stops exactly when the game's clock stops (goals, kick-offs)
-- and is the same on every screen of the match.
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

SCNP_POSS = { a = 0, b = 0, last = 0 }      -- ball possession frames, 1P's side / 2P's side (draw_hud counts them)
local function draw_hud()
  if not cfg.hud or not screen or phase ~= "play" then return end
  local w = screen.width or 320
  box(0, 0, w, HUD_H, 0x8c000000)
  box(0, HUD_H, w, HUD_H + 1, 0x40000000)
  local x = 3
  for gi = 1, nplayers do
    -- left to right in GAME order (1P = the left side of the pitch), whoever sits there; a 2v2 by team, as the
    -- board lists them under its flags: 1P 3P | 2P 4P
    local g = is_teams and ({ 1, 3, 2, 4 })[gi] or gi
    local seat = scnp_seat_of(g)
    local dev = hud_dev[seat] or 0
    local col = (seat == local_slot) and 0xffffe9a8 or 0xffe4e4e4

    -- the web build draws the HUD in Neo둥근모, which has no ⌨ or ⏱: ▦ and ◷ there
    local glyph = (dev == 2) and "◉" or ((dev == 1) and (cfg.web and "▦" or "⌨") or "·")
    screen:draw_text(x, 1, glyph, col, 0)
    x = x + ((dev == 1) and 11 or 8) * FS
    local ms = (seat == 1) and nil or hud_ping[seat]
    local label = string.format("%dP", g)
    -- two seats leave room for a long name (a Korean character takes two columns); four do not
    local nm = short_name(hud_names[seat], (nplayers <= 2) and 16 or 8)
    if nm ~= "" then label = label .. " " .. nm end
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
  -- people watching, right of the clock: "(3)" (user, 2026-09-26) - the clock moves left to make room
  local stag = (SCNP_SPEC.n or 0) > 0 and ("(" .. SCNP_SPEC.n .. ")") or nil
  local cx = w - 6 - #clock * 5.4 * FS - 12 - (stag and (text_w(stag) + 2 * FS) or 0)
  local ccol = (frac > 0.5) and 0xfff4f4f4 or ((frac > 0.25) and 0xffffd98a or 0xffff9c9c)
  screen:draw_text(cx, 2, ctext, ccol, 0)
  if stag then screen:draw_text(w - 4 - text_w(stag), 2, stag, 0xffb8d8ff, 0) end
  -- the time bar: half as wide as it was and right up against the clock, so four names fit beside it (user,
  -- 2026-09-24: in 4-player games it sat on 4P's name); never drawn over the names or the REPLAY / watching
  -- tag (drawn below, once those are placed)
  local bw, bh, bx, by = 18, 5, cx - 3 - 18, math.max(3, math.floor(HUD_H / 2 - 2))
  local bar_from = x - 8 * FS + 2
  -- the series (FT) and, while they run, the penalties - left side first, like the names
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
        -- side A is seat 1 (or seats 1+2): the left side unless a 1v1 swapped them
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

  -- (free play: the credits never run out, so the hint goes once this seat is in the game)
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
    local tw = text_w(t)
    box(w / 2 - tw / 2 - 6, HUD_H + 14, w / 2 + tw / 2 + 6, HUD_H + 16 + HUD_TH + 4, 0xd0000000)
    screen:draw_text("center", HUD_H + 16, t, 0xffffd24a, 0)
  end
  -- where the board's "CREDIT:07" was (the ROM patch above blanks it): a small line in the 3x5 dot font, no box
  -- (user 2026-10-06 band, 2026-10-08 "2번" + smaller) - the FT series score in a series, ball possession, the site's
  -- address otherwise. Drawn on the screen only - it changes nothing in the lockstep or a replay
  if SCNP_G.credits and mem:read_u8(SCNP_G.credits) > 0 then       -- (not over the black screen before the board shows)
    local h = screen.height or 224
    local x0, x1, y0, y1 = w * 340 / 960, w * 552 / 960, h * 664 / 720, h * 703 / 720
    local u = h / 240                                                  -- one dot = one board pixel
    local ty = (y0 + y1) / 2 - 2.5 * u
    local function line(runs)
      local t = ""; for _, r in ipairs(runs) do t = t .. r[1] end
      scnp_pf_draw((x0 + x1) / 2 - scnp_pf_w(t) * u / 2, ty, u, runs)
    end
    -- ball possession, live (user 2026-10-06): the frames the ball's last toucher (0x1138ae) was a man of each side
    -- while the match clock ticks. The 22 men sit 0xdc apart from 0x111e54, the board's 1P side first (cupsocs2).
    -- Read only, so every screen of the match counts the same; the left number is the HUD's left side (1P)
    if SCNP_GAME == "cupsocs2" then
      local df = frame - SCNP_POSS.last; SCNP_POSS.last = frame
      if df > 0 and df < 30 and (frame - hud_tick_frame) <= clock_fpu + 6 then
        local o = mem:read_u32(0x1138ae) & 0xffffff
        if o >= 0x111e54 and (o - 0x111e54) % 0xdc == 0 then
          local i = (o - 0x111e54) // 0xdc
          if i < 11 then SCNP_POSS.a = SCNP_POSS.a + df elseif i < 22 then SCNP_POSS.b = SCNP_POSS.b + df end
        end
      end
    end
    local pt = SCNP_POSS.a + SCNP_POSS.b
    if pt >= 120 then
      local pa = math.floor(SCNP_POSS.a * 100 / pt + 0.5)
      line({ { "BALL  ", 0xff9fd8a8 }, { string.format("%d%%", pa), pa >= 50 and 0xffffd23f or 0xffffffff },
             { " : ", 0xffb0b0b0 }, { string.format("%d%%", 100 - pa), pa <= 50 and 0xffffd23f or 0xffffffff } })
    elseif scnp_series then
      local l, r = scnp_series[2], scnp_series[3]
      if scnp_swap then l, r = r, l end
      line({ { "FT" .. scnp_series[1] .. "  ", 0xffffd23f }, { string.format("%d : %d", l, r), 0xffffffff } })
    else
      line({ { "seibucup.online", 0xffe1e6e1 } })
    end
    -- a replay: the input delay at this point of the match, under the board's clock (right of the line above)
    if is_replay and SCNP_RPD then
      local d = SCNP_RPD.d0
      for i = 1, #SCNP_RPD.at do if frame >= SCNP_RPD.at[i] then d = SCNP_RPD.d[i] end end
      local t = "DELAY " .. d
      scnp_pf_draw(w * 0.868 - scnp_pf_w(t) * u / 2, ty, u, { { "DELAY ", 0xff9fd8a8 }, { tostring(d), 0xffffffff } })
      if d ~= SCNP_RPD.shown then SCNP_RPD.shown = d; log("replay: delay %d shown from frame %d", d, frame) end
    end
  end
  -- the input delay this match runs with: faint, in the bottom-left corner (user 2026-09-27)
  if not is_replay then screen:draw_text(2, (screen.height or 240) - 9, "delay " .. tostring(cfg.delay), 0x80ffffff, 0) end
end

local C_INFO, C_WARN, C_ERR = 0xffe8e8e8, 0xffffd040, 0xffff5050
local overlay, overlay_color, overlay_hint = nil, C_INFO, nil

local TR = {
  ["NETPLAY: starting..."] = { ko = "NETPLAY: 시작하는 중...", ja = "NETPLAY: 開始しています...", zh = "NETPLAY: 正在启动..." },
  ["GOLDEN GOAL - 30 more seconds, the first goal wins"] = { ko = "골든골! 30초 연장 - 먼저 골을 넣으면 승리", ja = "ゴールデンゴール！30秒延長 - 先に決めた方の勝ち", zh = "金球！加时30秒 - 先进球者获胜" },
  ["GOLDEN GOAL!"] = { ko = "골든골!", ja = "ゴールデンゴール！", zh = "金球！" },
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
-- draw_hud comes before tr in this file: as a local it was out of its reach (the 2v2 hint raised
-- "attempt to call a nil value (global 'tr')" every frame and never showed); a global it can call
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
  -- the launcher says it again once the window is closed (a player leaving is told by the relay)
  if fmt ~= "%dP left - game over" then log("LOST %s", string.format(tr(fmt), ...)) end
  overlay_hint = tr("close this window, then start again from the launcher")
  clear_all_inputs()
  phase = "lost"
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
if is_teams then allow = { 0x3f, 0x3f, 0x00, 0x00 } end   -- 1P and 2P pick; 3P and 4P have controls once they are in
if SCNP_PVE.on then allow = { 0xff, 0x00, 0x00, 0x00 } end      -- the others come in once the match runs (scnp_pve_step)
local aj = { stage = SCNP_FREE and "start" or "coins", at = 0, c0 = 0, tries = 0 }   -- free play: no coins to put in
local function credits() return mem:read_u8(CREDITS_ADDR) + SCNP_FREE_ADD end   -- + free play's top-ups: only goes down when used
local function schedule(slot, from, len, bits)
  for X = from, from + len - 1 do
    local a = auto[X]; if not a then a = { 0, 0, 0, 0 }; auto[X] = a end
    a[slot] = a[slot] | bits
  end
end
-- PvE, host only, every frame of play: keep every seated guest in the game on 1P's team, and continue
-- a match lost (or drawn) at full time. Everything goes out as inputs, so every screen plays the same.
function scnp_pve_step()
  local P, G = SCNP_PVE, SCNP_G
  local X = last_broadcast + cfg.delay + 2
  local pm = mem:read_u8(G.pm)
  -- before 1P has pressed start the mask belongs to the attract demo: nobody is brought in, nothing is continued
  if not P.saw_start then return end
  -- Who is where. The board marks a joiner as in the game as soon as its side choice opens, with the cursor
  -- on the CPU's side: he gets his controls only once he is on 1P's team (with them earlier his own presses
  -- chose the side - that is how people ended up against 1P). Should he stay on the CPU's team past the
  -- choice (shoot confirms it some 45 frames after START; 3 s is plenty), he is taken out (the leaver's
  -- marker) and brought in again.
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
      allow[s] = 0                                      -- choosing a side, or on the CPU's: no controls of his own
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
  -- full time: the scores count from this match's kick-off (after a CONTINUE the board keeps adding up)
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
  -- bringing the guests in: only while the clock runs (the board offers "LET'S JOIN!" in play)
  -- the side choice is confirmed with SHOOT (as in 2v2 - left to its own timer it ran ~6 s); another try
  -- inside it would press Left again and move the choice back to the CPU's side, so a try is given 3 s
  if P.cur and frame - P.at < 180 then return end
  P.cur = nil
  local ticking = clock_start ~= nil and clock > 0 and (frame - hud_tick_frame) <= clock_fpu + 6
  if not ticking or frame < P.next_try or pm & 1 == 0 then return end        -- only into 1P's own game
  -- everybody still outside comes in at once, 20 frames apart (the board takes them all together, each on 1P's
  -- team; one after another made the last one wait for everybody before him), one credit each
  local k, cr = 0, mem:read_u8(CREDITS_ADDR)
  for s = 2, nplayers do
    -- only somebody not in the game at all: while a side choice is open a second START would confirm it
    if not P.dropped[s] and pm & (1 << (s - 1)) == 0 then
      local t = X + k * 20
      if cr <= k then schedule(s, t, 6, 0x80) end
      -- START, then ONE press of Left once the side choice is open: each press moves its cursor (pressed
      -- again and again it wandered back to the CPU's side, held from before START it was not seen)
      schedule(s, t + 30, 6, 0x40); schedule(s, t + 35, 30, 0x04)
      schedule(s, t + 75, 6, 0x10)                        -- shoot confirms the side choice (START does not)
      P.jat = P.jat or {}; P.jat[s] = t + 30
      P.tries[s] = (P.tries[s] or 0) + 1
      log("PvE: bringing %dP onto 1P's team (try %d)", s, P.tries[s])
      k = k + 1
    end
  end
  if k > 0 then P.cur, P.at, P.next_try = true, frame, frame + 200 end
end

-- PvE: a guest left. The host stops waiting for him; the next input frame carries 0xff for him once.
function scnp_pve_left(s)
  local P = SCNP_PVE
  if P.dropped[s] then return end
  P.dropped[s] = true; P.mark[s] = true; allow[s] = 0
  inputs[s] = {}
  log("PvE: %dP left - the CPU takes over his man", s); status("PvE: %dP left - the match goes on", s)
end

-- PvE, every screen (and a replay), at the frame whose input says 0xff for seat s: out of the game
-- The "1P2P3P" under the score is text the board draws when somebody joins and never redraws when we take a player
-- out (the user saw 2P stay after 2P left, 2026-09-25). Each player's mark is 2x2 text tiles (rows 64 words apart,
-- 0x102000 on), top-left tile code 0x5e8 + 4*(n-1) under its own colour, packed left to right: take the leaver's
-- two columns out, move the marks after it left and blank the last pair. Every peer does it at the same frame.
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
    for _, o in ipairs({ 0, 0x48 }) do                         -- 1P's team, then the CPU's (0x48 further on)
      local tm = mem:read_u8(G.tm + o)
      if tm & bit ~= 0 then mem:write_u8(G.tm + o, tm & ~bit); mem:write_u8(G.tc + o, math.max(0, mem:read_u8(G.tc + o) - 1)) end
    end
    mem:write_u8(G.pc, math.max(0, mem:read_u8(G.pc) - 1))
    local c = G.ctl + (s - 1) * 0x1e
    local man = mem:read_u32(c + 4) & 0xffffff
    if man ~= 0 then mem:write_u8(man + 0xc8, 0) end             -- the man's own "steered by player n": the CPU's now
    mem:write_u16(c, 0x00ff); mem:write_u16(c + 2, 0); mem:write_u32(c + 4, 0); mem:write_u32(c + 8, 0)
    scnp_pve_unlabel(s)
  end
  SCNP_PVE.gone[s] = true
  log("PvE: %dP taken out of the game at frame %d", s, frame)
end

-- A 1v1 versus (host only): the first start press anybody makes also starts the board's other player, so whoever
-- was away from the keys a moment is on the country select too (no country countdown in a versus, so the select
-- waits for them) instead of the other side landing in a match against the CPU. The user, 2026-09-25.
SCNP_VS = { stage = "watch", hit = nil, at = 0, tries = 0 }
SCNP_SPEC = { n = 0 }      -- spectators watching this match: the host counts them and sends V with the HUD line (17)
SCNP_WAIT = { on = false, deadline = 0, t0 = 0 }   -- web: paused until the next frame's inputs are in (see step)
function scnp_vs_start_step()
  local V = SCNP_VS
  if V.stage == "done" then return end
  local pm = SCNP_G.pm and mem:read_u8(SCNP_G.pm)
  if V.stage == "watch" then
    -- try_broadcast notes the first start press as it goes out (V.hit = { frame, seat })
    if V.hit then V.stage = "press"; V.at = frame; log("versus: seat %d pressed start at frame %d - bringing the other side in", V.hit[2], V.hit[1]) end
    return
  end
  if V.stage == "press" then
    if frame - V.at < 20 then return end                   -- the press that was made goes through first
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
  -- the kick-off, for the join log: when each seat came in against it
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
    schedule(scnp_seat_of(1), X, 6, 0x40); schedule(scnp_seat_of(2), X + 10, 6, 0x40)   -- the board's 1P, then its 2P
    aj.stage, aj.at, aj.c0 = "start_wait", frame, c
  elseif aj.stage == "start_wait" then
    if frame - aj.at < 120 then return end
    if c <= aj.c0 - 2 then
      aj.stage = SCNP_G.tm and "join" or "join2"; aj.tries = 0
      log("2v2: seats %d and %d are picking the countries (credits %d)", scnp_seat_of(1), scnp_seat_of(2), c)
      status("2 vs 2: 1P and 2P pick the countries; 3P and 4P join their teams automatically")
    else aj.stage = "start"; aj.tries = aj.tries + 1; if aj.tries > 90 then lose("2v2: could not start the game") end end
  elseif aj.stage == "join" then
    -- 2P and 4P come in together, before kick-off (user, 2026-09-24: 4P came in some 4 s after it). START is
    -- tried every 30 frames or so until the board takes it (a credit goes - it takes joins from the match's
    -- intro on, some 200 frames before kick-off), one seat at a time so the credit says whose it was; 2P's side
    -- choice then gets Left (the left team; 4P's cursor already sits on the right) and SHOOT confirms it: left
    -- to its own timer the choice ran ~245 frames, so they appeared after kick-off, 4P last (it was only tried
    -- once 2P's credit had been seen). Now both are in some 40 frames after their START, ~2.5 s before kick-off.
    -- (by the board's player: its 3P joins the left team, its 4P the right; the seats follow the sides)
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
          if b == 3 then schedule(s, X, 25, 0x04) end      -- the left team: Left
          schedule(s, X + 35, 6, 0x10)                     -- shoot confirms the side choice (START does not)
          log("2v2: the board took %dP's start (frame %d)", s, j.x)
        elseif frame > j.x + 8 then j.st = "wait" end                      -- not taken yet: again
      elseif j.st == "wait" and not busy and frame >= (j.next or 0) then
        schedule(s, X, 6, 0x40); j.st, j.x, j.c0, j.next = "press", X, c, X + 30; busy = true
      elseif j.st == "choose" and frame - j.at > 420 then j.st = "wait"   -- never showed up: again
      end
      if j.st ~= "in" and j.st ~= "wrong" then all = false end
    end
    if all then aj.stage = "done"; log("2v2: everybody is in"); status("2 vs 2: everybody is in!") end
  elseif aj.stage == "join2" then                    -- (no player-mask address: one after the other, as before)
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

-- The input delay follows the connection during a match (protocol 19, user 2026-09-27). The host decides for everybody:
-- every 5 s it looks at the longest wait - its own, and what each player reports (W) - and goes up a frame when somebody
-- waited over 150 ms, down a frame after 5 calm seconds (under 60 ms) when every ping fits the smaller delay (never below 2, never
-- above 8; a drop that had to be undone within a minute is not tried again for 5 minutes). It says so in L and every
-- screen uses the new value from its next frame. Nobody has to switch at the same frame: an input carries the frame it
-- is for, so a frame skipped when the delay went up is filled on the host with that player's previous input, and an
-- input for a frame already sent out (when it went down) is dropped - the host's frames are what every screen plays.
-- Off (SCNP_DYNDELAY=0) when the host set the delay by hand, and in replays.
-- 2.0.23 (2026-10-09): "waited" is the part of each wait beyond a frame (late_ms below), the undone-drop floor holds only the
-- step dropped from, and the first 15 s decide nothing (a browser warms up there, hitching ~0.2 s for ~6 s)
-- (2.0.23) the waits of the last 5 s, logged as "DDW" every 300 frames with the wall-clock frame rate and the pings; and the
-- measure the auto delay goes by: only the part of a wait beyond a frame (stats.late_ms). A side running a hair ahead of the
-- other waits a few ms on nearly every frame and still makes 60 frames a second - measured 2026-10-09 (web_lag_test.py): a
-- web host waited ~240 times in 5 s, 1.5 s in all, at a steady 60 fps, which the old sum read as lag and took to 8
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
  -- a drop undone within a minute is not tried again for 2 minutes: the floor is the step it dropped from - only the first
  -- rise after it, back to that step (2.0.23; before, every rise in that minute raised the floor with it)
  if nd < od then D.lowered = frame; D.lowfrom = od
  elseif D.lowfrom and nd == D.lowfrom and frame - D.lowered < 3600 then D.floor = nd; D.floor_until = frame + 7200; D.lowfrom = nil   -- 2 min (was 5, 2026-10-02)
  else D.lowfrom = nil end
  broadcast("L" .. string.char(gen, nd))
  log("input delay %d -> %d frames at frame %d (%s)", od, nd, frame, why)
  -- kept for the replay's header ("dd"), so the server's copy shows how the delay moved (user 2026-09-29)
  D.hist = D.hist or {}
  if #D.hist < 60 then D.hist[#D.hist + 1] = string.format("%d>%d@%d", od, nd, frame) end
end
function scnp_dd_host()
  -- every 5 s alike (user 2026-09-29: "균일적으로 그냥 5초마다"): somebody waited over 150 ms in those 5 s -> a frame
  -- up; under 60 ms (calm) -> a frame down, when every ping fits the smaller delay and no recent undone drop holds it
  local D = SCNP_DD
  if not D.on or is_replay or phase ~= "play" then return end
  if frame - D.at < 300 then return end
  D.at = frame
  -- the first 15 s (the country select) decide nothing (2.0.23)
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
  -- one bad 5 s alone does not raise it any more (2026-10-02: a fifth of the raises were undone within 15 s - a single
  -- hiccup): two in a row, or one wait of 400 ms or more
  local bad = worst > 150
  local raise = bad and (D.badprev or worst >= 400)
  D.badprev = bad
  if bad and not raise then
    D.calm = 0
    log("input delay: %dP lost %d ms in 5 s - held at %d unless it happens again", who, math.floor(worst), d)
  elseif raise then
    D.calm = 0
    -- a frame up only while the delay is within 2 of what the pings need (the relay's own start formula, a browser's frame
    -- counted in): waits beyond that are a machine that cannot keep 60 frames a second (a phone's browser) - more delay does
    -- not help it, and it climbed to 8 with every web match (user 2026-09-29: "웹버전유저랑은 무조건 딜레이가 8이야")
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
  if is_host or is_spec or is_replay or phase ~= "play" or frame % 300 ~= 0 then return end   -- the host decides every 5 s
  local w = D.cw and (stats.late_ms - D.cw) or 0      -- the part of the waits beyond a frame (2.0.23)
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
      -- the delay went up: nobody sent this frame; that player's inputs are already past it
      if m == nil and (SCNP_DD.hi[s] or 0) > X then m = SCNP_DD.last[s] or 0 end
      if m == nil then
        local lv = SCNP_PVE.late[s] and SCNP_PVE.live[s]
        if SCNP_PVE.dropped[s] or (SCNP_PVE.joining and SCNP_PVE.joining[s]) or (SCNP_PVE.late[s] and (not lv or X < lv)) then m = 0 else return end
      end
      SCNP_DD.last[s] = m
      masks[s] = (m & allow[s]) | (a and a[s] or 0)
      if SCNP_PVE.mark[s] then masks[s] = 0xff end       -- cleared below, once this frame really goes out
    end
    if SCNP_PVE.on and masks[1] & 0x40 ~= 0 then SCNP_PVE.saw_start = true end
    -- the versus auto start sees a start press here, as it goes out: a frame broadcast while we wait on a late
    -- input is applied (and gone) before scnp_vs_start_step runs again (2026-09-26: missed, 1P went on alone)
    if SCNP_VS and SCNP_VS.stage == "watch" and not SCNP_VS.hit then
      for s2 = 1, nplayers do if masks[s2] & 0x40 ~= 0 then SCNP_VS.hit = { X, s2 } end end
    end
    for s = nplayers + 1, 4 do masks[s] = a and a[s] or 0 end
    -- a frame given up above (somebody's input not in yet) must not take the leaver's marker with it
    for s = 2, 4 do if SCNP_PVE.mark[s] and masks[s] == 0xff then SCNP_PVE.mark[s] = nil end end
    auto[X] = nil
    agg[X] = masks
    broadcast("A" .. string.char(gen) .. u32le(X) .. string.char(masks[1], masks[2], masks[3], masks[4]))
    for s = 1, nplayers do inputs[s][X] = nil end
    last_broadcast = X
    guard = guard + 1
  end
end

local function begin_sync(reason)
  -- PvE's timers count frames, and the count starts again after a sync: carry them over
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
  set_overlay(C_INFO, "NETPLAY: loading the game state...")
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
    -- The frame right after the hand-over runs on the input the host had already set for it (the state was
    -- saved after its step): cleared inputs here made the newcomer - and every spectator joining late - play
    -- that one frame differently (the game's own input copy at 0x109300 showed it)
    local a1 = agg[frame + 1]
    if a1 then
      if SCNP_FREE and mem:read_u8(CREDITS_ADDR) <= 3 then mem:write_u8(CREDITS_ADDR, 9) end   -- free play, as in step
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
  if is_spec then status("netplay synchronised: %d players, you are spectating", nplayers)
  else status("netplay synchronised: %d players, you are player %d, delay %d frames", nplayers, local_slot, cfg.delay) end
end


-- ================================================================== quick chat (F1-F8, protocol 23)
-- User 2026-10-10: "인게임에서 f1~f8까지 매크로 채팅", the look of the mockup (quickchat_2v2.png), "골 뒤랑 경기 끝에만". Eight fixed
-- phrases, sent as a number in the "M" message (gen, seat, phrase) and shown in each viewer's own language under the sender's
-- team flag: a dark band, a bar and the seat tag in the seat's marker colour (1P red, 2P blue, 3P yellow, 4P green), the
-- phrase in white. The window (user 2026-10-11 "골을 넣자마자 바로 ... 승부가 나자마자 바로 ... 채팅시간 끝나면 없애줘"): opens the
-- moment the ball goes in (the ball's handler at 0x1138a0 turns to the board's goal routine - the score byte only moves at the
-- restart, ~4.5 s later) for 7 s, and at full time (the relay keeps the games open 4 s after the result); the bands and the
-- phrase line go when it closes. One phrase per player per window, and the host lets a seat through at most every 3 s. It
-- never touches game memory, so the lockstep and the checksums do not see it, and replays do not keep it. One global table:
-- the main chunk is at Lua's 200-local limit.
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
  -- the phrase line's short names, for a screen where the whole phrases do not fit on one line
  S = {
    { ko = "인사", en = "Hi" }, { ko = "나이스 슛", en = "Nice shot" }, { ko = "아깝다", en = "Close" }, { ko = "나이스 패스", en = "Nice pass" },
    { ko = "감사", en = "Thanks" }, { ko = "미안", en = "Sorry" }, { ko = "한게임 더", en = "One more" }, { ko = "수고", en = "GG" },
  },
  -- the ball's handler while the board celebrates a goal (the same routine in both sets, :Selection:'s 0xcf4 further on)
  GOAL = { cupsoc = { [0x12064] = true, [0x12078] = true }, cupsocs2 = { [0x12d58] = true, [0x12d6c] = true } },
  COL = { 0xffff4a4a, 0xff4070ff, 0xffffd23f, 0xff3ccd5f },
  IN = 8, OUT = 14, GOALWIN = 420, GAP = 180,
  keys = {}, prev = {}, show = { {}, {} }, last = { -99999, -99999, -99999, -99999 }, sent = false, winTill = -1, score = nil,
  over = false, open = false, ingoal = false, goalAt = -99999, closeAt = nil, wc = {},
}
QC.GOAL.cupsocs = QC.GOAL.cupsocs2
for i = 1, 8 do QC.keys[i] = input:code_from_token("KEYCODE_F" .. i) end
function QC.text(id) local t = QC.T[id]; return t and (t[cfg.lang] or t.en) or "" end
function QC.short(id) local t = QC.S[id]; return t and (t[cfg.lang] or t.en) or "" end
-- the side whose flag a seat plays under: the board's 1P and 3P on the left (the seats are mapped, sides swap in a series)
function QC.side(seat) local gp = GAME_PLAYER[seat] or seat; return (gp == 1 or gp == 3) and 1 or 2 end
function qc_show(seat, id)
  if not seat or not id or seat < 1 or seat > 4 or not QC.T[id] then return end
  log("chat: %dP %s", seat, QC.T[id].en)
  if not QC.open then return end                 -- came in after this machine's window closed: nothing to show any more
  -- kept by the board's player: the tag and colour are the in-game marker's (a seat plays the board's 2P when sides are swapped)
  local gp = GAME_PLAYER[seat] or seat
  QC.show[QC.side(seat)][gp] = { id = id, at = frame }
end
-- the host: a player's phrase, checked (his own seat, a phrase there is, the window open, not too often) and passed on to everybody
function qc_from_peer(p, payload)
  local seat, id = payload:byte(1, 2)
  if not seat or seat ~= p.slot or seat < 1 or seat > 4 or not QC.T[id] or not QC.open then return end
  if frame - QC.last[seat] < QC.GAP then return end
  QC.last[seat] = frame
  qc_show(seat, id)
  broadcast("M" .. string.char(gen, seat, id))
end
function qc_send(id)
  QC.sent = true                                 -- one per window, whoever calls it (the phrase line goes)
  if is_host then
    if frame - QC.last[local_slot] < QC.GAP then return end
    QC.last[local_slot] = frame
    qc_show(local_slot, id)
    broadcast("M" .. string.char(gen, local_slot, id))
  elseif host_peer then
    send_to(host_peer, "M" .. string.char(gen, local_slot, id))
  end
end
-- each drawn frame: the window (a goal, or full time), and the keys
function qc_step()
  if phase ~= "play" then return end
  local g = QC.GOAL[SCNP_GAME]
  local goal = g and g[mem:read_u32(0x1138a0)] or false
  if goal and not QC.ingoal then QC.winTill = frame + QC.GOALWIN; QC.sent = false; QC.goalAt = frame end
  QC.ingoal = goal
  if SCNP_G.score_l and SCNP_G.score_r then      -- a goal the handler did not show (should not happen): the score's change
    local sc = mem:read_u8(SCNP_G.score_l) + mem:read_u8(SCNP_G.score_r)
    if QC.score and sc > QC.score and frame - QC.goalAt > 600 then QC.winTill = frame + QC.GOALWIN; QC.sent = false end
    QC.score = sc
  end
  -- full time: the clock at 0, not while a shoot-out is still on
  local over = clock_start ~= nil and mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run" and not SCNP_PVE.on
  if over and not QC.over then QC.sent = false end
  QC.over = over
  local open = over or frame <= QC.winTill
  if open ~= QC.open then
    QC.closeAt = (not open) and frame or nil
    if open then QC.show = { {}, {} } end
    log("chat window %s at frame %d%s", open and "open" or "closed", frame, open and (over and " (full time)" or " (goal)") or "")
  end
  QC.open = open
  if is_replay then return end
  for i = 1, 8 do
    local down = QC.keys[i] and input:code_pressed(QC.keys[i])
    if down and not QC.prev[i] and open and not QC.sent and not is_spec and local_slot >= 1 and local_slot <= 4 then
      qc_send(i)
    end
    QC.prev[i] = down
  end
end
-- a band fades in when it comes and out when the window closes
function QC.alpha(m)
  local a = math.min(1, (frame - m.at + 1) / QC.IN)
  if QC.closeAt then a = math.min(a, 1 - (frame - QC.closeAt) / QC.OUT) end
  return a
end
function QC.argb(col, a) return (math.floor(a * ((col >> 24) & 0xff) + 0.5) << 24) | (col & 0xffffff) end
-- the width of a string as the UI font draws it on the game screen. The UI's own measure is a share of the render target's
-- width, which moves with the window's shape; its ratio to ten Hangul syllables does not, and a syllable is 0.83 of the line
-- height (measured on 960x720 pictures, 2026-10-11 - the old estimate made spaces and Latin letters about twice too wide)
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
-- under each team's flag, one band per seat that spoke (2 vs 2: up to two), as in the mockup at 960x720
function qc_draw()
  if not screen then return end
  local w, h = screen.width or 320, screen.height or 240
  -- the phrases while one may be sent (user 2026-10-11 "하단에 한줄로"): one line along the bottom, "[F1] 안녕하세요! ..."; when the
  -- whole phrases do not fit the width, their short names, and only then F1-F4 over F5-F8 (the UI font has one size)
  if QC.open and not QC.sent and not is_spec and not is_replay and local_slot >= 1 and local_slot <= 4 then
    local kg, ig = QC.width(" "), QC.width("   ")
    local function lw(a, b, f) local x = 0; for i = a, b do x = x + QC.width("[F" .. i .. "]") + kg + QC.width(f(i)) + (i < b and ig or 0) end; return x end
    local f, rows = QC.text, { { 1, 8 } }
    if lw(1, 8, QC.text) > w - 8 then
      f = QC.short
      if lw(1, 8, QC.short) > w - 8 then f, rows = QC.text, { { 1, 4 }, { 5, 8 } } end
    end
    local lh = HUD_TH + 2
    local top = h - #rows * lh - 2
    box(0, top - 2, w, h, 0xc8000000)
    for r, rg in ipairs(rows) do
      local x = (w - lw(rg[1], rg[2], f)) / 2
      for i = rg[1], rg[2] do
        local k, t = "[F" .. i .. "]", f(i)
        screen:draw_text(x, top + (r - 1) * lh, k, 0xffffd23f, 0); x = x + QC.width(k) + kg
        screen:draw_text(x, top + (r - 1) * lh, t, 0xfff4f4f4, 0); x = x + QC.width(t) + ig
      end
    end
  end
  local rh, gap, y0 = h * 30 / 720, h * 6 / 720, h * 134 / 720
  local bar, pad, tgap = w * 5 / 960, w * 8 / 960, w * 7 / 960
  for side = 1, 2 do
    local y = y0
    for seat = 1, 4 do                          -- here: the board's player (1P..4P on the scoreboard)
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
    local ver, _, want = payload:byte(1, 3)
    if ver ~= VERSION then status("player %d has protocol version %d (need %d)", p.slot, ver, VERSION); return end
    local ml, mh = payload:byte(6, 7)
    local pm = (ml or 0) + (mh or 0) * 256
    if pm > 0 and MAME_MINOR > 0 and pm ~= MAME_MINOR then

      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_SEL.on and 1 or 0, SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0))
      if p.slot >= 5 then log("spectator %d has MAME %s (we run %s) - ignored", p.slot, mame_str(pm), mame_str(MAME_MINOR)); return end
      lose("MAME version differs: player %d has %s, you have %s - everybody needs the same MAME build", p.slot, mame_str(pm), mame_str(MAME_MINOR))
      return
    end
    if p.slot >= 5 then

      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_SEL.on and 1 or 0, SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0))
      if not p.ready then log("spectator %d joined", p.slot) end
      p.ready = true

      if phase == "play" and not p.join_at and p.handed ~= gen then
        p.join_at = frame + cfg.delay + 3
        log("spectator %d joins mid-match, state at frame %d", p.slot, p.join_at)
      end
      return
    end
    if SCNP_PVE.on and phase == "play" and p.slot >= 2 and p.slot <= 4 and not p.ready then
      -- PvE drop-in: a free seat taken while the match runs. He gets the running game like a spectator
      -- would, and his inputs are waited for only once the first one comes in for a frame not sent yet
      local P = SCNP_PVE
      P.dropped[p.slot] = nil; P.gone[p.slot] = nil; P.mark[p.slot] = nil; P.tries[p.slot] = nil
      P.late[p.slot] = nil; P.live[p.slot] = nil; allow[p.slot] = 0; inputs[p.slot] = {}; peer_sums[p.slot] = {}
      if p.slot > nplayers then nplayers = p.slot end
      send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_SEL.on and 1 or 0, SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0))
      p.ready = true
      -- he comes in through a resync: everybody loads the same state, so he is in step by construction.
      -- Until it starts he is not waited for - the host would stall on him and never reach the resync
      P.sync_join = true; P.joining = P.joining or {}; P.joining[p.slot] = true
      log("PvE: %dP joins the running match (resync)", p.slot); status("PvE: %dP is joining the match", p.slot)
      return
    end
    if p.ready then send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_SEL.on and 1 or 0, SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0)); return end

    if want and want >= 2 and want <= nplayers and want ~= p.slot and not peers[want] then
      peers[p.slot] = nil; peers[want] = p; p.slot = want
    end
    send_to(p, "H" .. string.char(gen, VERSION, cfg.delay, p.slot, nplayers, time_byte()) .. mame_bytes()); send_to(p, "F" .. string.char(gen, scnp_stage, SCNP_PK.on and 1 or (SCNP_PK.gg and 2 or 0), SCNP_SEL.on and 1 or 0, SCNP_GOD.on and (SCNP_GOD.fix and 2 or 1) or 0))
    p.ready = true
    log("player %d joined (%d/%d)", p.slot, p.slot, nplayers)
    status("player %d joined (%d of %d)", p.slot, p.slot, nplayers)
    set_overlay(C_INFO, "NETPLAY: %d of %d players here, waiting for the rest...", p.slot, nplayers)
  elseif t == "X" then
    if g >= 5 then
      -- a spectator quit (usually a different build that could not load our state): the
      -- players are not affected, the seat is simply free again
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
      if f <= (p.resync_base or -1) then mine = nil end            -- from before the last hand-off: says nothing now
      if mine and mine ~= sum then
        -- drifted (user 2026-10-03: a web spectator saw other goals than the match): hand him the running game again,
        -- like a newcomer - at most every 10 s and 6 times a match, so one that can never agree does not cost forever
        p.resyncs = p.resyncs or 0
        if phase == "play" and not p.join_at and p.handed == gen and p.resyncs < 6 and frame - (p.resync_at or -100000) >= 600 then
          p.resyncs = p.resyncs + 1; p.resync_at = frame; p.force = true; p.agree_logged = nil
          p.join_at = frame + cfg.delay + 3
          log("spectator %d drifted from us at frame %d (host %08x, spectator %08x) - sending it the game again (%d)", p.slot, f, mine, sum, p.resyncs)
        elseif not p.drift_logged then p.drift_logged = true; log("spectator %d drifted from us at frame %d (host %08x, spectator %08x)", p.slot, f, mine, sum) end
      end
      if mine and mine == sum and not p.agree_logged then p.agree_logged = true; log("spectator %d in step with us (checksum agrees at frame %d)", p.slot, f) end
    end
    return
  elseif t == "I" then
    local f, m = string.unpack("<I4B", payload)
    if SCNP_PVE.late[p.slot] and not SCNP_PVE.live[p.slot] then
      -- he plays only frames already sent; once he is within 8 of them, the host waits for him from the next one
      if f + 8 < last_broadcast then return end
      SCNP_PVE.live[p.slot] = last_broadcast + 1
      log("PvE: %dP is in step from frame %d", p.slot, last_broadcast + 1)
      if f <= last_broadcast then return end
    end
    if f <= last_broadcast then return end            -- the delay went down: this frame has gone out already
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
    -- the host's pitch (field), right after its handshake: every screen must draw the same one
    local st, pk, sel, god = payload:byte(1, 4)
    if st and st <= 7 and st ~= scnp_stage then scnp_stage = st; scnp_install_stage_tap() end
    if pk then SCNP_PK.on = (pk == 1); SCNP_PK.gg = (pk == 2) end          -- the host decides whether a level match goes to penalties
    if sel then scnp_sel_apply(sel == 1) end        -- and whether the country select is the versus one (protocol 16)
    if god then scnp_god_apply(god >= 1, god >= 2) end        -- and whether 1P may pick GOD (PvE, protocol 18)
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
    bgm_rand = (r and r ~= 0) and r or nil          -- the match's random tune, if it has one yet (else worked out here, at the same frame)
    if not is_spec then SCNP_PVE.catchup = true end                  -- a PvE newcomer: run until caught up
    set_overlay(C_INFO, "NETPLAY: spectator mode - joining the match in progress...")
    log("joining mid-match: state will be from frame %d", spec_base)
  elseif t == "S" then
    if SCNP_SPEC_SKIP and is_spec and phase == "play" then SCNP_SPEC_SKIP = nil; return end
    gen = g
    if not spec_base then agg = {} end
    pending_state = payload
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
    for s = 5, 8 do if peers[s] and peers[s].ready then specs = specs + 1 end end
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
  send_to(p, "H" .. string.char(0, VERSION, 0, cfg.slot, 0, 0) .. mame_bytes())
  phase = "handshake"
  hs_wait = now_ms()
  set_overlay(C_INFO, "NETPLAY: connected, waiting for the host's reply...")
  log("connected to %s:%d, handshake sent", cfg.addr, cfg.port)
end

local SPEC_STATE = "np_specjoin"
local SPEC_SAVE_LAG = tonumber(os.getenv("SCNP_SPEC_LAG") or "1")
SCNP_SPEC_POKE = tonumber(os.getenv("SCNP_SPEC_POKE") or "")          -- test only: a spectator drifts on purpose there
local spec_join = nil
local function spec_join_step()
  if spec_join then
    local data, info = read_state_file(spec_join.name)
    if data then
      local p = spec_join.p
      -- + the match's random tune (16); its top bit set when it puts a drifted spectator back in step (2026-10-03 - the
      -- tunes are all under 0x80, and J keeps its length, so older peers read it as before)
      send_to(p, "J" .. string.char(gen) .. u32le(spec_join.at) .. string.char((bgm_rand or 0) | (p.force and 0x80 or 0)))
      p.force = nil; p.resync_base = spec_join.at
      send_to(p, "S" .. string.char(gen) .. u32le(#data) .. data)
      log("spectator %d: sent state of frame %d (%d bytes)", p.slot, spec_join.at, #data)
      p.join_at = nil; p.handed = gen
      spec_join = nil
    elseif os.time() - spec_join.t > 5 then
      log("spectator %d: could not read the hand-off state (%s), giving up", spec_join.p.slot, tostring(info))
      spec_join.p.join_at = nil
      spec_join = nil
    end
    return
  end
  for slot = 2, 8 do
    local p = peers[slot]
    if p and p.join_at and frame >= p.join_at and (slot >= 5 or SCNP_PVE.late[slot]) then
      -- a new file for every hand-off: with one name, the file of the previous hand-off was already there and
      -- went out before the new save had been written - every newcomer after the first started from an old state
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
  if is_replay and rp_phase ~= "play" then
    if rp_phase == "boot" then
      if frame < 90 then frame = frame + 1; return end     -- let the machine settle
      local path = pct_decode_path(cfg.replay or "")
      local r, err = replay_read(path)
      if not r then lose("replay: %s", tostring(err)); return end
      rp = r; rp_meta = r.meta
      if r.meta:match('"swap":1') then scnp_swap = true; GAME_PLAYER = { 2, 1, 3, 4 } end
      if r.meta:match('"type":"2v2"') then is_teams = true end
      local map = r.meta:match('"map":"(%d%d%d%d)"')
      if map then
        -- protocol 15 on: the recording says which seat played which board player
        GAME_PLAYER = { tonumber(map:sub(1, 1)), tonumber(map:sub(2, 2)), tonumber(map:sub(3, 3)), tonumber(map:sub(4, 4)) }
      elseif is_teams then
        -- before it a 2v2 played seats 1+2 against 3+4 as the game's 1P+3P and 2P+4P (and never swapped sides)
        scnp_swap = false; GAME_PLAYER = { 1, 3, 2, 4 }
      end
      if r.meta:match('"type":"pve"') and SCNP_G.pm then SCNP_PVE.on = true end
      SCNP_FREE = r.meta:match('"free":1') ~= nil
      SCNP_PACE = r.meta:match('"pace":2') ~= nil          -- recorded with the board running a stretched clock
      clock_run = not r.meta:match('"clock":"stop"')      -- recordings before netplay 10 ran the clock through stoppages
      nplayers = tonumber(r.meta:match('"players":(%d+)')) or 2
      cfg.delay = tonumber(r.meta:match('"delay":(%d+)')) or cfg.delay
      -- the input delay over the match, shown under the clock (user 2026-10-10 "리플레이에도 딜레이정보 ... 우측하단 게임시계 밑에"):
      -- "dd" lists the host's changes as old>new@frame; "delay" is the one it ended on
      SCNP_RPD = { at = {}, d = {} }
      for od, nd, at in (r.meta:match('"dd":"([^"]*)"') or ""):gmatch("(%d+)>(%d+)@(%d+)") do
        if not SCNP_RPD.d0 then SCNP_RPD.d0 = tonumber(od) end
        SCNP_RPD.at[#SCNP_RPD.at + 1] = tonumber(at); SCNP_RPD.d[#SCNP_RPD.d + 1] = tonumber(nd)
      end
      SCNP_RPD.d0 = SCNP_RPD.d0 or cfg.delay
      cfg.time = r.meta:match('"time":(%d+)') or cfg.time
      scnp_stage = tonumber(r.meta:match('"stage":(%d+)') or "0") or 0; scnp_install_stage_tap()
      SCNP_PK.on = r.meta:match('"pk":1') ~= nil
      SCNP_PK.gg = r.meta:match('"pk":2') ~= nil
      scnp_sel_apply(r.meta:match('"sel":1') ~= nil)     -- recorded with the versus country select (protocol 16)
      do local b = r.meta:match('"ball":"(%a+)"'); if b then SCNP_PAL.BALLNAME = b; SCNP_PAL.BALL = SCNP_PAL.BALLS[b] end end   -- the match's own ball (2026-10-08)
      scnp_god_apply(r.meta:match('"god":[12]') ~= nil, r.meta:match('"god":2') ~= nil)     -- recorded in a PvE room that let 1P pick GOD (protocol 18)
      SCNP_DEVR.play = {}; SCNP_DEVR.pi = 1              -- each seat's stick / keyboard over the match (2.0.8 on)
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
      -- one state of our own, just to read its header: if the signatures differ the load would fail
      -- inside MAME with a message nobody can act on
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
  -- In the browser a wait must not spin: the WebSocket's data only arrives once this script has returned. So
  -- before a frame starts, a missing input for the frame after it pauses the machine and hands the turn back;
  -- frame_done keeps coming while paused (the screen is still drawn), and the machine goes on once it is here.
  -- (What the frame will need was sent at least delay - 1 frames ago, so with delay >= 2 it can be waited for here.)
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
    -- the browser's main loop starts its clock afresh after every such pause, so each wait was time lost for good
    -- and on a phone the waits added up to a match 40% slow for both sides (2026-09-27). Keep the game on the wall
    -- clock instead: behind it by more than a frame and a half, run unthrottled (a frame per main-loop call) until
    -- it has caught up; more than half a second behind, start the clock over rather than race
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
  if is_host then spec_join_step() end

  frame = frame + 1
  scnp_stage_palette()
  scnp_live_step()
  -- a shoot-out runs on its own schedule: the routine may set the clock, which the gate below
  -- would take for a new match; when it ends, the result and the replay go out from here
  scnp_gg_step()
  if SCNP_PK.state == "run" and scnp_pk_step() then
    scnp_pk_finish()
    if is_host and nplayers >= 2 and not result_written then scnp_write_result() end
    if not rec_written then rec_save(true) end
  end
  if clock_start then
   if clock_run then
    local due = math.max(0, clock_u0 - math.floor((frame - clock_start) / clock_boundary))
    -- during a stoppage the game runs no tick of its own, so the clock is moved here instead -
    -- but never onto the last unit: that step has to be the game's, or TIME UP never happens
    local floor_unit = (due == 0) and 1 or due
    if mem:read_u16(CLOCK_ADDR) > floor_unit then
      clock_ours = true; mem:write_u16(CLOCK_ADDR, floor_unit); clock_ours = false
      if floor_unit <= BEEP_RED then beep_want = beep_want + 1 end      -- the game did not tick, so it did not beep
    end
   end
    -- full time: a level match in a series goes to penalties first; the result and the replay wait for them
    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state == nil and nplayers >= 2 and not SCNP_PVE.on then scnp_pk_decide() end
    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run" and is_host and nplayers >= 2 and not result_written and not SCNP_PVE.on then   -- solo vs the CPU (and PvE) is not a record
      scnp_write_result()
    end
    if mem:read_u16(CLOCK_ADDR) == 0 and SCNP_PK.state ~= "run" and not rec_written and not SCNP_PVE.on then rec_save(true) end   -- PvE plays on: saved at the end
  end
  local nxt = frame + 1
  local target = frame + cfg.delay
  local mask = (is_spec or is_replay) and 0 or read_local_input()

  if is_replay then
    -- the next input frame comes from the file; a segment boundary means "load that state first"
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
      for s = 5, 8 do if peers[s] and peers[s].ready then nspec = nspec + 1 end end
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
  if SCNP_RELOAD and mem:read_u8(CLOCK_ADDR + 2) ~= SCNP_RELOAD then mem:write_u8(CLOCK_ADDR + 2, SCNP_RELOAD) end   -- the clock's pace
  if SCNP_FREE then                                                     -- free play: never short of credits
    local cr = mem:read_u8(CREDITS_ADDR)
    if cr <= 3 then mem:write_u8(CREDITS_ADDR, 9); SCNP_FREE_ADD = SCNP_FREE_ADD + 9 - cr end
  end
  if SCNP_PVE.on then for s = 2, 4 do if a[s] == 0xff then scnp_pve_drop(s) end end end
  for s = 1, 4 do apply_input(s, (SCNP_PVE.on and s >= 2 and a[s] == 0xff) and 0 or a[s]) end
  agg[nxt] = nil
  if not is_replay and not is_spec then rec_inputs[#rec_inputs + 1] = { a[1], a[2], a[3], a[4] }; scnp_devr_rec() end
  -- a spectator keeps its last 3 s of inputs: a resync hands it a state from a frame it may already have run past
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

-- Formation preview (user, 2026-09-25): on PLAYER TEAM SELECT the face under a player's cursor shows that
-- country's formation - the left half of the pitch on the game's own "DEFENSS SYSTEM" screen, cut from it (the
-- same on both sets). Drawing only: nothing reaches the game, so the lockstep is untouched.
-- sel = the countries already picked (one bit each: 0 England .. 7 Korea); sel+2 = the phase (2 while choosing);
-- sel+4 / sel+6 = 1P's / 2P's cursor (the same bits; it blinks while a picked face flashes).
SCNP_FORM = { sel = ({ cupsoc = 0x109b3b, cupsocs2 = 0x109c73 })[SCNP_GAME], tex = {}, png = {
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA7UlEQVR42tVUyw6CMBAcF87GxjtpuBMJ/QM/3D8ASbgjelcb71APQCRQ1gdyoGmatJPp7s5sdqXMbWu0sO1zeCWwi4ALD/PsRHJwHLFs9S61hcJuDIAaZXKI3ukqo8Vxrtjdi29075xaGMlZDM3LtIYrG5r4TlAQAFAxRMsIcOTo51kntjdAq/BzzSntv19azfe4A+uTsPo9b6/hIAXw2GnG76bKzvK+iD0cEI0So+zgBVeWhnESoGwMtdGjvMwkk5rvhKCYl0UZPaPm3db9s9/18BiHfUC0tVn8FpulzlTeUFIJ/3lUTErN+539BPB8W/O96k/2AAAAAElFTkSuQmCC",   -- England
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABCElEQVR42tWUzW7DIAzH/3M4T0W9R5R7pSi8wR68b0BWqXea9b4l6j3JDnQKA+Z2SydtKALJv/gL2zyY6W099TL3vVSvBHYRcOIxr90oDtua1TbXQvurWHQ8dgBIOcgIeIkwHeQz43u1JDR/6KmPgJcszNuSurWg7jjvV427Ye/xmKONLrYtAQC1KR1qoFCfjOvNvB8C32WiPFa3twPtY/np486f0AGPx3y9f7lTdw7AeRMDnz2FWQar/Ibv9IG43IRIc/X7dtYeMw1TNMBwKWjObe2Gg2JC00UFYSnu7bDnhUkG4I7jH2Z873oLy/4jNCCn/sv5lqt/+qaS5bFpeON1uyi08ufa741CV+qsOX50AAAAAElFTkSuQmCC",   -- Germany
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABDUlEQVR42r1Uyw6CMBAcl56NjXcCvZsQ+gd+uH8Amniv6F0l3gEPxVBprQ+QpmnSTna3s7O7M9lclk3JXfuYnAneRcDJD/ut88gHZ2l3UQcLlu++NgBm5kU05ajO38XOAJAjMwocAJNNybdT8LZzMJQYefU2BdV6m6p7nKtqp+HaheYiWBUEAFTYaJUCQfTkXMTduTdih5ZxnXyec9r130+PnK9xBeYH7tT7r7VG2CgAt9jSO+6sW5bGCr+IbQ+INhPM5qrPVWddOwomyIGqFdQVNlXVPvJ8TQQJWEb92ja7nEmr5SfosTH01sPjNSwA7uLW9jdfTDRTNdcRCznzwzLv1/az87QYxDv83foOWL5W3C9elzMAAAAASUVORK5CYII=",   -- USA
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABCElEQVR42tWUzW7DIAzH/3M4T0W9R5R7pSi8wR68b0BWqXea9b4l6j3JDnQKA+Z2SydtKALJv/gL2zyY6W099TL3vVSvBHYRcOIxr90oDtua1TbXQvurWHQ8dgBIOcgIeIkwHeQz43u1JDR/6KmPgJcszNuSurWg7jjvV427Ye/xmKONLrYtAQC1KR1qoFCfjOvNvB8C32WiPFa3twPtY/np486f0AGPx3y9f7lTdw7AeRMDnz2FWQar/Ibv9IG43IRIc/X7dtYeMw1TNMBwKWjObe2Gg2JC00UFYSnu7bDnhUkG4I7jH2Z873oLy/4jNCCn/sv5lqt/+qaS5bFpeON1uyi08ufa741CV+qsOX50AAAAAElFTkSuQmCC",   -- Japan
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA+ElEQVR42tVUSw6CMBB9Fg5g456U7k0IvYEH9wYgCXtE9ioXAFxQpEIZ/LGg6WLal/m8ee1sVHPbNSW37UtwZSAXAwoapr1jQcFRSHqrudJWCrsRAKY7k4E/gdZ2VVPy01K5zYNsyoH9KzEm5gXNzv2VaRPBsypp4dqGxtLZ5wwAWD5GqxBwhA4ufYO9DwCpkdsbOdfB+z1nyfC+6Hp+wP1VY9Ne9q3hKPic3pqlsbwPco8HhO6EO8V433vXlgfjxEClBbWlDbMqFURp0gngRszOWLdFGYdF/9i/9W6HxzQsAd5xs+jNt2udqRENq5gOHuY/leZ97/0A2FNZ6l9WW50AAAAASUVORK5CYII=",   -- Italy
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAAA+ElEQVR42tVUzQ6CMAz+LDsbF+8EuRuJewMf3DdATbwP9K4S74KHgeIcRSVoXEjT8a3rz7d2oIrjuMik69tFBwK7CNjzMG+9ChhYxPPsttGQlk6qLbQOsKhvwiKz9G6Xt/mOAVBjZYQqMrnuyXfPiRHH9wOhOrElc7m+bAycO+HQm6YEAJS67b3AwbeR59mdb//JMI9eLwtt7P/76q0tcPoZY0vdal1mWVv+G76fB0RZiYeam542cpjIyjpveDCXVDQHoLENmNBCL4KIyc23kULVWv7Peow9I0JANudGcvSlmeqY593KEvOwWtX4ntg6YZ52ytv/3PoK+idXa8KylKMAAAAASUVORK5CYII=",   -- Brazil
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABAklEQVR42sVUyw6CMBAcF87GxjuB3k0I/QM/3D8ATbxX9K4S74CHFjHSFrU+GsKBYbs7Ozs7Ee1p3lbM9OzTI8F5CDi4YXd0EbvgPDMDcgcAJMZK84BDG8Dbyvvysdw5ANKdkWCPsGgrtv4Fb8X1k8TIqbewKK31tkfKeqPgxqxZsCgJAKg0xwex4XKeAMAl6XNHg3+a9Pm20Obx+6Hr+RJnYLpjRr2/OmuElbyxVIyH0Zrl3YleyD1cELoTZHP2tNe7sQxMXYb2AiS2saM0HqQIczI7W71DMRj9L3ns03qr5WGHOcA6bgZ/s9kfdqrqgecg525YFJZh0P7OSi/e0fvRV3wWU3s84A6IAAAAAElFTkSuQmCC",   -- Argentina
  "iVBORw0KGgoAAAANSUhEUgAAADsAAAA+BAMAAABnxn4zAAAAD1BMVEXn7+f/7wAAtTEApSEAAP/N+xfyAAABDUlEQVR42r1Uyw6CMBAcl56NjXcCvZsQ+gd+uH8Amniv6F0l3gEPxVBprQ+QpmnSTna3s7O7M9lclk3JXfuYnAneRcDJD/ut88gHZ2l3UQcLlu++NgBm5kU05ajO38XOAJAjMwocAJNNybdT8LZzMJQYefU2BdV6m6p7nKtqp+HaheYiWBUEAFTYaJUCQfTkXMTduTdih5ZxnXyec9r130+PnK9xBeYH7tT7r7VG2CgAt9jSO+6sW5bGCr+IbQ+INhPM5qrPVWddOwomyIGqFdQVNlXVPvJ8TQQJWEb92ja7nEmr5SfosTH01sPjNSwA7uLW9jdfTDRTNdcRCznzwzLv1/az87QYxDv83foOWL5W3C9elzMAAAAASUVORK5CYII=",   -- Korea
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
    -- (the bitmap is kept with its texture: the texture only points at it)
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
        -- the face cells: x 41 + 64 per column, y 41 / 137, 46 x 43 (the flag and name stay visible)
        local x0, y0 = 41 + 64 * (i % 4), (i < 4) and 41 or 137
        screen.container:draw_quad(tx, x0 / 320, y0 / 240, (x0 + 46) / 320, (y0 + 43) / 240)
      end
    end
  end
end

local function on_frame_done()
  step()
  -- web: while paused for an input, frame_done keeps coming but the screen is not redrawn, so whatever is drawn
  -- stays and piles up (the HUD's see-through black turned solid and flickered): draw it once per pause
  local W = SCNP_WAIT
  if W.on then if W.drawn then return end; W.drawn = true else W.drawn = false end
  if phase == "play" then qc_step(); SCNP_FORM.draw(); draw_hud(); qc_draw() else draw_overlay() end
end

-- SCNP_MODE=probe: the launcher wants the build id before any match has been played (it is
-- normally written at the first state exchange). Save one state, note its signature, quit.
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
-- web: the browser build calls the scripts every few ms between frames (its main loop is paced by the clock), so
-- the socket is read - and the host passes a complete set of inputs on - as soon as the data is there
if cfg.web then
  SCNP_WAIT.sub = emu.register_periodic(function()
    if phase == "play" and not is_replay then pump(); if is_host then try_broadcast() end end
  end)
end
postload_sub = emu.add_machine_post_load_notifier(on_post_load)
stop_sub     = emu.add_machine_stop_notifier(function()
  rec_save(false)                       -- an unfinished match is still worth keeping
  restore_fields()
  log("stopped at frame %d: stalls %d, max stall %.1f ms, desyncs %d, resyncs %d, long stalls %d, stall ms %d, catch-ups %d",
      frame, stats.stalls, stats.max_stall_ms, stats.desync, stats.resyncs, stats.long_stalls, math.floor(stats.stall_total_ms), stats.catchups or 0)
  if logf then logf:close() end
end)

log("netplay.lua v%d loaded: game=%s mode=%s addr=%s port=%d delay=%d players=%s",
    VERSION, SCNP_GAME, cfg.mode, cfg.addr, cfg.port, cfg.delay, is_host and tostring(nplayers) or "?")
log("MAME %s", mame_str(MAME_MINOR))
