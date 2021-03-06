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

local options = require "mp.options"
local server = require "mpvsync_modules/server"
local client = require "mpvsync_modules/client"

-- Default options
local _opts = {
        help = false,
        enabled = true,
        port = 32923,
        osd = true,
        host = "",
        wait = true,
        ipv6 = true,
        srv_client_timeout = 8,
        cli_syn_period = 5
}

-- Assert options before use it
local opts = {}

function opts:assert(_opts)
    local port = _opts.port
    if type(port) ~= "number" or (port < 0) or (port > 65535) then
        mp.msg.error("illegal port number")
        os.exit(1)
    end

    if type(_opts.host) ~= "string" then
        mp.msg.error("illegal host value")
        os.exit(1)
    end

    self.enabled            = _opts.enabled
    self.port               = _opts.port
    self.osd                = _opts.osd
    self.host               = _opts.host
    self.wait               = _opts.wait
    self.help               = _opts.help
    self.srv_client_timeout = _opts.srv_client_timeout
    self.cli_syn_period     = _opts.cli_syn_period
end

options.read_options(_opts, "mpvsync")
opts:assert(_opts)

if opts.help then
    mp.msg.info("mpvsync options:")
    for o, v in pairs(_opts) do
        mp.msg.info(type(v) .. "\tmpvsync-" .. o)
    end
    os.exit(1)
end

if opts.enabled then
    local event_loop
    if opts.host ~= "" then
        local cli = client:new(opts)
        event_loop = cli:get_event_loop()
    else
        local srv = server:new(opts)
        event_loop = srv:get_event_loop()
    end

    if event_loop then
        mp_event_loop = event_loop
    end
end
