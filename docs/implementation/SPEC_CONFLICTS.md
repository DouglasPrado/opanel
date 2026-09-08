---
title: "Opanel — Conflitos de Especificação encontrados no planejamento"
type: "implementation-conflicts"
status: "ready-for-human-review"
---

# Conflitos de especificação

Registro dos conflitos encontrados durante a leitura completa da especificação para produzir este Implementation Pack.

**Nenhuma decisão arquitetural foi alterada silenciosamente.** Onde a decisão vigente era inequívoca, ela foi aplicada e o conflito ficou registrado. Onde não era, o item está `unresolved` e bloqueia a Story correspondente.

Complementa — não substitui — [`docs/decisions/pending-documentation-updates.md`](../decisions/pending-documentation-updates.md). Itens já catalogados lá são referenciados por código (C1..C6, I1..I4).

| Estado | Significado |
|---|---|
| `resolved` | Decisão vigente inequívoca; aplicada no pack. O documento antigo ainda precisa ser corrigido por Story/ADR. |
| `deferred` | Decisão legítima, mas que só pode ser tomada com informação que ainda não existe. Tem dono (Story) e prazo (Milestone). |
| `unresolved` | Exige decisão humana/ADR **antes** da Story indicada. |

---

## SC-01 — Frontend: Next.js separado vs Rails + Inertia + React

- **Documentos envolvidos:** `docs/annexes/G-agent-oriented-development.md` §2 (linhas 95, 99-100), §3 (160-162), §4 (202-203), §17 (819). Corresponde a C1–C4.
- **Decisão antiga:** UI Next.js consumindo Rails em modo API; repositório com `apps/api/` e `apps/web/`.
- **Decisão atual:** Aplicação Rails 8.1 única servindo a UI por **Inertia + React/TypeScript**, Vite e Tailwind. Registrada em `CLAUDE.md`, `docs/AGENT_RULES.md` e `docs/decisions/pending-documentation-updates.md` §1.
- **Impacto:** Arquitetura de entrega da UI, estrutura de diretórios, contratos entre UI e backend, política de reuso de componentes.
- **Resolução aplicada:** `resolved`. `M00-01` congela a estrutura de aplicação Rails única; `M00-04` integra Inertia/React/Vite/Tailwind; nenhuma Story de UI cria REST endpoint apenas para servir a própria UI.
- **Ação documental pendente:** corrigir o Anexo G. Story âncora: `M14-08-documentation-set` (ou ADR antes, se alguém tocar o Anexo G primeiro).

## SC-02 — Fila: BullMQ + Redis vs Solid Queue

- **Documentos envolvidos:** `docs/architecture/07-internal-control-plane.md` §9.2 (linha 437). Corresponde a C5.
- **Decisão antiga:** “a implementação inicial pode usar BullMQ + Redis gerenciado, alinhada ao ecossistema Node/TypeScript”.
- **Decisão atual:** **Solid Queue** sobre PostgreSQL.
- **Impacto:** Camada de entrega das Operations. O restante do §9.2 continua normativo: a fila é mecanismo de entrega, PostgreSQL é fonte de verdade da Operation, e o sweep periódico recupera Operations sem lease válido.
- **Resolução aplicada:** `resolved`. `M00-03` instala Solid Queue; `M01-15` implementa outbox dispatcher + sweep de recuperação **sem** depender do broker para durabilidade.
- **Nota:** a ausência de Redis não relaxa nenhum requisito — o sweep continua obrigatório porque a garantia nunca foi do broker.

## SC-03 — Runners e bibliotecas de teste indefinidos

- **Documentos envolvidos:** `docs/annexes/D-test-strategy.md` §21 (linha 563). Corresponde a C6.
- **Decisão antiga:** “Quando a linguagem do Control Plane for definida definitivamente (Rails ou Rust), o Implementation Pack deverá escolher runners/libraries concretos.”
- **Decisão atual:** Rails 8.1 está definido; a escolha dos runners foi **explicitamente delegada a este pack** pelo próprio Anexo D.
- **Impacto:** Todas as classes de teste do Anexo D.
- **Resolução aplicada:** `resolved`, sem necessidade de ADR (não altera a stack aprovada; o Anexo D delega). Congelado em:
  - unit/integration/request/policy/contract → **RSpec + FactoryBot**, PostgreSQL real (`M00-07`);
  - frontend de componente → **Vitest + Testing Library** (`M00-08`);
  - E2E de browser → **Playwright** com seletores semânticos/roles/test IDs (`M00-08`);
  - Docker/Swarm integration → harness próprio sobre Swarm Lab descartável (`M00-17`);
  - carga → ferramenta com arrival-rate e thresholds p95/p99, escolhida em `M13-06`;
  - segurança estática → RuboCop + Brakeman + bundler-audit + secret scan (`M00-09`, `M00-10`).

