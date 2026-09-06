# M00-01 — Repository layout and Rails 8.1 application skeleton

## Objective
Criar a aplicação Rails 8.1.x única do Control Plane e congelar a estrutura de diretórios que todos os Milestones seguintes vão respeitar.

## Outcome
`bin/rails server` sobe a aplicação; `bin/rails runner` executa; a estrutura de boundaries do Anexo I §4.1 existe no disco com README curto em cada diretório explicando o que pode e o que não pode viver ali.

## References
- `docs/AGENT_RULES.md` — “Approved stack”, “Backend Rules”, “Frontend Rules”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §4 (boundaries), §6.1 (hierarquia de frontend)
- `docs/implementation/SPEC_CONFLICTS.md` SC-01

## Preconditions
Nenhuma. Primeira Story do pack.

## Scope
- Aplicação Rails 8.1.x única (não API-only: serve a UI via Inertia).
- Diretórios de backend: `app/commands/`, `app/queries/`, `app/policies/`, `app/operations/`, `app/reconcilers/`, `app/executors/`, `app/providers/`, além dos padrões do Rails.
- Diretórios de frontend: `app/frontend/{components/{ui,shared,features,layouts},pages,hooks,lib,types}`.
- `README` do repositório com o comando único de bootstrap (preenchido de fato em `M00-06`).
- `.gitignore` cobrindo artefatos de build, logs locais, `node_modules`, credenciais e diretórios de evidence.
- Um `README.md` de uma tela em cada diretório de boundary declarando responsabilidade e proibições.

## Out of Scope
- PostgreSQL e migrations (`M00-02`).
- Inertia/React/Vite/Tailwind (`M00-04`).
- Qualquer model, controller ou rota de domínio.
- Docker, CI e gates.

## Domain Impact
Nenhum. Nenhuma entidade de domínio é criada nesta Story.

## Application Layer
Cria os **diretórios** de Commands, Queries e Policies, vazios, com a regra de dependência documentada: `controllers → commands|queries → models`; `reconcilers → executors`; `providers` isolam APIs externas e não vazam SDK para o domínio.

## Security Requirements
- `.gitignore` impede versionar `config/master.key`, `.env*`, credenciais e dumps.
- Nenhum segredo default embutido no repositório.
- `app/executors/` nasce com um `README.md` declarando que é o **único** boundary autorizado a falar com a Docker Engine API — a regra que a fitness function AF-02 vai verificar em `M00-13`.

## Observability Requirements
Nenhuma nesta Story. O logger estruturado entra em `M00-15`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Versão de Ruby/Rails incompatível | O boot falha com mensagem explícita indicando a versão exigida; não degrada para outra versão. |
| Diretório de boundary criado sem README | `M00-13` (AF) detecta boundary não documentado. |

## Acceptance Criteria
1. `bin/rails -v` reporta Rails 8.1.x.
2. A aplicação **não** está em modo API-only e consegue renderizar uma resposta HTML.
3. Existem `app/commands/`, `app/queries/`, `app/policies/`, `app/operations/`, `app/reconcilers/`, `app/executors/`, `app/providers/`, cada um com `README.md` de responsabilidade e proibições.
4. Existe `app/frontend/components/{ui,shared,features,layouts}` e `app/frontend/{pages,hooks,lib,types}`.
5. `git status` está limpo após um boot completo — nenhum artefato gerado escapa do `.gitignore`.
6. O repositório não contém nenhuma referência a Next.js, e nenhum diretório `apps/api` ou `apps/web`.

## Required Tests
- **unit**: teste que afirma a presença e a nomenclatura dos diretórios de boundary (falha se um for removido ou renomeado).
- **integration**: boot da aplicação em ambiente de teste retorna 200 em uma rota de placeholder.

## Quality Gates
Local Quality Gate (Anexo I §11.1, classe Ruby/Rails). Pre-commit e Post-commit ainda não existem — esta Story roda com verificação manual documentada no Story Report e é revalidada quando `M00-12` entregar os scripts.

## Definition of Done
Os 6 Acceptance Criteria satisfeitos, testes verdes, diff restrito ao esqueleto do repositório, Story Report com os comandos executados e nenhum Critical/High aberto no review.
