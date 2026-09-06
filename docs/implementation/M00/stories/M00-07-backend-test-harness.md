# M00-07 — Backend test harness with real PostgreSQL

## Objective
Estabelecer o harness de testes de backend — RSpec + FactoryBot sobre PostgreSQL real — com isolamento, determinismo e controle de relógio, conforme o Anexo D.

## Outcome
`bin/test` roda unit, integration e request; cada job de CI usa banco próprio; factories criam apenas o necessário; testes podem controlar o relógio sem esperar tempo real.

## References
- `docs/annexes/D-test-strategy.md` §4 (unit), §5 (PostgreSQL e transações), §5.1 (concorrência), §22 (fixtures e isolamento)
- `docs/implementation/SPEC_CONFLICTS.md` SC-03 (escolha dos runners delegada ao pack)
- `docs/AGENT_RULES.md` — “Testing”

## Preconditions
`M00-02` done.

## Scope
- RSpec configurado com tipos separados: `unit`, `integration`, `request`, `policy`, `contract`.
- FactoryBot com factories mínimas e linting de factory.
- Banco de teste real, recriável, com estratégia de limpeza determinística.
- Suporte a **múltiplas conexões e barreiras** para testes de concorrência (exigido pelo Anexo D §5.1 e usado a sério a partir de `M01-16`).
- Controle de relógio (freeze/travel) para testar expiração, retry, renovação e retenção.
- Paralelização com namespaces únicos por processo e cleanup idempotente.
- Relatórios em formato consumível pelo CI (JUnit/JSON) com metadata de commit e ambiente.

## Out of Scope
- Testes de frontend e E2E (`M00-08`).
- Swarm Lab (`M00-17`).
- Testes de carga e chaos (M13).

## Security Requirements
- Fixtures sintéticas; proibido copiar dado de produção (Anexo D §22).
- Credenciais de teste são rotacionáveis e distintas de qualquer outro ambiente.
- Relatórios de teste não podem conter valor sensível.

## Observability Requirements
Saída de teste identifica commit, ambiente, duração e tipo de suíte, para virar evidência de release (Anexo D §24).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Teste depende de ordem global | O harness embaralha a ordem por padrão e o teste falha, expondo a dependência. |
| Cleanup falha após crash | Cleanup é idempotente e roda de novo sem erro. |
| Teste intermitente | Política de flaky do Anexo D §20.1: quarentena com dono e prazo; **nunca** retry até verde. |

## Acceptance Criteria
1. `bin/test` executa a suíte de backend contra **PostgreSQL real** e retorna exit code 0.
2. Suítes são separáveis por tipo e executáveis individualmente.
3. Ordem de execução é aleatória por padrão e a seed é reportada para reprodução.
4. Existe helper de teste de concorrência com múltiplas conexões e barreira explícita, provado por um teste que reproduz um lost update sem ele e o evita com ele.
5. O relógio é controlável em teste; existe um teste que exercita expiração sem esperar tempo real.
6. A execução paralela usa namespaces únicos e o cleanup é idempotente após crash simulado.
7. Factory lint passa; nenhuma factory cria dados além do necessário.
8. O relatório de teste inclui commit, ambiente, duração e resultado por suíte.
9. Nenhuma fixture contém dado real ou PII.

## Required Tests
- **unit**: helpers do próprio harness (relógio, namespace, barreira).
- **integration**: suíte roda contra PostgreSQL real; cleanup idempotente após crash simulado; teste de concorrência com barreira.

## Quality Gates
Local Quality Gate classes Ruby/Rails e Database. A partir desta Story, toda Story seguinte declara suas suítes obrigatórias em `Required Tests` e elas rodam por este harness.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, teste de concorrência demonstrando a barreira, política de flaky documentada, Critical/High = 0.
