math.randomseed(os.time())

local busy = {}       -- citizenid -> true while a trade is processing
local lastAction = {} -- src -> GetGameTimer() of last trade action

local function round(n, decimals)
    local m = 10 ^ (decimals or 8)
    return math.floor(n * m + 0.5) / m
end

-- Floors a coin amount to 8 decimals (fewer for huge meme-coin amounts, so we stay within
-- double precision). The small epsilon absorbs float error (0.0197 * 1e8 = 1969999.9999...).
local function floor8(n)
    if n <= 0 then return 0 end
    local intDigits = math.max(1, math.floor(math.log(n, 10)) + 1)
    local decimals = math.max(0, math.min(8, 15 - intDigits))
    local m = 10 ^ decimals
    return math.floor(n * m + 1e-6) / m
end

local function rateLimited(src)
    local t = GetGameTimer()
    if lastAction[src] and t - lastAction[src] < Config.Trading.Cooldown then return true end
    lastAction[src] = t
    return false
end

--- Runs fn while holding a per-character lock so trades can't interleave.
local function withLock(citizenid, fn)
    if busy[citizenid] then return { ok = false, error = 'Please wait for your last action to finish.' } end
    busy[citizenid] = true
    local ok, result = pcall(fn)
    busy[citizenid] = nil
    if not ok then
        print('[bdev-crypto] error: ' .. tostring(result))
        return { ok = false, error = 'Something went wrong. Try again.' }
    end
    return result
end

local function fail(msg) return { ok = false, error = msg } end

local function cleanSymbol(symbol)
    if type(symbol) ~= 'string' then return nil end
    symbol = symbol:upper()
    return Prices.Exists(symbol) and symbol or nil
end

local function cleanNumber(n)
    n = tonumber(n)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return n
end

---------------------------------------------------------------------
-- Wallet overview
---------------------------------------------------------------------
local function buildWallet(src, citizenid)
    local holdings = DB.GetHoldings(citizenid)
    local list, totalValue, totalInvested = {}, 0, 0
    for _, coin in ipairs(Prices.GetMarket()) do
        local h = holdings[coin.symbol]
        if h and h.amount > 0 then
            local value = (coin.price or 0) * h.amount
            totalValue = totalValue + value
            totalInvested = totalInvested + h.invested
            list[#list + 1] = {
                symbol = coin.symbol,
                name = coin.name,
                color = coin.color,
                amount = h.amount,
                invested = h.invested,
                value = value,
                price = coin.price,
            }
        end
    end
    return {
        address = DB.GetOrCreateAddress(citizenid),
        holdings = list,
        totalValue = totalValue,
        totalInvested = totalInvested,
        balance = Bridge.GetMoney(src),
    }
end

lib.callback.register('bdev-crypto:getData', function(src)
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('No character loaded') end
    return {
        ok = true,
        market = Prices.GetMarket(),
        wallet = buildWallet(src, citizenid),
        settings = {
            tradeFee = Config.Trading.FeePercent,
            transferFee = Config.Transfers.FeePercent,
            transfersEnabled = Config.Transfers.Enabled,
            allowPhone = Config.Transfers.AllowPhoneNumber,
            minBuy = Config.Trading.MinBuy,
            maxBuy = Config.Trading.MaxBuy,
        },
    }
end)

local RANGES = { ['1H'] = 3600, ['24H'] = 86400, ['7D'] = 604800 }

lib.callback.register('bdev-crypto:getChart', function(src, symbol, range)
    symbol = cleanSymbol(symbol)
    if not symbol then return fail('Unknown coin') end
    return { ok = true, points = Prices.GetChart(symbol, RANGES[range] or RANGES['24H']) }
end)

lib.callback.register('bdev-crypto:getTransactions', function(src)
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('No character loaded') end
    local rows = DB.GetTransactions(citizenid, Config.TransactionHistoryLimit)
    for _, row in ipairs(rows) do
        row.amount = tonumber(row.amount)
        row.price = tonumber(row.price)
        row.usd = tonumber(row.usd)
        row.fee = tonumber(row.fee)
        row.ts = tonumber(row.ts)
    end
    return { ok = true, transactions = rows }
end)

