#!/bin/bash

# Script inteligente para build da imagem Swift/Vapor - Rinha 2025
# ================================================================
# Uso: 
#   ./build-and-push.sh                    # Build local (macOS ARM64) 
#   ./build-and-push.sh --submission       # Build para submissão (linux/amd64 + push)
#   ./build-and-push.sh --test-amd64       # Build local linux/amd64 (teste compatibilidade)

set -e

DOCKER_USERNAME="valcanaia"
IMAGE_NAME="rinha-backend-2025-swift"
TAG="latest"
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG}"

# Detectar modo de operação
SUBMISSION_MODE=false
TEST_AMD64_MODE=false

case "${1:-}" in
    --submission)
        SUBMISSION_MODE=true
        echo "🚀 Modo: SUBMISSÃO OFICIAL (linux/amd64 + push para Docker Hub)"
        ;;
    --test-amd64)
        TEST_AMD64_MODE=true
        echo "🧪 Modo: TESTE AMD64 LOCAL (linux/amd64 sem push)"
        ;;
    "")
        echo "🏗️ Modo: DESENVOLVIMENTO LOCAL (arquitetura nativa)"
        ;;
    *)
        echo "❌ Uso: $0 [--submission|--test-amd64]"
        echo "   (sem args) = build local arquitetura nativa"
        echo "   --submission = build linux/amd64 + push Docker Hub"
        echo "   --test-amd64 = build linux/amd64 local (teste)"
        exit 1
        ;;
esac

echo "=========================================================="
echo "Imagem: ${FULL_IMAGE_NAME}"
echo "Diretório: $(pwd)"

# Verificações básicas
if [ ! -f "Package.swift" ]; then
    echo "❌ Execute este script da raiz do projeto!"
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker não está rodando. Inicie o Docker Desktop!"
    exit 1
fi

# Executar build conforme o modo
if [ "$SUBMISSION_MODE" = true ]; then
    echo "📝 Verificando login Docker Hub..."
    if ! docker system info | grep -q "Username"; then
        echo "🔑 Fazendo login no Docker Hub..."
        docker login
    fi
    
    echo "🏗️ Build cross-platform para submissão (linux/amd64)..."
    echo "⚠️  IMPORTANTE: Arquitetura linux/amd64 conforme INSTRUCOES.md"
    docker buildx build --platform linux/amd64 -t ${FULL_IMAGE_NAME} .
    
    echo "🚀 Push para Docker Hub..."
    docker push ${FULL_IMAGE_NAME}
    
    echo "✅ Imagem oficial publicada para submissão!"
    echo "📋 Tag: ${FULL_IMAGE_NAME} (linux/amd64)"
    
elif [ "$TEST_AMD64_MODE" = true ]; then
    echo "🏗️ Build linux/amd64 local para teste de compatibilidade..."
    echo "💡 Testando a mesma arquitetura que será usada na submissão"
    docker buildx build --platform linux/amd64 -t ${FULL_IMAGE_NAME} .
    
    echo "✅ Imagem linux/amd64 construída para teste!"
    echo "💡 Mesma imagem que seria enviada na submissão (sem push)"
    
else
    echo "🏗️ Build nativo para desenvolvimento local..."
    echo "💡 Arquitetura nativa (provavelmente macOS ARM64) - mais rápido"
    docker build -t ${FULL_IMAGE_NAME} .
    
    echo "✅ Imagem local construída!"
    echo "💡 Próximos passos: docker-compose up -d"
fi

echo ""
echo "📊 Imagens disponíveis:"
docker images | grep -E "(${IMAGE_NAME}|REPOSITORY)"

echo ""
echo "🎯 Próximos passos:"
if [ "$SUBMISSION_MODE" = true ]; then
    echo "   - Imagem ${FULL_IMAGE_NAME} publicada no Docker Hub"
    echo "   - Arquitetura: linux/amd64 (compatível com Rinha)"
    echo "   - Pronta para usar na submissão oficial"
elif [ "$TEST_AMD64_MODE" = true ]; then
    echo "   - Testar localmente: docker-compose up -d"
    echo "   - Se funcionar, usar --submission para publicar"
else
    echo "   - Testar compatibilidade: ./build-and-push.sh --test-amd64"
    echo "   - Publicar oficial: ./build-and-push.sh --submission"
fi 