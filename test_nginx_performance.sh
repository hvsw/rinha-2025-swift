#!/bin/bash

echo "🎯 TESTE DE PERFORMANCE NGINX - FASE 3A"
echo "========================================"

# Limpar dados anteriores
echo "Limpando dados..."
curl -s "http://localhost:9999/health" > /dev/null

# Teste de throughput simples
echo "📊 Executando teste de throughput..."
START_TIME=$(date +%s.%N)

# Enviar 100 requisições em paralelo
for i in {1..100}; do
    {
        UUID=$(uuidgen)
        AMOUNT=$((1000 + RANDOM % 1000))
        curl -s -X POST "http://localhost:9999/payments" \
             -H "Content-Type: application/json" \
             -d "{\"amount\": $AMOUNT, \"currency\": \"BRL\", \"correlationId\": \"$UUID\"}" > /dev/null
    } &
done

# Aguardar todas as requisições
wait

END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)
THROUGHPUT=$(echo "scale=2; 100 / $DURATION" | bc)

echo "✅ Tempo total: ${DURATION}s"
echo "✅ Throughput: ${THROUGHPUT} req/s"

# Aguardar processamento
echo "⏳ Aguardando processamento..."
sleep 3

# Verificar summary
echo "📊 Verificando resultados..."
SUMMARY=$(curl -s "http://localhost:9999/payments-summary")
echo "Summary: $SUMMARY"

echo ""
echo "🎯 FASE 3A - NGINX ULTRA-OTIMIZADO"
echo "Throughput: ${THROUGHPUT} req/s"
echo "Configurações aplicadas:"
echo "  ✅ worker_connections: 2048 (dobrado)"
echo "  ✅ use epoll (Linux optimized)"
echo "  ✅ multi_accept on"
echo "  ✅ keepalive otimizado"
echo "  ✅ tcp_nopush + tcp_nodelay" 