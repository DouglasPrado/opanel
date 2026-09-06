---
milestone: "M06"
type: "autonomous-goal"
---

# M06 — Autonomous Goal

## Completion condition

M06 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Suíte Docker/Swarm verde: rolling update com múltiplas réplicas; health falhando durante rollout; rollback automático e manual.
4. **Teste de ausência de falso sucesso** verde: Docker aceita o update, as Tasks não ficam saudáveis, e o Deployment **não** vira `HEALTHY`.
5. **Teste de watchdog** verde: um deployment travado é marcado `STALLED`, nunca fica indefinidamente em `DEPLOYING`.
6. **Teste de rollback** verde, sem rebuild, com tempo medido.
7. **Teste de promoção** verde: o digest em produção é **byte a byte o mesmo** do artefato promovido de homologação.
8. Teste de supersession verde: dois deploys rápidos, o mais novo vence, o anterior fica `SUPERSEDED`.
9. Teste de restart do Control Plane durante o rollout verde: intenção preservada, sem efeito duplicado.
10. Teste de webhook duplicado e fora de ordem verde; `watchPaths` evitando deploy desnecessário.
11. Teste de retenção verde: Artifact referenciado não pode ser coletado.
12. **E2E verde**: `git push` → build → deploy → `HEALTHY`.
13. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M06/review/`.
14. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- digest do artefato em homologação e em produção, provando que são idênticos;
- saída do teste de health falhando sem falso sucesso;
- tempo medido do rollback;
- saída do teste de restart do Control Plane no meio do rollout;
- timeline de um deployment completo com duração por etapa;
- um commit por Story.

## Constraints

- **Promoção nunca rebuilda.** Rebuildar quebra a cadeia de evidência e é finding Critical.
- Deploy sempre por **digest**; nunca por tag mutável.
- `Release` nunca carrega plaintext de secret — apenas `SecretVersion` IDs.
- Nenhuma requisição HTTP fica aberta durante o rollout.
- Docker aceitar o update **não** é sucesso; a confirmação vem do health.
- Não implementar canary, blue-green nem traffic splitting.
- Não implementar métricas/alertas/autoscaling (M09), snapshots (M10) nem tools MCP (M12).
- Não acessar Docker fora do Swarm Executor.
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Registry indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories que precisam de pull. Se a promoção produzir digest diferente do artefato de origem, **parar**: é violação da invariante central do Milestone, não um bug de ajuste.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M07 automaticamente**.

Delivery Gate humano (Anexo A §11).

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
