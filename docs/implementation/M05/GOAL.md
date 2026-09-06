---
milestone: "M05"
type: "autonomous-goal"
---

# M05 — Autonomous Goal

## Completion condition

M05 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. Suítes unit, integration, request, policy e contract verdes.
3. Contract tests verdes: GitHub (webhook signature, commit resolution, credential lifecycle) e Registry (push/pull/manifest/digest/auth/not found/rate limit).
4. **Corpus de builds** verde: Railpack em stack suportado, Dockerfile explícito, monorepo, build pesado, build que falha, timeout e cancelamento.
5. **Corpus adversarial verde**: fixtures maliciosas **não** conseguem alcançar docker.sock do cluster, rede de manager, Vault de runtime, cloud metadata nem ranges internos.
6. Teste de webhook verde: assinatura inválida rejeitada antes de qualquer ação; replay bloqueado; delivery duplicado deduplicado; payload gigante rejeitado.
7. Teste de **build secret** verde: o valor não persiste na imagem, em layer, em stdout/stderr, em metadata do BuildKit nem em log.
8. Teste de token de curta duração verde: o token não aparece em build log, deployment log nem no frontend.
9. Teste de limites verde: CPU, memória, disco e tempo aplicados; build excedido é morto e o workspace é limpo.
10. Teste de cache verde: hit/miss com resultado funcional idêntico e métricas registradas.
11. **E2E verde**: repositório privado → build → `Artifact` com digest visível na UI, **sem** alterar o Service.
12. `bin/fitness` e `bin/security` verdes; Critical/High = 0 em `M05/review/`.
13. `MILESTONE_REPORT.md` gerado com evidência por Acceptance Criterion.

## Required proof

- saída completa do corpus adversarial, nomeando cada tentativa e o bloqueio correspondente;
- prova de que o builder não tem docker.sock do cluster;
- digest do artefato produzido e a cadeia provider → repo → commit → build → artifact;
- saída dos testes de webhook (4 casos);
- prova de ausência do build secret na imagem final;
- um commit por Story.

## Constraints

- **Builder é código não confiável.** Nunca conceder docker.sock do cluster, Vault de runtime, credencial administrativa ou acesso a manager.
- **Builds não rodam em Manager nodes** quando existe builder dedicado.
- Egress do builder limitado por policy; metadata, loopback, link-local e RFC1918/ULA bloqueados.
- Build secret **nunca** vira ENV permanente da imagem.
- Assinatura de webhook verificada **antes de qualquer ação**.
- Artifact identificado por digest; tag é alias.
- **Não implantar nada**: `Release`, `Deployment`, rollout, rollback e promoção são de M06. Build falho não pode alterar o Service.
- Não implementar scanning bloqueador de vulnerabilidade (M13) nem quotas por Team (M11).
- Não desabilitar teste, checker ou gate.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. GitHub App não registrado → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de source; build por Dockerfile local em laboratório continua possível. Registry indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de publicação. Qualquer fixture adversarial que **consiga** escapar → parar imediatamente, marcar `blocked` como incidente de segurança e escalar para revisão humana; **não** contornar o teste.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M06 automaticamente**.

Revisão de segurança humana do build plane (T03 é CRITICAL).

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
