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
    SeedDelaySeconds = 6,          -- delay between history requests on start (free API is rate limited)
    ApiKey = '',                   -- optional free "demo" API key (raises rate limits)
    RefreshSeconds = 90,           -- how often to refresh live prices
    SeedHistoryDays = 7,           -- pull this many days of real history on start for charts
}

-- Simulated coins tick on the server.
Config.Simulation = {
    TickSeconds = 30,
    AnnounceEvents = true,         -- notify all players when a meme coin pumps or dumps
}

-- History kept for charts
Config.History = {
    PointSeconds = 60,             -- record a chart point every N seconds
    KeepDays = 7,
    MaxChartPoints = 150,          -- points sent to the phone per chart
}

-- Coins and presets live in coins.lua

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
