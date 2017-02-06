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

local ut = require "mpvsync_modules/utils"

local PlayBackState = {
    max_pos_error = 0.5,
    min_pos_error = 0.1
}

function PlayBackState:new()
    local pb_state = {}
    self.__index = self
    setmetatable(pb_state, self)
    return pb_state
end

function PlayBackState:update()
    self.pos   = mp.get_property_number("time-pos")
    self.speed = mp.get_property_number("speed")
    self.pause = mp.get_property_bool("pause") and 1 or 0

    if self.pos and self.speed and self.pause then
        return true
    else
        return
    end
end

function PlayBackState:serialize()
    local pb_state_srl = {
        "p", self.pos, ";",
        "s", self.speed, ";",
        "m", self.pause
    }
    return table.concat(pb_state_srl)
end

function PlayBackState:deserialize(pb_state_srl)
    local pb_state = PlayBackState:new()
    local s_pos, s_speed, s_pause = pb_state_srl:match("p([^,]+);s([^,]+);m([^,]+)")
    if s_pos and s_speed and s_pause then
        pb_state.pos   = tonumber(s_pos)
        pb_state.speed = tonumber(s_speed)
        pb_state.pause = tonumber(s_pause)
        if pb_state.pos and pb_state.speed and pb_state.pause then
            return pb_state
        end
    end

    return nil
end

function PlayBackState:syn(sv_st, ping_avg)
    if not sv_st then
        return
    end

    if self:update() then
        if self.pause ~= sv_st.pause then
            local pause = sv_st.pause == 1 and true or false
            mp.set_property_bool("pause", pause)
            if pause then
                mp.set_property("time-pos", sv_st.pos)
                ut.mpvsync_osd("pause")
            else
                mp.set_property("time-pos", sv_st.pos + 0.5 * ping_avg)
                ut.mpvsync_osd("play")
            end
        end

        if self.speed ~= sv_st.speed then
            mp.set_property("speed", sv_st.speed)
            ut.mpvsync_osd("speed " .. sv_st.speed)
        end

        if self.pos ~= sv_st.pos then
            local pos_error = math.max(math.min(1.5 * ping_avg, self.max_pos_error),
                                       self.min_pos_error)
            local diff = sv_st.pos + 0.5 * ping_avg - self.pos
            if math.abs(diff) > pos_error then
                mp.set_property("time-pos", sv_st.pos)
                ut.mpvsync_osd("seek " .. sv_st.pos - self.pos)
            end
        end
    end

    return true
end

return PlayBackState
