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
- **Resolução:** `resolved` em 2026-09-08. [`ADR-0001`](../decisions/ADR-0001-swarm-ownership-label-namespace.md) foi **aceito** pelo dono do repositório: o namespace é `com.opanel.*`, e as node labels de placement migram para `opanel.*` mantendo as chaves. `M01-16` está desbloqueada.
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
- **Resolução:** `resolved` em 2026-09-08. [`ADR-0002`](../decisions/ADR-0002-identifier-strategy.md) foi **aceito** pelo dono do repositório: ULID em `char(26)`, exposto como `<prefixo>_<ulid>`, com o registro de prefixos como constante única. `M01-01` está desbloqueada, e a convenção passa a ser irreversível na prática a partir da primeira tabela.
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

## SC-17 — `char(26)` do ADR-0002 não sobrevive ao round-trip de `db/schema.rb`

- **Documentos envolvidos:** `docs/decisions/ADR-0002-identifier-strategy.md`
  §Decision.1 (“Toda tabela de domínio usa `id char(26) PRIMARY KEY`”), aceito em
  2026-09-08; contra o pipeline de schema aprovado em M00 —
  `config.active_record.schema_format` no padrão `:ruby` e
  `ActiveRecord::Migration.maintain_test_schema!` em `spec/rails_helper.rb:14`,
  que carrega `db/schema.rb` no banco de teste.
- **Situação:** o adapter PostgreSQL do Active Record 8.1 mapeia o OID `bpchar`
  para `varchar` (`activerecord-8.1.3.1/lib/active_record/connection_adapters/postgresql_adapter.rb:702`,
  `m.alias_type "bpchar", "varchar"`). Verificado empiricamente em banco descartável:
  uma coluna `char(26)` volta do `SchemaDumper` como
  `create_table "…", id: { type: :string, limit: 26 }`. Um banco **migrado** fica
  com `character(26)`; um banco **carregado a partir do dump** — que é como o
  banco de teste é construído — fica com `character varying(26)`. A suíte inteira,
  incluindo os testes que provam as constraints do próprio ADR, roda contra uma
  forma que a migration não produz.
- **Impacto:** persistência, e a chave primária de **todas** as entidades da
  plataforma. Não há impacto comportamental enquanto a `CHECK
  (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$')` exigida por `M01-01` estiver presente: com
  todo valor tendo exatamente 26 caracteres, `char(26)` e `varchar(26)` são
  indistinguíveis em armazenamento, comparação, índice e join — o padding do
  `bpchar` nunca ocorre. O que diverge é a representação no dump, não o dado.
- **Como apareceu:** planejamento de `M01-01`, a primeira Story a criar tabela.
- **Resolução aplicada:** `open`. `M01-01` implementa `char(26)` **literalmente
  como o ADR aceito manda** (`AGENT_RULES`, §Specification Conflicts item 4: a
  decisão mais recente é inequívoca), com a `CHECK` que torna a perda do dump
  inerte. Não se reescreve um ADR aceito de passagem.
- **Decisão que falta ao dono do repositório**, e que não é do implementer:
  1. emendar o `ADR-0002` para `varchar(26)` + `CHECK` — mesmo armazenamento,
     garantia de banco mais forte (Crockford Base32, não só comprimento), dump
     fiel, nenhuma mudança de infraestrutura; ou
  2. `config.active_record.schema_format = :sql`, que é fiel à letra do ADR e
     muda o pipeline de banco do M00 (`db/structure.sql`, jobs de CI,
     `bin/migration-gate`) — fora do boundary de qualquer Story de domínio.
  Enquanto nenhuma das duas for tomada, a divergência é esta: o dump diz
  `varchar(26)`, a migration diz `char(26)`, e a `CHECK` garante que isso não
  muda o comportamento de nenhum valor válido.

## SC-18 — `M01-07` AC5 exige `Environment`, que só a `M01-11` cria

- **Documentos envolvidos:**
  `docs/implementation/M01/stories/M01-07-project-entity.md` — AC5 (“Arquivar um
  Project com Environments ativos é bloqueado com erro explicativo”), §Failure
  Scenarios (mesma regra) e §Out of Scope (“Environment (`M01-11`)”); contra
  `docs/implementation/M01/stories/M01-11-environment-entity.md` §Preconditions
  (“`M01-07` e `M01-08` done”).
- **Situação:** a dependência é circular e está escrita nos dois arquivos. A
  `M01-07` precisa de Environments ativos para provar o AC5 e declara Environment
  fora de escopo; a `M01-11`, que cria a entidade, exige a `M01-07` fechada antes
  de começar. Verificado no repositório em `M01-07`: `git grep -l "class
  Environment\|create_table :environments" -- app lib db` não retorna nada. Não
  existe tabela, modelo nem associação sobre a qual o guarda possa consultar.
