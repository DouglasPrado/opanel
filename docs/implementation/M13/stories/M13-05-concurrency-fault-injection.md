# M13-05 — Concurrency and idempotency suite with deterministic fault injection

## Objective

Provar que operações concorrentes sobre o mesmo recurso não corrompem o Desired State, e que a falha injetada em qualquer ponto do caminho durável leva a um estado consistente e recuperável.

## Outcome

Uma suíte que **força** a corrida em vez de esperar por ela: pontos de injeção explícitos, sem `sleep`, sem “rodar 100 vezes até flakear”.

## References

- `docs/architecture/07-internal-control-plane.md` — locks, leases, fencing tokens, supersessão
- `docs/annexes/D-test-strategy.md` §5.1, §18
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2

## Preconditions

- Operation Engine, outbox, locks e reconcilers implementados (M01, M02).

## Scope

- **Pontos de injeção nomeados** no caminho durável: antes do commit, entre commit e publish, entre publish e claim, durante a execução, após o efeito e antes do registro do resultado.
- Cenários de corrida: dois deploys simultâneos no mesmo Service; deploy + scale; rollback durante rollout; delete durante deploy; drain de node durante rollout; duas rotações de secret; dois writes concorrentes na mesma configuração.
- Idempotência: mesma `Idempotency-Key` no mesmo escopo produz uma operação lógica, mesmo com retry paralelo.
- Fencing: um worker com lease expirado que “acorda” e tenta aplicar é rejeitado pelo token.
- Supersessão: revisão mais nova invalida a mais antiga enfileirada; a antiga termina `SUPERSEDED`, não aplicada.
- Recuperação após restart: kill do worker em cada ponto de injeção; a varredura periódica recupera a Operation sem duplicar efeito.
- Verificação de que nenhuma chamada de rede ocorre dentro de transação.

## Out of Scope

- Testes de carga: `M13-07`.

## Security Requirements

- Corrida não pode produzir escalação: uma operação autorizada não “empresta” contexto para outra.
- Falha injetada não deixa secret em estado intermediário legível.

## Observability Requirements

- Cada execução registra o ponto de injeção, o resultado e o estado final observado.
- Relatório com a matriz `cenário × ponto de injeção` e o invariante verificado em cada célula.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Kill entre commit e publish | Sweep recupera; efeito aplicado exatamente uma vez. |
| Lease expirado aplica efeito | Fencing rejeita; finding **Critical** se aplicar. |
| Revisão antiga sobrescreve nova | Finding **Critical**. |
| Retry duplica efeito não idempotente | Finding **Critical**. |
| Desired State corrompido por corrida | Finding **Critical**. |

## Acceptance Criteria

1. Os pontos de injeção são explícitos e determinísticos; a suíte não depende de timing.
2. Todos os cenários de corrida listados são exercitados.
3. O Desired State permanece íntegro em todos eles.
4. `Idempotency-Key` repetida produz uma operação lógica, inclusive sob paralelismo.
5. Fencing token rejeita worker com lease expirado.
6. Revisão mais nova supersede a mais antiga; a antiga não é aplicada.
7. Kill em cada ponto de injeção é recuperado pelo sweep sem duplicar efeito.
8. Nenhuma chamada de rede ocorre dentro de transação (verificado por teste).
9. A matriz `cenário × ponto de injeção` é completa no relatório.
10. Nenhum teste da suíte é flaky; falha intermitente bloqueia o release.

## Required Tests

- Integration com PostgreSQL real, com hooks de injeção.
- Testes de concorrência com barreiras determinísticas.
- Teste que falha se uma chamada de rede for detectada em transação.

## Quality Gates

Local Quality Gate; AF-08 (eventos e operations carregam correlation IDs).

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Matriz completa e verde, sem flakiness.
- [ ] Self-review; `tasks.json` atualizado com commit.
