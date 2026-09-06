---
milestone: "M14"
type: "autonomous-goal"
---

# M14 — Autonomous Goal

## Completion condition

M14 está `READY` quando, com comando e exit code demonstrados:

1. Stories `required: true` `done` com `commit`; nenhuma `required` `blocked`; `bin/pack validate` verde.
2. **E2E de aceitação** verde, cobrindo todas as jornadas críticas declaradas.
3. **Instalação limpa** executada a partir da documentação, por um operador que não escreveu o código, com o tempo e os obstáculos registrados.
4. **Upgrade e rollback** da plataforma exercitados em staging, com evidência.
5. **Runbooks** do Anexo E executados, cronometrados e corrigidos onde falharam.
6. **DR drill completo** com RPO e RTO medidos e dentro do alvo.
7. **Checklist de go-live** do Anexo C §23 completo, com evidência por item.
8. **Gate de Production Readiness** executado; nenhum item sem evidência.
9. **Documentação de release** completa e verificada contra o comportamento real.
10. **Release Candidate** identificado por commit, com pacote de evidência arquivado.
11. **Limitações conhecidas e waivers** declarados, com risco, dono, mitigação e expiração.
12. Critical = 0 e High = 0.
13. `MILESTONE_REPORT.md` gerado com `Status: READY_FOR_REVIEW`.

## Required proof

- pacote de evidência do Release Candidate, indexado por item de gate;
- registro do exercício de instalação, com quem executou e o que travou;
- relatórios de upgrade, DR drill e runbooks, com tempos medidos;
- checklist de segurança preenchido com referência à evidência;
- lista de limitações e waivers vigentes;
- um commit por Story.

## Constraints

- **Nenhuma capacidade nova de produto.** M14 fecha; não expande.
- **Um item de gate sem evidência é um item reprovado.** Não existe “provavelmente ok”.
- Documentação que descreve comportamento não verificado é finding, não documentação.
- Runbook que falhou no exercício é corrigido; um runbook que “só funciona com quem escreveu” não conta.
- DR drill roda em infraestrutura **nova**, não na existente.
- Nenhuma credencial de produção no workspace, em nenhum momento.
- Pentest externo não é substituível por automação nem declarado como feito.
- **A decisão de ir para produção é humana.** O agente produz evidência e para.

## Block policy

3 tentativas sem progresso → mudar estratégia uma vez → `blocked`. Ambiente de staging ou laboratório de DR indisponível → `BLOCKED_EXTERNAL_DEPENDENCY`. Operador independente indisponível para o exercício de instalação → `BLOCKED_FOR_HUMAN_APPROVAL`; **não** substituir por auto-execução de quem implementou. Finding Critical/High → `blocked` até correção na Story de origem.

## End state

Para o implementer: `READY_FOR_REVIEW`, `BLOCKED` ou `FAILED`. Nunca abandonar trabalho silenciosamente. Ao atingir `READY_FOR_REVIEW`, gerar `MILESTONE_REPORT.md`, atualizar `review-state.json` e devolver o controle ao orquestrador — **não declarar GA nem promover o Release Candidate automaticamente**.

Production Readiness / GA é decisão humana e não é automatizável.

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