- **Impacto:** um único critério de aceite, e nenhum comportamento. Com zero
  Environments no sistema, nenhum Project pode ter Environment ativo, então a
  regra é **vacuamente verdadeira** e nenhum arquivamento indevido é possível
  hoje. O que não existe é a **prova**: não há como escrever um exemplo que
  planta a condição e vê o Command recusar. Um critério que não pode falhar não é
  um critério satisfeito — é a mesma armadilha dos quatro checks que a revisão da
  `M01-05` e da `M01-06` derrubou.
- **Como apareceu:** planejamento da `M01-07`, ao mapear os nove critérios contra
  o que existe no repositório.
- **Resolução:** `resolved` em 2026-09-10, decisão do dono: o critério **migra**
  para a `M01-11`, onde pode ser provado. Está escrito no arquivo daquela Story
  como critério dela, com o caso negativo plantado, e nas Preconditions dela
  como obrigação herdada. A `M01-07` fecha com os oito critérios que provou.
  Sem ADR: é correção de autoria do pack, não decisão de arquitetura.
- **Resolução aplicada:** `closed` em 2026-09-10. A `M01-07` foi implementada com
  os oito critérios que podia provar naquela altura; o AC5 foi diferido
  oficialmente no relatório dela com esta entrada como referência. A `M01-11`
  criou a tabela `environments` e implementou o guarda de arquivamento com o caso
  negativo plantado: um Project com Environment ativo não pode ser arquivado, e
  um cujos Environments foram todos deletados pode. O código da `ArchiveProject`
  foi atualizado para implementar a regra e o TODO foi removido.

## SC-19 — o Swarm Executor como módulo do processo do Control Plane × serviço separado por RPC (doc 07 §2.2)

