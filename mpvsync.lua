--[[
The MIT License (MIT)

Copyright (c) 2017 Maksim Esterkin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
--]]

local socket = require "socket"
local options = require 'mp.options'

local opts = {
    connect = "",
    port = 32923,
    debug = false
}

--[[
    The structure of datagram

    | 1 | 2  |       3       |
    |SYN|0000|p66.360000;s1.0|

    1. Type of datagram (SYN, LIV or MSG)
    2. Datagram's index; used for network stats and ping calculation
        * Clients count datagrams sent
        * Server-initiated datagrams always have index 0000
        * Server replies to client with the index received
    3. Data; can be empty for certain datagram's types
        * The data section has a variable size
]]

local function dg_pack(datagram)
    return datagram.reqtype .. datagram.reqn .. (datagram.data or "")
end

local function dg_unpack(datagram_pkd)
    datagram = {}
    datagram.reqtype = datagram_pkd:sub(1,3)
    datagram.reqn = datagram_pkd:sub(4,7)
    datagram.data = datagram_pkd:sub(8)
    return datagram
end


--[[
    Sent datagram's data content (* is empty)
    Type    Server      Client
    --------------------------
    SYN     State       *
    LIV     *           *
    MSG     Message     Message

    Therefore, server serialize own state and client deserialize it
]]

