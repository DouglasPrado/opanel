# M10-18 — Environment migration between Clusters

## Objective
Permitir que um Environment mude de Cluster (UC-011) reconvergindo o Desired State no destino, sem que o usuário recrie Services, Secrets, domínios ou rotas à mão.

## Outcome
Um OWNER/ADMIN com permissão de instância move um Environment de um Cluster para outro. Ao final, os Services estão healthy no Cluster destino, os domínios respondem, os Secrets decifram, e o Cluster de origem não guarda recurso órfão.

## References
- `docs/architecture/10-ui-use-cases.md` — UC-011
- `docs/architecture/07-internal-control-plane.md` — Operations, locks e supersessão
- `docs/architecture/01-foundation.md` — Cluster e placement
- `docs/annexes/C-threat-model-security-hardening.md` §12 — redistribuição de SecretVersion
- `docs/implementation/M10/stories/M10-11-restore-engine.md`

## Preconditions
- Pelo menos dois Clusters registrados e operáveis (`M01-08`).
- Environment com placement explícito (`M01-11`), overlay network reconciliada (`M01-17`), Services convergindo (`M01-18`), Secrets distribuídos (`M03-07`) e ingress reconciliado (`M04-05`).
- Restore Engine (`M10-11`) disponível: a migração reutiliza o mesmo motor de plano/validação/execução/verificação, em vez de criar um segundo.

## Scope
- Operation `ENVIRONMENT_MIGRATE` com plano explícito, revisado antes da execução: o que será recriado no destino, o que será removido na origem, e o que **não** pode ser movido.
- **Preflight**: capacidade do Cluster destino, versões de Docker compatíveis, papéis de node necessários (ingress, builder), providers de DNS e Registry alcançáveis a partir do destino.
- Reuso do Desired State existente: a migração **não** reescreve a intenção do usuário; ela muda o `clusterId` do Environment e deixa os reconcilers convergirem no destino.
- Ordem de execução: criar overlay network no destino → materializar SecretVersions no destino → criar Services → aguardar health → mover rotas de ingress → drenar e remover recursos da origem.
- **Corte de tráfego explícito**: as rotas só apontam para o destino depois que os Services do destino estão healthy; a origem só é removida depois do corte confirmado.
- Modo `dry-run`: gera o plano e as verificações sem alterar estado.
- Abort seguro em qualquer etapa antes do corte de tráfego: a origem continua servindo e o destino é limpo.
- Não migráveis declarados explicitamente: volumes locais de node, dados de aplicação fora do modelo de Desired State e recursos não rotulados como da plataforma.
- Registro de audit da operação completa, com origem, destino, ator e resultado.

## Out of Scope
- Migração de dados de aplicação (volumes, bancos do cliente) — a plataforma declara o que não move; a movimentação de dados é responsabilidade do dono da aplicação, apoiada por `M10-09`/`M10-12`.
- Migração com zero downtime garantida para Services `1/1` — a janela é declarada, não prometida.
- Balanceamento automático entre Clusters.
- **Federação multi-cluster e multi-region ativo-ativo** — backlog pós-core (Anexo A §12). Esta Story move um Environment de um Cluster para outro, um de cada vez, com janela declarada; ela não faz Clusters operarem como um só.

## Domain Impact
**Entidades:** `Environment` (`clusterId` passa a ser alterável somente por esta Operation), `Operation` (`ENVIRONMENT_MIGRATE`), `MigrationPlan` como payload versionado da Operation.

Restrição: enquanto uma migração está ativa, o Environment é bloqueado para outras mutações estruturais (lock por recurso, `M01-15`).

## Application Layer
- `MigrateEnvironmentCommand` — valida permissão, gera o plano, cria Desired State + Operation + OutboxEvent em uma transação.
- `EnvironmentMigrationPlanQuery` — plano e preflight para o modo `dry-run` e para a tela de confirmação.
- Política: OWNER/ADMIN do Team **e** permissão de instância para o Cluster destino.

