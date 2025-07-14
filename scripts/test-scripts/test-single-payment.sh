#!/bin/bash

echo "🧪 Teste: Single Payment Processing"
echo "=================================="

# Generate unique correlation ID
CORRELATION_ID=$(uuidgen)
AMOUNT=1000

echo "📤 Enviando pagamento..."
echo "Correlation ID: $CORRELATION_ID"
echo "Amount: $AMOUNT"

# Send payment
RESPONSE=$(curl -s -X POST "http://localhost:9999/payments" \
  -H "Content-Type: application/json" \
  -d "{\"correlationId\": \"$CORRELATION_ID\", \"amount\": $AMOUNT}")

echo "Response: $RESPONSE"

echo ""
echo "⏳ Aguardando processamento (5 segundos)..."
sleep 5

echo ""
echo "📊 Verificando status dos pagamentos..."

# Check API summary
echo "--- API Summary ---"
curl -s "http://localhost:9999/payments-summary" | jq '.'

echo ""
echo "--- Processador Default (8001) ---"
curl -s "http://localhost:8001/admin/payments-summary" | jq '.'

echo ""
echo "--- Processador Fallback (8002) ---"
curl -s "http://localhost:8002/admin/payments-summary" | jq '.'

echo ""
echo "📋 Logs das APIs (últimas 5 linhas):"
echo "--- API01 ---"
docker logs rinhabackend-api01-1 2>&1 | tail -5

echo ""
echo "--- API02 ---"
docker logs rinhabackend-api02-1 2>&1 | tail -5 