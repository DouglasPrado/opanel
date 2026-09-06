# M07-10 — Customer wildcard certificates and delegated zones

## Objective
Suportar o caso em que o cliente delega uma zona à plataforma e quer subdomínios dinâmicos sob um wildcard próprio.

## Outcome
Com a zona delegada e o provider conectado, a plataforma emite um wildcard do **cliente** e serve qualquer subdomínio configurado sob ele.

## References
- `docs/architecture/08-networking-domains-edge.md` §15 (wildcard do cliente: “quando o cliente delega DNS e quer previews/subdomínios dinâmicos”), §12
- `docs/annexes/C-threat-model-security-hardening.md` §14.1 (DNS token com menor escopo)

## Preconditions
`M07-03` e `M07-04` done.

## Scope
- Zona delegada: o cliente conecta o provider da sua zona e autoriza a plataforma a gerenciá-la.
- Emissão de wildcard do cliente via DNS-01 (única opção; HTTP-01 não emite wildcard).
- Uso do wildcard do cliente para subdomínios sob aquela zona, com a mesma disciplina de distribuição e ativação de `M04-10`.
- Verificação de posse da **zona** (`M07-06`) como pré-condição.
- Limite explícito: o wildcard do cliente cobre **apenas** a zona dele; nunca é misturado com outros Teams nem com a zona da plataforma.

## Out of Scope
- Preview environments por Pull Request (backlog) — o wildcard é a infraestrutura que os viabilizaria depois.
- Subdomínios dinâmicos criados automaticamente sem `DomainBinding`.
- Delegação parcial de zona.

## Application Layer
- **Commands:** `DelegateZone`, `IssueCustomerWildcard`.
- **Queries:** `DelegatedZones`.

## Security Requirements
- **Blast radius**: um wildcard cobre todos os subdomínios da zona. Ele é aceitável para a zona **do próprio cliente**, e inaceitável entre clientes — a regra do doc 08 §15 é explícita.
- A posse da zona é verificada antes da emissão.
- A credencial da zona delegada tem escopo mínimo, restrito àquela zona.
- Um subdomínio sob a zona delegada só é servido quando existe `DomainBinding` — o wildcard não cria rota sozinho.
- Revogar a delegação retira a zona do gerenciamento e retira o wildcard após o grace period.
- Todas as chamadas passam pela política de SSRF.

## Observability Requirements
Zonas delegadas com estado, wildcard associado e validade. Métrica de subdomínios servidos por zona.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Posse da zona não verificada | Wildcard **não** é emitido. |
| Provider sem escopo para a zona | Erro distinto de autenticação, indicando o que falta. |
| Subdomínio sem `DomainBinding` | Não é servido; o wildcard não cria rota sozinha. |
| Delegação revogada | Zona sai do gerenciamento; wildcard retirado após o grace period. |
| Wildcard de um cliente cobrindo domínio de outro | Impossível por construção; teste guarda a propriedade. |
| Rate limit da CA em wildcard | Backoff; deduplicação por conjunto de nomes. |

## Acceptance Criteria
1. O cliente delega uma zona conectando o provider e autorizando o gerenciamento.
2. A posse da zona é verificada **antes** da emissão do wildcard.
3. O wildcard do cliente é emitido via DNS-01.
4. O wildcard cobre **apenas** a zona do cliente; nunca é compartilhado entre Teams, provado por teste.
5. Um subdomínio só é servido quando existe `DomainBinding`; o wildcard não cria rota sozinho.
6. A credencial da zona tem escopo mínimo restrito àquela zona.
7. Revogar a delegação retira a zona do gerenciamento e o wildcard após o grace period.
8. Provider sem escopo produz erro distinto de autenticação.
9. Pedidos redundantes de wildcard são deduplicados; rate limit leva a backoff.
10. Todas as chamadas passam pela política de SSRF.
11. Zonas delegadas e wildcards são observáveis com estado e validade.

## Required Tests
- **contract**: emissão de wildcard via DNS-01 contra CA de staging.
- **integration**: posse não verificada bloqueando; subdomínio sem binding não servido; revogação da delegação.
- **security**: wildcard não compartilhado entre Teams; escopo da credencial; SSRF.
- **Docker/Swarm**: subdomínio servido sob o wildcard do cliente.

## Quality Gates
Local Quality Gate + contract tests + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, isolamento do wildcard entre Teams provado, posse exigida antes da emissão, Critical/High = 0.
