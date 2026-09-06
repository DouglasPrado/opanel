# M09-10 — Incident lifecycle and aggregation

## Objective
Agregar alertas, eventos e contexto em um incidente com dono e timeline, porque um problema operacional raramente é um alerta isolado.

## Outcome
Um deploy falho somado a taxa de erro e perda de node vira **um** incidente com timeline, não três alertas desconexos.

## References
- `docs/architecture/03-runtime-observability.md` §12.2 (lifecycle do incidente)
- `docs/architecture/09-data-model-apis-contracts.md` §13.2 (Incident)
- `docs/architecture/10-ui-use-cases.md` §18.3 (incident como entidade agregadora com notas e owner)
- `docs/annexes/E-operational-runbooks.md` §1.1 (ciclo de resposta), §11 (timeline mínima)

## Preconditions
`M09-09` done.

## Scope
- `Incident`: teamId, source (`ALERT`, `DEPLOYMENT`, `NODE`, `SECURITY`, `MANUAL`), severity, status (`OPEN`, `ACKNOWLEDGED`, `MITIGATED`, `RESOLVED`), resourceRefs, startedAt/resolvedAt, summary **sem dados sensíveis**.
- Agregação: alertas relacionados ao mesmo recurso e período entram no mesmo incidente.
- Timeline do incidente unindo alertas, eventos, deployments e operações.
- Notas e owner.
- Criação manual de incidente.
- Resolução automática quando as condições que o abriram se resolvem, com confirmação.

## Out of Scope
- Postmortem estruturado (Anexo E §11.2 define o critério; a ferramenta é backlog).
- Integração com PagerDuty e similares (`M09-11` abre o caminho por provider).
- Correlação automática sofisticada — a agregação é por recurso e janela, sem heurística opaca.

## Application Layer
- **Commands:** `OpenIncident`, `AcknowledgeIncident`, `MitigateIncident`, `ResolveIncident`, `AddIncidentNote`.
- **Queries:** `IncidentsForTeam`, `IncidentTimeline`.

## Security Requirements
- `summary` e notas **não** contêm dados sensíveis (doc 09 §13.2, regra explícita) e passam por redaction.
- Incidentes de origem `SECURITY` recebem tratamento de acesso mais restrito.
- A timeline do incidente é evidência: append-only para os eventos agregados; notas são atribuídas ao autor.
- Incidentes respeitam tenancy.
- Resolver um incidente não apaga o histórico dos alertas que o compuseram.

## Observability Requirements
Incidentes abertos por severidade; tempo até reconhecimento e até resolução. Esses números alimentam a avaliação de operabilidade em M14.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Vários alertas do mesmo problema | Agregados em um incidente. |
| Condição resolve sozinha | Sugerir resolução; **não** fechar sozinho sem confirmação quando houver dono. |
| Incidente sem dono | Sinalizado; incidente órfão é um problema operacional. |
| Nota com dado sensível | Redaction aplicada. |
| Incidente de segurança | Acesso mais restrito; auditado. |
| Recurso deletado durante o incidente | O incidente permanece com as referências; o histórico não some. |

## Acceptance Criteria
1. `Incident` existe com os campos do doc 09 §13.2.
2. Alertas do mesmo recurso e janela são agregados em um incidente.
3. A timeline une alertas, eventos, deployments e operações.
4. Notas e owner são atribuíveis.
5. Resolução automática é **sugerida**, não aplicada sem confirmação quando há dono.
6. Incidente sem dono é sinalizado.
7. `summary` e notas passam por redaction; nenhum dado sensível é persistido, provado com valor plantado.
8. Incidentes de origem `SECURITY` têm acesso mais restrito e são auditados.
9. Resolver não apaga o histórico dos alertas que o compuseram.
10. Recurso deletado durante o incidente não apaga o incidente nem suas referências.
11. Incidentes respeitam tenancy; negativo cross-team passa.
12. Tempo até reconhecimento e até resolução são medidos.

## Required Tests
- **unit**: agregação por recurso e janela; transições de status.
- **integration**: resolução sugerida; recurso deletado; histórico preservado.
- **security**: redaction em summary e notas; acesso restrito a incidentes de segurança.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, agregação provada, redaction verificada, Critical/High = 0.
