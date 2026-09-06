# M05-16 — Adversarial build corpus proving builder isolation

## Objective
Provar, com fixtures que **tentam ativamente escapar**, que o isolamento do builder funciona — em vez de confiar que a configuração está correta.

## Outcome
Um corpus versionado de repositórios maliciosos roda no Build Lab; cada tentativa de alcançar socket, manager, Vault, metadata ou rede interna é bloqueada e **registrada**.

## References
- `docs/annexes/C-threat-model-security-hardening.md` §10 (build plane), §21 (security testing: “repo malicioso de fixture”), T03 (**CRITICAL**), §26 (critério de aceite: “build malicioso de fixture não consegue acessar runtime secrets, manager ou host socket”)
- `docs/annexes/D-test-strategy.md` §8 (malicious build), §8.1 (corpus como dependência do produto), §17 (builder isolation)
- `docs/architecture/02-build-deploy.md` §7

## Preconditions
`M05-10` e `M05-15` done.

## Scope
Corpus **versionado** de fixtures adversariais, cada uma tentando uma técnica concreta:

| Fixture | Tenta |
|---|---|
| `socket-probe` | Encontrar e usar `/var/run/docker.sock`. |
| `manager-reach` | Alcançar as portas do Swarm (2377/7946/4789) e a rede de manager. |
| `metadata-exfil` | Acessar endpoints de metadata de cloud (link-local). |
| `internal-scan` | Varrer RFC1918/ULA e loopback. |
| `vault-reach` | Alcançar o Control Plane ou o Vault a partir do builder. |
| `secret-echo` | Ecoar o build secret para stdout, layer, `history` e metadata. |
| `resource-bomb` | Consumir CPU/memória/pids/disco além do limite. |
| `time-bomb` | Rodar além do deadline. |
| `persistence` | Deixar processo, arquivo ou cache para o build seguinte. |
| `cache-poison` | Envenenar o cache de outro Service/Team. |
| `path-escape` | Escapar do `rootDir` via `rootDir`/`dockerfilePath`/symlink. |
| `log-injection` | Injetar sequência de escape/HTML/prompt no log de build. |

Cada fixture tem uma **asserção positiva**: a tentativa é bloqueada **e** registrada.

## Out of Scope
- Escape de container por zero-day — fora do que a arquitetura promete mitigar (Anexo C §24, risco residual declarado).
- Tenancy hostil (T2 do Anexo C §9.1) — **não é GA**; o corpus não valida esse cenário.
- Pentest externo (M13/M14).

## Application Layer
Nenhuma. Esta Story é de verificação. Se uma fixture passar, a correção vai para a Story do controle correspondente (`M05-07`, `M05-10`, `M05-13`), não para cá.

## Security Requirements
Esta Story **é** o critério de aceite de segurança do build plane (Anexo C §26):
- Nenhuma fixture pode alcançar o `docker.sock` do cluster, a rede de manager, o Vault de runtime, endpoints de metadata ou ranges internos.
- Nenhuma fixture pode fazer o build secret persistir na imagem.
- Nenhuma fixture pode deixar resíduo para o build seguinte.
- Nenhuma fixture pode envenenar cache de outro Service ou Team.
- Toda tentativa bloqueada é **registrada**, porque em produção esse registro é o sinal de repositório comprometido.
- **Se qualquer fixture conseguir escapar, o Milestone para**: é incidente de segurança, marcado `blocked`, escalado para revisão humana. Contornar o teste é proibido explicitamente.

## Observability Requirements
Cada execução do corpus produz um relatório com: fixture, técnica, resultado esperado, resultado observado, e o registro do bloqueio. O relatório é evidência de release (Anexo D §24).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Fixture consegue escapar | **Parar.** Incidente de segurança; `blocked`; escalar. Nunca ajustar o teste para passar. |
| Fixture falha por motivo errado | Investigar: um bloqueio acidental não prova o controle. A asserção precisa verificar **como** foi bloqueado. |
| Corpus fica desatualizado | Novo controle exige nova fixture; o corpus é dependência do produto, não exemplo descartável. |
| Build Lab indisponível | `BLOCKED_EXTERNAL_DEPENDENCY`; **não** marcar o Milestone como pronto sem o corpus. |

## Acceptance Criteria
1. O corpus é versionado no repositório e tratado como dependência do produto.
2. As 12 fixtures da tabela existem e executam no Build Lab.
3. Nenhuma fixture alcança o `docker.sock` do cluster.
4. Nenhuma fixture alcança a rede de manager ou as portas do Swarm.
5. Nenhuma fixture alcança endpoints de metadata ou ranges internos.
6. Nenhuma fixture alcança o Control Plane ou o Vault.
7. Nenhuma fixture faz o build secret persistir na imagem, em layer, em `history` ou em metadata.
8. Nenhuma fixture excede os limites de recurso ou de tempo sem ser morta.
9. Nenhuma fixture deixa resíduo para o build seguinte.
10. Nenhuma fixture envenena cache de outro Service ou Team.
11. Nenhuma fixture escapa do `rootDir`.
12. A injeção de log é sanitizada e não é renderizada como ativo.
13. **Cada bloqueio é registrado**, e a asserção verifica o mecanismo, não apenas o resultado.
14. O relatório do corpus é arquivado como evidência de release.

## Required Tests
Esta Story **é** a suíte. Ela roda no Build Lab e integra o Merge Gate e o Release Gate.

## Quality Gates
Build Lab + `bin/security`. **Gate humano:** o resultado deste corpus é parte da revisão de segurança do Exit Gate de M05.

## Definition of Done
Os 14 Acceptance Criteria satisfeitos, corpus completo verde com o mecanismo de bloqueio verificado em cada caso, relatório arquivado, Critical/High = 0.
