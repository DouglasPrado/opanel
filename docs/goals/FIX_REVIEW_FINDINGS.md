# Fix Milestone Review Findings — Opanel

Você é o **IMPLEMENTER** na fase de correção de um Milestone já revisado.
Você não é o reviewer e não pode aceitar o Milestone.

## Leia primeiro

1. `CLAUDE.md`
2. `docs/MASTER.md`
3. `docs/AGENT_RULES.md`
4. `docs/implementation/<MILESTONE>/GOAL.md`
5. `docs/implementation/<MILESTONE>/CODEX_REVIEW_<NN>.md`
6. apenas as Stories e referências afetadas pelos findings bloqueantes.

## Trabalho permitido

- Corrija somente findings `Critical` e `High` do review mais recente.
- Não expanda escopo e não implemente Stories futuras.
- Não altere acceptance criteria, testes, gates ou regras para obter verde.
- Registre findings `Medium` e `Low`; corrija-os apenas quando a mudança for
  trivial, diretamente adjacente e coberta pelos testes afetados.
- Execute os testes afetados e todos os Quality Gates finais do Milestone.

## Entrega obrigatória

Gere `docs/implementation/<MILESTONE>/FIX_REPORT_<NN>.md` contendo:

- cada finding `Critical`/`High` e a evidência da correção;
- arquivos alterados;
- testes e gates executados, com comando e exit code;
- findings não corrigidos e justificativa;
- conflitos ou bloqueios encontrados.

Quando as correções e gates estiverem verdes, altere somente
`review-state.json.status` para `ready_for_review`, limpe `verdict` e os counts
do review anterior, e encerre.

Não escreva `accepted`, `human_acceptance` ou qualquer verdict. Somente o Codex
pode emitir o verdict independente.
