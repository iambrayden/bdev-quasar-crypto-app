-- Database layer. Tables are created automatically on start (see also install.sql).
DB = {}

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `bdev_crypto_wallets` (
        `citizenid` VARCHAR(50) NOT NULL,
        `address` VARCHAR(64) NOT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`citizenid`),
        UNIQUE KEY `address` (`address`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `bdev_crypto_holdings` (
        `citizenid` VARCHAR(50) NOT NULL,
        `coin` VARCHAR(16) NOT NULL,
        `amount` DECIMAL(30,8) NOT NULL DEFAULT 0,
        `invested` DECIMAL(20,2) NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`, `coin`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `bdev_crypto_transactions` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `citizenid` VARCHAR(50) NOT NULL,
        `type` VARCHAR(16) NOT NULL,
        `coin` VARCHAR(16) NOT NULL,
        `amount` DECIMAL(30,8) NOT NULL,
        `price` DECIMAL(24,8) NOT NULL DEFAULT 0,
        `usd` DECIMAL(20,2) NOT NULL DEFAULT 0,
        `fee` DECIMAL(30,8) NOT NULL DEFAULT 0,
        `counterparty` VARCHAR(64) DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`id`),
        KEY `citizenid` (`citizenid`, `id`)
    )]],
    [[CREATE TABLE IF NOT EXISTS `bdev_crypto_history` (
        `coin` VARCHAR(16) NOT NULL,
        `ts` INT UNSIGNED NOT NULL,
        `price` DECIMAL(24,8) NOT NULL,
        PRIMARY KEY (`coin`, `ts`)
    )]],
}

function DB.Init()
    for _, query in ipairs(SCHEMA) do
        MySQL.query.await(query)
    end
end

---------------------------------------------------------------------
-- Wallets
---------------------------------------------------------------------
local function randomAddress()
    local hex = {}
    for i = 1, 40 do
        hex[i] = ('%x'):format(math.random(0, 15))
    end
    return '0x' .. table.concat(hex)
end

function DB.GetOrCreateAddress(citizenid)
    local address = MySQL.scalar.await('SELECT address FROM bdev_crypto_wallets WHERE citizenid = ?', { citizenid })
    if address then return address end

    for _ = 1, 5 do
        address = randomAddress()
        local ok = pcall(MySQL.insert.await,
            'INSERT INTO bdev_crypto_wallets (citizenid, address) VALUES (?, ?)', { citizenid, address })
        if ok then return address end
        -- Either an address collision or another request created the wallet first.
        local existing = MySQL.scalar.await('SELECT address FROM bdev_crypto_wallets WHERE citizenid = ?', { citizenid })
        if existing then return existing end
    end
    error('could not create wallet address')
end

function DB.GetCitizenIdByAddress(address)
    return MySQL.scalar.await('SELECT citizenid FROM bdev_crypto_wallets WHERE address = ?', { address:lower() })
end

---------------------------------------------------------------------
-- Holdings
---------------------------------------------------------------------
function DB.GetHoldings(citizenid)
    local rows = MySQL.query.await(
        'SELECT coin, amount, invested FROM bdev_crypto_holdings WHERE citizenid = ? AND amount > 0', { citizenid })
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[row.coin] = { amount = tonumber(row.amount), invested = tonumber(row.invested) }
    end
    return out
end

function DB.GetHolding(citizenid, coin)
    local row = MySQL.single.await(
        'SELECT amount, invested FROM bdev_crypto_holdings WHERE citizenid = ? AND coin = ?', { citizenid, coin })
    if not row then return { amount = 0, invested = 0 } end
    return { amount = tonumber(row.amount), invested = tonumber(row.invested) }
end

--- Add coins (and optional cost basis) to a holding.
function DB.AddCoins(citizenid, coin, amount, invested)
    MySQL.query.await([[
        INSERT INTO bdev_crypto_holdings (citizenid, coin, amount, invested) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE amount = amount + VALUES(amount), invested = invested + VALUES(invested)
    ]], { citizenid, coin, amount, invested or 0 })
end

--- Atomically remove coins. Returns false if the holding doesn't have enough.
--- investedReduction lowers the cost basis proportionally (never below 0).
function DB.RemoveCoins(citizenid, coin, amount, investedReduction)
    local affected = MySQL.update.await([[
        UPDATE bdev_crypto_holdings
        SET amount = amount - ?, invested = GREATEST(invested - ?, 0)
        WHERE citizenid = ? AND coin = ? AND amount >= ?
    ]], { amount, investedReduction or 0, citizenid, coin, amount })
    if affected ~= 1 then return false end

    -- Clean up dust so empty holdings don't keep a cost basis.
    MySQL.update.await([[
        UPDATE bdev_crypto_holdings SET amount = 0, invested = 0
        WHERE citizenid = ? AND coin = ? AND amount < 0.00000001
    ]], { citizenid, coin })
    return true
end

---------------------------------------------------------------------
-- Transactions
---------------------------------------------------------------------
function DB.LogTransaction(citizenid, data)
    MySQL.insert([[
        INSERT INTO bdev_crypto_transactions (citizenid, type, coin, amount, price, usd, fee, counterparty)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid, data.type, data.coin, data.amount, data.price or 0, data.usd or 0, data.fee or 0, data.counterparty,
    })
end

function DB.GetTransactions(citizenid, limit)
    return MySQL.query.await([[
        SELECT id, type, coin, amount, price, usd, fee, counterparty, UNIX_TIMESTAMP(created_at) AS ts
        FROM bdev_crypto_transactions WHERE citizenid = ? ORDER BY id DESC LIMIT ?
    ]], { citizenid, limit }) or {}
end

---------------------------------------------------------------------
-- Price history (only simulated coins are persisted; real coins are re-seeded from CoinGecko)
---------------------------------------------------------------------
function DB.LoadHistory(coin, sinceTs)
    return MySQL.query.await(
        'SELECT ts, price FROM bdev_crypto_history WHERE coin = ? AND ts >= ? ORDER BY ts ASC', { coin, sinceTs }) or {}
end

function DB.SaveHistoryPoint(coin, ts, price)
    MySQL.insert('INSERT IGNORE INTO bdev_crypto_history (coin, ts, price) VALUES (?, ?, ?)', { coin, ts, price })
end

function DB.PruneHistory(beforeTs)
    MySQL.query('DELETE FROM bdev_crypto_history WHERE ts < ?', { beforeTs })
end
