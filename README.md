# bdev-quasar-crypto-app

A crypto exchange app for the **Quasar smartphone** on **Qbox** servers.

Players can:

- Browse a market of real coins (live prices), meme coins, and server-only coins (simulated prices), with filters and 1H / 24H / 7D charts.
- Buy and sell coins with their **bank** balance, with a configurable trading fee.
- See their wallet: holdings, value, profit/loss, and a personal wallet address.
- Send coins to other players by wallet address or phone number, with an optional network fee.
- View their transaction history.

Admins can create new coins in-game, set/pump/crash server coins, and give coins to players.

## Requirements

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- Quasar **Smartphone V3** (`qs-smartphone`) or **Smartphone PRO** (`qs-smartphone-pro`). The script detects which one you run.
- For live prices, your FiveM server needs outbound HTTPS to `api.coingecko.com`.

## Install

1. Put the folder in your resources, e.g. `resources/[bdev]/bdev-quasar-crypto-app`.
2. Add it to `server.cfg` **after** the phone and its dependencies:
   ```
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core
   ensure qs-smartphone
   ensure bdev-quasar-crypto-app
   ```
3. Start the server. The database tables are created automatically (`install.sql` is included if you'd rather run it yourself).
4. **Crypto** appears on every phone's home screen. Set `Config.App.appStoreOnly = true` to make players download it from the App Store instead.

### The app doesn't show up?

Type `/cryptoapp` in game and open F8. It re-registers the app and prints which phone was found and, if the phone refused the app, its error code. Common causes:

- The phone's folder was renamed. Put the new name in `Config.Phone`.
- This resource starts before the phone. It waits up to a minute, but `ensure` it after the phone anyway.
- You changed `Config.App.name` to an id another app already uses.

## Configuration

Everything is in `config.lua`:

| Section | What it controls |
| --- | --- |
| `Config.Phone`, `Config.App` | Which phone to register with, plus the app's name, icon label, store category and job lock |
| `Config.Trading` | Trading fee %, min/max buy, minimum sell value, per-player cooldown |
| `Config.Transfers` | Enable/disable sending, transfer fee %, sending by phone number |
| `Config.CoinGecko` | Optional free demo API key, refresh rate, days of chart history to seed |
| `Config.Simulation`, `Config.History` | Simulated tick rate, chart point interval and retention |
| `Config.Coins` | The coin list (see below) |
| `Config.PhoneLookup` | How a phone number is resolved to a citizenid |

### Coins

Coins live in **`coins.lua`**, one line each. Only `symbol` and `name` are required.

```lua
-- Server coin with a preset (stable / normal / volatile / meme)
{ symbol = 'RON', name = 'RonCoin', startPrice = 0.042, preset = 'meme', icon = 'coins/roncoin.png' },

-- Real coin: live CoinGecko price (geckoId = last part of the coin's coingecko.com URL)
{ symbol = 'SHIB', name = 'Shiba Inu', geckoId = 'shiba-inu', tag = 'MEME' },
```

Optional fields: `color`, `icon` (a file in `html/coins/` or an https URL), `tag` (market badge), `multiplier` (scales real prices for your economy), and any preset value to override (`volatility`, `drift`, `reversion`, `floor`, `events`).

**Presets** (defined in `coins.lua`, so you can edit them or add your own):

| Preset | Behaviour |
| --- | --- |
| `stable` | Barely moves, stays near its start price |
| `normal` | Moderate swings |
| `volatile` | Big swings plus rare 10-40% pumps/dumps |
| `meme` | Wild swings, slow bleed, frequent 30-250% pumps and 35-85% rug-pull dumps. Tagged MEME |

When a coin pumps or dumps, every player gets a notification (`Config.Simulation.AnnounceEvents`).

**Included coins:** BTC, ETH, SOL; meme coins DOGE, SHIB, PEPE, WIF, BONK, FLOKI (live); and server coins LSC, MAZE, LSUSD, plus server meme coins CHOP, RAGE, CLUCK, YOLO, GRAPE and RON.

#### Creating coins in-game

`/cryptocreate` opens a form (name, symbol, server/real, start price, preset, CoinGecko id, colour, logo). Or use it in one line:

```
/cryptocreate RON 0.042 meme RonCoin
```

Coins created this way are stored in the database, show up for everyone immediately and survive restarts. Remove them with `/cryptoremove RON`. If players hold the coin, you'll be asked to confirm with `/cryptoremove RON force`, which wipes their holdings.

#### Coin logos

Put a square image in `html/coins/` (png, jpg or webp) and set `icon = 'coins/<file>'`. If the image is missing, the coloured circle with the symbol is shown instead.

Simulated prices and their history are saved in the database, so they survive restarts.

### Sending by phone number

Sending by phone number matches online players using the phone's `GetCurrentPhoneNumber` export. To also reach offline players, set `Config.PhoneLookup.Sql` to a table that maps numbers to citizenids. Sending by wallet address always works, online or offline.

Players who receive coins get a phone notification (Smartphone V3), or an on-screen notification otherwise.

## Admin commands

Restricted to `Config.AdminGroup` (default `group.admin`).

| Command | Description |
| --- | --- |
| `/cryptoprices` | Show all current prices |
| `/cryptoset [coin] [price]` | Set a simulated coin's price |
| `/cryptopump [coin] [percent]` | Raise a simulated coin by a percentage |
| `/cryptocrash [coin] [percent]` | Drop a simulated coin by a percentage |
| `/cryptogive [id] [coin] [amount]` | Give coins to a player |
| `/cryptocreate` | Create a coin (opens a form; or `/cryptocreate SYMBOL PRICE PRESET NAME`) |
| `/cryptoremove [coin] [force]` | Remove a coin made with `/cryptocreate` |

Real coins follow the market and can't be changed with these commands.

## Exports (server)

These are for other resources, such as the upcoming mining machines.

```lua
local res = exports['bdev-quasar-crypto-app']

res:AddCrypto(citizenid, 'BTC', 0.0005, 'mined')   -- -> true/false (reason shows in history)
res:RemoveCrypto(citizenid, 'BTC', 0.0005, 'fee')  -- -> false if they don't have enough
res:GetCryptoBalance(citizenid, 'BTC')             -- -> number
res:GetCryptoPrice('BTC')                          -- -> number or nil
```

Use the resource's folder name in `exports[...]` if you renamed the folder.

## Previewing the UI

Open `html/index.html` in a browser. Outside FiveM it runs with built-in mock data, so you can see and click through the app without a server.

## Files

```
config.lua          all settings
coins.lua           coin list and presets
client/phone.lua    Quasar phone integration (the only phone-specific file)
client/main.lua     NUI callbacks that relay app requests to the server
client/admin.lua    /cryptocreate form
server/bridge.lua   Qbox money/player functions and phone-number lookup
server/db.lua       database tables and queries
server/prices.lua   CoinGecko prices, simulated prices, chart history
server/main.lua     buy / sell / send logic and exports
server/admin.lua    admin commands
html/               the app UI shown inside the phone
html/coins/         coin logo images
```
