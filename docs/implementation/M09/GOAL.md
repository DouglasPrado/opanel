---
milestone: "M09"
type: "autonomous-goal"
---

# M09 — Autonomous Goal

## Completion condition

M09 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. **ADR do backend de observabilidade aceito** (SC-11), registrado em `docs/decisions/`.
3. Suítes unit, integration, request, policy e contract verdes.
4. Contract tests verdes: `MetricProvider`, `LogProvider`, `NotificationProvider`.
5. Suíte Docker/Swarm verde: logs sobrevivendo à substituição de Task; métricas após reinício de node; exec em Task real.
6. **Teste de deduplicação de alerta** verde: a mesma condição não notifica repetidamente a cada coleta.
7. **Teste de silenciamento** verde: mute exige expiração e volta a alertar depois.
8. **Teste de autoscaling em modo seguro** verde: sem métricas confiáveis, durante deployment incompleto ou sem capacidade, o autoscaler **não** escala.
9. **Teste de terminal** verde: `VIEWER` negado; produção exige step-up; sessão auditada com início, fim e alvo; nenhum acesso a shell do host.
10. Teste de redaction verde: nenhum secret em log, métrica, evento ou trace.
11. **E2E verde**: diagnosticar um Service degradado correlacionando status, logs, métricas e deployment — sem SSH.
12. E2E verde: criar alerta → disparar → incidente aberto → recuperação → incidente resolvido.
13. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M09/review/`.
14. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- ADR do backend aceito;
- saída do teste de deduplicação e de silenciamento;
- saída dos três cenários de modo seguro do autoscaler;
- registro de auditoria de uma sessão de terminal;
- demonstração do diagnóstico sem SSH;
- um commit por Story.

## Constraints

- **Terminal nunca dá acesso a shell do host** nem a container do Control Plane.
- `VIEWER` **nunca** recebe exec.
- Autoscaler **nunca** decide com métrica indisponível, durante deployment incompleto ou sem capacidade.
- Autoscaler **nunca** aumenta limite de memória após OOM sem política explícita.
- Silenciamento de alerta **sempre** exige expiração.
- Nenhum secret em log, métrica, evento ou trace.
- Métricas sem labels de alta cardinalidade nem valores sensíveis.
- Não implementar APM completo, tracing obrigatório nem autoscaling preditivo.
- Não implementar validação formal de SLO sob carga (M13).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Backend de observabilidade indisponível ou ADR não aceito → `BLOCKED_FOR_PRODUCT_DECISION` em `M09-03` e nas Stories dependentes; coletores e eventos continuam. Cluster multi-node indisponível → métricas de ingress redundante ficam parciais, registrado no report.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M10 automaticamente**.

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
