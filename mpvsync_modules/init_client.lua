local socket = require "socket"
local ut = require "mpvsync_modules/utils"
local RingBuffer = require "mpvsync_modules/ringbuffer"

local debug = false

local reqn = 1
local ping_buff = RingBuffer:new(5)
local ping_avg = 0
local syn_sent = 0
local syn_sent_last = 0
local syn_lost = 0
local max_pos_error = 0.5
local state
local udp

local function connect(host, port)
    local ip, err = socket.dns.toip(host)
    udp = socket.udp()
    udp:setpeername(ip, port)
    udp:settimeout(1)

end

local function update_state()
    if not state then
        state = {}
    end

    state.pos   = mp.get_property_number("time-pos")
    state.speed = mp.get_property_number("speed")
    state.pause = mp.get_property_bool("pause") and 1 or 0

    if state.pos and state.speed and state.pause then
        return true
    else
        state = nil
    end

    return
end

local function syn_state(sv_st)
    if not sv_st then
        return
    end

    update_state()

    if state then
        if state.pause ~= sv_st.pause then
            local pause = sv_st.pause == 1 and true or false
            mp.set_property_bool("pause", pause)
            if pause then
                ut.mpvsync_osd("pause")
            else
                ut.mpvsync_osd("play")
            end
        end

        if state.speed ~= sv_st.speed then
            mp.set_property("speed", sv_st.speed)
            ut.mpvsync_osd("speed " .. sv_st.speed)
        end

        if state.pos ~= sv_st.pos then
            local diff = sv_st.pos + 0.5 * ping_avg - state.pos
            if math.abs(diff) > max_pos_error then
                mp.set_property("time-pos", sv_st.pos)
                ut.mpvsync_osd("seek " .. sv_st.pos - state.pos)
            end
        end
    end


end

local function req_send(reqtype)
    local datagram = {}
    datagram.reqtype = reqtype

    if reqtype == "SYN" then
        datagram.reqn = reqn

        reqn = (reqn + 1) % 10000
        if reqn == 0 then
            reqn = 1
        end

        syn_sent = syn_sent + 1
        syn_sent_last = mp.get_time()
    else
        datagram.reqn = 0
    end

    udp:send(ut.dg_pack(datagram))
end

local function update_ping(dg_reqn)
    if dg_reqn == 0 then
        return
    end

    if dg_reqn == reqn - 1 then
        local ping = mp.get_time() - syn_sent_last
        ping_buff:insert(ping)
        ping_avg = ping_buff:average()
    else
        syn_lost = syn_lost + 1
    end
end

local function dispatch(datagram_pkg)
    local datagram = ut.dg_unpack(datagram_pkg)

    if datagram.reqtype == "SYN" then
        update_ping(datagram.reqn)
        syn_state(ut.st_deserialize(datagram.data))
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
    mp.msg.info("ping: avg " .. ping_avg ..
                    " sent " .. syn_sent ..
                    " lost " .. syn_lost)
end

local callback = {}

function callback.syn()
    req_send("SYN")
    local datagram_pkg = udp:receive()
    if datagram_pkg then
        return dispatch(datagram_pkg)
    else
        return false
    end
end

function callback.disconnect()
    req_send("END")
end

local function init_client(_opts)
    opts  = _opts
    debug = opts.debug

    connect(opts.host, opts.port)

    mp.add_periodic_timer(10, callback.syn)
    mp.register_event("seek", callback.syn)
    mp.register_event("end-file", callback.disconnect)
    mp.observe_property("pause", "bool", callback.syn)

    mp.set_property_bool("pause", true)
    ut.mpvsync_osd("Connecting to " .. opts.host)

    if callback.syn() then
        ut.mpvsync_osd("Connection enstablished")
    end

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
