---
document: "B"
title: "Requisitos Não Funcionais e SLOs"
type: "annex"
status: "approved"
source: "docx"
---

**PLATAFORMA PAAS  
CLUSTER-FIRST**

**Anexo B — Requisitos Não Funcionais e SLOs**

Disponibilidade, desempenho, capacidade, segurança, retenção, RPO/RTO e critérios de production readiness

## **Resumo executivo**

Este anexo transforma a arquitetura e os fluxos funcionais definidos nas Partes 1–10 em metas mensuráveis de qualidade. Os SLOs aqui descritos pertencem à plataforma de compute/deploy/ingress; bancos PostgreSQL, Redis e object storage das aplicações permanecem, nesta fase, em serviços externos gerenciados e são avaliados como dependências externas.

O documento distingue explicitamente clusters single-node de clusters elegíveis a alta disponibilidade. Ele também evita usar “visitas por mês” como unidade de capacidade: a plataforma deve ser qualificada em requests por segundo, concorrência, tamanho de payload, CPU, memória, conexões e perfil de pico. Aplicações com 100 milhões de visitas mensais são suportáveis desde que o workload real seja medido e o cluster seja dimensionado e testado contra esse perfil.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Regra de governança<br />
</strong>Princípio central: nenhum SLO é apenas um número de marketing. Cada meta deve possuir um SLI calculável, uma janela de medição, exclusões documentadas, alertas e um teste de aceitação que prove o comportamento.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# **1. Terminologia e regras de medição**

| **Termo**    | **Definição**                                                                                                           |
|--------------|-------------------------------------------------------------------------------------------------------------------------|
| NFR          | Requisito não funcional: característica de qualidade, segurança, desempenho, resiliência ou operação.                   |
| SLI          | Indicador mensurável usado para observar o comportamento real, por exemplo taxa de requests válidos ou p95 de latência. |
| SLO          | Objetivo interno para um SLI durante uma janela, por exemplo 99,95% de disponibilidade mensal.                          |
| SLA          | Compromisso contratual externo. Não deve ser criado automaticamente a partir deste documento.                           |
| Error Budget | Parcela de indisponibilidade ou erro permitida pelo SLO antes de bloquear mudanças arriscadas.                          |
| RPO          | Máxima perda temporal de dados aceitável após desastre.                                                                 |
| RTO          | Tempo máximo desejado para restaurar a capacidade funcional após desastre.                                              |

Todos os SLIs devem usar timestamps UTC, manter definição estável e registrar o denominador. Requests inválidos do cliente (4xx esperados), operações canceladas pelo próprio usuário e falhas explicitamente causadas por serviços externos podem ser classificadas separadamente, mas nunca removidas silenciosamente das métricas.

# **2. Classes de topologia e elegibilidade a SLO**

| **Classe**    | **Topologia mínima**                                                                       | **Uso**                                          | **Elegibilidade**                         |
|---------------|--------------------------------------------------------------------------------------------|--------------------------------------------------|-------------------------------------------|
| DEV / SINGLE  | 1 Manager que também executa workload; Traefik único; sem LB redundante.                   | Desenvolvimento, testes, ambientes não críticos. | Sem SLO de HA. Best effort.               |
| PROD-HA       | 3 Managers; ≥3 Workers; ≥2 Ingress; LB redundante; dados stateful externos; health checks. | Produção padrão.                                 | Elegível aos SLOs GA.                     |
| PROD-HA-ZONAL | PROD-HA distribuído em ≥3 failure domains/zonas quando o provider permitir.                | Produção crítica.                                | Elegível a metas maduras mais agressivas. |

| O painel deve exibir claramente quando um cluster não atende aos pré-requisitos de HA. “Replicas \> 1” não transforma um cluster single-node em alta disponibilidade. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# **3. SLOs de disponibilidade**

