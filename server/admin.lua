-- Admin commands (restricted to Config.AdminGroup)

local function reply(src, msg, kind)
    if src == 0 then return print('[bdev-crypto] ' .. msg) end
    TriggerClientEvent('ox_lib:notify', src, { title = Config.App.label, description = msg, type = kind or 'inform' })
end

local function simCoinParam(src, symbol)
    symbol = tostring(symbol or ''):upper()
    local cfg = Prices.GetConfig(symbol)
    if not cfg then reply(src, 'Unknown coin: ' .. symbol, 'error') return nil end
    if cfg.type ~= 'simulated' then reply(src, symbol .. ' tracks the real market and can\'t be changed.', 'error') return nil end
    return symbol
end

lib.addCommand('cryptoset', {
    help = 'Set the price of a simulated coin',
    restricted = Config.AdminGroup,
    params = {
        { name = 'coin', type = 'string', help = 'Coin symbol' },
        { name = 'price', type = 'number', help = 'New price in $' },
    },
}, function(src, args)
    local symbol = simCoinParam(src, args.coin)
    if not symbol then return end
    if args.price <= 0 then return reply(src, 'Price must be above 0', 'error') end
    local ok, err = Prices.SetSimulated(symbol, args.price)
    reply(src, ok and ('%s set to $%s'):format(symbol, Prices.Get(symbol)) or err, ok and 'success' or 'error')
end)

local function movePrice(src, args, direction)
    local symbol = simCoinParam(src, args.coin)
    if not symbol then return end
    local percent = args.percent
    if percent <= 0 or (direction < 0 and percent >= 100) then
        return reply(src, 'Invalid percent', 'error')
    end
    local newPrice = Prices.Get(symbol) * (1 + direction * percent / 100)
    local ok, err = Prices.SetSimulated(symbol, newPrice)
    reply(src, ok and ('%s is now $%s'):format(symbol, Prices.Get(symbol)) or err, ok and 'success' or 'error')
end

lib.addCommand('cryptopump', {
    help = 'Pump a simulated coin by a percentage',
    restricted = Config.AdminGroup,
    params = {
        { name = 'coin', type = 'string', help = 'Coin symbol' },
        { name = 'percent', type = 'number', help = 'Percent increase (e.g. 25)' },
    },
}, function(src, args) movePrice(src, args, 1) end)

lib.addCommand('cryptocrash', {
    help = 'Crash a simulated coin by a percentage',
    restricted = Config.AdminGroup,
    params = {
        { name = 'coin', type = 'string', help = 'Coin symbol' },
        { name = 'percent', type = 'number', help = 'Percent drop (e.g. 40)' },
    },
}, function(src, args) movePrice(src, args, -1) end)

lib.addCommand('cryptogive', {
    help = 'Give crypto to a player',
    restricted = Config.AdminGroup,
    params = {
        { name = 'target', type = 'playerId', help = 'Player server id' },
        { name = 'coin', type = 'string', help = 'Coin symbol' },
        { name = 'amount', type = 'number', help = 'Amount of coins' },
    },
}, function(src, args)
    local citizenid = Bridge.GetCitizenId(args.target)
    if not citizenid then return reply(src, 'Player not found', 'error') end
    local symbol = tostring(args.coin):upper()
    if exports[GetCurrentResourceName()]:AddCrypto(citizenid, symbol, args.amount, 'admin') then
        reply(src, ('Gave %s %s to %s'):format(args.amount, symbol, Bridge.GetName(args.target)), 'success')
        Bridge.Notify(args.target, ('You received %s %s'):format(args.amount, symbol), 'success')
    else
        reply(src, 'Failed. Check the coin and amount.', 'error')
    end
end)

lib.addCommand('cryptoprices', {
    help = 'Print current crypto prices',
    restricted = Config.AdminGroup,
}, function(src)
    for _, coin in ipairs(Prices.GetMarket()) do
        local cfg = Prices.GetConfig(coin.symbol)
        reply(src, ('%s: $%s (%.2f%%) [%s%s]'):format(coin.symbol, tostring(coin.price or 'n/a'), coin.change or 0,
            cfg.type == 'real' and 'live' or cfg.preset, cfg.custom and ', custom' or ''))
    end
end)

