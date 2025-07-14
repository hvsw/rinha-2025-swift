#!/bin/bash

echo "🧪 Teste: Load Simulation"
echo "========================="

DURATION=30  # seconds
CONCURRENT_REQUESTS=10
REQUESTS_PER_SECOND=10

echo "📊 Configuração do teste:"
echo "- Duração: $DURATION segundos"
echo "- Requests concorrentes: $CONCURRENT_REQUESTS"
echo "- Target RPS: $REQUESTS_PER_SECOND"

# Function to send continuous payments
send_continuous_payments() {
    local thread_id=$1
    local end_time=$(($(date +%s) + DURATION))
    local request_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        local correlation_id=$(uuidgen)
        local amount=$((100 + RANDOM % 900))
        
        curl -s -X POST "http://localhost:9999/payments" \
            -H "Content-Type: application/json" \
            -d "{\"correlationId\": \"$correlation_id\", \"amount\": $amount}" > /dev/null
        
        request_count=$((request_count + 1))
        
        # Control rate
        sleep 0.1
    done
    
    echo "Thread $thread_id: Sent $request_count requests"
}

# Get initial state
echo ""
echo "📊 Estado inicial:"
INITIAL_SUMMARY=$(curl -s "http://localhost:9999/payments-summary")
echo "$INITIAL_SUMMARY" | jq '.'

INITIAL_DEFAULT=$(curl -s "http://localhost:8001/admin/payments-summary" 2>/dev/null || echo '{"total_requests": 0}')
INITIAL_FALLBACK=$(curl -s "http://localhost:8002/admin/payments-summary" 2>/dev/null || echo '{"total_requests": 0}')

echo ""
echo "🚀 Iniciando simulação de carga..."

# Start load generation
for i in $(seq 1 $CONCURRENT_REQUESTS); do
    send_continuous_payments $i &
done

# Monitor progress
for i in $(seq 1 $DURATION); do
    echo -n "."
    sleep 1
    
    # Show progress every 10 seconds
    if [ $((i % 10)) -eq 0 ]; then
        echo ""
        echo "📊 Progresso ($i/${DURATION}s):"
        curl -s "http://localhost:9999/payments-summary" | jq '.total_requests'
    fi
done

# Wait for all requests to complete
wait

echo ""
echo "⏳ Aguardando processamento final (15 segundos)..."
sleep 15

echo ""
echo "📊 Resultados finais:"

# Get final state
FINAL_SUMMARY=$(curl -s "http://localhost:9999/payments-summary")
echo "--- API Summary ---"
echo "$FINAL_SUMMARY" | jq '.'

FINAL_DEFAULT=$(curl -s "http://localhost:8001/admin/payments-summary" 2>/dev/null || echo '{"total_requests": 0}')
FINAL_FALLBACK=$(curl -s "http://localhost:8002/admin/payments-summary" 2>/dev/null || echo '{"total_requests": 0}')

echo ""
echo "--- Processador Default (8001) ---"
echo "$FINAL_DEFAULT" | jq '.'

echo ""
echo "--- Processador Fallback (8002) ---"
echo "$FINAL_FALLBACK" | jq '.'

echo ""
echo "📈 Análise de Performance:"

# Calculate differences
INITIAL_TOTAL=$(echo "$INITIAL_SUMMARY" | jq -r '.total_requests // 0')
FINAL_TOTAL=$(echo "$FINAL_SUMMARY" | jq -r '.total_requests // 0')
REQUESTS_SENT=$((FINAL_TOTAL - INITIAL_TOTAL))

INITIAL_DEFAULT_COUNT=$(echo "$INITIAL_DEFAULT" | jq -r '.total_requests // 0')
FINAL_DEFAULT_COUNT=$(echo "$FINAL_DEFAULT" | jq -r '.total_requests // 0')
DEFAULT_PROCESSED=$((FINAL_DEFAULT_COUNT - INITIAL_DEFAULT_COUNT))

INITIAL_FALLBACK_COUNT=$(echo "$INITIAL_FALLBACK" | jq -r '.total_requests // 0')
FINAL_FALLBACK_COUNT=$(echo "$FINAL_FALLBACK" | jq -r '.total_requests // 0')
FALLBACK_PROCESSED=$((FINAL_FALLBACK_COUNT - INITIAL_FALLBACK_COUNT))

TOTAL_PROCESSED=$((DEFAULT_PROCESSED + FALLBACK_PROCESSED))

echo "- Requests enviados: $REQUESTS_SENT"
echo "- Requests processados: $TOTAL_PROCESSED"
echo "- Default processados: $DEFAULT_PROCESSED"
echo "- Fallback processados: $FALLBACK_PROCESSED"
echo "- Taxa de processamento: $(( TOTAL_PROCESSED * 100 / (REQUESTS_SENT + 1) ))%"

if [ $TOTAL_PROCESSED -gt 0 ]; then
    echo "- Default usage: $(( DEFAULT_PROCESSED * 100 / TOTAL_PROCESSED ))%"
fi

echo ""
echo "📋 Logs recentes:"
echo "--- API01 (últimas 5 linhas) ---"
docker logs rinhabackend-api01-1 2>&1 | tail -5

echo ""
echo "--- API02 (últimas 5 linhas) ---"
docker logs rinhabackend-api02-1 2>&1 | tail -5 