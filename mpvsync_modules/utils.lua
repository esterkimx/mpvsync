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


--[[
    The structure of datagram

    | 1 | 2  |       3       |
    |SYN|0000|p66.360000;s1.0|

    1. [3 bytes] Type of datagram (SYN, LIV, MSG, END)
    2. [4 bytes] The datagram's index; used fora network stats and ping calculation
        * Clients count SYN datagrams sent
        * All datagrams except SYN have index 0000
        * Server-initiated SYN datagrams also have index 0000
        * The server replies toa the client with the index received
    3. [from 0 to 64 bytes] Data string; can be empty for certain datagrams' types
        * The data section has a variable size
]

--[[
    Protocol summary

    Type |  Server     |  Client
    -----------------------------
    SYN  |  r:state    |  q:*
    SYN  |  q:state    |  -
    LIV  |  q:*        |  r:*
    MSG  |  q:msg      |  -
    END  |  q:*        |  -
    END  |  -          |  q:*

    q     - request
    r     - reply on request
    *     - empty data
    state - serialized playback state
    msg   - string to show as osd_message

    For example a client send a SYN datagram with empty data (ini:*). The server receive it,
    serialize and send own playback state (rep:state) back to the client.
]]


local utils = {}

function utils.dg_pack(datagram)
    if not datagram.reqtype or datagram.reqtype:len() ~= 3 then
        error("Invalid reqtype")
    end

    if (type(datagram.reqn) ~= "number") or (datagram.reqn < 0) or (datagram.reqn > 9999) then
        error("Invalid reqn")
    end

    if datagram.data and datagram.data:len() > 64 then
        error("Data string is too long")
    end

    return datagram.reqtype .. string.format("%04d", datagram.reqn) .. (datagram.data or "")
end

function utils.dg_unpack(datagram_pkd)
    local datagram = {}
    datagram.reqtype = datagram_pkd:sub(1, 3)
    datagram.reqn = tonumber(datagram_pkd:sub(4, 7))
    datagram.data = datagram_pkd:sub(8)
    return datagram
end

-- Sometimes it's better to know the type before unpacking
function utils.dg_type(datagram_pkd)
    return datagram_pkd:sub(1, 3)
end

-- Playback state serialization/deserialization
function utils.st_serialize(pb_state)
    local pb_state_srl = {
        "p", pb_state.pos, ";",
        "s", pb_state.speed, ";",
        "m", pb_state.pause
    }
    return table.concat(pb_state_srl)
end

function utils.st_deserialize(pb_state_srl)
    local pb_state = {}
    local s_pos, s_speed, s_pause = pb_state_srl:match("p([^,]+);s([^,]+);m([^,]+)")
    if s_pos and s_speed and s_pause then
        pb_state.pos   = tonumber(s_pos)
        pb_state.speed = tonumber(s_speed)
        pb_state.pause = tonumber(s_pause)
        return pb_state
    else
        return nil
    end
end

--  Show OSD message
function utils.mpvsync_osd(msg)
    mp.osd_message("mpvsync: " .. msg, 3)
end

-- Get next timer timeout in milliseconds
function utils.get_next_timeout_ms()
    local next_timeout = mp.get_next_timeout()
    if next_timeout then
        next_timeout = 1000 * next_timeout
    end
    return next_timeout
end

return utils