---------------------------------------------------------------------
-- Creating / removing coins in-game
---------------------------------------------------------------------
local function presetNames()
    local names = {}
    for name in pairs(Config.Presets) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- Creates a coin from a definition, saves it and returns ok, message.
local function createCoin(src, raw)
    raw = type(raw) == 'table' and raw or {}
    local def = {
        symbol = raw.symbol,
        name = raw.name,
        color = raw.color,
        icon = raw.icon,
        tag = raw.tag,
    }
    if raw.live or (raw.market and raw.market ~= '') or (raw.geckoId and raw.geckoId ~= '') then
        def.live = true
        def.market = raw.market
        def.geckoId = raw.geckoId
        def.multiplier = raw.multiplier
    else
        def.startPrice = raw.startPrice
        def.preset = raw.preset
    end

    local coin, err = Prices.AddCoin(def)
    if not coin then return false, err end

    def.symbol = coin.symbol
    DB.SaveCustomCoin(coin.symbol, def, src ~= 0 and Bridge.GetCitizenId(src) or 'console')
    return true, ('Created %s (%s)%s'):format(coin.name, coin.symbol,
        coin.type == 'real' and ' with live prices' or (' at $' .. tostring(Prices.Get(coin.symbol))))
end

lib.addCommand('cryptocreate', {
    help = 'Create a new coin (no arguments opens a form)',
    restricted = Config.AdminGroup,
    params = {
        { name = 'symbol', type = 'string', help = 'Symbol, e.g. RON', optional = true },
        { name = 'price', type = 'number', help = 'Start price in $', optional = true },
        { name = 'preset', type = 'string', help = 'stable / normal / volatile / meme', optional = true },
        { name = 'name', type = 'longString', help = 'Coin name', optional = true },
    },
}, function(src, args)
    if not args.symbol then
        if src == 0 then return reply(src, 'Usage: cryptocreate SYMBOL PRICE PRESET NAME') end
        return TriggerClientEvent('bdev-crypto:createCoinDialog', src, presetNames())
    end
    local ok, msg = createCoin(src, {
        symbol = args.symbol,
        startPrice = args.price,
        preset = args.preset and args.preset:lower() or 'normal',
        name = args.name or args.symbol,
    })
    reply(src, msg, ok and 'success' or 'error')
end)

-- Submitted from the /cryptocreate form.
lib.callback.register('bdev-crypto:createCoin', function(src, data)
    if not IsPlayerAceAllowed(src, 'command.cryptocreate') then return { ok = false, error = 'Not allowed' } end
    local ok, msg = createCoin(src, data)
    return { ok = ok, message = ok and msg or nil, error = not ok and msg or nil }
end)

lib.addCommand('cryptoremove', {
    help = 'Remove a coin created with /cryptocreate',
    restricted = Config.AdminGroup,
    params = {
        { name = 'coin', type = 'string', help = 'Coin symbol' },
        { name = 'force', type = 'string', help = 'Type "force" to also wipe everyone\'s holdings', optional = true },
    },
}, function(src, args)
    local symbol = tostring(args.coin):upper()
    local cfg = Prices.GetConfig(symbol)
    if not cfg then return reply(src, 'Unknown coin: ' .. symbol, 'error') end
    if not cfg.custom then
        return reply(src, symbol .. ' is defined in coins.lua. Remove it there and restart.', 'error')
    end

    local holders = DB.CountHolders(symbol)
    if holders > 0 and args.force ~= 'force' then
        return reply(src, ('%d player(s) still hold %s. Use /cryptoremove %s force to wipe their holdings.')
            :format(holders, symbol, symbol), 'error')
    end
    if holders > 0 then
        MySQL.query.await('DELETE FROM bdev_crypto_holdings WHERE coin = ?', { symbol })
    end
    Prices.RemoveCoin(symbol)
    DB.DeleteCustomCoin(symbol)
    reply(src, ('Removed %s'):format(symbol), 'success')
end)
