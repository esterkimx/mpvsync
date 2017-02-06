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

local posix = require "posix"

local utils = {
    err = {
        DG_INVALID_REQTYPE = 1,
        DG_INVALID_REQN = 2,
        DG_INVALID_DATA = 3
    }
}

function utils.dg_assert(datagram)
    if not datagram.reqtype then
        return nil, utils.err.DG_INVALID_REQTYPE
    end

    if datagram.reqtype ~= "SYN" and
       datagram.reqtype ~= "LIV" and
       datagram.reqtype ~= "MSG" and
       datagram.reqtype ~= "END" then
           return nil, utils.err.DG_INVALID_REQTYPE
    end

    if (type(datagram.reqn) ~= "number") or (datagram.reqn < 0) or (datagram.reqn > 9999) then
        return nil, utils.err.DG_INVALID_REQN
    end

    if datagram.data and datagram.data:len() > 64 then
        return nil, utils.err.DG_INVALID_DATA
    end

    return datagram
end

function utils.dg_pack(datagram)
    local err

    datagram, err = utils.dg_assert(datagram)
    if datagram then
        return datagram.reqtype .. string.format("%04d", datagram.reqn) .. (datagram.data or "")
    end

    if err == utils.err.DG_INVALID_REQTYPE then
        error("Invalid reqtype")
    elseif err == utils.err.DG_INVALID_REQN then
        error("Invalid reqn")
    elseif err == utils.err.DG_INVALID_DATA then
        error("Data string is too long")
    end

    return
end

function utils.dg_unpack(datagram_pkd)
    local datagram = {}
    datagram.reqtype = datagram_pkd:sub(1, 3)
    datagram.reqn = tonumber(datagram_pkd:sub(4, 7))
    datagram.data = datagram_pkd:sub(8)
    return utils.dg_assert(datagram)
end

-- Sometimes it's better to know the type before unpacking
function utils.dg_type(datagram_pkd)
    return datagram_pkd:sub(1, 3)
end

--  Show OSD message
function utils.mpvsync_osd(msg)
    mp.osd_message("mpvsync: " .. msg, 3)
end

-- Posix poll wrap
-- If timeout < 0 returns 0
-- If timeout == nil blocks indefinitely
function utils.poll(fds, timeout)
    if timeout then
        if timeout > 0 then
            return posix.poll(fds, timeout)
        else
            return 0
        end
    else
        return posix.poll(fds, -1)
    end
end

function utils.is_poll_event(poll_ret)
    return poll_ret > 0
end

function utils.is_poll_timeout(poll_ret)
    return poll_ret == 0
end

-- Flush data from pipe/socket
function utils.flush(fd)
    posix.read(fd, 1)
    return
end

return utils
