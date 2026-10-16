-- Seibu Cup Soccer Online - play solo with GOD (god.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online). All rights reserved.
-- SPDX-License-Identifier: LicenseRef-SeibuCupOnline-Proprietary
--
-- 이 파일은 세이부 컵 사커 온라인의 런처와 웹 플레이에서 쓰기 위해서만 배포됩니다.
-- 허락 없이 수정하거나 다른 곳에 재배포할 수 없습니다.
-- This file is distributed only for use with the Seibu Cup Soccer Online launcher and web play.
-- It may not be modified or redistributed without permission.
local machine = manager.machine
local game = machine.system.name
local mem = machine.devices[":maincpu"].spaces["program"]

local ED = { cupsoc = { 0x7F2E, 0x7F45, 0x109b3b, 0x7f66, 0x7cf4, 0x109d6e, 0x109db6 },
             cupsocs2 = { 0x7F5E, 0x7F8D, 0x109c73, 0x7fbe, 0x7d16, 0x109efe, 0x109f46 } }
local e = ED[game]
local ko = (os.getenv("SCNP_LANG") or "ko") ~= "en"

local passes = {}
for _, port in pairs(machine.ioport.ports) do
  for name, f in pairs(port.fields) do
    if name == "P1 Pass" or name == "P2 Pass" then passes[#passes + 1] = { port = port, mask = f.mask, dv = f.defvalue & f.mask } end
  end
end

local ALWAYS = os.getenv("GOD_ALWAYS") == "1"
local function pass_held()
  if ALWAYS then return true end
  for _, p in ipairs(passes) do if (p.port:read() & p.mask) ~= p.dv then return true end end
  return false
end

if not e or #passes == 0 then
  print("god.lua: GOD is not available for " .. tostring(game))
  return
end
local cpu = machine.devices[":maincpu"]
local side, pending = {}, nil
god_tap = mem:install_read_tap(e[1], e[2], "god", function(offset, data, mask)
  if pass_held() then
    if cpu.state["CURPC"].value == e[4] then
      local v = (mask == 0x00ff) and (data & 0xff) or (data >> 8)
      if v >= 1 and v <= 11 then pending = v - 1 end
    end
    return 0x0C0C
  end
  return data
end)

god_wtap = mem:install_write_tap(e[6], e[7] + 1, "god_w", function(offset, data, mask)
  for _, a in ipairs({ e[6], e[7] }) do
    if a == offset and mask & 0xff00 ~= 0 then
      local v = data >> 8
      if v == 11 and pending then side[a] = pending; pending = nil elseif v ~= 11 then side[a] = nil end
    end
  end
end)
god_rtap = mem:install_read_tap(e[6], e[7] + 1, "god_r", function(offset, data, mask)
  if not next(side) then return data end
  local pc = cpu.state["CURPC"].value
  if pc ~= e[5] and (pc < 0x50000 or pc >= 0x60000) then return data end
  local c = side[offset]
  if c and mask & 0xff00 ~= 0 and (data >> 8) == 11 then data = (data & 0x00ff) | (c << 8) end
  return data
end)
print(ALWAYS and "god.lua: every country confirmed plays as GOD" or "god.lua: hold Pass while confirming a country to play as GOD")

local hint = ALWAYS and (ko and "GOD로 플레이합니다 - 아무 나라나 결정하세요" or "You play as GOD - confirm any country")
  or (ko and "패스를 누른 채 결정하면 GOD" or "Hold PASS while confirming to play as GOD")
god_draw = emu.register_frame_done(function()
  if mem:read_u8(e[3] + 2) ~= 2 then return end
  local s = machine.screens[":screen"]
  if s then s:draw_box(0, 0, s.width, 9, 0xc0000000, 0xc0000000); s:draw_text("center", 0, hint, 0xffffff40) end
end)

;(function()
  local rq = os.getenv("RQW_OVERLAY")
  if rq and rq ~= "" then
    local f, err = loadfile(rq, "t", _ENV)
    local ok = f and pcall(f)
    if not ok then emu.print_error("ranked overlay: " .. tostring(err)) end
  end
end)()
