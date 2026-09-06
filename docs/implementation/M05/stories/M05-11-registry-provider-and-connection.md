# M05-11 — Registry provider abstraction and connection

## Objective
Tornar o Registry uma fronteira explícita entre build e runtime distribuído, com credenciais no Vault, escopo mínimo e teste de pull a partir dos nodes.

## Outcome
O Team conecta um Registry OCI; a plataforma testa push e pull; o builder publica com credencial escopada e de vida curta, e os workers conseguem baixar por digest.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §12 (Registry Provider), §12.2 (modos)
- `docs/architecture/02-build-deploy.md` §9 (registry e artefatos imutáveis)
- `docs/annexes/C-threat-model-security-hardening.md` §11 (supply chain), §2 (registry credentials = ALTO)
- `docs/annexes/D-test-strategy.md` §6.3 (contract de Registry)

## Preconditions
M03 aceito. Registry OCI acessível.

## Scope
- `RegistryConnection`: teamId, providerType, registryUrl, `ProviderCredentialBinding` para `SecretVersion`, status.
- Contrato de Registry: push, pull, manifest, resolução de digest, autenticação.
- Modos do doc 06 §12.2: registry externo (GHCR, Docker Hub, GitLab, compatível) ou registry privado do cliente.
- **Teste de conectividade por node**: um worker consegue fazer pull de um digest conhecido — é o que garante que o cluster inteiro pode executar o artefato.
- Credencial de **push** para o builder: escopada ao namespace/repositório e de vida curta quando o provider permitir.
- Credencial de **pull** para os workers, distribuída pelo caminho seguro do Swarm.

## Out of Scope
- Registry gerenciado pela própria plataforma (doc 06 §12.2 marca como futuro).
- Mirror de imagens críticas (doc 05 §8.1, opcional futuro).
- Retenção e GC de artefatos (`M06-13`).
- Scanning de vulnerabilidade (M13).

## Domain Impact
`RegistryConnection`, `ProviderCredentialBinding`.

## Application Layer
- **Commands:** `ConnectRegistry`, `TestRegistryConnection`.
- **Providers:** adapter de Registry com erros normalizados.

## Security Requirements
- Credencial de Registry é ativo **ALTO** (Anexo C §2): comprometê-la permite ler e publicar imagens, abrindo supply-chain compromise.
- Credencial vive no Vault; **nunca** é retornada ao frontend após a criação (doc 04 §9).
- **Push e pull separados**: o builder recebe credencial de push escopada; os workers recebem apenas pull. Um builder comprometido não deve poder ler imagens de outros Teams.
- A credencial de push é de vida curta quando o provider permitir.
- A URL do registry passa pela política de SSRF.
- Rotação de credencial suportada sem recriar a conexão.
- Falha de autenticação distinguível de falha de permissão e de indisponibilidade.

## Observability Requirements
- Estado da conexão: última verificação, resultado de push e de pull.
- Métrica: erros de push/pull por classe, latência.
- Teste de pull por node registrado com o resultado por node.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Registry indisponível | Workloads em execução continuam; novos deploys/pulls bloqueiam com causa (Anexo B §14, RB-13). |
| Credencial inválida | Erro classificado; a UI oferece reconectar. |
| Escopo insuficiente para push | Erro distinto de autenticação. |
| Node sem acesso ao registry | Teste de pull por node falha nomeando o node; o cluster não é considerado pronto para aquele artefato. |
| URL apontando para rede interna | Bloqueada por SSRF. |
| Rate limit do registry | Backoff; registrar; não insistir agressivamente. |

## Acceptance Criteria
1. `RegistryConnection` existe com credencial em `SecretVersion` do Vault.
2. A credencial nunca é retornada ao frontend após a criação.
3. Push e pull usam credenciais **separadas** e escopadas; o builder não recebe credencial de leitura ampla.
4. A credencial de push é de vida curta quando o provider permitir.
5. O teste de conectividade valida push **e** pull, e o pull é testado **a partir de um node de runtime**.
6. Node sem acesso é reportado nominalmente.
7. A URL do registry passa pela política de SSRF.
8. Falha de autenticação, de permissão e de indisponibilidade são erros distintos.
9. Rate limit leva a backoff, sem insistência.
10. A credencial pode ser rotacionada sem recriar a conexão.
11. Conectar, testar e rotacionar geram AuditLog; negativo cross-team passa.
12. Registry indisponível não derruba workloads em execução.

## Required Tests
- **contract**: push, pull, manifest, digest, auth, not found, rate limit.
- **integration**: rotação de credencial; erros distintos; backoff.
- **Docker/Swarm**: pull por digest a partir de um node de runtime.
- **security**: SSRF na URL; separação de escopo push/pull; credencial ausente da resposta.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + contract tests + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, pull por node validado, separação push/pull provada, Critical/High = 0.
