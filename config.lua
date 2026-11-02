Config = {}

Config.Debug = false

---------------------------------------------------------------------
-- Phone integration
---------------------------------------------------------------------
-- 'auto' finds Smartphone V3 ('qs-smartphone') or Smartphone PRO ('qs-smartphone-pro').
-- If you renamed the phone's folder, put the new resource name here.
Config.Phone = 'auto'

Config.App = {
    name = 'bdev-crypto',          -- internal app id (must be unique on the phone)
    label = 'Crypto',
    description = 'Buy, sell and send cryptocurrency.',
    category = 'Utilities',        -- app store category
    creator = 'bdev',
    age = '18+',
    appStoreOnly = false,          -- false = already on every home screen, true = download it from the App Store
    price = 0,                     -- App Store price (only used when appStoreOnly = true)
    job = false,                   -- Smartphone PRO only: false = everyone, or a job name
    blockedJobs = {},              -- Smartphone PRO only
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
    AllowPhoneNumber = true,       -- allow sending to online players by phone number (see Config.PhoneLookup)
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
---------------------------------------------------------------------
Config.PhoneLookup = {
    -- Online players: the phone's GetCurrentPhoneNumber(source) export. 'auto' = the detected phone.
    Export = { resource = 'auto', name = 'GetCurrentPhoneNumber' },
    -- Offline players (optional): direct SQL lookup, e.g.
    --   Sql = { table = 'your_numbers_table', numberColumn = 'number', identifierColumn = 'citizenid' },
    -- Off by default: Smartphone V3 ties numbers to the phone/SIM, not the character.
    -- Wallet addresses always work, online or offline.
    Sql = false,
}
