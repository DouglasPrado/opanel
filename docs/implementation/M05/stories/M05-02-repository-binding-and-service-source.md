# M05-02 — Repository binding and per-Service source configuration

## Objective
Ligar um Service a um repositório, branch, diretório raiz e estratégia de build, suportando monorepos onde vários Services vêm do mesmo repositório.

## Outcome
Um Service declara `repo`, `branch`, `rootDir`, `buildMethod` e `watchPaths`; dois Services podem apontar para pastas diferentes do mesmo repositório.

## References
- `docs/architecture/02-build-deploy.md` §3.1 (source configurado no Service), §3.2 (monorepos)
- `docs/architecture/09-data-model-apis-contracts.md` §5.3 (build source), §7 (RepositoryBinding)
- `docs/architecture/10-ui-use-cases.md` UC-012, §10.1

## Preconditions
`M05-01` done.

## Scope
- `RepositoryBinding`: connectionId, repositório escolhido, validação de acesso.
- `ServiceSource`: serviceId, repositoryBindingId, branch padrão, `rootDir`, `dockerfilePath`, `buildMethod` (`railpack` default ou `dockerfile`), `watchPaths`, submodules, `autoDeploy` (flag registrada; o comportamento é de `M06-11`).
- Suporte a monorepo: múltiplos Services do mesmo repositório com contextos distintos.
- Validação de caminhos: `rootDir` e `dockerfilePath` restritos ao repositório.

## Out of Scope
- Resolução de commit (`M05-05`).
- Auto-deploy por push (`M06-11`) — aqui só a flag e os `watchPaths`.
- Build (`M05-08`, `M05-09`).

## Domain Impact
**Entidades:** `RepositoryBinding`, `ServiceSource`.
**Regra:** branch é referência **móvel** e nunca é identidade de release (doc 02 §3.1).

## Application Layer
- **Commands:** `BindRepository`, `UpdateServiceSource`.
- **Queries:** `ServiceSourceConfig`.
- **Policies:** `service.update` conforme escopo.

## UI Impact
Wizard do doc 10 §10.1: escolher repositório, branch, `rootDir`; o builder default é Automatic (Railpack).

## Security Requirements
- **Path traversal**: `rootDir` e `dockerfilePath` são validados e normalizados; `../` e caminhos absolutos são rejeitados. Um caminho que escape do repositório permitiria ler arquivos do builder.
- Só é possível bindar repositórios da instalação **do próprio Team**; repositório de outra conexão é negado.
- `watchPaths` é validado como padrão de caminho, não como expressão arbitrária.
- Alteração de source gera AuditLog — mudar o repositório de origem de um Service é uma ação sensível de supply chain.

## Observability Requirements
Log com `service_id`, repositório e branch configurados. A UI mostra a origem atual do Service com clareza.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Repositório sem acesso pela instalação | Rejeitado com causa. |
| `rootDir` com `../` ou caminho absoluto | Rejeitado por validação. |
| `dockerfilePath` fora do `rootDir` | Rejeitado. |
| Branch inexistente | Aviso na configuração; o erro definitivo aparece na resolução (`M05-05`). |
| Repositório de outro Team | Negado sem revelar existência. |
| Monorepo com dois Services no mesmo `rootDir` | Permitido, mas sinalizado, porque provavelmente é engano. |

## Acceptance Criteria
1. Um Service é ligado a um repositório, branch, `rootDir` e `buildMethod`.
2. Dois Services do mesmo repositório com `rootDir` diferentes funcionam (monorepo).
3. `rootDir` e `dockerfilePath` com `../` ou caminho absoluto são **rejeitados**, provado por casos negativos.
4. `dockerfilePath` fora do `rootDir` é rejeitado.
5. Repositório sem acesso pela instalação é rejeitado com causa.
6. Repositório de outro Team é negado sem revelar existência.
7. `watchPaths` é validado como padrão de caminho.
8. `buildMethod` default é `railpack`.
9. Branch é tratada como referência móvel; nada a usa como identidade de release.
10. Alteração de source gera AuditLog; negativo cross-team passa.

## Required Tests
- **unit**: validação e normalização de caminhos; `watchPaths`.
- **integration**: monorepo com dois Services; repositório sem acesso.
- **security**: bateria de path traversal em `rootDir` e `dockerfilePath`; repositório cross-team.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, path traversal comprovadamente bloqueado, monorepo funcionando, Critical/High = 0.
