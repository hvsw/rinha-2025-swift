# Scripts de Build e Testes

Scripts para construir, testar e publicar a aplicação Swift/Vapor para a Rinha 2025.

## 🎯 Problema Resolvido
**Erro original**: Imagem `linux/arm64` (Apple Silicon) → **Solução**: `linux/amd64` com `docker buildx --platform`

## 🚀 Script Principal: `build-and-push.sh`

| Comando | Arquitetura | Função | Push Docker Hub |
|---------|-------------|---------|-----------------|
| `./build-and-push.sh` | Nativa (ARM64) | Desenvolvimento rápido | ❌ |
| `./build-and-push.sh --test-amd64` | linux/amd64 | Teste compatibilidade | ❌ |
| `./build-and-push.sh --submission` | linux/amd64 | Submissão oficial | ✅ |

**Tag sempre**: `valcanaia/rinha-backend-2025-swift:latest`

## Scripts de Testes

| Script | Função |
|--------|---------|
| `test.sh` | Testes unitários e integração |
| `test_nginx_performance.sh` | Performance do load balancer |
| `testing/run-clean-official-test.sh` | Teste K6 oficial da Rinha |

## Fluxos de Trabalho

| Cenário | Comandos |
|---------|----------|
| **Desenvolvimento** | `./build-and-push.sh` → `./scripts/testing/run-clean-official-test.sh` |
| **Teste Final** | `./build-and-push.sh --test-amd64` → teste K6 |
| **Submissão** | `./build-and-push.sh --submission` |

## Troubleshooting

| Erro | Causa | Solução |
|------|-------|---------|
| `exec format error` | Imagem ARM64 em host AMD64 | `./build-and-push.sh --submission` |
| Build muito lento | Emulação AMD64 no Mac | Use sem args para desenvolvimento | 