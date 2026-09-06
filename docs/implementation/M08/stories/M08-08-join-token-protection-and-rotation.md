# M08-08 — Swarm join token protection and rotation

## Objective
Tratar os join tokens do Swarm como segredo operacional: nunca exibidos, nunca logados, e rotacionáveis após suspeita de vazamento.

## Outcome
Os join tokens de worker e de manager existem apenas dentro do boundary autorizado; a rotação é uma operação disponível e não expulsa os nodes já existentes.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §6.3 (join token do Swarm)
- `docs/architecture/04-identity-teams-security.md` §14.2 (nunca persistir join token em logs ou audit; permitir rotação)
- `docs/annexes/C-threat-model-security-hardening.md` §8.1 (join tokens como segredo operacional, rotacionáveis após incidente)
- `docs/annexes/E-operational-runbooks.md` RB-20, RB-21

## Preconditions
`M08-01` done.

## Scope
- Obtenção dos join tokens apenas pelo Swarm Executor, sob demanda, durante o enrollment.
- **Nunca** persistir o join token; **nunca** exibi-lo na UI; **nunca** registrá-lo em log ou AuditLog.
- Token de **manager** com proteção adicional: só é obtido no fluxo de enrollment de manager, que já exige privilégio elevado.
- Rotação dos join tokens por role, disponível como operação privilegiada.
- Regra: rotacionar **não** expulsa os nodes já existentes (doc 06 §6.3).
- Integração com RB-21: após suspeita de comprometimento de manager, rotacionar join tokens faz parte da resposta.

## Out of Scope
- Autolock do Swarm (Anexo C §8; registrado como evolução).
- Rotação de credenciais de provider (`M11`, RB-20).
- Recuperação de cluster comprometido (RB-21, operacional).

## Application Layer
- **Commands:** `RotateJoinToken`.
- **Executor:** obtenção do token sob demanda, sem persistência.

## Security Requirements
- O join token permite entrada no cluster enquanto for válido: é um segredo de alto impacto.
- **Nunca persistido, nunca exibido, nunca logado** (doc 04 §14.2, regra explícita) — verificado com valor plantado no scanner de `M03-10`.
- O token de manager permite entrar como manager: privilégio de control plane. Ele é tratado com proteção adicional.
- A rotação é privilegiada (`INSTANCE_ADMIN` + step-up) e auditada.
- A rotação invalida tokens antigos para **novos** joins, sem afetar nodes já membros.
- A operação está documentada como parte da resposta a incidente (RB-21).

## Observability Requirements
AuditLog de rotação com actor, role e timestamp — sem o token. Métrica de rotações.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Token aparecendo em log | Impossível: scanner com valor plantado; se ocorrer, é finding Critical. |
| Rotação durante enrollment em andamento | O enrollment em curso falha e precisa de novo token de plataforma; comportamento documentado. |
| Rotação falha no meio | Estado consistente; o token anterior continua válido até a rotação concluir. |
| Suspeita de vazamento | Rotacionar por role; nodes existentes permanecem. |
| Tentativa de obter o token pela API pública | Não existe endpoint que o retorne. |

## Acceptance Criteria
1. Os join tokens são obtidos apenas pelo Executor, sob demanda, e **não** são persistidos.
2. O join token nunca aparece em log, UI, AuditLog ou métrica, provado com valor plantado.
3. **Nenhum endpoint da API retorna o join token**, provado por varredura de rotas.
4. O token de manager só é obtido no fluxo de enrollment de manager, que exige privilégio elevado.
5. A rotação por role está disponível como operação privilegiada.
6. A rotação exige `INSTANCE_ADMIN` + step-up e é auditada.
7. Rotacionar **não** expulsa nodes já existentes, provado contra cluster real.
8. Rotação durante enrollment em andamento tem comportamento documentado e determinístico.
9. Rotação que falha no meio deixa o estado consistente.
10. A operação está referenciada no procedimento de resposta a incidente.

## Required Tests
- **security**: varredura de rotas comprovando que nenhuma retorna o token; valor plantado ausente de todos os sinks.
- **Docker/Swarm**: rotação real; nodes existentes permanecendo; join com token antigo rejeitado.
- **policy**: rotação exigindo `INSTANCE_ADMIN` + step-up.
- **integration**: rotação durante enrollment; falha no meio.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, varredura de rotas verde, nodes preservados na rotação, Critical/High = 0.
