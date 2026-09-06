# M01-05 — AuditLog foundation: append-only, redacted, correlated

## Objective
Criar o registro append-only das ações privilegiadas, com redaction obrigatória e correlação suficiente para reconstruir o que aconteceu sem reproduzir o incidente.

## Outcome
Toda ação privilegiada grava um AuditLog com actor, recurso, ação, resultado, `requestId` e `operationId`; nenhum valor sensível chega ao registro; o log não é editável pela aplicação.

## References
- `docs/architecture/04-identity-teams-security.md` §10 (Audit Log e eventos obrigatórios), §10.2 (estrutura)
- `docs/architecture/09-data-model-apis-contracts.md` §15.1 (AuditLog), §18 (índices)
- `docs/annexes/C-threat-model-security-hardening.md` §17 (logs e AuditLog), §17.1 (redaction)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §19.2 (observabilidade mínima)

## Preconditions
`M01-04` done.

## Scope
- `AuditLog`: id, teamId (nullable **apenas** para eventos de instância), actorType (`USER`, `API_TOKEN`, `SYSTEM`, `RECOVERY`), actorId, action, resourceType, resourceId, environmentId?, requestId, correlationId, operationId?, ip?, userAgent?, before/after sanitizados, result (`SUCCESS`, `DENIED`, `FAILED`), createdAt.
- Nomes de ação **estáveis e versionáveis**: `team.created`, `installation.bootstrapped`, `session.revoked`, `authorization.denied`, etc.
- Append-only: sem `UPDATE` nem `DELETE` pela aplicação; a garantia é de permissão de banco + ausência de código, verificada por teste.
- **Redaction obrigatória** antes de persistir: `before`/`after` passam por sanitizador com allowlist de campos, não blocklist.
- Índices do doc 09 §18: `(teamId, createdAt DESC)` e `(resourceType, resourceId, createdAt DESC)`.
- Helper de instrumentação que Commands usam, para que auditar não dependa de lembrar.

## Out of Scope
- UI de consulta e filtros (`M11-11`).
- Retenção e GC de audit (M13/M14; o default de 365 dias do Anexo B §12 é registrado como configuração, não implementado como job aqui).
- Audit específico de MCP (`M12-14`).
- Detecção de anomalia (fora do core, doc 10 §21.1).

## Domain Impact
**Entidade:** `AuditLog`, imutável após inserção.
**Regra de tenancy:** `teamId` nulo é permitido **somente** para eventos de instalação; um teste garante que nenhum evento tenant-scoped grava `teamId` nulo.

## Application Layer
- **Commands:** todos passam a emitir AuditLog no mesmo boundary transacional da mutação, quando a ação for auditável.
- **Queries:** `AuditTrailForResource` (usada pela UI em `M11-11`).

## Security Requirements
- **Nunca** registrar secret plaintext, token, senha, chave privada ou Recovery Key (doc 04 §10.2, Anexo C §17).
- Sanitização por **allowlist**: um campo novo não auditado por engano é omitido, não vazado.
- `before`/`after` de campo sensível registram apenas que houve mudança e a referência de versão — nunca o valor.
- AuditLog não é editável nem apagável pela aplicação.
- Negações de autorização (`result: DENIED`) são auditadas — é o sinal detectivo do controle preventivo de `M01-04`.
- AF-06 passa a avaliar payloads de audit.

## Observability Requirements
- `requestId` e `correlationId` sempre presentes; `operationId` presente sempre que a ação originar uma Operation.
- A partir de um `requestId` é possível reconstruir a cadeia: request → AuditLog → Operation → tentativas.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Falha ao gravar AuditLog em ação crítica | A mutação **não** é considerada bem-sucedida; audit e mutação compartilham a transação. |
| Campo sensível em `before`/`after` | Allowlist omite; teste com valor plantado comprova. |
| Tentativa de `UPDATE`/`DELETE` no audit | Rejeitada; teste comprova. |
| Evento de instância com `teamId` | Aceito apenas quando o evento é realmente de instância; teste guarda a regra inversa. |

## Acceptance Criteria
1. `AuditLog` existe com todos os campos do doc 04 §10.2 e é append-only.
2. Nenhum código da aplicação faz `UPDATE` ou `DELETE` em AuditLog, comprovado por teste.
3. Ações de identidade de M01 (bootstrap, criação de Team, login, revogação de sessão) geram AuditLog.
4. Negação de autorização gera AuditLog com `result: DENIED`.
5. A sanitização é por allowlist; um campo sensível plantado em `before`/`after` **não** é persistido, provado por teste.
6. Nenhum AuditLog contém secret, token, senha ou chave, provado por teste com valores plantados.
7. `requestId` e `correlationId` estão sempre presentes; `operationId` está presente quando há Operation.
8. A partir de um `requestId` é possível recuperar a cadeia completa da ação.
9. Os índices `(teamId, createdAt DESC)` e `(resourceType, resourceId, createdAt DESC)` existem e são usados pela query de trilha.
10. `teamId` nulo só ocorre em eventos de instância, garantido por teste.
11. Falha ao auditar uma ação crítica impede que a mutação seja considerada bem-sucedida.

## Required Tests
- **unit**: sanitizador por allowlist; nomes de ação estáveis.
- **integration**: append-only; audit no mesmo boundary transacional; índices exercitados pela query.
- **security**: valores sensíveis plantados não aparecem; AF-06 sobre payloads de audit.
- **policy**: negação gerando `DENIED`.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-06 e AF-08 avaliando código real).

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, redaction provada com valores plantados, append-only garantido, Critical/High = 0.
