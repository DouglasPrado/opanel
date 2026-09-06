---
milestone: "M04"
name: "Ingress, Default Domains & TLS"
type: "milestone"
status: "pending"
---

# M04 — Ingress, Default Domains & TLS

## Identity

| Campo | Valor |
|---|---|
| **ID** | M04 |
| **Nome** | Ingress, Default Domains & TLS |
| **Objetivo** | Introduzir o **Edge**: Traefik em modo global nos ingress nodes, roteamento declarativo por `DomainBinding`, domínio default sob zona controlada pela plataforma, e Certificate Manager centralizado emitindo por ACME DNS-01 e distribuindo versões com confirmação. |
| **Resultado observável** | Um Service criado em M01 passa a responder por HTTPS em `api-prod-albert.apps.<zona-da-plataforma>`, com certificado válido emitido e distribuído pela plataforma, sem que nenhuma porta da aplicação seja publicada diretamente. |

## Why

Até M03 a plataforma cria e opera workloads que **ninguém alcança**. M04 é o Milestone que transforma o produto em algo utilizável: URL, TLS e um caminho de rede previsível.

Ele depende de M03 por uma razão técnica, não organizacional: a chave privada de `CertificateVersion` é criptografada com o mesmo envelope protegido pela Recovery Key (doc 08 §13.2), e a credencial do DNS provider vive no Vault (doc 06 §11.2). Ver SC-05.

M04 desbloqueia M07 (domínios do cliente) e M08 (ingress HA), e é pré-requisito para qualquer demonstração real de deploy.

## Scope

- Role lógica `ingress` por label; Traefik como Service **global** com placement em ingress nodes e portas 80/443 em **host mode**.
- Attachment reconciliado do Traefik às overlays dos Services publicados; nada de porta publicada por aplicação.
- `ServicePort` e alias de service discovery interno.
- `Domain` e `DomainBinding` como desired state, traduzidos em labels/routers/services do Traefik pelo Ingress Reconciler.
- Domínio default da plataforma sob zona wildcard controlada.
- `DnsProvider` como abstração, com o primeiro adapter e proteção SSRF.
- `Certificate` e `CertificateVersion` com chave privada **cifrada** pelo envelope de M03.
- Certificate Manager centralizado: conta ACME, ordem DNS-01, versionamento.
- Certificate Distributor: materialização por file provider, ACK por ingress node, ativação só após quorum.
- Renovação com margem e retirada da versão anterior após janela de segurança.
- Políticas de edge: HTTP→HTTPS, TLS mínimo, forwarded headers e trusted proxies.
- Edge health reconciler e tela de diagnóstico por camada.
- Presets de compatibilidade para WebSocket, SSE e gRPC.

## Out of Scope

| Deixado para | O quê |
|---|---|
| M07 | Domínios customizados do cliente, verificação de DNS de terceiros, certificados por hostname/SAN, políticas por domínio (rate limit, allowlist), HTTP-01 fallback, IPv6. |
| M08 | Múltiplos ingress nodes reais, Load Balancer L4 e a distribuição de certificado para N gateways em cluster multi-node. |
| M09 | Métricas de edge no backend de observabilidade. |
| Backlog | WAF/CDN próprios, exposição TCP/UDP arbitrária, path routing avançado. |

## Dependencies

- **Hard:** M02, M03.
- **Soft:** M08 — em cluster single-node há um ingress apenas; a política de quorum de distribuição é implementada aqui, mas só é exercida de verdade em M08.
- **Externas:** zona DNS controlada pela plataforma + credencial de provider; conta ACME acessível.

## User-visible Outcome

O usuário publica um Service e recebe uma URL HTTPS funcional gerada pela plataforma, sem configurar DNS, sem lidar com certificado e sem abrir porta. Quando algo falha, a tela de diagnóstico diz **onde** quebrou: DNS, LB, Traefik, rota, backend ou Task.

## Technical Outcome

- Caminho padrão de tráfego estabelecido: LB/entrada → Traefik host-mode → overlay do Environment → Swarm Service.
- Roteamento declarativo: `DomainBinding` no banco vira labels no Service, reconciliadas.
- Emissão e renovação centralizadas: nenhum Traefik mantém `acme.json` gravável próprio.
- `CertificateVersion` imutável; ativação condicionada a confirmação de distribuição.

## Architecture Impact

| Categoria | Impacto |
|---|---|
| Entities | `ServicePort`, `Domain`, `DomainBinding`, `Certificate`, `CertificateVersion`, `CertificateDistribution`, `EdgeEndpoint`, `IngressGateway`, `DnsConnection`, `EdgePolicy`. |
| Commands | `EnsureIngress`, `CreateDomainBinding`, `IssueCertificate`, `RenewCertificate`, `DistributeCertificateVersion`, `ConnectDnsProvider`. |
| Queries | `EdgeOverview`, `DomainDiagnostics`, `CertificateStatus`. |
| Events | `domain.activated.v1`, `certificate.issued`, `certificate.activated`. |
| Reconcilers | `IngressReconciler`, `NetworkReconciler` (attachment), `CertificateReconciler`, `CertificateDistributionReconciler`, `DnsReconciler`, `EdgeHealthReconciler`. |
| Providers | `DnsProvider` (primeiro adapter), cliente ACME. |
| UI | Domains, Domain detail, Diagnostics, Cluster Edge. |

