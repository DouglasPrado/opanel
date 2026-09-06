# M04-01 — Ingress node role and global Traefik deployment

## Objective
Estabelecer a role lógica `ingress` e executar o Traefik como Service **global** restrito a esses nodes, com 80/443 em host mode.

## Outcome
Nodes marcados como ingress recebem uma instância de Traefik cada; a plataforma administra esse Service como qualquer outro recurso gerenciado, com labels de ownership e reconciliação.

## References
- `docs/architecture/08-networking-domains-edge.md` §7 (ingress nodes e múltiplos Traefiks), §2 (caminho da request)
- `docs/architecture/06-infrastructure-provisioning.md` §1.2 (papéis lógicos), §9.1 (labels)
- `docs/architecture/01-foundation.md` §6.1 (por que ingress dedicado)

## Preconditions
M03 aceito. Label de node de `M02-03` disponível.

## Scope
- Marcação de um node como `ingress` via label gerenciada.
- Traefik como Service **global** com placement por label de ingress, portas 80/443 publicadas em **host mode** (não routing mesh).
- Configuração estática mínima do Traefik com Swarm provider e file provider para configuração dinâmica distribuída pelo Control Plane.
- Endpoint interno de health (`/ping`) restrito, não público.
- Labels de ownership no Service do Traefik; ele é reconciliado como recurso gerenciado.
- Versão do Traefik registrada, para a suíte de compatibilidade de `M13-12`.

## Out of Scope
- Múltiplos ingress nodes reais e LB (`M08-10`, `M08-11`).
- Attachment às overlays dos Services publicados (`M04-02`).
- Rotas e domínios (`M04-04`, `M04-05`).
- Certificados (`M04-08`+).

## Domain Impact
`IngressGateway` como representação do Traefik por node, com estado observado.

## Application Layer
- **Commands:** `EnsureIngressGateway`.
- **Reconciler:** parte do `IngressReconciler` responsável pelo Service do Traefik.

## Async / Control Plane
O Traefik é um Service da plataforma, criado e mantido pelo mesmo ciclo Desired State → Operation → Executor → verificação. Nada de `docker run` nem de deploy manual.

## Security Requirements
- 80/443 em **host mode** somente nos nodes de ingress; nenhum outro node expõe portas públicas.
- Dashboard do Traefik, API interna e exporters **não públicos** por default (Anexo C §14).
- O endpoint de health é acessível apenas à rede confiável / ao LB.
- O Traefik não recebe o Docker socket de escrita; ele observa o Swarm com o mínimo necessário — e a decisão de qual acesso conceder é registrada explicitamente, porque o provider Swarm do Traefik exige leitura do socket em um manager. Esse acesso é **somente leitura** e o node que o hospeda é tratado como sensível.
- Labels de ownership obrigatórias.

## Observability Requirements
- Estado de cada `IngressGateway`: healthy/unhealthy, versão, `observedAt`.
- Logs de acesso do Traefik configurados com redaction de query string sensível.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Nenhum node com label de ingress | O Service global não agenda; a plataforma reporta “ingress não configurado”, não “falha genérica”. |
| Porta 80/443 ocupada no host | Falha explícita nomeando a porta; o preflight de `M01-08` já cobria o caso do bootstrap. |
| Traefik unhealthy | `IngressGateway` degradado; a UI mostra; a remoção do target do LB é de `M08-11`. |
| Configuração dinâmica inválida | Traefik mantém a última configuração válida; a plataforma reporta o erro sem derrubar rotas existentes. |
| Versão incompatível | Falha explícita nomeando versões. |

## Acceptance Criteria
1. Um node marcado como ingress recebe exatamente uma instância de Traefik (Service global com placement).
2. As portas 80/443 são publicadas em host mode apenas nos ingress nodes.
3. O Service do Traefik tem labels de ownership e é reconciliado como recurso gerenciado.
4. O endpoint de health existe e **não** é público.
5. Dashboard, API interna e exporters do Traefik não são acessíveis publicamente, provado por teste.
6. Sem node de ingress, a plataforma reporta “ingress não configurado” explicitamente.
7. Porta ocupada produz falha nomeando a porta.
8. Configuração dinâmica inválida não derruba as rotas existentes.
9. A versão do Traefik está registrada em arquivo versionado.
10. O acesso do Traefik ao Swarm é somente leitura e a decisão está documentada.

## Required Tests
- **unit**: geração da spec do Service do Traefik; placement por label.
- **Docker/Swarm**: Traefik global agendado; host mode; ausência de node de ingress; configuração inválida preservando rotas.
- **security**: dashboard/API/exporters não públicos; acesso somente leitura ao Swarm.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos contra Swarm real, endpoints administrativos comprovadamente privados, Critical/High = 0.