## Async / Control Plane
- Executada por etapas idempotentes; cada etapa reexecutável após falha sem duplicar efeito.
- Após qualquer resultado desconhecido, **observar o Actual State antes de repetir**.
- Supersessão: uma migração mais nova cancela uma enfileirada; migrações concorrentes no mesmo Environment são serializadas.

## API Impact
- `POST /environments/:id/migrations` com `Idempotency-Key`; `GET` do plano e do progresso.

## UI Impact
- Fluxo de confirmação que mostra o plano, o que não será movido e a janela estimada; progresso por etapa; botão de abort disponível até o corte de tráfego.
- Reutilizar os componentes de Operation/timeline (`M02-10`) — não criar uma tela de progresso paralela.

## Security Requirements
- SecretVersions são **redistribuídas**, nunca reveladas: o plano carrega IDs, jamais plaintext.
- O destino só recebe os Secrets que o Environment já tinha direito de usar; a migração não amplia escopo.
- Permissão de instância é obrigatória: um ADMIN de Team não move workload para um Cluster que não lhe pertence.
- Recursos da origem só são removidos se estiverem rotulados como da plataforma (`M01-16`).

## Observability Requirements
- Cada etapa emite evento com `operation_id`, `environment_id`, `cluster_id` de origem e destino.
- Métrica de duração por etapa e da janela de corte de tráfego.
- Audit da operação completa, incluindo abort.

## Failure Scenarios
| Cenário | Comportamento esperado |
|---|---|
| Capacidade insuficiente no destino | Preflight falha; nada é alterado. |
| Service não fica healthy no destino | Abort; tráfego permanece na origem; destino é limpo. |
| Falha após o corte de tráfego | Não faz rollback automático de tráfego; sinaliza `DEGRADED` e exige decisão explícita. |
| Secret não decifra no destino | Abort antes do corte; finding de segurança se ocorrer depois. |
| Recurso órfão na origem | Sweep detecta e reporta; remoção só de recurso rotulado como da plataforma. |
| Migração concorrente | Serializada por lock; a mais nova supersede a enfileirada. |

## Acceptance Criteria
1. UC-011 é executável pela UI e pela API, com plano revisável antes da execução.
2. O modo `dry-run` gera plano e preflight sem alterar estado.
3. O preflight bloqueia a migração quando o destino não comporta o Environment.
4. O Desired State do usuário não é reescrito; apenas o placement muda.
5. Overlay network, Secrets, Services e rotas são recriados no destino na ordem declarada.
6. O corte de tráfego só ocorre depois que os Services do destino estão healthy.
7. Abort antes do corte mantém a origem servindo e limpa o destino.
8. Recursos da origem são removidos apenas se rotulados como da plataforma.
9. SecretVersions são redistribuídas sem plaintext em plano, payload, log ou audit.
10. A permissão de instância sobre o Cluster destino é exigida; teste negativo cross-team incluído.
11. O que não é migrável está declarado na UI e na documentação.
12. Etapas são idempotentes e reexecutáveis; migrações concorrentes são serializadas.

## Required Tests
- **unit**: geração de plano, preflight, ordenação de etapas, decisão de abort.
- **integration**: Operation + lock + supersessão com PostgreSQL real; idempotência por etapa.
- **swarm**: migração real entre dois Clusters de laboratório, incluindo corte de tráfego e limpeza da origem.
- **security**: negativo de permissão de instância; ausência de plaintext em plano, payload, log e audit.
- **e2e**: jornada completa com `dry-run`, execução e verificação.

## Quality Gates
Local Quality Gate; AF-03 (reconciler não reescreve intenção do usuário); AF-06; AF-08.

## Definition of Done
- [ ] 12 Acceptance Criteria com evidência.
- [ ] Migração demonstrada entre dois Clusters, com abort testado.
- [ ] Self-review; `tasks.json` atualizado com commit.
