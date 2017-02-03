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

local debug = false

local pb_state
local udp

local clients = {}
local client_timeout = 5
local timeout = 0.5

local function listen(port)
    local err_prefix = "Cannot start server on port " .. port .. ": "
    local udp, status, err

    udp, err = socket.udp()
    if not udp then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    status, err = udp:setsockname("*", port)
    if not status then
        mp.msg.error(err_prefix .. err)
        os.exit(1)
    end

    udp:settimeout(timeout)
    return udp
end

local function wall(msg, filter)
    local datagram = {
        reqtype = "MSG",
        reqn = 0,
        data = msg
    }
    local datagram_pkd = ut.dg_pack(datagram)

    filter = filter or function(id) return true end

    ut.mpvsync_osd(msg, 3)
    for id, cli in pairs(clients) do
        if filter(id) then
            udp:sendto(datagram_pkd, cli.ip, cli.port)
        end
    end
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
            clients[id].port = port
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
        udp:sendto(datagram_pkd, cli.ip, cli.port)
        clients[id].live = false
    end
end

local function dispatch(datagram_pkd, ip, port)
    local datagram = ut.dg_unpack(datagram_pkd)
    local id = ip .. ":" .. port

    if opts.debug then
        mp.msg.info(datagram.reqtype .. " " .. id)
    end

    if datagram.reqtype == "SYN" then
        local datagram_rep = {
            reqtype = "SYN",
            reqn = datagram.reqn
        }

        update_pb_state()
        if pb_state then
            datagram_rep.data = ut.st_serialize(pb_state)
        end

        udp:sendto(ut.dg_pack(datagram_rep), ip, port)
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

local callback = {}

function syn_all()
    local datagram = { reqtype = "SYN", reqn = 0 }
    update_pb_state()
    if pb_state then
        for _, cli in pairs(clients) do
            datagram.data = ut.st_serialize(pb_state)
            udp:sendto(ut.dg_pack(datagram), cli.ip, cli.port)
        end
    end
end

function disconnect()
end

local function init_server(_opts)
    opts  = _opts
    debug = opts.debug

    udp = listen(opts.port)

    -- Add callbaks for events
    mp.register_event("seek", syn_all)
    mp.observe_property("pause", "bool", syn_all)
    mp.observe_property("speed", "number", syn_all)
    mp.add_periodic_timer(client_timeout, check_clients)

    -- Wait for clients on load
    mp.set_property_bool("pause", true)
    ut.mpvsync_osd("Wating for clients. Port: " .. opts.port)

    local function event_loop()
        while mp.keep_running do
            local datagram_pkd, ip, port = udp:receivefrom()
            if datagram_pkd then
                dispatch(datagram_pkd, ip, port)
            end

            mp.dispatch_events(false)
        end
    end

    return event_loop
end

return init_server
