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

if os.getenv("WEB_FPS") then
  WEB_FPSSUB = emu.register_frame_done(function() pcall(function() manager.ui.show_fps = true end) end)
end

if os.getenv("WEB_FPSLOG") then
  local nf = 0
  WEB_FPSLOGSUB = emu.register_frame_done(function() nf = nf + 1; if nf % 300 == 0 then print("WEB frames " .. nf) end end)
end

if os.getenv("WEB_BURN") then
  local ms = tonumber(os.getenv("WEB_BURN")) or 0
  WEB_BURNSUB = emu.register_frame_done(function() local t = os.clock() + ms / 1000; while os.clock() < t do end end)
end

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

if os.getenv("WEB_LOCKUI") == "1" then
  local ioport, none = manager.machine.ioport, input:seq_from_tokens("")
  local locked, missed = 0, {}
  for _, tok in ipairs({ "UI_CANCEL", "UI_PAUSE", "UI_PAUSE_SHOT", "UI_MENU", "UI_CONFIGURE", "UI_SHOW_GFX", "UI_PAUSE_SINGLE",
                         "UI_ON_SCREEN_DISPLAY", "UI_RESET_MACHINE", "UI_SOFT_RESET", "UI_SAVE_STATE", "UI_LOAD_STATE",
                         "UI_QUICK_SAVE_STATE", "UI_QUICK_LOAD_STATE", "UI_REWIND_SINGLE", "UI_FAST_FORWARD", "UI_THROTTLE",
                         "UI_FRAMESKIP_DEC", "UI_FRAMESKIP_INC", "UI_TOGGLE_DEBUG",
                         "UI_HELP", "UI_AUDIT", "UI_SAVE_STATE_QUICK", "UI_LOAD_STATE_QUICK", "UI_TOGGLE_CHEAT", "UI_TAPE_START", "UI_TAPE_STOP" }) do
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
