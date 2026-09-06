---
title: "Opanel — Dependências entre Milestones"
type: "implementation-dependencies"
status: "ready-for-human-review"
---

# Dependências, caminho crítico e paralelização

Este arquivo é normativo para a ordem de execução. Um Milestone só pode entrar em `in_progress` quando **todas as suas hard dependencies** estiverem `READY_FOR_HUMAN_ACCEPTANCE` ou aceitas.

## 1. Definições

| Tipo | Significado | Efeito |
|---|---|---|
| **Hard** | Sem o Milestone anterior, a capacidade não pode ser implementada corretamente ou não pode ser testada com o runtime real. | Bloqueia o início. |
| **Soft** | O Milestone pode começar e entregar valor, mas alguma Story precisa de re-validação depois, ou a demonstração fica parcial. | Não bloqueia; exige nota no Milestone Report. |

## 2. DAG dos Milestones

```text
                                   M00 Foundation
                                        │
                                        ▼
                                   M01 Vertical Slice
                                        │
                        ┌───────────────┼────────────────┐
                        ▼               ▼                │
                   M02 Runtime Ops      │                │
                        │               │                │
                        ▼               │                │
                   M03 Vault ◄──────────┘                │
                        │                                │
          ┌─────────────┼─────────────┐                  │
          ▼             ▼             ▼                  │
    M04 Edge/TLS   M05 Build     M11 Governance ◄────────┘
          │             │             │
     ┌────┴────┐        ▼             │
     ▼         ▼   M06 Delivery       │
 M07 Custom  M08 HA     │             │
 Domains       │        ├─────────────┼──────────┐
     │         │        ▼             ▼          ▼
     │         │   M09 Observ.   M12 MCP     M10 Backup/DR
     │         │        │             │          │
     └─────────┴────────┴──────┬──────┴──────────┘
                               ▼
                        M13 Hardening & Scale
                               ▼
                        M14 Production Readiness
```

## 3. Matriz de dependências

| Milestone | Hard | Soft | Justificativa da hard dependency |
|---|---|---|---|
| M00 | — | — | Raiz do grafo. |
| M01 | M00 | — | Precisa de app, banco, fila, UI, testes e gates. |
| M02 | M01 | — | Opera sobre Service, Operation, Executor e Reconciler existentes. |
| M03 | M01, M02 | — | SecretVersion → Swarm Secret exige rollout controlado (M02) e Operation/Reconciler (M01). |
| M04 | M02, M03 | M08 | Chave privada de `CertificateVersion` usa o envelope de M03 (doc 08 §13.2); credenciais do DNS provider vivem no Vault. Ingress HA real depende de M08. |
| M05 | M02, M03 | M08 | Credenciais de Registry e tokens do Git provider ficam no Vault (doc 06 §11.2/§12.2). Builder node dedicado depende de M08. |
| M06 | M02, M03, M05 | M04 | Deployment materializa Swarm Secrets (M03) e consome Artifact por digest (M05). Domínio para validar tráfego vem de M04. |
| M07 | M04 | M06 | Estende Domain/Certificate/Ingress introduzidos em M04. |
| M08 | M02, M04 | M05 | Ingress HA exige Traefik e Certificate Distribution multi-target (M04). Builder pool depende de M05. |
| M09 | M02, M06 | M08 | Timeline/health de deployment e runtime precisam existir. Métricas multi-node dependem de M08. |
| M10 | M03, M06 | M08, M04 | Recovery do Vault exige M03; Clean Rebuild recria Services por digest de Release (M06). Swarm Raft/ClusterSnapshot fica mais forte com M08; certificados com M04. |
| M11 | M01, M03 | — | Governança opera sobre identidade/RBAC de M01; step-up authentication vem de M03. |
| M12 | M06, M11 | M09, M10 | Tools de delivery precisam de M06; OAuth/scopes/tokens/service accounts vêm de M11. Tools de observabilidade e restore dependem de M09/M10. |
| M13 | M05, M06, M08, M10 | M09, M11, M12 | Chaos/quorum exige cluster real (M08); DR drill exige M10; builder adversarial exige M05. |
| M14 | M13 | todos | Só faz sentido validar production readiness depois do hardening. |

**Não há ciclos.** Verificação: a matriz é uma ordem topológica estrita `M00 < M01 < M02 < M03 < {M04, M05, M11} < {M06, M07, M08} < {M09, M10, M12} < M13 < M14`; nenhuma aresta aponta para trás.

## 4. Caminho crítico

```text
M00 → M01 → M02 → M03 → M05 → M06 → M10 → M13 → M14
```

**9 Milestones.** É o caminho mais longo do grafo porque combina três cadeias irredutíveis:

1. **Base → backbone** (`M00 → M01 → M02`): nada existe antes da cadeia Desired State → Operation → Executor → Reconciler estar provada.
2. **Crypto → delivery** (`M03 → M05 → M06`): o Vault desbloqueia credenciais de Registry/Git; o build produz o Artifact; o Deployment consome o digest.
3. **Delivery → recuperabilidade → prova** (`M06 → M10 → M13 → M14`): o Clean Rebuild reconstrói Services a partir de Releases por digest, e o hardening só pode ser validado quando existe o que quebrar.

