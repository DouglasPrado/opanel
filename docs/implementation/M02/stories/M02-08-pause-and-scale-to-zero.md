# M02-08 — Pause and scale-to-zero without losing configuration

## Objective
Permitir suspender um Service — pausando a reconciliação de mutações ou zerando réplicas — sem perder configuração, Release ou bindings.

## Outcome
O usuário escala para zero ou pausa um Service; a configuração permanece intacta; voltar a N réplicas restaura o serviço sem reconfiguração.

## References
- `docs/architecture/03-runtime-observability.md` §7.1 (scale to zero), §2.2 (estado `PAUSED`, `STOPPED`)
- `docs/architecture/07-internal-control-plane.md` §17.1 (status `PAUSED`)
- `docs/architecture/09-data-model-apis-contracts.md` §17 (state machines)

## Preconditions
`M02-01` done.

## Scope
- **Scale to zero**: `desiredReplicas = 0`; o Swarm Service permanece existindo com zero Tasks; configuração, domínios futuros e bindings preservados.
- **Pause**: suspende a reconciliação de mutações específicas do recurso, mantendo o estado atual; usado para manutenção e para conter incidente.
- Status `STOPPED` (zero réplicas deliberadas) distinto de `PAUSED` (reconciliação suspensa) e de `FAILED`.
- Retomada: voltar a N réplicas ou retomar a reconciliação, com convergência normal.
- Regra: pausar **não** apaga nem esconde divergência; o drift continua sendo detectado e registrado, apenas não é corrigido enquanto pausado.

## Out of Scope
- Pausa de Environment inteiro — o campo de status existe desde `M01-11`, mas a operação de pausa em massa não tem requisito e fica fora.
- Autoscaling respeitando pausa (`M09-13`).
- Deleção (`M02-09`).

## Application Layer
- **Commands:** `PauseService`, `ResumeService`, `ScaleService` (reuso, com zero permitido).
- **Policies:** `service.pause` e `service.scale` conforme escopo.

## Async / Control Plane
Pausar é uma decisão sobre **reconciliação**, não sobre desired state: o desired state continua registrado. Isso preserva a invariante de que o PostgreSQL descreve a intenção aprovada.

## UI Impact
Ações Pause/Resume no Service, com badge de estado distinto e explicação do que está suspenso. Um Service `STOPPED` mostra claramente que foi deliberado, não que quebrou.

## Security Requirements
- Pausar a reconciliação suspende também a correção automática de drift — isso é dito explicitamente na UI, porque cria uma janela em que o runtime pode divergir sem correção.
- Pausar e retomar geram AuditLog.
- Um Service pausado por longo período é sinalizado, para não virar um ponto cego permanente.

## Observability Requirements
- Estado `PAUSED`/`STOPPED` visível com desde quando e por quem.
- Drift detectado durante a pausa continua sendo registrado, com a marcação de que a correção está suspensa.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Scale-to-zero em Service com domínio ativo (a partir de M04) | Permitido com aviso de que o domínio deixará de responder. |
| Retomar Service cuja imagem não existe mais | `BLOCKED` com causa; não falha silenciosa. |
| Drift durante a pausa | Registrado, não corrigido; a UI mostra que a correção está suspensa. |
| Pausa esquecida por muito tempo | Sinalizado na UI e no dashboard de atenção. |
| Retomada concorrente com outra operação | Serializada pelo lease. |

## Acceptance Criteria
1. Scale-to-zero preserva configuração, Release e bindings; o registro do Service permanece completo.
2. Voltar a N réplicas restaura o serviço sem reconfiguração manual.
3. `STOPPED` é distinguível de `PAUSED` e de `FAILED` na API e na UI.
4. Pausar suspende a correção de drift, e isso é dito explicitamente ao usuário.
5. Drift ocorrido durante a pausa continua sendo **detectado e registrado**.
6. Retomar um Service cuja imagem não existe mais resulta em `BLOCKED` com causa.
7. Pausa prolongada é sinalizada.
8. Pausar, retomar e escalar para zero geram AuditLog; negativo cross-team passa.
9. Operações concorrentes com a retomada são serializadas pelo lease.

## Required Tests
- **unit**: transições entre `RUNNING`, `STOPPED` e `PAUSED`; sinalização de pausa prolongada.
- **integration**: preservação de configuração; drift registrado durante a pausa.
- **Docker/Swarm**: zero réplicas com Service existente; retomada convergindo; imagem inexistente bloqueando.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm.

## Definition of Done
Os 9 Acceptance Criteria satisfeitos, preservação de configuração provada, drift registrado durante pausa, Critical/High = 0.
