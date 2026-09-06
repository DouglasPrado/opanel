---
milestone: "M01"
type: "autonomous-goal"
---

# M01 — Autonomous Goal

## Completion condition

M01 está `READY` quando **todas** as condições abaixo são verdadeiras e demonstradas no transcript com comando e exit code:

1. `ADR-0001` e `ADR-0002` estão com status `Accepted` em `docs/decisions/`.
2. Todas as Stories `required: true` de `docs/implementation/M01/tasks.json` estão `done`, cada uma com `commit` preenchido.
3. Nenhuma Story `required: true` está `blocked`.
4. `bin/pack validate` retorna exit code 0 para M01.
5. A suíte unit + integration + request + policy retorna exit code 0 contra **PostgreSQL real**.
6. A suíte de autorização, incluindo os negativos cross-team de **todas** as rotas de mutação, retorna exit code 0.
7. A suíte Docker/Swarm retorna exit code 0 contra um **Swarm real** provisionado por `bin/swarm-lab`.
8. O E2E do vertical slice retorna exit code 0 e cobre: login → Team → Project → Cluster → Environment → Service → `1/1 Healthy` → logs → scale 1→3 → `3/3 Healthy`.
9. `bin/fitness` retorna exit code 0, e AF-02, AF-06, AF-07 e AF-08 estão avaliando código real, não conjunto vazio.
10. `bin/gate post-commit` retorna exit code 0 para o último commit de cada Story.
11. `bin/security` retorna exit code 0.
12. Nenhum finding Critical ou High permanece aberto em `M01/review/`.
13. `docs/implementation/M01/MILESTONE_REPORT.md` foi gerado com a demonstração do slice e evidência por Acceptance Criterion do `README.md`.

## Required proof

- estado de `tasks.json` validado;
- comandos executados e exit codes registrados, por suíte;
- saída do teste de crash entre commit e publish do Outbox;
- saída do teste de concorrência de scale (serialização ou `SUPERSEDED`);
- saída do teste de fencing token rejeitando worker com lease expirado;
- prova de que a API pública não tem acesso ao `docker.sock` (AF-02 + teste de integração);
- resultado do review de cada Story;
- um commit por Story concluída.

## Constraints

- Não acessar Docker fora do Swarm Executor. Nenhum `docker run`; aplicações são **Swarm Services**.
- Não criar primitive `exec(command: string)` no executor.
- Não manter requisição HTTP aberta esperando convergência do runtime.
- Não gravar plaintext de secret em payload de Operation, log, evento ou AuditLog.
- Não implementar Story de M02..M14: sem restart, sem drift correction ativa, sem Vault, sem Traefik, sem build, sem Release/Deployment, sem multi-node, sem métricas, sem convites/MFA.
- Não alterar arquitetura fora dos documentos referenciados pelas Stories.
- Não desabilitar teste, lint, checker ou gate para obter verde.
- Não usar credencial de produção nem apontar o Swarm Executor para um Docker de produção.
- Não adicionar dependência sem Dependency Gate e justificativa no Story Report.

## Block policy

- 3 tentativas sem progresso na mesma falha → trocar de estratégia uma vez → `blocked` com diagnóstico reproduzível, seguindo para Story independente.
- `ADR-0002` não aceito → `M01-01` fica `BLOCKED_FOR_PRODUCT_DECISION`. **Todo o Milestone depende disso**; parar e reportar.
- `ADR-0001` não aceito → `M01-16` fica `BLOCKED_FOR_PRODUCT_DECISION`; Stories independentes continuam.
- Docker/Swarm indisponível → `BLOCKED_EXTERNAL_DEPENDENCY` nas Stories de runtime; as de domínio e UI continuam.
- Conflito com a arquitetura aprovada → `blocked` imediato + registro em `SPEC_CONFLICTS.md`; nunca redesenhar em silêncio.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M02 automaticamente**.

Aceitação da espinha dorsal é gate humano.

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
