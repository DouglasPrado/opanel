# M09-05 — Historical log pipeline with retention

## Objective
Preservar os logs depois que a Task que os produziu deixou de existir, para que o diagnóstico não dependa de estar olhando na hora.

## Outcome
Logs de aplicação e de plataforma são coletados, enriquecidos com a identidade da plataforma, armazenados com retenção configurável e permanecem consultáveis após a substituição da Task.

## References
- `docs/architecture/03-runtime-observability.md` §10.1 (live × historical), §10.3 (segurança de logs)
- `docs/annexes/B-nfr-slos.md` §12 (retenção: service logs 14 dias, build logs 30 dias)
- `docs/annexes/C-threat-model-security-hardening.md` §17, §17.1 (redaction)
- `docs/implementation/SPEC_CONFLICTS.md` SC-11

## Preconditions
`M09-01` done.

## Scope
- Coletor de logs por node, enviando para o backend de logs com os labels de `M09-01`.
- `LogProvider` como abstração, com backend substituível (mesmo princípio do `MetricProvider`).
- Retenção configurável por Team/Environment, com default do Anexo B §12.
- **Redaction no pipeline**, reutilizando o módulo de `M03-10`.
- Rotação e limites de volume por Team, para que um workload verborrágico não consuma o storage de todos.
- Distinção entre logs da **aplicação** e logs da **plataforma**, com regras de acesso diferentes.

## Out of Scope
- Busca e export (`M09-06`).
- Logs de build (`M05-14`, que já tem seu caminho).
- Tracing (não é requisito da primeira fase).

## Application Layer
- **Providers:** `LogProvider`.
- **Commands:** `EnsureLogCollectors`, `UpdateRetentionPolicy`.

## Security Requirements
- **Nunca logar valores de SecretVersion** (doc 03 §10.3); a redaction do pipeline é a última barreira.
- Log de aplicação é **conteúdo do usuário**: redaction best-effort; log da plataforma é responsabilidade nossa e a garantia é forte.
- Acesso a logs respeita RBAC por Environment; produção pode exigir mais.
- Limites de volume por Team como controle de abuso (Anexo C §19).
- Credencial do backend no Vault; a URL passa pela política de SSRF.
- Retenção não pode ser reduzida de forma a apagar evidência de um incidente em curso sem registro.

## Observability Requirements
Volume ingerido por Team/Service; lacunas de coleta sinalizadas; saúde do pipeline visível.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Backend de logs indisponível | Sinalizado; a UI oferece apenas live/recente e **diz** que o histórico está indisponível (doc 10 UC-033). |
| Volume acima do limite | Backpressure e alerta; não derrubar o node nem perder silenciosamente. |
| Task substituída | Os logs anteriores continuam consultáveis. |
| Lacuna de coleta | Sinalizada na consulta, não escondida. |
| Redaction falha | Falha fechada para o campo afetado: preferir perder o campo a vazar. |
| Retenção expira durante investigação | A UI informa a data limite; reduzir retenção é ação registrada. |

## Acceptance Criteria
1. Logs são coletados por node e enriquecidos com os labels de `M09-01`.
2. Os logs permanecem consultáveis **após** a Task ser substituída, provado contra runtime real.
3. `LogProvider` abstrai o backend; trocá-lo não exige alterar os coletores.
4. A retenção é configurável, com os defaults do Anexo B §12.
5. A redaction do pipeline mascara valores conhecidos, provado com valor plantado.
6. Redaction que falha **omite o campo**; nunca deixa passar.
7. Backend indisponível é sinalizado e a UI oferece apenas live/recente, dizendo o motivo.
8. Volume acima do limite gera backpressure e alerta, sem perda silenciosa.
9. Lacuna de coleta é sinalizada na consulta.
10. Acesso respeita RBAC por Environment; negativo cross-team passa.
11. A credencial do backend vive no Vault e a URL passa pela política de SSRF.
12. Reduzir a retenção é ação registrada.

## Required Tests
- **Docker/Swarm**: logs consultáveis após substituição de Task.
- **integration**: backend indisponível; limite de volume; lacuna sinalizada.
- **security**: valor plantado mascarado; redaction falhando fechada; SSRF; negativo cross-team.
- **contract**: `LogProvider`.

## Quality Gates
Local Quality Gate + contract tests + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, persistência após substituição de Task provada, redaction fechada verificada, Critical/High = 0.
