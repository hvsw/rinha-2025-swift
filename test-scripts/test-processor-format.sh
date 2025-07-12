#!/bin/bash

echo "🔍 TESTE: Formato de Dados dos Processadores"
echo "============================================="

# Test different data formats to understand what processors expect

echo "📤 Testando formato 1: ISO 8601 padrão"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440000", "amount": 100.0, "requestedAt": "2024-01-01T00:00:00Z"}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 2: ISO 8601 com milissegundos"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440001", "amount": 100.0, "requestedAt": "2024-01-01T00:00:00.000Z"}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 3: Sem requestedAt"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440002", "amount": 100.0}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 4: Amount como integer"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440003", "amount": 100, "requestedAt": "2024-01-01T00:00:00Z"}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 5: UUID sem hífens"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400e29b41d4a716446655440004", "amount": 100.0, "requestedAt": "2024-01-01T00:00:00Z"}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 6: Data timestamp Unix"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440005", "amount": 100.0, "requestedAt": 1704067200}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📤 Testando formato 7: Data como string simples"
curl -s -X POST "http://localhost:8001/payments" \
  -H "Content-Type: application/json" \
  -d '{"correlationId": "550e8400-e29b-41d4-a716-446655440006", "amount": 100.0, "requestedAt": "2024-01-01 00:00:00"}' \
  -w "Status: %{http_code}\n"

echo ""
echo "📊 Verificando se algum pagamento foi processado..."
curl -s "http://localhost:8001/admin/summary" | jq '.' 