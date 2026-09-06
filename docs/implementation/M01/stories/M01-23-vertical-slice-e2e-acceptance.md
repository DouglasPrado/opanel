# M01-23 — Vertical slice end-to-end acceptance

## Objective
Provar, em um único teste automatizado contra infraestrutura real, que a espinha dorsal da arquitetura funciona de ponta a ponta.

## Outcome
Um E2E executa a jornada completa exigida pelo Goal §6 e pelo Anexo A §6, contra um Swarm real, e falha se qualquer elo se romper.

## References
- `docs/goals/G01-create-implementation-pack.md` §6 (cadeia obrigatória do M01)
- `docs/annexes/A-implementation-roadmap.md` §6 (primeiro vertical slice), §7 (VS-1, VS-2)
- `docs/annexes/G-agent-oriented-development.md` §7 (primeiro vertical slice)
- `docs/annexes/D-test-strategy.md` §11 (jornadas E2E), §11.1 (regra de seletores)
- `docs/annexes/H-autonomous-development-loop.md` §9.2 (Milestone Report)

## Preconditions
`M01-20`, `M01-21` e `M01-22` done. Swarm Lab disponível.

## Scope
A jornada completa, em um teste executável:

```text
Authentication → Team → Project → Cluster → Environment → Service
   → Desired State → Operation → Swarm Executor → Docker Swarm Service
   → Actual State → 1/1 Healthy → Logs → Scale 1 → 3 → 3/3 Healthy
```

- Execução contra Swarm real provisionado por `bin/swarm-lab`.
- Verificação em **dois lados**: o que a UI mostra e o que o Docker realmente tem.
- Asserção explícita de que nenhuma etapa declarou sucesso antes da confirmação do runtime.
- Cleanup idempotente ao final, com namespaces únicos por execução.
- Um teste complementar de **isolamento**: um segundo Team não enxerga nem alcança nenhum recurso do primeiro.

## Out of Scope
- Build a partir de Git, domínio, TLS, secrets, multi-node — nenhum deles pertence ao slice (Anexo G §7.1).
- Testes de carga e chaos (M13).
- Rollback e promoção (M06).

## Application Layer
Nenhuma nova. Esta Story **não implementa capacidade**; ela prova a integração das anteriores. Se um passo exigir código novo, isso é sinal de que a Story correspondente está incompleta — a correção vai para lá, não para cá.

## Security Requirements
- O teste inclui a jornada negativa de tenancy: um usuário do Team B recebe negação em todas as rotas de mutação do Team A.
- Nenhum artefato do teste (screenshot, trace, log) contém valor sensível.
- O teste verifica que a API pública não alcança o Docker socket.

## Observability Requirements
O E2E coleta e arquiva como evidência: `operationId` de cada mutação, a timeline de cada Operation, e o estado observado do Swarm em cada marco. Essa evidência entra no `MILESTONE_REPORT.md`.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Um elo da cadeia quebra | O teste falha nomeando **qual** elo, não “E2E vermelho”. |
| Convergência demora além do limite | Falha com o estado observado no momento do timeout, para diagnóstico. |
| Swarm Lab indisponível | Falha explícita de setup, marcada como tal — **nunca** reportada como sucesso ou skip silencioso. |
| Recursos órfãos de execução anterior | Namespaces únicos evitam colisão; o cleanup roda mesmo após falha. |

## Acceptance Criteria
1. O E2E executa a jornada completa da seção Scope contra um **Swarm real** e passa.
2. Cada marco é verificado nos dois lados: UI/API **e** estado real do Docker.
3. O teste falha nomeando o elo específico que quebrou.
4. O teste comprova que nenhuma etapa declarou sucesso antes da confirmação do runtime.
5. O scale 1→3 é verificado até `3/3 Healthy` observado.
6. Os logs ao vivo são lidos com sucesso durante a jornada.
7. A jornada negativa de tenancy passa: Team B é negado em todas as mutações do Team A.
8. O teste verifica que a API pública não alcança o Docker socket.
9. Cleanup é idempotente e roda mesmo após falha; nenhum recurso órfão permanece no lab.
10. Swarm Lab indisponível produz falha explícita de setup, nunca skip silencioso.
11. A evidência coletada (operationIds, timelines, estado observado) é arquivada para o Milestone Report.
12. Os seletores usam roles/atributos semânticos/test IDs, nunca classes CSS.

## Required Tests
Esta Story **é** o teste. As classes envolvidas:
- **E2E**: a jornada completa e a jornada negativa de tenancy.
- **Docker/Swarm**: asserções diretas contra o runtime em cada marco.
- **security**: ausência de acesso ao socket pela API pública; artefatos sem valor sensível.

## Quality Gates
Todos os gates: Local, Pre-commit, Post-commit, `bin/fitness`, `bin/security`, suíte Docker/Swarm e E2E. Esta Story é a última antes do Exit Gate de M01.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, jornada completa verde contra Swarm real, evidência arquivada, Critical/High = 0, e o `MILESTONE_REPORT.md` de M01 pronto para aceitação humana.
