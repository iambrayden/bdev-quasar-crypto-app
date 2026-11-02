-- Admin commands (restricted to Config.AdminGroup)

local function reply(src, msg, kind)
    if src == 0 then return print('[bdev-crypto] ' .. msg) end
    Bridge.Notify(src, msg, kind)
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
        reply(src, ('%s: $%s (%.2f%%)'):format(coin.symbol, tostring(coin.price or 'n/a'), coin.change or 0))
    end
end)
