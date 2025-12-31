// ScanSend Generator
const CHUNK_SIZE = 500; // bytes per chunk

let file = null;
let chunks = [];
let currentPage = 0;
let totalPages = 0;
let fileHash = '';
let qrCode = null;

// DOM Elements
const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');
const statusEl = document.getElementById('status');
const fileInfoEl = document.getElementById('file-info');
const qrContainer = document.getElementById('qr-container');
const qrInfoEl = document.getElementById('qr-info');
const navigationEl = document.getElementById('navigation');
const prevBtn = document.getElementById('prev-btn');
const nextBtn = document.getElementById('next-btn');
const pageInput = document.getElementById('page-input');

// Event Listeners
dropZone.addEventListener('dragover', (e) => {
    e.preventDefault();
    dropZone.classList.add('dragover');
});

dropZone.addEventListener('dragleave', () => {
    dropZone.classList.remove('dragover');
});

dropZone.addEventListener('drop', (e) => {
    e.preventDefault();
    dropZone.classList.remove('dragover');
    if (e.dataTransfer.files.length > 0) {
        handleFile(e.dataTransfer.files[0]);
    }
});

fileInput.addEventListener('change', (e) => {
    if (e.target.files.length > 0) {
        handleFile(e.target.files[0]);
    }
});

prevBtn.addEventListener('click', () => navigatePage(-1));
nextBtn.addEventListener('click', () => navigatePage(1));
pageInput.addEventListener('change', () => goToPage(parseInt(pageInput.value)));

document.addEventListener('keydown', (e) => {
    if (totalPages === 0) return;
    if (e.key === 'ArrowLeft') navigatePage(-1);
    if (e.key === 'ArrowRight') navigatePage(1);
    if (e.key === 'Home') goToPage(1);
    if (e.key === 'End') goToPage(totalPages);
});

// Functions
async function handleFile(f) {
    file = f;
    statusEl.textContent = '파일 처리 중...';
    
    try {
        const arrayBuffer = await file.arrayBuffer();
        const uint8Array = new Uint8Array(arrayBuffer);
        
        // Calculate SHA-256 hash
        const hashBuffer = await crypto.subtle.digest('SHA-256', uint8Array);
        const hashArray = Array.from(new Uint8Array(hashBuffer));
        fileHash = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
        
        // Create chunks
        chunks = [];
        for (let i = 0; i < uint8Array.length; i += CHUNK_SIZE) {
            const chunk = uint8Array.slice(i, i + CHUNK_SIZE);
            const base64 = btoa(String.fromCharCode.apply(null, chunk));
            chunks.push(base64);
        }
        
        // Total pages = chunks + 1 (final QR)
        totalPages = chunks.length + 1;
        currentPage = 0;
        
        // Update UI
        fileInfoEl.innerHTML = `
            <strong>파일명:</strong> ${file.name}<br>
            <strong>크기:</strong> ${formatSize(file.size)}<br>
            <strong>청크 수:</strong> ${chunks.length}<br>
            <strong>전체 페이지:</strong> ${totalPages}
        `;
        
        navigationEl.style.display = 'flex';
        pageInput.max = totalPages;
        
        statusEl.textContent = 'QR 코드 생성 완료!';
        showQRCode();
        
    } catch (error) {
        statusEl.textContent = '오류: ' + error.message;
        console.error(error);
    }
}

function showQRCode() {
    let data;
    
    if (currentPage < chunks.length) {
        // Chunk QR
        data = JSON.stringify({
            t: 'chunk',
            f: file.name,
            i: currentPage,
            n: chunks.length,
            d: chunks[currentPage]
        });
    } else {
        // Final QR
        data = JSON.stringify({
            t: 'final',
            f: file.name,
            n: chunks.length,
            h: fileHash,
            s: file.size
        });
    }
    
    // Clear previous QR
    qrContainer.innerHTML = '';
    
    // Generate new QR
    qrCode = new QRCode(qrContainer, {
        text: data,
        width: 300,
        height: 300,
        correctLevel: QRCode.CorrectLevel.L
    });
    
    // Update info
    const pageType = currentPage < chunks.length ? '청크' : '완료(해시)';
    qrInfoEl.textContent = `페이지 ${currentPage + 1} / ${totalPages} (${pageType})`;
    pageInput.value = currentPage + 1;
    
    // Update buttons
    prevBtn.disabled = currentPage === 0;
    nextBtn.disabled = currentPage >= totalPages - 1;
}

function navigatePage(delta) {
    const newPage = currentPage + delta;
    if (newPage >= 0 && newPage < totalPages) {
        currentPage = newPage;
        showQRCode();
    }
}

function goToPage(page) {
    const newPage = page - 1;
    if (newPage >= 0 && newPage < totalPages) {
        currentPage = newPage;
        showQRCode();
    }
}

function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / 1024 / 1024).toFixed(1) + ' MB';
}
