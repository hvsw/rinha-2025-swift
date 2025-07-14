#!/bin/bash

echo "🧪 RINHA DE BACKEND 2025 - SUITE DE TESTES"
echo "=========================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if containers are running
echo "🔍 Verificando se os containers estão rodando..."
if ! docker ps | grep -q "rinhabackend"; then
    echo "❌ Containers não estão rodando. Execute: docker-compose up -d"
    exit 1
fi

echo "✅ Containers detectados"
echo ""

# Create results directory
RESULTS_DIR="$SCRIPT_DIR/test-results"
mkdir -p "$RESULTS_DIR"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$RESULTS_DIR/test_run_$TIMESTAMP.log"

echo "📁 Logs serão salvos em: $LOG_FILE"
echo ""

# Function to run test and log results
run_test() {
    local test_name="$1"
    local script_path="$2"
    
    echo "🚀 Executando: $test_name"
    echo "=================================="
    echo ""
    
    # Log to file
    echo "=== $test_name - $(date) ===" >> "$LOG_FILE"
    
    # Make script executable and run
    chmod +x "$script_path"
    "$script_path" 2>&1 | tee -a "$LOG_FILE"
    
    echo ""
    echo "✅ $test_name concluído"
    echo ""
    echo "⏳ Aguardando 5 segundos antes do próximo teste..."
    sleep 5
    echo ""
}

# Run tests in sequence
echo "🎯 Iniciando suite de testes..."
echo ""

# Test 1: Health Check
run_test "Health Check e Conectividade" "$SCRIPT_DIR/test-health-check.sh"

# Test 2: Single Payment
run_test "Single Payment Processing" "$SCRIPT_DIR/test-single-payment.sh"

# Test 3: Parallel Payments
run_test "Parallel Payments Processing" "$SCRIPT_DIR/test-parallel-payments.sh"

# Test 4: Load Simulation
run_test "Load Simulation" "$SCRIPT_DIR/test-load-simulation.sh"

# Final summary
echo "🎉 SUITE DE TESTES CONCLUÍDA"
echo "============================"
echo ""
echo "📊 Resumo final dos serviços:"

echo ""
echo "--- API Principal ---"
curl -s "http://localhost:9999/payments-summary" | jq '.'

echo ""
echo "--- Processador Default ---"
curl -s "http://localhost:8001/admin/payments-summary" | jq '.'

echo ""
echo "--- Processador Fallback ---"
curl -s "http://localhost:8002/admin/payments-summary" | jq '.'

echo ""
echo "📋 Logs completos salvos em: $LOG_FILE"

# Create summary file
SUMMARY_FILE="$RESULTS_DIR/summary_$TIMESTAMP.json"
echo "📄 Criando resumo em: $SUMMARY_FILE"

# Get final states
API_SUMMARY=$(curl -s "http://localhost:9999/payments-summary")
DEFAULT_SUMMARY=$(curl -s "http://localhost:8001/admin/payments-summary" 2>/dev/null || echo '{}')
FALLBACK_SUMMARY=$(curl -s "http://localhost:8002/admin/payments-summary" 2>/dev/null || echo '{}')

# Create comprehensive summary
cat > "$SUMMARY_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "test_run_id": "$TIMESTAMP",
  "api_summary": $API_SUMMARY,
  "default_processor": $DEFAULT_SUMMARY,
  "fallback_processor": $FALLBACK_SUMMARY,
  "containers_status": $(docker ps --format '{"name":"{{.Names}}","status":"{{.Status}}","ports":"{{.Ports}}"}' | jq -s '.'),
  "log_file": "$LOG_FILE"
}
EOF

echo ""
echo "✅ Resumo JSON criado: $SUMMARY_FILE"
echo ""
echo "🔍 Para analisar os resultados:"
echo "  - Logs completos: cat $LOG_FILE"
echo "  - Resumo JSON: cat $SUMMARY_FILE | jq '.'"
echo ""
echo "🎯 Próximos passos sugeridos:"
echo "  - Analisar taxa de processamento nos logs"
echo "  - Verificar distribuição default vs fallback"
echo "  - Executar teste K6 completo se os resultados estiverem bons" 