---
document: "08"
title: "Networking, Domains & Edge"
type: "architecture"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Documento técnico consolidado - Parte 8**

Networking, domínios, ingress, TLS e caminho completo de tráfego

## Resumo executivo

Esta parte define a camada de networking e edge da plataforma. O objetivo é transformar domínio, porta e política de exposição declarados no produto em um caminho de rede previsível, altamente disponível e isolado entre Environments. O desenho padrão usa um Load Balancer externo em L4/TCP, múltiplos Traefiks em nodes de ingress, redes overlay por Environment e Docker Swarm Services como destino final.

A plataforma não trata Traefik como um detalhe de implementação. Ingress, Domain, Certificate e Network passam a ser recursos explícitos do produto, reconciliados pelo Control Plane da Parte 7. O usuário administra domínios e exposição de serviços; a plataforma traduz isso em DNS, certificados, labels do Swarm, configuração dinâmica do Traefik e targets do Load Balancer.

| **Campo**      | **Definição**                                                                                   |
|----------------|-------------------------------------------------------------------------------------------------|
| Status         | Documento vivo - v0.8                                                                           |
| Data           | 05 de setembro de 2026                                                                          |
| Escopo         | Networking do cluster, edge, DNS, TLS, ingress e isolamento de Environments                     |
| Caminho padrão | L4 Load Balancer -\> Traefik host-mode -\> overlay network -\> Swarm Service                    |
| TLS            | Certificate Manager centralizado; certificados distribuídos para todas as instâncias de Traefik |
| Dados stateful | Fora do cluster nesta fase; Postgres/Redis/Object Storage são serviços gerenciados externos     |

| **Princípio:** nenhum serviço de aplicação precisa publicar portas diretamente na internet. O único ponto público normal do cluster é a camada de ingress em 80/443; o restante permanece em redes privadas/overlay. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Objetivos da camada de Networking & Edge

| **Objetivo**           | **Resultado esperado**                                                                                   |
|------------------------|----------------------------------------------------------------------------------------------------------|
| Isolamento             | Production, HML e demais Environments não compartilham rede de aplicação por padrão.                     |
| HA de entrada          | Falha de um ingress node ou de uma instância Traefik não interrompe o serviço.                           |
| Roteamento declarativo | Domain e Service no banco viram routers/services/middlewares no Traefik sem edição manual.               |
| TLS centralizado       | Emissão, renovação e distribuição de certificados não dependem de uma única réplica Traefik.             |
| Portabilidade          | Load Balancer, DNS e Registry podem ser trocados por providers sem mudar o modelo de domínio do produto. |
| Observabilidade        | É possível localizar falha em DNS, LB, Traefik, overlay ou workload separadamente.                       |
| Escala                 | Adicionar ingress nodes ou réplicas de aplicação não exige alterar DNS de cada domínio.                  |

# 2. Caminho completo de uma request

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Client / Browser<br />
|<br />
| DNS: api.example.com<br />
v<br />
Public Load Balancer (L4 / TCP 443)<br />
|<br />
+--------+---------+<br />
| | |<br />
v v v<br />
Ingress-01 Ingress-02 Ingress-03<br />
Traefik A Traefik B Traefik C<br />
\ | /<br />
\ | /<br />
+---- ingress overlay ----+<br />
|<br />
v<br />
Environment overlay network<br />
|<br />
v<br />
Swarm Service: api<br />
/ | \<br />
api.1 api.2 api.3</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

O Load Balancer decide apenas qual ingress saudável recebe a conexão TCP. O Traefik termina TLS, interpreta Host/SNI/path e seleciona o Service correto. A conexão interna segue pela rede overlay do Environment até uma Task saudável do Docker Swarm Service.

| **Decisão:** o Routing Mesh do Swarm continua disponível para workloads que precisarem, mas não será o caminho padrão do tráfego público. Para ingress HTTP/HTTPS, os Traefiks usam portas publicadas em host mode nos nodes marcados como ingress. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 3. Planos de rede

| **Plano**              | **Tráfego**                                             | **Regra**                                                     |
|------------------------|---------------------------------------------------------|---------------------------------------------------------------|
| Management plane       | Managers, join, Raft e Docker/Swarm control traffic     | Somente rede confiável do cluster; nunca internet aberta.     |
| Ingress plane          | Load Balancer -\> Traefik                               | Somente nodes de ingress recebem tráfego público/LB.          |
| Application data plane | Traefik -\> services e service -\> service              | Overlay networks específicas por Environment.                 |
| External egress        | Services -\> APIs externas, DBaaS, Redis gerenciado, S3 | Permitido conforme política de egress do Environment/Service. |
| Observability plane    | Collectors -\> backend de métricas/logs                 | Rede/endpoint próprio; não deve competir com tráfego público. |

