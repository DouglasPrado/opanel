# M00-13 — Architecture fitness functions AF-01..AF-10

## Objective
Transformar os invariantes arquiteturais do Anexo I §16.2 em checks executáveis, para que centenas de Stories autônomas não corroam os boundaries ao longo do tempo.

## Outcome
`bin/fitness` executa AF-01..AF-10, reporta cada uma individualmente e falha o CI em violação. Cada função tem um teste negativo que prova que ela **detecta** a violação.

## References
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16 (fitness functions e waivers)
- `docs/AGENT_RULES.md` — “Architecture Invariants”, “Quality Gates”
- `docs/architecture/07-internal-control-plane.md` §21 (segurança interna)
- `docs/annexes/C-threat-model-security-hardening.md` §8 (docker socket e executor)

## Preconditions
`M00-07` done.

## Scope
As dez funções do Anexo I §16.2, implementadas de forma que funcionem **desde já**, mesmo quando o alvo ainda não existe (uma regra sobre um conjunto vazio passa vacuamente, mas o checker precisa existir e ser testado):

| ID | Regra verificada |
|---|---|
| AF-01 | Controllers públicos não importam cliente Docker/socket adapter. |
| AF-02 | Somente o módulo Swarm Executor referencia `docker.sock` ou cliente Docker privilegiado. |
| AF-03 | Reconcilers não escrevem colunas de Desired State definidas como intenção do usuário. |
| AF-04 | A árvore React não importa código server-only (banco, Docker, infraestrutura). |
| AF-05 | O adapter MCP não chama o Swarm Executor diretamente; passa pela Application Layer. |
| AF-06 | Secret plaintext não aparece em serializers, logs ou payloads de audit. |
| AF-07 | Mutações críticas possuem caminho de autorização server-side (Policy). |
| AF-08 | Events e Operations carregam identificadores de correlação. |
| AF-09 | Migrations destrutivas conhecidas exigem marcador de fase contract ou ADR. |
| AF-10 | Feature React não duplica primitive existente sem waiver. |

Também no escopo:
- Registro de waiver por função: motivo, dono, prazo e Story de remoção; waiver sem prazo é reprovado; waiver expirado volta a bloquear.
- Metadados declarativos que as funções consomem: lista de colunas de intenção do usuário (AF-03), lista de mutações críticas (AF-07), inventário de componentes de `M00-05` (AF-10).

## Out of Scope
- Novas fitness functions além de AF-01..AF-10 — o Anexo I §16.1 prevê crescimento, mas por Story própria quando o invariante existir.
- Substituir testes de segurança (M13) ou o Reviewer Agent.

## Security Requirements
AF-02, AF-06 e AF-07 são controles de segurança executáveis, não apenas verificações de estilo:
- AF-02 protege o invariante Tier-0 do Anexo C §8. Ela deve rodar mesmo antes de existir um executor, para que o **primeiro** código que tocar Docker fora do boundary seja pego.
- AF-06 é a última linha automatizada contra vazamento de secret; ela verifica serializers, formatadores de log e construtores de payload de audit.
- Nenhuma dessas três pode receber waiver sem aprovação humana registrada.

## Observability Requirements
`bin/fitness` reporta por função: ID, resultado, arquivos violadores e regra textual. O relatório é arquivado como evidência de release.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Função passa vacuamente para sempre | O teste negativo obrigatório impede isso: ele planta a violação e exige que a função detecte. |
| Agente edita o checker para passar | Proibido pelo Anexo I §21.2. O post-commit compara o diff com a lista de arquivos de gate e reprova alteração não justificada. |
| Waiver eterno | Waiver exige prazo; expirado, volta a bloquear. |
| Falso positivo bloqueando trabalho legítimo | Ajuste da regra por Story própria, com teste; nunca supressão silenciosa. |

## Acceptance Criteria
1. `bin/fitness` executa AF-01..AF-10 e reporta cada uma individualmente.
2. Existe um teste negativo por função que planta a violação e prova que a função a detecta.
3. AF-02 detecta referência a Docker fora de `app/executors/`, provado por caso negativo.
4. AF-06 detecta um valor sensível alcançando serializer, log ou payload de audit, provado por caso negativo.
5. Waiver exige motivo, dono, prazo e Story de remoção; waiver sem prazo é reprovado.
6. Waiver expirado volta a bloquear, provado com relógio controlado.
7. AF-02, AF-06 e AF-07 não aceitam waiver sem aprovação humana registrada.
8. `bin/fitness` integra o PR Gate e o Post-commit Gate.
9. Alteração em qualquer checker é detectada pelo post-commit e exige justificativa explícita.
10. O relatório de fitness é arquivado como evidência.

## Required Tests
- **unit**: dez testes negativos, um por função.
- **integration**: `bin/fitness` no CI; waiver expirado voltando a bloquear; detecção de alteração em checker.

## Quality Gates
Integra PR Gate, Merge Gate e Post-commit Gate a partir desta Story.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, dez testes negativos verdes, política de waiver testada, Critical/High = 0.
