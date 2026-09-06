---
milestone: "M00"
type: "autonomous-goal"
---

# M00 — Autonomous Goal

## Completion condition

M00 está `READY` quando **todas** as condições abaixo são verdadeiras e demonstradas no transcript com comando e exit code:

1. Todas as Stories `required: true` de `docs/implementation/M00/tasks.json` estão `done`, cada uma com `commit` preenchido.
2. Nenhuma Story `required: true` está `blocked`.
3. Um clone limpo sobe com o comando único documentado em `README` e serve uma página Inertia renderizada.
4. `bin/gate local` retorna exit code 0.
5. `bin/gate pre-commit` retorna exit code 0 e comprovadamente **falha** em um caso negativo controlado.
6. `bin/gate post-commit` retorna exit code 0.
7. `bin/fitness` executa AF-01..AF-10, reporta cada uma individualmente e retorna exit code 0; existe um teste negativo por fitness function que prova que ela detecta a violação.
8. `bin/pack validate` valida os `tasks.json` dos 15 Milestones contra o schema e retorna exit code 0.
9. `bin/stop-gate` (Anexo H §4.2) executa e devolve `ok:true` no estado final, e `ok:false` com razão objetiva num caso negativo controlado.
10. `bin/swarm-lab up` seguido de `bin/swarm-lab down` executa duas vezes seguidas sem erro (idempotência).
11. A suíte de testes definida por cada Story termina com exit code 0.
12. Secret scan e dependency scan executam e retornam exit code 0.
13. `app/frontend/components/INVENTORY.md` existe e não está vazio.
14. Nenhum finding Critical ou High permanece aberto em `M00/review/`.
15. `docs/implementation/M00/MILESTONE_REPORT.md` foi gerado com evidências objetivas.

## Required proof

- estado de `tasks.json` validado por `bin/pack validate`;
- comandos executados e exit codes registrados no transcript;
- resultado dos gates local, pre-commit, post-commit, fitness e stop-gate;
- resultado do review de cada Story;
- um commit por Story concluída, identificável por hash.

## Constraints

- Não implementar nenhuma entidade ou regra do domínio Opanel. M00 é infraestrutura de engenharia.
- Não introduzir Next.js, HTMX ou qualquer frontend fora de Rails + Inertia + React/TypeScript.
- Não criar componentes React novos quando a biblioteca importada resolver (Anexo I §6.3).
- Não adicionar dependência sem passar pelo Dependency Gate (Anexo I §10.1) e registrar a justificativa no Story Report.
- Não desabilitar teste, lint, checker ou gate para obter verde.
- Não acessar `/var/run/docker.sock` fora de `bin/swarm-lab` e do harness de teste; nenhum código de aplicação toca Docker em M00.
- Não usar credencial de produção; nenhuma deve existir no workspace.
- Não criar abstração especulativa: sem generic repository, sem event bus, sem plugin system.

## Block policy

- Após **3 tentativas sem progresso** na mesma falha, mudar de estratégia uma vez; se ainda assim não progredir, marcar a Story `blocked` com diagnóstico reproduzível e seguir para uma Story independente.
- `M00-05` sem acesso à biblioteca de componentes → `BLOCKED_EXTERNAL_DEPENDENCY`. Não substituir por um design system novo.
- Conflito com a arquitetura aprovada → `blocked` imediatamente e registro em `SPEC_CONFLICTS.md`; nunca redesenhar em silêncio.
- Necessidade de ação destrutiva ou de infraestrutura real → `BLOCKED_FOR_HUMAN_APPROVAL`.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M01 automaticamente**.

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
