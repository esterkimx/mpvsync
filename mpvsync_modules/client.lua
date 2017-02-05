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
local PlayBackState = require "mpvsync_modules/playbackstate"
local PingStat = require "mpvsync_modules/pingstat"

local Client = {}

function Client:send_req(reqtype)
    local datagram = { reqtype = reqtype }

    if reqtype == "SYN" then
        datagram.reqn = self.pstat.reqn
        self.pstat:inc()
    else
        datagram.reqn = 0
    end

    self.socket:send(ut.dg_pack(datagram))
end

function Client:dispatch(datagram_pkd)
    local datagram = ut.dg_unpack(datagram_pkd)

    if datagram.reqtype == "SYN" then
        self.pstat:update(datagram.reqn)
        self.pb_state:syn(PlayBackState:deserialize(datagram.data), self.pstat.ping_avg)
        return true

    elseif datagram.reqtype == "LIV" then
        self:send_req("LIV")
        return true

    elseif datagram.reqtype == "MSG" then
        ut.mpvsync_osd("Server" .. ": " .. datagram.data)
        return true

    elseif datagram.reqtype == "END" then
        ut.mpvsync_osd("Server stopped")
        return true
    end
end

---[[
function Client:debug_info()
    mp.msg.debug(self.pstat)
end
--]]
function Client:get_event_loop()
    return function()
        if self.opts.wait then
            mp.set_property_bool("pause", true)
        end
        ut.mpvsync_osd("Connecting to " .. self.opts.host)

        local i = 0

        while mp.keep_running do
            local next_timeout = ut.get_next_timeout_ms()
            i = i + 1
            print(i .." POLL " .. next_timeout)
            local poll_ret = ut.poll(self.fds, next_timeout)
            print("ret ".. poll_ret)


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

            if ut.is_poll_timeout(poll_ret) then
                dbg()
                mp.dispatch_events(false)
            end
        end
    end
end

function Client:bind_callbacks(cb)
    self.fd_event_cb = {
        [self.socket.fd]      = { IN  = cb.socket_IN,
                                  HUP = cb.socket_HUP },
        [self.wakeup_pipe_fd] = { IN  = cb.wakeup_pipe_IN,
                                  HUP = cb.wakeup_pipe_HUP }
    }

    mp.register_event("file-loaded", cb.syn)
    mp.register_event("seek", cb.syn)
    mp.register_event("end-file", cb.disconnect)
    mp.observe_property("pause", "bool", cb.syn)
    mp.add_periodic_timer(0.5, cb.syn)
end

function Client:new(opts)
    local cli =  {
        opts = opts,
        wakeup_pipe_fd = mp.get_wakeup_pipe(),
        pb_state = PlayBackState:new(),
        pstat = PingStat:new(),
        socket = udp:new()
    }
    cli.socket:connect(opts.host, opts.port)
    cli.fds = {
        [cli.socket.fd]      = { events = { IN = true } },
        [cli.wakeup_pipe_fd] = { events = { IN = true } }
    }

    self.__index = self
    setmetatable(cli, Client)

    cb = {
        socket_IN = function(fd)
            local datagram_pkd, err = cli.socket:receive()
            if datagram_pkd then
                cli:dispatch(datagram_pkd)
            else
                mp.msg.debug("Error on receive: " .. err)
            end
        end,
        socket_HUP = function(fd)
            cli.socket:close()
        end,
        wakeup_pipe_IN = function(fd)
            mp.dispatch_events(false)
            ut.flush(fd)
        end,
        wakeup_pipe_HUP = function(fd)
            os.exit(0)
        end,
        syn = function()
            cli:send_req("SYN")
        end,
        disconnect = function()
            cli:send_req("END")
        end
    }
    cli:bind_callbacks(cb)

    return cli
end

return Client