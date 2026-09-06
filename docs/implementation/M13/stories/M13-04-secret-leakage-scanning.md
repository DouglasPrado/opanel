# M13-04 — Consolidated secret leakage scanning

## Objective

Provar que nenhum secret em plaintext aparece em log, exceção, resposta, payload de evento, payload de Operation, audit, métrica ou telemetria — em nenhum caminho, incluindo os de erro.

## Outcome

Um scanner que injeta canários e falha se qualquer um deles aparecer em qualquer superfície observável.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §6 (T05), §12, §17.1, §21
- `docs/architecture/04-identity-teams-security.md` — Vault, SecretVersion e redaction
- `docs/annexes/D-test-strategy.md` §10, §17

## Preconditions

- Vault e redaction implementados em M03; distribuição implementada nas Stories de consumo.

## Scope

- **Canários**: valores de secret únicos e reconhecíveis, plantados em Secret, credencial de registry, credencial de DNS, token de MCP, chave privada de certificado e Recovery Key.
- Exercício do sistema inteiro: caminhos felizes **e** caminhos de erro, exceções, timeouts e falhas de provider.
- Superfícies varridas: logs de aplicação e de job, exceções e backtraces, respostas HTTP e Inertia, payloads de OutboxEvent e de Operation, registros de audit, métricas e labels, arquivos temporários e artefatos de build, dumps de backup e telemetria.
- Verificação de que a redaction cobre valor **parcial** e derivações óbvias (base64, url-encoded, JSON-escaped).
- Verificação de que a Recovery Key nunca é persistida de forma recuperável nem aparece em backup do store primário.
- Verificação de que payload de Operation carrega `SecretVersion` ID, nunca plaintext.

## Out of Scope

- Vazamento por canal lateral criptográfico: fora do modelo de ameaça do MVP.

## Security Requirements

- O canário nunca é um secret real.
- A suíte falha fechada: superfície nova não varrida é finding, não silêncio.
- Um hit de canário é **Critical** e bloqueia o release.

## Observability Requirements

- Relatório: canários plantados, superfícies varridas, hits e sua localização exata.
- A localização do hit no relatório usa referência (arquivo:linha, campo), nunca o valor.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Canário em log de erro | Finding **Critical**. |
| Canário em payload de Operation | Finding **Critical**. |
| Canário em audit | Finding **Critical**. |
| Canário em métrica/label | Finding **High**. |
| Superfície nova não varrida | Suíte falha. |

## Acceptance Criteria

1. Canários cobrem Secret, registry, DNS, token MCP, chave privada de cert e Recovery Key.
2. Caminhos de erro e exceção são exercitados, não só os felizes.
3. Todas as superfícies listadas são varridas.
4. Derivações codificadas do canário também são detectadas.
5. Nenhum hit em nenhuma superfície.
6. Payload de Operation carrega apenas `SecretVersion` ID.
7. Recovery Key não aparece em backup do store primário.
8. Superfície nova não varrida faz a suíte falhar.
9. O relatório nunca contém o valor do canário.

## Required Tests

- Integration end-to-end com injeção de falha nos providers.
- Teste do scanner contra um vazamento deliberado (prova de que ele detecta).

## Quality Gates

Local Quality Gate; AF-06 (nenhum secret plaintext em serializer, log ou audit).

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Zero hits; scanner provado contra vazamento deliberado.
- [ ] Self-review; `tasks.json` atualizado com commit.
