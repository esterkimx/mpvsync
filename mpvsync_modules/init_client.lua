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
local dbg = require "debugger"

local posix = require "posix"
local socket = require "posix.sys.socket"
local unistd = require "posix.unistd"
local ut = require "mpvsync_modules/utils"
local RingBuffer = require "mpvsync_modules/ringbuffer"

local pb_state
local sock_fd
local sock_dest

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
    local err_prefix = "Cannot connect to " .. host .. ":" .. port .. " "
    local sock_dest = { family = socket.AF_INET, addr = host, port = port }
    local sock_fd, status, err, errnum

    sock_fd, err = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, 0)
    if not sock_fd then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    status, err, errnum = socket.bind(sock_fd,
        { family = socket.AF_INET, addr = "127.0.0.1", port = 0 })

    if not status then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    return sock_fd, sock_dest
end

local function send(datagram_pkd)
    return socket.sendto(sock_fd, datagram_pkd, sock_dest)
end

local function send_req(reqtype)
    local datagram = { reqtype = reqtype }

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

    send(ut.dg_pack(datagram))
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
        send_req("LIV")
        return true

    elseif datagram.reqtype == "MSG" then
        ut.mpvsync_osd("Server" .. ": " .. datagram.data)
        return true

    elseif datagram.reqtype == "END" then
        ut.mpvsync_osd("Server stopped")
        return true
    end
end

local function receive()
    local datagram_pkg, err = socket.recv(sock_fd, 128)
    if datagram_pkg then
        mp.msg.debug(datagram_pkg)
        dispatch(datagram_pkg)
        return true
    else
        return nil, err
    end
end

---[[
local function debug_info()
    mp.msg.debug("ping: avg " .. stats.ping_avg ..
                    " sent " .. stats.syn_sent ..
                    " lost " .. stats.syn_lost)
end
--]]

local function syn()
    send_req("SYN")
end

local function disconnect()
    send_req("END")
    unistd.close(sock_fd)
end

local function is_poll_timeout(poll_ret)
    return poll_ret == 0
end


local function init_client(opts)
    sock_fd, sock_dest = connect(opts.host, opts.port)
    local wakeup_pipe_fd = mp.get_wakeup_pipe()
    local fds = {
        [sock_fd]        = { events = { IN = true } },
        [wakeup_pipe_fd] = { events = { IN = true } }
    }

    --mp.register_event("file-loaded", syn)
    mp.register_event("seek", syn)
    mp.register_event("end-file", disconnect)
    --mp.observe_property("pause", "bool", syn)

    mp.add_periodic_timer(5, syn)

    -- Connect on load
    if opts.wait then
        mp.set_property_bool("pause", true)
    end
    ut.mpvsync_osd("Connecting to " .. opts.host)

    local function event_loop()
        mp.dispatch_events(false)

        while mp.keep_running do
            local next_timeout = ut.get_next_timeout_ms()
            local poll_ret = 0

            if next_timeout then
                if next_timeout > 0 then
                    poll_ret = posix.poll(fds, next_timeout)
                end
            else
                poll_ret = posix.poll(fds, -1)
            end

            if fds[sock_fd].revents.IN then
                local status, err = receive()
                if not status then
                    mp.msg.debug("Error on receive: " .. err)
                end
            end

            if fds[wakeup_pipe_fd].revents.IN or is_poll_timeout(poll_ret) then
                mp.dispatch_events(false)

                if fds[wakeup_pipe_fd].revents.IN then
                    --flush wakeup_pipe
                    posix.read(wakeup_pipe_fd, 1)
                end
            end
        end
    end

    return event_loop
end

return init_client
