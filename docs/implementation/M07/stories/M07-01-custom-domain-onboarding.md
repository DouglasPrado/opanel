# M07-01 — Custom domain onboarding flow

## Objective
Permitir adicionar um domínio próprio com instrução clara do que precisa ser configurado, e acompanhamento explícito até a ativação.

## Outcome
O usuário informa hostname, Service e porta; a plataforma cria o `Domain` em `PENDING_DNS` e mostra exatamente qual registro criar.

## References
- `docs/architecture/08-networking-domains-edge.md` §10 (domínios e onboarding de DNS), §11 (tipos de registro)
- `docs/architecture/10-ui-use-cases.md` UC-024, §14.2 (Add Domain)

## Preconditions
M04 aceito.

## Scope
- Formulário: hostname, Service, `targetPort`, preferência de HTTPS e redirect.
- Criação do `Domain` e do `DomainBinding` em estado inicial, reutilizando o modelo de `M04-04`.
- Instrução do registro esperado, dependendo do tipo: subdomínio (CNAME para o endpoint estável, ou A/AAAA), apex (A/AAAA, ou ALIAS/ANAME quando o provider oferecer).
- Detecção do tipo de hostname (apex × subdomínio) e a instrução correspondente.
- Estado inicial e próximos passos visíveis; nada é ativado ainda.

## Out of Scope
- Verificação (`M07-02`) e posse (`M07-06`).
- Criação automática do registro (`M07-03`).
- Certificado (`M07-04`).

## Application Layer
- **Commands:** `AddCustomDomain`.
- **Policies:** `domain.create`.

## UI Impact
Tela do doc 10 §14.2 com hostname, porta, HTTPS automático, redirect, e o bloco de status: “Waiting for DNS”, “Certificate will be issued after validation”.

## Security Requirements
- O hostname é normalizado antes de qualquer checagem, e a unicidade global de `M04-04` se aplica.
- Adicionar um domínio **não** ativa nada: a rota e o certificado só existem após verificação e posse.
- A instrução exibida não revela topologia interna além do endpoint público necessário.
- Adicionar domínio gera AuditLog.

## Observability Requirements
Estado inicial com o motivo (“aguardando DNS”) e o registro esperado, para que o diagnóstico posterior compare observado × esperado.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Hostname já usado por outro Team | Rejeitado sem revelar quem o usa. |
| Hostname malformado ou com variação de normalização | Rejeitado. |
| Apex sem suporte a ALIAS no provider | Instrução por A/AAAA, com o aviso das limitações. |
| Service ou porta inexistente | Rejeitado por validação. |
| Domínio adicionado e abandonado | Fica `PENDING_DNS`; a UI sinaliza domínios parados há muito tempo. |

## Acceptance Criteria
1. O usuário adiciona um domínio informando hostname, Service e `targetPort`.
2. O `Domain` é criado em estado inicial; **nada** é ativado.
3. A instrução do registro esperado é exibida e corresponde ao tipo de hostname (apex × subdomínio).
4. Hostname já usado por outro Team é rejeitado sem revelar quem o usa.
5. Hostname malformado ou com variação de normalização é rejeitado.
6. Service ou porta inexistente é rejeitado por validação.
7. Apex sem ALIAS recebe instrução por A/AAAA com o aviso das limitações.
8. Domínio parado em `PENDING_DNS` por muito tempo é sinalizado.
9. A instrução não revela topologia interna.
10. Adicionar domínio exige permissão, gera AuditLog e passa no negativo cross-team.

## Required Tests
- **unit**: detecção apex × subdomínio; geração da instrução; normalização.
- **integration**: estado inicial sem ativação; sinalização de domínio parado.
- **policy**: negativo cross-team; hostname de outro Team.

## Quality Gates
Local Quality Gate + Reuse Gate.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, ausência de ativação prematura provada, Critical/High = 0.
