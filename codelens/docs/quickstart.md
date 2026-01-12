# CodeLens 빠른 시작 가이드

CodeLens는 HTML/JS 파일을 분석하여 AST 기반 청크 분리 및 구조 분석을 제공하는 도구입니다.

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

### 3. LLM 엔드포인트 설정

`config/settings.yaml` 파일을 편집하여 LLM 엔드포인트를 설정합니다:

```yaml
llm:
  endpoint: "http://<LLM_SERVER_IP>:8000/v1"
  model: "your-model-name"
  api_key: "your-api-key"  # 필요시
```

### 4. 서버 시작

```bash
./run_server.sh
```

서버는 기본적으로 `http://0.0.0.0:8080`에서 실행됩니다.

## 클라이언트 설치 (개발자 PC)

### 1. 바이너리 다운로드 및 설치

```bash
tar -xzvf codelens-cli-1.0.0-linux-arm64.tar.gz
sudo mv codelens /usr/local/bin/
```

또는 PATH에 추가:

```bash
export PATH=$PATH:/path/to/codelens
```

### 2. 서버 연결 설정

```bash
codelens config set server.url http://<서버IP>:8080
```

## 사용법

### 파일 분석

```bash
codelens analyze /path/to/large-file.html
```

### 옵션

```bash
# 출력 형식 지정
codelens analyze /path/to/file.html --format json

# 출력 파일 지정
codelens analyze /path/to/file.html --output result.json

# 청크 크기 제한
codelens analyze /path/to/file.html --max-chunk-size 4096
```

### 설정 확인

```bash
codelens config show
```

## API 엔드포인트

서버는 다음 API를 제공합니다:

- `POST /analyze` - 파일 분석
- `GET /health` - 서버 상태 확인

## 문제 해결

### 서버 연결 실패

1. 서버가 실행 중인지 확인: `curl http://<서버IP>:8080/health`
2. 방화벽 설정 확인
3. 클라이언트 설정 확인: `codelens config show`

### LLM 분석 실패

1. `config/settings.yaml`의 LLM 엔드포인트 확인
2. LLM 서버 상태 확인
3. 서버 로그 확인
