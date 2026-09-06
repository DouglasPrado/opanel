# M03-07 — Swarm Secret materialization with least privilege

## Objective
Entregar o valor da secret ao workload através de Docker Swarm Secrets, decifrando apenas durante a operação autorizada e anexando somente ao Service que tem o binding.

## Outcome
Um container autorizado lê o valor em `/run/secrets/<targetName>`; um Service sem binding **não** recebe a secret; a decifra acontece apenas no boundary autorizado.

## References
- `docs/architecture/01-foundation.md` §10 (segurança e distribuição das secrets), §10.3 (fluxo completo)
- `docs/architecture/07-internal-control-plane.md` §11.1 (Secret Reconciler)
- `docs/architecture/08-networking-domains-edge.md` §5 (naming `vault_<secretVersionId>`)
- `docs/annexes/C-threat-model-security-hardening.md` §12 (distribuição), T05

## Preconditions
`M03-06` done.

## Scope
- `SecretReconciler`: materializa `SecretVersion` como Docker Swarm Secret e mantém os bindings corretos.
- Nome técnico determinístico derivado do `secretVersionId` (doc 08 §5), com labels de ownership de `M01-16`.
- Anexação ao Service com `targetName` e modo de injeção; `SECRET_FILE` como padrão.
- Modo `ENVIRONMENT` por compatibilidade: entrypoint controlado lê `/run/secrets` e exporta apenas para o processo filho imediatamente antes do exec (doc 01 §10.2).
- Rotação de versão: nova Swarm Secret, atualização do Service, remoção segura da anterior quando não referenciada.
- Decifra **apenas** no boundary autorizado, em memória, durante a operação.

## Out of Scope
- Promoção entre Environments (`M03-08`).
- Reveal para humano (`M03-09`).
- Secrets de provider (M05, M10) — reutilizam este mecanismo depois.
- Rotação automática por política de tempo — sem requisito.

## Application Layer
- **Reconciler:** `SecretReconciler`.
- **Executor:** `CreateSecret`, `RemoveSecret`, `UpdateServiceSpec` com referências.
- **Operations:** `MATERIALIZE_SECRET`, `ROTATE_SECRET_BINDING`.

## Async / Control Plane
Materializar é reconciliação: desired (bindings) × actual (secrets anexadas no Swarm) → diff → aplicar → re-inspecionar. Mudança de binding é `ROLLOUT`, porque recria Tasks.

## Security Requirements
Esta é a Story de maior risco do Milestone:
- **Least privilege**: a Swarm Secret é anexada **somente** aos Services com binding correspondente. Um Service sem binding não a recebe — testado contra Swarm real.
- O plaintext existe apenas **em memória**, no boundary autorizado, durante a operação. Nunca em disco do Control Plane, nunca em log, nunca em payload de Operation (que carrega apenas `secretVersionId`).
- `SECRET_FILE` é o padrão; `ENVIRONMENT` é compatibilidade com aviso, porque aumenta a exposição operacional (doc 01 §10.2).
- A remoção de uma Swarm Secret antiga só ocorre quando nenhum Service a referencia — remover cedo derruba workload.
- Somente o Swarm Executor cria/remove secrets no Docker.
- Nenhum workload de usuário recebe o socket, host mount ou privilégio que permita ler secrets de outros Services.

## Observability Requirements
- Log com `service_id`, `secret_id`, `secret_version_id` e `operation_id` — **nunca** o valor.
- Evento de materialização e de rotação, sem valores.
- Falha de materialização classificada e visível no status do Service.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Service sem binding tenta acessar | Não recebe a secret; teste obrigatório contra Swarm real. |
| Task movida para outro node | Recebe a versão correta via distribuição do Swarm; teste obrigatório. |
| `SecretVersion` indisponível | Bloquear o rollout **antes** de aplicar; nunca subir Task sem a secret esperada. |
| Remoção prematura da secret antiga | Impedida enquanto houver referência. |
| Falha na decifra | Operação falha classificada; nunca materializa valor parcial ou vazio. |
| Secret órfã no Swarm | Detectada pelo reconciler e removida somente se tiver ownership e não for referenciada. |

## Acceptance Criteria
1. Um container com binding lê o valor em `/run/secrets/<targetName>`, verificado contra Swarm real.
2. Um Service **sem** binding não recebe a secret, verificado contra Swarm real.
3. Uma Task movida para outro node recebe a versão correta da secret.
4. O plaintext não é gravado em disco do Control Plane, log, evento, payload de Operation ou audit, provado com valor plantado.
5. O payload da Operation carrega apenas `secretVersionId`.
6. `SECRET_FILE` é o padrão; `ENVIRONMENT` funciona e emite aviso explícito.
7. A Swarm Secret recebe nome determinístico por `secretVersionId` e labels de ownership.
8. `SecretVersion` indisponível bloqueia o rollout antes de aplicar.
9. A secret antiga só é removida quando nenhum Service a referencia.
10. Secret órfã com ownership da plataforma e sem referência é removida pelo reconciler; secret sem ownership é ignorada.
11. Falha na decifra resulta em operação falha classificada, sem materializar valor parcial.
12. Somente o Swarm Executor cria/remove secrets no Docker (AF-02).

## Required Tests
- **unit**: diff de bindings; decisão de remoção segura.
- **integration**: payload de Operation sem plaintext; bloqueio por versão indisponível.
- **Docker/Swarm**: leitura em `/run/secrets`; Service sem binding não recebe; Task movida entre nodes; rotação de versão; secret órfã.
- **security**: valor plantado ausente de todos os sinks; AF-02; workload sem socket/host mount.

## Quality Gates
Local Quality Gate + `bin/security` + `bin/fitness` + suíte Docker/Swarm. **Story crítica: exige plan mode.**

## Definition of Done
Os 12 Acceptance Criteria satisfeitos contra Swarm real, least privilege e ausência de plaintext provados, Critical/High = 0.
