---
milestone: "M05"
name: "Source, Build & Artifacts"
type: "milestone"
status: "pending"
---

# M05 — Source, Build & Artifacts

## Identity

| Campo | Valor |
|---|---|
| **ID** | M05 |
| **Nome** | Source, Build & Artifacts |
| **Objetivo** | Introduzir o **Build Pipeline**: conectar um repositório Git, resolver a branch para um commit imutável, construir com Railpack (default) ou Dockerfile (avançado) sobre BuildKit em builders isolados, e publicar um Artifact OCI identificado por digest. |
| **Resultado observável** | Um `git push` em repositório privado dispara um build assinado e verificado; a UI mostra os logs em tempo real; ao final existe um `Artifact` com `sha256:` reutilizável, e o Service **não** foi alterado. |

## Why

Este é o Milestone que separa **build** de **deploy** (doc 02, decisão central). Sem ele, produção implantaria código-fonte em vez de artefato imutável, e a promoção HML→PROD perderia a garantia de “build once, deploy many”.

É também a maior superfície de risco de segurança do produto: um Dockerfile é código arbitrário, e o builder executa código que a plataforma não controla (Anexo C §10, T03 é `CRITICAL`). Por isso o isolamento do builder e o corpus adversarial **nascem aqui**, não em M13.

Depende de M03 porque credenciais de Registry e tokens de Git vivem no Vault (doc 06 §11.2, §12.2).

## Scope

- `SourceConnection` com GitHub App: instalação, seleção de repositórios, tokens de curta duração.
- Webhook com verificação de assinatura, janela de replay, deduplicação por delivery ID e limite de payload.
- `SourceRevision`: resolução de branch/tag para **commit SHA imutável**.
- `Build` com state machine e logs.
- Builder pool: nodes dedicados, **sem** docker.sock do cluster, sem secrets de runtime, com limites de CPU/memória/disco/tempo e workspace efêmero.
- Railpack como estratégia automática default (detecção → Build Plan → BuildKit).
- Dockerfile como estratégia explícita, também sobre BuildKit/Buildx.
- Build args × build secrets, com secrets entregues como mount temporário.
- `RegistryConnection` provider-agnostic, com credencial do Vault e teste de pull por node.
- `Artifact` identificado por `registryRef` + `digest`.
- Cache por Service/plataforma, com métricas.
- Logs de build streamados, persistidos e **sanitizados**.
- Cancelamento, timeout e limpeza do workspace.
- Corpus de fixtures adversariais para provar o isolamento do builder.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M06 | `Release`, `Deployment`, rollout, rollback, promoção e auto-deploy a partir do webhook. **M05 constrói; não implanta.** |
| M08 | Provisionamento de builder nodes por enrollment. |
| M09 | Métricas de build no backend de observabilidade. |
| M11 | Quotas de concorrência de build por Team. |
| M13 | Escaneamento de vulnerabilidade de imagem e políticas bloqueadoras de supply chain. |
| Backlog | Multi-arch avançado, builders além do Railpack, CI genérico estilo GitHub Actions. |

## Dependencies

- **Hard:** M02, M03.
- **Soft:** M08 (builder node dedicado provisionado por enrollment; em M05 o builder pode ser um node existente rotulado).
- **Externas:** GitHub App registrado; Registry OCI acessível.

## User-visible Outcome

O usuário conecta o GitHub, escolhe um repositório e uma branch, e a plataforma constrói a imagem sem Dockerfile quando o Railpack detecta o stack. Ele acompanha os logs em tempo real, vê o cache funcionando entre builds, e recebe um artefato identificado por digest — que M06 vai implantar.

## Technical Outcome

- Cadeia de proveniência completa: provider → repo → branch → commit SHA → Build → Artifact digest.
- Builder isolado, sem privilégio administrativo do cluster.
- Registry como fronteira entre build e runtime distribuído.
- Build determinístico o suficiente para que o mesmo commit com a mesma configuração não seja reconstruído sem necessidade.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `SourceConnection`, `RepositoryBinding`, `ServiceSource`, `WebhookDelivery`, `SourceRevision`, `Build`, `Artifact`, `RegistryConnection`, `BuildLogRef`. |
| Commands | `ConnectSource`, `BindRepository`, `ResolveSourceRevision`, `CreateBuild`, `CancelBuild`, `ConnectRegistry`. |
| Queries | `BuildsForService`, `BuildLogs`, `ArtifactByDigest`. |
| Events | `build.succeeded.v1`, `build.failed`, `artifact.published`. |
| Jobs | Scheduler de builds; limpeza de workspace; GC de cache. |
| Providers | GitHub App adapter; Registry adapter. |
| Executor | Nenhuma nova operação Docker de runtime; o builder é infraestrutura própria de build. |
| UI | Source, Build config, Build list/detail, Build logs, Registry providers. |

