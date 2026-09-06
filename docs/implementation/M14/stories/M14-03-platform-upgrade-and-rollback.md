# M14-03 — Platform upgrade and rollback exercised in staging

## Objective

Provar que atualizar a plataforma é uma operação rotineira e reversível — com aplicações de cliente permanecendo no ar durante o processo.

## Outcome

Um procedimento de upgrade executado, cronometrado e revertido, com o impacto sobre os workloads medido.

## References

- `docs/annexes/E-operational-runbooks.md` — RB-29 e RB-30
- `docs/annexes/D-test-strategy.md` §16, §16.1
- `docs/implementation/M13/stories/M13-12-upgrade-compatibility-suite.md`

## Preconditions

- Staging equivalente à produção, com dados e workloads representativos.
- `M13-12` verde (compatibilidade N/N-1 comprovada).

## Scope

- Upgrade da versão N-1 para N seguindo o runbook, sem atalho e sem intervenção não documentada.
- Medição do impacto: aplicações de cliente permanecem servindo tráfego durante o upgrade.
- Verificação de que Operations em voo sobrevivem: nenhuma perdida, nenhuma duplicada.
- Migrações aplicadas na ordem expand-contract, com verificação de fase.
- Rollback do código para N-1 com o schema em N, confirmando que a plataforma volta a operar.
- Verificação pós-upgrade: reconcilers convergem, drift não é gerado artificialmente, certificados e rotas permanecem válidos.
- Cronometragem de cada fase e da janela total.
- Correção do runbook com base no que o exercício revelou; reexecução das partes corrigidas.

## Out of Scope

- Upgrade em produção: decisão e execução humanas, com gate próprio.

## Security Requirements

- O upgrade não reabre permissão removida nem restaura secret revogado.
- Nenhuma credencial de produção é usada em staging.

## Observability Requirements

- Relatório: fases, tempos, impacto medido no tráfego, Operations em voo e resultado do rollback.
- Correlação entre o upgrade e qualquer alerta disparado durante a janela.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Aplicação de cliente cai durante o upgrade | Finding **Critical**. |
| Operation em voo perdida ou duplicada | Finding **Critical**. |
| Rollback não restaura operação | Finding **Critical**. |
| Upgrade exige passo não documentado | Runbook corrigido; finding registrado. |
| Reconcilers geram drift artificial após o upgrade | Finding **High**. |

## Acceptance Criteria

1. O upgrade N-1 → N é executado seguindo o runbook, sem passo não documentado.
2. Aplicações de cliente continuam servindo tráfego durante o upgrade.
3. Nenhuma Operation em voo é perdida ou duplicada.
4. As migrações respeitam expand-contract, com fase verificada.
5. O rollback para N-1 restaura a operação da plataforma.
6. Após o upgrade, os reconcilers convergem sem gerar drift artificial.
7. Certificados e rotas permanecem válidos.
8. Cada fase é cronometrada e a janela total é registrada.
9. O runbook é corrigido e as partes corrigidas são reexecutadas.

## Required Tests

- Exercício de upgrade e rollback em staging.
- Verificação de continuidade de tráfego durante a janela.

## Quality Gates

Local Quality Gate; AF-09.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Upgrade e rollback demonstrados com tempos.
- [ ] Self-review; `tasks.json` atualizado com commit.
