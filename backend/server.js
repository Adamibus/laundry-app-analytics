// Prune log entries older than 30 days
function pruneOldLogEntries(logPath) {
    if (!fs.existsSync(logPath)) return;
    const lines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(Boolean);
    const minDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000); // 30 days ago
    const kept = lines.filter(line => {
        try {
            const entry = JSON.parse(line);
            return new Date(entry.timestamp) >= minDate;
        } catch {
            return false;
        }
    });
    if (kept.length !== lines.length) {
        fs.writeFileSync(logPath, kept.join('\n') + (kept.length ? '\n' : ''));
    }
}

const express = require('express');
const compression = require('compression');
const axios = require('axios');
const cheerio = require('cheerio');
const cors = require('cors');
const fs = require('fs');
const path = require('path');


const app = express();
app.use(cors());
// Enable gzip/deflate compression for faster responses
app.use(compression());
const PORT = process.env.PORT || 5000;

// Serve static files from the React app with cache headers
app.use(express.static(path.join(__dirname, 'build'), {
    maxAge: '7d',
    etag: true
}));

// In-memory cache for fast snapshots
let SNAPSHOT = {
    machines: null,
    lastUpdated: null
};

function readLastLogSnapshot() {
    const logPath = path.join(__dirname, 'laundry_log.jsonl');
    if (!fs.existsSync(logPath)) return null;
    const data = fs.readFileSync(logPath, 'utf-8').trim();
    if (!data) return null;
    const lastLine = data.split('\n').filter(Boolean).pop();
    try {
        const parsed = JSON.parse(lastLine);
        return { machines: parsed.machines || [], lastUpdated: parsed.timestamp };
    } catch {
        return null;
    }
}

// Basic internal health endpoint
app.get('/health', (req, res) => {
    res.json({ ok: true, uptime: process.uptime(), timestamp: new Date().toISOString() });
});

// External connectivity health endpoint
app.get('/health/external', async (req, res) => {
    const mainUrl = 'https://laundryconnect.net/conncollege/cc.html';
    try {
        const response = await axios.get(mainUrl, { timeout: 10000 });
        const html = typeof response.data === 'string' ? response.data : '';
        const ok = response.status === 200 && html.includes('Connecticut College');
        res.status(ok ? 200 : 503).json({ ok, status: response.status, bytes: html.length });
    } catch (error) {
        console.error('External health check failed:', error);
        res.status(503).json({ ok: false, error: error.message || 'request-failed' });
    }
});

// Weekly time-slot analytics endpoint: returns for each weekday/hour the number of available and in-use machines
app.get('/api/laundry/weekly-times', (req, res) => {
    const logPath = path.join(__dirname, 'laundry_log.jsonl');
    if (!fs.existsSync(logPath)) {
        return res.json({ message: 'No log data yet.' });
    }
    const weekStats = {};
    const weekStatsCounts = {};
    const lines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(Boolean);
    const minDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000); // 7 days ago
    const dormFilter = req.query.dorm ? req.query.dorm.trim().toLowerCase() : null;
    const typeFilter = req.query.type ? req.query.type.trim().toLowerCase() : null;
    const statusFilter = req.query.status ? req.query.status.trim().toLowerCase() : null;
    lines.forEach(line => {
        try {
            const entry = JSON.parse(line);
            const date = new Date(entry.timestamp);
            if (date < minDate) return;
            const weekday = date.toLocaleString('en-US', { weekday: 'short' });
            const hour = date.getHours();
            weekStats[weekday] = weekStats[weekday] || {};
            weekStatsCounts[weekday] = weekStatsCounts[weekday] || {};
            weekStats[weekday][hour] = weekStats[weekday][hour] || { available: 0, inUse: 0, total: 0 };
            weekStatsCounts[weekday][hour] = weekStatsCounts[weekday][hour] || 0;
            const filteredMachines = entry.machines.filter(machine => {
                const dormName = (machine.dorm || '').trim().toLowerCase();
                const typeName = (machine.type || '').trim().toLowerCase();
                const statusName = (machine.status || '').trim().toLowerCase();
                if (dormFilter && dormName !== dormFilter) return false;
                if (typeFilter && typeName !== typeFilter) return false;
                if (statusFilter && statusName !== statusFilter) return false;
                return true;
            });
            if (filteredMachines.length > 0) {
                let available = 0, inUse = 0, total = 0;
                filteredMachines.forEach(machine => {
                    const status = machine.status.toLowerCase();
                    if (status.includes('available')) available++;
                    else if (status.includes('in use')) inUse++;
                    total++;
                });
                weekStats[weekday][hour].available += available;
                weekStats[weekday][hour].inUse += inUse;
                weekStats[weekday][hour].total += total;
                weekStatsCounts[weekday][hour]++;
            }
        } catch {}
    });
    const averagedStats = {};
    for (const weekday in weekStats) {
        averagedStats[weekday] = {};
        for (const hour in weekStats[weekday]) {
            const count = weekStatsCounts[weekday][hour] || 1;
            averagedStats[weekday][hour] = {
                available: weekStats[weekday][hour].available / count,
                inUse: weekStats[weekday][hour].inUse / count,
                total: weekStats[weekday][hour].total / count,
                count
            };
        }
    }
    res.json({ weekStats: averagedStats });
});

