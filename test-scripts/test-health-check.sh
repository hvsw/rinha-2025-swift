#!/bin/bash

echo "🧪 Teste: Health Check e Conectividade"
echo "======================================"

echo "🔍 Verificando conectividade dos serviços..."

# Test main API
echo ""
echo "--- API Principal (9999) ---"
API_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9999/payments-summary")
if [ "$API_STATUS" = "200" ]; then
    echo "✅ API Principal: OK ($API_STATUS)"
    curl -s "http://localhost:9999/payments-summary" | jq '.'
else
    echo "❌ API Principal: FALHA ($API_STATUS)"
fi

# Test default processor
echo ""
echo "--- Processador Default (8001) ---"
DEFAULT_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8001/payments/service-health")
if [ "$DEFAULT_HEALTH" = "200" ]; then
    echo "✅ Default Health Check: OK ($DEFAULT_HEALTH)"
    curl -s "http://localhost:8001/payments/service-health" | jq '.'
else
    echo "❌ Default Health Check: FALHA ($DEFAULT_HEALTH)"
fi

DEFAULT_ADMIN=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8001/admin/payments-summary")
if [ "$DEFAULT_ADMIN" = "200" ]; then
    echo "✅ Default Admin: OK ($DEFAULT_ADMIN)"
    curl -s "http://localhost:8001/admin/payments-summary" | jq '.'
else
    echo "❌ Default Admin: FALHA ($DEFAULT_ADMIN)"
fi

# Test fallback processor
echo ""
echo "--- Processador Fallback (8002) ---"
FALLBACK_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8002/payments/service-health")
if [ "$FALLBACK_HEALTH" = "200" ]; then
    echo "✅ Fallback Health Check: OK ($FALLBACK_HEALTH)"
    curl -s "http://localhost:8002/payments/service-health" | jq '.'
else
    echo "❌ Fallback Health Check: FALHA ($FALLBACK_HEALTH)"
fi

FALLBACK_ADMIN=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8002/admin/payments-summary")
if [ "$FALLBACK_ADMIN" = "200" ]; then
    echo "✅ Fallback Admin: OK ($FALLBACK_ADMIN)"
    curl -s "http://localhost:8002/admin/payments-summary" | jq '.'
else
    echo "❌ Fallback Admin: FALHA ($FALLBACK_ADMIN)"
fi

echo ""
echo "🐳 Status dos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "📊 Resumo de conectividade:"
echo "- API Principal: $([ "$API_STATUS" = "200" ] && echo "✅ OK" || echo "❌ FALHA")"
echo "- Default Health: $([ "$DEFAULT_HEALTH" = "200" ] && echo "✅ OK" || echo "❌ FALHA")"
echo "- Default Admin: $([ "$DEFAULT_ADMIN" = "200" ] && echo "✅ OK" || echo "❌ FALHA")"
echo "- Fallback Health: $([ "$FALLBACK_HEALTH" = "200" ] && echo "✅ OK" || echo "❌ FALHA")"
echo "- Fallback Admin: $([ "$FALLBACK_ADMIN" = "200" ] && echo "✅ OK" || echo "❌ FALHA")"

# Test direct processor communication
echo ""
echo "🔗 Teste de comunicação direta com processadores:"

echo ""
echo "--- Teste POST Default ---"
TEST_ID=$(uuidgen)
DEFAULT_POST=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:8001/payments" \
    -H "Content-Type: application/json" \
    -d "{\"correlationId\": \"$TEST_ID\", \"amount\": 100, \"requestedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")

echo "Default POST status: $DEFAULT_POST"

echo ""
echo "--- Teste POST Fallback ---"
TEST_ID2=$(uuidgen)
FALLBACK_POST=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:8002/payments" \
    -H "Content-Type: application/json" \
    -d "{\"correlationId\": \"$TEST_ID2\", \"amount\": 200, \"requestedAt\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}")

echo "Fallback POST status: $FALLBACK_POST"

echo ""
echo "⏳ Aguardando processamento (3 segundos)..."
sleep 3

echo ""
echo "📊 Verificando se os testes diretos foram processados:"
echo "--- Default após teste direto ---"
curl -s "http://localhost:8001/admin/payments-summary" | jq '.'

echo ""
echo "--- Fallback após teste direto ---"
curl -s "http://localhost:8002/admin/payments-summary" | jq '.' 