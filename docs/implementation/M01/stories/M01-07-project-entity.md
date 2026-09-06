# M01-07 — Project entity and lifecycle

## Objective
Criar o Project — o produto lógico do Team — com ownership inequívoco, slug único e lifecycle explícito.

## Outcome
Um membro autorizado cria, lista, renomeia e arquiva Projects dentro do seu Team; ninguém de fora do Team enxerga nada.

## References
- `docs/architecture/09-data-model-apis-contracts.md` §5.1 (Project), §18 (constraints), §25 (exclusão e retenção)
- `docs/architecture/04-identity-teams-security.md` §2 (hierarquia), §6.2 (matriz)
- `docs/architecture/10-ui-use-cases.md` UC-009, §7 (Projects)

## Preconditions
`M01-04` e `M01-05` done.

## Scope
- `Project`: id, teamId, name, slug, description?, defaultEnvironmentId?, status (`ACTIVE`, `ARCHIVED`, `DELETING`), timestamps, deletedAt.
- Constraint `UNIQUE(teamId, slug) WHERE deletedAt IS NULL`.
- Commands de criação, atualização e arquivamento, com Policy e AuditLog.
- Query de listagem paginada por cursor (obrigatória em coleções potencialmente grandes).
- Slug derivado do nome, editável, **nunca** usado como foreign key.

## Out of Scope
- Environment (`M01-11`).
- Deleção com cleanup de runtime (`M02-09`) — em M01 o Project apenas arquiva.
- Project Settings avançado, templates e clonagem.
- Comparação entre Environments (`M02` em diante).

## Domain Impact
**Entidade:** `Project`.
**Relacionamentos:** `Team 1—N Project`.
**Validações:** slug único entre ativos do mesmo Team; nome obrigatório.
**Transições:** `ACTIVE → ARCHIVED`; `→ DELETING` reservado para `M02-09`.
**Regra:** Project **não** é filho hierárquico de Cluster (doc 09 §5.1) — quem escolhe o Cluster é o Environment.

## Application Layer
- **Commands:** `CreateProject`, `UpdateProject`, `ArchiveProject`.
- **Queries:** `ProjectsForTeam` (paginada por cursor), `ProjectOverview` (versão mínima do doc 09 §23).
- **Policies:** `ProjectPolicy` — criar exige ADMIN ou DEVELOPER conforme escopo; arquivar exige ADMIN.

## API Impact
Servido por Inertia. Erros usam o envelope estável; slug duplicado retorna erro de validação inline, não 500.

## UI Impact
Lista de Projects e criação com fluxo curto: nome e slug apenas. Não pedir build, Git ou domínio antes do Project existir (doc 10 §7.2).

## Security Requirements
- Toda query parte de `teamId`; nenhuma busca por ID sem escopo.
- Criar, atualizar e arquivar geram AuditLog.
- Teste negativo cross-team obrigatório para as três mutações.

## Observability Requirements
Logs com `team_id`, `project_id`, `actor_id` e `request_id`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Slug duplicado no mesmo Team | Validação inline com sugestão; sem perder o formulário preenchido. |
| Mesmo slug em Teams diferentes | Permitido — a unicidade é por Team. |
| Arquivar Project com Environments ativos | Bloqueado com explicação do que precisa acontecer antes. |
| Listagem grande | Paginação por cursor estável sob inserções concorrentes. |

## Acceptance Criteria
1. Um membro autorizado cria um Project dentro do seu Team.
2. `UNIQUE(teamId, slug) WHERE deletedAt IS NULL` existe no banco e é provado por caso negativo.
3. O mesmo slug é permitido em Teams diferentes.
4. Um usuário de outro Team não lista, não lê e não muta o Project, provado por teste cross-team.
5. Arquivar um Project com Environments ativos é bloqueado com erro explicativo.
6. A listagem usa cursor e permanece estável sob inserções concorrentes.
7. Slug é editável e nunca é referenciado por foreign key.
8. Criar, atualizar e arquivar geram AuditLog com actor e resultado.
9. `VIEWER` lê e não muta; a matriz do doc 04 §6.2 está coberta.

## Required Tests
- **unit**: geração e validação de slug; transições de status.
- **integration**: constraint de slug por caso negativo; cursor estável sob concorrência; bloqueio de arquivamento.
- **policy**: matriz de roles + negativo cross-team.
- **request**: envelope de erro para slug duplicado.

## Quality Gates
Local Quality Gate (Ruby/Rails, Database, React/TypeScript) + suíte cross-team obrigatória.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, constraint provada no banco, cross-team verde, Critical/High = 0.