| **Superfície**                | **SLI**                                                                | **GA** | **Meta madura** | **Janela** |
|-------------------------------|------------------------------------------------------------------------|--------|-----------------|------------|
| Control Plane API             | requests elegíveis bem-sucedidos / total elegível                      | 99,90% | 99,95%          | 30 dias    |
| UI/API de leitura crítica     | requests elegíveis bem-sucedidos / total elegível                      | 99,90% | 99,95%          | 30 dias    |
| Ingress público da plataforma | conexões/requests aceitos pelo edge e roteados para serviço saudável   | 99,95% | 99,99%          | 30 dias    |
| Operation Engine              | operações aceitas que chegam a estado terminal sem falha de plataforma | 99,90% | 99,95%          | 30 dias    |
| Build submission plane        | builds válidos que são aceitos/encaminhados ao builder                 | 99,90% | 99,95%          | 30 dias    |
| Certificate management        | renovações elegíveis concluídas antes da janela de risco               | 99,95% | 99,99%          | 90 dias    |

## **3.1 Error budget mensal de referência**

| **SLO** | **Indisponibilidade equivalente em 30 dias** |
|---------|----------------------------------------------|
| 99,90%  | 43 min 12 s                                  |
| 99,95%  | 21 min 36 s                                  |
| 99,99%  | 4 min 19 s                                   |

A indisponibilidade do Control Plane não deve derrubar workloads já executando. Por isso, o SLO do ingress e o SLO do Control Plane são medidos separadamente.

# **4. SLOs de latência e responsividade**

| **Operação**                            | **Meta GA**                                    | **Meta madura**            | **Observação**                                                            |
|-----------------------------------------|------------------------------------------------|----------------------------|---------------------------------------------------------------------------|
| GETs comuns da API do painel            | p95 ≤ 300 ms; p99 ≤ 800 ms                     | p95 ≤ 200 ms; p99 ≤ 500 ms | Exclui chamadas que aguardam provider externo.                            |
| Writes síncronos da API                 | p95 ≤ 500 ms para aceitar e persistir intenção | p95 ≤ 300 ms               | Operações longas retornam Operation ID; não ficam presas no request HTTP. |
| Atualização de status via SSE/WebSocket | evento visível na UI ≤ 2 s após persistência   | ≤ 1 s                      | Em condições normais.                                                     |
| Listagem paginada                       | p95 ≤ 400 ms em datasets qualificados          | p95 ≤ 250 ms               | Obrigatório keyset/cursor em listas grandes.                              |
| Busca/filtro operacional                | p95 ≤ 500 ms                                   | p95 ≤ 300 ms               | Índices devem cobrir filtros principais.                                  |
| Login/session refresh                   | p95 ≤ 700 ms                                   | p95 ≤ 400 ms               | Sem dependência de IdP externo.                                           |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Regra de UX e arquitetura<br />
</strong>A API nunca espera um deploy/build terminar. Ela persiste a intenção, cria a Operation e responde rapidamente. A execução é acompanhada assincronamente.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# **5. Reconciliation, desired state e convergência**

| **Indicador**                         | **Meta GA**                                                   |
|---------------------------------------|---------------------------------------------------------------|
| Detecção de mudança desejada          | ≤ 2 s após commit transacional/outbox em 95% dos casos.       |
| Início de operação após enqueue       | p95 ≤ 5 s quando não há saturação de fila.                    |
| Detecção de evento Docker relevante   | p95 ≤ 3 s.                                                    |
| Detecção de drift por sweep           | ≤ 60 s.                                                       |
| Scale simples 1→N, imagem já presente | p95 ≤ 60 s para convergir; dependente do health check da app. |
| Restart solicitado                    | início p95 ≤ 10 s.                                            |
| Status final refletido na UI          | ≤ 2 s após reconciler persistir o actual state.               |

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Desired State<br />
↓<br />
Operation / Queue<br />
↓<br />
Swarm Executor<br />
↓<br />
Docker Swarm<br />
↓<br />
Actual State<br />
↓<br />
Reconciler<br />
↓<br />
UI</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# **6. Deploy, rollback e promotion**

| **Fluxo**                      | **SLO/objetivo**                                                                             |
|--------------------------------|----------------------------------------------------------------------------------------------|
| Deploy de artefato existente   | p95 ≤ 2 min do início da operação até HEALTHY para apps com health check ≤30 s.              |
| Rolling update                 | não reduzir abaixo do mínimo saudável definido pela política de update.                      |
| Rollback para release anterior | p95 ≤ 90 s quando imagem está disponível no Registry.                                        |
| Promotion HML → PROD           | não rebuildar; deve promover o mesmo digest imutável.                                        |
| Falha de rollout               | deve chegar a FAILED/BLOCKED com causa observável; nunca ficar indefinidamente em DEPLOYING. |
| Operação presa                 | watchdog marca STALLED e inicia recovery/alerta após limiar configurado.                     |

