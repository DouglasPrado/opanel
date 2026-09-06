# M14-07 — Release documentation set

## Objective

Publicar a documentação que um operador, um desenvolvedor e um integrador precisam — verificada contra o comportamento real, não contra a intenção original.

## Outcome

Documentação que descreve o sistema que existe.

## References

- `docs/MASTER.md` — mapa da especificação
- `docs/annexes/E-operational-runbooks.md`
- `docs/annexes/F-mcp-platform-agents.md`

## Preconditions

- `M14-02` e `M14-04` concluídas: instalação e runbooks já corrigidos pelo exercício.

## Scope

Conjunto mínimo, cada peça com dono e verificação:

- **Operação**: instalação, configuração, upgrade, backup/restore, DR, runbooks e índice por sintoma.
- **Arquitetura**: visão do sistema, Desired/Actual State, Operations, reconciliação e boundaries — resumo navegável apontando para a especificação, sem duplicá-la.
- **API pública**: contrato, autenticação, idempotência, paginação, erros e versionamento.
- **MCP**: ferramentas, scopes, boundaries, approvals e o que um agente não pode fazer.
- **Segurança**: modelo de ameaça resumido, responsabilidades do operador, custódia da Recovery Key e o que a plataforma **não** protege.
- **Notas de release**: o que mudou, o que quebrou, o que exige ação do operador.

Regras:

- Todo exemplo executável é **testado**; exemplo que não roda é defeito.
- Toda afirmação de comportamento aponta para o teste que a sustenta ou é removida.
- A documentação não duplica a especificação aprovada; ela referencia.
- Divergência encontrada entre documentação e comportamento vira conflito registrado, nunca reescrita silenciosa da especificação.

## Out of Scope

- Material de marketing.
- Reescrever `docs/architecture/**`: fora do boundary; divergência é registrada em `SPEC_CONFLICTS.md`.

## Security Requirements

- Nenhum exemplo contém credencial real, mesmo desativada.
- A documentação de segurança declara explicitamente o que está fora do modelo de ameaça.
- Exemplos de MCP não induzem a conceder scope amplo por conveniência.

## Observability Requirements

- Índice com dono e data da última verificação por peça.
- Lista das afirmações verificadas por teste automatizado.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Exemplo não roda | Defeito; corrigido ou removido. |
| Documentação descreve comportamento inexistente | Finding **High**. |
| Documentação contradiz a especificação | Conflito registrado; não resolver silenciosamente. |
| Credencial em exemplo | Finding **Critical**. |

## Acceptance Criteria

1. As seis peças do conjunto estão publicadas, com dono.
2. Todo exemplo executável é testado e roda.
3. Toda afirmação de comportamento é sustentada por teste ou removida.
4. A documentação referencia a especificação em vez de duplicá-la.
5. Divergências viram conflito registrado, não reescrita.
6. Nenhum exemplo contém credencial.
7. O que está fora do modelo de ameaça é declarado.
8. As notas de release declaram mudanças, quebras e ações do operador.
9. O índice registra a data da última verificação de cada peça.

## Required Tests

- Execução automatizada dos exemplos da documentação.
- Verificação de links e referências.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Exemplos verdes.
- [ ] Self-review; `tasks.json` atualizado com commit.
