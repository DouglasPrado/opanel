# M13-03 — Adversarial builder isolation suite

## Objective

Estender o corpus adversarial de `M05-16` e provar que código de build hostil não alcança o Docker socket, o Manager, o Vault, o metadata do provider nem a rede interna do Control Plane.

## Outcome

Um corpus versionado de fixtures hostis que roda contra o builder real; nenhuma delas escapa.

## References

- `docs/annexes/C-threat-model-security-hardening.md` §6 (T03), §10, §10.1, §21
- `docs/architecture/02-build-deploy.md` — isolamento do builder
- `docs/annexes/D-test-strategy.md` §8, §17

## Preconditions

- Builder isolado implementado em M05.
- Ambiente de laboratório dedicado; **nunca** produção.

## Scope

- Fixtures que tentam: montar ou alcançar `/var/run/docker.sock`; conectar ao Manager na porta do Swarm; ler `169.254.169.254`; alcançar o PostgreSQL do Control Plane; ler o Vault; escrever fora do workspace; escapar por symlink ou path traversal; abusar de cache compartilhado entre Teams; exaurir CPU, memória, disco e PIDs; abrir conexão de saída para host arbitrário.
- Verificação de que o build roda em nó **worker rotulado**, nunca em manager.
- Verificação de que credenciais de push não ficam disponíveis ao código do usuário.
- Verificação de que o cache é isolado por escopo e não vaza conteúdo entre Teams.
- Limites de recurso e timeout efetivos, com o build sendo morto — não o nó.

## Out of Scope

- Escape de kernel/container runtime: fora do controle da plataforma; mitigado por versão e documentado como risco residual.

## Security Requirements

- Uma fixture que **consiga** escapar é incidente de segurança: parar a suíte, escalar, não “ajustar o teste”.
- Os artefatos de teste hostis ficam claramente marcados e não são executáveis fora do laboratório.
- Logs de build hostil passam pela mesma redaction dos demais.

## Observability Requirements

- Relatório por fixture: tentativa, resultado, mecanismo de bloqueio observado.
- Métrica de builds mortos por limite, separada de builds com falha de compilação.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Fixture alcança o socket | Incidente **Critical**; parar e escalar. |
| Build agendado em manager | Finding **Critical**. |
| Credencial de push legível pelo build | Finding **Critical**. |
| Cache vaza entre Teams | Finding **High**. |
| Exaustão derruba o nó | Finding **High**; limites insuficientes. |

## Acceptance Criteria

1. Nenhuma fixture alcança socket, manager, Vault, metadata ou rede interna.
2. Builds são agendados apenas em workers rotulados como builder.
3. Credenciais de push não são acessíveis ao código do usuário.
4. Cache é isolado por escopo, sem vazamento entre Teams.
5. Limites de CPU, memória, disco e PIDs matam o build sem afetar o nó.
6. Timeout encerra o build de forma determinística.
7. Path traversal e symlink não escrevem fora do workspace.
8. O corpus é versionado e cada fixture tem resultado esperado explícito.
9. A suíte roda apenas em laboratório dedicado.

## Required Tests

- Docker/Swarm integration com o builder real.
- Testes de limite de recurso com medição.

## Quality Gates

Local Quality Gate; AF-02 (apenas o Swarm Executor referencia o socket).

## Definition of Done

- [ ] 9 Acceptance Criteria com evidência.
- [ ] Nenhuma fixture escapou.
- [ ] Relatório arquivado por fixture.
- [ ] Self-review; `tasks.json` atualizado com commit.
