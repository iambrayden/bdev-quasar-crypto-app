(() => {
    'use strict';

    // ------------------------------------------------------------------
    // NUI transport
    // ------------------------------------------------------------------
    // The phone loads this page from https://cfx-nui-<resource>/html/index.html
    const hostMatch = location.hostname.match(/^cfx-nui-(.+)$/);
    const RESOURCE = hostMatch ? hostMatch[1]
        : (typeof GetParentResourceName === 'function' ? GetParentResourceName() : null);
    const IN_GAME = !!RESOURCE;

    async function nui(name, data = {}) {
        if (!IN_GAME) return Mock.handle(name, data);
        try {
            const res = await fetch(`https://${RESOURCE}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (e) {
            return { ok: false, error: 'Connection error' };
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    const $ = (id) => document.getElementById(id);
    const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

    function usd(n, opts = {}) {
        n = Number(n) || 0;
        const abs = Math.abs(n);
        let digits = 2;
        // Prices under $1 keep ~4 significant digits: 0.3821, 0.00001234
        if (opts.price && abs > 0 && abs < 1) digits = Math.min(12, Math.max(2, 3 - Math.floor(Math.log10(abs))));
        const str = abs.toLocaleString('en-US', { minimumFractionDigits: opts.whole ? 0 : digits, maximumFractionDigits: opts.whole ? 0 : digits });
        return (n < 0 ? '-$' : (opts.sign && n > 0 ? '+$' : '$')) + str;
    }

    function coinAmt(n) {
        n = Number(n) || 0;
        return n.toLocaleString('en-US', { maximumFractionDigits: n >= 1000 ? 2 : 8 });
    }

    function pct(n, sign = true) {
        n = Number(n) || 0;
        return (sign && n > 0 ? '+' : '') + n.toFixed(2) + '%';
    }

    const cls = (n) => (Number(n) >= 0 ? 'up' : 'down');
    // Mirrors the server: 8 decimals, fewer for huge meme-coin amounts.
    const floor8 = (n) => {
        if (!(n > 0)) return 0;
        const intDigits = Math.max(1, Math.floor(Math.log10(n)) + 1);
        const m = 10 ** Math.max(0, Math.min(8, 15 - intDigits));
        return Math.floor(n * m + 1e-6) / m;
    };

    function coinIcon(coin) {
        const style = `background:${esc(coin.color || '#6c5ce7')}`;
        const img = coin.icon ? `<img src="${esc(coin.icon)}" alt="" onerror="this.remove()">` : '';
        return `<span class="coin-icon" style="${style}">${esc(coin.symbol.slice(0, 4))}${img}</span>`;
    }

    function badges(c) {
        let out = '';
        if (c.tag) out += `<span class="badge tag">${esc(c.tag)}</span>`;
        else if (c.type === 'simulated') out += '<span class="badge">SERVER</span>';
        return out;
    }

    let toastTimer;
    function toast(msg, ok = true) {
        const el = $('toast');
        el.textContent = msg;
        el.className = 'toast show ' + (ok ? 'ok' : 'err');
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => (el.className = 'toast'), 2600);
    }

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------
    const state = {
        market: [],
        wallet: { holdings: [], totalValue: 0, totalInvested: 0, balance: 0, address: '' },
        settings: { tradeFee: 0, transferFee: 0, transfersEnabled: true, minBuy: 0, maxBuy: 0 },
        view: 'market',
        coin: null,     // symbol open on the detail page
        filter: 'all',  // market filter chip
        range: '24H',
        chart: [],
        sheet: null,    // 'buy' | 'sell' | 'send'
        sellAll: false,
        busy: false,
    };

    const coinBySymbol = (s) => state.market.find((c) => c.symbol === s);
    const holdingOf = (s) => state.wallet.holdings.find((h) => h.symbol === s);

    // ------------------------------------------------------------------
    // Rendering
    // ------------------------------------------------------------------
    function renderHeader() {
        const w = state.wallet;
        const pl = w.totalValue - w.totalInvested;
        const plPct = w.totalInvested > 0 ? (pl / w.totalInvested) * 100 : 0;
        $('portfolio-value').textContent = usd(w.totalValue);
        const plEl = $('portfolio-pl');
        plEl.textContent = `${usd(pl, { sign: true })} (${pct(plPct)})`;
        plEl.className = 'pl ' + cls(pl);
        $('bank-balance').textContent = usd(w.balance, { whole: true });
    }

    const FILTERS = {
        all: () => true,
        live: (c) => c.type === 'real',
        server: (c) => c.type === 'simulated',
        meme: (c) => c.tag === 'MEME',
        gainers: (c) => c.change > 0,
    };

    function renderMarket() {
        const list = state.market.filter(FILTERS[state.filter] || FILTERS.all);
        if (state.filter === 'gainers') list.sort((a, b) => b.change - a.change);
        $('market-list').innerHTML = list.map((c) => `
            <div class="item" data-coin="${esc(c.symbol)}">
                ${coinIcon(c)}
                <div class="main">
                    <div class="title">${esc(c.name)}${badges(c)}</div>
                    <div class="sub">${esc(c.symbol)}</div>
                </div>
                <div class="right">
                    <div class="title">${c.price ? usd(c.price, { price: true }) : '—'}</div>
                    <span class="chip ${cls(c.change)}">${pct(c.change)}</span>
                </div>
            </div>`).join('') || '<div class="empty">No coins here.</div>';
    }

    function renderWallet() {
        $('wallet-address').textContent = state.wallet.address || '—';
        $('open-send').style.display = state.settings.transfersEnabled ? '' : 'none';
        $('holdings-list').innerHTML = state.wallet.holdings.map((h) => {
            const pl = h.value - h.invested;
            return `
            <div class="item" data-coin="${esc(h.symbol)}">
                ${coinIcon(h)}
                <div class="main">
                    <div class="title">${esc(h.name)}</div>
                    <div class="sub">${coinAmt(h.amount)} ${esc(h.symbol)}</div>
                </div>
                <div class="right">
                    <div class="title">${usd(h.value)}</div>
                    <div class="sub ${cls(pl)}">${usd(pl, { sign: true })}</div>
                </div>
            </div>`;
        }).join('') || '<div class="empty">You don\'t own any crypto yet.<br>Pick a coin in the Market to buy.</div>';
    }

    const TX_LABELS = { buy: 'Bought', sell: 'Sold', send: 'Sent', receive: 'Received', admin: 'Granted', mined: 'Mined', deposit: 'Deposit', withdraw: 'Withdrawn' };

    function renderTransactions(list) {
        $('tx-list').innerHTML = list.map((tx) => {
            const coin = coinBySymbol(tx.coin) || { symbol: tx.coin, color: '#444' };
            const incoming = ['buy', 'receive', 'admin', 'mined', 'deposit'].includes(tx.type);
            const label = TX_LABELS[tx.type] || tx.type;
            const date = new Date(tx.ts * 1000);
            let sub = date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' +
                date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
            if (tx.counterparty) sub += ' · ' + tx.counterparty.slice(0, 6) + '…' + tx.counterparty.slice(-4);
            const right = tx.type === 'buy' ? `-${usd(tx.usd)}` : tx.type === 'sell' ? `+${usd(tx.usd)}` : (tx.price ? '≈ ' + usd(tx.amount * tx.price) : '');
            return `
            <div class="item">
                ${coinIcon(coin)}
                <div class="main">
                    <div class="title">${esc(label)} ${esc(tx.coin)}</div>
                    <div class="sub">${esc(sub)}</div>
                </div>
                <div class="right">
                    <div class="title ${incoming ? 'up' : 'down'}">${incoming ? '+' : '-'}${coinAmt(tx.amount)}</div>
                    <div class="sub">${right}</div>
                </div>
            </div>`;
        }).join('') || '<div class="empty">No transactions yet.</div>';
    }

    function renderCoinPage() {
        const c = coinBySymbol(state.coin);
        if (!c) return;
        const h = holdingOf(c.symbol);
        $('coin-icon').outerHTML = coinIcon(c).replace('class="coin-icon"', 'class="coin-icon" id="coin-icon"');
        $('coin-name').textContent = `${c.name} (${c.symbol})`;
        $('coin-type').textContent = (c.tag === 'MEME' ? 'Meme coin · ' : '') + (c.type === 'simulated' ? 'Server coin' : 'Live market price');
        $('coin-price').textContent = c.price ? usd(c.price, { price: true }) : '—';

        const owned = h ? h.amount : 0;
        const value = h ? h.value : 0;
        const pl = h ? h.value - h.invested : 0;
        $('coin-owned').textContent = `${coinAmt(owned)} ${c.symbol}`;
        $('coin-value').textContent = usd(value);
        const plEl = $('coin-pl');
        plEl.textContent = usd(pl, { sign: true });
        plEl.className = cls(pl);
        $('btn-sell').disabled = owned <= 0;
        $('btn-buy').disabled = !c.price;
        renderRangeChange();
    }

    function renderRangeChange() {
        const c = coinBySymbol(state.coin);
        const el = $('coin-change');
        let change = c ? c.change : 0;
        if (state.range !== '24H' && state.chart.length > 1) {
            const first = state.chart[0].p;
            change = first > 0 ? ((state.chart[state.chart.length - 1].p - first) / first) * 100 : 0;
        }
        el.textContent = `${pct(change)} · ${state.range}`;
        el.className = 'pl ' + cls(change);
    }

    function renderAll() {
        renderHeader();
        renderMarket();
        renderWallet();
        if (state.coin) renderCoinPage();
    }

    // ------------------------------------------------------------------
    // Chart (plain canvas)
    // ------------------------------------------------------------------
    const canvas = $('chart');
    const ctx = canvas.getContext('2d');
    let chartGeom = null;

    function drawChart(hoverIndex = null) {
        const pts = state.chart;
        const dpr = window.devicePixelRatio || 1;
        const w = canvas.clientWidth, h = canvas.clientHeight;
        canvas.width = w * dpr;
        canvas.height = h * dpr;
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, w, h);

        $('chart-empty').style.display = pts.length < 2 ? 'grid' : 'none';
        if (pts.length < 2) { chartGeom = null; return; }

        let min = Infinity, max = -Infinity;
        for (const p of pts) { if (p.p < min) min = p.p; if (p.p > max) max = p.p; }
        if (max === min) { max += max * 0.01 || 1; min -= min * 0.01 || 1; }
        const t0 = pts[0].t, t1 = pts[pts.length - 1].t || t0 + 1;
        const padTop = 22, padBottom = 8;
        const x = (t) => ((t - t0) / Math.max(1, t1 - t0)) * w;
        const y = (p) => padTop + (1 - (p - min) / (max - min)) * (h - padTop - padBottom);
        chartGeom = { x, y, pts };

        const up = pts[pts.length - 1].p >= pts[0].p;
        const color = up ? '#16c784' : '#ea3943';

        ctx.beginPath();
        pts.forEach((p, i) => (i ? ctx.lineTo(x(p.t), y(p.p)) : ctx.moveTo(x(p.t), y(p.p))));
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.lineJoin = 'round';
        ctx.stroke();

        ctx.lineTo(w, h);
        ctx.lineTo(0, h);
        ctx.closePath();
        const grad = ctx.createLinearGradient(0, 0, 0, h);
        grad.addColorStop(0, up ? 'rgba(22,199,132,.28)' : 'rgba(234,57,67,.28)');
        grad.addColorStop(1, 'rgba(0,0,0,0)');
        ctx.fillStyle = grad;
        ctx.fill();

        if (hoverIndex !== null && pts[hoverIndex]) {
            const p = pts[hoverIndex];
            const px = x(p.t), py = y(p.p);
            ctx.strokeStyle = 'rgba(255,255,255,.25)';
            ctx.lineWidth = 1;
            ctx.setLineDash([3, 3]);
            ctx.beginPath(); ctx.moveTo(px, padTop - 6); ctx.lineTo(px, h); ctx.stroke();
            ctx.setLineDash([]);
            ctx.fillStyle = color;
            ctx.beginPath(); ctx.arc(px, py, 4, 0, Math.PI * 2); ctx.fill();
        }
    }

    function chartHover(e) {
        if (!chartGeom) return;
        const rect = canvas.getBoundingClientRect();
        const mx = e.clientX - rect.left;
        const { x, pts } = chartGeom;
        let best = 0, bestDist = Infinity;
        pts.forEach((p, i) => { const d = Math.abs(x(p.t) - mx); if (d < bestDist) { bestDist = d; best = i; } });
        drawChart(best);
        const p = pts[best];
        const tip = $('chart-tip');
        const d = new Date(p.t * 1000);
        const when = state.range === '7D'
            ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) + ' ' + d.toLocaleTimeString('en-US', { hour: 'numeric' })
            : d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
        tip.textContent = `${usd(p.p, { price: true })} · ${when}`;
        tip.style.display = 'block';
        const half = tip.offsetWidth / 2;
        tip.style.left = Math.min(rect.width - half, Math.max(half, x(p.t))) + 'px';
    }

    function chartLeave() {
        $('chart-tip').style.display = 'none';
        drawChart();
    }

    canvas.addEventListener('pointermove', chartHover);
    canvas.addEventListener('pointerdown', chartHover);
    canvas.addEventListener('pointerleave', chartLeave);
    window.addEventListener('resize', () => drawChart());

    async function loadChart() {
        const symbol = state.coin;
        const res = await nui('getChart', { symbol, range: state.range });
        if (symbol !== state.coin) return;
        state.chart = res && res.ok ? res.points : [];
        drawChart();
        renderRangeChange();
    }

    // ------------------------------------------------------------------
    // Data loading
    // ------------------------------------------------------------------
    async function refresh() {
        const res = await nui('getData');
        if (!res || !res.ok) {
            if (res && res.error) toast(res.error, false);
            return;
        }
        state.market = res.market || [];
        state.wallet = res.wallet || state.wallet;
        state.settings = res.settings || state.settings;
        renderAll();
        if (state.sheet) updateSummary();
    }

    async function loadTransactions() {
        const res = await nui('getTransactions');
        renderTransactions(res && res.ok ? res.transactions : []);
    }

    // ------------------------------------------------------------------
    // Navigation
    // ------------------------------------------------------------------
    function showView(view) {
        state.view = view;
        document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.view === view));
        document.querySelectorAll('.view').forEach((v) => v.classList.toggle('active', v.id === 'view-' + view));
        if (view === 'history') loadTransactions();
    }

    function openCoin(symbol) {
        state.coin = symbol;
        state.chart = [];
        renderCoinPage();
        drawChart();
        $('coin-page').classList.add('open');
        loadChart();
    }

    function closeCoin() {
        $('coin-page').classList.remove('open');
        state.coin = null;
    }

    document.querySelectorAll('.tab').forEach((t) => t.addEventListener('click', () => showView(t.dataset.view)));
    $('filters').addEventListener('click', (e) => {
        const chip = e.target.closest('[data-filter]');
        if (!chip) return;
        state.filter = chip.dataset.filter;
        document.querySelectorAll('#filters [data-filter]').forEach((x) => x.classList.toggle('active', x === chip));
        renderMarket();
    });
    $('market-list').addEventListener('click', (e) => { const el = e.target.closest('[data-coin]'); if (el) openCoin(el.dataset.coin); });
    $('holdings-list').addEventListener('click', (e) => { const el = e.target.closest('[data-coin]'); if (el) openCoin(el.dataset.coin); });
    $('coin-back').addEventListener('click', closeCoin);
    document.querySelectorAll('.range').forEach((r) => r.addEventListener('click', () => {
        state.range = r.dataset.range;
        document.querySelectorAll('.range').forEach((x) => x.classList.toggle('active', x === r));
        loadChart();
    }));
    $('copy-address').addEventListener('click', () => {
        if (!state.wallet.address) return;
        if (IN_GAME) nui('copy', { text: state.wallet.address });
        else toast('Address copied');
    });

    // ------------------------------------------------------------------
    // Trade / send sheet
    // ------------------------------------------------------------------
    const amountInput = $('amount');

    function openSheet(mode, symbol) {
        state.sheet = mode;
        state.sellAll = false;
        amountInput.value = '';
        $('send-target').value = '';
        const c = coinBySymbol(symbol || state.coin);

        $('field-coin').style.display = mode === 'send' ? '' : 'none';
        $('field-target').style.display = mode === 'send' ? '' : 'none';
        $('target-label').textContent = state.settings.allowPhone ? 'Wallet address or phone number' : 'Wallet address';
        $('send-target').placeholder = state.settings.allowPhone ? '0x… or phone number' : '0x…';

        if (mode === 'send') {
            const options = state.wallet.holdings.map((h) =>
                `<option value="${esc(h.symbol)}">${esc(h.name)} (${coinAmt(h.amount)} ${esc(h.symbol)})</option>`).join('');
            $('send-coin').innerHTML = options || '<option value="">No coins to send</option>';
            if (c && holdingOf(c.symbol)) $('send-coin').value = c.symbol;
        }

        const titles = { buy: `Buy ${c ? c.symbol : ''}`, sell: `Sell ${c ? c.symbol : ''}`, send: 'Send crypto' };
        $('sheet-title').textContent = titles[mode];
        $('sheet-confirm').className = 'btn wide ' + (mode === 'buy' ? 'buy' : mode === 'sell' ? 'sell' : 'primary');
        $('sheet-confirm').textContent = mode === 'buy' ? 'Buy' : mode === 'sell' ? 'Sell' : 'Send';
        updateAmountField();
        updateSummary();

        $('backdrop').classList.add('open');
        $('sheet').classList.add('open');
        setTimeout(() => (mode === 'send' ? $('send-target') : amountInput).focus(), 250);
    }

    function closeSheet() {
        state.sheet = null;
        $('backdrop').classList.remove('open');
        $('sheet').classList.remove('open');
        amountInput.blur();
    }

    function sheetSymbol() {
        return state.sheet === 'send' ? $('send-coin').value : state.coin;
    }

    function updateAmountField() {
        const symbol = sheetSymbol();
        const isUsd = state.sheet === 'buy';
        $('amount-label').textContent = isUsd ? 'Amount to spend' : 'Amount of coins';
        $('amount-prefix').style.display = isUsd ? '' : 'none';
        amountInput.parentElement.classList.toggle('no-prefix', !isUsd);
        $('amount-suffix').textContent = isUsd ? 'USD' : (symbol || '');
        const h = holdingOf(symbol);
        $('amount-hint').textContent = isUsd
            ? `Available: ${usd(state.wallet.balance, { whole: true })} · Min ${usd(state.settings.minBuy, { whole: true })}`
            : `Available: ${coinAmt(h ? h.amount : 0)} ${symbol || ''}`;
    }

    function summaryRows(rows) {
        return rows.map(([k, v]) => `<div class="stat"><span class="muted">${esc(k)}</span><b>${esc(v)}</b></div>`).join('');
    }

    function updateSummary() {
        const symbol = sheetSymbol();
        const c = coinBySymbol(symbol);
        const amount = parseFloat(amountInput.value);
        const el = $('summary');
        if (!c || !c.price || !(amount > 0)) { el.innerHTML = ''; return; }

        if (state.sheet === 'buy') {
            const spend = Math.floor(amount);
            const fee = spend * state.settings.tradeFee / 100;
            el.innerHTML = summaryRows([
                ['Price', usd(c.price, { price: true })],
                [`Fee (${state.settings.tradeFee}%)`, usd(fee)],
                ['You get ≈', `${coinAmt(floor8((spend - fee) / c.price))} ${c.symbol}`],
            ]);
        } else if (state.sheet === 'sell') {
            const gross = amount * c.price;
            const fee = gross * state.settings.tradeFee / 100;
            el.innerHTML = summaryRows([
                ['Price', usd(c.price, { price: true })],
                [`Fee (${state.settings.tradeFee}%)`, usd(fee)],
                ['You receive ≈', usd(Math.floor(gross - fee), { whole: true })],
            ]);
        } else {
            const fee = floor8(amount * state.settings.transferFee / 100);
            el.innerHTML = summaryRows([
                [`Network fee (${state.settings.transferFee}%)`, `${coinAmt(fee)} ${c.symbol}`],
                ['Recipient gets', `${coinAmt(floor8(amount - fee))} ${c.symbol}`],
                ['Value ≈', usd((amount - fee) * c.price)],
            ]);
        }
    }

    amountInput.addEventListener('input', () => { state.sellAll = false; updateSummary(); });
    $('send-coin').addEventListener('change', () => { amountInput.value = ''; updateAmountField(); updateSummary(); });

    $('quick').addEventListener('click', (e) => {
        const btn = e.target.closest('button');
        if (!btn) return;
        const p = Number(btn.dataset.pct) / 100;
        if (state.sheet === 'buy') {
            const max = Math.min(state.wallet.balance, state.settings.maxBuy || Infinity);
            amountInput.value = Math.floor(max * p) || '';
        } else {
            const h = holdingOf(sheetSymbol());
            amountInput.value = h ? floor8(h.amount * p) : '';
            state.sellAll = p === 1;
        }
        updateSummary();
    });

    $('backdrop').addEventListener('click', closeSheet);
    $('btn-buy').addEventListener('click', () => openSheet('buy'));
    $('btn-sell').addEventListener('click', () => openSheet('sell'));
    $('open-send').addEventListener('click', () => {
        if (!state.wallet.holdings.length) return toast('You have no coins to send.', false);
        openSheet('send');
    });

    $('sheet-confirm').addEventListener('click', async () => {
        if (state.busy) return;
        const symbol = sheetSymbol();
        const amount = parseFloat(amountInput.value);
        if (!symbol) return toast('Choose a coin.', false);
        if (!(amount > 0) && !state.sellAll) return toast('Enter an amount.', false);

        let res;
        state.busy = true;
        $('sheet-confirm').disabled = true;
        if (state.sheet === 'buy') {
            res = await nui('buy', { symbol, usd: Math.floor(amount) });
        } else if (state.sheet === 'sell') {
            res = await nui('sell', { symbol, amount, all: state.sellAll });
        } else {
            const target = $('send-target').value.trim();
            if (!target) { state.busy = false; $('sheet-confirm').disabled = false; return toast('Enter a recipient.', false); }
            res = await nui('send', { symbol, amount, target });
        }
        state.busy = false;
        $('sheet-confirm').disabled = false;

        if (res && res.ok) {
            toast(res.message || 'Done');
            closeSheet();
            await refresh();
            if (state.view === 'history') loadTransactions();
        } else {
            toast((res && res.error) || 'Something went wrong.', false);
        }
    });

    // ------------------------------------------------------------------
    // Browser preview (only used when opened outside FiveM)
    // ------------------------------------------------------------------
    const Mock = {
        balance: 25000,
        holdings: { BTC: { amount: 0.0215, invested: 1800 }, LSC: { amount: 42.5, invested: 4900 } },
        txs: [],
        coins: [
            { symbol: 'BTC', name: 'Bitcoin', color: '#f7931a', type: 'real', price: 96250.12, change: 2.31 },
            { symbol: 'ETH', name: 'Ethereum', color: '#627eea', type: 'real', price: 3412.55, change: -1.12 },
            { symbol: 'SOL', name: 'Solana', color: '#14f195', type: 'real', price: 182.4, change: 4.87 },
            { symbol: 'DOGE', name: 'Dogecoin', color: '#c2a633', type: 'real', tag: 'MEME', price: 0.3821, change: -3.4 },
            { symbol: 'SHIB', name: 'Shiba Inu', color: '#ffa409', type: 'real', tag: 'MEME', price: 0.00002187, change: 6.1 },
            { symbol: 'PEPE', name: 'Pepe', color: '#3d9b3b', type: 'real', tag: 'MEME', price: 0.00001934, change: -7.25 },
            { symbol: 'LSC', name: 'LosSantosCoin', color: '#e84393', type: 'simulated', price: 131.77, change: 5.42 },
            { symbol: 'MAZE', name: 'MazeToken', color: '#00b894', type: 'simulated', price: 4.0312, change: -0.85 },
            { symbol: 'CHOP', name: 'ChopCoin', color: '#a0522d', type: 'simulated', tag: 'MEME', price: 0.006113, change: 45.5 },
            { symbol: 'RON', name: 'RonCoin', color: '#7ac143', type: 'simulated', tag: 'MEME', icon: 'coins/roncoin.png', price: 0.04871, change: 15.97 },
        ],
        handle(name, d) {
            const coin = (s) => this.coins.find((c) => c.symbol === s);
            const fee = 1.5;
            const log = (t) => this.txs.unshift({ ...t, ts: Date.now() / 1000 });
            switch (name) {
                case 'getData': {
                    const holdings = Object.entries(this.holdings).filter(([, h]) => h.amount > 0).map(([s, h]) => {
                        const c = coin(s);
                        return { symbol: s, name: c.name, color: c.color, amount: h.amount, invested: h.invested, value: h.amount * c.price, price: c.price };
                    });
                    return {
                        ok: true, market: this.coins,
                        wallet: {
                            address: '0x7a3f9c21b4e8d0a6f1c3e5b7d9a2c4e6f8b0d1e3', holdings, balance: this.balance,
                            totalValue: holdings.reduce((a, h) => a + h.value, 0), totalInvested: holdings.reduce((a, h) => a + h.invested, 0),
                        },
                        settings: { tradeFee: fee, transferFee: 0.5, transfersEnabled: true, allowPhone: true, minBuy: 10, maxBuy: 1000000 },
                    };
                }
                case 'getChart': {
                    const c = coin(d.symbol);
                    const span = { '1H': 3600, '24H': 86400, '7D': 604800 }[d.range];
                    const n = 120, now = Date.now() / 1000;
                    let p = c.price / (1 + c.change / 100);
                    const pts = [];
                    let seed = d.symbol.charCodeAt(0) + span;
                    const rnd = () => ((seed = (seed * 9301 + 49297) % 233280) / 233280) - 0.5;
                    for (let i = 0; i < n; i++) {
                        p *= 1 + rnd() * 0.02 + (c.price - p) / c.price * 0.03;
                        pts.push({ t: now - span + (span / n) * i, p });
                    }
                    pts.push({ t: now, p: c.price });
                    return { ok: true, points: pts };
                }
                case 'getTransactions':
                    return { ok: true, transactions: this.txs };
                case 'buy': {
                    const c = coin(d.symbol);
                    if (d.usd > this.balance) return { ok: false, error: 'Insufficient funds.' };
                    const amt = floor8((d.usd * (1 - fee / 100)) / c.price);
                    this.balance -= d.usd;
                    const h = this.holdings[d.symbol] || (this.holdings[d.symbol] = { amount: 0, invested: 0 });
                    h.amount += amt; h.invested += d.usd;
                    log({ type: 'buy', coin: d.symbol, amount: amt, price: c.price, usd: d.usd });
                    return { ok: true, message: `Bought ${amt} ${d.symbol}` };
                }
                case 'sell': {
                    const c = coin(d.symbol), h = this.holdings[d.symbol];
                    const amt = d.all ? h.amount : d.amount;
                    if (!h || amt > h.amount) return { ok: false, error: "You don't have that many coins." };
                    const pay = Math.floor(amt * c.price * (1 - fee / 100));
                    h.invested -= h.invested * (amt / h.amount); h.amount -= amt;
                    this.balance += pay;
                    log({ type: 'sell', coin: d.symbol, amount: amt, price: c.price, usd: pay });
                    return { ok: true, message: `Sold ${amt} ${d.symbol} for $${pay}` };
                }
                case 'send': {
                    const h = this.holdings[d.symbol];
                    if (!h || d.amount > h.amount) return { ok: false, error: "You don't have that many coins." };
                    h.invested -= h.invested * (d.amount / h.amount); h.amount -= d.amount;
                    log({ type: 'send', coin: d.symbol, amount: d.amount, price: coin(d.symbol).price, counterparty: '0x1111222233334444555566667777888899990000' });
                    return { ok: true, message: `Sent ${d.amount} ${d.symbol}` };
                }
            }
            return { ok: false, error: 'Unknown action' };
        },
    };

    // ------------------------------------------------------------------
    // Boot + polling
    // ------------------------------------------------------------------
    refresh();
    setInterval(() => { if (!document.hidden) refresh(); }, 15000);
    setInterval(() => { if (!document.hidden && state.coin) loadChart(); }, 60000);
})();
