# M14-04 — Operational runbook exercise program

## Objective

Executar cada runbook do Anexo E, cronometrar, encontrar onde ele falha e corrigi-lo — porque um runbook nunca exercitado é ficção.

## Outcome

Um conjunto de runbooks que funciona nas mãos de quem não os escreveu, com tempos conhecidos.

## References

- `docs/annexes/E-operational-runbooks.md` — RB-01..RB-30
- `docs/annexes/D-test-strategy.md` §19, §15.1

## Preconditions

- Ambiente de laboratório que permita provocar as condições de cada runbook.
- Executor preferencialmente distinto do autor do runbook.

## Scope

- Execução de **todos** os runbooks RB-01..RB-30, cada um com a condição real provocada, não simulada em papel.
- Registro por runbook: pré-condição, passos executados, desvios, tempo total e resultado.
- Verificação de que cada runbook declara: quando usar, pré-condições, passos, verificação de sucesso, o que fazer se falhar e quando escalar.
- Identificação de runbooks que exigem conhecimento tácito — e eliminação dessa dependência.
- Verificação de que runbooks que tocam ações perigosas exigem gate humano explícito e o declaram.
- Correção dos runbooks e reexecução dos corrigidos.
- Índice de runbooks por sintoma, para que sejam encontráveis durante um incidente.

## Out of Scope

- DR drill completo: `M14-05` (usa os runbooks exercitados aqui).

## Security Requirements

- Runbooks de ação perigosa (restore de produção, rotação de Recovery Key, delete de cluster, `force-new-cluster`) declaram o gate humano e **não** são exercitados contra produção.
- Nenhum runbook instrui a desabilitar um controle de segurança como atalho.
- Runbooks não contêm credencial embutida.

## Observability Requirements

- Relatório consolidado: runbook, executor, tempo, desvios, correções.
- Cada runbook aponta para os sinais (métrica, log, alerta) que confirmam sucesso.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Runbook não funciona como escrito | Corrigido e reexecutado; finding registrado. |
| Runbook exige conhecimento não documentado | Finding **High**; dependência eliminada. |
| Runbook de ação perigosa sem gate humano | Finding **Critical**. |
| Runbook com credencial embutida | Finding **Critical**. |
| Runbook sem verificação de sucesso | Finding **High**. |

## Acceptance Criteria

1. Todos os runbooks RB-01..RB-30 são executados com a condição real provocada.
2. Cada execução registra tempo, desvios e resultado.
3. Cada runbook declara quando usar, pré-condições, passos, verificação, falha e escalonamento.
4. Nenhum runbook depende de conhecimento tácito.
5. Runbooks de ação perigosa declaram gate humano e não são executados contra produção.
6. Nenhum runbook instrui a desabilitar controle de segurança.
7. Nenhum runbook contém credencial.
8. Runbooks corrigidos são reexecutados.
9. Existe índice por sintoma, utilizável durante incidente.

## Required Tests

- Exercício operacional de cada runbook, com evidência.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] RB-01..RB-30 exercitados e corrigidos.
- [ ] Self-review; `tasks.json` atualizado com commit.
