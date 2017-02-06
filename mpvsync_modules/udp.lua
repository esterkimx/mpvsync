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

local udp = {
    max_dg_size = 128
}

function udp:new()
    u = {}
    self.__index = self
    setmetatable(u, udp)
    return u
end

function udp:listen(port)
    local status, err

    self.fd, err = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, 0)
    if not self.fd then
        mp.msg.error("Failed to open socket: " .. err)
        os.exit(1)
    end

    status, err = socket.bind(self.fd,
        { family = socket.AF_INET, addr = "127.0.0.1", port = port })
    if not status then
        mp.msg.error("Failed to bind socket: "  .. err)
        os.exit(1)
    end

    status, err = socket.setsockopt(self.fd,
        socket.SOL_SOCKET, socket.SO_SNDTIMEO, 1, 0)
    if not status then
        mp.msg.error(err)
        os.exit(1)
    end
end

function udp:connect(host, port)
    local host_info = socket.getaddrinfo(host, nil, { family = socket.AF_INET })
    if not host_info then
        mp.msg.error("Invalid host")
        os.exit(1)
    end

    self.dest = { family = socket.AF_INET, addr = host_info[1].addr, port = port }
    udp:listen(0)
end

function udp:send(datagram_pkd, dest)
    dest = dest or self.dest
    socket.sendto(self.fd, datagram_pkd, dest)
    print(datagram_pkd)
end

function udp:receive()
    local data, src = socket.recvfrom(self.fd, self.max_dg_size)

    if not data then
        return nil, src
    end

    if self.dest then
        if self.dest.addr ~= src.addr or self.dest.port ~= src.port then
            return nil, "dest doesent match source of datagram"
        end
    end

    return data, src
end

function udp:close()
    unistd.close(self.fd)
end

function udp:get_fd()
    return self.fd
end

return udp