O tempo total de deploy inclui comportamento do container e seu health check. A plataforma mede separadamente “tempo de infraestrutura” e “tempo esperando a aplicação ficar saudável” para evitar esconder gargalos do software do cliente.

# **7. Build e Railpack/BuildKit**

| **Indicador**                         | **Meta/Regra**                                                                                               |
|---------------------------------------|--------------------------------------------------------------------------------------------------------------|
| Queue wait de build                   | p95 ≤ 30 s em capacidade normal; alertar quando exceder 2 min.                                               |
| Overhead da plataforma antes do build | p95 ≤ 15 s após checkout/source ready.                                                                       |
| Build duration                        | não possui SLO único por depender do projeto; deve ser medido por service e comparar com baseline histórico. |
| Logs de build                         | streaming disponível em ≤ 2 s após primeira saída do builder.                                                |
| Cancelamento                          | pedido de cancelamento deve ser propagado ao builder em ≤ 10 s.                                              |
| Imutabilidade                         | release referencia digest OCI; tag mutável não é fonte de verdade.                                           |
| Isolamento                            | builds não executam nos Managers nem possuem acesso ao docker.sock do Control Plane.                         |
| Cache                                 | perda do cache degrada performance, não corretude; cache não é dado crítico de backup.                       |

# **8. Edge, Traefik, LB, DNS e TLS**

| **Indicador**                           | **Meta/Regra**                                                                               |
|-----------------------------------------|----------------------------------------------------------------------------------------------|
| Health check do ingress                 | intervalo ≤ 10 s; remover target não saudável dentro da tolerância do LB.                    |
| Configuração de route após Domain READY | p95 ≤ 30 s para refletir em todos os Traefiks saudáveis.                                     |
| TLS handshake                           | TLS 1.2 mínimo; TLS 1.3 preferencial.                                                        |
| Certificado custom domain               | p95 ≤ 5 min depois que DNS está validamente configurado, excluindo propagação externa.       |
| Renovação                               | iniciar com margem ≥ 30 dias quando ACME/provider permitir; nunca depender da última semana. |
| Distribuição de certificado             | 100% dos ingress saudáveis devem confirmar versão antes de ela ser ACTIVE.                   |
| WebSocket/SSE                           | suportado sem timeout arbitrário do proxy incompatível com o protocolo.                      |
| gRPC                                    | HTTP/2 end-to-end quando configurado pelo serviço.                                           |

# **9. Capacidade e escalabilidade**

Capacidade será declarada em workload mensurável, não em “visitas/mês”. Para cada aplicação crítica, o usuário ou operador define peak RPS, concorrência, tamanho de resposta, custo médio de CPU/memória e dependências externas. O teste de qualificação deve exercitar pelo menos 2× o pico esperado ou o fator de segurança explicitamente aprovado.

| **Dimensão**     | **Regra de qualificação**                                                                              |
|------------------|--------------------------------------------------------------------------------------------------------|
| RPS              | Sustentar ≥2× pico esperado durante teste de 30–60 min sem violar SLO de erro/latência.                |
| Concorrência     | Sustentar ≥1,5× concorrência esperada.                                                                 |
| Falha de Worker  | repetir teste com ao menos um Worker indisponível em clusters PROD-HA.                                 |
| Ingress          | testar distribuição entre múltiplos Traefiks e remoção de um ingress durante carga.                    |
| Scale-out        | provar que réplicas adicionais reduzem saturação sem criar gargalo no Control Plane.                   |
| Queue saturation | build/deploy queues devem aplicar backpressure; nunca perder operações.                                |
| Noisy neighbor   | limites/reservas de CPU e memória devem impedir um service de esgotar todo o node quando configurados. |

## **9.1 Piso de qualificação da própria plataforma**

Antes de declarar a arquitetura GA, os testes de plataforma devem provar, no mínimo, um dataset e cluster significativamente maiores que o ambiente de desenvolvimento. Estes números são pisos de teste, não hard limits comerciais.

| **Dimensão**                   | **Piso de teste GA** |
|--------------------------------|----------------------|
| Nodes em um cluster            | 50                   |
| Services em um cluster         | 2.000                |
| Tasks simultâneas              | 5.000                |
| Projects/Environments no banco | 10.000 combinados    |
| Deployments históricos         | 250.000              |
| Audit events                   | 1.000.000            |
| Secret versions                | 100.000              |

