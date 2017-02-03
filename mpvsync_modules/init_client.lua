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

local socket = require "socket"
local ut = require "mpvsync_modules/utils"
local RingBuffer = require "mpvsync_modules/ringbuffer"

local debug = false

local pb_state
local udp

local max_pos_error = 0.5
local min_pos_error = 0.1

local stats = {
    reqn = 1,
    ping_buff = RingBuffer:new(6),
    ping_avg = 0,
    syn_sent = 0,
    syn_sent_last = 0,
    syn_lost = 0
}

local function connect(host, port)
    udp = socket.udp()

    local ip, err = socket.dns.toip(host)
    if not ip then
        -- For some hosts provided as IPs dns.toip fails
        local ip = host
        udp:setpeername(ip, port)
    else
        udp:setpeername(ip, port)
    end
    udp:settimeout(1)
end

local function update_pb_state()
    if not pb_state then
        pb_state = {}
    end

    pb_state.pos   = mp.get_property_number("time-pos")
    pb_state.speed = mp.get_property_number("speed")
    pb_state.pause = mp.get_property_bool("pause") and 1 or 0

    if pb_state.pos and pb_state.speed and pb_state.pause then
        return true
    else
        pb_state = nil
    end

    return
end

local function syn_pb_state(sv_st)
    if not sv_st then
        return
    end

    update_pb_state()

    if pb_state then
        if pb_state.pause ~= sv_st.pause then
            local pause = sv_st.pause == 1 and true or false
            mp.set_property_bool("pause", pause)
            if pause then
                mp.set_property("time-pos", sv_st.pos)
                ut.mpvsync_osd("pause")
            else
                mp.set_property("time-pos", sv_st.pos + 0.5 * stats.ping_avg)
                ut.mpvsync_osd("play")
            end
        end

        if pb_state.speed ~= sv_st.speed then
            mp.set_property("speed", sv_st.speed)
            ut.mpvsync_osd("speed " .. sv_st.speed)
        end

        if pb_state.pos ~= sv_st.pos then
            local pos_error = math.max(math.min(1.5 * stats.ping_avg, max_pos_error), min_pos_error)
            local diff = sv_st.pos + 0.5 * stats.ping_avg - pb_state.pos
            if math.abs(diff) > pos_error then
                mp.set_property("time-pos", sv_st.pos)
                ut.mpvsync_osd("seek " .. sv_st.pos - pb_state.pos)
            end
        end
    end

    return true
end

local function req_send(reqtype)
    local datagram = {}
    datagram.reqtype = reqtype

    if reqtype == "SYN" then
        datagram.reqn = stats.reqn

        stats.reqn = (stats.reqn + 1) % 10000
        if stats.reqn == 0 then
            stats.reqn = 1
        end

        stats.syn_sent = stats.syn_sent + 1
        stats.syn_sent_last = mp.get_time()
    else
        datagram.reqn = 0
    end

    udp:send(ut.dg_pack(datagram))
end

local function update_ping(reqn)
    if reqn == 0 then
        return
    end

    if reqn == stats.reqn - 1 then
        local ping = mp.get_time() - stats.syn_sent_last
        stats.ping_buff:insert(ping)
        stats.ping_avg = stats.ping_buff:average()
    else
        stats.syn_lost = stats.syn_lost + 1
    end
end

local function dispatch(datagram_pkg)
    local datagram = ut.dg_unpack(datagram_pkg)

    if datagram.reqtype == "SYN" then
        update_ping(datagram.reqn)
        syn_pb_state(ut.st_deserialize(datagram.data))
        return true

    elseif datagram.reqtype == "LIV" then
        req_send("LIV")
        return true

    elseif datagram.reqtype == "MSG" then
        ut.mpvsync_osd(opts.host .. ": " .. datagram.data)
        return true

    elseif datagram.reqtype == "END" then
        ut.mpvsync_osd("Server stopped")
        return true
    end
end

local function debug_info()
    mp.msg.info("ping: avg " .. stats.ping_avg ..
                    " sent " .. stats.syn_sent ..
                    " lost " .. stats.syn_lost)
end

function syn()
    req_send("SYN")
    local datagram_pkg = udp:receive()
    if datagram_pkg and ut.dg_type(datagram_pkg) == "SYN" then
        return dispatch(datagram_pkg)
    else
        return false
    end
end

local function disconnect()
    req_send("END")
end

local function init_client(_opts)
    opts  = _opts
    debug = opts.debug

    connect(opts.host, opts.port)

    mp.register_event("seek", syn)
    mp.register_event("end-file", disconnect)
    mp.observe_property("pause", "bool", syn)
    mp.add_periodic_timer(10, syn)

    -- Connect on load
    if opts.wait then
        mp.set_property_bool("pause", true)
    end
    ut.mpvsync_osd("Connecting to " .. opts.host)

    local function event_loop()
        while mp.keep_running do
            mp.dispatch_events(false)

            local datagram_pkg = udp:receive()
            if datagram_pkg then
                if opts.debug then
                    mp.msg.info(datagram_pkg)
                end

                dispatch(datagram_pkg)
            end

            if opts.debug then
                debug_info()
            end
        end
    end

    return event_loop
end

return init_client
