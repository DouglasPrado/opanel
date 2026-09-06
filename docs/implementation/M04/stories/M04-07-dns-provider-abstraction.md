# M04-07 — DnsProvider abstraction and first adapter

## Objective
Isolar a automação de DNS atrás de um contrato provider-agnostic, com credenciais no Vault e proteção rigorosa contra SSRF.

## Outcome
A plataforma cria e remove registros DNS na zona controlada através de um adapter, com credencial de escopo mínimo vinda do Vault e erros normalizados.

## References
- `docs/architecture/08-networking-domains-edge.md` §11 (DNS Provider)
- `docs/architecture/06-infrastructure-provisioning.md` §11 (DNS Provider), §11.2 (credenciais)
- `docs/annexes/C-threat-model-security-hardening.md` §13 (integrações externas), §13.1 (SSRF baseline), T11
- `docs/annexes/D-test-strategy.md` §6.3 (provider contracts)

## Preconditions
M03 aceito (credenciais no Vault).

## Scope
- Contrato `DnsProvider`: `listZones`, `ensureRecord`, `deleteRecord`, `createAcmeTxt`, `waitPropagation`.
- `ProviderConnection` + `ProviderCredentialBinding` apontando para `SecretVersion` — credencial **nunca** duplicada em JSON de provider (doc 09 §12).
- Primeiro adapter concreto, com normalização de erros para o modelo estável.
- Teste de permissão da conexão (“permissions test” do doc 10 §22) sem alterar dados.
- Timeout, retry com jitter e circuit breaker (Anexo C §13).
- **Proteção SSRF** em toda chamada saída e em qualquer URL configurável.

## Out of Scope
- Zonas de domínios de cliente (`M07-03`).
- Providers adicionais — o contrato permite; cada um é Story própria quando houver necessidade.
- LB provider (`M08-10`) e Registry provider (`M05-11`), que seguem o mesmo padrão.

## Domain Impact
`ProviderConnection`, `ProviderCredentialBinding`, `DnsConnection`.

## Application Layer
- **Commands:** `ConnectDnsProvider`, `TestDnsProviderConnection`.
- **Providers:** adapter isolando a API externa e normalizando erros; nenhum SDK vaza para o domínio.

## Security Requirements
- **Token com o menor escopo possível**, idealmente restrito à zona necessária (Anexo C §14.1).
- Credencial vive no Vault como `SecretVersion`; **nunca** é retornada ao frontend após a criação (doc 06 §11.2).
- **SSRF** (Anexo C §13.1): bloquear loopback, link-local, RFC1918/ULA e endpoints de metadata; resolver DNS e validar o IP final; tratar redirect como nova decisão de policy; recusar schemes inesperados.
- Erros do provider são normalizados e **não** vazam a resposta bruta, que pode conter dados de outras zonas.
- Rotação da credencial é suportada sem recriar a conexão.
- Falha de autenticação é distinguível de falha de permissão, para diagnóstico — sem revelar detalhes do provider.

## Observability Requirements
- Métrica: chamadas por provider, latência, erros por classe, circuit breaker aberto.
- AuditLog para conexão criada, testada, rotacionada e removida.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Provider indisponível | Circuit breaker abre; domínios já ativos continuam roteando (Anexo B §14). |
| Credencial inválida/expirada | Erro classificado; a UI mostra “reconectar”, sem detalhes do provider. |
| Escopo insuficiente | Erro distinto de autenticação, para diagnóstico correto. |
| URL de endpoint apontando para rede interna | Bloqueada pela política de SSRF. |
| Redirect para host interno | Bloqueado — o redirect é nova decisão de policy. |
| Propagação lenta | `waitPropagation` com timeout; não bloquear indefinidamente. |

## Acceptance Criteria
1. O contrato `DnsProvider` existe com as cinco operações e é implementado por um adapter concreto.
2. A credencial vive no Vault como `SecretVersion` e nunca é retornada ao frontend após a criação.
3. O teste de conexão valida permissões sem alterar dados.
4. Toda chamada de saída passa pela política de SSRF: loopback, link-local, RFC1918/ULA e metadata bloqueados, provado por teste.
5. Redirect para host interno é bloqueado, provado por teste.
6. Scheme inesperado é recusado.
7. Erros do provider são normalizados; a resposta bruta não vaza.
8. Falha de autenticação é distinguível de escopo insuficiente.
9. Circuit breaker abre sob falha contínua e domínios ativos continuam roteando.
10. `waitPropagation` respeita timeout e não bloqueia indefinidamente.
11. A credencial pode ser rotacionada sem recriar a conexão.
12. Conexão, teste e rotação geram AuditLog; negativo cross-team passa.

## Required Tests
- **contract**: create/update/delete de TXT/A/AAAA/CNAME; propagação; conflito; not found; rate limit.
- **security**: bateria de SSRF (loopback, link-local, RFC1918, metadata, redirect, scheme); credencial ausente da resposta.
- **integration**: circuit breaker; rotação de credencial; erro normalizado.
- **policy**: negativo cross-team.

## Quality Gates
Local Quality Gate + contract tests + `bin/security`. **Story crítica: exige plan mode** (superfície SSRF).

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, bateria de SSRF verde, credencial protegida, Critical/High = 0.
