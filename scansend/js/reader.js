// ScanSend Reader
const API_BASE = 'https://scansend.craftbay.io';

let html5QrCode = null;
let sessionId = null;
let filename = null;
let totalChunks = 0;
let receivedChunks = new Set();

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
    initScanner();
    loadSession();
});

if (btnNewScan) btnNewScan.addEventListener('click', resetSession);

async function initScanner() {
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
        
        console.log('Scanner started');
        
    } catch (error) {
        console.error('Camera init error:', error);
        alert('카메라 접근 실패: ' + error.message);
    }
}

async function onScanSuccess(decodedText) {
    console.log('QR Scanned:', decodedText.substring(0, 100));
    
    try {
        const data = JSON.parse(decodedText);
        console.log('Parsed data:', data.t, data.i);
        
        if (data.t === 'chunk') {
            await handleChunk(data);
        } else if (data.t === 'final') {
            await handleFinal(data);
        }
        
    } catch (error) {
        console.error('Scan parse error:', error);
        addScanResult('parse', false, error.message);
    }
}

function onScanFailure(error) {
    // Ignore - no QR detected
}

async function handleChunk(data) {
    // Skip if already received
    if (receivedChunks.has(data.i)) {
        console.log('Skip duplicate chunk:', data.i);
        return;
    }
    
    // Initialize session if first chunk
    if (!filename) {
        filename = data.f;
        totalChunks = data.n;
        showProgress();
    }
    
    console.log('Sending chunk:', data.i);
    
    try {
        const response = await fetch(`${API_BASE}/api/chunk`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...data,
                sessionId: sessionId
            })
        });
        
        console.log('Response status:', response.status);
        
        const result = await response.json();
        console.log('Result:', result);
        
        if (result.success) {
            sessionId = result.sessionId;
            receivedChunks.add(data.i);
            saveSession();
            updateProgress(result);
            addScanResult(data.i, true);
        } else {
            addScanResult(data.i, false, result.error);
        }
        
    } catch (error) {
        console.error('Chunk send error:', error);
        addScanResult(data.i, false, 'Network: ' + error.message);
    }
}

async function handleFinal(data) {
    if (!sessionId) {
        addScanResult('final', false, '청크 먼저 전송 필요');
        return;
    }
    
    console.log('Sending final');
    
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
        
        if (result.success) {
            showCompletion();
            clearSession();
        } else {
            addScanResult('final', false, result.error);
            if (result.missing && result.missing.length > 0) {
                updatePendingList(result.missing);
            }
        }
        
    } catch (error) {
        console.error('Finalize error:', error);
        addScanResult('final', false, error.message);
    }
}

function showProgress() {
    if (statusIdle) statusIdle.style.display = 'none';
    if (progressSection) progressSection.style.display = 'block';
    if (fileNameEl) fileNameEl.textContent = filename;
    if (pagesTotal) pagesTotal.textContent = totalChunks + 1;
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
    const text = index === 'final' ? '완료 QR' : (index === 'parse' ? '파싱 오류' : `페이지 ${index + 1}`);
    const errorText = error ? ` - ${error}` : '';
    
    item.innerHTML = `
        <span class="scan-icon">${icon}</span>
        <span class="scan-text">${text}${errorText}</span>
    `;
    
    // Remove empty state
    const emptyItem = scanList.querySelector('.scan-empty');
    if (emptyItem) emptyItem.remove();
    
    scanList.insertBefore(item, scanList.firstChild);
    
    // Keep only last 5
    while (scanList.children.length > 5) {
        scanList.removeChild(scanList.lastChild);
    }
}

function showCompletion() {
    if (html5QrCode) {
        html5QrCode.stop().catch(e => console.log(e));
    }
    
    if (completionSection) {
        completionSection.style.display = 'block';
        document.getElementById('stat-total').textContent = totalChunks + 1;
        document.getElementById('stat-success').textContent = receivedChunks.size;
    }
}

function saveSession() {
    try {
        localStorage.setItem('scansend_session', JSON.stringify({
            sessionId,
            filename,
            totalChunks,
            receivedChunks: Array.from(receivedChunks)
        }));
    } catch (e) {}
}

function loadSession() {
    try {
        const saved = localStorage.getItem('scansend_session');
        if (saved) {
            const data = JSON.parse(saved);
            sessionId = data.sessionId;
            filename = data.filename;
            totalChunks = data.totalChunks;
            receivedChunks = new Set(data.receivedChunks);
            
            if (sessionId && filename) {
                showProgress();
                updateProgress({ received: data.receivedChunks });
            }
        }
    } catch (e) {}
}

function clearSession() {
    localStorage.removeItem('scansend_session');
}

function resetSession() {
    clearSession();
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
