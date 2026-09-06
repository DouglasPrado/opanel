# M13-06 — Performance Lab and versioned baseline

## Objective

Estabelecer o ambiente, o dataset e a baseline sem os quais nenhum resultado de performance é comparável — e portanto nenhum é evidência.

## Outcome

Um laboratório provisionável por código, um dataset de referência determinístico e uma baseline por versão que permite dizer “regrediu” com números, não com impressão.

## References

- `docs/annexes/B-nfr-slos.md` §9, §17
- `docs/annexes/D-test-strategy.md` §13, §13.2, §24

## Preconditions

- Infraestrutura de laboratório disponível (não é produção).

## Scope

- Topologia declarada e provisionada por código: número de managers, workers, recursos por nó, versões de Docker, PostgreSQL e Traefik.
- **Dataset de referência** determinístico e gerado por seed: N Teams, Projects, Environments, Services, Secrets, Domains, Releases e histórico de Operations.
- Harness de carga com perfis nomeados e parâmetros versionados.
- Coleta padronizada: p50/p95/p99 de latência, taxa de erro, throughput, saturação de CPU/memória/IO, profundidade de fila, tempo de recuperação.
- **Baseline por versão**: resultado arquivado, associado a commit, topologia e dataset.
- Comparação automatizada contra a baseline compatível, com margem de regressão definida por métrica.
- Regra explícita: comparação entre topologias ou datasets diferentes é **inválida** e a ferramenta recusa.

## Out of Scope

- Os testes de carga em si (`M13-07`, `M13-08`, `M13-11`) — esta Story entrega a fundação.

## Security Requirements

- O dataset de referência **não** contém dado real de cliente nem secret real.
- O laboratório não tem acesso a credencial de produção.

## Observability Requirements

- Todo relatório de performance carrega: commit, ambiente, topologia, dataset, parâmetros, duração, resultado e disposição.
- Resultado sem essa metadata é rejeitado pela ferramenta de comparação.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Metadata incompleta | Resultado rejeitado; não vira baseline nem evidência. |
| Comparação entre topologias diferentes | Recusada com mensagem explícita. |
| Dataset não determinístico | Falha de setup; seed obrigatória. |
| Regressão acima da margem | Gate falha com a métrica e o delta. |

## Acceptance Criteria

1. A topologia é provisionada por código e registrada no relatório.
2. O dataset é determinístico por seed e não contém dado real.
3. O harness expõe perfis nomeados e versionados.
4. As métricas coletadas incluem latência p50/p95/p99, erro, throughput, saturação, fila e recovery.
5. Cada execução produz relatório com a metadata obrigatória do Anexo D §24.
6. A baseline é arquivada por versão e associada a commit, topologia e dataset.
7. A comparação recusa combinações incompatíveis.
8. A margem de regressão é definida por métrica e aplicada automaticamente.
9. “Não caiu” não é aceito como critério de aprovação.

## Required Tests

- Teste do harness contra carga sintética conhecida.
- Teste de que a comparação recusa metadata incompleta ou incompatível.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Baseline inicial arquivada.
- [ ] Self-review; `tasks.json` atualizado com commit.
