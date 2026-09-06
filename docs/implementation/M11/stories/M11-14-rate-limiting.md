# M11-14 — Rate limiting on authentication, API, webhooks and expensive endpoints

## Objective
Proteger as superfícies que um atacante ou uma automação mal configurada consegue inundar, aplicando limites proporcionais ao custo de cada operação.

## Outcome
Login, recuperação de conta, webhooks, criação de recursos, streaming de logs e consultas caras têm limites próprios; exceder retorna erro claro com `Retry-After`.

## References
- `docs/annexes/C-threat-model-security-hardening.md` §19 (abuse prevention e quotas), §14 (rate limiting no edge)
- `docs/architecture/04-identity-teams-security.md` §13 (deploy frequency, logs retention)
- `docs/annexes/B-nfr-slos.md` §9 (queue saturation, backpressure)

## Preconditions
M01 e M03 aceitos. Independente das demais Stories de M11.

## Scope
- `RateLimitPolicy` por superfície, com limites distintos: autenticação, recuperação de conta, API por token, webhooks, criação de recursos, deploy, streaming de logs, consultas caras (audit, métricas, logs).
- Dimensões de limite: por IP, por sessão, por token, por Team e global.
- Resposta `RATE_LIMITED` com `Retry-After`.
- Backpressure em vez de perda: filas aplicam contrapressão; operações não são descartadas.
- Isenções controladas para tráfego interno legítimo, explícitas e auditadas.
- Integração com os limites já criados em Stories anteriores (login, webhook, log stream, MCP).

## Out of Scope
- Rate limit no edge por domínio do cliente (`M07-07`) — mecanismo diferente, superfície diferente.
- Proteção volumétrica DDoS — responsabilidade de CDN/LB upstream (doc 08 §19).
- Quotas de recurso (`M11-10`).

## Application Layer
- **Commands:** `UpdateRateLimitPolicy`.
- Middleware aplicando o limite antes de o trabalho caro começar.

## Security Requirements
- **O limite é aplicado antes do trabalho caro**: rejeitar depois de processar não protege nada.
- Autenticação e recuperação de conta têm limites mais estritos: são as superfícies de credential stuffing e de enumeração (Anexo C §4).
- A resposta de rate limit **não** revela informação sobre a existência de contas ou recursos.
- O limite por IP considera os trusted proxies de `M04-12`; sem eles configurados, o limite por IP é enganoso — e a plataforma avisa.
- Isenções são explícitas, auditadas e limitadas; não existe “bypass global”.
- Exceder repetidamente é registrado como sinal de abuso.
- O limite não pode ser desabilitado por configuração de usuário comum.

## Observability Requirements
Requisições limitadas por superfície e por dimensão. Um pico de `RATE_LIMITED` em autenticação é sinal de ataque, e precisa ser distinguível de um pico em API.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Credential stuffing | Limite estrito em autenticação; registrado. |
| Automação mal configurada | Limite por token; `Retry-After` orienta a correção. |
| Webhook em rajada | Limite por conexão; backpressure, sem perder evento legítimo. |
| Consulta cara repetida | Limitada antes de executar. |
| Trusted proxies ausentes | Limite por IP é enganoso; a plataforma avisa. |
| Isenção mal configurada | Auditada e revisável; nunca global. |

## Acceptance Criteria
1. Existem políticas de rate limit distintas por superfície.
2. O limite é aplicado **antes** do trabalho caro, provado por teste.
3. Autenticação e recuperação de conta têm limites mais estritos.
4. A resposta é `RATE_LIMITED` com `Retry-After`.
5. A resposta **não** revela existência de conta ou recurso.
6. Filas aplicam backpressure; nenhuma operação legítima é descartada.
7. O limite por IP considera trusted proxies; sem eles, a plataforma **avisa** que o limite é enganoso.
8. Isenções são explícitas, auditadas e limitadas; **não existe bypass global**.
9. Exceder repetidamente é registrado como sinal de abuso.
10. O limite não é desabilitável por usuário comum.
11. Métricas por superfície e por dimensão estão disponíveis.
12. Alterar política gera AuditLog.

## Required Tests
- **security**: limite em autenticação e recuperação; resposta sem enumeração; ausência de bypass global.
- **integration**: limite aplicado antes do trabalho caro; backpressure; `Retry-After`.
- **unit**: cálculo por dimensão; isenções.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, aplicação antes do trabalho caro provada, ausência de bypass verificada, Critical/High = 0.
