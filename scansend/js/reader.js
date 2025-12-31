// ScanSend Reader v2.2 - 세션 관리 개선
const API_BASE = 'https://scansend.craftbay.io';
const VERSION = 'v2.2';

let html5QrCode = null;
let sessionId = null;
let filename = null;
let totalChunks = 0;
let receivedChunks = new Set();

// 서버 로그 전송
async function serverLog(msg, data = {}) {
    try {
        await fetch(`${API_BASE}/api/log`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ msg, ...data, ts: Date.now(), v: VERSION })
        });
    } catch (e) {}
    console.log(msg, data);
}

// DOM Elements
const statusIdle = document.getElementById('status-idle');
const progressSection = document.getElementById('progress-section');
const fileNameEl = document.getElementById('file-name');
const progressText = document.getElementById('progress-text');
const progressFill = document.getElementById('progress-fill');
const pagesSent = document.getElementById('pages-sent');
const pagesTotal = document.getElementById('pages-total');
const scanList = document.getElementById('scan-list');
const pendingInfo = document.getElementById('pending-info');
const pendingList = document.getElementById('pending-list');
const completionSection = document.getElementById('completion-section');
const btnNewScan = document.getElementById('btn-new-scan');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    const header = document.querySelector('h1');
    if (header) header.textContent = '📷 ScanSend ' + VERSION;
    
    serverLog('Reader loaded', { version: VERSION });
    initScanner();
    // 세션 로드 제거 - 항상 새로 시작
});

if (btnNewScan) btnNewScan.addEventListener('click', resetSession);

async function initScanner() {
    serverLog('initScanner start');
    try {
        html5QrCode = new Html5Qrcode("camera-preview");
        
        const config = {
            fps: 10,
            qrbox: { width: 250, height: 250 },
            aspectRatio: 1.0
        };
        
        await html5QrCode.start(
            { facingMode: "environment" },
            config,
            onScanSuccess,
            onScanFailure
        );
        
        serverLog('Scanner started OK');
        
    } catch (error) {
        serverLog('Camera error', { error: error.message });
    }
}

async function onScanSuccess(decodedText) {
    serverLog('QR scanned', { len: decodedText.length });
    
    try {
        const data = JSON.parse(decodedText);
        serverLog('Parsed', { type: data.t, index: data.i, file: data.f });
        
        // 파일명이 바뀌면 세션 리셋
        if (filename && data.f !== filename) {
            serverLog('New file detected, resetting session');
            sessionId = null;
            filename = null;
            totalChunks = 0;
            receivedChunks = new Set();
        }
        
        if (data.t === 'chunk') {
            await handleChunk(data);
        } else if (data.t === 'final') {
            await handleFinal(data);
        }
        
    } catch (error) {
        serverLog('Parse error', { error: error.message });
        addScanResult('parse', false, error.message);
    }
}

function onScanFailure(error) {
    // Ignore - no QR detected
}

async function handleChunk(data) {
    // Skip if already received
    if (receivedChunks.has(data.i)) {
        serverLog('Skip dup', { index: data.i });
        return;
    }
    
    // Initialize session if first chunk
    if (!filename) {
        filename = data.f;
        totalChunks = data.n;
        showProgress();
        serverLog('Session init', { file: filename, total: totalChunks });
    }
    
    serverLog('Sending chunk', { index: data.i, sessionId });
    
    try {
        const response = await fetch(`${API_BASE}/api/chunk`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...data,
                sessionId: sessionId
            })
        });
        
        serverLog('Response', { status: response.status, ok: response.ok });
        
        const result = await response.json();
        serverLog('Result', result);
        
        if (result.success) {
            sessionId = result.sessionId;  // 서버에서 받은 sessionId 저장
            receivedChunks.add(data.i);
            updateProgress(result);
            addScanResult(data.i, true);
        } else {
            addScanResult(data.i, false, result.error);
        }
        
    } catch (error) {
        serverLog('Fetch error', { error: error.message, name: error.name });
        addScanResult(data.i, false, error.message);
    }
}