O Docker Swarm criptografa o tráfego de management/control plane. O tráfego de aplicação em overlay não é criptografado por padrão; por isso a rede entre nodes deve ser privada/confiável. A plataforma pode oferecer overlay encryption como opção para clusters que atravessam redes não confiáveis, sabendo que há custo de performance.

# 4. Estratégia de overlay networks

## 4.1 Uma rede por Environment

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Project: Albert<br />
<br />
Environment: production<br />
network: prj_albert_env_prod<br />
- web<br />
- api<br />
- worker<br />
<br />
Environment: homolog<br />
network: prj_albert_env_hml<br />
- web<br />
- api<br />
- worker</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Cada Environment recebe pelo menos uma overlay network dedicada. Services de Production não são conectados à network de HML e vice-versa. O isolamento deve ser consequência da topologia, não apenas de uma convenção de nomes.

## 4.2 Rede compartilhada de ingress

Traefik precisa alcançar os Services expostos. Para isso, cada Service público pode ser conectado simultaneamente à sua network de Environment e a uma network de ingress controlada pela plataforma, ou o Traefik pode ser conectado às networks necessárias de forma reconciliada. A implementação deve limitar conectividade ao mínimo necessário.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>traefik<br />
networks:<br />
- edge_ingress<br />
- prj_albert_env_prod<br />
- prj_monexo_env_prod<br />
<br />
albert-api<br />
networks:<br />
- prj_albert_env_prod<br />
<br />
monexo-web<br />
networks:<br />
- prj_monexo_env_prod</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Preferência:** conectar Traefik diretamente às overlays dos serviços públicos evita publicar portas internas e mantém o roteamento dentro do overlay. O reconciler de ingress é responsável por anexar/remover essas networks conforme Domains ativos. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 5. Naming, IDs e endereçamento

| **Recurso**     | **Padrão recomendado**                               | **Exemplo**        |
|-----------------|------------------------------------------------------|--------------------|
| Overlay network | net\_\<projectId\>\_\<environmentId\>                | net_prj01_env_prod |
| Swarm Service   | svc\_\<projectId\>\_\<environmentId\>\_\<serviceId\> | svc_prj01_prod_api |
| Traefik router  | rtr\_\<domainBindingId\>                             | rtr_dom_01HX...    |
| Traefik service | tsvc\_\<serviceId\>\_\<port\>                        | tsvc_api_3000      |
| Certificate     | cert\_\<certificateId\>                              | cert_01HX...       |
| Docker Secret   | vault\_\<secretVersionId\>                           | vault_sv_01HX...   |

Nomes humanos podem mudar; IDs técnicos não. Labels e recursos do Docker devem preferir IDs estáveis para que renomear Project, Environment ou Service não provoque recriação desnecessária ou colisões.

Subnets de overlays podem ser atribuídas automaticamente pelo Docker inicialmente. Se a plataforma precisar de redes previsíveis ou integração com VPN/peering, introduz-se um IPAM interno com pools por cluster. A plataforma deve detectar conflito de CIDR antes de aplicar uma configuração.

# 6. Service discovery interno

Dentro da mesma overlay network, Docker oferece descoberta de serviços por DNS. O Service deve ter um alias previsível, permitindo que aplicações se comuniquem sem conhecer IP de Tasks individuais.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>api -&gt; http://redis-proxy:6379<br />
worker -&gt; http://api:3000<br />
web -&gt; http://api:3000</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Na fase atual, bancos e Redis são externos; portanto os destinos críticos serão URLs fornecidas pelos providers e injetadas via Vault/Environment. O DNS interno do Swarm continua útil para comunicação entre APIs, workers e serviços auxiliares.

| **Regra:** não persistir IP de container/Task no banco do produto. Tasks são efêmeras; a unidade estável é o Service e seu nome/alias no DNS da overlay. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------|

# 7. Ingress nodes e múltiplos Traefiks

