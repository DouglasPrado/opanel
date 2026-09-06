# M04-09 — Centralized Certificate Manager with ACME DNS-01

## Objective
Centralizar emissão de certificados no Control Plane, usando ACME com desafio DNS-01, para que nenhuma réplica de Traefik precise competir por estado ACME.

## Outcome
A plataforma cria a conta ACME, executa a ordem DNS-01 via `DnsProvider`, e persiste uma `CertificateVersion` — incluindo o wildcard da zona controlada.

## References
- `docs/architecture/08-networking-domains-edge.md` §13 (Certificate Manager centralizado), §13.1 (por que DNS-01), §15 (wildcard e limites)
- `docs/architecture/01-foundation.md` §8 (Certificate Manager), §8.1 (preferência por DNS-01)
- `docs/annexes/D-test-strategy.md` §6.3 (contract ACME)

## Preconditions
`M04-07` e `M04-08` done. Conta ACME acessível; ambiente de staging da CA disponível para teste.

## Scope
- Conta ACME gerenciada pela plataforma, com a chave da conta protegida pelo envelope.
- Ordem DNS-01: criar TXT `_acme-challenge` via `DnsProvider`, aguardar propagação, finalizar a ordem, **remover o TXT**.
- Emissão do wildcard da zona controlada e de certificados por conjunto de nomes.
- Deduplicação de pedidos simultâneos para a mesma cobertura (doc 08 §15).
- Respeito a rate limits da CA, com backoff e registro.
- Uso do ambiente de staging da CA nos testes automatizados.

## Out of Scope
- Distribuição e ativação (`M04-10`).
- Renovação agendada (`M04-11`).
- HTTP-01 como fallback (`M07-08`).
- Certificados de domínio de cliente (`M07-04`).

## Application Layer
- **Commands:** `IssueCertificate`.
- **Providers:** cliente ACME isolado, com erros normalizados.
- **Operations:** emissão é Operation durável, com retry por classe de erro.

## Async / Control Plane
A emissão é assíncrona e pode levar minutos por causa da propagação de DNS. Nenhuma requisição HTTP fica aberta; o estado é observável pelo Domain e pelo Certificate.

## Security Requirements
- A chave da conta ACME é protegida pelo envelope, como qualquer material criptográfico.
- O TXT de challenge é **removido** após a ordem, com sucesso ou falha — deixar registros órfãos é exposição desnecessária.
- **DNS-01 é preferido** exatamente porque não depende de qual ingress recebeu a requisição e permite wildcard (doc 08 §13.1).
- A credencial do DNS provider tem escopo mínimo; a política de SSRF de `M04-07` se aplica a todas as chamadas.
- Nenhum log registra a chave da conta, a chave privada emitida ou o token de challenge.
- Emissões simultâneas para a mesma cobertura são deduplicadas, para não estourar rate limit da CA.

## Observability Requirements
- Timeline da emissão: ordem criada, challenge publicado, propagação confirmada, ordem finalizada, versão persistida, TXT removido.
- Métrica: emissões por resultado, tempo até emissão, rate limit atingido.
- Meta do Anexo B §8: certificado p95 ≤ 5 min depois que o DNS está corretamente configurado, excluída a propagação externa.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| DNS provider indisponível | Ordem em retry com backoff; domínios já ativos continuam. |
| Propagação demorada | `waitPropagation` com timeout; não bloquear indefinidamente nem falhar cedo demais. |
| Rate limit da CA | Backoff e registro; **não** insistir agressivamente. |
| Ordem falha | `CERTIFICATE_ERROR` com causa e retry controlado; o TXT é removido mesmo assim. |
| Duas emissões para a mesma cobertura | Deduplicadas. |
| Relógio fora de sincronia | Falha explícita: ACME depende de tempo correto. |

## Acceptance Criteria
1. A plataforma cria e mantém a conta ACME, com a chave protegida pelo envelope.
2. A ordem DNS-01 cria o TXT via `DnsProvider`, aguarda propagação e finaliza.
3. O TXT de challenge é removido após a ordem, em sucesso **e** em falha.
4. Uma `CertificateVersion` é persistida com a chave privada cifrada.
5. O wildcard da zona controlada é emitido com sucesso.
6. Pedidos simultâneos para a mesma cobertura são deduplicados.
7. Rate limit da CA leva a backoff e registro, sem insistência agressiva.
8. Falha da ordem produz `CERTIFICATE_ERROR` com causa e retry controlado.
9. Nenhum log contém a chave da conta, a chave privada ou o token de challenge, provado com valores plantados.
10. Relógio fora de sincronia produz falha explícita.
11. Os testes automatizados usam o ambiente de staging da CA.
12. A emissão é Operation durável; nenhuma requisição HTTP fica aberta.

## Required Tests
- **contract**: ciclo ACME completo (challenge, finalize, failure, retry) contra staging/fake server.
- **integration**: TXT removido em sucesso e falha; deduplicação; rate limit com backoff.
- **security**: valores plantados ausentes de log; SSRF nas chamadas ao provider.
- **E2E**: emissão real do wildcard em ambiente de laboratório.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ciclo ACME provado contra staging, TXT removido em ambos os caminhos, Critical/High = 0.
