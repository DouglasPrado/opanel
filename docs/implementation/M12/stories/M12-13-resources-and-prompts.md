# M12-13 — MCP Resources and Prompts

## Objective
Oferecer contexto reutilizável e navegável por Resources read-only, e guias de fluxo por Prompts — sem que nenhum deles vire autoridade.

## Outcome
O agente lê `paas://services/{id}` para obter contexto sem executar mutação, e usa prompts para conduzir fluxos seguros de deploy, diagnóstico e restore.

## References
- `docs/annexes/F-mcp-platform-agents.md` §8 (Resources e Prompts), §8.1 (resources read-only), §8.2 (prompts são conveniência, não autoridade)

## Preconditions
`M12-06` done.

## Scope
- Resources com URIs opacas e estáveis do Anexo F §8.1: teams, projects, environments, services, deployments, operations, clusters, incidents, runbooks.
- **Autorização no momento da leitura**, não apenas na listagem.
- Prompts do Anexo F §8.2: `deploy_application`, `diagnose_service`, `production_change_plan`, `incident_triage`, `restore_plan`.
- Prompts referenciando os Runbooks do Anexo E quando aplicável.
- Regra explícita: **Prompts são conveniência; a segurança é determinada pelas tools e pelo Control Plane.**

## Out of Scope
- MCP Apps.
- Resources que exponham conteúdo sensível.
- Prompts que instruam bypass de política.

## Security Requirements
- **Resources são read-only** e sempre autorizados **no momento da leitura** (Anexo F §8.1, regra explícita) — um URI memorizado não vale como permissão futura.
- URIs são opacas e estáveis; elas não revelam estrutura interna nem permitem enumeração.
- `paas://runbooks/{id}` entrega o runbook **sem credenciais** (Anexo F §8.1).
- Nenhum Resource retorna secret, credencial ou material sensível.
- **Prompts não são autoridade**: um prompt não pode conceder capacidade nem sugerir contorno de política. O texto dos prompts é controlado pela plataforma, não pelo cliente.
- O conteúdo dinâmico interpolado em um prompt é sanitizado — ele pode vir de logs ou de nomes de recursos.

## Observability Requirements
Leituras de Resource por conexão; prompts utilizados. Uma sequência de leituras ampla é sinal de enumeração.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| URI de recurso fora do boundary | `NOT_FOUND` sem confirmar existência. |
| URI memorizada após perda de permissão | Negada na leitura. |
| Runbook com credencial | Impossível: runbooks não carregam credenciais. |
| Prompt tentando instruir bypass | Não existe: o texto é da plataforma. |
| Conteúdo dinâmico com injection | Sanitizado. |
| Resource muito grande | Paginado ou resumido. |

## Acceptance Criteria
1. Os Resources do Anexo F §8.1 existem com URIs opacas e estáveis.
2. A autorização acontece **no momento da leitura**, não apenas na listagem, provado por teste com permissão revogada.
3. URI de recurso fora do boundary responde sem confirmar existência.
4. Nenhum Resource retorna secret, credencial ou material sensível, provado com valor plantado.
5. `paas://runbooks/{id}` entrega o runbook **sem credenciais**.
6. Os cinco Prompts do Anexo F §8.2 existem.
7. O texto dos prompts é controlado pela plataforma; o cliente não o define.
8. **Prompts não concedem capacidade**; a segurança vem das tools, provado por teste.
9. Conteúdo dinâmico interpolado em prompt é sanitizado.
10. Resource grande é paginado ou resumido.
11. Prompts de incidente referenciam os Runbooks do Anexo E.
12. Leituras de Resource respeitam tenancy; negativo cross-team passa.

## Required Tests
- **security**: autorização na leitura com permissão revogada; enumeração por URI; valor plantado ausente; prompt não concedendo capacidade.
- **contract**: URIs estáveis; formato dos Resources.
- **integration**: paginação; sanitização de conteúdo dinâmico.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, autorização na leitura provada, prompts sem autoridade verificados, Critical/High = 0.
