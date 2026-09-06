# M03-12 — Vault UI: secrets, versions, usage and bindings

## Objective
Entregar a interface do Vault trabalhando com **versões e bindings**, não com valores — de modo que o caminho normal de uso nunca exponha plaintext.

## Outcome
A tela do Vault lista secrets com contagem de versões e quem as usa; a tela do Secret mostra o histórico de versões e o uso por Environment; a atualização de binding é uma ação deliberada.

## References
- `docs/architecture/10-ui-use-cases.md` §15 (Vault e Variables & Secrets), §15.1, §15.2, §15.4, §28 (secrets e clipboard)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §6 (Reuse Gate)
- `app/frontend/components/INVENTORY.md`

## Preconditions
`M03-08`, `M03-09` e `M03-11` done.

## Scope
- **Lista do Vault**: nome canônico, escopo, contagem de versões, última versão, quantos Services/Environments usam, e badge de atenção (nova versão não promovida, secret sem uso).
- **Detalhe do Secret**: histórico de versões com quem usa cada uma; ação “criar nova versão”; seção de uso por Environment.
- **Variables & Secrets do Service**: tabela unificada com key, origem, versão e modo de injeção.
- **Atualizar binding**: banner “nova versão disponível” com ação explícita.
- **Reveal**: diálogo separado com step-up, TTL e cópia com confirmação visual.
- Estados universais aplicados; paginação por cursor.

## Out of Scope
- Comparação completa entre Environments (`M06`, quando existir Release para comparar junto).
- Rotação da Recovery Key na UI (`M03-13` integra ao dashboard de segurança).
- Gestão de providers (`M11-12`).

## UI Impact
Consolida a regra de produto: **a UI trabalha com versões e bindings, não com plaintext** (doc 10 §15.2). O valor só aparece no fluxo explícito de reveal.

## Security Requirements
- Valores **não** aparecem em nenhuma listagem, detalhe, tooltip, título de elemento ou atributo de DOM.
- Nenhuma cópia automática para clipboard; a cópia exige ação e mostra confirmação visual (doc 10 §28).
- A comparação entre Environments mostra apenas a identidade da versão.
- A UI não oferece reveal a quem não tem a permissão — e o backend nega de qualquer forma.
- Nenhum valor sensível em shared props, em estado do cliente ou em cache do navegador.

## Observability Requirements
A UI mostra quando uma versão foi criada, por quem, e onde está em uso — para que a decisão de promover seja informada.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Secret sem uso | Badge de atenção; não apagar automaticamente. |
| Nova versão não promovida | Badge; ação explícita de atualizar binding. |
| Usuário sem permissão de reveal | A ação não aparece; o backend nega se forjada. |
| Muitas versões | Paginação por cursor. |
| Valor copiado | Confirmação visual explícita; sem cópia automática. |
| Falha ao carregar uso | Estado de erro com `requestId`; não mostrar “sem uso” quando o dado falhou. |

## Acceptance Criteria
1. A lista do Vault mostra nome, escopo, versões, uso e badges de atenção — **sem** valores.
2. O detalhe do Secret mostra histórico de versões e quem usa cada uma.
3. A tabela do Service mostra key, origem (variável ou Vault), versão e modo de injeção.
4. “Nova versão disponível” aparece como banner com ação explícita, sem alterar nada sozinho.
5. O reveal é um diálogo separado com step-up e TTL.
6. Nenhum valor aparece em listagem, tooltip, título ou atributo de DOM, provado por teste.
7. Não há cópia automática para clipboard; a cópia exige ação com confirmação visual.
8. A UI não oferece reveal sem permissão, e o backend nega requisição forjada.
9. Falha ao carregar o uso mostra estado de erro, nunca “sem uso” incorreto.
10. Listas usam paginação por cursor.
11. Nenhum componente novo foi criado onde o inventário resolvia; Reuse Gate documentado.
12. Acessibilidade AA verificada.

## Required Tests
- **unit (frontend)**: ausência de valor no DOM; banner de nova versão; estados de erro.
- **E2E**: criar secret → versão → binding → ver uso → promover; reveal com step-up; tentativa sem permissão.
- **security**: varredura do DOM por valor plantado; ausência de valor em shared props; **negativo cross-team**: um usuário de outro Team não vê a existência do Secret nem seus metadados em nenhuma prop.

## Quality Gates
Local Quality Gate classe React/TypeScript + Reuse Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, varredura de DOM verde, Reuse Gate documentado, Critical/High = 0.
