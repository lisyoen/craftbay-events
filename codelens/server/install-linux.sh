#!/bin/bash
set -e

echo "================================================"
echo "  CodeLens Server 설치"
echo "================================================"
echo ""

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

echo "[1/4] 가상환경 생성 중..."
python3 -m venv venv
source venv/bin/activate

echo "[2/4] 의존성 설치 중 (오프라인)..."
pip install --no-index --find-links=wheels -r requirements.txt

echo "[3/4] CodeLens 설치 중..."
pip install --no-index --find-links=. codelens-*.whl

echo "[4/4] 설정 파일 확인..."
if [ ! -f config/settings.yaml ]; then
    echo "[경고] config/settings.yaml 파일이 없습니다."
fi

echo ""
echo "================================================"
echo "  설치 완료!"
echo "================================================"
echo ""
echo "다음 단계:"
echo "  1. config/settings.yaml에서 LLM 엔드포인트 설정"
echo "  2. ./run_server.sh로 서버 시작"
echo ""
