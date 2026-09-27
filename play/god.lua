-- Seibu Cup Soccer Online - play solo with GOD (god.lua)
-- Copyright (C) 2026 seibucup.online (https://seibucup.online)
-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- This program is free software: you can redistribute it and/or modify it under the terms of the GNU General
-- Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version. It is distributed WITHOUT ANY WARRANTY; see the GNU General Public License for
-- details (the package's bin\legal\GPL-3.0.txt, the site's legal/GPL-3.0.txt, or <https://www.gnu.org/licenses/>).
-- Additional terms under section 7 of the GPL: a modified version must be marked as changed from the original,
-- and it may not use the name "Seibu Cup Soccer Online" (세이부 컵 사커 온라인).

-- 혼자놀기 "패스로 GOD 선택" (user, 2026-09-27): the plain game, except that a player who holds Pass while confirming
-- a country plays as GOD (the final boss team, grey kit), on both the original and the Selection set.
-- The select screen turns the chosen box into a team through an 8-byte table of team id + 1 (cupsoc reads the one at
-- $7F36, cupsocs2 the one at $7F5E; GOD's id is 11 -> $0C): while a Pass button is held every read of those tables
-- answers GOD. The same trick as netplay.lua's PvE option (SCNP_GOD), there only for 1P.
local machine = manager.machine
local game = machine.system.name
local mem = machine.devices[":maincpu"].spaces["program"]
local ED = { cupsoc = { 0x7F2E, 0x7F45, 0x109b3b }, cupsocs2 = { 0x7F5E, 0x7F8D, 0x109c73 } }   -- table range, select block
local e = ED[game]
local ko = (os.getenv("SCNP_LANG") or "ko") ~= "en"

-- every Pass button of the board (1P and 2P)
local passes = {}
for _, port in pairs(machine.ioport.ports) do
  for name, f in pairs(port.fields) do
    if name == "P1 Pass" or name == "P2 Pass" then passes[#passes + 1] = { port = port, mask = f.mask, dv = f.defvalue & f.mask } end
  end
end
local function pass_held()
  for _, p in ipairs(passes) do if (p.port:read() & p.mask) ~= p.dv then return true end end
  return false
end

if not e or #passes == 0 then
  print("god.lua: GOD is not available for " .. tostring(game))
  return
end
god_tap = mem:install_read_tap(e[1], e[2], "god", function(offset, data, mask)
  if pass_held() then return 0x0C0C end
  return data
end)
print("god.lua: hold Pass while confirming a country to play as GOD")

-- a line at the top while a country is being picked (the select block's phase word is 2 then)
local hint = ko and "패스를 누른 채 결정하면 GOD" or "Hold PASS while confirming to play as GOD"
god_draw = emu.register_frame_done(function()
  if mem:read_u8(e[3] + 2) ~= 2 then return end
  local s = machine.screens[":screen"]
  if s then s:draw_box(0, 0, s.width, 9, 0xc0000000, 0xc0000000); s:draw_text("center", 0, hint, 0xffffff40) end
end)
