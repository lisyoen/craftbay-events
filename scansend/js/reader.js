// ScanSend Reader
const API_BASE = 'https://scansend.craftbay.io';

let html5QrCode = null;
let sessionId = null;
let filename = null;
let totalChunks = 0;
let receivedChunks = new Set();
let scanHistory = [];

// DOM Elements
const cameraPreview = document.getElementById('camera-preview');
const transferStatus = document.getElementById('transfer-status');
const transferProgress = document.getElementById('transfer-progress');
const fileNameEl = document.getElementById('file-name');
const progressText = document.getElementById('progress-text');
const progressFill = document.getElementById('progress-fill');
const pagesSent = document.getElementById('pages-sent');
const pagesTotal = document.getElementById('pages-total');
const scanList = document.getElementById('scan-list');
const pendingInfo = document.getElementById('pending-info');
const pendingList = document.getElementById('pending-list');
const completionSection = document.getElementById('completion-section');
const btnToggleCamera = document.getElementById('btn-toggle-camera');
const btnNewScan = document.getElementById('btn-new-scan');

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    initScanner();
    loadSession();
});

btnToggleCamera.addEventListener('click', toggleCamera);
btnNewScan.addEventListener('click', resetSession);

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
        
    } catch (error) {
        console.error('Camera init error:', error);
        transferStatus.innerHTML = `
            <div class="status-error">
                <span class="status-icon">⚠️</span>
                <span class="status-text">카메라 접근 실패: ${error.message}</span>
            </div>
        `;
    }
}

async function onScanSuccess(decodedText) {
    try {
        const data = JSON.parse(decodedText);
        
        if (data.t === 'chunk') {
            await handleChunk(data);
        } else if (data.t === 'final') {
            await handleFinal(data);
        }
        
    } catch (error) {
        console.error('Scan parse error:', error);
    }
}

function onScanFailure(error) {
    // Ignore scan failures (no QR detected)
}

async function handleChunk(data) {
    // Skip if already received
    if (receivedChunks.has(data.i)) {
        return;
    }
    
    // Initialize session if first chunk
    if (!sessionId) {
        filename = data.f;
        totalChunks = data.n;
        showProgress();
    }
    
    try {
        const response = await fetch(`${API_BASE}/api/chunk`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                ...data,
                sessionId: sessionId
            })
        });
        
        const result = await response.json();
        
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
        addScanResult(data.i, false, error.message);
    }
}

async function handleFinal(data) {
    if (!sessionId) {
        addScanResult('final', false, '청크가 먼저 전송되어야 합니다');
        return;
    }
    
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
            showCompletion(true);
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
    transferStatus.style.display = 'none';
    transferProgress.style.display = 'block';
    fileNameEl.textContent = filename;
    pagesTotal.textContent = totalChunks + 1;
}

function updateProgress(result) {
    const received = result.received ? result.received.length : receivedChunks.size;
    const percent = Math.round((received / totalChunks) * 100);
    
    progressFill.style.width = percent + '%';
    progressText.textContent = percent + '%';
    pagesSent.textContent = received;
    
    if (result.missing && result.missing.length > 0) {
        updatePendingList(result.missing);
    }
}

function updatePendingList(missing) {
    pendingInfo.innerHTML = `<span class="pending-count">${missing.length}</span>개 페이지 미전송`;
    pendingList.innerHTML = missing.map(i => `
        <li class="pending-item">페이지 ${i + 1}</li>
    `).join('');
}

function addScanResult(index, success, error = null) {
    const item = document.createElement('li');
    item.className = `scan-item ${success ? 'scan-success' : 'scan-fail'}`;
    
    const icon = success ? '✓' : '✗';
    const text = index === 'final' ? '완료 QR' : `페이지 ${index + 1}`;
    const errorText = error ? ` - ${error}` : '';
    
    item.innerHTML = `
        <span class="scan-icon">${icon}</span>
        <span class="scan-text">${text}${errorText}</span>
        <span class="scan-time">방금</span>
    `;
    
    // Remove empty state
    const emptyItem = scanList.querySelector('.scan-empty');
    if (emptyItem) emptyItem.remove();
    
    scanList.insertBefore(item, scanList.firstChild);
    
    // Keep only last 10
    while (scanList.children.length > 10) {
        scanList.removeChild(scanList.lastChild);
    }
}

function showCompletion(success) {
    if (html5QrCode) {
        html5QrCode.stop();
    }
    
    completionSection.style.display = 'block';
    document.getElementById('stat-total').textContent = totalChunks + 1;
    document.getElementById('stat-success').textContent = receivedChunks.size;
}

function saveSession() {
    localStorage.setItem('scansend_session', JSON.stringify({
        sessionId,
        filename,
        totalChunks,
        receivedChunks: Array.from(receivedChunks)
    }));
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
            
            if (sessionId) {
                showProgress();
                updateProgress({ received: data.receivedChunks });
            }
        }
    } catch (e) {
        console.error('Load session error:', e);
    }
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
    
    transferStatus.style.display = 'block';
    transferProgress.style.display = 'none';
    completionSection.style.display = 'none';
    scanList.innerHTML = '<li class="scan-item scan-empty"><span class="scan-icon">🔍</span><span class="scan-text">스캔 기록이 없습니다</span></li>';
    pendingList.innerHTML = '';
    pendingInfo.innerHTML = '<span class="pending-count">0</span>개 페이지 대기 중';
    
    initScanner();
}

async function toggleCamera() {
    // Toggle between front and back camera
    if (html5QrCode) {
        await html5QrCode.stop();
        // Re-init with opposite camera
        initScanner();
    }
}
