# M10-17 — Protection Readiness dashboard and alerts

## Objective
Mostrar, em um lugar só, se a plataforma está realmente recuperável — com RPO real, verificação da Recovery Key, idade do último drill e saúde do destino.

## Outcome
O painel de proteção responde “conseguimos recuperar?” com evidência, e as condições de risco viram alertas.

## References
- `docs/architecture/05-backup-restore-dr.md` §17 (health de proteção na UI), §17.1 (dashboard), §17.2 (estados que geram alerta)
- `docs/architecture/10-ui-use-cases.md` §19.1 (protection dashboard)
- `docs/architecture/09-data-model-apis-contracts.md` §23 (`ProtectionReadinessView`)

## Preconditions
`M10-16` done. Integra com `M03-13` e com o motor de alertas de `M09-08`.

## Scope
- `ProtectionReadinessView` derivada: estado do Platform DB, último backup, **RPO alvo × atual**, Recovery Key verificada, recuperação do Vault verificada, certificados protegidos, idade do estado do Swarm, último restore test, saúde do destino.
- Preenchimento do contrato de extensão deixado por `M03-13`.
- Condições de alerta do doc 05 §17.2 registradas como `AlertRule` em `M09-08`: backup excedendo o RPO, último backup `FAILED`, Recovery Key não verificada, destino inacessível, verificação de restore falhando, backup de certificado desatualizado, estado do Swarm antigo antes de mudança de topologia, digest necessário indisponível.
- Badge de atenção na navegação quando a proteção está degradada.

## Out of Scope
- Execução dos backups e drills (Stories anteriores).
- Notificação externa (`M09-11`, que consome os alertas).
- Gate de release (`M14-07`).

## Application Layer
- **Queries:** `ProtectionReadinessView`.
- Derivação, nunca coluna booleana gravada.

## Security Requirements
- **A plataforma não afirma proteção sem evidência** (doc 05 §1.2, guardrail explícito): sem restore verificado, o estado reflete isso.
- Recovery Key não verificada é `CRITICAL` para recovery readiness (doc 05 §17.2).
- O painel não expõe material criptográfico; apenas estados, fingerprints e datas.
- O acesso exige permissão adequada; detalhes de infraestrutura são restritos.
- Um estado que não pôde ser calculado é **indisponível**, nunca `ok`.

## Observability Requirements
Cada item com valor, alvo, data da última verificação e o que fazer para melhorar. É o insumo direto do DR Gate de M14.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Último backup falhou | `CRITICAL`. |
| RPO atual acima do alvo | `WARNING` ou `CRITICAL` conforme o atraso. |
| Recovery Key não verificada | `CRITICAL` para recovery readiness. |
| Destino inacessível | `CRITICAL`. |
| Restore verification falhou | `CRITICAL`. |
| Nenhum drill executado | Estado **não** é `READY`; a ausência é explícita. |
| Cálculo indisponível | `indisponível` com causa, nunca `ok`. |

## Acceptance Criteria
1. `ProtectionReadinessView` é **derivada**, com todos os itens do doc 05 §17.1.
2. O RPO **atual** é exibido ao lado do alvo.
3. Sem restore verificado, o estado **não** é `READY`; a ausência é explícita.
4. Recovery Key não verificada resulta em `CRITICAL` para recovery readiness.
5. As oito condições de alerta do doc 05 §17.2 estão registradas como regras.
6. Um estado que não pôde ser calculado é `indisponível` com causa, nunca `ok`.
7. O painel não expõe material criptográfico; apenas estados, fingerprints e datas.
8. Cada item mostra valor, alvo, data da última verificação e o que fazer para melhorar.
9. O badge de atenção aparece na navegação quando a proteção está degradada.
10. O contrato de extensão deixado por `M03-13` é preenchido.
11. O painel de instância exige `INSTANCE_ADMIN`; a visão por Team exige `OWNER` ou `ADMIN` daquele Team; o negativo cross-team passa.
12. A view é o insumo do DR Gate de M14.

## Required Tests
- **unit**: derivação de cada item; estado indisponível; ausência de `READY` sem drill.
- **integration**: alertas disparando nas oito condições.
- **security**: ausência de material criptográfico; permissão.
- **unit (frontend)**: badge e painel.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de afirmação de proteção sem evidência provada, Critical/High = 0.
