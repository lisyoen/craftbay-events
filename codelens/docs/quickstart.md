# CodeLens 빠른 시작 가이드

CodeLens는 대용량 JavaScript/HTML 파일을 분석하고 AST 기반으로 청크를 분리하여 LLM이 이해할 수 있도록 돕는 도구입니다.

## 시스템 요구사항

- Python 3.10 이상
- Linux (aarch64 또는 x86_64)

## 서버 설치 (LLM 서버)

### 1. 패키지 압축 해제

```bash
tar -xzvf codelens-server-1.0.0.tar.gz
cd codelens-server-1.0.0
```

### 2. 설치 스크립트 실행

```bash
./install-linux.sh
```

### 3. 설정 파일 수정

```bash
vi config/settings.yaml
```

주요 설정:
```yaml
llm:
  base_url: "http://localhost:11434/v1"  # LLM API 엔드포인트
  model: "qwen2.5-coder:14b"              # 모델 이름
  api_key: ""                             # API 키 (필요시)
  timeout: 600                            # 요청 타임아웃 (초)

server:
  host: "0.0.0.0"
  port: 8080
```

### 4. 서버 시작

```bash
./run_server.sh
```

### 5. 헬스체크

```bash
curl http://localhost:8080/health
```

## 클라이언트 설치 (개발자 PC)

### 방법 1: 바이너리 사용

1. 다운로드:
```bash
tar -xzvf codelens-cli-1.0.0-linux-arm64.tar.gz
```

2. PATH에 추가:
```bash
sudo cp codelens /usr/local/bin/
# 또는
export PATH=$PATH:$(pwd)
```

3. 서버 설정:
```bash
codelens config set server.url http://<서버IP>:8080
```

### 방법 2: pip 설치

```bash
pip install codelens-cli
codelens config set server.url http://<서버IP>:8080
```

## 사용법

### 파일 분석

```bash
# 단일 파일 분석
codelens analyze /path/to/large-file.html

# 출력 디렉토리 지정
codelens analyze /path/to/file.js --output ./results

# 백그라운드 실행 (대기 없이)
codelens analyze /path/to/file.html --no-wait
```

### 작업 상태 확인

```bash
# 특정 작업 상태
codelens status <job-id>

# 모든 작업 목록
codelens jobs

# 실행 중인 작업만
codelens jobs --status running
```

### 결과 다운로드

```bash
# 전체 결과 다운로드
codelens download <job-id>

# 특정 파일만 다운로드
codelens download <job-id> --type report
```

### 서버 상태 확인

```bash
codelens health
```

### 설정 관리

```bash
# 현재 설정 보기
codelens config show

# 설정 변경
codelens config set server.url http://192.168.1.100:8080
codelens config set server.timeout 7200

# 설정 값 확인
codelens config get server.url
```

## API 엔드포인트

서버는 다음 API를 제공합니다:

- `POST /analyze` - 파일 분석 시작
- `GET /status/{job_id}` - 작업 상태 조회
- `GET /result/{job_id}` - 결과 다운로드
- `GET /jobs` - 작업 목록 조회
- `GET /health` - 서버 상태 확인

## 출력 파일

분석 완료 후 다음 파일들이 생성됩니다:

- `*_report.md` - 코드 분석 보고서
- `*_refactor.md` - 리팩토링 제안
- `*_architecture.md` - 아키텍처 분석
- `*_modules.json` - 모듈/함수 목록
- `*_metadata.json` - 분석 메타데이터

## 문제 해결

### 연결 오류

```bash
# 서버 상태 확인
curl http://<서버IP>:8080/health

# 방화벽 확인 (서버)
sudo ufw allow 8080
```

### LLM 연결 실패

```bash
# 서버 로그 확인
tail -f logs/service.log

# LLM 엔드포인트 확인
curl http://<LLM서버>/v1/models
```

### 분석 실패

```bash
# 작업 상태에서 오류 확인
codelens status <job-id>
```

## 폐쇄망 환경

이 패키지는 오프라인 설치를 지원합니다. 모든 의존성이 wheels 디렉토리에 포함되어 있어 인터넷 연결 없이 설치할 수 있습니다.

서버 설치:
```bash
cd codelens-server-1.0.0
./install-linux.sh  # --no-index 옵션으로 로컬 wheels 사용
```

클라이언트: 바이너리는 단일 실행 파일로 의존성이 없습니다.
