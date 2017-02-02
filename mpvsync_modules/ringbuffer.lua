local RingBuffer = {
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

return RingBuffer
