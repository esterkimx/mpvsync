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
local options = require 'mp.options'

local opts = {
    connect = "",
    port = 32923,
    debug = false
}

local function get_port()
    local port = opts.port

    if type(port) ~= "number" then
        mp.msg.error("illegal port number")
        os.exit(1)
    elseif (port < 0) or (port > 65535) then
        mp.msg.error("illegal port number")
        os.exit(1)
    end

    return port
end

local function mpvsync_osd(msg)
    mp.osd_message("mpvsync: " .. msg, 3)
end

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
    local datagram = {}
    datagram.reqtype = datagram_pkd:sub(1,3)
    datagram.reqn = datagram_pkd:sub(4,7)
    datagram.data = datagram_pkd:sub(8)
    return datagram
end


--[[
    Protocol summary

    Type |  Server     |  Client
    -----------------------------
    SYN  |  rep:state  |  ini:*
    LIV  |  ini:*      |  rep:*
    MSG  |  ini:msg    |  -
    END  |  -          |  ini:*

    ini   - initiator
    rep   - reply on initiator's request
    *     - empty data
    state - serialized playback state
    msg   - string to show as osd_message

    For example client send a SYN datagram with empty data (ini:*). Server receive it,
    serialize and send own state (rep:state) back to client.
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


-- RingBuffer for gathering ping statistics
RingBuffer = {
    __tostring = function(self)
        return table.concat(self.data, " ")
    end
}

function RingBuffer:insert(val)
    self.last = self.last % self.max_length + 1
    self.data[self.last] = val
    if self.length < self.max_length then
        self.length = self.length + 1
    end
end

function RingBuffer:average()
    if self.length == 0 then
        return nil
    end

    local acc = 0
    for _, v in ipairs(self.data) do
        acc = acc + v
    end

    return acc / self.length
end

function RingBuffer:clean()
    for i, v in ipairs(self.data) do
        self.data[i] = nil
    end
    self.length = 0
    self.last = 0
end

function RingBuffer:new(max_length)
    local buff = {
        data = {},
        max_length = max_length,
        length = 0,
        last = 0
    }
    self.__index = self
    setmetatable(buff, self)
    return buff
end


-- Server code
do
    local server = {
        clients = {},
        client_timeout = 5
    }

    local callback = {}

    function server:update_state()
        if not self.state then
            self.state = {}
        end

        self.state.pos   = mp.get_property_number("time-pos")
        self.state.speed = mp.get_property_number("speed")
        self.state.pause = mp.get_property_bool("pause") and 1 or 0

        if self.state.pos and self.state.speed and self.state.pause then
            return
        else
            self.state = nil
        end
    end

    function server:is_client(id)
        return (self.clients[id] and true or false)
    end

    function server:add_client(id, cli)
        if(not self.clients[id]) then
            if cli then
                self.clients[id] = cli
            else
                local ip, port = id:match("([^,]+):([^,]+)")
                self.clients[id] = {}
                self.clients[id].ip = ip
                self.clients[id].port = port
            end
        end

        self.clients[id].live = true
        self:wall(id .. " connected", function(_id) return _id ~= id end)
    end

    function server:del_client(id)
        self.clients[id] = nil
        self:wall(id .. " disconnected")
    end

    function server:wall(msg, filter)
        filter = filter or function(id) return true end
        local datagram = { reqtype = "MSG", reqn = "0000" }
        datagram.data = msg
        local datagram_pkd = dg_pack(datagram)

        mpvsync_osd(msg, 3)
        for id, cli in pairs(self.clients) do
            if filter(id) then
                self.udp:sendto(datagram_pkd, cli.ip, cli.port)
            end
        end
    end

    function server:check_clients()
        local datagram_pkd = dg_pack(
            { reqtype = "LIV", reqn = "0000" }
        )

        for id, cli in pairs(self.clients) do
            if not cli.live then
                self:del_client(id)
            end
        end

        for id, cli in pairs(self.clients) do
            self.clients[id].live = false
            self.udp:sendto(datagram_pkd, cli.ip, cli.port)
        end
    end

    function server:dispatch(datagram_pkd, ip, port)
        local datagram = dg_unpack(datagram_pkd)
        local id = ip .. ":" .. port

        if opts.debug then
            mp.msg.info(datagram.reqtype .. " " .. id)
        end

        if datagram.reqtype == "SYN" then
            local datagram_ans = { reqtype = "SYN" }
            datagram_ans.reqn = datagram.reqn
            self:update_state()
            if self.state then
                datagram_ans.data = st_serialize(self.state)
            end
            self.udp:sendto(dg_pack(datagram_ans), ip, port)
        end

        if not self:is_client(id) then
            self:add_client(id)
        end

        if datagram.reqtype == "END" then
            self:del_client(id)
        else
            self.clients[id].live = true
        end
    end

    function callback.syn_all()
        local datagram = { reqtype = "SYN", reqn = "0000" }
        server:update_state()
        if server.state then
            for _, cli in pairs(server.clients) do
                datagram.data = st_serialize(server.state)
                server.udp:sendto(dg_pack(datagram), cli.ip, cli.port)
            end
        end
    end

    local function onload()
        mp.set_property_bool("pause", true)
        mpvsync_osd("Wating for clients")
    end

    function init_server()
        local port = get_port()
        server.udp = socket.udp()
        server.udp:setsockname("*", port)
        server.udp:settimeout(0.5)

        onload()

        local last_clients_check = 0
        function event_loop()
            while mp.keep_running do
                local datagram_pkd, ip, port = server.udp:receivefrom()
                if datagram_pkd then
                    server:dispatch(datagram_pkd, ip, port)
                end

                mp.dispatch_events(false)

                local now = mp.get_time()
                if (now - last_clients_check) > server.client_timeout then
                    server:check_clients()
                    last_clients_check = mp.get_time()
                end

                mp.dispatch_events(false)
            end
        end

        return event_loop, callback
    end
end


-- Client code
do
    local client = {
        reqn = 1,
        ping_buff = RingBuffer:new(5),
        ping_avg = 0,
        syn_sent = 0,
        syn_sent_last = 0,
        syn_lost = 0,
        max_pos_error = 0.5
    }
    local callback = {}

    function client:update_state()
        if not self.state then
            self.state = {}
        end

        local st = self.state
        st.pos   = mp.get_property_number("time-pos")
        st.speed = mp.get_property_number("speed")
        st.pause = mp.get_property_bool("pause") and 1 or 0

        if st.pos and st.speed and st.pause then
            return
        else
            self.state = nil
        end
    end

    function client:syn_state(sv_st)
        self:update_state()
        local st = self.state

        if st then
            if st.pause ~= sv_st.pause then
                local pause = sv_st.pause == 1 and true or false
                mp.set_property_bool("pause", pause)
                if pause then
                    mpvsync_osd("pause")
                else
                    mpvsync_osd("play")
                end
            end

            if st.speed ~= sv_st.speed then
                mp.set_property("speed", sv_st.speed)
                mpvsync_osd("speed " .. sv_st.speed)
            end

            if st.pos ~= sv_st.pos then
                local diff = sv_st.pos + 0.5 * self.ping_avg - st.pos
                if math.abs(diff) > self.max_pos_error then
                    mp.set_property("time-pos", sv_st.pos)
                    mpvsync_osd("seek " .. sv_st.pos - st.pos)
                end
            end
        end
    end

    function client:req_send(reqtype)
        local datagram = {}
        datagram.reqtype = reqtype
        datagram.reqn = string.format("%04d", self.reqn)

        if reqtype == "SYN" then
            self.syn_sent = self.syn_sent + 1
            self.syn_sent_last = mp.get_time()
        end
        self.udp:send(dg_pack(datagram))

        self.reqn = (self.reqn + 1) % 10000
        if self.reqn == 0 then
            self.reqn = 1
        end
    end

    function client:update_ping(reqn)
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

    function client:dispatch(datagram_pkg)
        local datagram = dg_unpack(datagram_pkg)

        if opts.debug then
            mp.msg.info(datagram_pkg)
        end

        if datagram.reqtype == "SYN" then
            self:update_ping(tonumber(datagram.reqn))
            self:syn_state(st_deserialize(datagram.data))
        elseif datagram.reqtype == "LIV" then
            self:req_send("LIV")
        elseif datagram.reqtype == "MSG" then
            mpvsync_osd(opts.connect .. ": " .. datagram.data)
        else
            return nil
        end

        return true
    end

    function client:debug_info()
        mp.msg.info("ping_avg " .. self.ping_avg)
    end

    function callback.syn()
        client:req_send("SYN")
        local datagram_pkg = client.udp:receive()
        if datagram_pkg then
            return client:dispatch(datagram_pkg)
        else
            return false
        end
    end

    function callback.disconnect()
        client:req_send("END")
    end

    local function onload()
        mp.set_property_bool("pause", true)
        mpvsync_osd("Connecting to " .. opts.connect)
        if callback.syn() then
            mpvsync_osd("Connection enstablished")
        end
    end

    function init_client()
        local host = opts.connect
        local port = get_port()
        local ip = socket.dns.toip(host)
        client.udp = socket.udp()
        client.udp:setpeername(ip, port)
        client.udp:settimeout(1)

        onload()

        function cli_loop()
            while mp.keep_running do
                mp.dispatch_events(false)

                local datagram_pkg = client.udp:receive()
                if datagram_pkg then
                    client:dispatch(datagram_pkg)
                end

                if opts.debug then
                    client:debug_info()
                end
            end
        end

        return cli_loop, callback
    end
end


-- Run
options.read_options(opts, "mpvsync")

local event_loop
if opts.connect ~= "" then
    event_loop, callback = init_client()

    if callback then
        mp.add_periodic_timer(10, callback.syn)
        mp.register_event("seek", callback.syn)
        mp.register_event("end-file", callback.disconnect)
        mp.observe_property("pause", "bool", callback.syn)
    end
else
    event_loop, callback = init_server()

    if callback then
        mp.register_event("seek", callback.syn_all)
        mp.observe_property("pause", "bool", callback.syn_all)
        mp.observe_property("speed", "number", callback.syn_all)
    end
end

if event_loop then
    mp_event_loop = event_loop
end
