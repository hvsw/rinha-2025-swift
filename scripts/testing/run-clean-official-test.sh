#!/bin/bash

echo "🧪 TESTE OFICIAL K6 - SWIFT/VAPOR"
echo "================================="

# Obter diretório base
SCRIPT_DIR="$(dirname "$0")"
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configurar MAX_REQUESTS 
export MAX_REQUESTS=${MAX_REQUESTS:-550}
echo "📊 MAX_REQUESTS configurado para: $MAX_REQUESTS"

# Detectar arquitetura
ARCH=$(uname -m)
echo "🔍 Arquitetura detectada: $ARCH"

# Escolher docker-compose correto para payment processors
if [[ "$ARCH" == "arm64" ]]; then
    PAYMENT_COMPOSE="docker-compose-arm64.yml"
    echo "🍎 Usando payment processors ARM64 (Mac)"
else
    PAYMENT_COMPOSE="docker-compose.yml"
    echo "🐧 Usando payment processors AMD64 (Linux)"
fi

echo ""
echo "🧹 Limpeza completa do Docker..."

# Limpeza completa para garantir ambiente limpo
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
docker volume prune -f > /dev/null 2>&1
docker network prune -f > /dev/null 2>&1

echo "✅ Limpeza Docker completa!"

echo ""
echo "🚀 Subindo Payment Processors ($PAYMENT_COMPOSE)..."

# Subir payment processors primeiro
cd "$BASE_DIR/../rinha-de-backend-2025/payment-processor"
docker compose -f "$PAYMENT_COMPOSE" up -d

echo ""
echo "🚀 Subindo nosso backend Swift/Vapor..."

# Subir nosso backend
cd "$BASE_DIR"
docker compose up -d

echo ""
echo "⏳ Aguardando serviços ficarem prontos..."

# Aguardar payment processors
echo "Verificando Payment Processors..."
for i in {1..30}; do
    if curl -f -s http://localhost:8001/payments/service-health > /dev/null 2>&1 && \
       curl -f -s http://localhost:8002/payments/service-health > /dev/null 2>&1; then
        echo "✅ Payment Processors prontos!"
        break
    fi
    echo "Tentativa $i/30 - aguardando processors..."
    sleep 3
done

# Aguardar nossa API
echo "Verificando nossa API..."
for i in {1..30}; do
    if curl -f -s http://localhost:9999/payments-summary > /dev/null 2>&1; then
        echo "✅ API Swift/Vapor pronta!"
        break
    fi
    echo "Tentativa $i/30 - aguardando API..."
    sleep 2
done

echo ""
echo "🔍 Verificação final dos serviços:"
echo "- Payment Processor Default (8001): $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/payments/service-health)"
echo "- Payment Processor Fallback (8002): $(curl -s -o /dev/null -w "%{http_code}" http://localhost:8002/payments/service-health)"  
echo "- API Swift/Vapor (9999): $(curl -s -o /dev/null -w "%{http_code}" http://localhost:9999/payments-summary)"

# Verificar se todos os serviços estão funcionando
DEFAULT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8001/payments/service-health)
FALLBACK_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8002/payments/service-health)
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9999/payments-summary)

if [[ "$DEFAULT_STATUS" != "200" ]] || [[ "$FALLBACK_STATUS" != "200" ]] || [[ "$API_STATUS" != "200" ]]; then
    echo ""
    echo "❌ ERRO: Nem todos os serviços estão respondendo corretamente!"
    echo "- Default: $DEFAULT_STATUS (esperado: 200)"
    echo "- Fallback: $FALLBACK_STATUS (esperado: 200)"
    echo "- API: $API_STATUS (esperado: 200)"
    echo ""
    echo "🔍 Verificando logs dos containers..."
    echo "--- Payment Default ---"
    docker logs payment-processor-default 2>&1 | tail -10
    echo "--- Payment Fallback ---"
    docker logs payment-processor-fallback 2>&1 | tail -10
    echo "--- Parando containers e saindo ---"
    
    # Parar containers
    cd "$BASE_DIR"
    docker compose down
    cd "$BASE_DIR/../rinha-de-backend-2025/payment-processor"
    docker compose -f "$PAYMENT_COMPOSE" down
    
    exit 1
fi

echo ""
echo "🎯 EXECUTANDO TESTE OFICIAL K6..."
echo "================================="

# Ir para o diretório de testes oficial
cd "$BASE_DIR/../rinha-de-backend-2025/rinha-test"

# Configurar dashboard do K6 (opcional)
export K6_WEB_DASHBOARD=false
export K6_WEB_DASHBOARD_PORT=5665
export K6_WEB_DASHBOARD_PERIOD=2s
export K6_WEB_DASHBOARD_EXPORT="$BASE_DIR/results/report-official-$(date +%Y%m%d_%H%M%S).html"

# Executar K6 oficial diretamente (SEM run-tests.sh)
echo "Executando: k6 run -e MAX_REQUESTS=$MAX_REQUESTS rinha.js"
echo ""

k6 run -e MAX_REQUESTS=$MAX_REQUESTS rinha.js

RESULT_CODE=$?

echo ""
echo "🎯 TESTE OFICIAL CONCLUÍDO!"
echo "=========================="

if [ $RESULT_CODE -eq 0 ]; then
    echo "✅ Teste executado com sucesso!"
else
    echo "❌ Teste falhou com código: $RESULT_CODE"
fi

echo ""
echo "📊 Resultado final da API:"
curl -s "http://localhost:9999/payments-summary" | jq '.' || echo "Erro ao obter summary"

echo ""
echo "🧹 Parando containers..."

# Parar nosso backend
cd "$BASE_DIR"
docker compose down

# Parar payment processors  
cd "$BASE_DIR/../rinha-de-backend-2025/payment-processor"
docker compose -f "$PAYMENT_COMPOSE" down

echo ""
echo "✅ Teste oficial finalizado!"
echo "📁 Relatório salvo em: $BASE_DIR/results/"

exit $RESULT_CODE 