// Analytics per machine endpoint (supports ?period=week for last 7 days)
app.get('/api/laundry/machine-analytics', (req, res) => {
    const logPath = path.join(__dirname, 'laundry_log.jsonl');
    if (!fs.existsSync(logPath)) {
        return res.json({ message: 'No log data yet.' });
    }
    const machineStats = {};
    const lines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(Boolean);
    let minDate = null;
    if (req.query.period === 'week') {
        minDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000); // 7 days ago
    }
    lines.forEach(line => {
        try {
            const entry = JSON.parse(line);
            if (minDate && new Date(entry.timestamp) < minDate) return;
            entry.machines.forEach(machine => {
                const key = `${machine.dorm}__${machine.machine}`;
                if (!machineStats[key]) {
                    machineStats[key] = {
                        dorm: machine.dorm,
                        machine: machine.machine,
                        type: machine.type,
                        available: 0,
                        inUse: 0,
                        outOfOrder: 0,
                        endOfCycle: 0,
                        almostDone: 0,
                        total: 0
                    };
                }
                const status = machine.status.toLowerCase();
                if (status.includes('available')) machineStats[key].available++;
                else if (status.includes('in use')) machineStats[key].inUse++;
                else if (status.includes('out of order')) machineStats[key].outOfOrder++;
                else if (status.includes('end of cycle')) machineStats[key].endOfCycle++;
                else if (status.includes('almost done')) machineStats[key].almostDone++;
                machineStats[key].total++;
            });
        } catch (e) {
            // skip malformed lines
        }
    });
    // Convert to array and sort by dorm, then machine
    const statsArr = Object.values(machineStats).sort((a, b) => {
        if (a.dorm === b.dorm) return a.machine.localeCompare(b.machine);
        return a.dorm.localeCompare(b.dorm);
    });
    res.json({ machineAnalytics: statsArr });
});


// Helper function to analyze laundry availability for a dorm
function analyzeAvailability(html, dorm) {
    const $ = cheerio.load(html);
    const machines = [];
    $('table tr').each((i, row) => {
        const cols = $(row).find('td');
        if (cols.length >= 4) {
            const machine = $(cols[0]).text().trim();
            const type = $(cols[1]).text().trim();
            const status = $(cols[2]).text().trim();
            const timeRemaining = $(cols[3]).text().trim();
            // Filter out header rows
            if (
                machine && type && status &&
                machine.toLowerCase() !== 'machine' &&
                type.toLowerCase() !== 'type' &&
                status.toLowerCase() !== 'status'
            ) {
                machines.push({
                    dorm,
                    machine,
                    type,
                    status,
                    timeRemaining: timeRemaining || null
                });
            }
        }
    });
    return machines;
}

// Helper to get all dorm links from the main page
async function getDormLinks() {
    const mainUrl = 'https://laundryconnect.net/conncollege/cc.html';
    try {
        const response = await axios.get(mainUrl);
        const $ = cheerio.load(response.data);
        const dormLinks = [];
        $('a').each((i, el) => {
            const href = $(el).attr('href');
            const text = $(el).text().trim();
            if (href && href.endsWith('.aspx') && text) {
                dormLinks.push({
                    name: text,
                    url: 'https://laundryconnect.net/' + href
                });
            }
        });
        return dormLinks;
    } catch (error) {
        console.error('Error in getDormLinks:', error);
        throw error;
    }
}

