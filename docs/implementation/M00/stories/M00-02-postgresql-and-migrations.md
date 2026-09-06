# M00-02 — PostgreSQL, database bootstrap and migration tooling

## Objective
Conectar a aplicação ao PostgreSQL da plataforma e estabelecer a política de migrations que vale para todos os Milestones: expand-contract, reversível e validada automaticamente.

## Outcome
`bin/rails db:prepare` funciona em banco vazio; uma migration de exemplo aplica e reverte; o validador de migrations rejeita uma migration destrutiva sem marcador de fase contract.

## References
- `docs/AGENT_RULES.md` — “Database Rules”
- `docs/annexes/I-engineering-playbook-quality-gates.md` §8 (regras e Migration Gate)
- `docs/annexes/D-test-strategy.md` §5 (integração com PostgreSQL real)
- `docs/architecture/09-data-model-apis-contracts.md` §26 (migrações e compatibilidade)
- `docs/decisions/ADR-0002-identifier-strategy.md`

## Preconditions
`M00-01` done. ADR-0002 precisa estar **aceito** para que a convenção de chave primária seja aplicada aqui — se ainda estiver `Proposed`, a Story implementa tudo exceto o helper de ID e marca esse ponto como pendente.

## Scope
- Configuração de conexão por ambiente (development, test, ci), com pool explícito.
- `db:prepare` funcionando em banco limpo.
- Convenção de chave primária conforme ADR-0002 (helper único de geração de ID).
- Migration Gate executável: checa reversibilidade, marcador de fase contract em `DROP`/rename, e índice potencialmente pesado sinalizado.
- Uma migration de exemplo (tabela técnica de infraestrutura, não de domínio) que exercita o caminho completo.

## Out of Scope
- Qualquer tabela de domínio do Opanel.
- Solid Queue (`M00-03`).
- Backups (M10).

## Domain Impact
Nenhuma entidade de domínio. Apenas a infraestrutura de schema e a convenção de identificadores.

## Security Requirements
- Credencial do banco vem da camada de configuração (`M00-16`), nunca hardcoded.
- O banco de teste é distinto do de desenvolvimento e é recriável; nenhuma fixture com dado real.

## Observability Requirements
Falha de conexão ao banco precisa aparecer como erro classificado com causa, não como timeout genérico — é o mesmo padrão que o RB-02 vai exigir em produção.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| PostgreSQL indisponível no boot | Erro explícito identificando host/porta/database; readiness (`M00-15`) reporta o banco como indisponível. |
| Migration irreversível sem plano | Migration Gate falha e bloqueia o commit. |
| Pool esgotado em teste | Teste falha de forma determinística, não intermitente. |

## Acceptance Criteria
1. `bin/rails db:prepare` cria o schema a partir de banco vazio, sem erro.
2. A migration de exemplo aplica com `db:migrate` e reverte com `db:rollback` sem perda de estrutura.
3. O helper de chave primária gera identificadores conforme ADR-0002 e é o **único** ponto de geração no código.
4. O Migration Gate reprova, em teste, uma migration que remove coluna sem marcador de fase contract.
5. O Migration Gate reprova uma migration sem `down` nem plano de forward-fix documentado.
6. Ambientes `development`, `test` e `ci` usam bancos distintos e configuráveis.
7. Um teste de integração roda contra **PostgreSQL real**, não SQLite.

## Required Tests
- **unit**: geração e validação de identificadores; parser do Migration Gate.
- **integration**: `db:prepare` em banco limpo; migrate/rollback; conexão com credencial inválida falha de forma classificada.
- **security**: nenhuma credencial de banco aparece em log ou mensagem de erro.

## Quality Gates
Local Quality Gate classe Database (Anexo I §11.1): migration validation + testes de integração + constraint/query relevante.

## Definition of Done
Os 7 Acceptance Criteria satisfeitos com PostgreSQL real, Migration Gate provado por caso negativo, nenhum dado sensível em log, Critical/High = 0.
