# M13-13 — SLO instrumentation and error budget policy validation

## Objective

Transformar os SLOs do Anexo B em thresholds mensuráveis e automatizados, e provar que a instrumentação mede o que promete — inclusive quando o sistema está degradado.

## Outcome

Um SLO que falha o gate quando é violado, em vez de um número em um documento.

## References

- `docs/annexes/B-nfr-slos.md` §3, §3.1, §4, §15
- `docs/annexes/D-test-strategy.md` §19
- `docs/architecture/03-runtime-observability.md`

## Preconditions

- Observabilidade de M09 implementada; `M13-06` e `M13-07` concluídas.

## Scope

- Tradução de cada SLO do Anexo B em um indicador com: definição, janela, fonte de dado e threshold.
- Verificação de que o indicador é calculado a partir de dado **realmente coletado**, não de uma estimativa.
- Injeção de violação controlada: degradar deliberadamente uma dependência e confirmar que o indicador registra a violação no tempo esperado.
- Verificação de que dependência degradada aparece como degradada — nunca mascarada como saudável.
- Cálculo e consumo de **error budget**: janela, taxa de consumo e o que acontece ao esgotar.
- Política de error budget: quais ações ficam bloqueadas ao esgotar e quem pode liberar.
- Gate automatizado: violação de SLO na execução do Release Candidate falha o gate com o indicador nomeado.
- Verificação de que os indicadores não usam labels de alta cardinalidade nem valores sensíveis.

## Out of Scope

- Definir novos SLOs: o Anexo B é a fonte; divergência vira conflito registrado, não decisão local.

## Security Requirements

- Nenhum indicador expõe identificador sensível ou valor de secret em label.
- O acesso aos painéis de SLO respeita o escopo de tenancy.

## Observability Requirements

- Cada indicador documenta fonte, janela e fórmula.
- Relatório do Release Candidate lista indicador, valor medido, threshold e disposição.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Indicador não registra violação injetada | Finding **Critical** — a medição é falsa. |
| Dependência degradada aparece saudável | Finding **Critical**. |
| SLO sem fonte de dado real | Finding **High**. |
| Label de alta cardinalidade | Finding **High**. |
| Error budget esgotado sem efeito | Finding **Medium**; política inócua. |

## Acceptance Criteria

1. Todo SLO do Anexo B tem indicador com definição, janela, fonte e threshold.
2. Cada indicador é calculado a partir de dado efetivamente coletado.
3. Uma violação injetada é registrada pelo indicador no tempo esperado.
4. Dependência degradada nunca aparece como saudável.
5. O error budget é calculado, com taxa de consumo observável.
6. A política de esgotamento bloqueia as ações declaradas e nomeia quem libera.
7. Violação de SLO falha o gate do Release Candidate com o indicador nomeado.
8. Nenhum indicador usa alta cardinalidade ou valor sensível.
9. O relatório do Release Candidate lista indicador, valor, threshold e disposição.

## Required Tests

- Integration com injeção de degradação controlada.
- Teste do gate contra um resultado que viola o SLO.

## Quality Gates

Local Quality Gate; gate de SLO automatizado.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Gate de SLO provado contra violação deliberada.
- [ ] Self-review; `tasks.json` atualizado com commit.
