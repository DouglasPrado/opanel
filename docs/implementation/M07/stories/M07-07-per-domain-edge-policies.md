# M07-07 — Per-domain edge policies

## Objective
Permitir políticas de borda específicas por domínio — rate limit, IP allowlist, headers e limite de corpo — como configuração versionada e auditada, não como deploy de aplicação.

## Outcome
Um domínio recebe rate limit e allowlist próprios; a alteração é uma operação de ingress, aplicada sem redeploy da aplicação.

## References
- `docs/architecture/08-networking-domains-edge.md` §19 (rate limiting e proteção de edge), §16 (políticas edge), §26 (`EdgePolicy`, `EdgePolicyBinding`)
- `docs/annexes/C-threat-model-security-hardening.md` §14 (rate limiting), §19 (abuse prevention)

## Preconditions
M04 aceito (`M04-12` entregou as políticas globais).

## Scope
- `EdgePolicy` versionada e `EdgePolicyBinding` ligando política a `DomainBinding` ou Service.
- Políticas suportadas: rate limit, IP allowlist, headers adicionais, limite de corpo, basic auth.
- Presets seguros em vez de expor a sintaxe crua do Traefik.
- Aplicação como middleware referenciado pelos routers, reconciliada.
- **Regra explícita**: alterar rate limit é operação de **ingress**, não deployment de aplicação (doc 08 §19).

## Out of Scope
- WAF e proteção volumétrica — pertencem a CDN/LB upstream (doc 08 §19).
- Rate limit da API do Control Plane (`M11-14`).
- Políticas por rota/path.

## Application Layer
- **Commands:** `ApplyEdgePolicy`, `UnbindEdgePolicy`.
- **Reconciler:** `IngressReconciler` aplicando middlewares.

## Security Requirements
- **Rate limit no edge depende de IP confiável**: ele só funciona corretamente com os trusted proxies de `M04-12` configurados. A Story valida essa dependência e avisa quando a configuração não permite identificar o cliente real.
- IP allowlist é um controle de acesso: falha fechada — allowlist configurada e vazia bloqueia, não libera.
- Basic auth no edge **não** substitui a autenticação da aplicação; a UI diz isso.
- Ataques volumétricos são responsabilidade de CDN/LB upstream; a plataforma aplica backpressure e limites, e a UI não promete proteção que não entrega (doc 08 §19).
- Alteração de política gera AuditLog e é versionada.

## Observability Requirements
Métrica por domínio: requisições limitadas, bloqueadas por allowlist, rejeitadas por tamanho. Uma taxa alta de bloqueio é sinal operacional relevante.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Trusted proxies mal configurados | Rate limit e allowlist podem ver o IP errado; a plataforma **avisa** e não finge que o controle está ativo. |
| Allowlist vazia configurada | Bloqueia tudo — falha fechada, com aviso claro antes de aplicar. |
| Rate limit muito baixo | Aviso do impacto estimado antes de aplicar. |
| Política inválida | Rejeitada; a anterior permanece. |
| Ataque volumétrico | Backpressure local; a UI indica que a mitigação principal é upstream. |
| Política removida | Rota volta ao default global de `M04-12`. |

## Acceptance Criteria
1. `EdgePolicy` é versionada e vinculada por `EdgePolicyBinding` a domínio ou Service.
2. Rate limit, IP allowlist, headers, limite de corpo e basic auth são configuráveis por domínio.
3. A alteração é aplicada como operação de ingress, **sem** redeploy da aplicação, provado por teste.
4. Allowlist configurada e vazia **bloqueia** (falha fechada), com aviso antes de aplicar.
5. Rate limit e allowlist avisam quando os trusted proxies não permitem identificar o cliente real.
6. Rate limit muito baixo gera aviso de impacto estimado.
7. Política inválida é rejeitada e a anterior permanece.
8. Remover a política devolve a rota ao default global.
9. A UI declara que basic auth no edge não substitui a autenticação da aplicação.
10. A UI declara que mitigação volumétrica é responsabilidade upstream.
11. Métricas de requisições limitadas/bloqueadas por domínio estão disponíveis.
12. Alteração gera AuditLog; negativo cross-team passa.

## Required Tests
- **Docker/Swarm/E2E**: rate limit efetivo; allowlist bloqueando e permitindo; limite de corpo; basic auth.
- **integration**: alteração sem redeploy; política inválida; remoção voltando ao default.
- **security**: allowlist vazia falhando fechada; aviso com trusted proxies incorretos.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, falha fechada da allowlist provada, alteração sem redeploy verificada, Critical/High = 0.