- **Documentos envolvidos:** `docs/architecture/07-internal-control-plane.md`
  §2.2 (diagrama: `API / Workers --[internal authenticated RPC]--> Swarm
  Executor --[docker.sock]--> Docker Engine`, com `Public API ---X---> docker.sock`
  marcado como proibido, e réplicas do executor "para disponibilidade") e §21
  ("RPC interno autenticado e autorizado por identidade de serviço"); contra
  `docs/implementation/M01/stories/M01-09-swarm-executor.md` §Scope ("Módulo
  `app/executors/` como único boundary") e §Application Layer ("Ele também não
  recebe requisição pública diretamente").
- **Situação:** a `M01-09` entregou o executor como módulo Ruby dentro do único
  processo Rails (`config/application.rb`), o mesmo que serve
  `app/controllers/**`. Não há segundo processo, Procfile de executor nem RPC.
  "Nenhuma rota alcança o executor" (AC1/AC10) é verdadeiro e provado; o que
  **não** existe é a fronteira de processo que o diagrama desenha. A revisão
  independente (C-1) apontou: uma RCE em qualquer outro lugar do mesmo processo
  alcança `SwarmExecutor`/`EngineClient` sem nenhum salto de RPC a vencer.
- **Impacto:** arquitetura e segurança, num componente Tier-0 (Anexo C §8, T01
  CRITICAL). Não é impacto comportamental hoje — todo teste da Story passa e a
  superfície de rota é a que a Story pede — mas é a forma que a arquitetura
  aprovada proíbe, e o `AGENT_RULES` é explícito: a Story não pode contradizer a
  arquitetura, e um conflito de segurança "nunca é resolvido inventando um novo
  padrão".
- **Como apareceu:** a `M01-09` registrou a divergência no relatório como "de
  forma, não de invariante" e seguiu, citando o próprio §Scope da Story. A
  revisão discordou, com razão: a precedência é arquitetura → Story, e não há ADR.
- **Resolução:** `resolved` em 2026-09-10 por
  [`ADR-0005`](../decisions/ADR-0005-swarm-executor-in-process-for-m01.md),
  aceito pelo dono. O executor fica como módulo do processo do Control Plane no
  M01; o doc 07 §2.2 **não** é editado e continua sendo o alvo. O ADR nomeia os
  controles compensatórios que existem e são testados, declara o risco aceito
  nas palavras da revisão (RCE no mesmo processo alcança o socket, não apenas as
  onze operações), e fixa três gatilhos de extração — segundo nó, API pública
  servida do mesmo processo, primeiro workload de terceiro. O primeiro deles
  deixa de ser prosa: a `M01-10` carrega uma fitness function que falha com mais
  de um `Node` registrado enquanto `app/executors/` viver no Control Plane.
  A extração é troca de transporte atrás do contrato `ExecutorCommand` /
  `ExecutionResult`, que a `M01-09` já entregou — não redesenho.
- **Resolução aplicada:** `open`. O módulo fica como está — é o que o AF-02 varre
  e o que as Stories seguintes (`M01-17`, `M01-18`) consomem — e a `M01-09` fica
  `blocked` até a decisão. Não foi construído um segundo processo com RPC
  autenticado por identidade de serviço dentro da Story: isso é topologia de
  deployment (imagem mínima, rootfs read-only, usuário do grupo do socket, rede
  overlay privada) que nenhuma Story do M01 declara, e fazê-lo aqui seria
  exatamente o padrão inventado.
- **Decisão que falta ao dono do repositório:**
  1. **ADR** aceitando o executor como módulo in-process em M01 e nomeando a
     Story/Milestone que o separa em serviço com RPC (a mitigação de T01 fica
     parcial até lá: rota ausente, allowlist, sem exec — mas sem fronteira de
     processo); ou
  2. **ADR** exigindo o serviço separado já, com a Story que o entrega antes de
     `M01-17`/`M01-18` consumirem o módulo.
  Enquanto nenhuma for tomada, o executor existe, está testado contra o Engine
  real, e é o que o AF-02 permite — e a Story não fecha.

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

## SC-20 — AC11 da M01-10: AF que vence ADR-0005 vive em um arquivo que o guard-edit nega editar

- **Documentos envolvidos:** `docs/implementation/M01/stories/M01-10-node-registration-and-observation.md` AC11 ("Uma fitness function falha quando há mais de um `Node` registrado e `app/executors/` continua carregado no processo do Control Plane, e é vista falhando contra um segundo nó plantado (`ADR-0005`, gatilho 1)"); `lib/gates/fitness_functions.rb` (único home para AF novo); `tools/opanel-loop/hooks/guard-edit.sh` (nega edições a `lib/gates/**` durante execução do loop).
- **Situação:** AC11 é norma. O único lugar onde uma AF nova vive é `lib/gates/fitness_functions.rb`. O hook `guard-edit.sh` nega edições a `lib/gates/**` a qualquer Story em execução — deliberadamente, para proteger o loop contra modificações que mudem o critério que o próprio loop usa para julgar a Story. A `M01-10` é a Story que torna o segundo node observável e deve disparar o gatilho; ela não pode editar o arquivo do qual o gatilho é feito.
- **Impacto:** AC11 fica não satisfeito. AC1–AC10 satisfeitos por completo. A fitness function que vença ADR-0005 precisa de uma Story de manutenção do loop (`M01-91`, `M01-93` ou equivalente) ou de uma decisão do dono que autorize o `guard-edit` a fazer exceção para esta Story especificamente.
- **Como apareceu:** planejamento de `M01-10`, reconhecendo que AC11 é a primeira Story a mencionar a condição que faz disparar o gatilho e conversando com a regra em `guard-edit.sh`.
- **Resolução:** `resolved` em 2026-09-10, por arbitragem registrada em `docs/implementation/M01/DECISIONS.md` (`ADR-0007`), com veredito **DEBT**. AC11 fica deliberadamente não satisfeito e é *contabilizado* por decisão, não por implementação. A Story implementa AC1–AC10 por completo.
- **Por que os três caminhos propostos caíram:** o caminho 2 (whitelist de `M01-10` em `guard-edit.sh`) foi **recusado**: relaxar o guard para a Story que ele julga é exatamente o que `ADR-0007` §"What does not change" fecha, e um gate nunca é editável pela execução que ele avalia. Os caminhos 1 e 3 estão indisponíveis porque as Stories de manutenção de gates saíram de `tasks.json` — pelo mesmo `ADR-0007`, manutenção de gate não é Story de Milestone. A AF é manutenção do loop dirigida por humano, feita fora de uma execução autônoma.
- **Dívida, com herdeiro nomeado:** M02, junto de `M02-EXEC-SPLIT`. A AF precisa existir antes que qualquer Milestone torne um segundo `Node` registrável (`M08-01`..`M08-03`). O que se perde até lá é o prazo mecânico: o gatilho 1 do `ADR-0005` volta a ser prosa, que é o modo de falha que o próprio ADR queria evitar. Os controles compensatórios do `ADR-0005` (AF-01, AF-02, o allowlist de operações, a ausência de primitive `exec`, a redação) continuam implementados, testados e intocados por este adiamento.
- **Como AC11 é contabilizado:** no relatório de `M01-10` a caixa continua **desmarcada**, e a evidência nomeia `ADR-0005` e `ADR-0007` — o caminho de deferral que `lib/gates/acceptance_mapping.rb` já aceita. Não é uma alegação de satisfação.

## SC-21 — AC7 de M01-12: Armazenamento de digest de imagem

- **Documentos envolvidos:** `docs/implementation/M01/stories/M01-12-service-desired-state-and-revisions.md` AC7; `docs/architecture/01-architecture-overview.md` §"Releases are immutable and identified by digest".
- **Questão:** Quando o usuário fornece uma referência de imagem OCI, CreateService deve:
  - (Opção A) Resolver tags mutáveis para digest buscando o registro e armazenar referência + digest resolvido, ou
  - (Opção B) Armazenar apenas digests fornecidos explicitamente pelo usuário e adiar resolução de tags para o reconciliador.
- **Situação:** AC7 como redigido é ambíguo. Diz "digest é o que fica em produção" sem proibir explicitamente o adiamento da resolução.
- **Resolução:** `deferred`. O veredito é **Opção B**. CreateService armazena `image_digest` apenas quando o usuário fixa uma referência com @sha256:. Tags mutáveis são armazenadas como-é em `image_ref` e resolvidas para digest pelo reconciliador M01-18 (ver AC2 naquela Story). Decisão registrada em `DECISIONS.md` em 2026-09-10.
- **Impacto:** CreateService e UpdateServiceDesiredState aceitam `image_ref` como recebido. Se a referência é `myregistry/app:v1.0`, `image_digest` é null; `image_digest` é preenchido apenas quando a referência é `myregistry/app@sha256:abc123...`.
- **Encaminhamento para M01-18:** O reconciliador lê `image_digest` (se presente) ou resolve `image_ref` buscando o digest, o armazena e o usa para deploy imutável.
- **Como AC7 é contabilizado:** No relatório de `M01-12` a caixa de AC7 fica **desmarcada** e a evidência nomeia este conflito (SC-21) e a Story de adiamento (M01-18 AC2). Não é satisfação automática — é deferral explícita com Story herdeira.
- **Situação em M01-18 (2026-09-11), metade resolvida e metade ainda `deferred`:** a Story herdeira implementou o que era decidível e **não** resolveu o resto sozinha.
  - **Feito:** o reconciliador lê `image_digest` e monta a referência imutável `registry/repository@sha256:…` (`ServiceReconciler::SpecTranslation.image_for`); quando nada fixa a imagem, `Opanel::ServiceDiff` responde `BLOCKED` com causa observável e **não** faz deploy por tag. AC2 de `M01-18` fica satisfeita literalmente — a imagem é referenciada por digest, e uma tag mutável nunca chega ao Engine.
  - **Não feito, e por quê:** resolver a tag mutável contra o registry exige uma leitura de registry que **não existe** no allowlist do Swarm Executor (`SwarmExecutor::OPERATIONS`), que a Story `M01-18` não menciona em Scope nem em References, e que `config/architecture/docker-lab.yml` torna improvável de provar — o laboratório é declaradamente utilizável **sem acesso a registry** ("a suite que silenciosamente depende do Docker Hub falha por razões que nada têm a ver com o código"), e é lá que a Docker/Swarm suite roda. Adicionar uma operação privilegiada nova, com superfície SSRF própria, para satisfazer meia frase de um conflito registrado seria inventar contrato — o que `AGENT_RULES` §"Specification Conflicts" proíbe.
  - **Encaminhamento proposto (não decidido por esta Story):** SC-21 permanece `deferred` e o dono passa da `M01-18` para a Story que introduzir **Release/Registry** por digest (M05/M06), onde a leitura de registry tem motivo próprio, orçamento de segurança e um lugar natural para o digest resolvido. Até lá, uma imagem sem digest é `BLOCKED` com causa, e não silenciosamente publicada por tag. Quem decide a mudança de dono é a arbitragem/o humano no PR, não o implementador.

## SC-23 — InboxEvent external_id column shadows UlidPrimaryKey.external_id method

- **Documentos envolvidos:** `docs/architecture/07-internal-control-plane.md` §10.2 (linha ???, `externalId` no contexto de dedup); `docs/decisions/ADR-0002-opaque-identifiers.md` (`external_id` como método público do ULID do objeto); `app/models/concerns/ulid_primary_key.rb` (define `external_id` como method que retorna o `id` serializado).
- **Decisão antiga:** Dedup spec doc 07 §10.2 nomeia o campo como `externalId` (formato JSON/API).
- **Decisão atual:** `InboxEvent` armazena o ID do evento externo em coluna `source_event_id`, **não** `external_id`. Razão: `UlidPrimaryKey` define `external_id` como accessor que retorna o ULID **próprio** do objeto (`ibevt_01H…`), e uma coluna de mesmo nome sombra o método. Durante `mark_processed!(result_ref)`, a validação `validates :external_id` lê o método (que retorna nil antes da save) em vez da coluna, falha com "External can't be blank", e `update!` falha.
- **Impacto:** Nome de coluna, índice único `(source, source_event_id)`, validações do modelo, referências em specs.
- **Resolução aplicada:** `resolved`. Coluna criada como `source_event_id` em migration 20260910000700_create_inbox_events. Semântica de AC4 (dedup por `source` + `externalId` do evento) **não muda** — `source_event_id` carrega o mesmo valor que `externalId` levaria. ADR-0002 continua válido: `external_id` permanece o método público para a identidade **interna** do `InboxEvent` (seu ULID). O número de serie `externalId` (do mensageiro) agora vive em `source_event_id`.
- **Documentação:** Doc 07 §10.2 menciona dedup schema como `(source, externalId)`; ela continua verdadeira. A implementação espelha a spec no sentido semântico; o nome Ruby reflete a coluna com precisão.

## SC-22 — Field naming: resourceType/resourceId vs scopeType/scopeId

- **Documentos envolvidos:** `docs/architecture/07-internal-control-plane.md` §5.1 (linhas 262-263, `scopeType/scopeId`); `docs/architecture/09-data-model-apis-contracts.md` §9.1 (linhas 306, `resourceType/resourceId`) e §21 (`CommandEnvelope`, `resourceType`/`resourceId`); `docs/implementation/M01/stories/M01-13-operation-and-outbox-transaction.md` §Scope (linha 19, `resourceType`/`resourceId`).
- **Decisão antiga:** doc 07 §5.1 usa `scopeType/scopeId` como nomes de coluna da Operation.
- **Decisão atual:** `resource_type`/`resource_id` em `operations` table e `Operation` model, seguindo doc 09 §21 (`CommandEnvelope`) que é o contrato que o Operation payload viaja.
- **Impacto:** nomes de coluna, nomes de campo do modelo, nomes de atributos expostos, and queries.
- **Resolução aplicada:** `resolved`. Doc 07 §5.1 é a primeira mente desta decisão; doc 09 §9.1 e §21 (CommandEnvelope) a refinam. O `CommandEnvelope` do doc 09 §21 é o contrato **viajante** que formata o payload da Operation para o executor (M01-15+), então a coerência com ele é mais crítica que a coerência com doc 07 §5.1 — que é um diagrama conceitual em prosa. `M01-13` implementa `resource_type`/`resource_id` no banco e no modelo; doc 07 §5.1 continua válida conceitualmente e não é editada (a próxima reescrita do Anexo A fará a atualização prosaica).

## Resumo

| Estado | Quantidade | Itens |
|---|---|---|
| `resolved` | 18 | SC-01, SC-02, SC-03, **SC-04**, SC-05, SC-06, **SC-08**, SC-09, SC-10, SC-12, SC-14, SC-15, SC-16, **SC-18**, **SC-19**, **SC-20**, **SC-22**, **SC-23** |
| `deferred` | 3 | SC-07 (inventário de componentes, dono `M00-05`), SC-11 (backend de métricas, dono `M09-03`), **SC-21** (resolução de tag de imagem, dono `M01-18`) |
| `unresolved` | 0 | — |
| informativo | 5 | SC-13.1 … SC-13.5 |

**Nenhum item `unresolved` que bloqueie implementação permanece.**  SC-04 e SC-08 foram decididos em 2026-09-08 pelo dono do repositório, através de `ADR-0001` e `ADR-0002`, ambos agora `accepted`. SC-18 e SC-19 foram decididos em 2026-09-10, o primeiro movendo o critério para a Story onde ele pode ser provado e o segundo através de `ADR-0005`. SC-20 foi decidido em 2026-09-10 por arbitragem (`ADR-0007`, veredito DEBT, registrada em `docs/implementation/M01/DECISIONS.md`): AC1–AC10 de `M01-10` estão satisfeitos, e AC11 fica deliberadamente não satisfeito, contabilizado por deferral a `ADR-0005` e `ADR-0007`, com a dívida herdada por M02 junto de `M02-EXEC-SPLIT`. SC-21 foi decidido em 2026-09-10 por arbitragem: AC7 de `M01-12` fica deliberadamente não satisfeito, armazenando apenas digests explícitos; resolução de tags mutáveis é adiada para `M01-18` AC2.
