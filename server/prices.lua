-- Price engine: live CoinGecko prices for real coins, a random walk for simulated coins,
-- and in-memory chart history for both.
Prices = {}

local coins = {}      -- symbol -> state
local order = {}      -- symbols in config order

local GECKO_BASE = 'https://api.coingecko.com/api/v3'

local function debug(...)
    if Config.Debug then print('[bdev-crypto]', ...) end
end

local function now() return os.time() end

local function round(n, decimals)
    local m = 10 ^ (decimals or 8)
    return math.floor(n * m + 0.5) / m
end

-- Standard normal sample (Box-Muller)
local function gaussian()
    local u1 = math.max(math.random(), 1e-12)
    local u2 = math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function keepSeconds() return Config.History.KeepDays * 86400 end

local function trimHistory(state)
    local cutoff = now() - keepSeconds()
    local h = state.history
    local first = 1
    while h[first] and h[first].t < cutoff do first = first + 1 end
    if first > 1 then
        table.move(h, first, #h, 1)
        for i = #h - first + 2, #h do h[i] = nil end
    end
end

local function pushPoint(state, ts, price)
    local h = state.history
    local last = h[#h]
    if last and last.t >= ts then
        last.p = price
        return
    end
    h[#h + 1] = { t = ts, p = price }
end

--- Records a chart point for every coin with a price (called every Config.History.PointSeconds).
local function recordPoints()
    local ts = now()
    for _, symbol in ipairs(order) do
        local state = coins[symbol]
        if state.price then
            pushPoint(state, ts, state.price)
            trimHistory(state)
            if state.cfg.type == 'simulated' then
                DB.SaveHistoryPoint(symbol, ts, state.price)
            end
        end
    end
end

local function change24h(state)
    if state.cfg.type == 'real' and state.change24h then return state.change24h end
    local since = now() - 86400
    for _, point in ipairs(state.history) do
        if point.t >= since then
            if point.p > 0 and state.price then
                return (state.price - point.p) / point.p * 100
            end
            break
        end
    end
    return 0
end

---------------------------------------------------------------------
-- CoinGecko
---------------------------------------------------------------------
local function geckoGet(path, cb)
    local headers = { ['Accept'] = 'application/json' }
    if Config.CoinGecko.ApiKey ~= '' then
        headers['x-cg-demo-api-key'] = Config.CoinGecko.ApiKey
    end
    PerformHttpRequest(GECKO_BASE .. path, function(status, body)
        if status ~= 200 or not body then
            print(('[bdev-crypto] CoinGecko request failed (%s): %s'):format(tostring(status), path))
            return cb(nil)
        end
        local ok, data = pcall(json.decode, body)
        cb(ok and data or nil)
    end, 'GET', '', headers)
end

local function realCoins()
    local list = {}
    for _, symbol in ipairs(order) do
        if coins[symbol].cfg.type == 'real' then list[#list + 1] = coins[symbol] end
    end
    return list
end

local function refreshRealPrices()
    local list = realCoins()
    if #list == 0 then return end

    local ids = {}
    for i, state in ipairs(list) do ids[i] = state.cfg.geckoId end

    geckoGet(('/simple/price?ids=%s&vs_currencies=usd&include_24hr_change=true'):format(table.concat(ids, ',')),
        function(data)
            if not data then return end
            for _, state in ipairs(list) do
                local entry = data[state.cfg.geckoId]
                if entry and tonumber(entry.usd) then
                    state.price = round(entry.usd * (state.cfg.multiplier or 1.0), 8)
                    state.change24h = tonumber(entry.usd_24h_change) or 0
                    state.updated = now()
                end
            end
            debug('real prices refreshed')
        end)
end

local function seedRealHistory()
    for _, state in ipairs(realCoins()) do
        geckoGet(('/coins/%s/market_chart?vs_currency=usd&days=%d'):format(
            state.cfg.geckoId, Config.CoinGecko.SeedHistoryDays), function(data)
            if not data or type(data.prices) ~= 'table' then return end
            local seeded = {}
            for _, pair in ipairs(data.prices) do
                seeded[#seeded + 1] = {
                    t = math.floor(pair[1] / 1000),
                    p = round(pair[2] * (state.cfg.multiplier or 1.0), 8),
                }
            end
            -- Keep any live points recorded after the seed's last point.
            local lastSeed = seeded[#seeded] and seeded[#seeded].t or 0
            for _, point in ipairs(state.history) do
                if point.t > lastSeed then seeded[#seeded + 1] = point end
            end
            state.history = seeded
            if not state.price and seeded[#seeded] then state.price = seeded[#seeded].p end
            debug(('seeded %d history points for %s'):format(#seeded, state.cfg.symbol))
        end)
        Wait(2500) -- stay well under the free API rate limit
    end
end

---------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------
local function tickSimulated()
    for _, symbol in ipairs(order) do
        local state = coins[symbol]
        local c = state.cfg
        if c.type == 'simulated' and state.price then
            local logChange = (c.drift or 0) + (c.volatility or 0.01) * gaussian()
            if (c.reversion or 0) > 0 then
                logChange = logChange + c.reversion * (math.log(c.startPrice) - math.log(state.price))
            end
            state.price = round(math.max(c.minPrice or 0.0001, state.price * math.exp(logChange)), 8)
            state.updated = now()
        end
    end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
function Prices.Init()
    for _, c in ipairs(Config.Coins) do
        local symbol = c.symbol:upper()
        c.symbol = symbol
        coins[symbol] = { cfg = c, price = nil, history = {}, updated = 0 }
        order[#order + 1] = symbol

        if c.type == 'simulated' then
            local rows = DB.LoadHistory(symbol, now() - keepSeconds())
            for _, row in ipairs(rows) do
                pushPoint(coins[symbol], tonumber(row.ts), tonumber(row.price))
            end
            local last = coins[symbol].history[#coins[symbol].history]
            coins[symbol].price = last and last.p or c.startPrice
        end
    end

    CreateThread(function()
        refreshRealPrices()
        seedRealHistory()
    end)

    CreateThread(function()
        while true do
            Wait(Config.CoinGecko.RefreshSeconds * 1000)
            refreshRealPrices()
        end
    end)

    CreateThread(function()
        while true do
            Wait(Config.Simulation.TickSeconds * 1000)
            tickSimulated()
        end
    end)

    CreateThread(function()
        local lastPrune = 0
        while true do
            recordPoints()
            if now() - lastPrune > 3600 then
                DB.PruneHistory(now() - keepSeconds())
                lastPrune = now()
            end
            Wait(Config.History.PointSeconds * 1000)
        end
    end)
end

function Prices.Exists(symbol)
    return coins[symbol] ~= nil
end

function Prices.Get(symbol)
    local state = coins[symbol]
    return state and state.price or nil
end

function Prices.GetConfig(symbol)
    local state = coins[symbol]
    return state and state.cfg or nil
end

--- Market overview for the phone.
function Prices.GetMarket()
    local list = {}
    for _, symbol in ipairs(order) do
        local state = coins[symbol]
        list[#list + 1] = {
            symbol = symbol,
            name = state.cfg.name,
            color = state.cfg.color,
            type = state.cfg.type,
            price = state.price,
            change = change24h(state),
        }
    end
    return list
end

--- Downsampled chart points for a range (seconds).
function Prices.GetChart(symbol, rangeSeconds)
    local state = coins[symbol]
    if not state then return {} end

    local since = now() - rangeSeconds
    local points = {}
    for _, point in ipairs(state.history) do
        if point.t >= since then points[#points + 1] = point end
    end
    if state.price then points[#points + 1] = { t = now(), p = state.price } end

    local max = Config.History.MaxChartPoints
    if #points <= max then return points end

    local out = {}
    local step = #points / max
    for i = 1, max do
        out[i] = points[math.min(#points, math.floor(i * step))]
    end
    out[#out] = points[#points]
    return out
end

--- Admin: set a simulated coin's price. Returns ok, error.
function Prices.SetSimulated(symbol, price)
    local state = coins[symbol]
    if not state then return false, 'Unknown coin' end
    if state.cfg.type ~= 'simulated' then return false, 'Only simulated coins can be changed' end
    state.price = round(math.max(state.cfg.minPrice or 0.0001, price), 8)
    state.updated = now()
    pushPoint(state, now(), state.price)
    DB.SaveHistoryPoint(symbol, now(), state.price)
    return true
end
