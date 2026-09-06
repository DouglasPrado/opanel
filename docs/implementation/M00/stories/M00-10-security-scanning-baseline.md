# M00-10 — Security scanning baseline

## Objective
Colocar as verificações rápidas de segurança do Anexo C e D dentro do ciclo de desenvolvimento desde o primeiro commit: secret scan, dependency/SCA scan e análise estática.

## Outcome
`bin/security` executa secret scan, `bundler-audit`, auditoria de dependências npm e Brakeman, com severidade classificada e exit code coerente com a política.

## References
- `docs/annexes/C-threat-model-security-hardening.md` §21 (security testing obrigatório), §21.1 (ferramentas/processos)
- `docs/annexes/D-test-strategy.md` §4.1 (static checks), §17.1 (segurança em CI vs periódica)
- `docs/annexes/I-engineering-playbook-quality-gates.md` §10 (Dependency Gate), §19.1
- `docs/implementation/SPEC_CONFLICTS.md` SC-13.3

## Preconditions
`M00-09` done.

## Scope
- Secret scan cobrindo working tree **e** histórico do branch, com allowlist versionada e justificada.
- `bundler-audit` para gems e auditoria de dependências npm.
- Brakeman para análise estática de Rails.
- Política de severidade: Critical/High **novos** bloqueiam; Medium/Low são reportados e acompanhados.
- Registro de waiver: risco, justificativa, dono, expiração e mitigação (Anexo D §24.1). Waiver expirado volta a bloquear.
- Dependency Gate como checklist executável no CI: dependência nova sem justificativa no Story Report é reprovada.

## Out of Scope
- DAST, scan de imagem OCI e pentest — entram em `M13` e na cadência periódica (Anexo D §17.1).
- Testes de SSRF, IDOR e isolamento de builder — nascem junto das features (M04, M05, M11) e são consolidados em M13.

## Security Requirements
Esta Story **é** um controle de segurança. Regras próprias:
- O scanner não pode ser desabilitado pelo agente para destravar Story.
- Um achado suprimido exige waiver com expiração; sem expiração o CI reprova.
- O resultado do scan não pode conter o segredo detectado em texto claro — reporta arquivo, linha e tipo.

## Observability Requirements
Cada execução registra ferramenta, versão, contagem por severidade e disposição (bloqueado/waiver), no formato de Security Report do Anexo D §24.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Segredo commitado | Secret scan bloqueia; o segredo é tratado como comprometido e precisa de rotação, não apenas remoção do commit. |
| Vulnerabilidade Critical em dependência | CI bloqueia até atualizar, mitigar ou registrar waiver com expiração. |
| Falso positivo recorrente | Entra na allowlist versionada **com justificativa**, nunca por supressão silenciosa. |
| Waiver expirado | Volta a bloquear automaticamente. |

## Acceptance Criteria
1. `bin/security` executa secret scan, `bundler-audit`, auditoria npm e Brakeman.
2. Um segredo plantado em um commit de teste é detectado, e o relatório **não** imprime o valor.
3. Uma dependência com vulnerabilidade Critical conhecida bloqueia o CI, provado por caso negativo controlado.
4. A allowlist de falso positivo exige justificativa; entrada sem justificativa é reprovada.
5. Waiver exige risco, dono, justificativa, mitigação e expiração; waiver sem expiração é reprovado.
6. Waiver expirado volta a bloquear automaticamente, provado por teste com relógio controlado.
7. O Dependency Gate reprova uma dependência nova sem justificativa registrada.
8. O relatório de segurança segue o formato do Anexo D §24 e é arquivado como evidência.

## Required Tests
- **security**: caso negativo por scanner (2, 3), allowlist sem justificativa (4), waiver sem expiração (5), waiver expirado (6).
- **integration**: `bin/security` no CI com exit code correto em cenário limpo e sujo.

## Quality Gates
Integra o Local Quality Gate, o Pre-commit Gate (secret scan) e o PR Gate (suíte completa).

## Definition of Done
Os 8 Acceptance Criteria satisfeitos, cada scanner provado por caso negativo, política de waiver com expiração testada, Critical/High = 0.
