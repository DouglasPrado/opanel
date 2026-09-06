# M11-10 — Quota enforcement across the platform

## Objective
Aplicar os limites onde as operações acontecem, com o comportamento correto por nível — e sem permitir que requisições concorrentes ultrapassem o teto.

## Outcome
Criar um recurso além do limite é bloqueado com `QUOTA_EXCEEDED`; um `soft limit` exige confirmação ou privilégio maior; um `warning` apenas informa.

## References
- `docs/architecture/04-identity-teams-security.md` §13.1 (hard limit × warning)
- `docs/architecture/09-data-model-apis-contracts.md` §27 (validações), §28 (`QUOTA_EXCEEDED`)
- `docs/annexes/C-threat-model-security-hardening.md` §19 (abuse prevention)

## Preconditions
`M11-09` done.

## Scope
- Enforcement nos pontos de criação e de escala: Project, Environment, Service, réplicas, recursos, builds concorrentes, frequência de deploy, secrets, streams de log.
- Comportamento por nível: `warning` informa; `soft limit` exige confirmação ou papel maior; `hard limit` bloqueia; `safety limit` bloqueia sem exceção.
- **Verificação atômica**: a checagem e o consumo acontecem de forma que requisições concorrentes não ultrapassem o teto.
- Erro `QUOTA_EXCEEDED` com a dimensão, o limite e o uso atual.
- Interação com o autoscaler: a quota prevalece sobre a decisão automática (`M09-12`).

## Out of Scope
- Modelo de quotas (`M11-09`).
- Rate limit de API (`M11-14`) — mecanismo diferente, para abuso de requisição.
- Cobrança por excedente.

## Application Layer
- **Commands:** todos os Commands de criação e escala consultam a quota antes de mutar.
- **Queries:** `QuotaCheck`.

## Security Requirements
- **Verificação atômica** é essencial: uma checagem seguida de consumo em transações separadas permite ultrapassar o limite com requisições concorrentes — exatamente o cenário de abuso que a quota deveria impedir.
- `safety limit` bloqueia sem exceção, inclusive para OWNER e para o autoscaler.
- A quota prevalece sobre decisões automáticas.
- O erro informa o suficiente para o usuário agir, sem revelar dados de outros Teams.
- Ultrapassagens tentadas são registradas — um padrão é sinal de abuso ou de erro de automação.

## Observability Requirements
Tentativas bloqueadas por dimensão; proximidade do limite. `quota.exceeded` como evento.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Requisições concorrentes no limite | O teto **não** é ultrapassado, provado por teste com barreira. |
| Autoscaler tentando exceder | Bloqueado; a decisão é registrada como suprimida por quota. |
| `soft limit` atingido | Exige confirmação ou papel maior. |
| `hard limit` atingido | `QUOTA_EXCEEDED` com dimensão, limite e uso. |
| `safety limit` | Bloqueado sem exceção. |
| Uso acima do limite após redução | Nada é destruído; novas criações são bloqueadas. |

## Acceptance Criteria
1. O enforcement acontece nos pontos de criação e de escala listados no escopo.
2. `warning`, `soft`, `hard` e `safety` têm comportamentos distintos e corretos.
3. **Requisições concorrentes não ultrapassam o teto**, provado por teste com barreira.
4. `safety limit` bloqueia sem exceção, inclusive para OWNER e para o autoscaler.
5. A quota prevalece sobre a decisão do autoscaler, que registra a supressão.
6. `QUOTA_EXCEEDED` informa dimensão, limite e uso atual, sem revelar dados de outros Teams.
7. `soft limit` exige confirmação ou papel maior.
8. Uso acima do limite após redução **não** destrói nada; apenas bloqueia novas criações.
9. Tentativas bloqueadas são registradas.
10. O evento `quota.exceeded` é emitido.
11. Negativos cross-team passam.

## Required Tests
- **integration (concorrente, com barreira)**: requisições simultâneas no limite.
- **unit**: comportamento por nível.
- **integration**: autoscaler bloqueado por quota; redução de limite abaixo do uso.
- **contract**: envelope de `QUOTA_EXCEEDED`.
- **security**: `safety limit` inviolável; erro sem vazamento.

## Quality Gates
Local Quality Gate + suíte de concorrência + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, atomicidade sob concorrência provada, Critical/High = 0.