Ingress é uma role lógica de node. Nodes marcados com node.labels.platform.role=ingress recebem uma instância Traefik em modo global. Isso garante uma instância por ingress node e simplifica portas 80/443 em host mode.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Swarm<br />
<br />
manager-01 role=manager<br />
manager-02 role=manager<br />
manager-03 role=manager<br />
<br />
ingress-01 platform.role=ingress -&gt; traefik.1<br />
ingress-02 platform.role=ingress -&gt; traefik.2<br />
ingress-03 platform.role=ingress -&gt; traefik.3<br />
<br />
worker-01 platform.role=worker<br />
worker-02 platform.role=worker<br />
worker-03 platform.role=worker</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Configuração**          | **Valor padrão**                                    |
|---------------------------|-----------------------------------------------------|
| Traefik deploy mode       | global                                              |
| Placement                 | node.labels.platform.role == ingress                |
| HTTP                      | published 80 -\> target 80, mode=host               |
| HTTPS                     | published 443 -\> target 443, mode=host             |
| Provider                  | Swarm provider                                      |
| Config dinâmica adicional | File provider gerado/distribuído pelo Control Plane |

Cada Traefik observa o mesmo estado do Swarm. Em Swarm mode, as labels de roteamento ficam no Service, não na Task/container individual. O port do backend deve ser informado explicitamente nas labels porque o Swarm provider não infere automaticamente a porta privada da aplicação.

# 8. Load Balancer externo em L4

O Load Balancer público opera em TCP e não precisa conhecer Projects, Domains ou certificados. Ele conhece apenas os ingress targets e suas portas.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>frontend TCP/443<br />
-&gt; ingress-01:443<br />
-&gt; ingress-02:443<br />
-&gt; ingress-03:443<br />
<br />
frontend TCP/80<br />
-&gt; ingress-01:80<br />
-&gt; ingress-02:80<br />
-&gt; ingress-03:80</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Responsabilidade do LB** | **Detalhe**                                            |
|----------------------------|--------------------------------------------------------|
| Distribuir conexões        | Selecionar um ingress target saudável.                 |
| Health check               | Retirar target indisponível automaticamente.           |
| Preservar TLS              | TCP passthrough; certificado termina no Traefik.       |
| Não conhecer apps          | Nenhuma configuração por domínio ou Service.           |
| Escalar ingress            | Adicionar/remover targets conforme lifecycle de nodes. |

## 8.1 Health check do ingress

Cada Traefik expõe um endpoint interno de saúde, por exemplo /ping, em porta não pública ou restrita ao Load Balancer. O target só entra em rotação depois de Traefik estar pronto, certificados/configuração básica carregados e rede overlay funcional.