// Function to fetch and log laundry data for all dorms
async function fetchAndLogLaundry() {
    try {
        const dormLinks = await getDormLinks();
        let allMachines = [];
        for (const dorm of dormLinks) {
            try {
                const resp = await axios.get(dorm.url);
                const machines = analyzeAvailability(resp.data, dorm.name);
                allMachines = allMachines.concat(machines);
            } catch (e) {
                console.error(`Failed to fetch data for dorm ${dorm.name}:`, e);
            }
        }
        const logEntry = {
            timestamp: new Date().toISOString(),
            machines: allMachines
        };
        const logPath = path.join(__dirname, 'laundry_log.jsonl');
        fs.appendFile(logPath, JSON.stringify(logEntry) + '\n', err => {
            if (err) console.error('Failed to log data:', err);
            else pruneOldLogEntries(logPath);
        });
        // Update in-memory snapshot for fast reads
        SNAPSHOT.machines = allMachines;
        SNAPSHOT.lastUpdated = logEntry.timestamp;
        return allMachines;
    } catch (error) {
        console.error('Failed to fetch dorm links or data:', error);
        return null;
    }
}


// Analyze the log and return best times for laundry availability
app.get('/api/laundry/best-times', (req, res) => {
    const logPath = path.join(__dirname, 'laundry_log.jsonl');
    if (!fs.existsSync(logPath)) {
        return res.json({ message: 'No log data yet.' });
    }
    const hourStats = {};
    const lines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(Boolean);
    lines.forEach(line => {
        try {
            const entry = JSON.parse(line);
            const date = new Date(entry.timestamp);
            const hour = date.getHours();
            const day = date.toLocaleString('en-US', { weekday: 'long' });
            entry.machines.forEach(machine => {
                if (machine.status.toLowerCase() === 'available') {
                    const key = `${day} ${hour}:00`;
                    hourStats[key] = (hourStats[key] || 0) + 1;
                }
            });
        } catch (e) {
            // skip malformed lines
        }
    });
    // Sort by most available
    const sorted = Object.entries(hourStats)
        .sort((a, b) => b[1] - a[1])
        .map(([time, count]) => ({ time, availableCount: count }));
    res.json({ bestTimes: sorted });
});

app.get('/api/laundry', async (req, res) => {
    // Support cached mode to avoid blocking on live scrape
    if (req.query.cached === '1') {
        if (!SNAPSHOT.machines) {
            const last = readLastLogSnapshot();
            if (last) {
                SNAPSHOT.machines = last.machines;
                SNAPSHOT.lastUpdated = last.lastUpdated;
            }
        }
        // Kick off background refresh if stale > 30 minutes
        const isStale = SNAPSHOT.lastUpdated ? (Date.now() - new Date(SNAPSHOT.lastUpdated).getTime() > 30 * 60 * 1000) : true;
        if (isStale) {
            fetchAndLogLaundry().catch(() => {});
        }
        return res.json({ machines: SNAPSHOT.machines || [], lastUpdated: SNAPSHOT.lastUpdated });
    }

    // Default: live scrape (may be slower)
    const machines = await fetchAndLogLaundry();
    if (machines) {
        res.json({ machines, lastUpdated: new Date().toISOString() });
    } else {
        res.status(500).json({ error: 'Failed to fetch laundry data.' });
    }
});

// Fast snapshot endpoint that never blocks on live scrape
app.get('/api/laundry/snapshot', (req, res) => {
    if (!SNAPSHOT.machines) {
        const last = readLastLogSnapshot();
        if (last) {
            SNAPSHOT.machines = last.machines;
            SNAPSHOT.lastUpdated = last.lastUpdated;
        }
    }
    // Background refresh if stale > 30 minutes
    const isStale = SNAPSHOT.lastUpdated ? (Date.now() - new Date(SNAPSHOT.lastUpdated).getTime() > 30 * 60 * 1000) : true;
    if (isStale) {
        fetchAndLogLaundry().catch(() => {});
    }
    res.json({ machines: SNAPSHOT.machines || [], lastUpdated: SNAPSHOT.lastUpdated });
});


// Catch-all handler to serve React's index.html for any non-API GET requests (Express 4.x, Node.js v22+)
app.get(/^\/(?!api).*/, (req, res) => {
    res.sendFile(path.join(__dirname, 'build', 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`Server running on port ${PORT}`);
    fetchAndLogLaundry();
    setInterval(fetchAndLogLaundry, 60 * 60 * 1000);
});