## Security

Este é o Milestone de maior risco. Controles obrigatórios (Anexo C §10):

- **Builder é sandbox temporária**, não extensão confiável do Control Plane.
- **Sem docker.sock do cluster** no builder; **sem** Vault de runtime; **sem** credenciais administrativas.
- Builders **não** rodam nos Manager nodes.
- Egress do builder limitado por policy; ranges internos, link-local e endpoints de metadata bloqueados.
- Limites de CPU, memória, pids, disco e **tempo máximo**; build excedido é morto.
- Workspace destruído após sucesso **e** após falha.
- **Build secret** entregue como mount temporário; nunca vira ENV permanente da imagem, nunca aparece em layer, stdout/stderr ou metadata.
- Credencial de push escopada ao repositório/namespace e de vida curta.
- Token do Git provider de curta duração; nunca em build log, deployment log ou frontend.
- Webhook: assinatura verificada **antes de qualquer ação**, janela de replay, dedup por delivery ID, limite de tamanho.
- Cache namespaced por Service; não compartilhar cache entre tenants não confiáveis.
- Build logs tratados como **não confiáveis**: sanitizados na UI, limitados em tamanho e retenção.
- Ameaças cobertas: **T03 (CRITICAL)**, T07, T08, T13.

## Observability

- Timeline do build: enfileirado, preparando, checkout, construindo, publicando, terminal — com duração por etapa.
- Métricas do Anexo B §7: espera na fila (p95 ≤ 30 s), overhead da plataforma (p95 ≤ 15 s), logs disponíveis em ≤ 2 s, cancelamento propagado em ≤ 10 s.
- Métricas de cache: bytes reutilizados, etapas em cache.
- Duração de build comparada com a baseline histórica **por Service** — não existe SLO único de duração.

## Testing

| Classe | Exigência |
|---|---|
| Unit | State machine de Build; resolução de revisão; classificação de erro; política de cache. |
| Integration | Dedup de webhook; token de curta duração; limpeza de workspace; timeout. |
| Contract | GitHub (validação de webhook, resolução de commit, ciclo de credencial de clone); Registry (push/pull/manifest/digest/auth/not found/rate limit). |
| Build Lab | Corpus de builds: Railpack, Dockerfile, monorepo, build pesado, build que falha, e **fixtures maliciosas**. |
| Security | Repositório malicioso tentando alcançar socket, manager, Vault, metadata e rede interna; assinatura inválida; replay; payload gigante. |
| E2E | Repositório privado → build → artifact por digest visível na UI. |

## Acceptance Criteria

1. Um repositório conectado por GitHub App é clonado com token de **curta duração**, e o token não aparece em log algum.
2. Um webhook com assinatura inválida é **rejeitado antes de qualquer ação**.
3. Replay e delivery duplicado não geram dois builds lógicos.
4. Branch é resolvida para commit SHA e o Build fica permanentemente ligado a ele.
5. Um repositório suportado gera Build Plan Railpack e produz imagem OCI sem Dockerfile.
6. Dockerfile explícito ignora a detecção automática.
7. O Artifact é identificado por `digest`, não apenas por tag.
8. Build falho **não** altera a release atual do Service.
9. Logs são streamados, persistidos e **sanitizados**.
10. Builds **não** executam nos Manager nodes quando há builder dedicado.
11. O builder **não** tem acesso ao docker.sock do cluster, ao Vault de runtime nem a credenciais administrativas — provado por fixture adversarial.
12. Egress do builder é limitado; metadata endpoints e ranges internos são bloqueados — provado por fixture adversarial.
13. Limites de CPU, memória, disco e tempo são aplicados; build excedido é morto.
14. Workspace é destruído após sucesso e após falha.
15. Build secret não persiste na imagem, em layer, em log ou em metadata.
16. Cache é namespaced por Service e produz resultado funcional idêntico.
17. Cancelamento é propagado ao builder e limpa os recursos.
18. Credencial de Registry vem do Vault e é escopada.

## Exit Gate

- [ ] Stories `required` `done`; 18 Acceptance Criteria com evidência.
- [ ] **Corpus adversarial verde**: nenhuma fixture maliciosa alcança socket, manager, Vault, metadata ou rede interna.
- [ ] Contract tests de GitHub e Registry verdes.
- [ ] Teste de webhook (assinatura inválida, replay, duplicado, payload gigante) verde.
- [ ] E2E de repositório privado → artifact por digest verde.
- [ ] Teste de build secret não persistindo na imagem verde.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.

**Gate humano:** revisão de segurança do build plane. T03 é `CRITICAL` no Anexo C §6 e não pode ser aceito só por evidência automatizada.
