# M00-17 — Disposable Docker/Swarm Lab harness

## Objective
Criar um laboratório Docker/Swarm descartável e reproduzível, para que o comportamento de runtime seja testado contra infraestrutura **real** — não contra mocks — desde o primeiro Milestone que toca o Swarm.

## Outcome
`bin/swarm-lab up` sobe um Swarm descartável e utilizável; `bin/swarm-lab down` o destrói; ambos são idempotentes; o harness de teste consegue criar e remover Services e networks com namespaces únicos.

## References
- `docs/annexes/D-test-strategy.md` §3 (ambientes), §3.1 (reprodutibilidade), §7 (Docker e Swarm integration tests)
- `docs/annexes/H-autonomous-development-loop.md` §12.2 (Swarm Lab)
- `docs/architecture/06-infrastructure-provisioning.md` §4 (portas e firewall do Swarm)
- `docs/annexes/C-threat-model-security-hardening.md` §8 (docker socket)

## Preconditions
`M00-07` done.

## Scope
- Provisionamento por código de um Swarm de laboratório com versão de Docker **conhecida e registrada**.
- `bin/swarm-lab up|down|status|reset`, idempotentes.
- Helpers de teste: criar/remover Service, network, secret e config com sufixo único por execução, e cleanup idempotente que roda de novo após crash.
- Registro da versão de Docker/Engine API usada, para a suíte de compatibilidade de `M13-12`.
- Guardrail: o harness recusa apontar para um Docker que **não** seja o laboratório; a verificação é explícita e não pode ser desligada por variável de ambiente sozinha.

## Out of Scope
- Cluster multi-node real (M08 usa este lab e o estende).
- Registry e Traefik de laboratório (`M05` e `M04` acrescentam quando precisarem).
- Chaos e injeção de falha (M13).
- Qualquer código de aplicação que fale com Docker — em M00 só o harness de teste fala.

## Security Requirements
- O lab **nunca** aponta para um Docker de produção. O guardrail verifica isso e falha fechado (Anexo H §12.2).
- Nenhum código fora de `app/executors/` e do harness de teste referencia Docker — garantido por AF-02 de `M00-13`.
- O socket do lab não é montado em nenhum container de workload de teste.
- Portas internas do Swarm (2377, 7946, 4789) ficam restritas à rede do laboratório.

## Observability Requirements
`bin/swarm-lab status` reporta: versão do Docker, número de nodes, Services criados pelo harness, e recursos órfãos de execuções anteriores.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Docker indisponível | `up` falha com mensagem acionável; a suíte que depende do lab é pulada com marcação explícita, nunca reportada como verde. |
| `down` após crash | Idempotente: remove o que existir, não falha pelo que já não existe. |
| Recursos órfãos de execução anterior | `status` os identifica e `reset` os remove; nenhum teste depende de estado herdado. |
| Harness apontando para Docker errado | Guardrail falha fechado antes de qualquer mutação. |
| Versão de Docker incompatível | Falha explícita nomeando a versão encontrada e a esperada. |

## Acceptance Criteria
1. `bin/swarm-lab up` sobe um Swarm de laboratório funcional e registra a versão do Docker.
2. `bin/swarm-lab down` destrói o laboratório sem deixar recurso órfão.
3. `up` e `down` executados duas vezes seguidas terminam com exit code 0 (idempotência).
4. `bin/swarm-lab status` reporta versão, nodes, Services do harness e órfãos.
5. Os helpers de teste criam recursos com sufixo único por execução e limpam de forma idempotente após crash simulado.
6. Um teste de integração cria um Service no lab, observa suas Tasks e o remove.
7. O guardrail impede o harness de apontar para um Docker fora do laboratório, provado por caso negativo.
8. Com Docker indisponível, a suíte dependente é marcada como pulada explicitamente, nunca como verde.
9. A versão de Docker/Engine API do lab está registrada em arquivo versionado.

## Required Tests
- **unit**: guardrail de destino; gerador de namespace único.
- **Docker/Swarm integration**: ciclo criar/observar/remover Service; cleanup idempotente após crash; idempotência de `up`/`down`.
- **security**: guardrail de Docker de produção; ausência de referência a Docker fora de executor/harness (AF-02).

## Quality Gates
Local Quality Gate classe Infrastructure. A suíte Docker/Swarm passa a integrar o Merge Gate a partir de `M01`.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, ciclo completo contra Swarm real, guardrail provado por caso negativo, Critical/High = 0.
