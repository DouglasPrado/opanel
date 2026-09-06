---
milestone: "M08"
type: "autonomous-goal"
---

# M08 — Autonomous Goal

## Completion condition

M08 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Contract tests do `LoadBalancerProvider` verdes (add/remove/health de target, idempotência, erro de provider).
4. Suíte Docker/Swarm verde em cluster **multi-node**: join e remoção de worker; promote/demote preservando quorum; drain com evacuação.
5. **Teste de perda de manager** verde: em cluster de 3, matar um manager mantém `docker node ls` e as mutações funcionando.
6. **Teste de perda de ingress** verde: sob tráfego, matar um ingress faz o LB retirar o target e o tráfego continua pelos demais.
7. **Teste de kill de worker sob tráfego** verde: Tasks stateless reagendadas em nodes elegíveis.
8. **Teste de enrollment** verde: token expirado e token reutilizado são rejeitados; o bootstrap aborta antes do join.
9. **Teste de guardrail de quorum** verde: promote/demote/remove que comprometeria o quorum é bloqueado com o cálculo mostrado.
10. Teste de segurança verde: join token ausente de log/UI/AuditLog; portas do Swarm não públicas; 4789/UDP restrito; nenhuma porta 2375.
11. **Teste de distribuição de certificado com quorum real** verde: com um ingress fora, a versão **não** é ativada.
12. E2E verde: adicionar node pela UI até `READY`; manutenção guiada; `HA Ready` derivado corretamente.
13. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M08/review/`.
14. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- topologia usada nos testes (número de managers, workers, ingress);
- saída dos três testes de falha (manager, ingress, worker) com o comportamento observado;
- saída do teste de token expirado/reutilizado;
- cálculo de quorum exibido no bloqueio de promote/demote;
- prova de que `HA Ready` é falso em cluster single-node e verdadeiro na topologia PROD-HA;
- um commit por Story.

## Constraints

- **Nunca** expor a Docker API; nenhuma porta 2375.
- **Nunca** abrir 4789/UDP indiscriminadamente — VXLAN não autentica tráfego.
- **Nunca** registrar o join token do Swarm em log, UI ou AuditLog.
- **Nunca** remover um manager sem avaliar o efeito no quorum.
- **Nunca** declarar HA sem os checks de redundância verdes: “replicas > 1” não é HA.
- `force remove` apenas para node perdido, como operação privilegiada e auditada.
- Não implementar provisionamento automático por cloud provider, multi-cluster remoto nem OpenTofu.
- Não implementar métricas históricas (M09), backup do Swarm (M10) nem chaos sob carga (M13).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Hosts adicionais indisponíveis → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories multi-node; as de modelagem e UI continuam. Provider de LB indisponível → `BLOCKED_EXTERNAL_DEPENDENCY`; o modo `MANUAL` permite validar o restante. Perda de quorum durante teste → seguir RB-06; **nunca** usar `force-new-cluster` como troubleshooting.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M09 automaticamente**.

HA Gate humano (Anexo A §11, G4).

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
