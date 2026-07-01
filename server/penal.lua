local IsAuthorized = function(src) return exports['cipher-mdt']:IsAuthorized(src) end

lib.callback.register('cipher-mdt:server:getPenalCodes', function(source)
    if not IsAuthorized(source) then return nil end
    local codes = MySQL.query.await('SELECT * FROM mdt_penal_codes WHERE active = 1 ORDER BY category, code', {})
    -- Group by category
    local grouped = {}
    for _, code in ipairs(codes) do
        if not grouped[code.category] then
            grouped[code.category] = { category = code.category, codes = {} }
        end
        grouped[code.category].codes[#grouped[code.category].codes + 1] = code
    end
    local result = {}
    for _, v in pairs(grouped) do result[#result + 1] = v end
    table.sort(result, function(a, b) return a.category < b.category end)
    return result
end)

-- Admin only: add/edit/remove penal codes
lib.callback.register('cipher-mdt:server:addPenalCode', function(source, data)
    if not IsAuthorized(source) then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if not player or player.PlayerData.job.grade.level < 3 then return false end

    MySQL.insert.await([[
        INSERT INTO mdt_penal_codes (category, code, name, type, fine_amount, jail_time, description)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { data.category, data.code, data.name, data.type, data.fine_amount or 0, data.jail_time or 0, data.description })
    return true
end)

lib.callback.register('cipher-mdt:server:updatePenalCode', function(source, data)
    if not IsAuthorized(source) then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if not player or player.PlayerData.job.grade.level < 3 then return false end

    MySQL.update.await([[
        UPDATE mdt_penal_codes SET category=?, code=?, name=?, type=?, fine_amount=?, jail_time=?, description=?
        WHERE id = ?
    ]], { data.category, data.code, data.name, data.type, data.fine_amount, data.jail_time, data.description, data.id })
    return true
end)

lib.callback.register('cipher-mdt:server:deletePenalCode', function(source, id)
    if not IsAuthorized(source) then return false end
    local player = exports['qbx_core']:GetPlayer(source)
    if not player or player.PlayerData.job.grade.level < 3 then return false end

    MySQL.update.await('UPDATE mdt_penal_codes SET active = 0 WHERE id = ?', { id })
    return true
end)
