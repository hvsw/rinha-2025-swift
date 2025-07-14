#!/bin/bash

# Script para build e push da imagem Swift/Vapor para Docker Hub
# Rinha de Backend 2025

set -e

echo "🚀 Build e Push da Imagem Swift/Vapor para Docker Hub"
echo "======================================================"

# Configurações
DOCKER_USERNAME="valcanaia"
IMAGE_NAME="rinha-backend-2025-swift"
TAG="latest"
FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${TAG}"

# Verificar se Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker não está rodando. Inicie o Docker e tente novamente."
    exit 1
fi

# Verificar se está logado no Docker Hub
if ! docker system info | grep -q "Username"; then
    echo "📝 Fazendo login no Docker Hub..."
    docker login
fi

echo "🏗️ Fazendo build da imagem..."
docker build -t ${FULL_IMAGE_NAME} .

echo "📊 Verificando tamanho da imagem..."
docker images ${FULL_IMAGE_NAME}

echo "🧪 Testando imagem localmente..."
# Testar se a imagem roda sem erros
if docker run --rm ${FULL_IMAGE_NAME} --help > /dev/null 2>&1; then
    echo "✅ Imagem funciona corretamente"
else
    echo "⚠️  Imagem criada, mas teste básico falhou"
fi

echo "🚀 Fazendo push para Docker Hub..."
docker push ${FULL_IMAGE_NAME}

echo ""
echo "✅ SUCESSO! Imagem publicada:"
echo "   ${FULL_IMAGE_NAME}"
echo ""
echo "🔗 Disponível em: https://hub.docker.com/r/${DOCKER_USERNAME}/${IMAGE_NAME}"
echo ""
echo "📝 Para usar na submissão:"
echo "   image: ${FULL_IMAGE_NAME}"
echo ""
echo "🧪 Para testar localmente:"
echo "   docker pull ${FULL_IMAGE_NAME}"
echo "   docker run --rm -p 8080:8080 ${FULL_IMAGE_NAME}" 