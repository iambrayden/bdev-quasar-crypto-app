-- Optional: the resource creates these tables automatically on start.

CREATE TABLE IF NOT EXISTS `bdev_crypto_wallets` (
    `citizenid` VARCHAR(50) NOT NULL,
    `address` VARCHAR(64) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`),
    UNIQUE KEY `address` (`address`)
);

CREATE TABLE IF NOT EXISTS `bdev_crypto_holdings` (
    `citizenid` VARCHAR(50) NOT NULL,
    `coin` VARCHAR(16) NOT NULL,
    `amount` DECIMAL(30,8) NOT NULL DEFAULT 0,
    `invested` DECIMAL(20,2) NOT NULL DEFAULT 0,
    PRIMARY KEY (`citizenid`, `coin`)
);

CREATE TABLE IF NOT EXISTS `bdev_crypto_transactions` (
    `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `citizenid` VARCHAR(50) NOT NULL,
    `type` VARCHAR(16) NOT NULL,
    `coin` VARCHAR(16) NOT NULL,
    `amount` DECIMAL(30,8) NOT NULL,
    `price` DECIMAL(30,12) NOT NULL DEFAULT 0,
    `usd` DECIMAL(20,2) NOT NULL DEFAULT 0,
    `fee` DECIMAL(30,8) NOT NULL DEFAULT 0,
    `counterparty` VARCHAR(64) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `citizenid` (`citizenid`, `id`)
);

CREATE TABLE IF NOT EXISTS `bdev_crypto_history` (
    `coin` VARCHAR(16) NOT NULL,
    `ts` INT UNSIGNED NOT NULL,
    `price` DECIMAL(30,12) NOT NULL,
    PRIMARY KEY (`coin`, `ts`)
);

CREATE TABLE IF NOT EXISTS `bdev_crypto_coins` (
    `symbol` VARCHAR(16) NOT NULL,
    `data` LONGTEXT NOT NULL,
    `created_by` VARCHAR(50) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`symbol`)
);
