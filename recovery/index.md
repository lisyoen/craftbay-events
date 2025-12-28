# CraftBay 복구 가이드

Spark 서버 또는 MCP 장애 시 복구 절차

---

## 인프라 정보

| 항목 | 값 |
|------|-----|
| Spark 서버 | DGX Spark (192.168.219.189) - 메인 서버 |
| miniPC | 192.168.219.100 - 백업/복구용 |
| CraftBay MCP | https://mcp.craftbay.io/mcp (포트 9060) |
| Recovery MCP | https://spark-recovery.craftbay.io/mcp (miniPC 포트 9060) |
| Cloudflare Tunnel | ID: 5bd2fd2c-665c-4d85-959d-54c3eca2a743 |

---

## 1. CraftBay MCP 복구 (우선)

MCP가 응답하지 않을 때 - Recovery MCP의 `exec_command`로 실행:

```bash
# 1. PM2 상태 확인
ssh spark "pm2 list"

# 2. MCP 서버 재시작
ssh spark "pm2 restart mcp-server"

# 3. MCP 로그 확인
ssh spark "pm2 logs mcp-server --lines 20"
```

> 복구 후 사용자에게 CraftBay MCP 재연결 요청 (claude.ai 새로고침)

---

## 2. Cloudflare Tunnel 복구

*.craftbay.io 도메인 접속 불가 시:

```bash
# 1. 터널 상태 확인
ssh spark "sudo systemctl status cloudflared"

# 2. 터널 재시작
ssh spark "sudo systemctl restart cloudflared"

# 3. 터널 로그 확인
ssh spark "sudo journalctl -u cloudflared --lines 30"
```

---

## 3. Spark 서버 접속 불가 (긴급)

`ssh spark` 자체가 실패할 때:

```bash
# 네트워크 확인
ping 192.168.219.189
```

⚠️ 응답 없으면 사용자(창연)의 물리적 개입 필요. 전원, 네트워크 케이블, 콘솔 접속 확인.

---

## 서비스 포트 맵

| 서비스 | 포트 | PM2 이름 |
|--------|------|----------|
| Zodiac Guesser | 9010 | zodiac |
| Life EXP | 9020 | lifeexp |
| PoliLog | 9030 | polilog |
| IP Search | 9040 | ipsearch |
| ClaudeQ | 9050 | claudeq |
| MCP Server | 9060 | mcp-server |
| Notify | 9074 | notify |

---

## 이 페이지 수정 방법

**Spark에서 (정상 상태):**
```bash
cd /tmp/craftbay-events
# 수정 후
git add recovery/ && git commit -m "Update recovery guide" && git push
```

**miniPC에서 (Spark 장애 시):**
```bash
cd ~/craftbay-events
git pull
# 수정 후
git add recovery/ && git commit -m "Update recovery guide" && git push
```

GitHub Pages 배포: push 후 1-2분 내 자동 반영

---

*최종 업데이트: 2025-12-28 | [CraftBay](https://craftbay.io)*
