# bdev-quasar-crypto-app

A crypto exchange app for the **Quasar smartphone** on **Qbox** servers.

Players can:

- Browse a market of real coins (live prices) and server-only coins (simulated prices), with 1H / 24H / 7D charts.
- Buy and sell coins with their **bank** balance, with a configurable trading fee.
- See their wallet: holdings, value, profit/loss, and a personal wallet address.
- Send coins to other players by wallet address or phone number, with an optional network fee.
- View their transaction history.

Admins can set, pump and crash the server coins, and give coins to players.

## Requirements

- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- `qs-smartphone-pro` (preferred) or `qs-smartphone`
- For live prices, your FiveM server needs outbound HTTPS to `api.coingecko.com`.

## Install

1. Put the folder in your resources, e.g. `resources/[bdev]/bdev-quasar-crypto-app`.
2. Add it to `server.cfg` **after** the phone and its dependencies:
   ```
   ensure ox_lib
   ensure oxmysql
   ensure qbx_core
   ensure qs-smartphone-pro
   ensure bdev-quasar-crypto-app
   ```
3. Start the server. The database tables are created automatically (`install.sql` is included if you'd rather run it yourself).
4. Players find **Crypto** in the phone's app store.

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

```lua
-- Real coin: price = CoinGecko USD price * multiplier
{ symbol = 'BTC', name = 'Bitcoin', type = 'real', geckoId = 'bitcoin', multiplier = 1.0, color = '#f7931a' },

-- Simulated coin: random walk on the server
{ symbol = 'LSC', name = 'LosSantosCoin', type = 'simulated', color = '#e84393',
  startPrice = 125.0,  -- starting price and the level it drifts back toward
  volatility = 0.012,  -- size of each tick's move (~1.2%)
  drift = 0.0,         -- trend per tick (e.g. 0.0005 for a slow climb)
  reversion = 0.002,   -- 0 = pure random walk, higher = pulled harder toward startPrice
  minPrice = 0.5 },
```

`geckoId` is the coin's id on coingecko.com (the last part of its page URL). Use `multiplier` to scale real prices to your server's economy, for example `0.01` makes BTC 100x cheaper.

Simulated prices and their history are saved in the database, so they survive restarts.

### Sending by phone number

`Config.PhoneLookup` decides how a phone number is turned into a citizenid. It tries an export on the phone first, then a direct SQL lookup. **Check the table and column names against your phone's database.** If the lookup fails, players can still send by wallet address.

## Admin commands

Restricted to `Config.AdminGroup` (default `group.admin`).

| Command | Description |
| --- | --- |
| `/cryptoprices` | Show all current prices |
| `/cryptoset [coin] [price]` | Set a simulated coin's price |
| `/cryptopump [coin] [percent]` | Raise a simulated coin by a percentage |
| `/cryptocrash [coin] [percent]` | Drop a simulated coin by a percentage |
| `/cryptogive [id] [coin] [amount]` | Give coins to a player |

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
client/phone.lua    Quasar phone integration (the only phone-specific file)
client/main.lua     NUI callbacks that relay app requests to the server
server/bridge.lua   Qbox money/player functions and phone-number lookup
server/db.lua       database tables and queries
server/prices.lua   CoinGecko prices, simulated prices, chart history
server/main.lua     buy / sell / send logic and exports
server/admin.lua    admin commands
html/               the app UI shown inside the phone
```
