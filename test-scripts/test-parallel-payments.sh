#!/bin/bash

echo "🧪 Teste: Parallel Payments Processing"
echo "======================================"

NUM_PAYMENTS=20
CONCURRENT_REQUESTS=5

echo "📤 Enviando $NUM_PAYMENTS pagamentos em $CONCURRENT_REQUESTS threads paralelas..."

# Function to send a payment
send_payment() {
    local id=$1
    local correlation_id=$(uuidgen)
    local amount=$((100 + RANDOM % 900))  # Random amount between 100-1000
    
    echo "Thread $id: Enviando pagamento $correlation_id (amount: $amount)"
    
    response=$(curl -s -X POST "http://localhost:9999/payments" \
        -H "Content-Type: application/json" \
        -d "{\"correlationId\": \"$correlation_id\", \"amount\": $amount}")
    
    echo "Thread $id: Response: $response"
}

# Get initial state
echo "📊 Estado inicial:"
curl -s "http://localhost:9999/payments-summary" | jq '.'

echo ""
echo "🚀 Iniciando envio de pagamentos..."

# Send payments in parallel
for i in $(seq 1 $NUM_PAYMENTS); do
    # Limit concurrent requests
    while [ $(jobs -r | wc -l) -ge $CONCURRENT_REQUESTS ]; do
        sleep 0.1
    done
    
    send_payment $i &
done

# Wait for all background jobs to complete
wait

echo ""
echo "⏳ Aguardando processamento (10 segundos)..."
sleep 10

echo ""
echo "📊 Estado final:"

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
echo "📋 Logs das APIs (últimas 10 linhas):"
echo "--- API01 ---"
docker logs rinhabackend-api01-1 2>&1 | tail -10

echo ""
echo "--- API02 ---"
docker logs rinhabackend-api02-1 2>&1 | tail -10 