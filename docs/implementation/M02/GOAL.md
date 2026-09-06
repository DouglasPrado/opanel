---
milestone: "M02"
type: "autonomous-goal"
---

# M02 — Autonomous Goal

## Completion condition

M02 está `READY` quando todas as condições forem verdadeiras e demonstradas com comando e exit code:

1. Todas as Stories `required: true` de `tasks.json` estão `done` com `commit`; nenhuma `required` está `blocked`.
2. `bin/pack validate` verde para M02.
3. Suítes unit, integration, request, policy e contract verdes.
4. Suíte Docker/Swarm verde contra Swarm real, incluindo: drift por alteração manual, deleção com limpeza, restart, health check e mudança de recursos.
5. **Teste de drift**: `docker service scale` manual é detectado e revertido por Platform Wins; `DriftRecord` persistido.
6. **Teste de reconcile sem eventos**: com o stream de Docker Events desligado, o sweep periódico ainda converge o recurso.
7. Teste de `Idempotency-Key` concorrente verde: uma única operação lógica.
8. Teste de cancelamento e de supersession verdes.
9. E2E de operações verde: restart, resources, scale-to-zero, deleção e drift revertido pela UI.
10. `bin/fitness` verde com AF-03 avaliando reconcilers reais.
11. `bin/security` verde.
12. Nenhum finding Critical/High aberto em `M02/review/`.
13. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- saída do teste de drift, mostrando o estado manual e a reversão;
- saída do teste de reconcile com eventos desligados;
- saída do teste de `Idempotency-Key` concorrente;
- prova de que a deleção não deixou recurso órfão no Swarm;
- evidência de que `AdoptRuntimeState` exige `INSTANCE_ADMIN` e é auditado;
- um commit por Story concluída.

## Constraints

- Não implementar Release, Deployment, rollback ou promoção (M06).
- Não implementar Vault, secrets ou step-up (M03).
- Não implementar Traefik, domínio ou TLS (M04).
- Não implementar drain/promote/demote/remoção de node (M08).
- Não implementar métricas, alertas, autoscaling ou terminal (M09).
- **Nunca** adotar estado de runtime automaticamente; adopt é operação humana explícita.
- Não usar Docker Events como ledger definitivo: a corretude vem de reler o estado.
- Não acessar Docker fora do Swarm Executor.
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → trocar de estratégia uma vez → `blocked` com diagnóstico reproduzível, seguindo para Story independente. Docker/Swarm indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de runtime. Conflito com a arquitetura → `blocked` + registro em `SPEC_CONFLICTS.md`.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M03 automaticamente**.

## Final Handoff

Quando todas as condições do Milestone estiverem satisfeitas:

1. marque todas as Stories obrigatórias como `done`;
2. execute todos os testes e Quality Gates finais;
3. gere `MILESTONE_REPORT.md`;
4. o relatório deve conter explicitamente:

   `Status: READY_FOR_REVIEW`

5. altere `review-state.json.status` de `implementing` ou `fixing` para `ready_for_review`;
6. não inicie o próximo Milestone;
7. encerre a execução.

O review independente posterior é responsabilidade exclusiva do Codex. Claude
não deve executar nem substituir o Codex Review e nunca pode declarar o estado
`accepted` ou `human_acceptance`.
