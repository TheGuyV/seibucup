-- Seibu Cup Soccer Online - web start-up script (boot.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online)
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
-- Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public License for
-- details (the package's bin\legal\GPL-3.0.txt, the site's legal/GPL-3.0.txt, or <https://www.gnu.org/licenses/>).
-- Additional terms under section 7 of the GPL: a modified version must be marked as changed from the original,
-- and it may not use the name "Seibu Cup Soccer Online" (세이부 컵 사커 온라인).

-- 웹 런처의 시작 스크립트 (autoboot 는 하나뿐이라 여기서 이어 부른다)
--  1. 1P 슛/패스에 Z / X 를 더한다 (브라우저에서는 Alt 가 메뉴로 새기 쉬워서). 기본값(키 + 조이스틱 버튼)은 그대로 두고
--     덧붙이기만 하며, 사용자가 Tab 메뉴에서 직접 바꾼 칸(저장된 설정)은 건드리지 않는다.
--  2. WEB_TARGET 에 적힌 스크립트(netplay.lua / tutorial.lua / practice.lua)를 이어서 실행한다. 없으면 그냥 MAME (혼자 하기)
local input = manager.machine.input
local extra = { ["P1 Shoot"] = "KEYCODE_Z", ["P1 Pass"] = "KEYCODE_X" }
for tag, port in pairs(manager.machine.ioport.ports) do
  for name, field in pairs(port.fields) do
    if extra[name] then
      local now = input:seq_to_tokens(field:input_seq("standard"))
      local def = input:seq_to_tokens(field:default_input_seq("standard"))
      if now == def and not now:find(extra[name], 1, true) then
        field:set_input_seq("standard", input:seq_from_tokens(def .. " OR " .. extra[name]))
      end
    end
  end
end

-- ?fps=1 (WEB_FPS): MAME 의 속도 표시(F11 과 같은 것)를 켠다 - 느린 기기에서 몇 프레임이 나오는지 보려고
if os.getenv("WEB_FPS") then
  WEB_FPSSUB = emu.register_frame_done(function() pcall(function() manager.ui.show_fps = true end) end)
end

-- 시험용: WEB_FPSLOG 가 있으면 300프레임마다 프레임 수를 적는다 (진짜 시간 대비 게임 속도 측정, web_pace_test.py)
if os.getenv("WEB_FPSLOG") then
  local nf = 0
  WEB_FPSLOGSUB = emu.register_frame_done(function() nf = nf + 1; if nf % 300 == 0 then print("WEB frames " .. nf) end end)
end

-- 시험용: WEB_BURN=ms 이면 매 프레임 그만큼 계산을 더 한다 (느린 폰 흉내, web_speed_test.py)
if os.getenv("WEB_BURN") then
  local ms = tonumber(os.getenv("WEB_BURN")) or 0
  WEB_BURNSUB = emu.register_frame_done(function() local t = os.clock() + ms / 1000; while os.clock() < t do end end)
end

-- 시험용: WEB_PADLOG 가 있으면 MAME 가 보는 조이스틱 장치를 2초마다 적는다
if os.getenv("WEB_PADLOG") then
  local n = 0
  WEB_PADSUB = emu.register_periodic(function()
    n = n + 1
    if n % 120 ~= 0 then return end
    local out = {}
    for cname, dc in pairs(manager.machine.input.device_classes) do
      if cname == "joystick" then for _, d in pairs(dc.devices) do out[#out + 1] = d.name end end
    end
    print("WEB pads: " .. #out .. " " .. table.concat(out, ", "))
  end)
end

-- 온라인 경기(WEB_LOCKUI=1): PC 런처처럼 게임을 멈추거나 끝내는 UI 키를 모두 뺀다 (ESC, P, Tab, F3, 상태 저장/불러오기 ...).
-- 한 사람이 멈추면 동기화 때문에 상대도 멈춘다. 경기용이라 설정 파일에는 남지 않는다 (game.html 이 경기 cfg 는 저장하지 않음)
if os.getenv("WEB_LOCKUI") == "1" then
  local ioport, none = manager.machine.ioport, input:seq_from_tokens("")
  local locked, missed = 0, {}
  for _, tok in ipairs({ "UI_CANCEL", "UI_PAUSE", "UI_PAUSE_SHOT", "UI_MENU", "UI_CONFIGURE", "UI_SHOW_GFX", "UI_PAUSE_SINGLE",
                         "UI_ON_SCREEN_DISPLAY", "UI_RESET_MACHINE", "UI_SOFT_RESET", "UI_SAVE_STATE", "UI_LOAD_STATE",
                         "UI_QUICK_SAVE_STATE", "UI_QUICK_LOAD_STATE", "UI_REWIND_SINGLE", "UI_FAST_FORWARD", "UI_THROTTLE",
                         "UI_FRAMESKIP_DEC", "UI_FRAMESKIP_INC", "UI_TOGGLE_DEBUG",
                         "UI_HELP", "UI_AUDIT", "UI_SAVE_STATE_QUICK", "UI_LOAD_STATE_QUICK", "UI_TOGGLE_CHEAT", "UI_TAPE_START", "UI_TAPE_STOP" }) do   -- F1-F8: the quick chat (2026-10-10)
    local ok = pcall(function()
      local t, pl = ioport:token_to_input_type(tok)
      ioport:set_type_seq(t, pl, "standard", none)
    end)
    if ok then locked = locked + 1 else missed[#missed + 1] = tok end
  end
  print("WEB lockui: " .. locked .. " keys off" .. (#missed > 0 and (", not found: " .. table.concat(missed, " ")) or ""))
end

local target = os.getenv("WEB_TARGET")
print("WEB boot: " .. tostring(target))
if target and target ~= "" then
  local fn, err = loadfile(target)
  if not fn then print("WEB boot: " .. tostring(err)) else fn() end
end