## Security

- **Nenhum Service publica porta pública**: o ingress é a única fronteira (doc 08 §1, princípio).
- Chave privada de certificado **cifrada em repouso** com o envelope de M03; plaintext existe apenas transitoriamente no Certificate Manager e no filesystem protegido do ingress (doc 08 §13.2).
- Credenciais do DNS provider no Vault, com o **menor escopo possível**, idealmente por zona (Anexo C §14.1).
- **SSRF**: toda chamada a provider e toda URL fornecida passam pelas defesas do Anexo C §13.1 — bloquear loopback, link-local, RFC1918/ULA e metadata; resolver DNS e validar o IP final; tratar redirect como nova decisão de policy.
- **Trusted proxies** configurados explicitamente: `X-Forwarded-*` só é confiável vindo do LB/proxy conhecido (Anexo C §14).
- Dashboard do Traefik, exporters e endpoints administrativos **nunca** públicos por default.
- Certificado só vira `ACTIVE` após a política de distribuição ser satisfeita — nunca por otimismo.
- Ameaças cobertas: T11 (DNS token comprometido), T12 (cert private key exfiltrada).

## Observability

- Sinais de edge do doc 08 §23: requests, latência, conexões ativas, handshakes/erros TLS, health de target, 5xx de origem, expiração de certificado, estado de verificação de DNS.
- **Diagnóstico por camada** (doc 08 §29.3): DNS → LB → TLS/SNI → router → backend service → Task health → resposta do origin. Um 502 nunca é apresentado como “aplicação offline” sem verificar as camadas.
- Alerta antecipado de falha de renovação, **antes** da janela crítica.

## Testing

| Classe | Exigência |
|---|---|
| Unit | Geração de labels do Traefik; cálculo de estado de Domain; política de quorum de distribuição; janela de renovação. |
| Integration | Ciclo de vida de `Certificate`/`CertificateVersion`; chave privada cifrada; ACK de distribuição. |
| Contract | `DnsProvider` (create/update/delete TXT/A/AAAA/CNAME, propagação, conflito); ACME (challenge, renewal, failure/retry, ativação de versão). |
| Docker/Swarm | Traefik global; labels gerando router/service; attachment de rede reconciliado; request real chegando ao Service. |
| E2E | Service publicado respondendo por HTTPS no domínio default; diagnóstico mostrando a camada quebrada. |
| Security | Ausência de porta pública; SSRF nos providers; trusted proxies; chave privada cifrada; endpoints administrativos não públicos. |

## Acceptance Criteria

1. Um Service recebe domínio e responde por HTTPS **sem** publicar porta diretamente no host.
2. Traefik roda como Service global nos nodes com label de ingress, com 80/443 em host mode.
3. `DomainBinding` no banco vira router/service do Traefik por reconciliação, e a divergência é corrigida.
4. O domínio default é gerado sob a zona controlada e resolve para o endpoint do cluster.
5. O Certificate Manager emite por ACME DNS-01 usando credencial do Vault.
6. Nenhum Traefik precisa compartilhar `acme.json` gravável entre réplicas.
7. A chave privada é armazenada **cifrada** pelo envelope de M03.
8. Uma `CertificateVersion` só vira `ACTIVE` após a política de distribuição ser satisfeita.
9. A renovação inicia com margem ≥ 30 dias quando o provider permitir e não derruba conexões existentes.
10. Os estados do Domain (`PENDING_DNS`, `PENDING_CERT`, `ACTIVE`, `DEGRADED`, `BLOCKED`, `FAILED`) são derivados de checks reais.
11. WebSocket e SSE atravessam o ingress corretamente.
12. HTTP redireciona para HTTPS e o TLS mínimo configurado é aplicado.
13. `X-Forwarded-*` só é confiável vindo de proxy conhecido.
14. Dashboard do Traefik e endpoints administrativos não são públicos.
15. Toda chamada a provider e toda URL fornecida passam pelas defesas de SSRF.
16. O diagnóstico identifica a camada quebrada em vez de reportar 502 genérico.

## Exit Gate

- [ ] Stories `required` `done` com commit; 16 Acceptance Criteria com evidência.
- [ ] E2E de HTTPS no domínio default verde contra Swarm real com Traefik.
- [ ] Teste de renovação sem downtime verde.
- [ ] Teste de SSRF nos providers verde.
- [ ] Teste comprovando que a chave privada está cifrada em repouso.
- [ ] Teste de trusted proxies e de endpoints administrativos não públicos.
- [ ] `bin/fitness`, `bin/security` verdes; Critical = 0, High = 0.
- [ ] `MILESTONE_REPORT.md` gerado.
