-- /cryptocreate form (the server checks permissions again when it's submitted)

RegisterNetEvent('bdev-crypto:createCoinDialog', function(presets)
    local presetOptions = {}
    for _, name in ipairs(presets or {}) do
        presetOptions[#presetOptions + 1] = { value = name, label = name:sub(1, 1):upper() .. name:sub(2) }
    end

    local input = lib.inputDialog('Create a coin', {
        { type = 'input', label = 'Name', placeholder = 'RonCoin', required = true, min = 2, max = 32 },
        { type = 'input', label = 'Symbol', placeholder = 'RON', required = true, min = 2, max = 8 },
        { type = 'select', label = 'Price source', required = true, default = 'simulated', options = {
            { value = 'simulated', label = 'Server coin (simulated price)' },
            { value = 'real', label = 'Real coin (live CoinGecko price)' },
        } },
        { type = 'number', label = 'Start price ($) - server coins', placeholder = '0.05', precision = 10, min = 0 },
        { type = 'select', label = 'Behaviour - server coins', default = 'meme', options = presetOptions },
        { type = 'input', label = 'CoinGecko id - real coins', placeholder = 'shiba-inu' },
        { type = 'color', label = 'Icon colour', default = '#6c5ce7' },
        { type = 'input', label = 'Logo (optional)', placeholder = 'coins/roncoin.png or https://...' },
    })
    if not input then return end

    local real = input[3] == 'real'
    local result = lib.callback.await('bdev-crypto:createCoin', false, {
        name = input[1],
        symbol = input[2],
        startPrice = not real and input[4] or nil,
        preset = not real and input[5] or nil,
        geckoId = real and input[6] or nil,
        color = input[7],
        icon = input[8] ~= '' and input[8] or nil,
    })
    lib.notify({
        title = Config.App.label,
        description = result and (result.message or result.error) or 'No response',
        type = result and result.ok and 'success' or 'error',
    })
end)