---------------------------------------------------------------------
-- Buy: player spends `usd` dollars (fee included)
---------------------------------------------------------------------
lib.callback.register('bdev-crypto:buy', function(src, symbol, usd)
    if rateLimited(src) then return fail('Slow down.') end
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('No character loaded') end
    symbol = cleanSymbol(symbol)
    usd = cleanNumber(usd)
    if not symbol then return fail('Unknown coin') end
    if not usd then return fail('Invalid amount') end
    usd = math.floor(usd)
    if usd < Config.Trading.MinBuy then return fail(('Minimum buy is $%d'):format(Config.Trading.MinBuy)) end
    if usd > Config.Trading.MaxBuy then return fail(('Maximum buy is $%d'):format(Config.Trading.MaxBuy)) end

    return withLock(citizenid, function()
        local price = Prices.Get(symbol)
        if not price or price <= 0 then return fail('Price unavailable right now.') end
        if Bridge.GetMoney(src) < usd then return fail('Insufficient funds.') end

        local fee = round(usd * Config.Trading.FeePercent / 100, 2)
        local coinsOut = floor8((usd - fee) / price)
        if coinsOut <= 0 then return fail('Amount too small.') end

        if not Bridge.RemoveMoney(src, usd, ('crypto-buy-%s'):format(symbol)) then
            return fail('Insufficient funds.')
        end
        DB.AddCoins(citizenid, symbol, coinsOut, usd)
        DB.LogTransaction(citizenid, { type = 'buy', coin = symbol, amount = coinsOut, price = price, usd = usd, fee = fee })

        return { ok = true, message = ('Bought %s %s'):format(coinsOut, symbol) }
    end)
end)

---------------------------------------------------------------------
-- Sell: player sells `amount` coins (or everything when sellAll is true)
---------------------------------------------------------------------
lib.callback.register('bdev-crypto:sell', function(src, symbol, amount, sellAll)
    if rateLimited(src) then return fail('Slow down.') end
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('No character loaded') end
    symbol = cleanSymbol(symbol)
    if not symbol then return fail('Unknown coin') end

    return withLock(citizenid, function()
        local price = Prices.Get(symbol)
        if not price or price <= 0 then return fail('Price unavailable right now.') end

        local holding = DB.GetHolding(citizenid, symbol)
        if sellAll then
            amount = holding.amount
        else
            amount = cleanNumber(amount)
            if not amount then return fail('Invalid amount') end
            amount = floor8(amount)
        end
        if amount <= 0 then return fail('Invalid amount') end
        if amount > holding.amount then return fail('You don\'t have that many coins.') end

        local gross = amount * price
        local fee = gross * Config.Trading.FeePercent / 100
        local payout = math.floor(gross - fee)
        if payout < Config.Trading.MinSellValue then
            return fail(('Minimum sell value is $%d'):format(Config.Trading.MinSellValue))
        end

        local investedReduction = holding.amount > 0 and round(holding.invested * (amount / holding.amount), 2) or 0
        if not DB.RemoveCoins(citizenid, symbol, amount, investedReduction) then
            return fail('You don\'t have that many coins.')
        end
        if not Bridge.AddMoney(src, payout, ('crypto-sell-%s'):format(symbol)) then
            -- Refund coins if the payout failed for any reason.
            DB.AddCoins(citizenid, symbol, amount, investedReduction)
            return fail('Payment failed. Your coins were returned.')
        end
        DB.LogTransaction(citizenid, {
            type = 'sell', coin = symbol, amount = amount, price = price, usd = payout, fee = round(fee, 2),
        })

        return { ok = true, message = ('Sold %s %s for $%d'):format(amount, symbol, payout) }
    end)
end)