## 8.2 LoadBalancerProvider

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>interface LoadBalancerProvider {<br />
ensureLoadBalancer(input): Promise&lt;LoadBalancerRef&gt;<br />
addTarget(lbId, target): Promise&lt;void&gt;<br />
removeTarget(lbId, targetId): Promise&lt;void&gt;<br />
listTargets(lbId): Promise&lt;TargetState[]&gt;<br />
health(lbId): Promise&lt;LoadBalancerHealth&gt;<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Providers possíveis: Hetzner, AWS NLB, DigitalOcean, OVH, Cloudflare Load Balancing ou modo manual. O modelo do produto não depende de um fornecedor específico.

# 9. Modelo de roteamento do Traefik

Um DomainBinding liga um hostname a um Service e a uma porta interna. O reconciler traduz esse binding em labels do Swarm e, quando necessário, middlewares/policies adicionais.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>DomainBinding<br />
hostname: api.example.com<br />
serviceId: svc_api<br />
targetPort: 3000<br />
tls: true<br />
<br />
-&gt;<br />
<br />
traefik.enable=true<br />
traefik.http.routers.rtr_123.rule=Host(`api.example.com`)<br />
traefik.http.routers.rtr_123.entrypoints=websecure<br />
traefik.http.routers.rtr_123.tls=true<br />
traefik.http.routers.rtr_123.service=tsvc_api_3000<br />
traefik.http.services.tsvc_api_3000.loadbalancer.server.port=3000</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 9.1 Path routing

A plataforma pode permitir regras adicionais como Host + PathPrefix, mas o modelo default deve ser um hostname por binding. Path routing é útil para gateways e monólitos, porém aumenta conflitos e precisa de validação de precedência.

## 9.2 Múltiplas portas

Um Service pode expor múltiplos ports internamente. Cada DomainBinding referencia explicitamente targetPort. Assim, api.example.com pode apontar para 3000 e admin.example.com para 9000 no mesmo Service sem ambiguidade.

# 10. Domínios e onboarding de DNS

| **Estado**   | **Significado**                                                    |
|--------------|--------------------------------------------------------------------|
| PENDING_DNS  | Domain criado, mas DNS ainda não aponta para o endpoint esperado.  |
| DNS_VERIFIED | A/AAAA/CNAME validado.                                             |
| CERT_PENDING | Controle do domínio validado; certificado em emissão/distribuição. |
| ACTIVE       | DNS, certificado e router convergidos.                             |
| DEGRADED     | Domínio existe, mas alguma dependência está inconsistente.         |
| FAILED       | Erro persistente de DNS/certificado/ingress.                       |

Ao adicionar um domínio, o Control Plane informa exatamente qual registro deve ser criado. Se houver DNS Provider conectado, pode aplicar automaticamente; caso contrário, apresenta instruções e verifica periodicamente até convergir.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Custom domain<br />
api.customer.com<br />
|<br />
+-- DNS Provider integrado? -- yes --&gt; create record<br />
| no --&gt; show instructions<br />
v<br />
verify DNS<br />
v<br />
issue/attach certificate<br />
v<br />
apply Traefik route<br />
v<br />
ACTIVE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 11. DNS Provider

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>interface DnsProvider {<br />
listZones(): Promise&lt;DnsZone[]&gt;<br />
ensureRecord(input): Promise&lt;DnsRecordRef&gt;<br />
deleteRecord(id): Promise&lt;void&gt;<br />
createAcmeTxt(input): Promise&lt;DnsRecordRef&gt;<br />
waitPropagation(input): Promise&lt;DnsPropagationState&gt;<br />
}</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Tipo de domínio** | **Registro normal**                                                             |
|---------------------|---------------------------------------------------------------------------------|
| Subdomínio          | CNAME para endpoint estável da plataforma quando possível, ou A/AAAA para o LB. |
| Apex/root           | A/AAAA para o Load Balancer; ALIAS/ANAME quando o provider oferecer.            |
| Wildcard            | \*.apps.customer.com apontando para o mesmo edge endpoint.                      |
| ACME DNS-01         | TXT temporário em \_acme-challenge.\<domain\>.                                  |

Credenciais do DNS Provider são secrets do Team e ficam protegidas pelo Vault versionado. O provider recebe apenas a permissão mínima possível para a zona necessária.

# 12. Domínios default da plataforma

Para reduzir atrito, cada Environment/Service público pode receber um domínio automático sob uma zona controlada pela plataforma, antes de o usuário conectar um domínio próprio.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>service: api<br />
project: albert<br />
environment: homolog<br />
<br />
-&gt; api-homolog-albert.apps.platform.example</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Um wildcard DNS para \*.apps.platform.example aponta para o Load Balancer. A plataforma pode usar um wildcard certificate para a zona controlada, emitido via DNS-01. Domínios customizados continuam tendo certificados próprios ou SANs gerenciados pelo Certificate Manager.

# 13. Certificate Manager centralizado

Com múltiplas instâncias Traefik, não é desejável que cada réplica mantenha um acme.json independente ou tente emitir o mesmo certificado. O Certificate Manager do Control Plane torna emissão e renovação uma operação centralizada e versionada.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Domain ACTIVE candidate<br />
|<br />
v<br />
Certificate Manager<br />
|<br />
+--&gt; ACME account<br />
+--&gt; DNS-01 challenge<br />
+--&gt; DNS Provider API<br />
|<br />
v<br />
CertificateVersion v12<br />
cert.pem<br />
encrypted key.pem<br />
chain.pem<br />
|<br />
v<br />
Certificate Distributor<br />
+----+----+<br />
v v v<br />
T1 T2 T3<br />
ACK ACK ACK<br />
|<br />
v<br />
ACTIVE</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 13.1 Por que DNS-01 como padrão para HA

DNS-01 independe de qual ingress recebe uma requisição HTTP durante a emissão e permite wildcard certificates. Quando o DNS provider possui API, o fluxo é totalmente automatizável. HTTP-01 pode ser oferecido como fallback para domínios simples quando DNS automation não está disponível.

## 13.2 Armazenamento

A chave privada do certificado é criptografada no storage da plataforma usando o mesmo envelope encryption protegido pela Recovery Key. O plaintext só existe temporariamente no Certificate Manager/Distributor e no filesystem protegido dos ingress nodes.

## 13.3 Distribuição

Traefik recebe certificados via File Provider. Cada versão é materializada em diretório com permissões restritas e configuração dinâmica versionada. Uma nova versão só vira ACTIVE depois que o número mínimo exigido de ingress nodes confirmar a instalação.

# 14. Renovação e rotação de certificados

1\. Scheduler identifica certificados entrando na janela de renovação.

2\. Certificate Manager inicia nova ACME Order usando DNS-01.

3\. Nova CertificateVersion é armazenada criptografada.

4\. Distributor envia a versão para todos os ingress nodes ativos.

5\. Traefik recarrega configuração dinâmica sem derrubar conexões existentes.

6\. Health/handshake é verificado em múltiplos ingress nodes.

7\. Nova versão passa para ACTIVE; versão anterior entra em grace period.

8\. Após a janela de segurança, arquivos/chaves antigos são removidos.

| **Regra:** a renovação não altera o DomainBinding nem exige recriar o Swarm Service da aplicação. Certificado e release da aplicação possuem ciclos de vida independentes. |
|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 15. Wildcard certificates e limites

Wildcards são úteis para zonas controladas pela própria plataforma ou pelo cliente, por exemplo \*.apps.example.com. A emissão exige DNS-01. O Certificate Manager deve evitar criar certificados redundantes e respeitar limites da CA, deduplicando pedidos simultâneos para a mesma cobertura de nomes.

| **Estratégia**           | **Quando usar**                                                    |
|--------------------------|--------------------------------------------------------------------|
| Wildcard da plataforma   | Default domains sob uma zona que controlamos.                      |
| Certificado por hostname | Domínios customizados isolados; blast radius menor.                |
| SAN certificate          | Pequeno conjunto de nomes que compartilham lifecycle/ownership.    |
| Wildcard do cliente      | Quando o cliente delega DNS e quer previews/subdomínios dinâmicos. |

# 16. HTTP, HTTPS e políticas edge

| **Política**   | **Default**                                                                           |
|----------------|---------------------------------------------------------------------------------------|
| HTTP -\> HTTPS | Redirect permanente para serviços TLS.                                                |
| TLS minimum    | Política moderna definida globalmente e versionada.                                   |
| HSTS           | Opt-in inicialmente; pode ser padrão em domínios confirmados sem necessidade de HTTP. |
| X-Forwarded-\* | Preservar e normalizar headers no ingress.                                            |
| Request ID     | Gerar/propagar correlation id quando ausente.                                         |
| Compression    | Configurável por Service/Domain; evitar dupla compressão.                             |
| Body size      | Limite configurável; não impor valor baixo global que quebre uploads.                 |

Políticas viram Middlewares referenciados pelos routers. O produto deve oferecer presets seguros em vez de expor toda a sintaxe do Traefik na UI desde o início.

# 17. WebSocket, SSE, streaming e gRPC

| **Protocolo**  | **Tratamento**                                                                |
|----------------|-------------------------------------------------------------------------------|
| WebSocket      | Traefik suporta upgrade HTTP; garantir timeouts adequados no LB e no ingress. |
| SSE            | Desabilitar buffering incompatível e manter idle timeout suficiente.          |
| HTTP streaming | Evitar middleware que bufferize resposta inteira.                             |
| gRPC           | Suportar HTTP/2 no edge e backend scheme/config apropriados.                  |
| gRPC-Web       | Opcional via middleware/proxy compatível.                                     |

| **Importante:** o Load Balancer L4 simplifica protocolos porque ele não interpreta HTTP. Timeouts de conexão do provider ainda precisam ser compatíveis com WebSocket/SSE de longa duração. |
|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 18. TCP e UDP services

HTTP/HTTPS será o primeiro-class path. A plataforma pode oferecer TCP/UDP exposure posteriormente usando Traefik TCP/UDP routers ou portas publicadas do Swarm, mas isso exige alocação de portas públicas, regras de firewall e integração adicional com o Load Balancer.

| **Modo**          | **Uso**                                                    |
|-------------------|------------------------------------------------------------|
| HTTP/HTTPS domain | Default; entrada por Host/SNI e 80/443.                    |
| TCP + SNI         | TLS TCP para protocolos que suportam SNI.                  |
| TCP port dedicado | Ex.: broker ou protocolo customizado.                      |
| UDP port dedicado | Casos específicos; exige suporte explícito do LB/provider. |

Na primeira versão, exposição TCP/UDP arbitrária pode ser marcada como advanced/experimental para manter a superfície de segurança pequena.

# 19. Rate limiting e proteção de edge

A plataforma deve separar proteção local do Traefik de proteção upstream/CDN/WAF. Rate limit local é útil para bursts e abuse control, mas ataques volumétricos devem ser absorvidos antes de chegar ao cluster quando possível.

| **Camada**         | **Exemplos**                                                         |
|--------------------|----------------------------------------------------------------------|
| CDN/WAF externo    | DDoS, bot management, caching, WAF gerenciado.                       |
| Load Balancer      | Connection limits, target health, eventualmente source preservation. |
| Traefik middleware | Rate limit, IP allowlist, basic auth, headers, redirects.            |
| Application        | Autorização, quotas de negócio, rate limit por usuário/API key.      |

Policies devem ser vinculadas a DomainBinding ou Service, versionadas e auditadas. Uma alteração de rate limit é operação de ingress, não deployment de aplicação.

# 20. IPv4 e IPv6

O modelo de Domain não deve assumir IPv4. Endpoints públicos podem possuir A, AAAA ou ambos. A capacidade real de IPv6 depende do provider do Load Balancer, rede dos nodes e configuração Docker/host; por isso deve ser uma capability detectada do Cluster/Provider.

| **Capability** | **Comportamento**                                                              |
|----------------|--------------------------------------------------------------------------------|
| IPv4 only      | Criar/validar A/CNAME conforme provider.                                       |
| Dual-stack     | A + AAAA e health checks em ambas as famílias quando suportado.                |
| IPv6 only      | Só aceitar quando todos os componentes críticos suportarem o caminho completo. |

| **Regra:** não anunciar AAAA antes de o caminho IPv6 estar funcional ponta a ponta. Um AAAA quebrado pode causar falhas intermitentes difíceis de diagnosticar em clientes que preferem IPv6. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 21. Egress e acesso a serviços externos

Como Postgres, Redis e Object Storage serão gerenciados externamente nesta fase, egress é parte crítica do runtime. Nodes Workers precisam alcançar esses endpoints sem exigir que os serviços exponham portas inbound adicionais.

| **Recurso externo** | **Recomendação**                                                     |
|---------------------|----------------------------------------------------------------------|
| Postgres gerenciado | TLS obrigatório; allowlist/private network quando provider permitir. |
| Redis gerenciado    | TLS/auth; endpoint privado quando disponível.                        |
| S3/Object Storage   | HTTPS; credentials de menor privilégio via Vault.                    |
| Third-party APIs    | HTTPS, timeouts e retries no app; egress observável.                 |

Em uma fase posterior, o produto pode ter Egress Policies por Environment e allowlists de destinos, mas não é requisito para o primeiro release.

# 22. Segurança de rede

| **Risco**                   | **Controle**                                                                               |
|-----------------------------|--------------------------------------------------------------------------------------------|
| Docker API exposta          | Nunca publicar docker.sock/2375 para internet; somente executor privilegiado nos Managers. |
| Swarm control plane público | 2377/7946/4789 restritos à rede confiável do cluster.                                      |
| Apps publicando portas      | Services não publicam portas públicas por padrão; ingress é a fronteira.                   |
| Prod acessando HML          | Overlays distintas e nenhum attachment cruzado por padrão.                                 |
| Secret em URL/header de log | Redaction nos access logs e observabilidade.                                               |
| Cert private key            | Criptografada em storage e materializada somente nos ingress autorizados.                  |
| Spoof de forwarded headers  | Traefik confia apenas no LB/proxies conhecidos para forwarded headers sensíveis.           |

Se overlay encryption for habilitada, o Control Plane deve tratar isso como configuração de Network e alertar para impacto de performance. Em clusters com links privados entre nodes, a configuração default pode priorizar performance e confiar na rede privada.

# 23. Observabilidade de Edge

| **Métrica/Sinal**     | **Dimensões úteis**                      |
|-----------------------|------------------------------------------|
| Requests              | domain, router, service, status_code     |
| Latency               | p50/p95/p99 por domain/service           |
| Active connections    | ingress node, protocol                   |
| TLS handshakes/errors | domain, certificate, ingress node        |
| LB target health      | target/node/provider                     |
| 5xx origin            | router/service/task                      |
| 4xx                   | domain/status; cuidado com cardinalidade |
| Certificate expiry    | certificate/domain/days_remaining        |
| DNS verification      | domain/provider/state                    |

O dashboard deve permitir seguir o caminho de uma falha: DNS -\> LB -\> Traefik -\> Service -\> Task. Um erro 502 no Traefik não deve ser apresentado como “aplicação offline” sem verificar se há Tasks saudáveis e backend port correto.

# 24. Estados derivados de Domain e Ingress

| **Status** | **Condição resumida**                                                    |
|------------|--------------------------------------------------------------------------|
| ACTIVE     | DNS válido + cert válido + router aplicado + backend alcançável.         |
| PENDING    | Operação assíncrona em andamento sem erro definitivo.                    |
| DEGRADED   | Algumas instâncias ingress/targets falharam, mas tráfego ainda funciona. |
| BLOCKED    | Pré-condição ausente, ex.: DNS não aponta ou provider sem permissão.     |
| FAILED     | Operação encerrou após política de retry; requer ação.                   |
| DISABLED   | Binding existe mas não é exposto.                                        |

Esses estados são derivados de recursos e probes reais, não apenas de uma coluna status escrita pela API.

# 25. Falhas que o desenho precisa tolerar

| **Falha**                                   | **Comportamento esperado**                                                   |
|---------------------------------------------|------------------------------------------------------------------------------|
| Traefik A cai                               | LB remove target; Traefik B/C continuam atendendo.                           |
| Ingress node inteiro cai                    | LB retira node; Swarm/operador repõe capacidade quando possível.             |
| Worker com api.2 cai                        | Swarm recria Task em outro worker; Traefik descobre backend atualizado.      |
| Certificate Manager temporariamente offline | Certificados já distribuídos continuam servindo; novas emissões aguardam.    |
| DNS Provider indisponível                   | Domains existentes continuam; novas validações/renovações entram em retry.   |
| LB API indisponível                         | Targets atuais continuam; reconcile posterior converge mudanças.             |
| Um certificado novo falha em 1 de 3 ingress | Não promover globalmente até política de quorum/distribuição ser satisfeita. |
| Backend port errado                         | Router fica DEGRADED/FAILED com diagnóstico explícito de conexão ao origin.  |
| Overlay attachment perdido                  | Ingress reconciler detecta drift e reaplica network attachment.              |

# 26. Modelo de dados desta parte

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Cluster<br />
1--N IngressNode<br />
1--1 EdgeEndpoint<br />
1--N Network<br />
<br />
Team<br />
1--N DnsProviderConnection<br />
1--N Domain<br />
<br />
Environment<br />
1--1 PrimaryOverlayNetwork<br />
1--N Service<br />
<br />
Service<br />
1--N ServicePort<br />
1--N DomainBinding<br />
<br />
DomainBinding<br />
N--1 Domain<br />
N--1 ServicePort<br />
0--1 Certificate<br />
0--N EdgePolicyBinding<br />
<br />
Certificate<br />
1--N CertificateVersion<br />
<br />
LoadBalancer<br />
1--N LoadBalancerTarget</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Entidade**       | **Campos essenciais**                                                                            |
|--------------------|--------------------------------------------------------------------------------------------------|
| Domain             | id, teamId, hostname, verificationState, ownershipType                                           |
| DomainBinding      | id, environmentId, serviceId, servicePortId, domainId, tlsMode, desiredRevision, appliedRevision |
| ServicePort        | id, serviceId, name, targetPort, protocol                                                        |
| Network            | id, clusterId, environmentId?, dockerNetworkId, driver, cidr?, encrypted, state                  |
| Certificate        | id, domainSetHash, state, activeVersionId, renewAfter                                            |
| CertificateVersion | id, certificateId, encryptedPrivateKey, certificatePem, chainPem, issuedAt, expiresAt            |
| EdgeEndpoint       | id, clusterId, loadBalancerProviderId, ipv4?, ipv6?, hostname?                                   |
| LoadBalancerTarget | id, nodeId, address, port, healthState                                                           |
| EdgePolicy         | id, teamId, type, config, revision                                                               |

# 27. Operações e reconcilers

| **Reconciler**                    | **Responsabilidade**                                         |
|-----------------------------------|--------------------------------------------------------------|
| NetworkReconciler                 | Criar/remover overlay networks e attachments esperados.      |
| DomainReconciler                  | Validar DNS e calcular estado do DomainBinding.              |
| IngressReconciler                 | Aplicar labels/routers/services/middlewares no Swarm.        |
| CertificateReconciler             | Emitir, renovar, versionar e revogar certificados.           |
| CertificateDistributionReconciler | Garantir versão correta em todos os ingress nodes elegíveis. |
| LoadBalancerReconciler            | Garantir targets dos ingress nodes ativos.                   |
| DnsReconciler                     | Criar/verificar registros quando provider é gerenciado.      |
| EdgeHealthReconciler              | Probe de LB/Traefik/router/backend e estado derivado.        |

Todos seguem o modelo da Parte 7: Desired State persistente, Operation para mudanças explícitas, aplicação idempotente, verificação e reconcile periódico para corrigir drift.

# 28. API operacional sugerida

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>POST /projects/:projectId/environments/:envId/domains<br />
GET /projects/:projectId/environments/:envId/domains<br />
PATCH /domains/:domainId<br />
DELETE /domains/:domainId<br />
POST /domains/:domainId/verify<br />
<br />
GET /clusters/:clusterId/edge<br />
GET /clusters/:clusterId/ingress-nodes<br />
POST /clusters/:clusterId/ingress-nodes/:nodeId/enable<br />
POST /clusters/:clusterId/ingress-nodes/:nodeId/disable<br />
<br />
GET /certificates<br />
GET /certificates/:id<br />
POST /certificates/:id/renew<br />
<br />
POST /teams/:teamId/dns-providers<br />
GET /teams/:teamId/dns-providers<br />
DELETE /teams/:teamId/dns-providers/:id<br />
<br />
GET /domains/:domainId/events<br />
GET /domains/:domainId/diagnostics</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 29. Experiência de UI

## 29.1 Domain screen

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>api.example.com ACTIVE<br />
------------------------------------------------<br />
DNS Verified<br />
TLS Valid until 04 Dec 2026<br />
Route api : 3000<br />
Ingress 3 / 3 healthy<br />
Last check 12 seconds ago<br />
<br />
[Diagnostics] [Change service] [Disable] [Remove]</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 29.2 Cluster Edge screen

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>EDGE<br />
<br />
Public endpoint 203.0.113.10<br />
Load balancer Healthy<br />
<br />
Ingress gateways<br />
ingress-01 Healthy 8.1k req/s<br />
ingress-02 Healthy 7.9k req/s<br />
ingress-03 Healthy 8.4k req/s<br />
<br />
Certificates 43 valid / 0 expiring / 0 failed<br />
Domains 51 active / 2 pending</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 29.3 Diagnostics

A tela de diagnóstico executa checks independentes e mostra o primeiro ponto quebrado: resolução DNS, conectividade com LB, TLS/SNI, router encontrado, backend service, Task health e resposta do origin. Isso evita transformar toda falha de rede em um genérico “502”.

# 30. Ordem de implementação

1\. Criar Network e ServicePort no modelo de dados; overlay dedicada por Environment.

2\. Subir Traefik em modo global nos ingress nodes, com portas 80/443 host-mode.

3\. Criar DomainBinding e gerar labels básicas Host -\> Service -\> targetPort.

4\. Implementar domínio default da plataforma com wildcard DNS.

5\. Implementar EdgeHealthReconciler e diagnostics básicos.

6\. Criar abstração LoadBalancerProvider e integrar o primeiro provider/manual mode.

7\. Criar Certificate Manager e armazenamento criptografado de CertificateVersion.

8\. Implementar Certificate Distributor + File Provider do Traefik.

9\. Implementar ACME DNS-01 e o primeiro DnsProvider.

10\. Implementar custom domains com workflow PENDING_DNS -\> ACTIVE.

11\. Adicionar policies/middlewares: HTTPS redirect, headers, allowlist e rate limit.

12\. Adicionar WebSocket/SSE/gRPC presets e timeouts configuráveis.

13\. Adicionar IPv6/dual-stack como capability do provider/cluster.

14\. Adicionar TCP/UDP exposure somente após HTTP/HTTPS estar consolidado.

# 31. Decisões registradas nesta parte

| **Decisão**           | **Registro**                                                                          |
|-----------------------|---------------------------------------------------------------------------------------|
| Ingress público       | LB externo L4/TCP -\> Traefik host-mode; routing mesh não é default.                  |
| Traefik HA            | Uma instância global por ingress node elegível.                                       |
| Environment network   | Overlay isolada por Environment.                                                      |
| Roteamento            | Traefik Swarm provider + labels no Service.                                           |
| TLS                   | Certificate Manager central; não deixar cada Traefik emitir certificado isoladamente. |
| ACME                  | DNS-01 como caminho preferencial para HA e wildcard; HTTP-01 como fallback.           |
| Cert distribution     | File Provider + materialização versionada nos ingress nodes.                          |
| DNS                   | Provider abstraction com modo integrado ou instruções manuais.                        |
| Default domain        | Wildcard sob zona controlada pela plataforma.                                         |
| IPv6                  | Capability detectada; nunca publicar AAAA sem path funcional.                         |
| Stateful dependencies | Externas ao cluster nesta fase.                                                       |
| TCP/UDP               | Não é prioridade do primeiro release.                                                 |

## Referências técnicas oficiais usadas nesta parte

**Docker Swarm ingress/routing mesh:** https://docs.docker.com/engine/swarm/ingress/

**Docker Swarm networking/overlay:** https://docs.docker.com/engine/swarm/networking/

**Traefik Swarm provider:** https://doc.traefik.io/traefik/providers/swarm/

**Traefik ACME resolver:** https://doc.traefik.io/traefik/reference/install-configuration/tls/certificate-resolvers/acme/

**Let's Encrypt challenge types:** https://letsencrypt.org/docs/challenge-types/

## Próxima parte sugerida
