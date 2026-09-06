---
milestone: "M14"
name: "Production Readiness & Release Candidate"
type: "milestone"
status: "pending"
---

# M14 — Production Readiness & Release Candidate

## Identity

| Campo | Valor |
|---|---|
| **ID** | M14 |
| **Nome** | Production Readiness & Release Candidate |
| **Objetivo** | Executar o gate de Production Readiness como **checklist objetivo**, não como opinião — e produzir um Release Candidate com evidência arquivada. |
| **Resultado observável** | Um operador consegue instalar a plataforma do zero, operá-la pelos runbooks, atualizá-la, restaurá-la após desastre, e ler exatamente o que ela **não** faz. |

## Why

Um sistema pronto para produção não é o que passou nos testes. É o que **alguém que não o construiu** consegue instalar, operar, diagnosticar e recuperar — usando a documentação que existe, não a conversa que não aconteceu.

M14 é onde isso é verificado. O critério é objetivo por desenho: cada item do gate aponta para uma evidência, e um item sem evidência é um item reprovado.

Este Milestone também é onde as limitações conhecidas passam a existir por escrito. Uma limitação documentada é uma decisão; uma limitação descoberta em produção é um incidente.

## Scope

- Suíte E2E de aceitação cobrindo as jornadas críticas ponta a ponta.
- Instalação limpa e onboarding executados a partir da documentação, por quem não escreveu o código.
- Upgrade e rollback da plataforma exercitados em staging.
- Programa de exercício de runbooks: cada runbook do Anexo E executado e cronometrado.
- DR drill completo: reconstrução em infraestrutura nova com RPO/RTO medidos.
- Checklist de go-live de segurança do Anexo C §23.
- Gate de Production Readiness consolidado e automatizado onde possível.
- Conjunto de documentação de release: operação, arquitetura, API, MCP, segurança e limitações.
- Processo de release e empacotamento da evidência.
- Registro explícito de limitações conhecidas e waivers vigentes.

## Out of Scope

| Deixado para | O quê |
|---|---|
| Fora do produto | Pentest externo e auditoria independente — atividades humanas agendadas, não automatizáveis. |
| Pós-GA | Capacidades do backlog do `ROADMAP.md`; nenhuma feature nova entra em M14. |
| Humano | A decisão de ir para produção. M14 produz a evidência; a decisão é do gate humano. |

## Dependencies

- **Hard:** M13 (e, transitivamente, todos os anteriores).
- **Externas:** ambiente de staging equivalente à produção; laboratório de DR; um operador que não participou da implementação.

## User-visible Outcome

A plataforma passa a ter uma **superfície de entrega**: instalador, documentação, runbooks, notas de release e limitações declaradas. É o que separa “o código funciona” de “o produto existe”.

## Technical Outcome

- Release Candidate identificado por commit, com evidência completa arquivada.
- Todos os gates executados e registrados, com resultado e disposição.
- Waivers vigentes listados com risco, dono, mitigação e expiração.
- Nenhuma pergunta aberta sobre o que a plataforma faz e o que ela não faz.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Código | Apenas correções de findings; **nenhuma capacidade nova**. |
| CI | Pipeline de Release Candidate consolidando todos os gates. |
| Documentação | Conjunto completo de release. |
| Operação | Runbooks exercitados e corrigidos pelo próprio exercício. |

## Security

- Checklist de go-live do Anexo C §23 executado item a item, com evidência por item.
- Verificação final de que nenhuma credencial de produção existe no workspace.
- Confirmação de que os defaults são seguros: configuração ausente **não** abre acesso, expõe secret ou concede privilégio.
- Waivers de segurança, se existirem, são explícitos, temporais e aprovados por humano.

## Observability

- Painel de prontidão: cada item do gate com estado e link para a evidência.
- Pacote de evidência versionado junto ao Release Candidate.

## Testing

E2E de aceitação, exercícios operacionais e execução dos gates. Nenhuma suíte nova de unidade nasce aqui.

## Acceptance Criteria

1. A suíte E2E de aceitação cobre as jornadas críticas e está verde.
2. Instalação limpa é executada a partir da documentação por alguém que não escreveu o código.
3. Upgrade e rollback da plataforma são exercitados em staging com sucesso.
4. Todos os runbooks do Anexo E são executados, cronometrados e corrigidos.
5. O DR drill completo é executado com RPO e RTO medidos e dentro do alvo.
6. O checklist de go-live de segurança é executado item a item, com evidência.
7. O gate de Production Readiness é executado; nenhum item fica sem evidência.
8. A documentação de release está completa e verificada contra o comportamento real.
9. O processo de release produz um Release Candidate identificado por commit, com evidência empacotada.
10. As limitações conhecidas e os waivers vigentes estão declarados por escrito.
11. `Critical = 0` e `High = 0`, sem exceção não aprovada por humano.
12. Nenhuma capacidade nova de produto foi introduzida em M14.

## Exit Gate

- [ ] Stories `required` `done`; 12 Acceptance Criteria com evidência.
- [ ] E2E de aceitação verde.
- [ ] Instalação limpa, upgrade e DR drill demonstrados.
- [ ] Runbooks exercitados.
- [ ] Checklist de segurança completo.
- [ ] Documentação e limitações publicadas.
- [ ] Pacote de evidência do Release Candidate arquivado.
- [ ] Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`.

**Gate humano: Production Readiness / GA** (Anexo A §11). A decisão de ir para produção é humana e não é automatizável.
