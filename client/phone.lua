--[[
    Quasar smartphone integration.
    This is the ONLY file that talks to the phone resource. If your phone version uses a
    different custom-app API, change it here.

    The app UI is a normal web page (html/index.html) the phone shows in an iframe.
    The page talks to this resource through NUI callbacks (see client/main.lua), so it
    does not depend on any phone-specific messaging.
]]

local resource = GetCurrentResourceName()
local base = ('https://cfx-nui-%s/html/'):format(resource)

local function appData()
    local a = Config.App
    return {
        app = a.name,
        image = base .. 'icon.png',
        ui = base .. 'index.html',
        label = a.label,
        job = a.job,
        blockedJobs = a.blockedJobs,
        timeout = 5000,
        creator = a.creator,
        category = a.category,
        isGame = false,
        description = a.description,
        age = a.age,
        extraDescription = {
            { header = 'Prices', head = 'Live + server coins', image = base .. 'icon.png', footer = 'Real market prices and server-only coins' },
        },
        price = a.price,
        size = 2048,
        images = {},
        rating = 5.0,
    }
end

local phoneResources = {
    'qs-smartphone-pro',
    'qs-smartphone',
}

local function addApp(phone)
    if GetResourceState(phone) ~= 'started' then return false end
    local ok, added, err = pcall(function()
        return exports[phone]:addCustomApp(appData())
    end)
    if not ok then
        print(('[bdev-crypto] %s:addCustomApp failed: %s'):format(phone, tostring(added)))
        return false
    end
    if added == false then
        print(('[bdev-crypto] %s refused the app: %s'):format(phone, tostring(err)))
        return false
    end
    if Config.Debug then print('[bdev-crypto] app added to ' .. phone) end
    return true
end

local function register()
    if Config.Phone ~= 'auto' then return addApp(Config.Phone) end
    for _, phone in ipairs(phoneResources) do
        if addApp(phone) then return true end
    end
    print('[bdev-crypto] no supported Quasar phone found; the app was not added.')
    return false
end

local function unregister()
    for _, phone in ipairs(phoneResources) do
        if GetResourceState(phone) == 'started' then
            pcall(function() exports[phone]:removeCustomApp(Config.App.name) end)
        end
    end
end

-- Register on spawn / resource start, and again if the phone restarts.
CreateThread(function()
    Wait(1000)
    register()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    Wait(1000)
    register()
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == Config.Phone or (Config.Phone == 'auto' and (res == 'qs-smartphone-pro' or res == 'qs-smartphone')) then
        Wait(1000)
        register()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == resource then unregister() end
end)