## SC-04 — Prefixo das labels de ownership no Swarm (`com.platform.*`)

- **Documentos envolvidos:** `docs/architecture/07-internal-control-plane.md` §7; `docs/architecture/02-build-deploy.md` §11.1; `docs/decisions/pending-documentation-updates.md` §4.
- **Decisão antiga:** `com.platform.managed=true`, `com.platform.team_id=…` (doc 07) e, no mesmo assunto, `platform.team_id=…` **sem prefixo de domínio** (doc 02 §11.1). Os dois trechos da especificação já divergem entre si.
- **Decisão atual conhecida:** o produto chama-se **Opanel**; nenhuma decisão foi tomada sobre migrar o prefixo.
- **Impacto:** **Alto e irreversível na prática.** A label de ownership é a identidade dos recursos em runtime. Trocá-la depois do primeiro deploy quebra reconciliação, drift detection e adoção de recursos existentes de tudo que já estiver rodando.
- **Resolução:** `unresolved`. Proposta registrada em [`ADR-0001`](../decisions/ADR-0001-swarm-ownership-label-namespace.md) com status **Proposed**.
- **Bloqueio:** `M01-16-swarm-ownership-labels` não pode sair de `pending` enquanto o ADR-0001 não for aceito. Marcar `BLOCKED_FOR_PRODUCT_DECISION` se o loop autônomo alcançar a Story antes da decisão.

## SC-05 — Posição do Vault no roadmap

- **Documentos envolvidos:** `docs/annexes/A-implementation-roadmap.md` §3 e §5 (M8 Vault depois de M5 Delivery, M6 Deployment e M7 Edge); `docs/annexes/G-agent-oriented-development.md` §18 (Slice 4 Vault depois do Slice 3 Traefik); contra `docs/architecture/08-networking-domains-edge.md` §13.2 e `docs/architecture/06-infrastructure-provisioning.md` §11.2/§12.2.
- **Decisão antiga:** Vault entra tarde, depois de Edge e Delivery.
- **Conflito real:** o doc 08 §13.2 determina que **a chave privada do certificado é criptografada com o mesmo envelope protegido pela Recovery Key**; o doc 06 §11.2 e §12.2 determinam que **credenciais de DNS provider e de Registry ficam no Vault versionado**. Ou seja, Edge e Build dependem tecnicamente do Vault, embora o roadmap os coloque antes.
- **Impacto:** Se o Anexo A fosse seguido literalmente, M7 (Edge) e M5 (Build) precisariam de um armazenamento de credenciais temporário fora do Vault — exatamente o antipadrão que a Parte 4 §9 e o Anexo C §12 proíbem.
- **Resolução aplicada:** `resolved` pela precedência de `docs/AGENT_RULES.md` §“Source of Truth” (arquitetura aprovada > roadmap). O Vault foi **antecipado para M03**, antes de Edge (M04) e Build (M05). O Anexo A §3 continua válido como intenção; a ordem executável é a de [`ROADMAP.md`](ROADMAP.md).

## SC-06 — Numeração e agrupamento de Milestones

