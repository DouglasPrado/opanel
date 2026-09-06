# M13-10 — Chaos suite with blast radius and abort conditions

## Objective

Provar, por experimento controlado, que a perda de um componente dentro da tolerância declarada não causa indisponibilidade global indevida nem corrompe o estado.

## Outcome

Um conjunto de experimentos com hipótese, invariante, blast radius e condição de aborto — não “desligar coisas e ver o que acontece”.

## References

- `docs/annexes/D-test-strategy.md` §14
- `docs/architecture/06-infrastructure-provisioning.md` — quorum e tolerância a falhas
- `docs/annexes/B-nfr-slos.md` §14

## Preconditions

- Cluster multi-node de laboratório (M08); backup disponível (M10).

## Scope

Cada experimento declara **hipótese**, **invariante verificada**, **blast radius** e **abort condition**:

- Perda de um worker com Services replicados: reschedule e convergência.
- Perda de um worker com Service `1/1`: indisponibilidade limitada ao Service, com recuperação.
- Perda de um manager com 3 managers: quorum mantido, plataforma operacional.
- Perda de dois managers com 3: quorum perdido — verificar **degradação segura**, não corrupção; Control Plane recusa mutação em vez de aplicar às cegas.
- Queda de um ingress: tráfego continua pelo outro.
- Queda do PostgreSQL do Control Plane: API degrada; Operations em voo não duplicam efeito ao voltar.
- Indisponibilidade do Registry: build/deploy falham de forma explícita, sem estado inconsistente.
- Indisponibilidade do Swarm Executor: Operations ficam pendentes e são recuperadas, não perdidas.
- Partição de rede entre manager e worker: sem split-brain de Desired State.
- Latência e perda de pacote injetadas no caminho do executor.
- Disco cheio no nó de build e no nó do Control Plane.
- Restart do Control Plane no meio de um rollout.

## Out of Scope

- Chaos em produção: fora do escopo do MVP; exige gate humano e maturidade operacional.

## Security Requirements

- Chaos roda apenas em laboratório dedicado, com abort condition automática.
- Degradação nunca abre acesso: falha de dependência não deve resultar em permissão concedida por omissão.

## Observability Requirements

- Cada experimento produz relatório com hipótese, resultado, invariante verificada, tempo de recuperação e desvios.
- A degradação observada é comparada com a documentada em M09; divergência é finding.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Perda de quorum corrompe Desired State | Finding **Critical**. |
| Split-brain aplica configuração divergente | Finding **Critical**. |
| Falha de dependência concede permissão | Finding **Critical**. |
| Operation perdida após queda do executor | Finding **High**. |
| Recuperação excede o alvo declarado | Finding **High**. |
| Abort condition não dispara | Experimento inválido; corrigir o harness. |

## Acceptance Criteria

1. Todos os experimentos listados são executados com hipótese e invariante declaradas.
2. Cada experimento tem blast radius e abort condition, e a abort condition é testada.
3. A perda de um worker, um ingress ou um manager (com 3) não causa indisponibilidade global.
4. A perda de quorum resulta em degradação segura, sem corrupção nem mutação às cegas.
5. Não há split-brain de Desired State sob partição.
6. Operations sobrevivem à queda do executor e do Control Plane, sem duplicar efeito.
7. Falha de dependência nunca concede permissão.
8. Os tempos de recuperação são medidos e comparados com os alvos.
9. Cada experimento gera relatório arquivável.
10. Chaos roda somente em laboratório dedicado.

## Required Tests

- Experimentos de chaos automatizados no laboratório.
- Verificação de invariantes de estado após cada experimento.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 10 Acceptance Criteria com evidência.
- [ ] Invariantes preservadas em todos os experimentos.
- [ ] Relatórios arquivados.
- [ ] Self-review; `tasks.json` atualizado com commit.
