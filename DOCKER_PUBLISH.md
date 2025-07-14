# 🐳 Publicação da Imagem Docker - Rinha de Backend 2025

## 📋 **Resumo**

A submissão da Rinha de Backend 2025 requer que **todas as imagens Docker sejam públicas**. Este guia te ajuda a publicar a imagem Swift/Vapor no Docker Hub.

## 🚨 **Configuração de Imagens**

### 📂 **Projeto Local vs Submissão**

**IMPORTANTE:** Existe uma diferença fundamental entre o projeto local e a submissão oficial:

#### 🏠 **Projeto Local** (`rinha-2025-swift/docker-compose.yml`)
```yaml
services:
  api01:
    build: .  # ✅ CORRETO para desenvolvimento local
    environment:
      - ENVIRONMENT=production
```

#### 🚀 **Submissão Oficial** (`participantes/henriquevalcanaia-swift-vapor/docker-compose.yml`)
```yaml
services:
  api01:
    image: valcanaia/rinha-backend-2025-swift:latest  # ✅ OBRIGATÓRIO para submissão
    environment:
      - ENVIRONMENT=production
```

### 📋 **Regras:**

- **Projeto Local**: Pode usar `build: .` para desenvolvimento e testes
- **Submissão**: **DEVE** usar `image: nome-da-imagem:tag` (imagem pública)
- **Motivo**: Os avaliadores precisam baixar imagens prontas do Docker Hub

### ⚠️ **Atenção:**

As instruções da Rinha exigem que **"Todas as imagens declaradas no docker compose deverão estar publicamente disponíveis em registros de imagens"**. Por isso, a submissão não pode usar `build: .`.

## 🛠️ **Passo a Passo**

### 1. **Preparar Ambiente**
```bash
# Navegar para o diretório do projeto
cd rinha-2025-swift

# Verificar se Docker está rodando
docker --version
docker info
```

### 2. **Executar Script de Build e Push**
```bash
# Dar permissão de execução
chmod +x build-and-push.sh

# Executar o script
./build-and-push.sh
```

### 3. **Verificar Publicação**
- Acesse: https://hub.docker.com/r/valcanaia/rinha-backend-2025-swift
- Verifique se a imagem foi publicada corretamente

## 🔧 **Processo Manual (Alternativo)**

Se preferir fazer manualmente:

```bash
# 1. Login no Docker Hub
docker login

# 2. Build da imagem
docker build -t valcanaia/rinha-backend-2025-swift:latest .

# 3. Push para Docker Hub
docker push valcanaia/rinha-backend-2025-swift:latest
```

## ✅ **Verificação Final**

### Testar Imagem Pública
```bash
# Baixar e testar a imagem publicada
docker pull valcanaia/rinha-backend-2025-swift:latest
docker run --rm -p 8080:8080 valcanaia/rinha-backend-2025-swift:latest
```

### Testar Submissão Completa
```bash
# Navegar para a submissão
cd ../rinha-de-backend-2025/participantes/henriquevalcanaia-swift-vapor

# Iniciar Payment Processors
cd ../../../payment-processor
docker-compose -f docker-compose-arm64.yml up -d  # ou docker-compose.yml

# Voltar e testar a submissão
cd ../participantes/henriquevalcanaia-swift-vapor
docker-compose up -d

# Verificar se está funcionando
curl -X POST http://localhost:9999/payments \
     -H 'Content-Type: application/json' \
     -d '{"correlationId":"'$(uuidgen)'","amount":19.90}'
```

## 📊 **Arquivos Atualizados**

### ✅ **Já Corrigidos:**
- `docker-compose.yml` - Usando imagem pública
- `README.md` - Documentação atualizada
- `info.json` - Metadados corretos

### 🔄 **Próximos Passos:**
1. Publicar imagem no Docker Hub
2. Testar submissão completa
3. Verificar conformidade com requisitos

## 🎯 **Checklist de Submissão**

- [ ] ✅ **README.md** com informações da participação
- [ ] ✅ **docker-compose.yml** na raiz do diretório
- [ ] ✅ **info.json** com metadados estruturados
- [ ] ✅ **nginx.conf** com configuração otimizada
- [ ] 🔄 **Imagem Docker** publicada no Docker Hub
- [ ] 🔄 **Teste final** da submissão completa
- [ ] 🔄 **Verificação** de limites de CPU e memória
- [ ] 🔄 **Funcionamento** na porta 9999
- [ ] 🔄 **Compatibilidade** linux/amd64

## 🚀 **Após Publicação**

1. **Testar submissão completa**
2. **Verificar se não há arquivos desnecessários**
3. **Confirmar que todos os serviços sobem corretamente**
4. **Validar que API responde na porta 9999**

## 💡 **Dicas**

- A imagem Swift pode ser grande (~500MB-1GB), isso é normal
- Certifique-se de que a imagem funciona em **linux/amd64**
- Mantenha a imagem atualizada se fizer mudanças no código
- Documente qualquer dependência especial no README

---

**🦄 Única implementação Swift na Rinha de Backend 2025!** 