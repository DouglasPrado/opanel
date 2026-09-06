# M13-09 — GA scale floors and reference dataset

## Objective

Exercitar os pisos de teste definidos no Anexo B §9.1, provando que a plataforma opera nas quantidades mínimas exigidas para GA — e declarando o que está além do envelope testado.

## Outcome

Uma declaração honesta de capacidade: o que foi testado, com que números, e onde o suporte termina.

## References

- `docs/annexes/B-nfr-slos.md` §9, §9.1, §10
- `docs/annexes/D-test-strategy.md` §13, §22

## Preconditions

- `M13-06` concluída.

## Scope

- Dataset de escala nos pisos GA: nós, Services por cluster, Services por nó, rotas de ingress, domínios, Secrets, Releases retidos, Operations históricas e usuários por Team.
- Execução das jornadas críticas **com o dataset cheio**: listar, filtrar, abrir detalhe, fazer deploy, ver logs, ver métricas.
- Verificação de que consultas operacionais frequentes usam índice e não degradam com o volume.
- Verificação de que nenhuma listagem carrega coleção sem paginação.
- Medição da UI: tempo de resposta das páginas Inertia com o dataset cheio.
- Limites documentados: o valor testado, o comportamento ao ultrapassá-lo e a orientação operacional.

## Out of Scope

- Escala além dos pisos GA: documentada como não testada, não como “suportada”.

## Security Requirements

- O dataset não contém dado real; a geração é sintética e determinística.

## Observability Requirements

- Relatório com os pisos atingidos, a duração e o comportamento de cada jornada.
- Lista das consultas mais caras e do seu plano de execução.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Listagem sem paginação | Finding **High**. |
| Consulta operacional sem índice | Finding **High**. |
| N+1 em jornada crítica | Finding **High**. |
| Página inutilizável com o dataset cheio | Finding **Critical** para a jornada afetada. |

## Acceptance Criteria

1. Todos os pisos de teste do Anexo B §9.1 são exercitados.
2. As jornadas críticas funcionam dentro do SLO com o dataset cheio.
3. Nenhuma listagem carrega coleção potencialmente grande sem paginação.
4. Consultas operacionais frequentes usam índice verificado.
5. Não há N+1 em jornada crítica.
6. Os limites testados são documentados com o comportamento ao ultrapassá-los.
7. O que não foi testado é declarado como não testado.

## Required Tests

- Integration com dataset de escala.
- Verificação de plano de execução das consultas críticas.
- E2E das jornadas críticas com o dataset cheio.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 7 Acceptance Criteria com evidência.
- [ ] Limites publicados no relatório.
- [ ] Self-review; `tasks.json` atualizado com commit.
