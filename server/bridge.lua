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

local PHONES = { 'qs-smartphone', 'qs-smartphone-pro' }

local function activePhone()
    if Config.Phone ~= 'auto' then
        return GetResourceState(Config.Phone) == 'started' and Config.Phone or nil
    end
    for _, name in ipairs(PHONES) do
        if GetResourceState(name) == 'started' then return name end
    end
end

--- Phone push notification when possible (Smartphone V3), ox_lib notification otherwise.
function Bridge.Notify(src, message, kind)
    local phone = activePhone()
    if phone then
        local ok, sent = pcall(function()
            return exports[phone]:sendPhoneNotification(src, {
                appId = Config.App.name,
                title = Config.App.label,
                text = message,
                closeTimeout = 5000,
            })
        end)
        if ok and sent ~= false then return end
    end
    TriggerClientEvent('ox_lib:notify', src, {
        title = Config.App.label,
        description = message,
        type = kind or 'inform',
    })
end

local function digits(v)
    return (tostring(v or ''):gsub('[^%d]', ''))
end

--- Resolve a phone number to a citizenid. See Config.PhoneLookup.
function Bridge.GetCitizenIdFromPhone(number)
    number = digits(number)
    if number == '' then return nil end

    -- 1) Online players, using the phone's GetCurrentPhoneNumber(source) export.
    local exp = Config.PhoneLookup.Export
    local phone = exp and (exp.resource == 'auto' and activePhone() or exp.resource)
    if phone and GetResourceState(phone) == 'started' then
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local ok, result = pcall(function()
                local res = exports[phone]
                return res[exp.name](res, src)
            end)
            if ok and result and digits(result) == number then
                return Bridge.GetCitizenId(src)
            end
        end
    end

    -- 2) Offline players: direct SQL lookup (adjust the table/columns in config.lua).
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
