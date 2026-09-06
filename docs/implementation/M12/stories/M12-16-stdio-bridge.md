# M12-16 — Optional stdio bridge

## Objective
Atender hosts que ainda não suportam MCP remoto com OAuth adequadamente, sem abrir mão do modelo de segurança do endpoint remoto.

## Outcome
Um binário `platform-mcp` roda localmente, fala stdio com o host e HTTPS autenticado com o Control Plane — sendo apenas um tradutor.

## References
- `docs/annexes/F-mcp-platform-agents.md` §3.1 (transporte local via bridge, não como servidor principal), §4.3 (bridge stdio opcional), §22 (AC-MCP-15)

## Preconditions
`M12-06` done.

## Scope
- Binário/CLI `platform-mcp` distribuído pela plataforma, versionado.
- Host inicia o processo por stdio; a bridge autentica no Control Plane remoto e **apenas traduz** stdio ↔ HTTPS.
- Tokens armazenados no **keychain do sistema operacional**, nunca em arquivo plaintext por padrão.
- Fluxo de autenticação iniciando o consentimento OAuth no navegador.
- Verificação de versão da bridge contra o servidor, com aviso de incompatibilidade.

## Out of Scope
- Bridge como servidor MCP principal — explicitamente **não** (Anexo F §3.1).
- Modo offline.
- Distribuição em gerenciadores de pacote de terceiros.

## Security Requirements
- **A bridge apenas traduz**: nenhuma lógica de autorização, nenhuma regra de negócio, nenhum cache de decisão. Toda decisão continua no Gateway.
- **Tokens no keychain do SO**, nunca em arquivo plaintext por padrão (Anexo F §4.3, regra explícita).
- A bridge não expõe porta de rede; ela fala stdio com o host local e HTTPS com o servidor.
- O binário é versionado e verificável; a distribuição é por HTTPS.
- Um token na bridge tem o mesmo escopo e a mesma expiração do fluxo remoto — nada é ampliado por rodar localmente.
- Revogar a conexão no servidor invalida a bridge imediatamente.
- A bridge não registra argumentos nem respostas em disco.

## Observability Requirements
Versão da bridge observada pelo servidor, para depreciação. Erros de compatibilidade explícitos.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Keychain indisponível | Falhar com instrução; **não** cair para arquivo plaintext silenciosamente. |
| Versão incompatível | Aviso claro com a versão exigida. |
| Conexão revogada no servidor | Bridge para de funcionar imediatamente. |
| Servidor inalcançável | Erro estruturado; a bridge não inventa resposta. |
| Token expirado | Refluxo de autenticação. |
| Tentativa de usar a bridge como servidor completo | Não suportado; documentado. |

## Acceptance Criteria
1. O binário `platform-mcp` existe, é versionado e distribuído por HTTPS.
2. A bridge fala stdio com o host e HTTPS autenticado com o Control Plane.
3. **A bridge apenas traduz**: nenhuma lógica de autorização nem cache de decisão, verificado por revisão e teste.
4. Tokens são armazenados no **keychain do SO**; keychain indisponível **falha com instrução**, sem cair para arquivo plaintext.
5. A bridge não expõe porta de rede.
6. O escopo e a expiração do token são os mesmos do fluxo remoto.
7. Revogar a conexão no servidor invalida a bridge imediatamente.
8. A bridge **não** registra argumentos nem respostas em disco.
9. Versão incompatível gera aviso claro com a versão exigida.
10. Servidor inalcançável produz erro estruturado; a bridge não inventa resposta.
11. Token expirado dispara novo fluxo de autenticação.
12. A documentação declara que a bridge não é o servidor principal.

## Required Tests
- **security**: token no keychain; ausência de fallback para plaintext; sem porta de rede; sem persistência de argumentos.
- **integration**: revogação invalidando; versão incompatível; servidor inalcançável.
- **contract**: tradução fiel stdio ↔ HTTPS.

## Quality Gates
Local Quality Gate + `bin/security`.

## Definition of Done
Os 12 Acceptance Criteria satisfeitos, ausência de fallback para plaintext provada, bridge sem lógica própria verificada, Critical/High = 0.