---------------------------------------------------------------------
-- Send coins to another player by wallet address or phone number
---------------------------------------------------------------------
lib.callback.register('bdev-crypto:send', function(src, target, symbol, amount)
    if not Config.Transfers.Enabled then return fail('Transfers are disabled.') end
    if rateLimited(src) then return fail('Slow down.') end
    local citizenid = Bridge.GetCitizenId(src)
    if not citizenid then return fail('No character loaded') end
    symbol = cleanSymbol(symbol)
    amount = cleanNumber(amount)
    if not symbol then return fail('Unknown coin') end
    if not amount or amount <= 0 then return fail('Invalid amount') end
    amount = floor8(amount)
    if amount <= 0 then return fail('Invalid amount') end
    if type(target) ~= 'string' or #target < 3 or #target > 64 then return fail('Enter a wallet address or phone number.') end

    target = target:gsub('%s', '')
    local targetCid
    if target:match('^0[xX]%x+$') then
        targetCid = DB.GetCitizenIdByAddress(target)
    elseif Config.Transfers.AllowPhoneNumber then
        targetCid = Bridge.GetCitizenIdFromPhone(target)
        -- Make sure the target has a wallet so it shows up correctly.
        if targetCid then DB.GetOrCreateAddress(targetCid) end
    end
    if not targetCid then
        return fail(target:match('^0[xX]') and 'No wallet with that address.'
            or 'No online player with that number. Try their wallet address.')
    end
    if targetCid == citizenid then return fail('You can\'t send coins to yourself.') end

    return withLock(citizenid, function()
        local holding = DB.GetHolding(citizenid, symbol)
        if amount > holding.amount then return fail('You don\'t have that many coins.') end

        local fee = floor8(amount * Config.Transfers.FeePercent / 100)
        local received = floor8(amount - fee)
        if received <= 0 then return fail('Amount too small.') end

        local investedReduction = holding.amount > 0 and round(holding.invested * (amount / holding.amount), 2) or 0
        if not DB.RemoveCoins(citizenid, symbol, amount, investedReduction) then
            return fail('You don\'t have that many coins.')
        end

        -- The recipient's cost basis is the coins' current market value.
        local price = Prices.Get(symbol) or 0
        DB.AddCoins(targetCid, symbol, received, round(received * price, 2))

        local fromAddress = DB.GetOrCreateAddress(citizenid)
        local toAddress = DB.GetOrCreateAddress(targetCid)
        DB.LogTransaction(citizenid, {
            type = 'send', coin = symbol, amount = amount, price = price, fee = fee, counterparty = toAddress,
        })
        DB.LogTransaction(targetCid, {
            type = 'receive', coin = symbol, amount = received, price = price, counterparty = fromAddress,
        })

        local targetSrc = Bridge.GetSourceByCitizenId(targetCid)
        if targetSrc then
            Bridge.Notify(targetSrc, ('You received %s %s'):format(received, symbol), 'success')
        end

        return { ok = true, message = ('Sent %s %s'):format(amount, symbol) }
    end)
end)

AddEventHandler('playerDropped', function()
    lastAction[source] = nil
end)

---------------------------------------------------------------------
-- Exports for other resources (e.g. the upcoming mining machines)
---------------------------------------------------------------------

--- Give coins to a character. reason is stored as the transaction type (e.g. 'mined').
exports('AddCrypto', function(citizenid, symbol, amount, reason)
    symbol = cleanSymbol(symbol)
    amount = cleanNumber(amount)
    if not citizenid or not symbol or not amount or amount <= 0 then return false end
    amount = floor8(amount)
    local price = Prices.Get(symbol) or 0
    DB.GetOrCreateAddress(citizenid)
    DB.AddCoins(citizenid, symbol, amount, round(amount * price, 2))
    DB.LogTransaction(citizenid, { type = reason or 'deposit', coin = symbol, amount = amount, price = price })
    return true
end)

--- Take coins from a character. Returns false if they don't have enough.
exports('RemoveCrypto', function(citizenid, symbol, amount, reason)
    symbol = cleanSymbol(symbol)
    amount = cleanNumber(amount)
    if not citizenid or not symbol or not amount or amount <= 0 then return false end
    amount = floor8(amount)
    local holding = DB.GetHolding(citizenid, symbol)
    if amount > holding.amount then return false end
    local investedReduction = round(holding.invested * (amount / holding.amount), 2)
    if not DB.RemoveCoins(citizenid, symbol, amount, investedReduction) then return false end
    DB.LogTransaction(citizenid, {
        type = reason or 'withdraw', coin = symbol, amount = amount, price = Prices.Get(symbol) or 0,
    })
    return true
end)

exports('GetCryptoBalance', function(citizenid, symbol)
    symbol = cleanSymbol(symbol)
    if not citizenid or not symbol then return 0 end
    return DB.GetHolding(citizenid, symbol).amount
end)

exports('GetCryptoPrice', function(symbol)
    symbol = cleanSymbol(symbol)
    return symbol and Prices.Get(symbol) or nil
end)

---------------------------------------------------------------------
CreateThread(function()
    DB.Init()
    local count = Prices.Init(DB.LoadCustomCoins())
    print(('[bdev-crypto] started with %d coins'):format(count))
end)
