# M09-11 — Notification providers

## Objective
Entregar notificações por um contrato desacoplado, para que adicionar um canal não exija tocar o motor de regras.

## Outcome
Alertas e incidentes notificam por e-mail e webhook; adicionar outro canal é implementar um adapter.

## References
- `docs/architecture/03-runtime-observability.md` §12.3 (NotificationProvider desacoplado)
- `docs/architecture/10-ui-use-cases.md` §18.2 (notification target sem acoplar core)
- `docs/annexes/C-threat-model-security-hardening.md` §13.1 (SSRF em URL fornecida pelo usuário)

## Preconditions
`M09-09` done.

## Scope
- Contrato `NotificationProvider` com e-mail e webhook como primeiros adapters.
- `NotificationPolicy`: destino, severidades, escopo e janela de agrupamento.
- Agrupamento e throttling para evitar inundar o destino.
- Retry com backoff e dead-letter observável.
- Conteúdo da notificação **sanitizado**, com link para o recurso na plataforma.

## Out of Scope
- Slack, Discord, WhatsApp, PagerDuty — o contrato permite; cada um é Story própria.
- Escalonamento e rotação de on-call.
- Notificações in-app (já cobertas pelo Operations Center e pelo dashboard).

## Application Layer
- **Providers:** `NotificationProvider`.
- **Commands:** `CreateNotificationPolicy`, `TestNotificationTarget`.

## Security Requirements
- **URL de webhook é entrada do usuário**: passa pela política de SSRF (Anexo C §13.1) — loopback, link-local, RFC1918/ULA e metadata bloqueados; redirect é nova decisão de policy.
- A notificação **não** carrega valor sensível: nem secret, nem conteúdo de log, nem detalhe interno. Ela carrega contexto e um link.
- O webhook de saída é **assinado**, para que o destinatário possa verificar a origem.
- Credencial do destino (SMTP, token) no Vault.
- Throttling impede que um alerta em flapping vire ataque de volume contra o destino do próprio cliente.
- Falha de entrega não pode bloquear o motor de alertas.

## Observability Requirements
Entregas por resultado e latência; dead-letter visível. Um destino consistentemente falhando é sinalizado ao usuário.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Destino indisponível | Retry com backoff; dead-letter após o limite; o alerta permanece visível na plataforma. |
| URL apontando para rede interna | Bloqueada por SSRF. |
| Redirect para host interno | Bloqueado. |
| Alerta em flapping | Throttling e agrupamento. |
| Credencial de SMTP inválida | Erro classificado; o usuário é avisado no painel. |
| Falha de entrega | **Não** bloqueia o motor de alertas nem a abertura de incidente. |

## Acceptance Criteria
1. `NotificationProvider` existe com adapters de e-mail e webhook.
2. `NotificationPolicy` define destino, severidades, escopo e agrupamento.
3. A URL de webhook passa pela política de SSRF; loopback, link-local, RFC1918/ULA e metadata são bloqueados, provado por teste.
4. Redirect para host interno é bloqueado.
5. O webhook de saída é assinado e o destinatário pode verificar a origem.
6. A notificação **não** carrega valor sensível nem conteúdo de log; ela carrega contexto e link.
7. Throttling e agrupamento impedem inundar o destino em caso de flapping.
8. Retry com backoff e dead-letter observável existem.
9. Falha de entrega **não** bloqueia o motor de alertas nem a abertura de incidente.
10. Credenciais de destino vivem no Vault.
11. Destino consistentemente falhando é sinalizado ao usuário.
12. Criar/alterar política gera AuditLog; negativo cross-team passa.

## Required Tests
- **contract**: entrega por e-mail e por webhook; destino indisponível; retry.
- **security**: bateria de SSRF na URL; redirect; assinatura do webhook; ausência de valor sensível no payload.
- **integration**: throttling; dead-letter; falha não bloqueando o motor.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, SSRF coberta, payload sem dado sensível, Critical/High = 0.
