const WebSocket = require('ws');
const { TikTokLiveConnection } = require('tiktok-live-connector');
const { spawn } = require('child_process');
const colors = require('colors');

const PORT = 21213;
const TIKTOK_USERNAME = 'jersonalvr';

const wss = new WebSocket.Server({ port: PORT });
console.log(colors.cyan(`WebSocket server started on ws://localhost:${PORT}`));

let isLive = false;
let tiktok = null;
let isConnected = false;
let isConnecting = false;  // Flag para evitar conexiones simultáneas
let monitoringProcess = null;
let lastErrorTime = 0;
function generateRandomSessionId() {
    return Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
}

function startMonitoring() {
    if (monitoringProcess) return; // Ya está corriendo

    console.log(colors.blue('Iniciando monitoreo continuo de TikTok LIVE...'));
    monitoringProcess = spawn('powershell.exe', ['-ExecutionPolicy', 'Bypass', '-File', 'detect_tiktok_live.ps1'], { stdio: ['pipe', 'pipe', 'pipe'] });

    monitoringProcess.stdout.on('data', (data) => {
        const output = data.toString().trim();
        console.log(colors.yellow('PowerShell Output:', output));

        const isInLive = output.includes('ESTAS EN TIKTOK LIVE');

        if (isInLive && !isConnected && !isConnecting && (Date.now() - lastErrorTime > 10000)) {
            console.log(colors.green('Detectado: En LIVE. Conectando a TikTok...'));
            isConnecting = true;
            connectToTikTok();
        } else if (!isInLive && isConnected) {
            console.log(colors.red('Detectado: No en LIVE. Desconectando...'));
            disconnectFromTikTok();
        }
    });

    monitoringProcess.stderr.on('data', (data) => {
        console.error(colors.red('Stderr:', data.toString()));
    });

    monitoringProcess.on('close', (code) => {
        console.log(colors.gray('PowerShell process exited with code', code));
        monitoringProcess = null;
    });
}

function stopMonitoring() {
    if (monitoringProcess) {
        console.log(colors.blue('Deteniendo monitoreo de TikTok LIVE...'));
        monitoringProcess.kill();
        monitoringProcess = null;
    }
}

function connectToTikTok() {
    if (tiktok) {
        tiktok.disconnect();
    }
    tiktok = new TikTokLiveConnection(TIKTOK_USERNAME);

    tiktok.connect().then(() => {
        console.log(colors.green('Connected to TikTok live'));
        isConnected = true;
        isConnecting = false;  // Reset flag on success
    }).catch(err => {
        console.error(colors.red('Failed to connect:', err.message));
        isConnected = false;
        isConnecting = false;  // Reset flag on failure
        isLive = false;
        lastErrorTime = Date.now();  // Registrar el tiempo del error
        broadcast({ event: 'liveStatus', data: { isLive: false } });
    });

    tiktok.on('connected', () => {
        console.log(colors.green('TikTok connected'));
        isLive = true;
        broadcast({ event: 'liveStatus', data: { isLive: true } });
        stopMonitoring();
    });

    tiktok.on('disconnected', () => {
        console.log(colors.yellow('TikTok disconnected'));
        isLive = false;
        isConnected = false;
        broadcast({ event: 'liveStatus', data: { isLive: false } });
        startMonitoring();
    });

    tiktok.on('streamEnd', () => {
        console.log(colors.red('Stream ended'));
        isLive = false;
        isConnected = false;
        broadcast({ event: 'liveStatus', data: { isLive: false } });
        startMonitoring();
    });

    // Forward TikTok events to WebSocket clients
    tiktok.on('member', (data) => broadcast({ event: 'member', data }));
    tiktok.on('roomUser', (data) => broadcast({ event: 'roomUser', data }));
    tiktok.on('follow', (data) => broadcast({ event: 'follow', data }));
    tiktok.on('like', (data) => broadcast({ event: 'like', data }));
    tiktok.on('chat', (data) => broadcast({ event: 'chat', data }));
    tiktok.on('share', (data) => broadcast({ event: 'share', data }));
    tiktok.on('gift', (data) => broadcast({ event: 'gift', data }));
    tiktok.on('social', (data) => broadcast({ event: 'social', data }));
    tiktok.on('emote', (data) => broadcast({ event: 'emote', data }));
    tiktok.on('envelope', (data) => broadcast({ event: 'envelope', data }));
    tiktok.on('questionNew', (data) => broadcast({ event: 'questionNew', data }));
    tiktok.on('linkMicBattle', (data) => broadcast({ event: 'linkMicBattle', data }));
    tiktok.on('linkMicArmies', (data) => broadcast({ event: 'linkMicArmies', data }));
    tiktok.on('liveIntro', (data) => broadcast({ event: 'liveIntro', data }));
    tiktok.on('subscribe', (data) => broadcast({ event: 'subscribe', data }));
    tiktok.on('rawData', (data) => broadcast({ event: 'rawData', data }));
}

function disconnectFromTikTok() {
    if (tiktok) {
        tiktok.disconnect();
        tiktok = null;
        isConnected = false;
        isConnecting = false;  // Reset flag on disconnect
        isLive = false;
        broadcast({ event: 'liveStatus', data: { isLive: false } });
        startMonitoring();
    }
}

function broadcast(message) {
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(message));
        }
    });
}

wss.on('connection', (ws) => {
    console.log(colors.cyan('New WebSocket connection'));
    // Send current status to new client
    ws.send(JSON.stringify({ event: 'liveStatus', data: { isLive } }));

    ws.on('close', () => {
        console.log(colors.gray('WebSocket connection closed'));
    });
});

// Start monitoring
startMonitoring();
