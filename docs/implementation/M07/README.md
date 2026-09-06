---
milestone: "M07"
name: "Custom Domains & DNS Providers"
type: "milestone"
status: "pending"
---

# M07 — Custom Domains & DNS Providers

## Identity

| Campo | Valor |
|---|---|
| **ID** | M07 |
| **Nome** | Custom Domains & DNS Providers |
| **Objetivo** | Permitir que o cliente publique seus Services em **domínios próprios**, com verificação de posse, certificado dedicado, políticas de borda por domínio e diagnóstico de ponta a ponta. |
| **Resultado observável** | O usuário adiciona `api.cliente.com`, recebe a instrução exata de DNS (ou deixa a plataforma criar o registro), acompanha `PENDING_DNS → PENDING_CERT → ACTIVE`, e o domínio passa a servir com TLS válido. |

## Why

M04 entregou o Edge com domínio da plataforma. M07 é o que torna o produto utilizável por um cliente real: ninguém coloca a aplicação de produção em um subdomínio genérico do fornecedor.

Ele também introduz um risco que o domínio default não tinha: **domínios são disputáveis**. Dois Teams podem tentar reivindicar o mesmo hostname, e um deles pode não ser o dono. Por isso a verificação de posse nasce aqui, junto da capacidade.

## Scope

- Onboarding de domínio customizado com instrução explícita do registro esperado.
- Verificação de DNS a partir de múltiplos pontos de observação, com estados derivados.
- Verificação de **posse** do domínio antes de ativar rota e emitir certificado.
- Criação automática de registros quando há DNS provider conectado à zona do cliente.
- Estratégia de certificado: por hostname (blast radius menor) ou SAN para um pequeno conjunto com lifecycle comum.
- Salvaguardas na remoção: impacto em certificado, SAN e DNS gerenciado.
- Políticas de borda **por domínio**: rate limit, IP allowlist, headers, body size, basic auth.
- HTTP-01 como fallback quando não há automação de DNS.
- IPv4/IPv6 como capability detectada, com a regra de nunca anunciar AAAA sem caminho funcional.
- Wildcard do cliente quando ele delega a zona.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M08 | Múltiplos ingress reais, LB provider e o endpoint público em HA. |
| M09 | Métricas de edge no backend histórico e alertas formais. |
| M13 | Teste de carga do data plane e chaos de edge. |
| Backlog | WAF próprio, CDN própria, exposição TCP/UDP arbitrária, path routing avançado. |

## Dependencies

- **Hard:** M04.
- **Soft:** M06 — um domínio customizado apontando para uma release estável é o cenário demonstrável.
- **Externas:** o cliente precisa controlar o DNS do domínio, ou delegar a zona.

## User-visible Outcome

O usuário adiciona seu domínio, vê exatamente qual registro criar, acompanha a verificação, e recebe HTTPS funcionando. Quando algo não converge, a tela de diagnóstico diz se o problema é DNS, posse, certificado, rota ou backend — com o valor observado e o esperado.

## Technical Outcome

- `Domain` com verificação de posse e estado derivado de checks reais.
- Certificados por hostname com deduplicação por conjunto de nomes.
- Políticas de borda versionadas por domínio.
- Fallback HTTP-01 para quem não delega DNS.
- Capability de IPv6 detectada por cluster/provider.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `Domain` (verificação de posse), `EdgePolicyBinding`, `DnsRecordBinding`, `DomainVerificationChallenge`. |
| Commands | `AddCustomDomain`, `VerifyDomainOwnership`, `EnsureDnsRecord`, `ApplyEdgePolicy`, `RemoveDomain`. |
| Queries | `DomainDiagnostics` estendida, `EdgePolicyForDomain`. |
| Reconcilers | `DnsReconciler`, `DomainReconciler`, `CertificateReconciler` (estratégia por hostname). |
| Providers | `DnsProvider` para zonas do cliente. |
| UI | Add Domain, Domain detail, Diagnostics, Edge policies. |

## Security

- **Verificação de posse antes de ativar**: sem ela, um Team poderia apontar o DNS de um domínio alheio e obter certificado válido para ele.
- Unicidade global de hostname (herdada de `M04-04`) impede apropriação entre Teams.
- Credencial do DNS provider do cliente no Vault, com escopo mínimo por zona (Anexo C §14.1).
- Toda chamada a provider passa pela política de SSRF de `M04-07`.
- **Blast radius**: certificado por hostname para domínios de cliente; o wildcard da plataforma **nunca** é usado para domínio de terceiro (doc 08 §15).
- Rate limit e IP allowlist por domínio como controle de abuso no edge (doc 08 §19).
- `X-Forwarded-*` continua confiável apenas a partir de trusted proxies.
- Remoção de domínio avalia impacto em SAN e em DNS gerenciado antes de executar.
- Ameaças cobertas: T11 (DNS token comprometido), T12 (cert private key).

## Observability

- Estados de Domain derivados de checks: DNS, posse, certificado, rota, backend.
- Diagnóstico por camada estendido para domínio customizado, com valor observado × esperado.
- Métricas do doc 08 §23 por domínio.
- Alerta antecipado de falha de emissão/renovação.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Normalização de hostname; estratégia de certificado; avaliação de posse; capability IPv6. |
| Integration | Estados `PENDING_DNS → PENDING_CERT → ACTIVE`; remoção com impacto em SAN. |
| Contract | `DnsProvider` para zona do cliente; ACME com HTTP-01. |
| Docker/Swarm | Request real no domínio customizado; políticas de borda aplicadas. |
| E2E | Adicionar domínio → verificar → certificado → ACTIVE → responder. |
| Security | Apropriação entre Teams; posse não verificada; SSRF; rate limit; allowlist. |

## Acceptance Criteria

1. Um domínio customizado é adicionado com a instrução exata do registro esperado.
2. A verificação de DNS usa múltiplos pontos de observação e mostra observado × esperado.
3. A **posse** do domínio é verificada antes de ativar a rota e emitir certificado.
4. Um Team não consegue reivindicar um hostname de outro Team.
5. Com DNS provider conectado, os registros são criados automaticamente.
6. Sem provider, a plataforma mostra as instruções e verifica periodicamente até convergir.
7. O certificado de domínio customizado é dedicado (por hostname ou SAN pequeno); o wildcard da plataforma **não** é usado.
8. HTTP-01 funciona como fallback quando não há automação de DNS.
9. A remoção avalia impacto em certificado, SAN e DNS gerenciado antes de executar.
10. Políticas por domínio (rate limit, IP allowlist, headers, body size) são aplicadas e versionadas.
11. AAAA só é anunciado quando o caminho IPv6 está funcional de ponta a ponta.
12. O diagnóstico identifica a camada quebrada com valor observado × esperado.
13. Toda chamada a provider passa pela política de SSRF.

## Exit Gate

- [ ] Stories `required` `done`; 13 Acceptance Criteria com evidência.
- [ ] E2E de domínio customizado até `ACTIVE` verde.
- [ ] Teste de apropriação entre Teams verde (negativo).
- [ ] Teste de posse não verificada bloqueando emissão verde.
- [ ] Teste de rate limit e IP allowlist por domínio verde.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.