| Se os testes mostrarem que um piso exige arquitetura desnecessariamente complexa para a primeira GA, ele pode ser revisado formalmente. O que não pode ocorrer é publicar “escala ilimitada” sem um envelope testado. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# **10. Resource isolation e scheduling**

| **Requisito**         | **Diretriz**                                                                             |
|-----------------------|------------------------------------------------------------------------------------------|
| CPU/Memory limits     | Todo service deve aceitar limits; produção deve alertar services sem limites explícitos. |
| Reservations          | Disponíveis para workloads críticos e usados pelo scheduler.                             |
| Placement constraints | Usar labels para separar production, ingress, builders e workloads especiais.            |
| Managers              | Por padrão não recebem workloads de usuário em topologias PROD-HA.                       |
| Builders              | Nodes dedicados; build arbitrário não compartilha privilégio com Control Plane.          |
| Disk pressure         | node entra em degraded/drain conforme política antes de atingir condição destrutiva.     |
| OOM                   | eventos OOM devem aparecer na UI e alimentar incident/alert.                             |

# **11. Durabilidade, backup, RPO e RTO**

| **Componente**                       | **RPO**                                                                     | **RTO alvo**                                  | **Observação**                                                                        |
|--------------------------------------|-----------------------------------------------------------------------------|-----------------------------------------------|---------------------------------------------------------------------------------------|
| PostgreSQL do Control Plane          | ≤ 5 min                                                                     | ≤ 30 min                                      | Backup/PITR conforme provider ou estratégia definida na Parte 5.                      |
| Vault: SecretVersions criptografadas | ≤ 5 min                                                                     | ≤ 30 min                                      | Recuperação exige material criptográfico/Recovery Key.                                |
| Audit log                            | ≤ 5 min                                                                     | ≤ 60 min                                      | Alta prioridade por segurança/compliance.                                             |
| Certificados e metadata              | ≤ 15 min                                                                    | ≤ 30 min                                      | Certificados já distribuídos continuam servindo mesmo com Control Plane indisponível. |
| Estado Swarm / Raft                  | ≤ 15 min                                                                    | Fast restore ≤ 30 min; clean rebuild ≤ 60 min | Clean rebuild usa desired state + artifacts como fonte recuperável.                   |
| Registry artifacts                   | Conforme SLO do provider; releases pinadas não podem ser removidas pelo GC. | ≤ 30 min para reconnect/reconfigure           | Cache local não é backup.                                                             |
| Logs operacionais                    | ≤ 5 min de perda aceitável                                                  | ≤ 4 h                                         | Não bloqueiam recuperação de workloads.                                               |
| Metrics                              | ≤ 5 min de perda aceitável                                                  | ≤ 4 h                                         | Histórico pode ter prioridade inferior ao Control Plane.                              |

## **11.1 Restore verification**

- Backups do Control Plane devem possuir teste automático ou periódico de restauração.

- Recovery Key deve possuir fluxo de verificação no onboarding e após rotação.

- Um DR drill completo deve ser executado pelo menos trimestralmente em ambiente isolado.

- RPO/RTO só são considerados válidos após medição em restore real; documentação sozinha não comprova recuperação.

# **12. Retenção de dados e observabilidade**

| **Dado**                    | **Default recomendado**             | **Observação**                                               |
|-----------------------------|-------------------------------------|--------------------------------------------------------------|
| Service logs pesquisáveis   | 14 dias                             | Configurável; export para provider externo pode ampliar.     |
| Build logs                  | 30 dias                             | Metadata do build pode permanecer além do log bruto.         |
| Metrics high-resolution     | 30 dias                             | Downsampling pode preservar séries agregadas por mais tempo. |
| Audit log                   | 365 dias                            | Não deve ser editável pelo usuário comum.                    |
| Operation history           | 365 dias                            | Estados e causas terminalizados.                             |
| Deployment/Release metadata | ≥ 365 dias ou enquanto referenciado | Releases pinadas por env/snapshot não podem ser coletadas.   |
| Alerts/Incidents            | 365 dias                            | Útil para postmortems e capacity planning.                   |
| Idempotency keys            | 24–72 h conforme endpoint           | Suficiente para retry de clientes e webhooks.                |

