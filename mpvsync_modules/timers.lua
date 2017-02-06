--[[
Copyright (C) 2017  Maksim Esterkin

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
--]]

local Timers = {}

function Timers:new()
    local t = {
        list = {}
    }
    self.__index = self
    setmetatable(t, self)
    return t
end

function Timers:add(period, cb)
    local t = { period = period, cb = cb }
    t.next = mp.get_time() + period
    self.list[#self.list + 1] = t
end

function Timers:get_next_timeout_ms()
    local next = next -- opt
    if not next(self.list) then
        return nil
    end

    local next_timeout = 1e20 -- infinity
    local now = mp.get_time()

    for _, t in ipairs(self.list) do
        local dt = t.next - now
        if dt < next_timeout then
            next_timeout = dt
        end
    end

    return next_timeout * 1000
end

function Timers:process()
    for _, t in ipairs(self.list) do
        now = mp.get_time()
        if (t.next - now) <= 0 then
            t.next = now + t.period
            t.cb()
        end
    end
end

return Timers
