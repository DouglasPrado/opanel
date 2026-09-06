# M04-11 — Certificate renewal with early margin and safe retirement

## Objective
Renovar certificados com margem confortável e alertar **antes** da janela crítica, para que a plataforma nunca dependa da última semana de validade.

## Outcome
O scheduler identifica certificados na janela de renovação, emite nova versão, distribui, ativa e retira a anterior após o grace period — sem intervenção.

## References
- `docs/architecture/08-networking-domains-edge.md` §14 (renovação e rotação de certificados)
- `docs/annexes/B-nfr-slos.md` §8 (renovação com margem ≥ 30 dias; distribuição confirmada antes de ativar)
- `docs/annexes/E-operational-runbooks.md` RB-11 (certificado não emite/renova ou está perto de expirar)
- `docs/architecture/03-runtime-observability.md` §12.1 (alerta `CertificateExpiring`)

## Preconditions
`M04-10` done.

## Scope
- Scheduler que seleciona certificados dentro da janela de renovação (`renewAfter`), com margem ≥ 30 dias quando a CA permitir.
- Reuso do ciclo de `M04-09` + `M04-10`: emitir → distribuir → confirmar → ativar → retirar.
- **Alerta antecipado** de falha de renovação, disparado antes da janela crítica.
- Cadência do doc 07 §23: horas/dias normalmente, mais rápido perto do vencimento.
- Retentativa com backoff; falha persistente escala em severidade conforme a proximidade da expiração.
- Comportamento explícito do RB-11: se a renovação falhar mas o certificado ainda for válido, **manter a versão atual servindo**.

## Out of Scope
- Alertas formais e notificação externa (`M09-08`, `M09-11`) — aqui o sinal é gerado e registrado.
- Revogação de certificado — sem requisito imediato.
- Renovação de domínios de cliente (`M07`, mesmo mecanismo).

## Application Layer
- **Commands:** `RenewCertificate`.
- **Jobs:** scheduler de renovação com cadência adaptativa.

## Async / Control Plane
A renovação é a mesma cadeia de emissão, disparada por tempo em vez de por ação do usuário. Ela **não** altera o `DomainBinding` nem recria o Swarm Service da aplicação (doc 08 §14, regra): certificado e release têm ciclos de vida independentes.

## Security Requirements
- Renovar cedo é uma decisão de segurança: depender da última semana transforma qualquer indisponibilidade de provider em incidente de TLS.
- A versão anterior só é removida após a janela de segurança.
- A falha de renovação **nunca** derruba a versão válida em uso.
- Nenhum material de certificado em log.
- A escalada de severidade conforme a proximidade da expiração é obrigatória — um `WARNING` silencioso a 3 dias do vencimento é um defeito.

## Observability Requirements
- Métrica: dias restantes por certificado, renovações por resultado, falhas consecutivas.
- Condição de alerta `CertificateExpiring` do doc 03 §12.1 registrada com severidade crescente.
- Meta do Anexo B §3: gestão de certificados com 99,95% de renovações elegíveis concluídas antes da janela de risco, medida em 90 dias.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Renovação falha e o certificado ainda é válido | Manter servindo a versão atual; alertar; continuar tentando (RB-11). |
| Renovação falha perto da expiração | Severidade escala; o alerta é `CRITICAL`. |
| DNS provider indisponível | Retry com backoff; alerta antecipado. |
| Rate limit da CA | Backoff longo; registrar; não insistir. |
| Nova versão não confirma em todos os ingress | Não ativar; a anterior continua; alertar. |
| Relógio incorreto | Falha explícita; a validade não pode ser avaliada com relógio errado. |

## Acceptance Criteria
1. O scheduler identifica certificados na janela de renovação com margem ≥ 30 dias quando a CA permite.
2. A renovação reutiliza o ciclo emitir → distribuir → confirmar → ativar → retirar.
3. A renovação **não** altera o `DomainBinding` nem recria o Service da aplicação.
4. Renovação falha com certificado ainda válido mantém a versão atual servindo e alerta.
5. A severidade do alerta escala conforme a proximidade da expiração.
6. Nova versão que não confirma em todos os ingress **não** é ativada; a anterior continua.
7. A versão anterior só é removida após o grace period.
8. Rate limit da CA leva a backoff longo, sem insistência.
9. Relógio incorreto produz falha explícita.
10. Métricas de dias restantes e falhas consecutivas estão disponíveis.
11. Nenhum material de certificado aparece em log.
12. Renovação sem downtime, provado por teste com tráfego durante a troca.

## Required Tests
- **unit**: seleção da janela; escalada de severidade; cadência adaptativa.
- **integration**: falha de renovação preservando a versão válida; não ativação sem confirmação.
- **contract**: renovação no ambiente de staging da CA.
- **E2E/Docker/Swarm**: renovação com tráfego ativo, sem queda de conexão.
- **security**: ausência de material em log.

## Quality Gates
Local Quality Gate + contract tests + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, renovação sem downtime provada, preservação da versão válida em falha, Critical/High = 0.