# **13. Segurança não funcional**

| **Área**         | **Requisito**                                                                                        |
|------------------|------------------------------------------------------------------------------------------------------|
| Docker privilege | docker.sock somente no Swarm Executor privilegiado; nunca UI/API pública/build do usuário.           |
| Daemon remoto    | porta Docker insegura 2375 proibida; nenhuma Docker API exposta à Internet.                          |
| Cluster network  | 2377/7946/4789 restritas à rede confiável entre nodes.                                               |
| Secrets at rest  | AEAD com chave versionada; plaintext não persistido no PostgreSQL.                                   |
| Swarm Secrets    | segredos sensíveis distribuídos preferencialmente via Swarm Secrets, não Service Env.                |
| Recovery Key     | exibida uma vez, verificável, rotacionável; master key interna não é apresentada ao usuário.         |
| Passwords        | hash resistente a GPU, preferencialmente Argon2id, com parâmetros versionados.                       |
| API tokens       | armazenar somente hash/verificador; mostrar token completo uma única vez.                            |
| MFA              | obrigatório para INSTANCE_ADMIN e TEAM_OWNER em ambientes production-ready.                          |
| TLS              | TLS 1.2 mínimo; TLS 1.3 preferido; suites fracas desabilitadas.                                      |
| Webhooks         | assinatura/secret verificados; replay protection e idempotência.                                     |
| Audit            | toda ação privilegiada, reveal/rotation de secret, exec terminal e ownership transfer auditados.     |
| Build isolation  | builders tratados como execução de código não confiável; sem credenciais administrativas do cluster. |

# **14. Dependências externas e degradação**

| **Dependência**            | **Quando falha**                            | **Comportamento esperado**                                                           |
|----------------------------|---------------------------------------------|--------------------------------------------------------------------------------------|
| Managed PostgreSQL da app  | workload pode falhar                        | Plataforma não tenta “corrigir” o banco; mostra causa observável.                    |
| Managed Redis              | app pode degradar                           | Mesma regra; health do service pode refletir dependência se a app assim expuser.     |
| Object Storage             | uploads/assets podem falhar                 | Não derrubar Control Plane.                                                          |
| Registry                   | novos deploys/pulls podem falhar            | Workloads atuais continuam rodando; deploy fica BLOCKED/FAILED com retry controlado. |
| Git provider               | novos builds podem bloquear                 | Deploy por artefato existente continua possível.                                     |
| DNS provider               | automação de domínio bloqueia               | Domínios já ativos continuam roteando.                                               |
| ACME                       | novos certificados/renovações podem atrasar | Alertar cedo; certificados existentes continuam válidos.                             |
| Load Balancer provider API | mudanças de targets podem bloquear          | Targets atuais continuam atendendo; operação entra em degraded/blocked.              |

# **15. Error budget e política de mudança**

| **Consumo do budget**           | **Política**                                                                      |
|---------------------------------|-----------------------------------------------------------------------------------|
| \< 50%                          | Entrega normal; mudanças seguem gates padrão.                                     |
| ≥ 50% antes de metade da janela | Revisar causa; reduzir mudanças de alto risco.                                    |
| ≥ 80%                           | Congelar rollouts não essenciais; priorizar reliability work.                     |
| 100% ou SLO violado             | Bloquear releases arriscadas até estabilização e postmortem/ação corretiva.       |
| Violações recorrentes           | Reavaliar arquitetura/capacidade; não “resolver” reduzindo silenciosamente o SLO. |

O error budget deve ser visível no dashboard operacional e calculado por superfície. Um incidente no builder não consome automaticamente o budget de ingress se workloads publicados continuarem saudáveis.

# **16. Alertas e severidade operacional**

| **Severidade** | **Critério típico**                                                                                        | **Resposta esperada**                                           |
|----------------|------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------|
| SEV-1          | Ingress amplamente indisponível, quorum crítico perdido, comprometimento de secrets, perda ativa de dados. | Alerta imediato; prioridade absoluta; comunicação de incidente. |
| SEV-2          | Degradação relevante, um failure domain perdido, deploys globalmente bloqueados, certificate risk.         | Ação rápida; evitar mudanças não relacionadas.                  |
| SEV-3          | Problema localizado, capacidade reduzida, um node unhealthy com redundância preservada.                    | Tratamento em horário operacional/plantão conforme contexto.    |
| SEV-4          | Avisos de capacidade, manutenção preventiva, drift sem impacto.                                            | Backlog operacional com prazo.                                  |

