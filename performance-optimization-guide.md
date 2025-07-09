# Guia de Otimização de Performance - Baseado na Rinha de Backend 2023

*Técnicas extraídas do vídeo de análise do Fábio Akita sobre a Rinha de Backend*

## 🎯 Princípios Fundamentais

### 1. **Não Faça Otimização Prematura**
- ⚠️ "Otimização prematura é a raiz de todo o mal"
- Sempre meça antes de otimizar
- Identifique o real gargalo, não assuma
- Cache não deixa nada rápido automaticamente

### 2. **Identifique o Tipo de Problema**
- **CPU Bound**: Limitação de processamento
- **I/O Bound**: Limitação de entrada/saída (mais comum em web)
- **Memory Bound**: Limitação de memória
- **Network Bound**: Limitação de rede

## 🔧 Técnicas de Otimização

### **1. Controle de Fluxo de Requisições**

#### Nginx Configuration
```nginx
# ❌ ERRADO: Permitir muitas conexões simultâneas
worker_connections 10000;

# ✅ CORRETO: Controlar o fluxo
worker_connections 1024;  # Ou até menos (256-1000)
```

**Analogia da Lanchonete:**
- Porta gigante = Caos, requisições perdidas
- Porta controlada = Atendimento ordenado, melhor throughput
- Melhor atender 100 pessoas organizadamente que 1000 desordenadamente

#### Pool de Conexões de Banco
```yaml
# ❌ ERRADO: Muitas conexões
database:
  max_connections: 200

# ✅ CORRETO: Conexões balanceadas
database:
  max_connections: 40-100  # Dependendo dos recursos
```

**Regra:** Cada conexão PostgreSQL consome ~3MB RAM

### **2. Configurações de Docker**

#### Network Mode Host
```yaml
# ❌ ERRADO: Usar bridge (padrão)
services:
  app:
    network_mode: bridge

# ✅ CORRETO: Usar host para melhor performance
services:
  app:
    network_mode: host
  postgres:
    network_mode: host
  nginx:
    network_mode: host
```

**Impact:** Elimina o overhead da ponte de rede virtual

#### Distribuição de Recursos
```yaml
# Exemplo de distribuição otimizada para 1.5 CPU / 3GB RAM:
nginx:
  cpus: 0.15
  memory: 200MB

postgres:
  cpus: 1.0
  memory: 1.2GB

app_instances:
  cpus: 0.175 each  # Para 2 instâncias
  memory: 800MB each
```

### **3. Otimizações de Aplicação**

#### Validações Eficientes
```swift
// ❌ ERRADO: Validação complexa/demorada
func validateDate(_ dateString: String) -> Bool {
    // Usar bibliotecas pesadas como moment.js
    return complexValidation(dateString)
}

// ✅ CORRETO: Validação simples e rápida
func validateDate(_ dateString: String) -> Bool {
    // Verificar formato básico primeiro
    let components = dateString.split(separator: "-")
    guard components.count == 3 else { return false }
    // Validação mínima necessária
    return isValidDateFormat(components)
}
```

#### Respostas HTTP Otimizadas
```swift
// ❌ ERRADO: Retornar mensagens de erro detalhadas
return Response(status: .badRequest, body: "{\\"error\\": \\"Detailed error message\\"}")

// ✅ CORRETO: Apenas status code
return Response(status: .badRequest)
```

#### Logs Desnecessários
```swift
// ❌ ERRADO: Logs excessivos em produção
logger.info("Processing request for user \(id)")
logger.debug("Validating input data: \(data)")

// ✅ CORRETO: Logs mínimos durante stress test
// Desabilitar logs não críticos
```

### **4. Otimizações de Banco de Dados**

#### Pesquisas Otimizadas
```sql
-- ❌ ERRADO: Pesquisa LIKE simples
SELECT * FROM pessoas 
WHERE apelido LIKE '%termo%' 
   OR nome LIKE '%termo%' 
   OR stack LIKE '%termo%';

-- ✅ CORRETO: Usar índices apropriados
-- Criar índices GiST com trigrams para pesquisa fuzzy
CREATE INDEX idx_pessoas_search ON pessoas 
USING gin(to_tsvector('portuguese', apelido || ' ' || nome || ' ' || array_to_string(stack, ' ')));
```

#### Bulk Inserts
```swift
// ❌ ERRADO: Inserção individual
for payment in payments {
    try await repository.insert(payment)
}

// ✅ CORRETO: Inserção em lote
try await repository.bulkInsert(payments)
```

#### Configurações PostgreSQL
```postgresql
# postgresql.conf otimizado para a carga
max_connections = 100          # Não exagerar
shared_buffers = 256MB        # 25% da RAM disponível
effective_cache_size = 1GB    # 75% da RAM total
work_mem = 4MB               # Para operações de ordenação
```

