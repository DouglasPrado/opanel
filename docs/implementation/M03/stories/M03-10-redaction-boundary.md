# M03-10 — Redaction boundary across every sink

## Objective
Garantir, por mecanismo e por teste, que nenhum valor sensível atravesse qualquer fronteira de saída: log, erro, evento, payload de Operation, audit, métrica ou trace.

## Outcome
Existe uma camada de redaction aplicada em todos os sinks, e um scanner automatizado que planta valores conhecidos e falha o build se algum deles aparecer em qualquer saída.

## References
- `docs/annexes/C-threat-model-security-hardening.md` §17 (logs, métricas, tracing e AuditLog), §17.1 (redaction)
- `docs/architecture/03-runtime-observability.md` §10.3 (segurança de logs)
- `docs/architecture/07-internal-control-plane.md` §21 (logs removem tokens e material criptográfico)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §16.2 (AF-06), §19.1

## Preconditions
`M03-05` done.

## Scope
- Redaction **na origem e no sink**: quem conhece o segredo evita logá-lo; o sink é a última barreira (Anexo C §17.1).
- Cobertura obrigatória: logs da plataforma, respostas de erro, eventos de domínio e de integração, payloads de Operation, AuditLog, métricas, traces, artefatos de teste e relatórios.
- Sanitização por **allowlist** onde o formato é conhecido (audit `before`/`after`, payload de Operation) e por padrão conhecido onde não é (logs de aplicação).
- **Scanner de plaintext**: planta valores marcados no fluxo e varre todas as saídas; qualquer aparição falha o build.
- AF-06 estendida para avaliar serializers, formatadores de log e construtores de payload reais.
- Regra: erro retornado ao usuário nunca contém stack trace, SQL, caminho interno ou material criptográfico (doc 09 §28).

## Out of Scope
- Redaction em logs históricos de aplicação (`M09-05`, que herda esta camada).
- Redaction em logs de build (`M05-14`, idem).
- DLP genérico sobre conteúdo do usuário — impossível de garantir; a plataforma faz best-effort no que vem da aplicação e **garantia** no que é seu.

## Application Layer
Módulo único de redaction, consumido por logger, serializers, construtores de evento e de payload, e pelo AuditLog.

## Security Requirements
- **Não depender exclusivamente de regex genérica** (Anexo C §17.1): cada boundary que conhece secrets evita logá-los na origem; o sink é defesa em profundidade.
- Auth headers, cookies, senhas, chaves privadas, Recovery Key e valores conhecidos de secret são mascarados.
- O scanner planta valores **de teste** distintos por classe (secret, token, recovery key, chave privada) e varre todas as saídas.
- Uma saída nova que não passe pelo módulo de redaction é detectada por AF-06.
- Métricas evitam labels de alta cardinalidade e valores sensíveis (Anexo C §17).

## Observability Requirements
Este é um requisito de observabilidade **negativo**: a propriedade a garantir é a **ausência**. O scanner precisa produzir evidência arquivável de que a varredura rodou e o que cobriu.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Novo sink de log adicionado sem redaction | AF-06 e o scanner detectam. |
| Secret aparecendo em mensagem de exceção | Mascarado no sink; o teste planta e comprova. |
| Payload de evento com campo novo sensível | Allowlist omite por padrão; o campo novo não vaza por esquecimento. |
| Trace com header de autorização | Mascarado. |
| Artefato de teste com valor | Redaction aplicada antes do arquivamento. |
| Redaction mascarando demais e escondendo diagnóstico | Aceitável: preferir perder detalhe a vazar. O diagnóstico usa IDs e referências de versão. |

## Acceptance Criteria
1. Existe um módulo único de redaction, consumido por logger, serializers, eventos, payloads e AuditLog.
2. A sanitização de audit e de payload de Operation é por **allowlist**; campo novo não listado é omitido, não vazado.
3. O scanner de plaintext planta valores marcados e varre logs, erros, eventos, payloads, audit, métricas, traces e artefatos.
4. Qualquer aparição de valor plantado **falha o build**, provado por caso negativo controlado.
5. Auth headers, cookies, senhas, chaves privadas e Recovery Key são mascarados em todos os sinks.
6. Erro retornado ao usuário não contém stack trace, SQL, caminho interno nem material criptográfico.
7. AF-06 avalia serializers, formatadores de log e construtores de payload reais e reprova um caso negativo.
8. Métricas não carregam valor sensível nem label de alta cardinalidade.
9. Artefatos de teste passam por redaction antes do arquivamento.
10. Um sink novo sem redaction é detectado automaticamente.
11. O scanner produz evidência arquivável do que cobriu.

## Required Tests
- **unit**: allowlist; mascaramento por classe de valor.
- **integration**: scanner completo com valores plantados; caso negativo falhando o build.
- **security**: AF-06 com caso negativo; sink novo detectado; erro ao usuário sem detalhe interno.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` (AF-06 significativa). O scanner passa a integrar o PR Gate.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, scanner integrado ao CI com caso negativo comprovado, AF-06 avaliando código real, Critical/High = 0.
