# M07-03 — Managed DNS record creation for connected zones

## Objective
Quando o cliente conecta o provider da sua zona, criar e manter os registros necessários automaticamente, em vez de pedir configuração manual.

## Outcome
Com o provider conectado, adicionar um domínio cria o registro correto; remover o domínio remove o registro que a plataforma criou — e **apenas** esse.

## References
- `docs/architecture/08-networking-domains-edge.md` §10 (DNS Provider integrado), §11 (tipos de registro), §27 (DnsReconciler)
- `docs/architecture/06-infrastructure-provisioning.md` §11.2 (credenciais do provider)

## Preconditions
`M07-02` done. `DnsProvider` de `M04-07` disponível.

## Scope
- Conexão do provider para a **zona do cliente**, com credencial no Vault e escopo mínimo.
- `DnsRecordBinding`: registro criado pela plataforma, com o `externalId` do provider, para saber o que é seu.
- Criação e atualização reconciliadas do registro do domínio.
- Remoção **apenas** dos registros criados pela plataforma.
- Detecção de registro preexistente conflitante: não sobrescrever sem confirmação explícita.

## Out of Scope
- Registros de challenge ACME (`M04-09` já cobre DNS-01; aqui é o registro de apontamento).
- Zona wildcard delegada (`M07-10`).
- Failover de DNS por mudança de endpoint (doc 06 §11.1 menciona; sem requisito imediato).

## Application Layer
- **Reconciler:** `DnsReconciler`.
- **Commands:** `EnsureDnsRecord`, `RemoveManagedDnsRecord`.

## Security Requirements
- **A plataforma só remove o que ela criou.** Apagar um registro preexistente do cliente é destrutivo e irreversível do ponto de vista dele; o `DnsRecordBinding` com `externalId` é o que garante o boundary.
- Credencial da zona no Vault, com escopo mínimo — idealmente restrita àquela zona (Anexo C §14.1).
- Registro preexistente conflitante **não** é sobrescrito sem confirmação explícita.
- Todas as chamadas passam pela política de SSRF de `M04-07`.
- Criação e remoção de registro geram AuditLog.

## Observability Requirements
Registro criado, com tipo, valor e `externalId`. Métrica de operações de DNS por resultado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Registro preexistente com valor diferente | Não sobrescrever; pedir confirmação explícita mostrando o valor atual. |
| Provider indisponível | Domínios já ativos continuam; a criação entra em retry (Anexo B §14). |
| Escopo insuficiente na credencial | Erro distinto de autenticação, indicando o que falta. |
| Remoção de registro que a plataforma não criou | **Bloqueada**. |
| Propagação lenta | `waitPropagation` com timeout; a verificação de `M07-02` continua. |
| Zona removida no provider | Erro classificado; o domínio fica `BLOCKED` com causa. |

## Acceptance Criteria
1. Com o provider conectado, adicionar um domínio cria o registro correto automaticamente.
2. `DnsRecordBinding` registra o `externalId` do provider.
3. A plataforma remove **apenas** registros que ela criou, provado por teste.
4. Registro preexistente com valor diferente **não** é sobrescrito sem confirmação explícita.
5. A credencial da zona vive no Vault com escopo mínimo.
6. Todas as chamadas passam pela política de SSRF.
7. Provider indisponível não afeta domínios já ativos; a criação entra em retry.
8. Escopo insuficiente é erro distinto de autenticação.
9. Zona removida produz erro classificado e o domínio fica `BLOCKED`.
10. Criação e remoção geram AuditLog; negativo cross-team passa.

## Required Tests
- **contract**: create/update/delete na zona do cliente; conflito; propagação.
- **integration**: remoção limitada aos registros da plataforma; registro preexistente não sobrescrito.
- **security**: SSRF; credencial no Vault; bloqueio de remoção de registro alheio.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, boundary de propriedade dos registros provado, Critical/High = 0.
