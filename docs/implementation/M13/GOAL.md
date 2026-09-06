---
milestone: "M13"
type: "autonomous-goal"
---

# M13 — Autonomous Goal

## Completion condition

M13 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. **Suíte RBAC/IDOR cross-team** verde: nenhuma leitura ou mutação indevida entre Teams e Environments.
3. **Suíte SSRF** verde, cobrindo **todas** as features que aceitam URL.
4. **Corpus adversarial de builder** verde: nenhuma fixture alcança socket, manager, Vault, metadata ou rede interna.
5. **Scanner de plaintext** verde: nenhum secret em log, erro, evento, audit ou telemetria.
6. **Suíte de concorrência** verde: fault injection determinística, sem “tentar várias vezes até acontecer”.
7. **Performance** aprovada: p95/p99, taxa de erro, saturação, queue depth e recovery dentro dos critérios; “não caiu” **não** é critério suficiente.
8. **Pisos de teste GA** do Anexo B §9.1 exercitados.
9. **Chaos** verde: node, manager/quorum, Traefik, DB, Registry, executor e deploy — com invariantes preservadas.
10. **Abuse controls** verdes: rate limits, quotas e backpressure.
11. **Upgrade N/N-1** verde, com as combinações suportadas declaradas.
12. **SLO** verde: thresholds automatizados e política de error budget verificada.
13. Relatórios arquivados com topologia, dataset, versão, parâmetros e resultado.
14. Critical = 0 e High = 0, ou waiver explícito com risco, dono, expiração e mitigação.
15. `MILESTONE_REPORT.md` gerado com `Status: READY_FOR_REVIEW`.

## Required proof

- relatórios de performance, chaos, security e upgrade, com metadata completa;
- topologia e dataset usados em cada suíte;
- lista de findings com severidade e disposição;
- waivers, quando houver, com expiração;
- um commit por Story.

## Constraints

- **M13 valida; não introduz controles de segurança.** Se um controle não existir, a correção vai para a Story de origem, não para cá.
- **Não é permitido enfraquecer teste, threshold, gate ou acceptance criterion** para obter verde.
- Testes destrutivos rodam apenas em ambientes dedicados; **nunca** em produção.
- Experimentos de chaos têm abort condition e blast radius definidos.
- Flaky test é **defeito**: quarentena com dono e prazo; retry não mascara.
- Falha intermitente em segurança, restore ou concorrência **bloqueia** o release até ser entendida.
- Resultado sem topologia, dataset e versão registrados **não** conta como evidência.
- Não implementar capacidade nova de produto.
- Pentest externo não é substituível por automação.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Laboratório indisponível → `BLOCKED_EXTERNAL_DEPENDENCY`; **não** marcar o Milestone como pronto sem as suítes. Finding Critical/High sem mitigação → `blocked` até correção na Story de origem ou waiver aprovado por humano. Uma fixture adversarial que **consiga** escapar é incidente de segurança: parar e escalar.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não iniciar M14 automaticamente**.

Scale Gate humano (Anexo A §11).

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
