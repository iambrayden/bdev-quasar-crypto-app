-- NUI bridge: the phone app page calls these with fetch('https://<resource>/<name>')
-- and each one forwards to the matching server callback.

local function proxy(name, ...)
    local ok, result = pcall(lib.callback.await, 'bdev-crypto:' .. name, false, ...)
    if not ok or type(result) ~= 'table' then
        return { ok = false, error = 'Server did not respond.' }
    end
    return result
end

RegisterNUICallback('getData', function(_, cb)
    cb(proxy('getData'))
end)

RegisterNUICallback('getChart', function(data, cb)
    cb(proxy('getChart', data.symbol, data.range))
end)

RegisterNUICallback('getTransactions', function(_, cb)
    cb(proxy('getTransactions'))
end)

RegisterNUICallback('buy', function(data, cb)
    cb(proxy('buy', data.symbol, data.usd))
end)

RegisterNUICallback('sell', function(data, cb)
    cb(proxy('sell', data.symbol, data.amount, data.all == true))
end)

RegisterNUICallback('send', function(data, cb)
    cb(proxy('send', data.target, data.symbol, data.amount))
end)

RegisterNUICallback('copy', function(data, cb)
    if type(data.text) == 'string' then
        lib.setClipboard(data.text)
        lib.notify({ title = Config.App.label, description = 'Wallet address copied', type = 'success' })
    end
    cb({ ok = true })
end)
