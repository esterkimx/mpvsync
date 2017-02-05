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

local RingBuffer = require "mpvsync_modules/ringbuffer"

local PingStat = {
    __tostring = function(self)
        return "ping: avg "  .. self.ping_avg ..
                    " sent " .. self.syn_sent ..
                    " lost " .. self.syn_lost
    end
}

function PingStat:new()
    local pstat = {
        reqn = 1,
        ping_buff = RingBuffer:new(6),
        ping_avg = 0,
        syn_sent = 0,
        syn_sent_last = 0,
        syn_lost = 0
    }
    self.__index = self
    setmetatable(pstat, PingStat)
    return pstat
end

function PingStat:inc()
    self.reqn = (self.reqn + 1) % 10000

    if self.reqn == 0 then
        self.reqn = 1
    end

    self.syn_sent = self.syn_sent + 1
    self.syn_sent_last = mp.get_time()
end

function PingStat:update(reqn)
    if reqn == 0 then
        return
    end

    if reqn == self.reqn - 1 then
        local ping = mp.get_time() - self.syn_sent_last
        self.ping_buff:insert(ping)
        self.ping_avg = self.ping_buff:average()
    else
        self.syn_lost = self.syn_lost + 1
    end
end

return PingStat
