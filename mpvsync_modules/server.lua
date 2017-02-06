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
local udp = require "mpvsync_modules/udp"
local ut = require "mpvsync_modules/utils"
local Timers = require "mpvsync_modules/timers"
local PlayBackState = require "mpvsync_modules/playbackstate"

Server = {
    client_timeout = 5
}

function Server:is_client(id)
    return self.clients[id] and true or false
end

function Server:add_client(id, src)
    if not self.clients[id] then
        self.clients[id] = {}
        self.clients[id].src = src
        self.clients[id].live = true
    end

    self:wall(id .. " connected", function(_id) return _id ~= id end)
end

function Server:del_client(id)
    self.clients[id] = nil
    self:wall(id .. " disconnected")
end

function Server:clean_clients(id)
    for id, cli in pairs(self.clients) do
        if not cli.live then
            self:del_client(id)
        end
    end
end

function Server:set_allcli_dead()
    for id, cli in pairs(self.clients) do
        cli.live = false
    end
end

function Server:send_all(reqtype, data, filter)
    datagram = {
        reqtype = reqtype,
        reqn = 0,
        data = data or ""
    }
    filter = filter or function(id) return true end

    for id, cli in pairs(self.clients) do
        if filter(id) then
            self.socket:send(ut.dg_pack(datagram), cli.src)
        end
    end
end

function Server:wall(msg)
    local filter = filter or function(id) return true end

    if filter("localhost") then
        ut.mpvsync_osd(msg)
    end

    self:send_all("MSG", msg, filter)
end

function Server:syn_all()
    if self.pb_state:update() then
        self:send_all("SYN", self.pb_state:serialize())
    end
end

function Server:dispatch(datagram_pkd, src)
    local datagram, err = ut.dg_unpack(datagram_pkd)

    if not datagram then
        mp.msg.debug(err)
        return
    end

    local id = src.addr .. ":" .. src.port

    if not self:is_client(id) then
        self:add_client(id, src)
    end

    mp.msg.debug(datagram.reqtype .. " " .. id)

    if datagram.reqtype == "SYN" then
        local datagram_rep = { reqtype = "SYN", reqn = datagram.reqn }

        if self.pb_state:update() then
            datagram_rep.data = self.pb_state:serialize()
            self.socket:send(ut.dg_pack(datagram_rep), src)
        end

        self.clients[id].live = true
        return true

    elseif datagram.reqtype == "LIV" then
        self.clients[id].live = true
        return true

    elseif datagram.reqtype == "END" then
        self:del_client(id)
        return true
    end

    return false
end

function Server:get_event_loop()
    return function()
        if self.opts.wait then
            mp.set_property_bool("pause", true)
        end
        ut.mpvsync_osd("Wating for clients. Port: " .. self.opts.port)

        while mp.keep_running do
            local next_timeout = self.timers:get_next_timeout_ms()
            local poll_ret = ut.poll(self.fds, next_timeout)

            if ut.is_poll_event(poll_ret) then
                for fd in pairs(self.fds) do
                    if self.fds[fd].revents.IN then
                        self.fd_event_cb[fd].IN(fd)
                    end

                    if self.fds[fd].revents.HUP then
                        self.fd_event_cb[fd].HUP(fd)
                        self.fds[fd] = nil

                        if not next(self.fds) then
                            return
                        end
                    end
                end
            elseif ut.is_poll_timeout(poll_ret) then
                self.timers:process()
            end
        end
    end
end

function Server:bind_callbacks(cb)
    self.fd_event_cb = {
        [self.socket.fd]      = { IN  = cb.socket_IN,
                                  HUP = cb.socket_HUP },
        [self.wakeup_pipe_fd] = { IN  = cb.wakeup_pipe_IN,
                                  HUP = cb.wakeup_pipe_HUP }
    }

    mp.register_event("seek", cb.syn_all)
    mp.register_event("end-file", cb.disconnect)
    mp.observe_property("pause", "bool", cb.syn_all)
    mp.observe_property("speed", "number", cb.syn_all)

    self.timers:add(self.client_timeout, cb.check_clients)
end

function Server:new(opts)
    local srv =  {
        opts = opts,
        wakeup_pipe_fd = mp.get_wakeup_pipe(),
        pb_state = PlayBackState:new(),
        socket = udp:new(),
        timers = Timers:new(),
        clients = {}
    }
    srv.socket:listen(opts.port)
    srv.fds = {
        [srv.socket.fd]      = { events = { IN = true } },
        [srv.wakeup_pipe_fd] = { events = { IN = true } }
    }

    self.__index = self
    setmetatable(srv, Server)

    cb = {
        socket_IN = function(fd)
            local datagram_pkd, src = srv.socket:receive()
            if datagram_pkd then
                srv:dispatch(datagram_pkd, src)
            else
                mp.msg.debug("Error on receive: " .. err)
            end
        end,
        socket_HUP = function(fd)
            srv.socket:close()
        end,
        wakeup_pipe_IN = function(fd)
            mp.dispatch_events(false)
            ut.flush(fd)
        end,
        wakeup_pipe_HUP = function(fd)
            os.exit(0)
        end,
        syn_all = function()
            srv:syn_all()
        end,
        disconnect = function()
            srv:send_all("END")
        end,
        check_clients = function()
            srv:clean_clients()
            srv:set_allcli_dead()
            srv:send_all("LIV")
        end
    }
    srv:bind_callbacks(cb)

    return srv
end

return Server
