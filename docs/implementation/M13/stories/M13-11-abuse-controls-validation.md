# M13-11 — Abuse control validation: rate limits, quotas and backpressure

## Objective

Provar que os limites que protegem a plataforma funcionam sob abuso real — e que, ao serem atingidos, degradam o abusador sem derrubar os demais.

## Outcome

Evidência de que um Team hostil ou um cliente com bug não consegue consumir a plataforma inteira.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §6 (T13), §19, §21
- `docs/architecture/04-identity-teams-security.md` — quotas e limites por Team
- `docs/annexes/B-nfr-slos.md` §9, §17

## Preconditions

- Rate limits e quotas implementados nas Stories de origem (M01, M05, M09, M11, M12).
- `M13-06` concluída.

## Scope

- Abuso de autenticação: força bruta de login, spray de token, criação em massa de sessão.
- Abuso de build: enfileiramento massivo, builds intencionalmente lentos, artefatos gigantes.
- Abuso de deploy: rajada de deploys no mesmo Service; deploys em muitos Services.
- Abuso de logs e métricas: streaming simultâneo em massa, consultas de intervalo enorme.
- Abuso de webhook: rajada de entregas, payloads grandes, replay.
- Abuso de MCP: loop de agente chamando ferramentas sem parar.
- Quotas: exceder o limite de Services, réplicas, domínios, Secrets e retenção; comportamento ao atingir e ao ultrapassar.
- **Isolamento**: enquanto um Team abusa, um Team vizinho mantém o SLO — esta é a verificação central.
- Verificação de que o limite retorna erro claro e acionável, não falha genérica.

## Out of Scope

- DDoS volumétrico externo: responsabilidade da camada de rede, documentada como risco.

## Security Requirements

- Rate limit não pode ser contornado por rotação trivial de identidade dentro do mesmo Team ou token.
- Mensagens de limite não revelam a existência de recursos alheios nem a configuração exata que permitiria otimizar o abuso.
- Bloqueios são auditados.

## Observability Requirements

- Métrica de limites atingidos por classe, sem cardinalidade por usuário arbitrário.
- Relatório: por cenário de abuso, o limite que atuou, o efeito no abusador e o efeito no vizinho.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Abuso de um Team degrada o vizinho | Finding **Critical**. |
| Limite contornável por rotação trivial | Finding **High**. |
| Quota excedida sem erro claro | Finding **Medium**. |
| Limite derruba o componente em vez de rejeitar | Finding **High**. |
| Bloqueio sem audit | Finding **Medium**. |

## Acceptance Criteria

1. Todos os cenários de abuso listados são executados.
2. Rate limits impedem abuso de login, token, webhook, build, deploy e log streaming.
3. Quotas impedem ultrapassar os limites de Services, réplicas, domínios, Secrets e retenção.
4. Durante o abuso, um Team vizinho mantém o SLO.
5. O limite rejeita a requisição; ele não derruba o componente.
6. Erros de limite são claros e acionáveis, sem vazar configuração explorável.
7. Limites não são contornáveis por rotação trivial de identidade.
8. Bloqueios são auditados e produzem métrica.
9. Loop de agente MCP é contido pelo rate limit.

## Required Tests

- Testes de abuso com o harness de carga.
- Teste de isolamento com carga simultânea de Team vizinho.

## Quality Gates

Local Quality Gate.

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Isolamento entre Teams demonstrado sob abuso.
- [ ] Self-review; `tasks.json` atualizado com commit.
