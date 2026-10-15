-- Seibu Cup Soccer Online - 혼자놀기 while waiting for a ranked match (ranked_wait.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online)
-- SPDX-License-Identifier: GPL-3.0-or-later
local machine = manager.machine
local mem = machine.devices[":maincpu"].spaces["program"]
local SCNP_GAME = machine.system.name
local frame = 0
local FILE, ANSWER = os.getenv("RQW_FILE") or "", os.getenv("RQW_ANSWER") or ""
local KO = (os.getenv("RQW_LANG") or "ko") == "ko"
local function T(ko, en) return KO and ko or en end
local function env(name, default) local v = os.getenv(name); if v == nil or v == "" then return default end; return v end

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
SCNP_COMIC.on = os.getenv("RQW_COMIC") ~= "0"

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

local st = { kind = "", t = 0 }
local answered = nil
local function readstate()
  local f = io.open(FILE, "rb"); if not f then return end
  local l = f:read("*l") or ""; f:close()
  local w = {}
  for x in l:gmatch("%S+") do w[#w + 1] = x end
  local k = w[1] or ""
  if k == "WAIT" then st = { kind = "WAIT", secs = tonumber(w[2]) or 0, count = tonumber(w[3]) or 0 }
  elseif k == "FOUND" then
    local id = w[2]
    if st.kind ~= "FOUND" or st.id ~= id then answered = nil end
    st = { kind = "FOUND", id = id, left = tonumber(w[3]) or 0, rank = w[4] or "", opp = l:match("^FOUND %S+ %S+ %S+ (.+)$") or "?" }
  elseif k == "WAITOTHER" or k == "GO" then st = { kind = k }
  elseif k == "CHALLENGE" then if st.kind ~= "CHALLENGE" then st = { kind = k } end
  else st = { kind = "" } end
end
local function answer(what)
  if answered or ANSWER == "" or st.kind ~= "FOUND" then return end
  local f = io.open(ANSWER, "wb"); if not f then return end
  f:write(what .. " " .. st.id .. "\n"); f:close()
  answered = what
end
local inp = machine.input
local KY, KN = inp:code_from_token("KEYCODE_Y"), inp:code_from_token("KEYCODE_N")
local FAKEKEY = os.getenv("RQW_FAKEKEY")
local function mmss(s) s = math.max(0, math.floor(s)); return string.format("%d:%02d", s // 60, s % 60) end
local function range(s) return s < 10 and T("비슷한 실력", "similar level") or s < 30 and T("조금 넓게", "a little wider") or s < 60 and T("넓게", "wider") or T("누구와도", "anyone") end
local function box(scr, x0, y0, x1, y1, fill, line) scr:draw_box(x0, y0, x1, y1, line or fill, fill) end
local function center(scr, y, text, col) scr:draw_text("center", y, text, col or 0xffffffff, 0x00000000) end

local saved = false

local NOCONT = false
local NG = ({ cupsoc = { clock = 0x109d64, sl = 0x109d6f, sr = 0x109db7, tm = 0x109d6c },
              cupsocs2 = { clock = 0x109ef4, sl = 0x109eff, sr = 0x109f47, tm = 0x109efc } })[SCNP_GAME]
local nc = { on = false, endAt = nil }
local function nocontinue(scr, w)
  if not NOCONT or not NG then return end
  local c = mem:read_u16(NG.clock)
  if c > 5 then nc.on = true end
  if nc.on and c == 0 and not nc.endAt then
    nc.on = false
    local sl, sr = mem:read_u8(NG.sl), mem:read_u8(NG.sr)
    local left = (mem:read_u8(NG.tm) & 1) ~= 0 or (mem:read_u8(NG.tm + 0x48) & 1) == 0
    local mine, theirs = left and sl or sr, left and sr or sl
    if mine < theirs then nc.endAt = frame + 180 end
  end
  if nc.endAt then
    box(scr, w / 2 - 100, 92, w / 2 + 100, 122, 0xe0000000, 0xffff5050)
    center(scr, 98, "GAME OVER", 0xffff5050)
    center(scr, 110, T(math.max(1, (nc.endAt - frame + 59) // 60) .. "초 뒤 게임을 닫습니다", "Closing in " .. math.max(1, (nc.endAt - frame + 59) // 60) .. " s"), 0xffffffff)
    if frame >= nc.endAt then nc.endAt = nil; machine:exit() end
  end
end
RQW_SUB = emu.register_frame_done(function()
  frame = frame + 1
  local scr = machine.screens[":screen"]; if not scr then return end
  if SCNP_COMIC.on then scnp_comic_step(); scnp_comic_draw() end
  if frame % 10 == 0 then readstate() end
  if st.kind == "CHALLENGE" and not saved then saved = true; pcall(function() machine:save("arcade") end) end
  local w0 = scr.width or 320
  nocontinue(scr, w0)
  local w = scr.width or 320
  if st.kind == "WAIT" then
    local t = T("랭크전 상대 찾는 중 ", "Looking for a ranked match ") .. mmss(st.secs) .. " · " .. range(st.secs) .. (st.count > 1 and T(" · 대기 " .. st.count .. "명", " · " .. st.count .. " searching") or "")
    box(scr, w / 2 - 118, 1, w / 2 + 118, 11, 0xc04a1596, 0xffb48cff)
    center(scr, 2, t)
  elseif st.kind == "FOUND" then
    if inp:code_pressed(KY) or FAKEKEY == "Y" then answer("ACCEPT") elseif inp:code_pressed(KN) or FAKEKEY == "N" then answer("DECLINE") end
    local blink = (frame // 15) % 2 == 0
    box(scr, w / 2 - 110, 60, w / 2 + 110, 130, 0xe0140a28, blink and 0xffffd600 or 0xffb48cff)
    center(scr, 68, T("랭크전 상대를 찾았습니다!", "Ranked match found!"), 0xffffd600)

    if st.opp == "?" then center(scr, 84, T("상대는 둘 다 수락하면 보입니다", "Who it is shows once you both accept"))
    else center(scr, 84, T("상대: ", "Opponent: ") .. st.opp .. (st.rank ~= "" and st.rank ~= "-" and " (" .. st.rank .. ")" or "")) end
    if answered == "ACCEPT" then center(scr, 102, T("수락했습니다 - 상대를 기다리는 중", "Accepted - waiting for the opponent"), 0xff9cf0a8)
    elseif answered == "DECLINE" then center(scr, 102, T("거절했습니다", "Declined"), 0xffff9c9c)
    else center(scr, 102, T("Y 수락    N 거절", "Y accept    N decline"), 0xffffffff) end
    center(scr, 116, T(st.left .. "초 남음", st.left .. " s left"), 0xffc8c8c8)
  elseif st.kind == "WAITOTHER" then
    box(scr, w / 2 - 110, 70, w / 2 + 110, 100, 0xe0140a28, 0xffb48cff)
    center(scr, 80, T("상대의 수락을 기다리는 중...", "Waiting for the opponent..."), 0xffffffff)
  elseif st.kind == "CHALLENGE" then

    local blink = (frame // 10) % 2 == 0
    box(scr, 0, 76, w, 136, 0xe0000000, blink and 0xffff3030 or 0xffffd600)
    center(scr, 90, T("도전자가 나타났습니다!", "Here comes a new challenger!"), blink and 0xffffd600 or 0xffff5050)
    center(scr, 110, T("온라인 대전이 곧 시작됩니다. 지금 게임은 저장되고, 대전 뒤에 이어서 합니다", "An online match starts now - this game is saved and goes on after it"), 0xffffffff)
  elseif st.kind == "GO" then
    box(scr, w / 2 - 110, 70, w / 2 + 110, 100, 0xe0140a28, 0xffffd600)
    center(scr, 80, T("랭크전 시작! 이 게임은 곧 닫힙니다", "Ranked match on! This game closes now"), 0xffffd600)
  end
end)
