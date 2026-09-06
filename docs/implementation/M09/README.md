---
milestone: "M09"
name: "Observability, Alerts, Incidents & Autoscaling"
type: "milestone"
status: "pending"
---

# M09 — Observability, Alerts, Incidents & Autoscaling

## Identity

| Campo | Valor |
|---|---|
| **ID** | M09 |
| **Nome** | Observability, Alerts, Incidents & Autoscaling |
| **Objetivo** | Tornar a plataforma operável **sem SSH como mecanismo primário de diagnóstico**: métricas, logs históricos pesquisáveis, timeline de eventos, alertas com deduplicação, incidentes, notificações, autoscaling reativo e terminal auditado. |
| **Resultado observável** | Um operador diagnostica um Service degradado correlacionando status, logs, métricas e o deployment que o precedeu — sem acessar o host. Um alerta abre um incidente; a recuperação o resolve. O autoscaler ajusta réplicas com decisões explicáveis. |

## Why

Até aqui a plataforma **executa** workloads; a partir de M09 ela permite **operá-los**. Sem observabilidade histórica, todo diagnóstico depende de estar olhando na hora certa.

Este é também o Milestone que introduz a observabilidade **avançada**. A mínima — logs estruturados, correlation IDs, status derivado, timeline de Operations — nasceu em M00/M01/M02, como exige o Goal §19. M09 não corrige uma ausência; ele amplia uma base que já existe.

M09 desbloqueia M12 (tools de observabilidade do MCP) e alimenta M13 (validação de SLO).

## Scope

- Identidade de telemetria: labels estáveis da plataforma em todo dado coletado.
- Coletores por node: métricas de host, de container e do Traefik.
- `MetricProvider` como abstração, com backend substituível (SC-11 exige ADR para o backend concreto).
- Métricas por cluster, environment, service, task e ingress na UI.
- Pipeline de logs históricos com retenção configurável.
- Busca, filtro por tempo e export **auditado**.
- Ingestão de eventos de runtime e timeline operacional unificada.
- `AlertRule` com avaliação, `AlertInstance`, deduplicação e silenciamento com expiração obrigatória.
- `Incident` como entidade agregadora com lifecycle.
- `NotificationProvider` desacoplado (e-mail e webhook).
- Autoscaling reativo por CPU/memória, com min/max, thresholds, steps e cooldown.
- Regras de segurança do autoscaler: nunca escalar sem capacidade, sem métricas confiáveis ou durante deployment incompleto.
- Terminal/exec com RBAC, step-up, TTL e auditoria de sessão.
- SLIs, SLOs e error budget visível.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M10 | Protection readiness e alertas de backup (a regra de alerta é definida aqui; a fonte, lá). |
| M13 | Validação formal de SLO sob carga, chaos e load testing. |
| Backlog | APM completo, tracing distribuído obrigatório, autoscaling preditivo, métricas de negócio como sinal primário. |

## Dependencies

- **Hard:** M02 (runtime e eventos), M06 (deployments a observar).
- **Soft:** M08 (métricas multi-node e de ingress redundante ficam completas com cluster real).
- **Externas:** backend de métricas e de logs (gerenciado ou auto-hospedado) — decisão por ADR em `M09-03`.

## User-visible Outcome

O operador abre um Service degradado e vê, na mesma tela: status derivado, réplicas, CPU/memória, latência, erros, o último deployment e os logs relevantes. Ele cria uma regra de alerta, recebe a notificação, abre o incidente, resolve, e o histórico fica. E configura autoscaling sabendo **por que** cada decisão foi tomada.

## Technical Outcome

- Telemetria enriquecida com identidade da plataforma, não apenas container ID.
- Backend de observabilidade desacoplado por abstração.
- Motor de alertas com deduplicação, evitando tempestade.
- Autoscaler que se recusa a decidir com dado ruim.
- Exec como caminho separado, permissionado e auditado — nunca uma operação do Executor.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `MetricBinding`, `AlertRule`, `AlertInstance`, `Incident`, `NotificationPolicy`, `AutoscalingPolicy`, `TerminalSession`, `ObservabilityProvider`, `SloDefinition`. |
| Commands | `CreateAlertRule`, `MuteAlert`, `OpenIncident`, `ResolveIncident`, `UpdateAutoscalingPolicy`, `StartTerminalSession`. |
| Queries | `ServiceMetrics`, `ClusterMetrics`, `LogSearch`, `OperationalTimeline`, `ErrorBudgetView`. |
| Events | `incident.opened.v1`, `alert.fired`, `autoscale.applied`. |
| Jobs | Coleta, avaliação de regras, decisão de autoscaling, retenção. |
| Providers | `MetricProvider`, `LogProvider`, `NotificationProvider`. |
| UI | Metrics, Logs, Alerts, Incidents, Autoscaling, Terminal. |

