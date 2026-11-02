--[[
    ================================================================
     COINS
    ================================================================
    Add a coin with ONE line. Everything except symbol and name is optional.

    Server coin (price simulated on your server):
        { symbol = 'MYC', name = 'MyCoin', startPrice = 2.50, preset = 'volatile' },

    Real coin (live price; uses the Coinbase market SYMBOL-USD by default):
        { symbol = 'SHIB', name = 'Shiba Inu', live = true },
    If the Coinbase market has a different name, add market = 'XYZ-USD'.
    Using CoinGecko instead (Config.PriceSource = 'coingecko')? Add geckoId, the last part of
    the coin's coingecko.com URL, e.g. geckoId = 'shiba-inu'.

    Optional fields:
        preset     = 'stable' | 'normal' | 'volatile' | 'meme'  (server coins, default 'normal')
        color      = '#ff00aa'          icon background (auto-picked if omitted)
        icon       = 'coins/mycoin.png' logo image. By default a coin uses html/coins/<symbol>.png
                                        (e.g. html/coins/btc.png), so usually you just drop a square PNG
                                        there. Set icon only for another name, a .jpg/.webp, or an
                                        https:// URL. Missing images fall back to the coloured circle.
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
    { symbol = 'BTC',   name = 'Bitcoin',    live = true, geckoId = 'bitcoin',    color = '#f7931a' },
    { symbol = 'ETH',   name = 'Ethereum',   live = true, geckoId = 'ethereum',   color = '#627eea' },
    { symbol = 'SOL',   name = 'Solana',     live = true, geckoId = 'solana',     color = '#14f195' },

    -- Meme coins (live)
    { symbol = 'DOGE',  name = 'Dogecoin',   live = true, geckoId = 'dogecoin',   color = '#c2a633', tag = 'MEME' },
    { symbol = 'SHIB',  name = 'Shiba Inu',  live = true, geckoId = 'shiba-inu',  color = '#ffa409', tag = 'MEME' },
    { symbol = 'PEPE',  name = 'Pepe',       live = true, geckoId = 'pepe',       color = '#3d9b3b', tag = 'MEME' },
    { symbol = 'WIF',   name = 'dogwifhat',  live = true, geckoId = 'dogwifcoin', color = '#b8875a', tag = 'MEME' },

    -- Server coins
    { symbol = 'LSC',   name = 'LosSantosCoin', startPrice = 125.0, preset = 'normal',   color = '#e84393' },
    { symbol = 'LSUSD', name = 'LS Dollar',     startPrice = 1.00,  preset = 'stable',   color = '#2ecc71' },

    -- Server meme coins (expect wild pumps and rug-pull dumps)
    { symbol = 'RON',   name = 'RonCoin',           startPrice = 0.042,    preset = 'meme', color = '#7ac143',
      icon = 'coins/roncoin.png' },
}
