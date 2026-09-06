/goal Execute integralmente docs/implementation/M00/GOAL.md.

Leia primeiro CLAUDE.md, docs/MASTER.md, docs/AGENT_RULES.md,
docs/implementation/M00/README.md e tasks.json.

Execute as Stories respeitando dependências e critérios de aceite.
Atualize tasks.json conforme progride.
Rode testes e quality gates após cada checkpoint.
Corrija todos os findings Critical e High.

Continue até que todas as condições de conclusão definidas no GOAL.md
estejam satisfeitas.

Gere MILESTONE_REPORT.md com `Status: READY_FOR_REVIEW`, altere
docs/implementation/M00/review-state.json para `ready_for_review` e encerre.

Não declare o Milestone accepted ou pronto para aceitação humana. Esses estados
dependem do review independente do Codex.
Não inicie M01.
