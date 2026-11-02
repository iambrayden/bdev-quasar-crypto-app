--[[
    ================================================================
     COINS
    ================================================================
    Add a coin with ONE line. Everything except symbol and name is optional.

    Server coin (price simulated on your server):
        { symbol = 'MYC', name = 'MyCoin', startPrice = 2.50, preset = 'volatile' },

    Real coin (live price from CoinGecko; geckoId is the last part of the coin's
    coingecko.com URL, e.g. coingecko.com/en/coins/shiba-inu -> 'shiba-inu'):
        { symbol = 'SHIB', name = 'Shiba Inu', geckoId = 'shiba-inu' },

    Optional fields:
        preset     = 'stable' | 'normal' | 'volatile' | 'meme'  (server coins, default 'normal')
        color      = '#ff00aa'          icon background (auto-picked if omitted)
        icon       = 'coins/mycoin.png' logo image: put the file in html/coins/ (png/jpg/webp), or use a
                                        full https:// URL. Falls back to the coloured circle if missing.
        tag        = 'MEME'             badge shown in the market (meme preset sets this for you)
        multiplier = 0.01               real coins: scale the real price for your economy
        Any preset value (volatility, drift, reversion, floor, events) can be overridden per coin.

    You can also create coins in-game with /cryptocreate (no restart needed).
]]

--[[
    Presets for server (simulated) coins. Each tick (Config.Simulation.TickSeconds):
        volatility  typical move per tick (0.01 = ~1%)
        drift       trend per tick (positive = slowly climbs)
        reversion   0-1, how hard the price is pulled back toward startPrice
        floor       lowest price as a fraction of startPrice (0.01 = can fall to 1% of start)
        events      random pumps/dumps: chance per tick, pump/dump = {min%, max%}
]]
Config.Presets = {
    stable = {
        volatility = 0.003, drift = 0.0, reversion = 0.02, floor = 0.5,
    },
    normal = {
        volatility = 0.012, drift = 0.0, reversion = 0.002, floor = 0.02,
    },
    volatile = {
        volatility = 0.025, drift = 0.0, reversion = 0.003, floor = 0.01,
        events = { chance = 0.002, pump = { 10, 40 }, dump = { 10, 35 } },
    },
    meme = {
        tag = 'MEME',
        volatility = 0.045, drift = -0.0002, reversion = 0.001, floor = 0.001,
        events = { chance = 0.006, pump = { 30, 250 }, dump = { 35, 85 } },
    },
}

Config.Coins = {
    -- Majors (live)
    { symbol = 'BTC',   name = 'Bitcoin',    geckoId = 'bitcoin',    color = '#f7931a' },
    { symbol = 'ETH',   name = 'Ethereum',   geckoId = 'ethereum',   color = '#627eea' },
    { symbol = 'SOL',   name = 'Solana',     geckoId = 'solana',     color = '#14f195' },

    -- Meme coins (live)
    { symbol = 'DOGE',  name = 'Dogecoin',   geckoId = 'dogecoin',   color = '#c2a633', tag = 'MEME' },
    { symbol = 'SHIB',  name = 'Shiba Inu',  geckoId = 'shiba-inu',  color = '#ffa409', tag = 'MEME' },
    { symbol = 'PEPE',  name = 'Pepe',       geckoId = 'pepe',       color = '#3d9b3b', tag = 'MEME' },
    { symbol = 'WIF',   name = 'dogwifhat',  geckoId = 'dogwifcoin', color = '#b8875a', tag = 'MEME' },
    { symbol = 'BONK',  name = 'Bonk',       geckoId = 'bonk',       color = '#f8a103', tag = 'MEME' },
    { symbol = 'FLOKI', name = 'Floki',      geckoId = 'floki',      color = '#e2a43b', tag = 'MEME' },

    -- Server coins
    { symbol = 'LSC',   name = 'LosSantosCoin', startPrice = 125.0, preset = 'normal',   color = '#e84393' },
    { symbol = 'MAZE',  name = 'MazeToken',     startPrice = 4.20,  preset = 'volatile', color = '#00b894' },
    { symbol = 'LSUSD', name = 'LS Dollar',     startPrice = 1.00,  preset = 'stable',   color = '#2ecc71' },

    -- Server meme coins (expect wild pumps and rug-pull dumps)
    { symbol = 'CHOP',  name = 'ChopCoin',          startPrice = 0.0042,   preset = 'meme', color = '#a0522d' },
    { symbol = 'RAGE',  name = 'Impotent Rage',     startPrice = 0.069,    preset = 'meme', color = '#c0392b' },
    { symbol = 'CLUCK', name = 'CluckCoin',         startPrice = 0.0123,   preset = 'meme', color = '#f1c40f' },
    { symbol = 'YOLO',  name = 'YOLO Inu',          startPrice = 0.000777, preset = 'meme', color = '#9b59b6' },
    { symbol = 'GRAPE', name = 'Grapeseed Moon',    startPrice = 0.0315,   preset = 'meme', color = '#8e44ad' },
    { symbol = 'RON',   name = 'RonCoin',           startPrice = 0.042,    preset = 'meme', color = '#7ac143',
      icon = 'coins/roncoin.png' },
}
