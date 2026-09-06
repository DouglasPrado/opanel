# M06-03 — Configuration resolution and secret materialization steps

## Objective
Tornar explícitas as duas etapas que antecedem a mutação do Swarm: resolver a configuração efetiva e materializar as secrets referenciadas pela Release.

## Outcome
O deployment resolve variáveis e bindings, materializa as Swarm Secrets necessárias e só então atualiza o Service — falhando **antes** de tocar o runtime se algo faltar.

## References
- `docs/architecture/02-build-deploy.md` §17.2 (`RESOLVING_CONFIG`, `MATERIALIZING_SECRETS`), §21 (pipeline de referência)
- `docs/architecture/07-internal-control-plane.md` §13 (fluxo de deploy)
- `docs/architecture/01-foundation.md` §10.3 (fluxo completo de secret)

## Preconditions
`M06-02` done. M03 aceito.

## Scope
- Etapa `RESOLVING_CONFIG`: variáveis não sensíveis, recursos, placement, health, portas e política de rollout efetivos para aquele Environment.
- Etapa `MATERIALIZING_SECRETS`: reutiliza o `SecretReconciler` de `M03-07` para garantir que as Swarm Secrets das versões referenciadas existam e estejam anexadas.
- **Falha antes de mutar**: qualquer referência ausente bloqueia o deployment **antes** de `UPDATING_SERVICE`.
- Registro das versões efetivamente resolvidas no `DeploymentEvent` (`CONFIG_RESOLVED`), por ID.
- Ordem determinística das etapas.

## Out of Scope
- Rollout (`M06-04`).
- Criação de bindings (`M03-06`).
- Promoção de versões de secret (`M03-08`).

## Application Layer
- **Commands:** parte de `RequestDeployment`, executada pelo worker.
- **Reconciler:** reuso do `SecretReconciler`.

## Async / Control Plane
Estas etapas são o ponto onde o deployment ainda é **reversível sem custo**: nada foi aplicado ao runtime. Falhar aqui é barato; falhar depois não é. Por isso todas as validações caras acontecem antes de `UPDATING_SERVICE`.

## Security Requirements
- O evento `CONFIG_RESOLVED` registra `SecretVersion` **IDs**, nunca plaintext (doc 02 §18).
- A materialização segue o least privilege de `M03-07`: só o Service autorizado recebe.
- `SecretVersion` revogada ou indisponível **bloqueia** o rollout antes de aplicar (doc 10 UC-018).
- A decifra ocorre apenas no boundary autorizado, em memória.
- Nenhum valor sensível aparece no evento, no log ou na timeline.

## Observability Requirements
Evento `CONFIG_RESOLVED` com release id e IDs das versões de secret. Duração de cada etapa registrada.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| `SecretVersion` indisponível | Bloquear **antes** de `UPDATING_SERVICE`; nada é aplicado. |
| Variável referenciando chave inexistente | Bloquear com causa clara. |
| Colisão entre variável e `targetName` de secret | Bloquear (a validação já existe em `M03-11`; aqui é reafirmada no deploy). |
| Materialização falha | Deployment `FAILED` com causa; o Service continua na release anterior. |
| Envelope de criptografia indisponível | Bloquear; nunca aplicar sem a secret esperada. |
| Configuração resolvida difere do esperado | Registrada no evento, para diagnóstico posterior. |

## Acceptance Criteria
1. A configuração efetiva é resolvida antes de qualquer mutação no runtime.
2. As Swarm Secrets referenciadas são materializadas antes de `UPDATING_SERVICE`.
3. Qualquer referência ausente **bloqueia antes** de tocar o runtime, provado por teste.
4. `SecretVersion` revogada ou indisponível bloqueia o rollout.
5. O evento `CONFIG_RESOLVED` registra IDs de versão, nunca plaintext, provado com valor plantado.
6. A materialização respeita o least privilege: só o Service autorizado recebe.
7. Envelope indisponível bloqueia; nenhum deploy ocorre sem a secret esperada.
8. Falha de materialização deixa o Service na release anterior.
9. A ordem das etapas é determinística e observável na timeline.
10. A duração de cada etapa é registrada.

## Required Tests
- **unit**: resolução de configuração; ordem das etapas.
- **integration**: bloqueio antes de mutar em cada cenário de referência ausente.
- **Docker/Swarm**: materialização real seguida de update; falha de materialização preservando a release anterior.
- **security**: ausência de plaintext no evento e no log; least privilege verificado.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, bloqueio antes de mutar o runtime provado, Critical/High = 0.
