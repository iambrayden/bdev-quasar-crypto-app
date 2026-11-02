Config = {}

Config.Debug = false

---------------------------------------------------------------------
-- Phone integration
---------------------------------------------------------------------
-- 'auto' tries qs-smartphone-pro first, then legacy qs-smartphone.
-- Force one with 'qs-smartphone-pro' or 'qs-smartphone'.
Config.Phone = 'auto'

Config.App = {
    name = 'bdev-crypto',          -- internal app id (must be unique on the phone)
    label = 'Crypto',
    description = 'Buy, sell and send cryptocurrency.',
    category = 'finance',          -- app store category
    creator = 'bdev',
    age = '18+',
    job = false,                   -- false = everyone, or a job name string
    blockedJobs = {},
    price = 0,                     -- app store price
}

---------------------------------------------------------------------
-- Money / trading
---------------------------------------------------------------------
Config.MoneyAccount = 'bank'

Config.Trading = {
    FeePercent = 1.5,              -- % fee on buys and sells (0 to disable)
    MinBuy = 10,                   -- minimum $ per buy
    MaxBuy = 1000000,              -- maximum $ per buy
    MinSellValue = 1,              -- minimum $ value of a sell
    Cooldown = 1500,               -- ms between trade actions per player
}

Config.Transfers = {
    Enabled = true,
    FeePercent = 0.5,              -- % of sent coins burned as a network fee (0 to disable)
    AllowPhoneNumber = true,       -- allow sending by phone number (see Config.GetCitizenIdFromPhone)
}

Config.TransactionHistoryLimit = 50

---------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------
-- Real coins: prices come from CoinGecko (your FiveM server needs outbound access to api.coingecko.com).
Config.CoinGecko = {
    ApiKey = '',                   -- optional free "demo" API key (raises rate limits)
    RefreshSeconds = 90,           -- how often to refresh live prices
    SeedHistoryDays = 7,           -- pull this many days of real history on start for charts
}

-- Simulated coins tick on the server.
Config.Simulation = {
    TickSeconds = 30,
}

-- History kept for charts
Config.History = {
    PointSeconds = 60,             -- record a chart point every N seconds
    KeepDays = 7,
    MaxChartPoints = 150,          -- points sent to the phone per chart
}

--[[
    Coins
    type = 'real'      -> geckoId is required; price = real USD price * multiplier
    type = 'simulated' -> startPrice, volatility (per tick, 0.01 = ~1%), drift (per tick),
                          reversion (0-1 pull back toward startPrice), minPrice
]]
Config.Coins = {
    { symbol = 'BTC',  name = 'Bitcoin',   type = 'real', geckoId = 'bitcoin',  multiplier = 1.0, color = '#f7931a' },
    { symbol = 'ETH',  name = 'Ethereum',  type = 'real', geckoId = 'ethereum', multiplier = 1.0, color = '#627eea' },
    { symbol = 'SOL',  name = 'Solana',    type = 'real', geckoId = 'solana',   multiplier = 1.0, color = '#14f195' },
    { symbol = 'DOGE', name = 'Dogecoin',  type = 'real', geckoId = 'dogecoin', multiplier = 1.0, color = '#c2a633' },

    { symbol = 'LSC',  name = 'LosSantosCoin', type = 'simulated', color = '#e84393',
      startPrice = 125.0, volatility = 0.012, drift = 0.0, reversion = 0.002, minPrice = 0.5 },
    { symbol = 'MAZE', name = 'MazeToken',     type = 'simulated', color = '#00b894',
      startPrice = 4.20,  volatility = 0.025, drift = 0.0, reversion = 0.004, minPrice = 0.01 },
}

---------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------
Config.AdminGroup = 'group.admin'  -- ACE group allowed to use /crypto* admin commands

---------------------------------------------------------------------
-- Phone number -> citizenid lookup (server side) for "send to phone number".
-- Adjust this to match your phone's database if needed.
---------------------------------------------------------------------
Config.PhoneLookup = {
    -- Tried first: an export on the phone resource. Set to false to skip.
    Export = { resource = 'qs-smartphone-pro', name = 'GetIdentifierByPhone' },
    -- Fallback: direct SQL. {table} has a {numberColumn} and an {identifierColumn} (citizenid).
    Sql = { table = 'phone_phones', numberColumn = 'phone_number', identifierColumn = 'id' },
}
