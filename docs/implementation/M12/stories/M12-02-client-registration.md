# M12-02 — MCP client registration

## Objective
Identificar clientes MCP de forma verificável, preferindo Client ID Metadata Documents a registro dinâmico irrestrito.

## Outcome
Um cliente é identificado pelo seu documento de metadata; o fetch desse documento é protegido contra SSRF; o administrador vê quais clientes se conectam.

## References
- `docs/annexes/F-mcp-platform-agents.md` §5.2 (registro de clientes), §13 (`McpClientProfile`)
- `docs/annexes/C-threat-model-security-hardening.md` §13.1 (SSRF), §13 (callback URLs)

## Preconditions
`M12-01` done.

## Scope
- Preferência por **Client ID Metadata Documents** / pré-registro.
- Dynamic Client Registration apenas como compatibilidade, quando necessário, e com restrições.
- `McpClientProfile`: client id/name, URL de metadata, versões de protocolo observadas, notas de confiança.
- **Fetch de metadata protegido contra SSRF**.
- Allowlist opcional de clientes por instalação, controlada pelo `INSTANCE_ADMIN`.

## Out of Scope
- Certificação de clientes.
- Marketplace de agentes.

## Security Requirements
- **O servidor de autorização deve proteger qualquer fetch de metadata contra SSRF** (Anexo F §5.2, regra explícita): bloquear loopback, link-local, RFC1918/ULA e metadata endpoints; validar o IP final; tratar redirect como nova decisão.
- O documento de metadata é **dado não confiável**: validado contra schema, com limite de tamanho e de tempo.
- O nome do cliente exibido na tela de consentimento é sanitizado — um nome forjado pode induzir o usuário a autorizar mais do que pretende.
- Dynamic Client Registration, quando habilitado, é restrito e auditado.
- A allowlist por instalação permite bloquear clientes desconhecidos em ambientes sensíveis.
- Registro e alteração geram AuditLog.

## Observability Requirements
Clientes observados, com versões de protocolo e volume de uso — insumo para depreciação (Anexo F §19).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| URL de metadata apontando para rede interna | Bloqueada por SSRF. |
| Redirect para host interno | Bloqueado. |
| Documento inválido ou gigante | Rejeitado por schema e limite. |
| Nome de cliente com conteúdo enganoso | Sanitizado na tela de consentimento. |
| Cliente fora da allowlist | Conexão recusada com erro claro. |
| DCR habilitado sem restrição | Não permitido: sempre restrito e auditado. |

## Acceptance Criteria
1. Client ID Metadata Documents / pré-registro é o caminho preferido.
2. O fetch de metadata passa pela **política de SSRF**, provado por bateria de testes.
3. Redirect para host interno é bloqueado.
4. O documento é validado contra schema, com limite de tamanho e de tempo.
5. O nome do cliente é **sanitizado** na tela de consentimento.
6. Dynamic Client Registration, quando habilitado, é restrito e auditado.
7. A allowlist de clientes por instalação existe e é controlada pelo `INSTANCE_ADMIN`.
8. Cliente fora da allowlist recebe erro claro na conexão.
9. `McpClientProfile` registra client id/name, URL, versões observadas e notas.
10. Registro e alteração geram AuditLog.
11. As versões de protocolo observadas são consultáveis para decisão de depreciação.

## Required Tests
- **security**: bateria de SSRF no fetch; redirect; documento gigante; nome enganoso sanitizado.
- **integration**: allowlist bloqueando; DCR restrito.
- **contract**: validação do documento de metadata.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, SSRF no fetch coberta, nome sanitizado, Critical/High = 0.