async function handleFinal(data) {
    serverLog('handleFinal', { sessionId, filename: data.f });
    
    if (!sessionId) {
        serverLog('Final without session');
        addScanResult('final', false, '청크를 먼저 스캔하세요');
        return;
    }
    
    serverLog('Sending final', { sessionId });
    
    try {
        const response = await fetch(`${API_BASE}/api/finalize`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...data,
                sessionId: sessionId
            })
        });
        
        const result = await response.json();
        serverLog('Final result', result);
        
        if (result.success) {
            showCompletion();
        } else {
            addScanResult('final', false, result.error);
            if (result.missing && result.missing.length > 0) {
                updatePendingList(result.missing);
            }
        }
        
    } catch (error) {
        serverLog('Final error', { error: error.message });
        addScanResult('final', false, error.message);
    }
}

function showProgress() {
    if (statusIdle) statusIdle.style.display = 'none';
    if (progressSection) progressSection.style.display = 'block';
    if (fileNameEl) fileNameEl.textContent = filename;
    if (pagesTotal) pagesTotal.textContent = totalChunks + 1;
    if (pagesSent) pagesSent.textContent = '0';
    if (progressFill) progressFill.style.width = '0%';
    if (progressText) progressText.textContent = '0%';
}

function updateProgress(result) {
    const received = result.received ? result.received.length : receivedChunks.size;
    const percent = Math.round((received / totalChunks) * 100);
    
    if (progressFill) progressFill.style.width = percent + '%';
    if (progressText) progressText.textContent = percent + '%';
    if (pagesSent) pagesSent.textContent = received;
    
    if (result.missing && result.missing.length > 0) {
        updatePendingList(result.missing);
    }
}

function updatePendingList(missing) {
    if (pendingInfo) pendingInfo.innerHTML = `<span class="pending-count">${missing.length}</span>개 미전송`;
    if (pendingList) pendingList.innerHTML = missing.slice(0, 10).map(i => `
        <li class="pending-item">페이지 ${i + 1}</li>
    `).join('');
}

function addScanResult(index, success, error = null) {
    if (!scanList) return;
    
    const item = document.createElement('li');
    item.className = `scan-item ${success ? 'scan-success' : 'scan-fail'}`;
    
    const icon = success ? '✓' : '✗';
    const text = index === 'final' ? '완료' : (index === 'parse' ? '파싱오류' : `p${index + 1}`);
    const errorText = error ? `: ${error.substring(0, 30)}` : '';
    
    item.innerHTML = `<span class="scan-icon">${icon}</span><span class="scan-text">${text}${errorText}</span>`;
    
    const emptyItem = scanList.querySelector('.scan-empty');
    if (emptyItem) emptyItem.remove();
    
    scanList.insertBefore(item, scanList.firstChild);
    
    while (scanList.children.length > 5) {
        scanList.removeChild(scanList.lastChild);
    }
}

function showCompletion() {
    if (html5QrCode) html5QrCode.stop().catch(e => {});
    if (completionSection) {
        completionSection.style.display = 'block';
        document.getElementById('stat-total').textContent = totalChunks + 1;
        document.getElementById('stat-success').textContent = receivedChunks.size + 1;
    }
    // 세션 리셋
    sessionId = null;
    filename = null;
    totalChunks = 0;
    receivedChunks = new Set();
}

function resetSession() {
    sessionId = null;
    filename = null;
    totalChunks = 0;
    receivedChunks = new Set();
    if (statusIdle) statusIdle.style.display = 'block';
    if (progressSection) progressSection.style.display = 'none';
    if (completionSection) completionSection.style.display = 'none';
    if (scanList) scanList.innerHTML = '<li class="scan-item scan-empty"><span class="scan-icon">🔍</span><span class="scan-text">스캔 기록 없음</span></li>';
    if (pendingList) pendingList.innerHTML = '';
    if (pendingInfo) pendingInfo.innerHTML = '<span class="pending-count">0</span>개 미전송';
    initScanner();
}
