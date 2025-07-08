#!/bin/bash

# Test script for the Rinha de Backend 2025 Swift implementation

set -e

BASE_URL="http://localhost:9999"

echo "🧪 Testing Swift/Vapor Rinha de Backend implementation..."

# Test health endpoint
echo "1. Testing health endpoint..."
curl -s "$BASE_URL/health" | jq .

# Test payments endpoint
echo "2. Testing payment creation..."
PAYMENT_DATA='{
    "correlationId": "550e8400-e29b-41d4-a716-446655440000",
    "amount": 19.90
}'

curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYMENT_DATA" \
  "$BASE_URL/payments" | jq .

# Test another payment
echo "3. Testing another payment..."
PAYMENT_DATA2='{
    "correlationId": "550e8400-e29b-41d4-a716-446655440001",
    "amount": 50.00
}'

curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "$PAYMENT_DATA2" \
  "$BASE_URL/payments" | jq .

# Test payments summary
echo "4. Testing payments summary..."
curl -s "$BASE_URL/payments-summary" | jq .

# Test payments summary with date range
echo "5. Testing payments summary with date range..."
FROM_DATE="2024-01-01T00:00:00.000Z"
TO_DATE="2024-12-31T23:59:59.999Z"

curl -s "$BASE_URL/payments-summary?from=$FROM_DATE&to=$TO_DATE" | jq .

echo "✅ All tests completed!" 