### **5. Evitar Armadilhas Comuns**

#### Cache Desnecessário
```swift
// ❌ ERRADO: Cache quando PostgreSQL já é rápido
let cached = try await redis.get(key)
if cached == nil {
    let result = try await database.find(id)
    try await redis.set(key, result)
    return result
}

// ✅ CORRETO: PostgreSQL direto (quando apropriado)
return try await database.find(id)  // Busca por chave primária é rápida
```

#### Jobs Assíncronos Desnecessários
```swift
// ❌ ERRADO: Complicar sem necessidade
func createPayment() async throws {
    try await queue.dispatch(.insertPayment(data))
    return Response(status: .created)
}

// ✅ CORRETO: Inserção direta quando apropriada
func createPayment() async throws {
    try await repository.insert(payment)
    return Response(status: .created)
}
```

## 📊 Métricas de Sucesso

### Targets de Performance
- **Latência P99**: < 100ms
- **Throughput**: > 200 req/s
- **Failures**: < 1%
- **Inconsistência**: < 40,000 (específico para Rinha)

### Monitoramento
```swift
// Métricas importantes para acompanhar:
- Response time percentiles (P50, P95, P99)
- Request rate (req/s)
- Error rate (%)
- Database connection pool usage
- Memory utilization
- CPU utilization
```

## 🔄 Processo de Otimização

### 1. **Medição Baseline**
```bash
# Estabelecer linha base
./run_stress_test.sh
# Documentar: latência, throughput, recursos
```

### 2. **Identificar Gargalo**
- Use profiling tools
- Monitore métricas de sistema
- Analise logs de performance

### 3. **Aplicar Uma Mudança**
- Faça UMA otimização por vez
- Teste imediatamente
- Compare com baseline

### 4. **Validar Resultado**
- Performance melhorou?
- Funcionalidade mantida?
- Recursos dentro do limite?

## 🎛️ Configurações por Linguagem

### Swift/Vapor (Nossa Implementação)
```swift
// Configurações otimizadas
app.databases.use(.postgres(
    hostname: "localhost",
    port: 5432,
    username: "user",
    password: "pass",
    database: "db"
), as: .psql, maxConnectionsPerEventLoop: 20)

// Event loop otimizado
app.eventLoopGroup.configuration.threadCount = System.coreCount
```

### Configurações Docker Compose
```yaml
version: '3.8'
services:
  nginx:
    cpus: '0.15'
    memory: 200M
    
  db:
    cpus: '1.0' 
    memory: 1.2G
    environment:
      POSTGRES_MAX_CONNECTIONS: 100
      
  api1:
    cpus: '0.175'
    memory: 400M
    network_mode: host
    
  api2:
    cpus: '0.175' 
    memory: 400M
    network_mode: host
```

## ⚡ Quick Wins

### Implementação Rápida (Primeiras 24h)
1. ✅ **Network mode host** - Ganho imediato
2. ✅ **Limitar nginx workers** - Controle de fluxo
3. ✅ **Ajustar pool de conexões** - Balance recursos
4. ✅ **Remover logs excessivos** - Reduz I/O
5. ✅ **Simplificar validações** - Reduz CPU

### Otimizações Avançadas (Próximas fases)
1. 🔄 **Bulk inserts com batching**
2. 🔄 **Índices de pesquisa otimizados**
3. 🔄 **Cache inteligente (apenas onde necessário)**
4. 🔄 **Processamento assíncrono estratégico**
5. 🔄 **Tuning fino de PostgreSQL**

## 🚨 Red Flags - O Que Evitar

- ❌ **Cache premature** sem medir necessidade
- ❌ **Pools de conexão exagerados** 
- ❌ **Workers de nginx descontrolados**
- ❌ **Validações complexas desnecessárias**
- ❌ **Mensagens de erro verbosas em produção**
- ❌ **Jobs assíncronos onde síncrono basta**
- ❌ **Reescrever em linguagem "mais rápida" sem entender o problema**

## 🎯 Conclusão

> "A maioria dos problemas de performance são de I/O Bound, não CPU Bound. Controle o fluxo, não tente acelerar o processamento." - Fábio Akita

**Ordem de prioridade:**
1. 🥇 Controle de fluxo (nginx + pool connections)
2. 🥈 Configuração de recursos (Docker + PostgreSQL)  
3. 🥉 Otimizações de código (validações + responses)
4. 🏅 Otimizações avançadas (bulk inserts + caching inteligente)

---

*Baseado na análise completa de 16 linguagens e 18 repositórios da Rinha de Backend 2023* 