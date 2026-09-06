# M00-11 — CI pipeline with PR and Merge gates

## Objective
Tornar o CI a **autoridade de qualidade** do repositório, implementando os gates de PR e Merge do Anexo I §15 e a cadência do Anexo D §20.

## Outcome
Um PR com typecheck, lint, teste ou secret scan vermelho não pode ser mergeado. Os jobs têm nomes estáveis, referenciados nominalmente pelo Merge Gate.

## References
- `docs/annexes/D-test-strategy.md` §20 (pipeline e gates), §20.1 (política de flaky)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §15 (PR e Merge Gate)
- `docs/annexes/G-agent-oriented-development.md` §14 (“o CI é a autoridade”)

## Preconditions
`M00-07`, `M00-08`, `M00-09` e `M00-10` done.

## Scope
- Pipeline com jobs nomeados e estáveis: `static`, `unit`, `integration`, `contract`, `security-fast`, `frontend`, `e2e-critical`, `migrations`.
- Banco efêmero por job de integração; seed determinístico; paralelização.
- Cadência: PR roda static + unit + integration + contract + security rápido; merge adiciona Docker/Swarm smoke e E2E críticas; nightly roda a suíte ampla (definida agora, populada pelos Milestones seguintes).
- Merge Gate expresso como checklist verificável do Anexo I §15.2.
- Artefatos de evidência arquivados por execução: relatórios de teste, segurança e cobertura de gate.
- Medição de flaky rate e lista de top offenders.

## Out of Scope
- Deploy da própria plataforma (M14).
- Performance, chaos e security pesada (M13); os *slots* nightly/RC são criados aqui, mas ficam vazios.

## Security Requirements
- Nenhum segredo de produção no CI. Credenciais do CI são de escopo mínimo e rotacionáveis.
- Logs do CI passam por redaction; um valor mascarado não pode reaparecer em artefato arquivado.
- O agente autônomo **não** pode alterar a definição do pipeline para destravar Story (Anexo I §21.2); mudança de gate exige Story/ADR próprio.

## Observability Requirements
Cada execução registra commit, branch, duração por job, resultado e link para artefatos — a base do “Release evidence” do Anexo D §24.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Job intermitente | Entra em quarentena com dono e prazo; o retry de infraestrutura é distinguível do retry de assertion. |
| Job de integração sem banco | Falha explícita de setup, não teste vermelho enganoso. |
| Alguém tenta mergear com job vermelho | Merge Gate bloqueia por nome de job, não por “maioria verde”. |
| Pipeline muito lento | Paralelização e escopo por diff antes de remover verificação. |

## Acceptance Criteria
1. O pipeline executa todos os jobs nomeados e cada um reporta resultado individualmente.
2. Um PR com typecheck vermelho é bloqueado.
3. Um PR com lint vermelho é bloqueado.
4. Um PR com teste vermelho é bloqueado.
5. Um PR com secret detectado é bloqueado.
6. Um PR com migration inválida é bloqueado.
7. Os jobs de integração usam banco efêmero próprio e podem rodar em paralelo sem colisão.
8. O Merge Gate exige explicitamente: base atualizada, CI verde, Critical = 0, High = 0, rollout de migration seguro, rollback/forward-fix conhecido, status de Story consistente, documentação/ADR atualizada quando contrato mudou.
9. Artefatos de evidência são arquivados por execução e recuperáveis.
10. Existe métrica de flaky rate e lista de top offenders.
11. Uma alteração no pipeline exige revisão explícita e não pode ser feita como efeito colateral de outra Story.

## Required Tests
- **integration**: execução completa do pipeline em branch de teste, verde.
- **negativo**: cinco PRs de teste, um por classe de falha (2–6), cada um comprovadamente bloqueado.

## Quality Gates
Esta Story **implementa** o PR Gate e o Merge Gate. A partir daqui, nenhuma Story pode ser declarada `done` sem CI verde.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, os cinco casos negativos comprovados, evidência arquivada, Critical/High = 0.
