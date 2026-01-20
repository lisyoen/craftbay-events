// RTunnel Browser Script for Scripty Injection
// v1.0.0 - Single-page WebSocket control
// Usage: Load via Scripty extension from https://events.craftbay.io/rtunnel/browser.js

(function() {
  'use strict';

  // 이미 실행 중이면 중복 실행 방지
  if (window.__rtunnelLoaded) {
    console.log('[RTunnel] Already loaded, skipping');
    return;
  }
  window.__rtunnelLoaded = true;

  const SERVER_URL = 'wss://rtunnel-api.craftbay.io/ws';
  const VERSION = '1.0.0';
  const STORAGE_KEY = 'rtunnel_hostname';

  let ws = null;
  let clientId = null;
  let reconnectTimer = null;
  let reconnectAttempts = 0;
  const MAX_RECONNECT_DELAY = 30000;

  // hostname 가져오기/설정
  function getHostname() {
    let hostname = localStorage.getItem(STORAGE_KEY);
    if (!hostname) {
      // URL 파라미터 확인
      const params = new URLSearchParams(window.location.search);
      hostname = params.get('rtunnel_hostname');

      if (!hostname) {
        hostname = prompt('RTunnel hostname을 입력하세요 (예: DESKTOP-HOME)');
      }

      if (hostname) {
        localStorage.setItem(STORAGE_KEY, hostname);
      } else {
        hostname = 'Scripty-' + Math.random().toString(36).substr(2, 6);
        localStorage.setItem(STORAGE_KEY, hostname);
      }
    }
    return hostname;
  }

  function getBrowser() {
    const ua = navigator.userAgent;
    if (ua.includes('Edg/')) return 'Edge';
    if (ua.includes('Chrome/')) return 'Chrome';
    if (ua.includes('Firefox/')) return 'Firefox';
    if (ua.includes('Safari/')) return 'Safari';
    return 'Browser';
  }

  function safeSend(data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(data));
      return true;
    }
    return false;
  }

  function connect() {
    if (ws) {
      if (ws.readyState === WebSocket.OPEN) return;
      if (ws.readyState === WebSocket.CONNECTING) return;
    }

    try {
      const hostname = getHostname();
      const browser = getBrowser();

      ws = new WebSocket(SERVER_URL);

      ws.onopen = () => {
        console.log('[RTunnel] Connected');
        reconnectAttempts = 0;

        setTimeout(() => {
          safeSend({
            type: 'browser_connect',
            hostname: hostname,
            browser: browser + '-Scripty',
            version: VERSION
          });
        }, 100);
      };

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);
          handleMessage(msg);
        } catch (e) {
          console.error('[RTunnel] Parse error:', e);
        }
      };

      ws.onclose = () => {
        console.log('[RTunnel] Disconnected');
        ws = null;
        scheduleReconnect();
      };

      ws.onerror = (error) => {
        console.error('[RTunnel] Error:', error);
      };

    } catch (e) {
      console.error('[RTunnel] Connection failed:', e);
      scheduleReconnect();
    }
  }

  function scheduleReconnect() {
    if (reconnectTimer) clearTimeout(reconnectTimer);

    // Exponential backoff: 1s, 2s, 4s, 8s, ... max 30s
    const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), MAX_RECONNECT_DELAY);
    reconnectAttempts++;

    console.log('[RTunnel] Reconnecting in ' + delay + 'ms...');
    reconnectTimer = setTimeout(connect, delay);
  }

  function handleMessage(msg) {
    switch (msg.type) {
      case 'welcome':
        clientId = msg.clientId;
        console.log('[RTunnel] Welcome ID:', clientId);
        break;

      case 'connected':
        clientId = msg.clientId;
        console.log('[RTunnel] Registered, ID:', clientId);
        if (msg.hostnameHint) {
          localStorage.setItem(STORAGE_KEY, msg.hostnameHint);
          console.log('[RTunnel] Hostname hint saved:', msg.hostnameHint);
        }
        break;

      case 'ping':
        safeSend({ type: 'pong', timestamp: Date.now() });
        break;

      case 'browser_command':
        console.log('[RTunnel] Command:', msg.action);
        executeCommand(msg.action, msg.params || {})
          .then(result => {
            safeSend({
              type: 'browser_response',
              requestId: msg.requestId,
              success: true,
              result: result
            });
          })
          .catch(e => {
            console.error('[RTunnel] Command error:', e);
            safeSend({
              type: 'browser_response',
              requestId: msg.requestId,
              success: false,
              error: e.message
            });
          });
        break;

      case 'reload':
        console.log('[RTunnel] Reload requested');
        location.reload();
        break;
    }
  }

  async function executeCommand(action, params) {
    switch (action) {
      // Scripty는 단일 페이지에서만 동작하므로 탭 관련 기능은 제한적
      case 'listTabs': {
        return [{
          id: 0,
          url: location.href,
          title: document.title,
          active: true,
          note: 'Scripty mode: only current tab available'
        }];
      }

      case 'openTab': {
        window.open(params.url, '_blank');
        return { opened: params.url, note: 'Opened in new window' };
      }

      case 'navigate': {
        location.href = params.url;
        return { navigating: params.url };
      }

      case 'closeTab': {
        return { error: 'closeTab not supported in Scripty mode' };
      }

      case 'activateTab': {
        return { error: 'activateTab not supported in Scripty mode' };
      }

      case 'click': {
        const el = document.querySelector(params.selector);
        if (!el) throw new Error('Element not found: ' + params.selector);
        el.click();
        return true;
      }

      case 'type': {
        const el = document.querySelector(params.selector);
        if (!el) throw new Error('Element not found: ' + params.selector);
        el.focus();
        el.value = params.text;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return true;
      }

      case 'getText': {
        const el = document.querySelector(params.selector);
        if (!el) throw new Error('Element not found: ' + params.selector);
        return el.innerText;
      }

      case 'getHTML': {
        const el = document.querySelector(params.selector);
        if (!el) throw new Error('Element not found: ' + params.selector);
        return el.innerHTML;
      }

      case 'waitForSelector': {
        return !!document.querySelector(params.selector);
      }

      case 'selectAll': {
        // iframe 내부에서 selectAll 시도
        const iframe = document.querySelector('iframe#wysiwygTextarea_ifr, iframe.editor-frame');
        if (iframe && iframe.contentDocument) {
          iframe.contentDocument.execCommand('selectAll', false, null);
          return 'iframe';
        }
        // 일반 문서에서 selectAll
        document.execCommand('selectAll', false, null);
        return 'document';
      }

      case 'insertText': {
        // iframe 내부 시도 우선
        const iframe = document.querySelector('iframe#wysiwygTextarea_ifr, iframe.editor-frame');
        if (iframe && iframe.contentDocument) {
          iframe.contentDocument.execCommand('insertText', false, params.text);
          return 'iframe';
        }
        // 현재 포커스된 요소
        const activeEl = document.activeElement;
        if (activeEl.isContentEditable || activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT') {
          document.execCommand('insertText', false, params.text);
          return 'active';
        }
        return false;
      }

      case 'getVersion':
        return { version: VERSION, mode: 'Scripty' };

      case 'setHostname':
        localStorage.setItem(STORAGE_KEY, params.hostname);
        return { hostname: params.hostname };

      case 'getPageInfo':
        return {
          url: location.href,
          title: document.title,
          hostname: getHostname(),
          clientId: clientId
        };

      case 'eval': {
        // 주의: 보안상 신뢰된 환경에서만 사용
        if (params.code) {
          const result = eval(params.code);
          return result;
        }
        throw new Error('No code provided');
      }

      default:
        throw new Error('Unknown action: ' + action);
    }
  }

  // 페이지 언로드 시 정리
  window.addEventListener('beforeunload', () => {
    if (ws) {
      ws.close();
    }
  });

  // 연결 시작
  console.log('[RTunnel] Scripty v' + VERSION + ' initializing...');
  connect();

  // 전역 API 노출 (디버깅/수동 제어용)
  window.rtunnel = {
    version: VERSION,
    getStatus: () => ({
      connected: ws?.readyState === WebSocket.OPEN,
      clientId: clientId,
      hostname: getHostname()
    }),
    reconnect: () => {
      if (ws) ws.close();
      reconnectAttempts = 0;
      connect();
    },
    setHostname: (name) => {
      localStorage.setItem(STORAGE_KEY, name);
      console.log('[RTunnel] Hostname set to:', name);
    },
    disconnect: () => {
      if (reconnectTimer) clearTimeout(reconnectTimer);
      reconnectTimer = null;
      if (ws) ws.close();
      ws = null;
    }
  };

  console.log('[RTunnel] Ready. Use window.rtunnel.getStatus() to check connection.');
})();
