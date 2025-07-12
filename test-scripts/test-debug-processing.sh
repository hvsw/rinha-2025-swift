#!/bin/bash

echo "🔍 TESTE: Debug Detalhado do Processamento"
echo "=========================================="

# Test single payment with real-time monitoring
CORRELATION_ID=$(uuidgen)
AMOUNT=500

echo "📤 Enviando pagamento para debug..."
echo "Correlation ID: $CORRELATION_ID"
echo "Amount: $AMOUNT"

# Send payment
RESPONSE=$(curl -s -X POST "http://localhost:9999/payments" \
  -H "Content-Type: application/json" \
  -d "{\"correlationId\": \"$CORRELATION_ID\", \"amount\": $AMOUNT}")

echo "Response: $RESPONSE"
echo ""

# Monitor logs in real-time
echo "🔍 Monitorando logs em tempo real (15 segundos)..."

# Function to monitor logs
monitor_logs() {
    local container=$1
    local label=$2
    echo "--- $label ---"
    timeout 15s docker logs -f $container 2>&1 | grep -E "(💰|📦|Worker|Payment|$CORRELATION_ID)" | head -10
}

# Monitor both APIs simultaneously 
echo "🚀 Iniciando monitoramento..."
monitor_logs "rinhabackend-api01-1" "API01" &
monitor_logs "rinhabackend-api02-1" "API02" &

# Wait for monitoring to complete
wait

echo ""
echo "📊 Verificando estado após processamento..."

# Check API summary
echo "--- API Summary ---"
curl -s "http://localhost:9999/payments-summary" | jq '.'

echo ""
echo "--- Processador Default ---"
curl -s "http://localhost:8001/admin/summary" | jq '.' || echo "Erro ao acessar default processor"

echo ""
echo "--- Processador Fallback ---"
curl -s "http://localhost:8002/admin/summary" | jq '.' || echo "Erro ao acessar fallback processor"

echo ""
echo "🔍 Verificando conectividade dos processadores..."

# Test processor connectivity from host
echo "--- Testando conectividade ---"
DEFAULT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8001/payments/service-health")
FALLBACK_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8002/payments/service-health")

echo "Default Health: $DEFAULT_STATUS"
echo "Fallback Health: $FALLBACK_STATUS"

# Check if containers are in the same network
echo ""
echo "🌐 Verificando redes Docker..."
echo "--- API01 Networks ---"
docker inspect rinhabackend-api01-1 | jq '.[0].NetworkSettings.Networks' | head -10

echo ""
echo "--- Processador Default Networks ---"
docker inspect payment-processor-default | jq '.[0].NetworkSettings.Networks' | head -10

echo ""
echo "🔍 Logs finais das APIs (últimas 10 linhas):"
echo "--- API01 ---"
docker logs rinhabackend-api01-1 2>&1 | tail -10

echo ""
echo "--- API02 ---"
docker logs rinhabackend-api02-1 2>&1 | tail -10 