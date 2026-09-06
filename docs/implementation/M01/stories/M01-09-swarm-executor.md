# M01-09 — Privileged Swarm Executor with typed, allowlisted operations

## Objective
Isolar **todo** acesso à Docker Engine API em um único componente privilegiado, restrito aos Manager nodes, sem rota pública e sem nenhuma primitive de execução arbitrária.

## Outcome
Existe um Swarm Executor que expõe operações tipadas e allowlistadas; nenhum outro componente do repositório referencia o Docker socket; AF-02 comprova isso automaticamente.

## References
- `docs/architecture/07-internal-control-plane.md` §2.2 (executor privilegiado), §20 (contratos internos), §21 (segurança interna, proibição de `exec(command)`)
- `docs/annexes/C-threat-model-security-hardening.md` §8 (docker socket, executor e managers), T01
- `docs/AGENT_RULES.md` — “The Docker socket is isolated”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-01, AF-02)

## Preconditions
`M01-08` done.

## Scope
- Módulo `app/executors/` como **único** boundary autorizado a falar com a Docker Engine API.
- Operações tipadas para o que M01 precisa: `InspectService`, `CreateService`, `UpdateServiceSpec`, `RemoveService`, `CreateNetwork`, `InspectNetwork`, `RemoveNetwork`, `ListNodes`, `InspectNode`, `ServiceLogs`, `ListTasks`.
- Contrato `Command` e `ExecutionResult` do doc 07 §20: `outcome ∈ {APPLIED, NOOP, CONFLICT, RETRYABLE, FAILED}`, `observedRuntimeVersion`, `runtimeResourceIds`, `safeMetadata`, `errorCode?`.
- Normalização de erros do Docker para o modelo de erro estável do doc 09 §28.
- **Ausência** de qualquer primitive genérica: sem `exec(command: string)`, sem passagem de argumentos livres para o daemon.
- Validação de que o executor roda em Manager node; recusa fechada em worker.
- Sem rota pública: o executor não é alcançável pela internet nem pela API pública.

## Out of Scope
- Reconcilers (`M01-17`, `M01-18`) — eles **usam** o executor.
- Locks e leases (`M01-15`).
- Terminal/exec de usuário (`M09-14`) — é um caminho separado, permissionado e auditado; **não** é uma operação do executor.
- Operações de node (drain/promote/demote) — `M08`.
- Secrets no Swarm — `M03-07`.

## Application Layer
O executor **não decide autorização de produto** (Anexo I §4.1). Ele recebe comandos já autorizados pela Application Layer e os aplica. Ele também não recebe requisição pública diretamente.

## Async / Control Plane
O executor é o degrau final da cadeia `Command → Operation → Reconciler → Executor → Docker`. Ele é idempotente por construção:
- `Create` procura primeiro recursos já marcados com labels de ownership da plataforma;
- `Update` aplica a revisão desejada, não uma sequência imperativa cega;
- `Delete` de recurso ausente é tratado como convergido quando apropriado;
- toda operação retomada após crash **começa observando** o estado atual.

## Security Requirements
Este é um componente **Tier-0** (Anexo C §8):
- `/var/run/docker.sock` é acessível **somente** aqui. A API pública, workers comuns e builders nunca o recebem.
- **Proibido** criar endpoint interno `exec(command: string)` (doc 07 §21). Operações são tipadas e allowlistadas.
- Imagem mínima, rootfs read-only quando possível, usuário não-root salvo necessidade estrita do grupo do socket.
- Sem porta publicada; comunicação interna autenticada por identidade de serviço.
- Payloads de comando não carregam plaintext de secret — apenas IDs e referências.
- Logs do executor removem tokens, headers sensíveis, credenciais de registry e material criptográfico.
- Toda ação privilegiada carrega `requestId`, `operationId` e `actor` para correlação forense.
- **AF-01 e AF-02** passam a avaliar código real e reprovam qualquer referência a Docker fora deste módulo.

## Observability Requirements
- Cada chamada registra: operação, recurso, `operationId`, duração, `outcome`, e a versão observada do runtime (`Version.Index` do Swarm).
- Erro do Docker é normalizado e classificado (`Validation`, `Conflict`, `Transient`, `Runtime rejection`, `Timeout`, `Unknown outcome`), conforme doc 07 §5.3.
- **Resultado desconhecido nunca é tratado como falha**: é marcado como tal para que o reconciler observe o estado real antes de repetir.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Docker daemon indisponível | `RETRYABLE` com erro classificado; nenhuma configuração é inventada localmente. |
| Resposta do Docker perdida | `outcome` desconhecido; **nunca** repetir cegamente — reconciliar observando o estado atual. |
| Conflito de versão no update do Service | `CONFLICT`; o reconciler reobserva e recalcula o diff. |
| Executor rodando em worker | Recusa fechada com erro explícito. |
| Recurso já existente com labels da plataforma | `NOOP`/adoção idempotente, não erro. |
| Tentativa de operação fora da allowlist | Rejeitada; não existe caminho genérico. |

## Acceptance Criteria
1. Existe um módulo de executor e ele é o **único** lugar do repositório que referencia o Docker socket ou um cliente Docker privilegiado.
2. AF-01 e AF-02 avaliam código real e reprovam, em caso negativo controlado, uma referência a Docker em controller ou worker comum.
3. Nenhuma primitive genérica de execução existe; uma busca por `exec(command`/shell arbitrário no executor retorna vazio, verificado por teste.
4. As operações tipadas de M01 existem e retornam `ExecutionResult` com `outcome`, `observedRuntimeVersion` e `runtimeResourceIds`.
5. Erros do Docker são normalizados para o modelo de erro estável e classificados por tipo.
6. Um resultado desconhecido **não** é tratado como falha nem repetido cegamente; o teste comprova que o caminho leva a reobservação.
7. `Create` de um recurso já existente com labels da plataforma resulta em `NOOP`/adoção idempotente.
8. `Delete` de recurso ausente é tratado como convergido.
9. O executor recusa executar quando não está em um Manager node.
10. O executor não possui rota pública nem porta publicada, verificado por teste de configuração.
11. Nenhum payload de comando contém plaintext de secret.
12. Logs do executor não contêm token, credencial ou material criptográfico, provado com valores plantados.

## Required Tests
- **unit**: normalização de erro; classificação de `outcome`; recusa fora de Manager.
- **contract**: contrato `Command`/`ExecutionResult` estável.
- **Docker/Swarm**: create/inspect/update/remove contra Swarm real; create idempotente; delete de recurso ausente; conflito de versão.
- **security**: AF-01 e AF-02 com casos negativos; ausência de primitive genérica; ausência de rota pública; redaction de log com valores plantados.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-01, AF-02 significativas) + suíte Docker/Swarm. **Story crítica: exige plan mode antes da implementação** (`CLAUDE.md`, “Planning”).

## Definition of Done
Os 12 Acceptance Criteria satisfeitos contra Swarm real, AF-01/AF-02 provadas por caso negativo, ausência de primitive genérica comprovada, Critical/High = 0.
