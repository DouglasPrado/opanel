# M00-18 — ADR, Story Report and Milestone Report templates

## Objective
Padronizar os artefatos de decisão e de evidência que o Anexo G §22, o Anexo H §9.2 e o Anexo I §23 exigem, para que rastreabilidade não dependa da forma como cada sessão decide escrever.

## Outcome
Existem templates versionados de ADR, Story Report, Milestone Report, Dependency Justification e Review Findings, referenciados pelos gates e pelo Implementation Pack.

## References
- `docs/annexes/G-agent-oriented-development.md` §20 (ADR durante a construção), §22 (padrão de relatório)
- `docs/annexes/H-autonomous-development-loop.md` §9.2 (Milestone Report), §5.3 (artefatos persistentes)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §23 (templates operacionais), §17.2 (severidades)
- `docs/decisions/README.md`

## Preconditions
Nenhuma. Pode ser executada em paralelo com qualquer Story de M00.

## Scope
- **Template de ADR**: Status, Context, Decision, Consequences, Alternatives considered, Affected docs, Affected modules. Numeração sequencial e regra de quando criar (Anexo G §20.1).
- **Template de Story Report**: resultado, arquivos alterados, schema/API/eventos, decisões locais, testes executados com comando e resultado, acceptance criteria mapeados, dependências novas justificadas, pendências e conflitos.
- **Template de Milestone Report**: contagem de Stories, blocked, commits, resultado por classe de teste, findings por severidade, demonstração do resultado funcional, e o que o humano precisa aceitar.
- **Template de Dependency Justification** (Anexo I §23.3).
- **Template de Review Findings**: dimensão, severidade Critical/High/Medium/Low, evidência, ação.
- **Template de Blocker**: Story, qualificador de bloqueio, diagnóstico reproduzível, o que destravaria.
- Documento curto de convenção de commits (Anexo I §13.1) com exemplos bons e ruins.

## Out of Scope
- Escrever ADRs de conteúdo — `ADR-0001` e `ADR-0002` já existem e são decisões, não templates.
- Documentação de usuário final (M14).
- Automatizar a geração dos relatórios — os templates são consumidos pelo agente; automação só se houver Story própria.

## Security Requirements
Os templates instruem explicitamente que **nenhum** relatório, review ou evidência pode conter secret plaintext, token, chave privada, Recovery Key ou credencial de provider (Anexo C §17). O template de evidência inclui um lembrete de redaction antes do arquivamento.

## Observability Requirements
O template de Story Report exige comando executado + resultado, não apenas “testes passaram”. O de Milestone Report exige evidência objetiva por critério, não afirmação.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Story Report sem comandos executados | Post-commit Gate reprova pelo item “acceptance mapping”. |
| Milestone Report sem evidência | Stop Gate reprova pelo check “milestone report exists” estendido a “report completo”. |
| ADR criado depois do padrão já estar implícito no código | Review classifica como finding: o Anexo G §20 exige o ADR **antes** de virar padrão. |
| Relatório com valor sensível | Secret scan sobre os artefatos reprova. |

## Acceptance Criteria
1. Existe template de ADR com as sete seções exigidas e regra documentada de quando criar.
2. Existe template de Story Report cobrindo os itens do Anexo G §22.
3. Existe template de Milestone Report cobrindo os itens do Anexo H §9.2.
4. Existe template de Dependency Justification conforme Anexo I §23.3.
5. Existe template de Review Findings com as quatro severidades e a política de bloqueio de cada uma.
6. Existe template de Blocker com os três qualificadores válidos.
7. Existe documento de convenção de commits com exemplos bons e ruins.
8. Todos os templates declaram a proibição de conteúdo sensível.
9. O Post-commit Gate e o Stop Gate referenciam os templates por caminho estável.
10. O secret scan cobre o diretório de relatórios e evidências.

## Required Tests
- **unit**: verificação de que cada template contém as seções obrigatórias (falha se uma seção for removida).
- **integration**: secret scan cobrindo diretórios de report/evidence.

## Quality Gates
Local Quality Gate. Os templates passam a ser exigidos pelo Post-commit Gate a partir da próxima Story.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, templates referenciados pelos gates por caminho estável, secret scan cobrindo relatórios, Critical/High = 0.
