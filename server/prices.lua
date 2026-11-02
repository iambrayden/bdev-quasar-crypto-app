-- Price engine: live prices (Coinbase or CoinGecko) for real coins, a random walk (with optional
-- pump/dump events) for simulated coins, and in-memory chart history for both.
Prices = {}

local coins = {}      -- symbol -> state
local order = {}      -- symbols in display order


local AUTO_COLORS = {
    '#e84393', '#00b894', '#0984e3', '#fdcb6e', '#6c5ce7', '#e17055',
    '#00cec9', '#d63031', '#a29bfe', '#fab1a0', '#55efc4', '#ff7675',
}

local function debug(...)
    if Config.Debug then print('[bdev-crypto]', ...) end
end

local function now() return os.time() end

--- Rounds to 10 significant digits so tiny meme-coin prices (0.00000123) keep precision.
local function roundPrice(p)
    if not p or p <= 0 then return 0 end
    local mag = math.floor(math.log(p, 10))
    local decimals = math.max(0, math.min(14, 9 - mag))
    local m = 10 ^ decimals
    return math.floor(p * m + 0.5) / m
end
Prices.RoundPrice = roundPrice

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
-- Coin definitions
---------------------------------------------------------------------
local function autoColor(symbol)
    local hash = 0
    for i = 1, #symbol do hash = (hash * 31 + symbol:byte(i)) % 2147483647 end
    return AUTO_COLORS[hash % #AUTO_COLORS + 1]
end

--- Validates a coin definition and fills in defaults / preset values.
--- Returns the normalized coin, or nil and an error message.
function Prices.Normalize(raw)
    if type(raw) ~= 'table' then return nil, 'Invalid coin' end
    local symbol = type(raw.symbol) == 'string' and raw.symbol:upper():gsub('%s', '') or ''
    if not symbol:match('^[A-Z0-9]+$') or #symbol < 2 or #symbol > 8 then
        return nil, 'Symbol must be 2-8 letters/numbers'
    end
    local name = type(raw.name) == 'string' and raw.name:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if #name < 2 or #name > 32 then return nil, 'Name must be 2-32 characters' end

    local c = {
        symbol = symbol,
        name = name,
        color = (type(raw.color) == 'string' and raw.color:match('^#%x%x%x%x%x%x$')) and raw.color or autoColor(symbol),
        icon = type(raw.icon) == 'string' and raw.icon ~= '' and raw.icon or nil,
        tag = type(raw.tag) == 'string' and raw.tag ~= '' and raw.tag:upper():sub(1, 8) or nil,
        custom = raw.custom == true,
    }

    local hasGecko = type(raw.geckoId) == 'string' and raw.geckoId ~= ''
    local hasMarket = type(raw.market) == 'string' and raw.market ~= ''
    if raw.live == true or hasGecko or hasMarket then
        c.type = 'real'
        -- Coinbase market, e.g. 'BTC-USD' (defaults to SYMBOL-USD)
        c.market = hasMarket and raw.market:upper() or (symbol .. '-USD')
        if not c.market:match('^[%w]+%-[%w]+$') then return nil, 'Invalid market (use e.g. BTC-USD)' end
        if hasGecko then
            if not raw.geckoId:match('^[%w%-%.]+$') then return nil, 'Invalid CoinGecko id' end
            c.geckoId = raw.geckoId:lower()
        end
        if Prices.Source() == 'coingecko' and not c.geckoId then
            return nil, 'needs a geckoId when Config.PriceSource is coingecko'
        end
        c.multiplier = tonumber(raw.multiplier) or 1.0
        if c.multiplier <= 0 then return nil, 'Multiplier must be above 0' end
        return c
    end

    c.type = 'simulated'
    c.startPrice = tonumber(raw.startPrice)
    if not c.startPrice or c.startPrice <= 0 then return nil, 'Start price must be above 0' end

    c.preset = raw.preset or 'normal'
    local preset = (Config.Presets or {})[c.preset]
    if not preset then return nil, ('Unknown preset "%s"'):format(tostring(c.preset)) end

    local function pick(key, default)
        if raw[key] ~= nil then return raw[key] end
        if preset[key] ~= nil then return preset[key] end
        return default
    end
    c.volatility = tonumber(pick('volatility', 0.01)) or 0.01
    c.drift = tonumber(pick('drift', 0)) or 0
    c.reversion = tonumber(pick('reversion', 0)) or 0
    c.floor = tonumber(pick('floor', 0.01)) or 0.01
    c.minPrice = roundPrice(c.startPrice * c.floor)
    c.events = pick('events', nil)
    c.tag = c.tag or (preset.tag and preset.tag:upper() or nil)
    return c
end

---------------------------------------------------------------------
-- Live price sources
---------------------------------------------------------------------
-- Each source fetches prices for a list of coin states and a chart history for one coin.
-- HTTP calls are synchronous (promise + Citizen.Await), so they must run inside a thread.

local function httpJson(url, headers)
    local p = promise.new()
    PerformHttpRequest(url, function(status, body)
        p:resolve({ status = status, body = body })
    end, 'GET', '', headers or {})
    local res = Citizen.Await(p)
    if res.status ~= 200 or not res.body then return nil, res.status end
    local ok, data = pcall(json.decode, res.body)
    if not ok then return nil, 'bad json' end
    return data
end

local Sources = {}

-- Coinbase Exchange public API: free, no key, no monthly cap (about 10 requests/second).
Sources.coinbase = {
    base = 'https://api.exchange.coinbase.com',
    headers = { ['Accept'] = 'application/json', ['User-Agent'] = 'bdev-quasar-crypto-app' },

    --- Returns price, change24h for one coin, or nil and an error.
    quote = function(self, state)
        local data, err = httpJson(('%s/products/%s/stats'):format(self.base, state.cfg.market), self.headers)
        local last = data and tonumber(data.last)
        if not last then return nil, ('Coinbase has no %s market (%s)'):format(state.cfg.market, tostring(err)) end
        local open = tonumber(data.open)
        return last, (open and open > 0) and (last - open) / open * 100 or 0
    end,

    refresh = function(self, list)
        for i, state in ipairs(list) do
            local price, change = self:quote(state)
            if price then
                state.price = roundPrice(price * state.cfg.multiplier)
                state.change24h = change
                state.updated = now()
            else
                print('[bdev-crypto] ' .. tostring(change))
            end
            if i < #list then Wait(150) end -- stay well under the rate limit
        end
    end,

    history = function(self, state, days)
        local data = httpJson(('%s/products/%s/candles?granularity=3600'):format(self.base, state.cfg.market), self.headers)
        if type(data) ~= 'table' then return nil end
        local since = now() - days * 86400
        local points = {}
        -- candles are [time, low, high, open, close, volume], newest first
        for i = #data, 1, -1 do
            local c = data[i]
            if type(c) == 'table' and tonumber(c[1]) and tonumber(c[1]) >= since and tonumber(c[5]) then
                points[#points + 1] = { t = tonumber(c[1]), p = roundPrice(tonumber(c[5]) * state.cfg.multiplier) }
            end
        end
        return points
    end,

    historyDelay = 300,
}

-- CoinGecko: the free Demo key allows 10,000 calls/month, so keep RefreshSeconds at 300 or more.
Sources.coingecko = {
    base = 'https://api.coingecko.com/api/v3',

    headers = function()
        local h = { ['Accept'] = 'application/json' }
        if (Config.CoinGecko.ApiKey or '') ~= '' then h['x-cg-demo-api-key'] = Config.CoinGecko.ApiKey end
        return h
    end,

    quote = function(self, state)
        self:refresh({ state })
        if state.price then return state.price, state.change24h end
        return nil, ('CoinGecko has no price for "%s"'):format(tostring(state.cfg.geckoId))
    end,

    refresh = function(self, list)
        local ids, seen = {}, {}
        for _, state in ipairs(list) do
            if not seen[state.cfg.geckoId] then
                ids[#ids + 1] = state.cfg.geckoId
                seen[state.cfg.geckoId] = true
            end
        end
        local data, err = httpJson(('%s/simple/price?ids=%s&vs_currencies=usd&include_24hr_change=true&precision=full')
            :format(self.base, table.concat(ids, ',')), self.headers())
        if not data then return print(('[bdev-crypto] CoinGecko request failed (%s)'):format(tostring(err))) end
        for _, state in ipairs(list) do
            local entry = data[state.cfg.geckoId]
            if entry and tonumber(entry.usd) then
                state.price = roundPrice(entry.usd * state.cfg.multiplier)
                state.change24h = tonumber(entry.usd_24h_change) or 0
                state.updated = now()
            end
        end
    end,

    history = function(self, state, days)
        local data = httpJson(('%s/coins/%s/market_chart?vs_currency=usd&days=%d')
            :format(self.base, state.cfg.geckoId, days), self.headers())
        if not data or type(data.prices) ~= 'table' then return nil end
        local points = {}
        for _, pair in ipairs(data.prices) do
            points[#points + 1] = { t = math.floor(pair[1] / 1000), p = roundPrice(pair[2] * state.cfg.multiplier) }
        end
        return points
    end,

    historyDelay = 6000,
}

function Prices.Source()
    local name = tostring(Config.PriceSource or 'coinbase'):lower()
    return Sources[name] and name or 'coinbase'
end

local function source() return Sources[Prices.Source()] end

local function realCoins(only)
    local list = {}
    for _, symbol in ipairs(order) do
        local state = coins[symbol]
        if state.cfg.type == 'real' and (not only or only == symbol) then list[#list + 1] = state end
    end
    return list
end

local function refreshRealPrices()
    local list = realCoins()
    if #list > 0 then source():refresh(list) end
end

local function seedHistory(state)
    local seeded = source():history(state, Config.LivePrices.SeedHistoryDays)
    if not seeded or #seeded == 0 then return end
    -- Keep any live points recorded after the seed's last point.
    local lastSeed = seeded[#seeded].t
    for _, point in ipairs(state.history) do
        if point.t > lastSeed then seeded[#seeded + 1] = point end
    end
    state.history = seeded
    if not state.price then state.price = seeded[#seeded].p end
    debug(('seeded %d history points for %s'):format(#seeded, state.cfg.symbol))
end

local function seedAllHistory()
    for _, state in ipairs(realCoins()) do
        if coins[state.cfg.symbol] then seedHistory(state) end
        Wait(source().historyDelay)
    end
end

---------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------
local function announce(state, pumped, percent)
    if not Config.Simulation.AnnounceEvents then return end
    local c = state.cfg
    TriggerClientEvent('ox_lib:notify', -1, {
        title = Config.App.label,
        description = pumped
            and ('%s (%s) is mooning! +%d%%'):format(c.name, c.symbol, math.floor(percent))
            or ('%s (%s) just crashed! -%d%%'):format(c.name, c.symbol, math.floor(percent)),
        type = pumped and 'success' or 'error',
        duration = 7000,
    })
end

local function tickSimulated()
    for _, symbol in ipairs(order) do
        local state = coins[symbol]
        local c = state.cfg
        if c.type == 'simulated' and state.price then
            local logChange = c.drift + c.volatility * gaussian()
            if c.reversion > 0 then
                logChange = logChange + c.reversion * (math.log(c.startPrice) - math.log(state.price))
            end
            local price = state.price * math.exp(logChange)

            local ev = c.events
            if type(ev) == 'table' and math.random() < (ev.chance or 0) then
                local pumped = math.random() < 0.5
                local range = pumped and ev.pump or ev.dump
                if type(range) == 'table' then
                    local percent = range[1] + math.random() * (range[2] - range[1])
                    price = price * (pumped and (1 + percent / 100) or math.max(0.01, 1 - percent / 100))
                    announce(state, pumped, percent)
                    debug(('%s event: %s %.1f%%'):format(symbol, pumped and 'pump' or 'dump', percent))
                end
            end

            state.price = roundPrice(math.max(c.minPrice, price))
            state.updated = now()
        end
    end
end

---------------------------------------------------------------------
-- Coin registry
---------------------------------------------------------------------
local function register(c)
    local state = { cfg = c, price = nil, history = {}, updated = 0 }
    coins[c.symbol] = state
    order[#order + 1] = c.symbol

    if c.type == 'simulated' then
        local rows = DB.LoadHistory(c.symbol, now() - keepSeconds())
        for _, row in ipairs(rows) do
            pushPoint(state, tonumber(row.ts), tonumber(row.price))
        end
        local last = state.history[#state.history]
        state.price = last and last.p or c.startPrice
        if not last then
            pushPoint(state, now(), state.price)
            DB.SaveHistoryPoint(c.symbol, now(), state.price)
        end
    end
    return state
end

--- Adds a coin at runtime (used by /cryptocreate). raw is a coin definition like in coins.lua.
function Prices.AddCoin(raw)
    local c, err = Prices.Normalize(raw)
    if not c then return nil, err end
    c.custom = true
    if coins[c.symbol] then return nil, c.symbol .. ' already exists' end

    -- Check the live market exists before adding the coin.
    local probe
    if c.type == 'real' then
        probe = { cfg = c, history = {} }
        local price, change = source():quote(probe)
        if not price then return nil, change end
        probe.price = roundPrice(price * c.multiplier)
        probe.change24h = change
    end

    local state = register(c)
    if probe then
        state.price, state.change24h, state.updated = probe.price, probe.change24h, now()
        CreateThread(function() seedHistory(state) end)
    end
    return c
end

function Prices.RemoveCoin(symbol)
    if not coins[symbol] then return false end
    coins[symbol] = nil
    for i, s in ipairs(order) do
        if s == symbol then table.remove(order, i) break end
    end
    return true
end

---------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------
--- customCoins: coin definitions created in-game (stored in the database).
function Prices.Init(customCoins)
    local function load(raw, origin)
        local c, err = Prices.Normalize(raw)
        if not c then
            return print(('[bdev-crypto] skipped %s coin %s: %s'):format(origin, tostring(raw.symbol), err))
        end
        if coins[c.symbol] then
            return print(('[bdev-crypto] skipped duplicate %s coin %s'):format(origin, c.symbol))
        end
        register(c)
    end

    local function safeLoad(raw, origin)
        local ok, err = pcall(load, raw, origin)
        if not ok then
            print(('^1[bdev-crypto] error loading %s coin %s: %s^7'):format(origin, tostring(raw and raw.symbol), tostring(err)))
        end
    end

    if type(Config.Coins) ~= 'table' or type(Config.Presets) ~= 'table' then
        print('^1[bdev-crypto] coins.lua was not loaded. Make sure fxmanifest.lua lists \'coins.lua\' under shared_scripts.^7')
    end
    for _, raw in ipairs(Config.Coins or {}) do safeLoad(raw, 'config') end
    for _, raw in ipairs(customCoins or {}) do raw.custom = true; safeLoad(raw, 'custom') end

    CreateThread(function()
        refreshRealPrices()
        seedAllHistory()
    end)

    CreateThread(function()
        while true do
            Wait(math.max(30, Config.LivePrices.RefreshSeconds) * 1000)
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
            Wait(Config.History.PointSeconds * 1000)
            local ts = now()
            for _, symbol in ipairs(order) do
                local state = coins[symbol]
                if state.price then
                    pushPoint(state, ts, state.price)
                    trimHistory(state)
                    if state.cfg.type == 'simulated' then DB.SaveHistoryPoint(symbol, ts, state.price) end
                end
            end
            if ts - lastPrune > 3600 then
                DB.PruneHistory(ts - keepSeconds())
                lastPrune = ts
            end
        end
    end)

    return #order
end

---------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------
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
        local c = state.cfg
        list[#list + 1] = {
            symbol = symbol,
            name = c.name,
            color = c.color,
            icon = c.icon,
            tag = c.tag,
            type = c.type,
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
    state.price = roundPrice(math.max(state.cfg.minPrice, price))
    state.updated = now()
    pushPoint(state, now(), state.price)
    DB.SaveHistoryPoint(symbol, now(), state.price)
    return true
end