local function st_serialize(state)
    local state_srl = {}
    state_srl[#state_srl + 1] = "p"
    state_srl[#state_srl + 1] = state.pos
    state_srl[#state_srl + 1] = ";"
    state_srl[#state_srl + 1] = "s"
    state_srl[#state_srl + 1] = state.speed
    state_srl[#state_srl + 1] = ";"
    state_srl[#state_srl + 1] = "m"
    state_srl[#state_srl + 1] = state.pause
    return table.concat(state_srl)
end

local function st_deserialize(state_srl)
    local state = {}
    local s_pos, s_speed, s_pause = state_srl:match("p([^,]+);s([^,]+);m([^,]+)")
    state.pos   = tonumber(s_pos)
    state.speed = tonumber(s_speed)
    state.pause = tonumber(s_pause)
    return state
end


-- Server code
do
    local server = {}
    server.clients = {}
    server.client_timeout = 5

    function server:get_state()
        local state = {}
            state.pos   = mp.get_property_number("time-pos")
            state.speed = mp.get_property_number("speed")
            state.pause = mp.get_property_bool("pause") and 1 or 0
        return state
    end

    function server:is_client(id)
        return (self.clients[id] and true or false)
    end

    function server:add_client(id, cli)
        if(not self.clients[id]) then
            if (cli) then
                self.clients[id] = cli
            else
                local ip, port = id:match("([^,]+):([^,]+)")
                self.clients[id] = {}
                self.clients[id].ip = ip
                self.clients[id].port = port
            end
        end

        self.clients[id].live = true
        self:wall(id .. " connected")
    end

    function server.del_client(self, id)
        self.clients[id] = nil
        self:wall(id .. " disconnected")
    end

    function server.syn_all(self)
        local datagram = { reqtype = "SYN", reqn = "0000" }
        for _, cli in pairs(self.clients) do
            datagram.data = st_serialize(self:get_state())
            self.udp:sendto(dg_pack(datagram), cli.ip, cli.port)
        end
    end

    function server.wall(self, msg)
        local datagram = { reqtype = "MSG", reqn = "0000" }
        datagram.data = msg
        local datagram_pkd = dg_pack(datagram)

        mp.osd_message(msg)
        for _, cli in pairs(self.clients) do
            print(cli.ip)
            self.udp:sendto(datagram_pkd, cli.ip, cli.port)
        end
    end

    function server.check_clients(self)
        local datagram_pkd = dg_pack(
            { reqtype = "LIV", reqn = "0000" }
        )

        for id, cli in pairs(self.clients) do
            if (not cli.live) then
                self:del_client(id)
            end
        end

        for id, cli in pairs(self.clients) do
            self.udp:sendto(datagram_pkd, cli.ip, cli.port)
            self.clients[id].live = false
        end
    end

    function server.dispatch(self, datagram_pkd, ip, port)
        local datagram = dg_unpack(datagram_pkd)
        local id = ip .. ":" .. port

        if (opts.debug) then
            mp.osd_message(datagram.reqtype .. " " .. id)
        end

        if (not self:is_client(id)) then
            self:add_client(id)
        end

        self.clients[id].live = true

        if (datagram.reqtype == "SYN") then
            local datagram_ans = { reqtype = "SYN" }
            datagram_ans.reqn = datagram.reqn
            datagram_ans.data = st_serialize(self:get_state())
            self.udp:sendto(dg_pack(datagram_ans), ip, port)
        end
    end

    local function get_port()
        local port = opts.port
        if (not port) then
            mp.msg.error("illegal port number")
            os.exit(1)
        elseif (port < 0 or port > 65535) then
            mp.msg.error("illegal port number")
            os.exit(1)
        end
        return port
    end

    server.idle = false
    function init_server()
        local port = get_port()
        server.udp = socket.udp()
        server.udp:setsockname("*", port)
        server.udp:settimeout(2)

        local last_clients_check = 0
        return function()
            while true do
                if not server.idle then
                    server.idle = true
                    local datagram_pkd, ip, port = server.udp:receivefrom()
                    server.idle = false
                    if (datagram_pkd) then
                        server:dispatch(datagram_pkd, ip, port)
                    end
                end

                local now = mp.get_time()
                if (now - last_clients_check) > server.client_timeout then
                    print("LIV test")
                    server:check_clients()
                    last_clients_check = mp.get_time()
                end
            end
        end
    end
end


-- Client code
do
    local client = {}
    client.reqn = 1
    client.num_ping = 20
    client.avg_ping = 0
    client.max_pos_error = 0.5

    function client.syn_state(self, sv_state)
        local pos = tonumber(mp.get_property("time-pos"))

        mp.set_property_bool("pause", sv_state.pause == 1 and true or false)
        mp.set_property("speed", sv_state.speed)

        if math.abs(sv_state.pos - pos) > self.max_pos_error then
            mp.set_property("time-pos", sv_state.pos)
            mp.osd_message("sync " .. (sv_state.pos - pos))
        end

        if (sv_state.pause == 1) then
            mp.set_property("time-pos", sv_state.pos)
        end
    end

    function client.req_send(self, reqtype)
        local datagram = {}
        datagram.reqtype = reqtype
        datagram.reqn = string.format("%04d", self.reqn)

        self.udp:send(dg_pack(datagram))

        self.reqn = (self.reqn + 1) % 10000
        if (self.reqn == 0) then
            self.reqn = 1
        end
    end

    function client.dispatch(self, datagram_pkg)
        local datagram = dg_unpack(datagram_pkg)
        print(datagram_pkg)

        if (opts.debug) then
            mp.osd_message(datagram.reqtype)
        end

        if (datagram.reqtype == "SYN") then
            self:syn_state(st_deserialize(datagram.data))
        elseif (datagram.reqtype == "LIV") then
            self:req_send("LIV")
        elseif (datagram.reqtype == "MSG") then
            mp.osd_message(datagram.data)
        end
    end

    local function get_port()
        local port = opts.port
        if (not port) then
            mp.msg.error("illegal port number")
            os.exit(1)
        elseif (port < 0 or port > 65535) then
            mp.msg.error("illegal port number")
            os.exit(1)
        end
        return port
    end

    function init_client()
        local host = opts.connect
        local port = get_port()
        local ip = socket.dns.toip(host)
        client.udp = socket.udp()
        client.udp:setpeername(ip, port)
        client.udp:settimeout(3)

        --[[
        client:req_send("SYN")
        local datagram = client.udp:receive()
        if datagram then
            client:dispatch(datagram)
        end
        ]]

        return function()
            while true do
                local datagram = client.udp:receive()
                if datagram then
                    client:dispatch(datagram)
                end

                client:req_send("SYN")
                datagram = client.udp:receive()
                if datagram then
                    client:dispatch(datagram)
                end
            end
        end
    end
end


-- Run
do
    options.read_options(opts, "mpvsync")

    if (opts.connect ~= "") then
        local cli_loop = init_client()
        if(cli_loop) then
            mp.register_event("file-loaded",  cli_loop)
        end

    else
        local srv_loop = init_server()

        if(srv_loop) then
            local function onload()
                    mp.set_property_bool("pause", true)
                    mp.osd_message("Server is listening and wating for clients.", 5)
                    srv_loop()
            end
            mp.register_event("file-loaded", onload)
        end
    end
end