O caminho alternativo `M00 → M01 → M02 → M03 → M04 → M08 → M13 → M14` tem 8 Milestones e possui **1 Milestone de folga**. Um atraso em M04/M07/M08 maior que um Milestone move o caminho crítico para essa cadeia.

### Riscos concentrados no caminho crítico

| Risco | Milestone | Mitigação planejada |
|---|---|---|
| Envelope encryption/Recovery Key mal modelados forçam retrabalho em TLS, providers e DR. | M03 | `M03-01` exige plan mode e ADR se o modelo divergir do doc 09 §6.3. |
| Railpack/BuildKit em builder isolado é a maior superfície de risco de segurança. | M05 | `M05-07` e `M05-16` entregam isolamento e corpus adversarial dentro do próprio Milestone. |
| Clean Rebuild depende de o Desired State ser suficiente para recriar runtime. | M10 | `M10-13` valida em infraestrutura vazia; se faltar dado, vira Story em M10, não workaround. |

## 5. Oportunidades de paralelização

Paralelismo só é liberado depois que schemas, command/event contracts e boundaries estiverem congelados (Anexo G §13.2). Cada worktree precisa de Story exclusiva.

| Janela | Frentes simultâneas | Contrato que precisa estar congelado antes |
|---|---|---|
| Durante M00 | Backend toolchain ∥ Frontend toolchain ∥ CI/gates ∥ Swarm Lab | Layout de diretórios (`M00-01`). |
| Após M01 | **M11 Governance** pode iniciar cedo (só depende de M01 + step-up de M03) | Modelo `User/Team/TeamMember/InstanceRole` e Policies. |
| Após M03 | **M04 Edge** ∥ **M05 Build** ∥ **M11 Governance** | `Operation`, `Reconciler`, `SecretVersion`, `ProviderConnection`. |
| Após M04 | **M07 Custom Domains** ∥ **M08 HA** | `Domain`, `DomainBinding`, `Certificate*`, `LoadBalancerProvider`. |
| Após M06 | **M09 Observability** ∥ **M10 Backup/DR** | `Release`, `Deployment`, `DeploymentEvent`. |
| Após M11 + M06 | **M12 MCP** ∥ M09/M10 residual | Scopes OAuth, `ApiToken`, Application Services estáveis. |
| Durante M13 | Security ∥ Performance ∥ Chaos ∥ Upgrade | Ambientes de laboratório de `M00-17`. |

### Frente que pode andar quase o tempo todo

**UI/UX** pode avançar sobre props/contratos congelados de cada Milestone, desde que respeite o Reuse Gate (Anexo I §6.3) e não crie uma segunda fonte de verdade no browser. Isso **não** é um Milestone separado: cada Story de UI pertence ao Milestone da capacidade que ela expõe.

## 6. Dependências que não devem ser invertidas

Herdado de Anexo A §9 e reafirmado aqui como regra do pack:

| Não fazer | Por quê |
|---|---|
| Auto-deploy por webhook (M06) antes de Operation idempotente (M01/M02). | Webhooks duplicados e retries viram deploys inconsistentes. |
| Autoscaling (M09) antes de métricas confiáveis e scale idempotente. | O controller reage a dado ruim e oscila. |
| Secrets de produção (M03) antes de Recovery Key verificável e audit. | A dívida de segurança nasce no dado mais sensível. |
| Declarar HA (M08) antes de ingress redundante, quorum e testes de falha. | “Ter cluster” não é tolerar falha. |
| Cloud provider automation antes de enrollment manual estável (M08). | Automatiza um fluxo ainda não compreendido. |
| MCP (M12) antes de Command/Query/RBAC/audit maduros. | Estabiliza tools sobre contratos instáveis (Anexo G §18.1). |
| Certificate Manager (M04) antes do envelope de criptografia (M03). | Private key de certificado precisa de storage cifrado. |
| Clean Rebuild (M10) antes de Release por digest (M06). | Não há de onde reconstruir o runtime. |

## 7. Dependências externas (fora do controle do pack)

| Dependência | Quem precisa | Se indisponível |
|---|---|---|
| Repositório de componentes React existente (`gba.dev`) | M00-05 e toda Story de UI | `BLOCKED_EXTERNAL_DEPENDENCY` em M00-05; ver SC-07. |
| GitHub App registrado (App ID, private key, webhook secret) | M05-01, M05-04 | `BLOCKED_EXTERNAL_DEPENDENCY`; build por imagem continua possível. |
| Registry OCI acessível | M05-11, M06, M10 | Deploy por artifact existente continua; novos builds bloqueiam. |
| Zona DNS controlada pela plataforma + credencial de provider | M04-06, M04-07 | Domínio default bloqueia; runtime e logs seguem. |
| Conta ACME (Let's Encrypt) e rate limits | M04-09 | TLS bloqueia; HTTP interno segue para testes de laboratório. |
| Bucket S3-compatible para backup | M10-01 | DR bloqueia; nenhum outro Milestone bloqueia. |
| Hosts adicionais para cluster multi-node | M08, M13 | HA e chaos bloqueiam; single-node segue. |
