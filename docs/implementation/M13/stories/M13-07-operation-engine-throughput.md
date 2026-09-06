# M13-07 — Operation Engine and reconciler throughput

## Objective

Medir a capacidade real do caminho durável — API → Operation → fila → worker → executor → reconciler — e determinar onde ele satura antes que a produção descubra.

## Outcome

Um envelope de capacidade conhecido: quantas Operations por minuto a plataforma sustenta, com que latência, e o que acontece quando a demanda excede a capacidade.

## References

- `docs/annexes/B-nfr-slos.md` §5, §17
- `docs/architecture/07-internal-control-plane.md`
- `docs/annexes/D-test-strategy.md` §13

## Preconditions

- `M13-06` concluída: laboratório, dataset e baseline disponíveis.

## Scope

- Carga sobre a API do Control Plane com o perfil operacional alvo.
- Enfileiramento sustentado de Operations com mix realista (deploy, scale, restart, secret rotation, cert renewal).
- Medição de: latência de aceitação da intenção (a API responde rápido porque não espera o efeito), tempo até `RUNNING`, tempo até conclusão, profundidade de fila e tempo de drenagem.
- Reconcilers sob carga: tempo de varredura completa com o dataset de referência, custo por recurso, comportamento com muitos recursos em drift.
- **Backpressure**: comportamento quando a fila cresce além do alvo — degradação previsível, não colapso.
- Recuperação: parar os workers, acumular fila, religar e medir o tempo de drenagem.
- Verificação de que a serialização por recurso não vira gargalo global.

## Out of Scope

- Carga do edge (`M13-08`) e abuso deliberado (`M13-11`).

## Security Requirements

- A carga usa credenciais de laboratório; nenhuma credencial de produção.

## Observability Requirements

- Resultado comparado com a baseline de `M13-06` e a margem de regressão aplicada.
- Relatório com o ponto de saturação identificado e o gargalo dominante nomeado.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Fila colapsa sob carga alvo | Gate falha; capacidade insuficiente. |
| API bloqueia esperando o efeito | Finding **Critical** — viola “mutação é assíncrona”. |
| Sweep não termina no intervalo alvo | Finding **High**. |
| Drenagem após restart não converge | Finding **High**. |
| Serialização por recurso trava recursos não relacionados | Finding **High**. |

## Acceptance Criteria

1. A API suporta a carga operacional alvo sem a fila colapsar.
2. A latência de aceitação permanece dentro do SLO, independente do custo do efeito.
3. O ponto de saturação é identificado e o gargalo dominante é nomeado.
4. A varredura completa dos reconcilers termina dentro do intervalo alvo com o dataset de referência.
5. O backpressure degrada de forma previsível e documentada.
6. Após acúmulo e restart, a fila drena de forma determinística e sem duplicar efeito.
7. A serialização por recurso não bloqueia recursos não relacionados.
8. O resultado é comparado com a baseline e a margem de regressão é respeitada.

## Required Tests

- Testes de carga com os perfis do harness.
- Teste de recuperação com acúmulo e restart.

## Quality Gates

Local Quality Gate; comparação contra baseline.

## Definition of Done

- [ ] 8 Acceptance Criteria com evidência.
- [ ] Envelope de capacidade documentado.
- [ ] Self-review; `tasks.json` atualizado com commit.
