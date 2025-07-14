#!/bin/bash

echo "🧹 Iniciando limpeza completa do Docker..."

# Parar todos os containers
docker stop $(docker ps -aq) 2>/dev/null || true

# Remover todos os containers
docker rm $(docker ps -aq) 2>/dev/null || true

# Remover todas as imagens
docker rmi $(docker images -q) 2>/dev/null || true

# Limpar volumes
docker volume prune -f

# Limpar networks
docker network prune -f

# Limpar system completo
docker system prune -af

echo "✅ Limpeza Docker completa!"

# Obter o diretório base do script (dentro do nosso repositório rinha-2025-swift)
SCRIPT_DIR="$(dirname "$0")"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "🏗️  Subindo Payment Processors primeiro..."

# Ir para o diretório dos Payment Processors no repositório oficial
cd "$BASE_DIR/../rinha-de-backend-2025/payment-processor"

# Subir payment processors usando o arquivo original
docker-compose -f docker-compose-arm64.yml up -d

echo "⏱️  Aguardando payment processors ficarem prontos..."
sleep 15

# Verificar se os payment processors estão funcionando
echo "🔍 Verificando payment processors..."
curl -f http://localhost:8001/payments/service-health && echo "✅ Default OK" || echo "❌ Default FAIL"
curl -f http://localhost:8002/payments/service-health && echo "✅ Fallback OK" || echo "❌ Fallback FAIL"

echo "🏗️  Subindo backend Swift..."

# Ir para o diretório do nosso backend Swift
cd "$BASE_DIR"

# Construir e subir o backend Swift
docker-compose build --no-cache
docker-compose up -d

echo "⏱️  Aguardando backend Swift ficar pronto..."
sleep 15

# Verificar se o backend está funcionando
echo "🔍 Verificando backend Swift..."
curl -f http://localhost:9999/health && echo "✅ Backend OK" || echo "❌ Backend FAIL"

echo "🎯 Executando teste oficial k6..."

# Ir para o diretório de testes no repositório oficial
cd "$BASE_DIR/../rinha-de-backend-2025/rinha-test"

# Executar teste k6
k6 run rinha.js

echo "✅ Teste oficial concluído!" 