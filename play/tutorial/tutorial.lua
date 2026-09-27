-- Seibu Cup Soccer Online - tutorial (tutorial.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online)
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
-- Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public License for
-- details (the package's bin\legal\GPL-3.0.txt, the site's legal/GPL-3.0.txt, or <https://www.gnu.org/licenses/>).
-- Additional terms under section 7 of the GPL: a modified version must be marked as changed from the original,
-- and it may not use the name "Seibu Cup Soccer Online" (세이부 컵 사커 온라인).

-- Seibu Cup Soccer tutorial (standalone: plain MAME, no netplay, its own cfg/nvram and the scenes in netplay\tutorial\scenes).
-- Each lesson loads a saved scene (cupsocs2), pauses on it with the explanation, and once the player presses shoot it runs
-- and judges the move from RAM. Backspace = try the lesson again, Enter = next lesson, Esc = quit (MAME's own key).
-- env: TUT_LANG (ko|en), TUT_LESSON (1-based lesson to start at), TUT_LOG (a log file),
--      TUT_TEST ("<lesson id>:<from:dur:mask;...>") plays one lesson by itself with scripted P1 input, logs RESULT, exits.
local machine = manager.machine
local mem = machine.devices[":maincpu"].spaces["program"]
local screen = machine.screens[":screen"]
local input = machine.input

local LANG = (os.getenv("TUT_LANG") or "ko"):sub(1, 2) == "ko" and "ko" or "en"   -- Korean, else English
local logf = os.getenv("TUT_LOG") and io.open(os.getenv("TUT_LOG"), "w")
local function log(fmt, ...) if logf then logf:write(string.format(fmt, ...), "\n"); logf:flush() end end

-- RAM (cupsocs2): ball x/y/z 16.16 at 0x113820/24/28; 22 men 0xdc apart from 0x111e54 (0-10 P1's side, 10 = keeper,
-- 11-21 the CPU), man +04/+08/+0c = x/y/z, +0x8c = the action handler; the P1-controlled man pointer at 0x10a234;
-- score bytes 0x109eff (left = P1) / 0x109f47. Right goal line y 1617 (the net stops the ball by ~1660), left y 400.
local MEN, STRIDE, CTL, SCORE_L, SCORE_R = 0x111e54, 0xdc, 0x10a234, 0x109eff, 0x109f47
local FALL = { [0x9cc6] = true, [0x9ce6] = true, [0x9d06] = true, [0x9dc6] = true }
-- the keeper holding the ball (catch, then the throw or kick out)
local KEEP_HOLD = { [0xc81e] = true, [0xc880] = true, [0xbf38] = true, [0xbf80] = true }
local PASS = { [0xb6f2] = true, [0xb7ae] = true, [0xb7f6] = true }
local A = { slide = 0xbe5c, jump = 0xa606, fly = 0xa73e, shot = 0xb858, trap = 0xa20c, trapped = 0xa286,
            header = 0x9ede, overhead = 0x9f9a }

local function fx(a) return mem:read_i32(a) / 65536 end
local W = {}   -- the world this frame
local function read_world()
  W.bx, W.by, W.bz = fx(0x113820), fx(0x113824), fx(0x113828)
  W.men = W.men or {}
  for i = 0, 21 do
    local a = MEN + i * STRIDE
    local m = W.men[i] or {}
    m.x, m.y, m.z, m.act = fx(a + 4), fx(a + 8), fx(a + 12), mem:read_u16(a + 0x8c)
    W.men[i] = m
  end
  local c = mem:read_u32(CTL) & 0xffffff
  W.ctl = (c ~= 0) and (c - MEN) // STRIDE or -1
  W.sl, W.sr = mem:read_u8(SCORE_L), mem:read_u8(SCORE_R)
  -- the man on the ball: nearest within 14 while the ball is low (the game keeps no owner pointer)
  W.owner = nil
  if W.bz < 8 then
    local bd = 14
    for i = 0, 21 do
      local m = W.men[i]
      local d = math.max(math.abs(m.x - W.bx), math.abs(m.y - W.by))
      if d < bd then W.owner, bd = i, d end
    end
  end
end
local function p1(i) return i and i <= 10 end
local function cpu(i) return i and i >= 11 end
local function any_act(from, to, set) for i = from, to do if set[W.men[i].act] then return i end end end
local function p1_did(code) for i = 0, 10 do if W.men[i].act == code then return i end end end

-- ---------------------------------------------------------------- text
local T = {
  start   = { ko = "슛 버튼: 시작    Backspace: 다시    Enter: 다음 레슨", en = "Shoot: start    Backspace: retry    Enter: next lesson" },
  again   = { ko = "다시 해 봐요! 슛 버튼을 누르면 시작합니다.", en = "Try again! Press shoot to start." },
  info    = { ko = "슛 버튼: 다음 레슨    Backspace: 처음부터", en = "Shoot: next lesson    Backspace: back to the start" },
  keys    = { ko = "슛 버튼: 레슨 시작    Tab: 키 설정    Esc: 끝내기", en = "Shoot: start the lessons    Tab: set keys    Esc: quit" },
  lesson  = { ko = "레슨 %d/%d", en = "Lesson %d/%d" },
  ok      = { ko = "성공!", en = "Nice!" },
  goal    = { ko = "골!!", en = "GOAL!!" },
  save    = { ko = "선방!", en = "Saved!" },
  ready   = { ko = "준비...", en = "Ready..." },
  now     = { ko = "지금!", en = "NOW!" },
  done1   = { ko = "튜토리얼 끝! 이제 대전에서 실력을 보여 주세요.", en = "Tutorial complete! Show them in a real match." },
  done2   = { ko = "슛 버튼: 처음부터 다시    Esc: 끝내기", en = "Shoot: start over    Esc: quit" },
  lost    = { ko = "상대에게 공을 뺏겼어요.", en = "The CPU took the ball." },
  timeup  = { ko = "시간이 지났어요.", en = "Out of time." },
  lofted  = { ko = "공이 떴어요. 패스 버튼을 짧게 톡 누르세요.", en = "It went up - just tap pass." },
  flat    = { ko = "땅볼이 됐어요. 패스 버튼을 더 길게 꾹!", en = "That stayed low - hold pass longer." },
  cut     = { ko = "상대가 가로챘어요.", en = "The CPU cut it out." },
  wide    = { ko = "아깝다! 골대를 벗어났어요.", en = "Wide of the goal!" },
  kept    = { ko = "키퍼가 막았어요!", en = "The keeper got it!" },
  missed  = { ko = "빗나갔어요. 상대 발밑을 노리세요.", en = "Missed - aim at his feet." },
  button  = { ko = "이번엔 버튼 없이 몸으로 부딪혀 보세요.", en = "No buttons this time - just run into him." },
  nofly   = { ko = "늦었어요. 점프하면 '지금!'이 뜰 때 바로 슛!", en = "Too late - shoot as NOW! shows during the jump." },
  slideno = { ko = "슬라이딩이 됐어요. 패스를 먼저 누르고 한 박자 뒤에 슛!", en = "That was a slide - pass first, shoot a beat later." },
  early   = { ko = "조금 빨랐어요. '지금!'에 맞춰 누르세요.", en = "A little early - press on NOW!" },
  late    = { ko = "가슴으로 받아 버렸어요. 공이 닿는 순간 누르세요.", en = "He chested it - press as the ball arrives." },
  concede = { ko = "실점! 키퍼를 골문 앞에 두세요.", en = "Conceded! Keep the keeper in front of goal." },
}
local function tr(k) return T[k][LANG] end

-- ---------------------------------------------------------------- lessons
-- scene: the saved state; limit: frames before "out of time"; start(L) sets up per-try state; judge(L) returns
-- nil (still going), "ok"/"goal"/"save" or a T key for the failure; cue(L) may return "ready"/"now"
local binding   -- the name of a P1 control's binding, defined with the controls below
local LESSONS = {
  { id = "controls", scene = "kickoff", info = true, keys = true,
    title = { ko = "조작 방법", en = "Controls" },
    text = function()
      local shoot, pass = binding(5), binding(6)
      return ({
        ko = { "이동: 방향키    슛: 왼쪽 Ctrl    패스: 왼쪽 Alt  (이 기본 키는 항상 함께 동작)",
               "지금 설정 - 슛: " .. shoot .. "    패스: " .. pass,
               "패드나 다른 키를 쓰려면 Tab -> Input Settings -> Input Assignments (this system)",
               "-> P1 Shoot / P1 Pass 등을 고른 뒤 쓸 버튼을 누르세요. Tab으로 닫으면 바로 적용.",
               "여기서 바꾼 키는 대전(넷플레이)에도 그대로 쓰입니다." },
        en = { "Move: arrow keys    Shoot: Left Ctrl    Pass: Left Alt  (these always work too)",
               "Set now - shoot: " .. shoot .. "    pass: " .. pass,
               "For a pad or other keys: Tab -> Input Settings -> Input Assignments (this system)",
               "-> pick P1 Shoot / P1 Pass etc. and press the button to use. Tab closes the menu.",
               "Keys set here are used in netplay matches too." },
      })[LANG]
    end },
  { id = "move", scene = "kickoff", limit = 600,
    title = { ko = "이동", en = "Moving" },
    text = { ko = { "방향키로 선수를 움직입니다.", "공에 닿아 있으면 저절로 드리블해요.", "오른쪽이 상대 골대입니다." },
             en = { "Move your player with the arrow keys.", "Touch the ball and he dribbles by himself.", "The CPU's goal is on the right." } },
    goal = { ko = "공을 몰고 오른쪽으로 달려 보세요.", en = "Run to the right with the ball." },
    start = function(L) L.me = W.ctl; L.y0 = W.men[W.ctl].y end,
    judge = function(L)
      if cpu(W.owner) then return "lost" end
      if W.owner == W.ctl and W.men[W.ctl].y - L.y0 > 150 then return "ok" end
    end },
  { id = "short", scene = "kickoff", limit = 400,
    title = { ko = "짧은 패스", en = "Short pass" },
    text = { ko = { "공을 가졌을 때 패스 버튼(Alt)을 톡 누르면", "가까운 동료에게 땅볼 패스가 갑니다.", "방향키로 보낼 쪽을 고를 수 있어요." },
             en = { "With the ball, tap pass (Alt) for a ground", "pass to the nearest team-mate.", "The arrow keys choose the direction." } },
    goal = { ko = "패스 버튼을 짧게 톡!", en = "Tap pass!" },
    start = function(L) L.me, L.top, L.kicked = W.ctl, 0, false end,
    judge = function(L)
      if PASS[W.men[L.me].act] then L.kicked = true end
      if L.kicked then L.top = math.max(L.top, W.bz) end
      if L.kicked and L.top >= 20 then return "lofted" end
      if cpu(W.owner) then return L.kicked and "cut" or "lost" end
      if L.kicked and p1(W.owner) and W.owner ~= L.me then return "ok" end
    end },
  { id = "long", scene = "kickoff", limit = 400,
    title = { ko = "롱패스", en = "Long pass" },
    text = { ko = { "패스 버튼을 꾹 누르고 있으면(약 0.3초)", "공이 높이 떠서 멀리 있는 동료에게 갑니다." },
             en = { "Hold pass (about 0.3 s) and the ball flies", "high to a team-mate further away." } },
    goal = { ko = "패스 버튼을 꾹 눌러 띄워 보내세요.", en = "Hold pass to loft it." },
    start = function(L) L.me, L.top, L.kicked = W.ctl, 0, false end,
    judge = function(L)
      if PASS[W.men[L.me].act] then L.kicked = true end
      if L.kicked then L.top = math.max(L.top, W.bz) end
      if cpu(W.owner) then return L.kicked and "cut" or "lost" end
      local got = p1_did(A.trap) or p1_did(A.trapped) or (p1(W.owner) and W.owner ~= L.me and W.owner)
      if L.kicked and got and got ~= L.me then return L.top > 60 and "ok" or "flat" end
    end },
  { id = "shot", scene = "shot", limit = 500,
    title = { ko = "슛", en = "Shooting" },
    text = { ko = { "슛 버튼(Ctrl)으로 슛! 가장 빠른 공이 나갑니다.", "누르는 순간의 방향키로 방향이 바뀝니다.", "키퍼가 한쪽으로 치우쳐 있어요. → 를 누른 채 골문 한가운데로 곧장 쏴 보세요." },
             en = { "Shoot (Ctrl) fires the fastest ball.", "The arrow held as you press aims it.", "The keeper is off to one side: hold right and shoot straight at the middle." } },
    goal = { ko = "골을 넣어 보세요.", en = "Score a goal." },
    -- the CPU keeper saves nearly every shot from this scene (0 of 12 in tests; a lower difficulty changes nothing -
    -- the board sets the CPU level before kick-off), so he starts 90 to one side: every straight shot goes in
    -- (dribbling 0-24 frames first), the diagonal ones still go wide
    setup = function()
      local a = MEN + 21 * STRIDE
      mem:write_i32(a + 4, mem:read_i32(a + 4) + 90 * 65536)
    end,
    start = function(L) L.cross, L.sl = nil, W.sl end,
    judge = function(L)
      if W.sl > L.sl then return "goal" end
      if not L.cross and W.by >= 1617 then L.cross = L.t end
      if L.cross then
        if W.by > 1668 then return "wide" end
        if L.t - L.cross >= 30 then return "goal" end   -- still in the net
        return
      end
      if cpu(W.owner) then return W.owner == 21 and "kept" or "lost" end
    end },
  { id = "slide", scene = "defend", limit = 400,
    title = { ko = "슬라이딩 태클", en = "Sliding tackle" },
    text = { ko = { "공이 없을 때 슛 버튼 = 슬라이딩 태클.", "공을 가진 상대의 발밑으로 미끄러져 공을 뺏어요.", "빗나가면 한동안 못 일어나니 조심!" },
             en = { "Without the ball, shoot = sliding tackle.", "Slide into the carrier's feet to win the ball.", "Miss, and you're on the grass for a while!" } },
    goal = { ko = "공 가진 상대에게 다가가 슬라이딩!", en = "Close in on the carrier and slide!" },
    start = function(L) L.slid = nil end,
    judge = function(L)
      if not L.slid and p1_did(A.slide) then L.slid = L.t end
      if L.slid and (any_act(11, 21, FALL) or p1(W.owner)) then return "ok" end
      if L.slid and L.t - L.slid > 90 then return "missed" end
    end },
  { id = "charge", scene = "defend", limit = 400,
    title = { ko = "몸싸움", en = "Shoulder charge" },
    text = { ko = { "버튼을 누르지 않고 공을 가진 상대에게", "그대로 부딪혀도 상대가 비틀거리며 공을 놓칩니다." },
             en = { "Run into the carrier without pressing anything:", "he stumbles and loses the ball." } },
    goal = { ko = "버튼 없이 상대에게 부딪혀 보세요.", en = "Run into him - no buttons." },
    judge = function(L)
      if p1_did(A.slide) or p1_did(A.jump) then return "button" end
      if any_act(11, 21, FALL) then return "ok" end
    end },
  { id = "flying", scene = "defend", limit = 400,
    title = { ko = "날라차기", en = "Flying kick" },
    text = { ko = { "공이 없을 때 패스 버튼 = 점프.", "점프한 뒤 공중에서(한 박자 뒤) 슛 버튼을 누르면 날라차기!", "공을 가진 상대에게 맞히면 공을 빼앗을 수 있어요." },
             en = { "Without the ball, pass = jump.", "Press shoot in the air for a flying kick,", "and knock the ball off the carrier." } },
    goal = { ko = "패스로 점프 → '지금!'이 뜨면 슛!", en = "Pass to jump, then shoot on NOW!" },
    start = function(L) L.jump = nil end,
    -- shoot works from ~4 to ~24 frames after the jump starts (pressed together with pass it is a slide)
    cue = function(L) return L.jump and L.t - L.jump >= 2 and L.t - L.jump < 22 and "now" or nil end,
    judge = function(L)
      -- the kick itself is the lesson: it counts whether or not it wins the ball
      if p1_did(A.fly) then return "ok" end
      if not L.jump and p1_did(A.jump) then L.jump = L.t end
      if not L.jump and p1_did(A.slide) then return "slideno" end
      if L.jump and L.t - L.jump > 40 then return "nofly" end
    end },
  { id = "header", scene = "header", limit = 150,
    title = { ko = "헤딩", en = "Header" },
    text = { ko = { "동료의 롱패스가 날아옵니다.", "공이 몸에 닿는 순간 슛(또는 패스) 버튼을 누르면 헤딩!", "그냥 두면 가슴으로 받아요." },
             en = { "A team-mate's long ball is coming.", "Press shoot (or pass) as it reaches you: header!", "Do nothing and he just chests it." } },
    goal = { ko = "'지금!'이 뜨면 슛 버튼!", en = "Press shoot on NOW!" },
    cue = function(L) return (L.t >= 18 and L.t < 29) and "ready" or (L.t >= 29 and L.t < 40) and "now" or nil end,
    judge = function(L)
      if p1_did(A.header) or p1_did(A.overhead) then return "ok" end
      if p1_did(A.slide) or p1_did(A.jump) then return "early" end
      if p1_did(A.trapped) then return "late" end
    end },
  { id = "overhead", scene = "overhead", limit = 150,
    title = { ko = "오버헤드킥", en = "Overhead kick" },
    text = { ko = { "팀에서 단 한 명, 에이스 선수만 쓰는 특수기!", "헤딩과 같은 요령: 공중 볼이 닿는 순간 버튼.", "슛 = 낮고 강하게, 패스 = 띄워서." },
             en = { "Only one man per team - the ace - can do this.", "Same timing as a header: press as the ball arrives.", "Shoot = low and hard, pass = lofted." } },
    goal = { ko = "'지금!'이 뜨면 슛 버튼!", en = "Press shoot on NOW!" },
    cue = function(L) return (L.t >= 18 and L.t < 29) and "ready" or (L.t >= 29 and L.t < 40) and "now" or nil end,
    judge = function(L)
      if p1_did(A.overhead) or p1_did(A.header) then return "ok" end
      if p1_did(A.slide) or p1_did(A.jump) then return "early" end
      if p1_did(A.trapped) then return "late" end
    end },
  { id = "dynamite", scene = "kickoff", info = true,
    title = { ko = "다이너마이트 킥", en = "Dynamite Kick" },
    text = { ko = { "골을 넣은 뒤에 쓸 수 있는 필살 슛입니다.", "공을 몰고 달리면 화면 아래 게이지가 차오르고,", "꽉 차서 DYNAMITE KICK!이 뜨면 슛 버튼!", "게이지가 떠 있는 동안은 시계가 느리게 갑니다." },
             en = { "A super shot you earn after scoring.", "Dribble and the gauge at the bottom fills;", "when DYNAMITE KICK! shows, press shoot!", "The clock runs slower while the gauge is up." } } },
  { id = "keeper", scene = "keeper", limit = 420,
    title = { ko = "골키퍼", en = "Goalkeeper" },
    text = { ko = { "공이 우리 골대에 가까워지면 DANGER! 표시와 함께 키퍼를 조종합니다.", "키퍼가 너무 앞에 나와 있어요. 방향키(←)로 골라인 쪽으로 물러서거나,",
                    "슛이 오는 방향으로 방향키 + 슛 버튼 = 그쪽으로 다이빙!" },
             en = { "Near your goal (DANGER!) you control the keeper.", "He is too far out: step back to the line (left),",
                    "or arrow + shoot to dive that way as the shot comes." } },
    goal = { ko = "7초 동안 골을 지켜 내세요!", en = "Keep it out for 7 seconds!" },
    start = function(L) L.sr, L.frozen = W.sr, 0 end,
    judge = function(L)
      if W.sr > L.sr then return "concede" end
      local k = W.men[10].act
      if KEEP_HOLD[k] or W.by > 900 or (p1(W.owner) and W.owner ~= 10) then return "save" end
      -- the ball sitting in the net (behind the line, low, between the posts) for half a second
      if W.by <= 400 and W.bz < 40 and math.abs(W.bx - 1268) < 110 then L.frozen = L.frozen + 1 else L.frozen = 0 end
      if L.frozen >= 30 then return "concede" end
    end,
    timeout = "save" },
}

-- ---------------------------------------------------------------- flow
-- phase: "load" (waiting for the scene), "intro" (paused on the scene), "play", "result" (message, game running),
-- "done" (after the last lesson)
local cur = math.max(1, math.min(#LESSONS, tonumber(os.getenv("TUT_LESSON") or "1") or 1))
local phase, L, msg, msg_ok, msg_t, again = "load", nil, nil, false, 0, false
local test = os.getenv("TUT_TEST")
local test_id, test_script
if test then
  test_id, test_script = test:match("^(%w+):?(.*)$")
  for i, l in ipairs(LESSONS) do if l.id == test_id then cur = i end end
end
local script = {}
for a, d, m in (test_script or ""):gmatch("(%d+):(%d+):(%x+)") do script[#script + 1] = { tonumber(a), tonumber(d), tonumber(m, 16) } end

local fields = {}
for _, p in pairs(machine.ioport.ports) do
  for n, f in pairs(p.fields) do
    for b, want in ipairs({ "P1 Up", "P1 Down", "P1 Left", "P1 Right", "P1 Shoot", "P1 Pass" }) do if n == want then fields[b] = f end end
  end
end
-- controls: the player's own P1 bindings stay as they are (tutorial.cmd / the launcher copy netplay\cfg in, and Tab ->
-- Input changes them live); the stock keys are added on top by pressing the field from Lua (a field's Lua value is OR-ed
-- with its own binding), so nothing extra is ever written into the saved cfg. Key codes are looked up every frame: the
-- input devices come up a few frames after the script starts.
local STOCK = { "KEYCODE_UP", "KEYCODE_DOWN", "KEYCODE_LEFT", "KEYCODE_RIGHT", "KEYCODE_LCONTROL", "KEYCODE_LALT" }
local function key(token) return input:code_pressed(input:code_from_token(token)) end
local function own_pressed(b) return fields[b] and input:seq_pressed(fields[b]:input_seq("standard")) or false end
local function stock_keys()
  for b = 1, 6 do if fields[b] then fields[b]:set_value(key(STOCK[b]) and 1 or 0) end end
end
binding = function(b)   -- e.g. "Joy 1 Button 3" for the controls page
  return fields[b] and input:seq_name(fields[b]:input_seq("standard")) or "n/a"
end
local held = {}
local function pressed_once(name, down)   -- true on the frame a key goes down
  local was = held[name]; held[name] = down
  return down and not was
end

local function load_lesson(i)
  cur = i; L = { t = 0 }; phase = "load"; msg = nil
  machine:load(LESSONS[cur].scene)
  log("LOAD %s", LESSONS[cur].id)
end
local function start_play()
  L = { t = 0 }
  local les = LESSONS[cur]
  read_world()
  if les.start then les.start(L) end
  phase = "play"
  emu.unpause()
  log("START %s", les.id)
end
local function finish(res)
  local les = LESSONS[cur]
  msg_ok = (res == "ok" or res == "goal" or res == "save")
  msg, msg_t, phase = tr(res), 0, "result"
  log("RESULT %s %s %s t=%d", les.id, msg_ok and "ok" or "fail", res, L.t)
  if test and not os.getenv("TUT_TEST_STAY") then machine:exit() end
end

local hush = 0   -- frames left to keep MAME's "Loaded state ... not officially supported" pop-up cleared
__tut_post = emu.add_machine_post_load_notifier(function()
  hush = 10
  if phase == "load" then
    phase = "settle"; L = { t = 0 }
    if LESSONS[cur].setup then LESSONS[cur].setup() end   -- a lesson's own touch to its scene, every try
  end
end)

local function in_test_input(t)
  local m = 0
  for _, s in ipairs(script) do if t >= s[1] and t < s[1] + s[2] then m = m | s[3] end end
  for b = 1, 6 do if fields[b] then fields[b]:set_value((m >> (b - 1)) & 1) end end
end

-- ---------------------------------------------------------------- drawing
local SW, SH = screen.width, screen.height
local function text_w(s)
  local ok, w = pcall(function() return manager.ui:get_string_width(s) end)
  return ok and w * SW or #s * 4
end
local LINE = 10
do
  local ok, h = pcall(function() return manager.ui:get_line_height() end)
  if ok and h then LINE = math.max(8, math.floor(h * SH + 1.5)) end
end
local function box(x0, y0, x1, y1, fill, edge)
  screen:draw_box(x0, y0, x1, y1, edge or fill, fill)
end
local function centred(y, s, col)
  screen:draw_text(math.max(2, (SW - text_w(s)) / 2), y, s, col, 0)
end
local YEL, WHITE, GREY, GREEN, RED = 0xffffe28a, 0xfff4f4f4, 0xffb8c0b8, 0xff7dff9a, 0xffff8a8a

local function draw_panel(lines, foot, colour)
  local h = (#lines + 2) * LINE + 10
  local y0 = SH - h - 4
  box(4, y0, SW - 4, SH - 4, 0xd8000000, 0xffffe28a)
  local les = LESSONS[cur]
  -- the controls page is page 0; the lessons count from 1
  local head = les.keys and les.title[LANG] or (string.format(tr("lesson"), cur - 1, #LESSONS - 1) .. "  " .. les.title[LANG])
  screen:draw_text(10, y0 + 4, head, YEL, 0)
  for i, s in ipairs(lines) do screen:draw_text(10, y0 + 4 + i * LINE, s, colour or WHITE, 0) end
  screen:draw_text(10, y0 + 6 + (#lines + 1) * LINE, foot, GREY, 0)
end

local function draw()
  if phase == "done" then
    box(20, SH / 2 - 2 * LINE, SW - 20, SH / 2 + 2 * LINE, 0xe0000000, YEL)
    centred(SH / 2 - LINE - 2, tr("done1"), YEL)
    centred(SH / 2 + 2, tr("done2"), GREY)
    return
  end
  local les = LESSONS[cur]
  if phase == "intro" then
    local lines = {}
    for _, s in ipairs(type(les.text) == "function" and les.text() or les.text[LANG]) do lines[#lines + 1] = s end
    if les.goal then lines[#lines + 1] = "> " .. les.goal[LANG] end
    draw_panel(lines, les.keys and tr("keys") or les.info and tr("info") or (again and tr("again") or tr("start")))
  elseif phase == "play" then
    box(0, 0, SW, LINE + 4, 0xb0000000)
    screen:draw_text(4, 2, string.format(tr("lesson"), cur - 1, #LESSONS - 1) .. "  " .. les.title[LANG] .. "  -  " .. les.goal[LANG], YEL, 0)
    local c = les.cue and les.cue(L)
    if c then
      local w = text_w(tr(c)) + 16
      box((SW - w) / 2, SH * 0.3 - 3, (SW + w) / 2, SH * 0.3 + LINE + 2, c == "now" and 0xe0106020 or 0xc0000000, c == "now" and GREEN or WHITE)
      centred(SH * 0.3, tr(c), c == "now" and GREEN or WHITE)
    end
  elseif phase == "result" and msg then
    local w = text_w(msg) + 24
    box((SW - w) / 2, SH * 0.3 - 4, (SW + w) / 2, SH * 0.3 + LINE + 4, 0xd0000000, msg_ok and GREEN or RED)
    centred(SH * 0.3, msg, msg_ok and GREEN or RED)
  end
end

-- ---------------------------------------------------------------- per frame
local menu_quiet = 0
__tut_frame = emu.register_frame_done(function()
  if hush > 0 then hush = hush - 1; machine:popmessage() end
  local back = pressed_once("back", key("KEYCODE_BACKSPACE"))
  local enter = pressed_once("enter", key("KEYCODE_ENTER"))
  local shoot_down = own_pressed(5) or key("KEYCODE_LCONTROL")
  if not test then stock_keys() end
  local shoot = pressed_once("shoot", shoot_down)
  -- MAME's own menu (Tab: key settings) uses Enter, Backspace and the buttons being assigned: while it is open, and for
  -- a moment after it closes, none of them count for the tutorial (the edge state above keeps tracking, so a key still
  -- held as the menu closes does not fire either)
  local menu = false
  pcall(function() menu = manager.ui.menu_active end)
  if menu then menu_quiet = 20 elseif menu_quiet > 0 then menu_quiet = menu_quiet - 1 end
  if menu or menu_quiet > 0 then
    back, enter, shoot = false, false, false
    if L then L.armed = false end
  end
  if phase == "settle" then
    -- let one frame of the new scene reach the screen, then hold it for the explanation
    if machine.paused then return draw() end
    L.t = L.t + 1
    if L.t >= 1 then phase = "intro"; if not test then emu.pause() end end
  elseif phase == "intro" then
    -- a lesson starts when shoot is let go, so the press that starts it never reaches the game
    local les = LESSONS[cur]
    if not test and not menu and not machine.paused then emu.pause() end   -- closing the menu may resume the game
    L.shown = (L.shown or 0) + 1
    if shoot and L.shown > 60 then L.armed = true end
    if test then start_play()
    elseif enter then again = false; load_lesson(cur % #LESSONS + 1)
    elseif les.info and back then again = false; load_lesson(1)
    elseif L.armed and not shoot_down then
      if les.info then again = false; load_lesson(cur % #LESSONS + 1) else start_play() end
    end
  elseif phase == "play" then
    if machine.paused then return draw() end   -- the user paused MAME (P)
    local les = LESSONS[cur]
    L.t = L.t + 1
    if test then in_test_input(L.t) end
    read_world()
    local res = les.judge(L)
    if not res and L.t >= les.limit then res = les.timeout or "timeup" end
    if res then finish(res)
    elseif back then again = true; load_lesson(cur)
    elseif enter then again = false; load_lesson(cur % #LESSONS + 1) end
  elseif phase == "result" then
    msg_t = msg_t + 1
    if back then again = true; load_lesson(cur)
    elseif enter or msg_t >= (msg_ok and 150 or 110) then
      if msg_ok then
        again = false
        if cur == #LESSONS then phase = "done"; emu.pause() else load_lesson(cur + 1) end
      else again = true; load_lesson(cur) end
    end
  elseif phase == "done" then
    if shoot then emu.unpause(); again = false; load_lesson(1) end
  end
  draw()
end)

load_lesson(cur)
