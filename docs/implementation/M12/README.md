---
milestone: "M12"
name: "MCP & Agent Operations"
type: "milestone"
status: "pending"
---

# M12 — MCP & Agent Operations

## Identity

| Campo | Valor |
|---|---|
| **ID** | M12 |
| **Nome** | MCP & Agent Operations |
| **Objetivo** | Introduzir o **MCP oficial** da plataforma: um endpoint remoto OAuth-first que permite a um agente operar o Opanel por linguagem natural, com a mesma superfície funcional da UI e **nenhuma** autoridade adicional. |
| **Resultado observável** | Um usuário conecta um agente por OAuth, escolhe um preset e um resource boundary, e o agente cria projetos, dispara builds, acompanha Operations e faz deploy em homologação — enquanto produção permanece read-only e ações críticas exigem approval humano. |

## Why

O Anexo F é normativo: a plataforma será **agent-first**. Mas o Anexo G §18.1 é igualmente explícito sobre o **momento**: implementar MCP cedo demais força estabilizar tools sobre contratos instáveis e aumenta retrabalho.

Por isso M12 vem depois de M06 (delivery madura) e M11 (OAuth, scopes, service accounts). Nesse ponto, o Anexo F se torna principalmente **um adapter de protocolo** — que é exatamente o que ele deve ser.

A decisão central: o MCP é **mais um cliente do Control Plane**. Ele não aumenta a autoridade de quem o utiliza.

## Scope

- OAuth resource server: PKCE S256, resource indicators, validação estrita de issuer/audience.
- Registro de clientes por Client ID Metadata Documents, com fetch protegido contra SSRF.
- MCP Gateway **stateless**, JSON-RPC sobre HTTP, escalável horizontalmente sem sticky session.
- `AgentConnection`, `AgentPolicy` e `AgentResourceBoundary`.
- Presets de permissão (Observer, Developer, Deployer, Operator, Admin, Custom) e autorização efetiva.
- Catálogo de tools por fase de rollout F1→F5.
- Modelo de approvals para ações R2/R3, com digest binding e uso único.
- Resources e Prompts read-only.
- Auditoria, métricas e rate limiting específicos de MCP.
- UI de Agents & MCP: conexões, permissões, approvals, atividade e revogação.
- Bridge stdio opcional para hosts sem suporte a MCP remoto.

## Out of Scope

| Deixado para | O quê |
|---|---|
| Fora do produto | Shell genérica, docker.sock, Docker Engine API ou SSH via MCP (Anexo F §1.3). |
| Fora do produto | Permitir que o agente ignore approvals, RBAC, quotas ou políticas de produção. |
| Fora do produto | Duplicar regras de negócio dentro do servidor MCP. |
| M13 | Testes adversariais consolidados de prompt injection e enumeração cross-team. |
| Backlog | MCP Apps, tools de billing, extensões não suportadas pelo cliente. |

## Dependencies

- **Hard:** M06 (delivery), M11 (OAuth, scopes, service accounts, permissões por Environment).
- **Soft:** M09 (tools de observabilidade), M10 (tools de backup/restore).

## User-visible Outcome

O usuário adiciona a URL do MCP no seu host, autentica por OAuth, escolhe Team, escopo e preset. O agente descobre projetos e ambientes sem que ele copie IDs, sobe uma aplicação em homologação, acompanha a Operation até o fim e explica o resultado. Para promover para produção, o agente pede aprovação — e o humano decide.

## Technical Outcome

- Um endpoint HTTPS único, stateless, atrás do mesmo edge do produto.
- Toda mutação passa pelos mesmos Commands, Operations, Policies e auditoria da UI.
- `Operation` como contrato canônico para trabalho longo.
- Approval ligado ao **digest da ação**: mudar argumentos invalida a aprovação.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `AgentConnection`, `AgentResourceBoundary`, `OAuthGrant`, `AgentPolicy`, `ApprovalRequest`, `McpExecutionAudit`, `McpClientProfile`. |
| Commands | Reuso integral dos Commands existentes — **nenhuma regra de negócio nova**. |
| Queries | Reuso dos read models existentes. |
| UI | Agents & MCP: conexões, wizard, permissões, approvals, atividade, segurança. |
| Infrastructure | Endpoint `/mcp` nas réplicas web ou em process type dedicado. |

## Security

O MCP é uma superfície de autoridade delegada. As invariantes do Anexo F §1.2:

- **Sem bypass**: o MCP não acessa Docker, Swarm, Registry, banco ou Vault diretamente; usa os Application Services.
- **Mesma autorização**: permissão efetiva = scopes OAuth ∩ RBAC ∩ resource boundary ∩ policy de Environment ∩ entitlement ∩ approval ∩ estado do recurso.
- **Desired State**: mutações alteram estado desejado e disparam Operation; o MCP não aplica patch ad hoc no runtime.
- **Auditável**: toda chamada registra ator humano, cliente MCP, tool, recurso, Operation, approval e resultado.
- **Least privilege**: produção pode ser read-only mesmo com write em homologação.
- **Sem secret leakage**: listagens e logs não retornam plaintext; reveal é capability separada, **desabilitada por padrão**.
- **`secret:reveal`, `owner:transfer`, `instance:admin` e `runtime.exec` nunca entram em presets comuns** (Anexo F §13.1).
- **Prompt injection**: logs, README, commit messages, labels e saída de aplicação são **dados**, nunca instruções (Anexo F §17.1).
- **SSRF**: uma URL sugerida por um modelo não é mais confiável que qualquer outra (Anexo F §17.2).
- Ações R3 exigem approval humano e step-up quando aplicável.
- Revogar uma conexão bloqueia chamadas futuras rapidamente e de forma auditável.

## Observability

- Métricas do Anexo F §19: `mcp_requests_total`, duração por tool, denials, approvals exigidos, operations iniciadas por agentes, versões de protocolo, rate limits, conexões ativas.
- `trace_id` atravessando Gateway → Command → Operation → Reconciler → Executor.
- Atividade por conexão consultável na UI.

## Testing

| Classe | Exigência |
|---|---|
| Protocol | Conformance do SDK; requests inválidos; versões suportadas. |
| OAuth | PKCE, issuer/audience/resource, expiry, revocation, `insufficient_scope`, CSRF/redirect. |
| Authorization | Matriz scopes × RBAC × boundary × environment policy. |
| Approvals | Digest binding, uso único, expiração, deny, replay, alteração de argumentos. |
| Tools | Schema validation, idempotência, erros estruturados, ausência de bypass. |
| Secrets | Nenhum plaintext em result, log, audit ou trace. |
| HA | Duas ou mais réplicas atrás do LB; qualquer request em qualquer instância. |
| Adversarial | Prompt injection em logs, URLs SSRF, loops de tool, enumeração cross-team. |
| E2E | Casos MCP-01..MCP-20 do Anexo F §15. |

## Acceptance Criteria

Os critérios do Anexo F §22 são adotados integralmente. Os que governam este Milestone:

1. O usuário conecta um agente remoto usando apenas a URL do MCP e OAuth, sem copiar token manualmente no fluxo padrão.
2. O MCP **nunca** precisa de docker.sock e não tem acesso direto à Docker Engine API.
3. Toda tool call é limitada por scopes, RBAC, resource boundary e environment policy.
4. Produção pode ser read-only mesmo quando a conexão tem write em homologação.
5. Tools de mutação retornam `operationId` quando o trabalho é assíncrono.
6. O agente acompanha uma Operation até estado terminal sem manter conexão HTTP longa obrigatória.
7. Deploy e rollback preservam artifact/release por digest imutável.
8. Logs e tool results passam por redaction antes de sair do Control Plane.
9. Secret write/bind funciona **sem** revelar plaintext em leitura posterior.
10. `secret:reveal` e `runtime.exec` estão **desabilitados por padrão**.
11. Ações R3 exigem approval humano/step-up, e o approval é ligado ao **digest da ação**.
12. Revogar `AgentConnection`/Grant bloqueia novas chamadas rapidamente e de forma auditável.
13. Enumeração cross-team **não** revela se um ID existe fora do boundary.
14. O catálogo de tools tem schemas estáveis e versionados.
15. Existe bridge stdio opcional.
16. O Gateway escala horizontalmente **sem sticky session**.
17. A auditoria correlaciona usuário, cliente MCP, tool, approval e Operation.
18. Falhas de provider/cluster retornam erro estruturado sem induzir o agente a bypass.
19. **Nenhuma regra de negócio existe somente no MCP**; UI, API e MCP compartilham os Application Services.

## Exit Gate

- [ ] Stories `required` `done`; os 19 Acceptance Criteria com evidência.
- [ ] Suíte de conformidade de protocolo verde.
- [ ] Matriz scopes × RBAC × boundary × environment verde.
- [ ] Teste de approval com digest binding e uso único verde.
- [ ] **Teste adversarial** verde: prompt injection em logs, SSRF por URL sugerida, enumeração cross-team.
- [ ] Teste de HA verde: duas réplicas, qualquer request em qualquer instância.
- [ ] Teste de revogação verde: chamadas bloqueadas rapidamente.
- [ ] `bin/fitness` verde com **AF-05** avaliando código real.
- [ ] `bin/security` verde; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`.

**Gate humano:** revisão de segurança específica do MCP (Anexo F §21, fase F5).
