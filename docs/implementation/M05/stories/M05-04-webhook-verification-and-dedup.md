# M05-04 — Webhook signature verification, replay protection and deduplication

## Objective
Aceitar eventos do provider Git apenas quando comprovadamente autênticos, e garantir que redelivery e replay não produzam trabalho duplicado.

## Outcome
Um webhook com assinatura inválida é rejeitado **antes de qualquer ação**; o mesmo delivery entregue duas vezes gera um único trigger lógico.

## References
- `docs/architecture/02-build-deploy.md` §4.3 (webhook), §16 (idempotência)
- `docs/architecture/09-data-model-apis-contracts.md` §7 (`UNIQUE(providerConnectionId, externalDeliveryId)`)
- `docs/annexes/C-threat-model-security-hardening.md` §13 (webhooks), T07
- `docs/annexes/D-test-strategy.md` §17 (webhooks: assinatura inválida, replay, duplicata, payload enorme)

## Preconditions
`M05-01` done.

## Scope
- Endpoint de webhook com **verificação de assinatura antes de qualquer processamento**.
- `WebhookDelivery`: providerConnectionId, externalDeliveryId, eventType, payloadHash, receivedAt, processedAt, status.
- Constraint `UNIQUE(providerConnectionId, externalDeliveryId)`.
- Janela de replay por timestamp quando o provider fornecer.
- Limite de tamanho de payload.
- Conversão do evento em **trigger interno idempotente**, deduplicado por delivery ID + commit.
- Rate limit no endpoint.

## Out of Scope
- Criar build/deploy a partir do trigger (`M06-11`) — M05 registra o trigger; M06 decide o que fazer com ele.
- Webhooks de Registry (Anexo C §13; sem requisito imediato).
- Webhooks de saída para o usuário (`M09-11`).

## Domain Impact
**Entidade:** `WebhookDelivery`. A dedup é por **chave natural** do provider, não por `Idempotency-Key` de cliente.

## Application Layer
- **Commands:** `IngestWebhookDelivery`.
- O endpoint é público por necessidade e por isso concentra defesas próprias.

## Security Requirements
- **Assinatura verificada antes de qualquer ação** (doc 02 §4.3, regra explícita). Nenhum parsing de negócio antes da verificação.
- Comparação de assinatura em tempo constante.
- Janela de replay: evento com timestamp antigo é rejeitado.
- Limite de tamanho de payload, aplicado **antes** de carregar o corpo inteiro na memória.
- Rate limit por conexão e global.
- O payload é **dado não confiável**: validado, nunca desserializado às cegas, nunca interpretado como instrução.
- O webhook secret vive no Vault.
- Falha de verificação é registrada e é sinal de possível ataque (T07), com métrica própria.
- Nenhum conteúdo do payload é ecoado em resposta.

## Observability Requirements
- Métrica: deliveries recebidos, rejeitados por assinatura, rejeitados por replay, duplicados, aceitos.
- Log com delivery ID e resultado — sem o payload completo.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Assinatura inválida | Rejeitado antes de qualquer ação; registrado; métrica de segurança incrementada. |
| Replay de evento antigo | Rejeitado pela janela de tempo. |
| Delivery duplicado | Deduplicado pela constraint; um único trigger lógico. |
| Payload gigante | Rejeitado antes de carregar tudo. |
| Evento de tipo não suportado | Aceito, registrado e ignorado; não é erro. |
| Provider muda o formato | Falha de validação classificada, não crash. |
| Rajada de deliveries | Rate limit; backpressure, não perda de evento legítimo. |

## Acceptance Criteria
1. A assinatura é verificada **antes de qualquer processamento de negócio**, provado por teste que instrumenta a ordem.
2. A comparação de assinatura é em tempo constante.
3. Assinatura inválida é rejeitada e registrada com métrica de segurança.
4. Evento com timestamp fora da janela de replay é rejeitado.
5. `UNIQUE(providerConnectionId, externalDeliveryId)` existe; delivery duplicado gera **um** trigger lógico, provado por teste concorrente.
6. Payload acima do limite é rejeitado antes de ser carregado inteiro.
7. Rate limit é aplicado no endpoint.
8. O payload nunca é desserializado às cegas nem interpretado como instrução.
9. O webhook secret vive no Vault.
10. Nenhum conteúdo do payload é ecoado na resposta.
11. Evento de tipo não suportado é registrado e ignorado sem erro.
12. Métricas de deliveries por resultado estão disponíveis.

## Required Tests
- **security**: assinatura inválida; replay; payload gigante; comparação em tempo constante; ordem de verificação.
- **integration (concorrente)**: delivery duplicado gerando um trigger.
- **contract**: validação de webhook do provider.
- **unit**: janela de replay; validação de payload.

## Quality Gates
Local Quality Gate + `bin/security`. **Story crítica: exige plan mode** (endpoint público, T07).

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, os quatro casos de segurança verdes, ordem de verificação provada, Critical/High = 0.
