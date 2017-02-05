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
local socket = require "posix.sys.socket"
local unistd = require "posix.unistd"
local ut = require "mpvsync_modules/utils"

local pb_state
local sock_fd

local clients = {}
local client_timeout = 5
local timeout = 0.5

local function listen(port)
    local err_prefix = "Cannot start server on port " .. port .. ": "
    local sock_fd, status, err

    sock_fd, err = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, 0)
    if not sock_fd then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    status, err = socket.bind(sock_fd, { family = socket.AF_INET, addr = "127.0.0.1", port = port })
    if not status then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    --udp:settimeout(timeout)
    return sock_fd
end

local function sendto(datagram_pkd, addr, port)
    local dest = {
        family = socket.AF_INET,
        addr   = addr,
        port   = port
    }
    socket.sendto(sock_fd, datagram_pkd, dest)
end

local function sendto_all(reqtype, data, filter)

    local datagram = {
        reqtype = reqtype,
        reqn = 0,
        data = data or ""
    }
    local datagram_pkd = ut.dg_pack(datagram)

    filter = filter or function(id) return true end
    for id, cli in pairs(clients) do
        if filter(id) then
            sendto(datagram_pkd, cli.ip, cli.port)
        end
    end
end

local function wall(msg, filter)
    local filter = filter or function(id) return true end

    if filter("localhost") then
        ut.mpvsync_osd(msg)
    end

    sendto_all("MSG", msg, filter)
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
        pb_state = false
    end
end

local function is_client(id)
    return clients[id] and true or false
end

local function add_client(id, cli)
    if not clients[id] then
        if cli then
            clients[id] = cli
        else
            local ip, port = id:match("([^,]+):([^,]+)")
            clients[id] = {}
            clients[id].ip = ip
            clients[id].port = tonumber(port)
        end
    end

    clients[id].live = true

    wall(id .. " connected", function(_id) return _id ~= id end)
end

local function del_client(id)
    clients[id] = nil
    wall(id .. " disconnected")
end

local function check_clients()
    local datagram_pkd = ut.dg_pack{ reqtype = "LIV", reqn = 0 }

    for id, cli in pairs(clients) do
        if not cli.live then
            del_client(id)
        end
    end

    for id, cli in pairs(clients) do
        sendto(datagram_pkd, cli.ip, cli.port)
        clients[id].live = false
    end
end

local function dispatch(datagram_pkd, src)
    local datagram = ut.dg_unpack(datagram_pkd)
    local id = src.addr .. ":" .. src.port

    mp.msg.debug(datagram.reqtype .. " " .. id)

    if datagram.reqtype == "SYN" then
        local datagram_rep = {
            reqtype = "SYN",
            reqn = datagram.reqn
        }

        update_pb_state()
        if pb_state then
            datagram_rep.data = ut.st_serialize(pb_state)
            sendto(ut.dg_pack(datagram_rep), src.addr, src.port)
        end
    end

    if not is_client(id) then
        add_client(id)
    end

    if datagram.reqtype == "END" then
        del_client(id)
    else
        clients[id].live = true
    end
end

local function syn_all()
    local datagram = { reqtype = "SYN", reqn = 0 }
    update_pb_state()
    if pb_state then
        for _, cli in pairs(clients) do
            datagram.data = ut.st_serialize(pb_state)
            sendto(ut.dg_pack(datagram), cli.ip, cli.port)
        end
    end
end

local function disconnect()
    sendto_all("END")
    unistd.close(sock_fd)
end

local function is_poll_timeout(poll_ret)
    return poll_ret == 0
end

local function init_server(opts)
    sock_fd = listen(opts.port)
    local wakeup_pipe_fd = mp.get_wakeup_pipe()
    local fds = {
        [sock_fd]        = { events = { IN = true } },
        [wakeup_pipe_fd] = { events = { IN = true } }
    }

    -- Add callbaks for events
    mp.register_event("seek", syn_all)
    mp.register_event("end-file", disconnect)
    mp.observe_property("pause", "bool", syn_all)
    mp.observe_property("speed", "number", syn_all)
    mp.add_periodic_timer(client_timeout, check_clients)

    -- Wait for clients on load
    if opts.wait then
        mp.set_property_bool("pause", true)
    end
    ut.mpvsync_osd("Wating for clients. Port: " .. opts.port)

    local function event_loop()
        while mp.keep_running do
            local next_timeout = ut.get_next_timeout_ms()
            local poll_ret = 0

            if next_timeout and next_timeout > 0 then
                poll_ret = posix.poll(fds, next_timeout)
            else
                poll_ret = posix.poll(fds, -1)
            end


            if  fds[sock_fd].revents.IN then
                local datagram_pkd, src = socket.recvfrom(sock_fd, 128)

                if datagram_pkd then
                    dispatch(datagram_pkd, src)
                else
                    -- In case of error there will be the error message instead of the sender's data
                    local err = src
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

return init_server
