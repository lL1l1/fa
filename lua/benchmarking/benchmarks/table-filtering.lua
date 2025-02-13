-- DestructiveFilterRemove:     2.3214111328125
-- TableFilterUpvalued:         1.618164062
-- DestructiveFilterNilWhile:   0.708984375
-- AddToFilterByCount:          0.68408203125
-- DestructiveFilterNil2For:    0.677490234375
-- DestructiveFilterNilFor:     0.6591796875

local outerLoop = 1000000

local TableRemove = table.remove
local TableInsert = table.insert
local TableGetn = table.getn

local function TableClear(t)
    for i, _ in t do
        t[i] = nil
    end
end

local function CreateData()
    local data = {}
    for k = 1, 20 do
        data[k] = k
    end
    return data
end

local assert = assert
local function cmpInv(v) return v > 10 end
local function VerifyData(data)
    assert(TableGetn(data) == 10)
    assert(table.empty(table.filter(data, cmpInv)))
end

function AddToFilterByCount()

    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local filteredData = {}


    local sum = 0
    for _ = 1, outerLoop do
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        local i = 1
        for _, v in odata do
            if v > 10 then
                filteredData[i] = v
                i = i + 1
            end
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
        TableClear(filteredData)
    end

    return sum
end

function DestructiveFilterRemove()

    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local sum = 0
    for _ = 1, outerLoop do
        local data = table.copy(odata)
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        for i = TableGetn(data), 1, -1 do
            if data[i] <= 10 then
                TableRemove(data, i)
            end
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
    end

    return sum
end

function DestructiveFilterNilFor()

    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local sum = 0
    for _ = 1, outerLoop do
        local data = table.copy(odata)
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        local n = TableGetn(data)
        for i = n, 1, -1 do
            if data[i] <= 10 then
                data[i], data[n] = data[n], nil
                n = n - 1
            end
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
    end

    return sum
end

function DestructiveFilterNil2For()

    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local sum = 0
    for _ = 1, outerLoop do
        local data = table.copy(odata)
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        local n = TableGetn(data)
        for i = n, 1, -1 do
            if data[i] <= 10 then
                data[i] = data[n]
                data[n] = nil
                n = n - 1
            end
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
    end

    return sum
end

function DestructiveFilterNilWhile()

    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local sum = 0
    for _ = 1, outerLoop do
        local data = table.copy(odata)
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        local i = 1
        local n = TableGetn(data)
        while i < n do
            if data[i] <= 10 then
                data[i], data[n] = data[n], nil
                n = n - 1
            else
                i = i + 1
            end
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
    end

    return sum
end

-- local TableFilter = table.filter -- leaves nil holes in the table, so only good for k-v pairs not arrays

-- function TableFilterUpvalued()

--     local odata = {}
--     for k = 1, 20 do
--         odata[k] = k
--     end

--     local compFn = function(v)
--         return v <= 10
--     end
--     local filtered

--     local sum = 0
--     for _ = 1, outerLoop do
--         local data = table.copy(odata)
--         local start = GetSystemTimeSecondsOnlyForProfileUse()

--         filtered = TableFilter(data, compFn)

--         sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
--     end

--     return sum
-- end

function DestructiveFilterNil3For()
    local odata = {}
    for k = 1, 20 do
        odata[k] = k
    end

    local sum = 0
    for _ = 1, outerLoop do
        local data = table.copy(odata)
        local start = GetSystemTimeSecondsOnlyForProfileUse()

        for i, v in data do
            if v <= 10 then
                data[i] = nil
            end
        end
        local i = 1
        for _, v in data do
            data[i] = v
        end

        sum = sum + GetSystemTimeSecondsOnlyForProfileUse() - start
    end

    return sum

end
