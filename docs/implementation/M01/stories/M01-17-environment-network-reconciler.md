# M01-17 — Environment overlay network and Network Reconciler

## Objective
Dar a cada Environment sua própria overlay network, tornando o isolamento entre production e homologação uma **consequência da topologia** — não uma convenção de nome.

## Outcome
Criar um Environment gera uma Operation que cria a overlay network correspondente; a network aparece com labels de ownership; o Environment converge para `READY` só depois da confirmação no runtime.

## References
- `docs/architecture/01-foundation.md` §5.3 (isolamento de environments)
- `docs/architecture/08-networking-domains-edge.md` §4.1 (uma rede por Environment), §5 (naming), §6 (service discovery interno)
- `docs/architecture/09-data-model-apis-contracts.md` §11.1 (Network)
- `docs/architecture/07-internal-control-plane.md` §11.3 (algoritmo de reconcile), §11.4 (classes de diff)

## Preconditions
`M01-14`, `M01-15` e `M01-16` done.

## Scope
- `Network`: id, environmentId, clusterId, swarmNetworkId, name (determinístico por IDs), driver (`overlay`), encrypted (intenção registrada), status (`PROVISIONING`, `READY`, `DEGRADED`, `DELETING`), desiredRevision/appliedRevision.
- **Network Reconciler** seguindo o algoritmo do doc 07 §11.3: adquirir lease → carregar desired → inspecionar actual → calcular diff **sem efeito colateral** → aplicar a menor mutação segura → **re-inspecionar** → persistir resultado → liberar lease.
- Classes de diff aplicáveis: `NOOP`, `CREATE`, `DELETE`, `BLOCKED`.
- Criação de Environment passa a gerar Operation `CREATE_NETWORK`.
- `Environment.appliedRevision` avança apenas após confirmação no runtime.

## Out of Scope
- Rede de ingress e attachment do Traefik (`M04-02`).
- IPAM próprio e CIDR previsível (doc 08 §5 marca como evolução; não é requisito agora).
- Overlay encryption ativada (registrar a intenção basta; ligar tem custo de performance e exige decisão).
- Remoção de network no ciclo de deleção completo (`M02-09`).

## Domain Impact
**Entidade:** `Network`.
**Invariante:** um Environment tem pelo menos uma overlay dedicada; Services de Environments diferentes **não** compartilham rede de aplicação por padrão.

## Application Layer
- **Commands:** `EnsureEnvironmentNetwork`.
- **Queries:** `NetworkForEnvironment`.
- **Reconciler:** `NetworkReconciler`.

## Async / Control Plane
Primeira aplicação real do ciclo completo `Desired State → Operation → Lease → Executor → Re-inspect → appliedRevision`. Ela existe antes do Service Reconciler porque a network é pré-requisito do Service e porque é um recurso mais simples — o lugar certo para provar o algoritmo.

O reconciler **nunca** escreve colunas de intenção do usuário (AF-03).

## Security Requirements
- Isolamento entre Environments é um controle de segurança (Anexo C §14, “Prod acessando HML”): sem attachment cruzado por padrão.
- A network recebe labels de ownership de `M01-16`.
- Nenhum Service publica porta pública nesta Story; a exposição só existe a partir de M04.
- O reconciler não adota network preexistente sem ownership da plataforma.

## Observability Requirements
- `ReconciliationRun` persistido por execução: recurso, trigger, diff calculado, ações aplicadas, resultado, timestamps.
- Logs com `environment_id`, `cluster_id`, `operation_id`.
- Meta do Anexo B §5: detecção da mudança desejada ≤ 2 s após o commit.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Criação da network falha | Environment fica `DEGRADED` com retry; **não** desaparece nem finge estar `READY` (doc 10 UC-010). |
| Network já existe com ownership da plataforma | `NOOP`; `appliedRevision` avança. |
| Network já existe **sem** ownership | `BLOCKED` com diagnóstico; nunca adotar automaticamente. |
| Resposta do Docker perdida | Re-inspeção decide; nunca repetir criação às cegas. |
| Conflito de CIDR | `BLOCKED` com causa; o doc 08 §5 exige detectar conflito antes de aplicar. |
| Lease expira no meio | Sucessor reobserva antes de agir; nenhum recurso duplicado. |

## Acceptance Criteria
1. Criar um Environment gera Operation e resulta em uma overlay network real no Swarm.
2. A network carrega as labels de ownership e o nome determinístico por IDs.
3. `Environment.appliedRevision` só avança após a confirmação por re-inspeção do runtime.
4. Executar o reconciler duas vezes é idempotente: a segunda execução resulta em `NOOP`.
5. Uma network preexistente **com** ownership da plataforma é reconhecida (`NOOP`), não recriada.
6. Uma network preexistente **sem** ownership resulta em `BLOCKED` com diagnóstico, nunca adoção.
7. Falha de criação deixa o Environment `DEGRADED` com retry, e a UI mostra a causa.
8. Services de Environments diferentes não compartilham rede, provado contra Swarm real.
9. O reconciler não escreve nenhuma coluna de intenção do usuário, garantido por AF-03.
10. Cada execução persiste um `ReconciliationRun` com o diff e as ações.
11. Uma resposta perdida do Docker leva a re-inspeção, não a nova tentativa cega de criação.
12. O lease é respeitado: um sucessor após expiração reobserva antes de agir.

## Required Tests
- **unit**: cálculo de diff sem efeito colateral; classificação `NOOP`/`CREATE`/`BLOCKED`.
- **integration**: `appliedRevision` avançando só após confirmação; `ReconciliationRun` persistido.
- **Docker/Swarm**: criação real; idempotência; network sem ownership bloqueando; isolamento entre dois Environments.
- **security**: AF-03; ausência de adoção automática.

## Quality Gates
Local Quality Gate + `bin/fitness` (AF-03 significativa) + suíte Docker/Swarm.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos contra Swarm real, idempotência e isolamento provados, AF-03 avaliando código real, Critical/High = 0.