# **17. Perfil mínimo de testes de performance e resiliência**

1.  Baseline sem carga para medir overhead do Control Plane e do ingress.

2.  Ramp-up progressivo até o pico esperado.

3.  Soak test de 30–60 minutos no pico e teste mais longo periódico para detectar leaks.

4.  Spike test acima do pico para observar backpressure e recovery.

5.  Worker failure durante carga.

6.  Ingress failure durante carga.

7.  Manager failure preservando quorum.

8.  Rolling deploy durante tráfego.

9.  Autoscale durante tráfego.

10. Registry temporariamente indisponível durante novo deploy.

11. Restart do Control Plane durante operação em andamento.

12. DR restore cronometrado para validar RPO/RTO.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th><strong>Critério de performance<br />
</strong>Um teste de carga só é aprovado se além do throughput os p95/p99, taxa de erro, saturação, queue depth e recovery time permanecerem dentro dos critérios. “Não caiu” não é critério suficiente.</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# **18. NFRs de UX e acessibilidade**

| **Área**            | **Requisito**                                                                                                           |
|---------------------|-------------------------------------------------------------------------------------------------------------------------|
| Acessibilidade      | Meta WCAG 2.2 AA para fluxos principais.                                                                                |
| Keyboard            | Ações essenciais e navegação operacional acessíveis por teclado.                                                        |
| Status              | Nunca depender apenas de cor; incluir texto/ícone/descrição.                                                            |
| Operações longas    | Mostrar estado, progresso quando mensurável, logs/eventos e possibilidade de sair da tela sem cancelar.                 |
| Erro                | Exibir causa acionável e correlation/operation ID para suporte.                                                         |
| Destructive actions | Confirmação explícita; step-up/reautenticação quando impacto for crítico.                                               |
| Privileged data     | Secrets ocultas por default; reveal auditado.                                                                           |
| Browsers            | Suportar versões atuais dos principais navegadores desktop; mobile deve permitir observação e ações seguras essenciais. |

# **19. Gate de Production Readiness**

| **Gate**           | **Critério para aprovação**                                                                      |
|--------------------|--------------------------------------------------------------------------------------------------|
| HA topology        | Cluster PROD-HA atende managers/workers/ingress/LB mínimos.                                      |
| Availability       | SLIs coletados e dashboards de error budget funcionando.                                         |
| Performance        | Carga de qualificação aprovada com margem definida.                                              |
| Failure tests      | Worker/Manager/Ingress failures demonstrados sem indisponibilidade indevida.                     |
| Security           | MFA privilegiado, secrets, Docker privilege boundary, firewall e webhook verification validados. |
| Backup/DR          | Restore drill medido e dentro de RPO/RTO.                                                        |
| Observability      | Logs, metrics, alerts e correlation IDs disponíveis.                                             |
| Deploy safety      | rolling update, health check, rollback e idempotência testados.                                  |
| Certificates       | emissão, renovação e distribuição HA testadas.                                                   |
| Runbooks           | procedimentos críticos existem e foram exercitados.                                              |
| External providers | falhas simuladas e comportamento degraded conhecido.                                             |
| UX                 | fluxos críticos da Parte 10 aprovados, incluindo erros e degraded states.                        |

# **20. Critérios de aceite do Anexo B**

- Cada SLO possui um SLI implementável e uma janela de cálculo definida.

- A UI diferencia cluster não-HA de cluster elegível a SLO de produção.

- O sistema coleta métricas necessárias para disponibilidade, latência, operations, builds, deploys e ingress.

- O Control Plane não é requisito para continuidade de workloads já executando.

- RPO e RTO são comprovados por restore drills, não apenas configurados.

- O capacity planning usa RPS/concorrência/perfil de carga e não “visitas mensais” isoladamente.

- Error budgets influenciam a política de rollout e reliability work.

- Todas as metas externas/provider-dependent possuem classificação explícita de dependência.

- O gate de Production Readiness pode ser executado como checklist objetivo antes de uma release GA.

## **Próximo anexo recomendado**
