# M07-04 — Certificate strategy for customer domains

## Objective
Emitir certificados para domínios de cliente com blast radius mínimo, escolhendo entre certificado por hostname e SAN pequeno — e nunca reutilizando o wildcard da plataforma.

## Outcome
Cada domínio de cliente recebe um certificado dedicado; domínios com lifecycle comum podem compartilhar um SAN; pedidos redundantes são deduplicados.

## References
- `docs/architecture/08-networking-domains-edge.md` §15 (wildcard certificates e limites), §13 (Certificate Manager)
- `docs/annexes/C-threat-model-security-hardening.md` T12 (cert private key exfiltrada)
- `docs/annexes/B-nfr-slos.md` §8 (certificado de custom domain p95 ≤ 5 min após DNS válido)

## Preconditions
`M07-02` done. `M04-09` e `M04-10` entregaram emissão e distribuição.

## Scope
- Estratégia de certificado por hostname como **default** para domínio de cliente.
- SAN para um pequeno conjunto de nomes que **compartilham lifecycle e ownership** (doc 08 §15).
- Deduplicação por `domainSetHash`, evitando pedidos redundantes à CA.
- Reuso da emissão DNS-01 de `M04-09` quando há provider, e do HTTP-01 de `M07-08` quando não há.
- Regra explícita: o wildcard da zona da plataforma **nunca** cobre domínio de cliente.

## Out of Scope
- Certificado fornecido pelo cliente (`tlsMode: PROVIDED`) — o campo existe; o fluxo de upload é Story própria se houver requisito.
- Wildcard do cliente (`M07-10`).
- Renovação (`M04-11`, que já cobre todos os certificados).

## Application Layer
- **Commands:** `IssueCertificateForDomain`.
- **Reconciler:** `CertificateReconciler` escolhendo a estratégia.

## Security Requirements
- **Blast radius**: um certificado por hostname significa que comprometer a chave de um domínio não compromete os demais (doc 08 §15).
- O wildcard da plataforma **não** é usado para domínio de cliente — usá-lo colocaria domínios de terceiros sob a mesma chave privada.
- A emissão só acontece **após** a verificação de posse de `M07-06`.
- A chave privada é cifrada pelo envelope, como em `M04-08`.
- Deduplicação evita queimar rate limit da CA, que é um recurso compartilhado e escasso.
- SAN só agrupa nomes com ownership comum — agrupar domínios de Teams diferentes seria um vazamento de blast radius entre tenants.

## Observability Requirements
Estratégia escolhida registrada com o certificado. Métrica de certificados por estratégia e de deduplicações.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Posse não verificada | **Não** emitir. |
| Rate limit da CA | Backoff; a deduplicação reduz a pressão. |
| SAN com nomes de Teams diferentes | Rejeitado. |
| Domínio removido do SAN | Nova versão do certificado sem ele; a anterior permanece até o grace period. |
| Emissão falha | `CERTIFICATE_ERROR` com causa e retry controlado; o domínio fica `PENDING_CERT`. |
| Tentativa de usar o wildcard da plataforma | Bloqueada por regra. |

## Acceptance Criteria
1. O default para domínio de cliente é certificado **por hostname**.
2. SAN agrupa apenas nomes com ownership e lifecycle comuns.
3. SAN com nomes de Teams diferentes é rejeitado, provado por teste.
4. O wildcard da zona da plataforma **nunca** é usado para domínio de cliente, provado por teste.
5. A emissão só ocorre após a verificação de posse.
6. Pedidos redundantes são deduplicados por `domainSetHash`.
7. A chave privada é cifrada pelo envelope.
8. Rate limit da CA leva a backoff sem insistência.
9. Remover um nome do SAN gera nova versão; a anterior permanece até o grace period.
10. Falha de emissão deixa o domínio em `PENDING_CERT` com causa e retry controlado.
11. A estratégia escolhida é registrada com o certificado.

## Required Tests
- **unit**: escolha de estratégia; `domainSetHash`; validação de ownership no SAN.
- **integration**: emissão bloqueada sem posse; deduplicação; remoção de nome do SAN.
- **contract**: emissão via CA de staging.
- **security**: wildcard da plataforma não usado; SAN cross-team rejeitado.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, blast radius mínimo provado, emissão condicionada à posse, Critical/High = 0.