- **Documentos envolvidos:** `docs/annexes/A-implementation-roadmap.md` §4 (M0–M13); `docs/goals/G01-create-implementation-pack.md` §3 (“Não existe obrigação de manter a quantidade definida em roadmaps antigos caso uma decomposição melhor seja encontrada”).
- **Decisão antiga:** 14 milestones M0–M13, sem MCP e sem governança separada.
- **Decisão atual:** 15 milestones M00–M14, com três mudanças estruturais: (a) Vault antecipado (SC-05); (b) governança multiusuário extraída de M1 para M11 para não inflar o vertical slice obrigatório; (c) MCP passa a ter Milestone próprio (M12), já que o Anexo F é normativo e o Anexo A não o cobre.
- **Impacto:** Rastreabilidade entre Anexo A e o pack.
- **Resolução aplicada:** `resolved`. Mapeamento explícito em [`ROADMAP.md` §4](ROADMAP.md#4-mapeamento-anexo-a--implementation-pack). Nenhuma capacidade do Anexo A foi descartada.

## SC-07 — Biblioteca de componentes React existente não está neste repositório

- **Documentos envolvidos:** `docs/goals/G01-create-implementation-pack.md` §17 (“reutilizar componente existente que esta no repo gba.dev”); `docs/AGENT_RULES.md` §“Component Reuse”; `docs/annexes/I-engineering-playbook-quality-gates.md` §6.
- **Situação:** o repositório `opanel` contém apenas `docs/`. Não foi possível verificar, durante o planejamento, quais componentes existem, seus nomes, contratos ou aparência.
- **Impacto:** Toda Story de UI assume reuso, mas nenhuma pode nomear componentes concretos sem inventar contratos.
- **Resolução:** `deferred`, com dono e prazo. `M00-05-component-library-import-and-inventory` é responsável por importar/adaptar a biblioteca e produzir um **inventário versionado** (`app/frontend/components/INVENTORY.md`) com nome, responsabilidade, props e categoria (`ui` / `shared` / `features` / `layouts`). Todas as Stories de UI posteriores referenciam esse inventário e são avaliadas pelo Reuse Gate contra ele.
- **Se a biblioteca não estiver disponível:** `M00-05` vira `BLOCKED_EXTERNAL_DEPENDENCY`. Não é permitido “resolver” criando um design system novo — isso contraria o §17 do Goal e o Anexo I §6.

## SC-08 — Estratégia de identificadores não decidida

- **Documentos envolvidos:** `docs/architecture/09-data-model-apis-contracts.md` §19 (“UUIDv7 ou ULID são adequados; **decisão final deve ser única para toda a plataforma**”); exemplos de ID prefixado espalhados por doc 07 §7 (`team_01…`, `svc_01…`), doc 08 §5 (`cert_01HX…`, `rtr_dom_01HX…`) e Anexo F §9.1/§13 (`op_01…`, `apr_123`, `agc_…`, `usr_…`).
- **Situação:** a especificação exige uma decisão única e não a toma. Os exemplos sugerem ID prefixado por tipo, mas isso nunca foi formalizado.
- **Impacto:** Chave primária de **todas** as entidades, formato da API pública, URIs de Resources do MCP, labels do Swarm e enumerabilidade. Trocar depois exige migração global.
- **Resolução:** `unresolved`. Proposta registrada em [`ADR-0002`](../decisions/ADR-0002-identifier-strategy.md) com status **Proposed**.
- **Bloqueio:** `M01-01-user-and-authentication` é a primeira Story a criar tabela e não pode sair de `pending` sem o ADR-0002 aceito.

## SC-09 — Nome técnico do Swarm Service: slugs humanos vs IDs opacos

- **Documentos envolvidos:** `docs/architecture/02-build-deploy.md` §11.1 (`<team>-<project>-<environment>-<service>`); `docs/architecture/08-networking-domains-edge.md` §5 (`svc_<projectId>_<environmentId>_<serviceId>`, “Nomes humanos podem mudar; IDs técnicos não”); `docs/architecture/09-data-model-apis-contracts.md` §5.3 (“o nome técnico deve ser determinístico e derivado de IDs/slugs sanitizados, mas o produto nunca depende desse nome como identificador primário”).
- **Decisão antiga:** doc 02 usa slugs humanos no nome do Service e da network.
- **Decisão mais recente:** doc 08 §5 usa IDs opacos e justifica: renomear Project/Environment/Service não pode provocar recriação de recurso nem colisão.
- **Impacto:** Renomear um Project com nomes baseados em slug forçaria recriar Service e network — downtime desnecessário e drift.
- **Resolução aplicada:** `resolved` a favor do doc 08 §5 (documento posterior, com justificativa explícita, e coerente com o doc 09 §5.3). `M01-16` gera nomes técnicos a partir de IDs; o nome humano vive apenas em labels informativas e na UI.

## SC-10 — Modelo de entrega: `Deployment` direto vs `Artifact → Release → Deployment`

- **Documentos envolvidos:** `docs/architecture/01-foundation.md` §5.4 (“Deployment: versão implantada de um Service, normalmente ligada a image digest/commit SHA”) e §13 (“Deployment snapshot”); contra `docs/architecture/02-build-deploy.md` §2/§10 e `docs/architecture/09-data-model-apis-contracts.md` §8 (`Build → Artifact → Release → Deployment`).
- **Decisão antiga:** modelo grosseiro da Parte 1, sem `Release` nem `Artifact` separados.
- **Decisão atual:** modelo de quatro objetos das Partes 2 e 9. `Release` é a unidade imutável promovível; `Artifact` é só a imagem; `EnvironmentSnapshot` (Parte 5 §9) substitui o “Deployment snapshot” da Parte 1.
- **Impacto:** Promoção HML→PROD sem rebuild e rollback por digest dependem da separação.
- **Resolução aplicada:** `resolved` a favor das Partes 2/5/9. A Parte 1 §5.4 é tratada como visão introdutória, não como modelo de dados.

## SC-11 — Backend de observabilidade não faz parte da stack congelada

- **Documentos envolvidos:** `docs/architecture/03-runtime-observability.md` §9 e §21 (“Observabilidade desacoplada… backend histórico substituível/externo inicialmente”); `docs/annexes/G-agent-oriented-development.md` §2 (tabela cita “Prometheus + Grafana Alloy/Loki”); `docs/AGENT_RULES.md` (tabela de stack aprovada **não** inclui observabilidade).
- **Situação:** não é um conflito de decisão, é uma decisão deliberadamente em aberto. A tabela do Anexo G pode ser lida por engano como stack congelada.
- **Impacto:** Escolher o backend cedo demais acopla o produto a um fornecedor; escolher tarde demais impede autoscaling e alertas.
- **Resolução:** `deferred`. `M09-03-metrics-backend-abstraction` cria o `MetricProvider` (exigido pelo doc 03 §8.3) e **exige um ADR** para o backend concreto adotado no primeiro release. Coletores (`M09-02`) são independentes do backend, exatamente como o doc 03 §9 prevê.

## SC-12 — Tenancy de `Cluster` e cluster de sistema

- **Documentos envolvidos:** `docs/architecture/09-data-model-apis-contracts.md` §4.1 (“`teamId` … nullable apenas para cluster de sistema explicitamente modelado”); `docs/architecture/04-identity-teams-security.md` §2 (“Cluster: Swarm pertencente ao Team”); `docs/architecture/06-infrastructure-provisioning.md` §1.1.
- **Situação:** a possibilidade de `teamId` nulo abre um caminho de autorização sem boundary de tenancy — exatamente o que o Anexo C §7.3 proíbe.
- **Impacto:** Se implementado cedo sem modelagem explícita, cria um furo de autorização (recurso sem cadeia de ownership verificável).
- **Resolução aplicada:** `resolved` de forma restritiva. Em todo este pack **`Cluster.teamId` é NOT NULL**. O “cluster de sistema” não é modelado; se vier a ser necessário, exige ADR próprio e uma Policy explícita de instância. Aplicado em `M01-08`.

## SC-14 — UC-011 sem dono: mover Environment para outro Cluster

- **Estado:** `resolved`
- **Documentos envolvidos:** `docs/architecture/10-ui-use-cases.md` (catálogo UC-011); `docs/implementation/M01/stories/M01-11-environment-entity.md` (adiava para M08); `docs/implementation/M10/stories/M10-12-environment-restore.md` (excluía do escopo).
- **Situação:** UC-011 é um Use Case do catálogo aprovado, mas as duas Stories que o tocavam o empurravam uma para a outra: `M01-11` adiava para M08 e M08 nunca o assumiu; `M10-12` o declarava fora de escopo. O resultado era um requisito obrigatório **sem dono** — exatamente o que o Goal §15 proíbe.
- **Impacto:** cobertura. Sem correção, o pack declararia 49 de 50 Use Cases cobertos sem dizer qual faltava.
- **Resolução aplicada:** criada a Story `M10-18 — Environment migration between Clusters`, em M10, reusando o Restore Engine (`M10-11`) em vez de criar um segundo motor de migração. Os ponteiros em `M01-11` e `M10-12` foram corrigidos para apontar para ela. O que **não** é migrável (volumes e bancos da aplicação) está declarado explicitamente na Story e em `COVERAGE.md` §11.

## SC-15 — Status de handoff divergente entre GOAL.md e o orquestrador

- **Estado:** `resolved`
- **Documentos envolvidos:** `docs/implementation/AGENT_ORCHESTRATOR.md` (“`MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`”); `scripts/run-codex-review.sh`; as seções `Final Handoff` de `M01/GOAL.md` … `M14/GOAL.md`.
- **Situação:** os blocos `Final Handoff` mandavam o implementer escrever `Status: READY_FOR_HUMAN_ACCEPTANCE`, enquanto o orquestrador só inicia o review independente quando encontra `Status: READY_FOR_REVIEW`. `M00/GOAL.md` — escrito com o orquestrador — já usava a forma correta.
- **Impacto:** operacional e bloqueante. Um Milestone concluído ficaria parado: o review nunca seria disparado, e o implementer estaria declarando aceitação humana, algo que `CLAUDE.md` proíbe explicitamente.
- **Resolução aplicada:** todos os `GOAL.md` de M01 a M14 foram normalizados para a forma canônica de `M00`: gerar `MILESTONE_REPORT.md` com `Status: READY_FOR_REVIEW`, mover `review-state.json.status` para `ready_for_review`, não iniciar o Milestone seguinte e **nunca** declarar `accepted` ou `human_acceptance`.

## SC-16 — Quem é o reviewer independente do Milestone

- **Estado:** `resolved`
- **Documentos envolvidos:** `CLAUDE.md` §Fixed Role; `AGENTS.md` §Fixed Role;
  `docs/decisions/ADR-0003-agent-review-orchestrator.md`;
  `docs/implementation/AGENT_ORCHESTRATOR.md`; `tools/opanel-loop/**`.
- **Situação:** o commit `4d2fb44` substituiu o orquestrador externo por um loop
  in-process no qual um subagente Claude é o reviewer independente e um script
  escreve `reviewing`, `fix_required` e `human_acceptance`. O `CLAUDE.md` vigente
  proibia nominalmente as três coisas, o `ADR-0003` continuava `accepted` e o
  `AGENTS.md` ainda declarava o Codex como reviewer. O repositório passou a
  conter um conjunto de governança que se contradizia — e justamente sobre quem
  pode declarar um Milestone aceito.
- **Impacto:** governança e segurança do processo. Uma exceção permanente a um
  invariante precisa virar ADR **antes** de virar padrão implícito
  (`AGENT_RULES`, §Documentation), e um conflito entre documentação e
  implementação se registra, não se resolve em silêncio.
- **Como apareceu:** finding **F03** do `MILESTONE_REVIEW_03.md` — o primeiro
  review executado pela própria máquina nova, que a apontou contra si mesma.
- **Resolução aplicada:** escrito o `ADR-0004`, que assume explicitamente o que
  se perde (o reviewer deixa de ser de outro fornecedor) e o que sustenta a
  independência (contexto novo, modelo diferente, read-only, verdict mecânico).
  `ADR-0003` marcado `superseded`; `CLAUDE.md` e `AGENTS.md` alinhados à máquina
  em uso. Fica em aberto, por exigir Story própria, incluir `tools/**` e
  `.claude/**` no `PIPELINE_PATHS` do `bin/merge-gate` — hoje uma mudança no loop
  é invisível para o check de alteração de pipeline.

## SC-13 — Referências informativas sem conflito

Registradas para evitar releitura como pendência. **Nenhuma ação necessária.**

| # | Documento | Situação |
|---|---|---|
| SC-13.1 | Anexo G §2 linha 103 (Swarm Executor em Ruby, Rust condicional) — I1 | Continua válido. Ruby é o baseline; Rust exige ADR e necessidade concreta. |
| SC-13.2 | Anexo E linha 20 (runbooks agnósticos de linguagem) — I2 | Agnosticismo deliberado. Não é decisão de stack. |
| SC-13.3 | Anexo C §21.1 (SCA em “Ruby/JS/Rust conforme stack final”) — I3 | Escopo efetivo: Ruby + JS + imagens OCI. Aplicado em `M00-10`. |
| SC-13.4 | Anexo G §3 e §6.1: nomes de arquivo e diretórios ilustrativos (`M00-foundation/`, `architecture/04-identity-security.md`) — pendências §3 do log de decisões | `docs/MASTER.md` é a fonte de roteamento correta. Este pack usa `M00/`…`M14/` conforme o Goal §3. |
| SC-13.5 | `docs/architecture/05-backup-restore-dr.md` §22: lista “Ordem de implementação” numerada de 14 a 25 | Artefato de conversão DOCX. Conteúdo íntegro; numeração cosmética. |

---

## Resumo

| Estado | Quantidade | Itens |
|---|---|---|
| `resolved` | 11 | SC-01, SC-02, SC-03, SC-05, SC-06, SC-09, SC-10, SC-12, SC-14, SC-15, SC-16 |
| `deferred` | 2 | SC-07 (inventário de componentes, dono `M00-05`), SC-11 (backend de métricas, dono `M09-03`) |
| `unresolved` | 2 | **SC-04** (prefixo de label — bloqueia `M01-16`), **SC-08** (estratégia de ID — bloqueia `M01-01`) |
| informativo | 5 | SC-13.1 … SC-13.5 |

**Ambos os itens `unresolved` precisam de decisão humana antes de M01 começar.** Eles estão registrados como ADRs `Proposed` em `docs/decisions/` e não podem ser resolvidos pelo loop autônomo.
