# M05-07 — Isolated builder pool

## Objective
Executar builds em infraestrutura tratada como **sandbox temporária**, sem acesso ao cluster, ao Vault de runtime ou aos Managers — porque o build executa código arbitrário.

## Outcome
Builds rodam em builder nodes dedicados, sem `docker.sock` do cluster, com egress restrito, limites de recurso e workspace efêmero.

## References
- `docs/architecture/02-build-deploy.md` §7 (isolamento e segurança dos builders), §7.1 (regras obrigatórias), §7.2 (builder pool)
- `docs/annexes/C-threat-model-security-hardening.md` §10 (build plane e código não confiável), T03 (**CRITICAL**)
- `docs/annexes/B-nfr-slos.md` §7 (isolamento), §10 (builders dedicados)
- `docs/architecture/06-infrastructure-provisioning.md` §1.2 (papel Builder)

## Preconditions
`M05-06` done. Ao menos um node com label de builder disponível (em M05 pode ser um node existente rotulado; `M08-04` formaliza o provisionamento).

## Scope
- Seleção de builder saudável com capacidade, pela própria plataforma (doc 02 §7.2).
- **Builds não executam em Manager nodes** quando há builder dedicado.
- Daemon BuildKit isolado no builder, **sem** o `docker.sock` do cluster.
- Limites obrigatórios: CPU, memória, pids, disco e **tempo máximo**.
- Egress restrito por policy: bloquear loopback, link-local, RFC1918/ULA e endpoints de metadata; permitir o necessário para registries de pacotes e para o Registry OCI.
- Workspace temporário, único por build, destruído ao final.
- Nenhuma credencial administrativa do cluster e **nenhum** secret de runtime no builder.
- Registro da versão de BuildKit/Railpack usada, para a suíte de compatibilidade de `M13-12`.

## Out of Scope
- Provisionamento de builder por enrollment (`M08-04`).
- Corpus adversarial (`M05-16`) — esta Story cria os controles; aquela os **prova**.
- Rootless BuildKit / gVisor / microVM: o doc 02 §7.1 os menciona “conforme maturidade e modelo multi-tenant”, e o Anexo C §9.1 os exige apenas para tenancy hostil (T2), que **não** é GA. Registrado como evolução, não implementado aqui.

## Application Layer
- **Commands:** `ScheduleBuild` (seleção de builder).
- **Queries:** `BuilderCapacity`.

## Security Requirements
Esta Story implementa a mitigação de **T03, classificado CRITICAL** no Anexo C §6:
- **Sem `docker.sock` do cluster** no builder. O BuildKit tem seu próprio daemon isolado.
- **Sem Vault de runtime**: o builder nunca recebe secrets de aplicação.
- **Sem credencial administrativa** do cluster; a credencial de push é escopada e de vida curta (`M05-11`).
- **Não rodar em Managers**: um build malicioso em um Manager equivale a comprometimento do cluster.
- **Egress limitado**: metadata de cloud, loopback, link-local e RFC1918/ULA bloqueados. Este é o vetor de exfiltração mais direto.
- Limites de CPU/memória/pids/disco/tempo contra cryptomining e DoS (Anexo C §10, “Cryptomining/DoS”).
- Workspace destruído após sucesso e falha; nada persiste entre builds além do cache namespaced.
- Nenhum host mount sensível.

## Observability Requirements
- Capacidade e saúde do pool de builders.
- Por build: builder escolhido, recursos consumidos, duração.
- Tentativas de egress bloqueadas **registradas** — é sinal de repositório comprometido.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Nenhum builder saudável | Build fica na fila com causa; **nunca** cair para um Manager. |
| Builder saturado | Backpressure; alerta de espera na fila. |
| Build excede tempo/recursos | Morto; workspace limpo; `TIMED_OUT` ou `FAILED` com causa. |
| Builder comprometido | RB-14/Anexo C: isolar, revogar credenciais temporárias, preservar audit e reprovisionar. |
| Tentativa de acesso a metadata | Bloqueada e **registrada**. |
| Workspace não limpo por crash | Job de limpeza remove órfãos; teste comprova idempotência. |

## Acceptance Criteria
1. Builds executam em builder nodes dedicados; com builder disponível, **nunca** em Manager, provado por teste.
2. Sem builder saudável, o build espera com causa; não há fallback para Manager.
3. O builder **não** tem acesso ao `docker.sock` do cluster, provado por teste.
4. O builder **não** tem acesso ao Vault de runtime nem a credencial administrativa do cluster.
5. Limites de CPU, memória, pids, disco e tempo são aplicados; build excedido é morto.
6. Egress é restrito: metadata, loopback, link-local e RFC1918/ULA bloqueados, provado por teste.
7. Tentativas de egress bloqueadas são registradas.
8. O workspace é único por build e destruído após sucesso **e** falha.
9. Workspace órfão de crash é removido por job idempotente.
10. Nenhum host mount sensível é concedido ao builder.
11. A versão de BuildKit/Railpack está registrada em arquivo versionado.
12. A capacidade e a saúde do pool são observáveis.

## Required Tests
- **unit**: seleção de builder; aplicação de limites.
- **integration**: workspace destruído em sucesso e falha; limpeza de órfão.
- **Build Lab**: build real em builder isolado; build excedendo tempo/recursos morto.
- **security**: ausência de `docker.sock`; ausência de Vault; bloqueio de egress para metadata e ranges internos; ausência de fallback para Manager.

## Quality Gates
Local Quality Gate + Build Lab + `bin/security`. **Story crítica: exige plan mode** — mitiga T03 (CRITICAL).

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, isolamento provado por teste direto, egress bloqueado e registrado, Critical/High = 0.
