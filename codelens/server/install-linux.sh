#!/bin/bash
set -e

echo "================================================"
echo "  CodeLens Server 설치"
echo "================================================"
echo ""

# 현재 디렉토리에서 tar.gz 찾기
TARBALL=$(ls -1 codelens-server-*.tar.gz 2>/dev/null | head -1)

if [ -z "$TARBALL" ]; then
    echo "[오류] codelens-server-*.tar.gz 파일을 찾을 수 없습니다."
    echo "       install-linux.sh와 같은 폴더에 tar.gz 파일이 있어야 합니다."
    exit 1
fi

echo "[0/5] 압축 해제 중: $TARBALL"
tar -xzf "$TARBALL"

# 압축 해제된 폴더로 이동
INSTALL_DIR=$(basename "$TARBALL" .tar.gz)
cd "$INSTALL_DIR"
echo "      → $INSTALL_DIR/"

# Python 버전 확인
PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2 | cut -d'.' -f1,2)
REQUIRED_VERSION="3.10"

version_compare() {
    printf '%s\n%s\n' "$REQUIRED_VERSION" "$1" | sort -V | head -n1
}

if [ "$(version_compare "$PYTHON_VERSION")" != "$REQUIRED_VERSION" ]; then
    echo "[오류] Python 3.10 이상이 필요합니다. 현재: Python $PYTHON_VERSION"
    exit 1
fi

echo "[1/5] 가상환경 생성 중..."
python3 -m venv venv
source venv/bin/activate

echo "[2/5] 의존성 설치 중 (오프라인)..."
if [ -d "wheels" ]; then
    pip install --no-index --find-links=wheels -r requirements.txt
else
    echo "      wheels/ 폴더 없음, 온라인 설치 시도..."
    pip install -r requirements.txt
fi

echo "[3/5] CodeLens 설치 중..."
if ls codelens-*.whl 1>/dev/null 2>&1; then
    pip install --no-index --find-links=. codelens-*.whl
else
    echo "      wheel 파일 없음, src에서 직접 실행 가능"
fi

echo "[4/5] 설정 파일 확인..."
if [ ! -f config/settings.yaml ]; then
    mkdir -p config
    echo "      기본 설정 파일 생성 중..."
    cat > config/settings.yaml << 'YAML'
server:
  host: 0.0.0.0
  port: 8080

llm:
  base_url: http://localhost:4000/v1
  model: Qwen/Qwen3-Coder-30B-A3B-Instruct
  api_key: your-api-key-here
  max_context_kb: 256

chunking:
  target_size: 40
  max_size: 60
YAML
fi

echo "[5/5] 실행 스크립트 생성..."
cat > run_server.sh << 'SCRIPT'
#!/bin/bash
source venv/bin/activate
python -m uvicorn src.server:app --host 0.0.0.0 --port 8080
SCRIPT
chmod +x run_server.sh

echo ""
echo "================================================"
echo "  설치 완료!"
echo "================================================"
echo ""
echo "설치 경로: $(pwd)"
echo ""
echo "다음 단계:"
echo "  1. config/settings.yaml에서 LLM 엔드포인트 설정"
echo "  2. ./run_server.sh로 서버 시작"
echo ""
