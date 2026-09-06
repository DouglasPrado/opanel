# M07-02 — DNS verification from multiple vantage points

## Objective
Verificar se o DNS do domínio aponta para o endpoint esperado, com observação de múltiplos pontos e diagnóstico do que foi observado.

## Outcome
O `Domain` sai de `PENDING_DNS` quando a resolução converge para o endpoint da plataforma; quando não converge, a UI mostra o registro esperado e o observado.

## References
- `docs/architecture/08-networking-domains-edge.md` §10 (verificação e convergência), §29.3 (diagnostics)
- `docs/annexes/E-operational-runbooks.md` RB-12 (domínio não resolve ou aponta incorretamente)
- `docs/architecture/10-ui-use-cases.md` UC-024 (DNS mismatch → mostrar esperado/observado)

## Preconditions
`M07-01` done.

## Scope
- Checker de DNS resolvendo o hostname a partir de **múltiplos vantage points**, para não ser enganado por cache local.
- Comparação com o endpoint esperado (`EdgeEndpoint` do cluster).
- Estado derivado: `PENDING_DNS` → `DNS_VERIFIED`.
- Reavaliação periódica com backoff, até convergir ou até a política de desistência.
- Detecção de CAA que impeça a emissão pela CA escolhida.
- Detecção de proxy/CDN externo na frente, que muda o comportamento observado.

## Out of Scope
- Verificação de **posse** (`M07-06`) — resolver para o endpoint certo não prova posse.
- Criação de registro (`M07-03`).
- Emissão de certificado (`M07-04`).

## Application Layer
- **Reconciler:** `DomainReconciler` na parte de verificação de DNS.
- **Queries:** `DomainDnsCheck`.

## Security Requirements
- **Resolver para o endpoint correto não é prova de posse.** Um atacante pode apontar um domínio para o IP da plataforma. Por isso a emissão de certificado depende de `M07-06`, não desta Story.
- A resolução usa resolvers controlados; a resposta é **dado não confiável** e é validada antes de uso.
- O checker não é um mecanismo de requisição arbitrária: ele resolve nomes, não busca URLs fornecidas pelo usuário.
- CAA impeditiva é detectada e reportada **antes** de tentar emitir e queimar rate limit da CA.

## Observability Requirements
Por check: hostname, tipo de registro, valor esperado, valor observado por vantage point, e timestamp. Métrica de domínios por estado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| DNS não aponta para o endpoint | Mostrar esperado × observado por vantage point. |
| Resolução inconsistente entre pontos | Reportar a inconsistência; não declarar verificado. |
| CAA impede a CA | Reportar antes de tentar emitir. |
| Proxy/CDN na frente | Detectado e reportado, porque muda o comportamento e a estratégia de challenge. |
| Provider de DNS lento | Backoff; não declarar falha cedo demais. |
| Domínio nunca converge | Política de desistência com estado `BLOCKED` e causa. |

## Acceptance Criteria
1. A resolução é feita a partir de múltiplos vantage points.
2. O estado sai de `PENDING_DNS` apenas quando a resolução converge para o endpoint esperado.
3. Divergência mostra esperado × observado **por vantage point**.
4. Resolução inconsistente entre pontos **não** declara verificado.
5. CAA impeditiva é detectada e reportada antes de tentar emitir.
6. Proxy/CDN externo na frente é detectado e reportado.
7. A reavaliação usa backoff e não declara falha cedo demais.
8. Domínio que nunca converge chega a `BLOCKED` com causa, pela política de desistência.
9. A resposta do resolver é tratada como dado não confiável e validada.
10. O checker resolve nomes e **não** busca URLs fornecidas pelo usuário.
11. Verificação de DNS **não** é tratada como prova de posse.

## Required Tests
- **unit**: comparação esperado × observado; detecção de inconsistência; política de desistência.
- **integration**: DNS incorreto; CAA impeditiva; proxy detectado; backoff.
- **security**: ausência de busca de URL arbitrária; resposta de resolver validada.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, separação entre verificação de DNS e prova de posse explícita, Critical/High = 0.
