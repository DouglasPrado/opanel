# M03-11 — Non-sensitive environment variables and the sensitive boundary

## Objective
Oferecer variáveis de configuração comuns para o Service e tornar explícita a fronteira: valor sensível **não** vive aqui, vive no Vault.

## Outcome
O usuário define `NODE_ENV=production` como variável simples; ao marcar um valor como sensível, a UI o direciona para o Vault em vez de aceitá-lo em claro.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §6.1 (EnvironmentVariable, `isSensitive`)
- `docs/architecture/01-foundation.md` §10.1 (não usar Env para segredos por padrão)
- `docs/architecture/10-ui-use-cases.md` §15.3 (Variables & Secrets do Service)

## Preconditions
M02 aceito. Independente do restante de M03, mas a UI conjunta chega em `M03-12`.

## Scope
- `EnvironmentVariable`: serviceId, key, value, scope, revision. Apenas valores **não sensíveis**.
- `key` validada como chave de ambiente e única no escopo efetivo.
- `revision` permitindo compare-and-swap.
- **Fronteira explícita**: um valor marcado como sensível é **rejeitado** nesta tabela e direcionado ao Vault (doc 09 §6.1: “Se true, não usar esta tabela; promover para SecretBinding”).
- Alteração de variável gera Operation e rollout quando afeta o runtime.
- Detecção heurística de valor com aparência de credencial, com aviso — não bloqueio automático, mas registro.

## Out of Scope
- Herança por Team/Project/Environment com resolução no Control Plane (doc 09 §6.1 permite; sem requisito imediato — se vier, é Story própria).
- Secrets (`M03-05`..`M03-09`).
- Build args e build secrets (`M05-10`).

## Domain Impact
**Entidade:** `EnvironmentVariable`.
**Invariante:** esta tabela **nunca** armazena valor sensível. `isSensitive = true` é um caminho de rejeição, não de armazenamento.

## Application Layer
- **Commands:** `UpsertEnvironmentVariable`, `DeleteEnvironmentVariable`.
- **Policies:** `service.update` conforme escopo.

## UI Impact
Tabela unificada do doc 10 §15.3 mostrando origem de cada chave: variável simples ou Vault, com versão quando aplicável. A UI oferece “mover para o Vault” quando o usuário marca como sensível.

## Security Requirements
- Uma variável marcada como sensível é **rejeitada** com orientação para o Vault; não existe caminho que a persista em claro.
- A heurística de detecção (padrões de token, chave privada, URL com credencial embutida) gera **aviso** e é registrada; ela ajuda, mas não substitui a decisão do usuário.
- Variáveis comuns aparecem normalmente na UI e na API — elas não são secretas por definição, e tratá-las como se fossem criaria falsa sensação de segurança.
- Alteração gera AuditLog com chave e revisão; o valor de variável comum pode constar, mas passa pela heurística de redaction de `M03-10` por segurança.

## Observability Requirements
Log com `service_id` e a chave alterada. Aviso de heurística registrado para revisão.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Usuário marca como sensível | Rejeitar e direcionar ao Vault. |
| Valor com aparência de credencial | Aviso explícito e registro; o usuário decide, mas fica rastreável. |
| Chave inválida como variável de ambiente | Rejeitada por validação. |
| Chave duplicada no escopo | Rejeitada. |
| Colisão com `targetName` de um binding do Vault | Rejeitada, com explicação de qual origem já usa a chave. |
| Alteração concorrente | `revision` resolve por compare-and-swap. |

## Acceptance Criteria
1. Variáveis não sensíveis são criadas, editadas e removidas por Service.
2. `key` é validada e única no escopo efetivo.
3. Um valor marcado como sensível é **rejeitado** e direcionado ao Vault; nenhum caminho o persiste em claro.
4. Colisão entre uma variável e o `targetName` de um binding do Vault é rejeitada com explicação.
5. A heurística de detecção emite aviso e registra, sem bloquear automaticamente.
6. Alteração gera Operation e rollout quando afeta o runtime.
7. `revision` permite compare-and-swap; alteração concorrente resulta em conflito, não em lost update.
8. A UI mostra a origem de cada chave: variável simples ou Vault.
9. Alteração gera AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: validação de chave; heurística de detecção; compare-and-swap.
- **integration**: rejeição de valor sensível; colisão com binding do Vault; alteração concorrente.
- **Docker/Swarm**: variável aplicada ao Service e visível para o processo.
- **policy**: negativo cross-team.
- **security**: nenhum caminho persiste valor marcado como sensível.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, rejeição de valor sensível provada, colisão com Vault tratada, Critical/High = 0.