## Security

- **Terminal/exec é a capacidade de maior risco** (doc 03 §14, Anexo C §15): permissão dedicada, step-up em produção, alvo é uma Task específica, TTL e idle timeout, sessão auditada, **nunca** shell do host.
- `VIEWER` nunca recebe exec.
- Logs e métricas passam por redaction; secrets nunca aparecem em telemetria (doc 03 §10.3).
- Acesso a logs de produção respeita RBAC; export é evento auditado.
- Métricas evitam labels de alta cardinalidade e valores sensíveis.
- Coletores que precisam de acesso ao Docker são componentes privilegiados e hardenizados (doc 03 §18).
- Limites de streams e de consultas caras como controle de abuso (Anexo C §19).
- Autoscaling com min/max e cooldown como guardrail contra abuso e oscilação.
- Ameaça coberta: T10 (exec/terminal abusado).

## Observability

Este Milestone **é** a observabilidade. O critério interno: um incidente precisa ser diagnosticável a partir dos sinais coletados, sem reproduzir localmente e sem SSH.

- Correlação obrigatória entre métrica, log, evento, deployment e operação pelos IDs da plataforma.
- Dependência degradada aparece como degradada — **nunca** mascarada como saudável (Anexo B §20).
- Cada decisão de autoscaling registra métrica observada, política, valor anterior e novo.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Avaliação de regra; deduplicação; janela e cooldown; decisão de scale. |
| Integration | Retenção; silenciamento com expiração; incidente agregando alertas. |
| Contract | `MetricProvider`, `LogProvider`, `NotificationProvider`. |
| Docker/Swarm | Logs com substituição de Task; métricas após reinício de node; exec em Task real. |
| E2E | Diagnóstico de Service degradado; criação de alerta até incidente resolvido; autoscaling sob carga sintética. |
| Security | Terminal não autorizado; export auditado; ausência de secret em telemetria; limites de stream. |

## Acceptance Criteria

1. Todo dado de telemetria carrega os labels de identidade da plataforma, não apenas container ID.
2. O usuário acompanha um deployment em tempo real **sem polling agressivo** do Docker.
3. Logs ao vivo funcionam com múltiplas Tasks e sobrevivem à substituição de Task.
4. Logs históricos são pesquisáveis por tempo e conteúdo, com retenção configurável.
5. CPU, memória, réplicas e restarts têm histórico suficiente para diagnóstico.
6. Falha de Service cria status e contexto observável, não apenas stack trace.
7. Alertas evitam tempestade por deduplicação e silenciamento; o silenciamento **exige expiração**.
8. Incidentes agregam alertas, eventos e contexto de deployment.
9. Notificações são desacopladas por provider.
10. O autoscaler altera réplicas conforme política, e **cada decisão é explicável**.
11. O autoscaler **não** escala sem capacidade, sem métricas confiáveis ou durante deployment incompleto.
12. Terminal/exec exige permissão, step-up em produção, e gera AuditLog com início, fim e alvo.
13. Terminal nunca dá acesso a shell do host.
14. Nenhum secret aparece em log, métrica, evento ou trace.
15. Dependência degradada é exibida como degradada, nunca como saudável.
16. SLIs e error budget são calculáveis e visíveis.

## Exit Gate

- [ ] Stories `required` `done`; 16 Acceptance Criteria com evidência.
- [ ] E2E de diagnóstico de Service degradado verde.
- [ ] Teste de alerta → incidente → resolução verde.
- [ ] Teste de autoscaling com métricas indisponíveis (modo seguro) verde.
- [ ] Teste de terminal não autorizado e de auditoria de sessão verde.
- [ ] ADR do backend de observabilidade **aceito** (SC-11).
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.
