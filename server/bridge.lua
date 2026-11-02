-- Qbox (qbx_core) bridge. Everything framework-specific lives here.
Bridge = {}

local qbx = exports.qbx_core

function Bridge.GetPlayer(src)
    return qbx:GetPlayer(src)
end

function Bridge.GetCitizenId(src)
    local player = qbx:GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

function Bridge.GetName(src)
    local player = qbx:GetPlayer(src)
    if not player then return 'Unknown' end
    local ci = player.PlayerData.charinfo or {}
    return ('%s %s'):format(ci.firstname or '', ci.lastname or '')
end

function Bridge.GetMoney(src)
    local player = qbx:GetPlayer(src)
    if not player then return 0 end
    return player.PlayerData.money[Config.MoneyAccount] or 0
end

function Bridge.RemoveMoney(src, amount, reason)
    return qbx:RemoveMoney(src, Config.MoneyAccount, amount, reason) == true
end

function Bridge.AddMoney(src, amount, reason)
    return qbx:AddMoney(src, Config.MoneyAccount, amount, reason) == true
end

--- Returns the server id of an online player with this citizenid, or nil.
function Bridge.GetSourceByCitizenId(citizenid)
    local player = qbx:GetPlayerByCitizenId(citizenid)
    return player and player.PlayerData.source or nil
end

function Bridge.Notify(src, message, kind)
    TriggerClientEvent('ox_lib:notify', src, {
        title = Config.App.label,
        description = message,
        type = kind or 'inform',
    })
end

--- Resolve a phone number to a citizenid. See Config.PhoneLookup.
function Bridge.GetCitizenIdFromPhone(number)
    number = tostring(number or ''):gsub('[^%d]', '')
    if number == '' then return nil end

    local exp = Config.PhoneLookup.Export
    if exp and GetResourceState(exp.resource) == 'started' then
        local ok, result = pcall(function()
            local res = exports[exp.resource]
            return res[exp.name](res, number)
        end)
        if ok and result then return result end
    end

    local sql = Config.PhoneLookup.Sql
    if sql then
        local ok, result = pcall(MySQL.scalar.await,
            ('SELECT `%s` FROM `%s` WHERE REPLACE(REPLACE(`%s`, "-", ""), " ", "") = ? LIMIT 1')
                :format(sql.identifierColumn, sql.table, sql.numberColumn),
            { number })
        if ok and result then return result end
    end

    return nil
end
