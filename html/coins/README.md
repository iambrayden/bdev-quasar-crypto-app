Coin logos. Each coin automatically uses `<symbol>.png` from this folder, lowercase
(BTC -> btc.png, LSC -> lsc.png). Just drop a square PNG named after the symbol here
and restart the resource:

    restart bdev-quasar-crypto-app

To use another file name, a .jpg/.webp, or a web URL, set `icon = 'coins/<file>'`
(or `icon = 'https://...'`) on the coin in coins.lua.

roncoin.png is a placeholder: replace it with your own RonCoin image (same file name).

Live coin logos (btc, eth, sol, doge, shib, pepe, wif) are the projects'
own logos, from CoinGecko's image CDN.
