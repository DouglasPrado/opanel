---
title: "Fix Report — M00, attempt 01"
type: "fix-report"
milestone: "M00"
attempt: 1
---

# Fix Report — M00 · Attempt 01

Answers `CODEX_REVIEW_01.md` (`NOT_ACCEPTED — Critical: 1 · High: 15 · Medium: 0
· Low: 0`), reviewed at commit `2a38d11065dcce38e20afd695f446c27dcd33ddd`.

Role: **IMPLEMENTER**. This document does not contain a verdict and does not
declare acceptance. The independent verdict belongs to Codex.

## Resultado

| Item | Valor |
|---|---|
| Findings Critical corrigidos | 1 / 1 |
| Findings High corrigidos | 15 / 15 |
| Findings Medium / Low | 0 / 0 (o review não emitiu nenhum) |
| Commits | 11 (`04db7e6..77a3cb0`) |
| Diff | 57 arquivos, +3936 / −224 |
| Novas dependências | nenhuma |
| Novo ADR | nenhum |
| Bloqueios | nenhum |

Cada finding foi corrigido no defeito, nunca no teste, no gate ou no critério de
aceitação. Nenhuma supressão foi adicionada, nenhum threshold foi baixado e
nenhum arquivo foi excluído de scanner. Onde um controle já estava reduzido antes
deste ciclo, ele foi colocado sob waiver com dono e data — não relaxado (M00-R12).

## Commits

| Commit | Story | Findings |
|---|---|---|
| `04db7e6` | M00-15 | M00-R01, M00-R15 |
| `816b616` | M00-08 | M00-R02 |
| `b6788ef` | M00-09 | M00-R12 |
| `79a8ab7` | M00-06 | M00-R14, parte de M00-R03 |
| `f29ac35` | M00-11 | M00-R03, M00-R04 |
| `a859874` | M00-12 | M00-R05, M00-R06, M00-R07 |
| `76fb0c3` | M00-14 | M00-R08, parte de M00-R07 |
| `8d49e81` | M00-13 | M00-R10, M00-R13 |
| `6aacd38` | M00-10 | M00-R09 |
| `a858c54` | M00-17 | M00-R11, M00-R16 |
| `77a3cb0` | M00-18 | documentação dos controles acima |

Um commit por Story, cada um revisável e reversível isoladamente. Cada Story
tocada declara sua fronteira em `boundaries.yml` antes do commit: sem isso
`bin/gate post-commit --story <id>` **reprova** uma fronteira não declarada, de
modo que declará-las é o que faz a verificação incidir sobre este trabalho.

## Findings Critical

### M00-R01 — production sem redaction (`config/environments/production.rb:35`)

**Causa.** `config.log_formatter` era declarado em `config/application.rb` e nunca
chegava a production. O `initialize_logger` do railties lê `config.logger ||`
primeiro; como este environment fornecia um logger, o ramo que instala o
formatter jamais era alcançado. O sink efetivo era o `SimpleFormatter` do
ActiveSupport: sem JSON e sem redaction. Um password interpolado numa exceção de
driver era impresso íntegro.

**Correção.** O formatter é instalado explicitamente no logger e **antes** do
wrapper `TaggedLogging` — `TaggedLogging.new` estende o formatter que encontra, e
atribuí-lo depois substituiria o objeto estendido e levaria junto os métodos de
tagging. `config.log_tags` foi removido: o `request_id` é campo de primeira
classe de cada linha, e a tag também prefixaria `[<id>] ` dentro do valor
`message`, no lugar onde nenhum parser procura.

**Evidência.** `spec/security/production_logging_spec.rb` (novo) faz boot de um
logger de production real e escreve um password sintético:

- `does not print the value` / `masks it at the sink` — o valor não aparece;
- `masks the value and keeps the field` — campo estruturado mascarado;
- `is JSON with the mandatory fields`;
- `carries no bracketed log tag inside the message`.

O teste exercita o **sink**, não a configuração: uma asserção sobre
`config.log_formatter` teria passado antes do defeito e depois dele.

## Findings High

### M00-R02 — artefatos comprimidos/visuais não sanitizados (`bin/redact-artifacts:101`)

**Causa.** O scanner lia os bytes do contêiner. Um trace do Playwright é um ZIP
cujo JSON está DEFLATE-comprimido, então grepar o contêiner não encontrava nada e
o artefato era publicado com uma credencial recuperável dentro. Ler um contêiner
não é inspecioná-lo.

**Correção.** Três disposições em vez de duas: texto é mascarado; **arquivo é
aberto** (ZIP pelo central directory, gzip, um nível de aninhamento) e cada
entrada é escaneada descomprimida; **o que não pode ser inspecionado é
recusado** — ZIP corrompido, ZIP64, método de compressão desconhecido, formato
binário fora da lista `PUBLISHABLE_OPAQUE` — apagado, com exit não-zero. Não
saber o que há dentro não é o mesmo que saber que está limpo.

O padrão de header ganhou a forma que um trace realmente grava:
`{"name":"authorization","value":"Bearer …"}` põe toda a codificação JSON entre o
nome e o valor, e o padrão orientado a linha não alcançava através dela — foi por
isso que o canário dentro do arquivo passou por limpo mesmo depois de o ZIP ser
aberto.

**Evidência.** `spec/security/artifact_redaction_spec.rb`, com um ZIP DEFLATE
construído à mão (o fixture afirma `expect(trace).not_to include(<canário>)`, de
modo que um contêiner não comprimido não provaria nada):

- `opens a real archive and finds a secret that is only there when decompressed`;
- `leaves an archive alone when nothing inside it is sensitive`;
- `refuses an archive it cannot open`;
- `refuses a binary format it has no way to inspect`;
- `publishes a screenshot, and still scans its bytes`.

### M00-R03 — setup CI aponta para arquivo inexistente (`.github/actions/setup/action.yml:21`)

**Causa.** A action composta declarava `node-version-file: .nvmrc`, e esse arquivo
nunca existiu no repositório: todo job falhava no setup antes de executar um
único check.

**Correção.** `node-version-file: package.json`, lendo `engines.node` — a mesma
declaração que `bin/setup` passou a ler (M00-R14). Uma declaração só; duas cópias
é como CI e máquina de desenvolvedor terminam em majors diferentes, o que se
apresenta como build instável e não é.

**Evidência.** `spec/gates/ci_pipeline_spec.rb`:

- `points only at files that exist` — falha em qualquer `*-version-file` apontando
  para arquivo ausente, portanto pega a próxima ocorrência da mesma classe;
- `reads the Node version from the file bin/setup reads`.

O workflow completo está versionado em `.github/workflows/ci.yml`; `setup` entrou
na matriz do PR stage e em `required_for_merge`. **Não foi possível observar uma
execução remota**: `api.github.com` está inacessível deste ambiente. O que é
verificável localmente — a definição, a referência de arquivo e a execução de
cada job por `bin/ci-job` — está na tabela de gates abaixo.

### M00-R04 — runner transforma falha interna em PASS (`bin/ci-job:94`)

**Causa.** O laço lia a lista de comandos de um here-string, que em alguns hosts é
respaldado por arquivo temporário. Quando essa escrita falhava, o corpo do laço
nunca executava: o job imprimia `PASS` com zero checks e exit 0 — um gate
certificando uma execução que não aconteceu.

**Correção.** A lista é dividida no shell (`IFS=$'\n'`, com `set -f` para que um
comando contendo `*` não seja expandido contra o diretório). O número de checks
executados é comparado com o número declarado, consultado separadamente; qualquer
interrupção vira falha `job-integrity`. Um resultado que o Merge Gate não
consegue ler é falha da execução, não detalhe dela.

A mesma classe de defeito existia um nível abaixo, em `bin/_gate_lib.sh`: o exit
code do `mktemp` era descartado e o gate reportava sobre um arquivo de resultados
vazio — e lista vazia lê-se como "nada falhou". Agora o gate recusa começar sem
onde registrar, e recusa reportar quando os resultados registrados não batem com
os checks iniciados, no formato pedido (JSON quando `--format json`, para que
quem parseia receba um documento e não prosa em stderr).

**Evidência.** `spec/gates/ci_pipeline_spec.rb`:

- `refuses to report a result for checks it did not run`;
- `records one result per declared command, so a short run is visible`.

### M00-R05 — evidência pre-commit gravada após reprovação (`bin/gate:155`)

**Causa.** O registro era escrito incondicionalmente ao fim da execução. Um gate
pre-commit vermelho produzia um certificado para a árvore que acabara de
reprovar — e o check post-commit que existe para pegar `--no-verify` lia esse
certificado e passava.

**Correção.** O registro só é escrito quando **todos** os itens passaram, e nomeia
os checks em vez de contá-los. O post-commit passou a **ler** o registro: o gate,
a árvore, o resultado e os oito itens do Anexo I §12.1 — um registro a que falte
um item é falha, não uma lista mais curta que ninguém comparou com nada.

**Evidência.** `spec/gates/gate_scripts_spec.rb`:

- `is written only by a gate that passed`;
- `refuses a record whose own result was a failure`;
- `refuses a record that does not name every item of §12.1`;
- `refuses a record describing another tree`;
- `is not detected when the record exists` (o caso positivo).

### M00-R06 — testes relacionados e evidência por suíte não garantidos (`bin/test:55`; `lib/gates/post_commit.rb:127`)

**Causa (seleção).** `bin/test --changed` selecionava arquivos de *spec*
alterados. Um commit que tocasse apenas código-fonte não executava nada e o gate
registrava `tests PASS` — a forma de commit em que rodar a suíte mais importa era
exatamente aquela em que nenhuma rodava.

**Causa (evidência).** O check `tests` do post-commit lia um único campo,
`result`. Aceitava uma execução com zero exemplos, uma execução cujos relatórios
registravam falhas, e um `type` estreito no lugar de uma Story que declara
várias suítes.

**Correção.** `lib/gates/related_specs.rb` seleciona os testes **relacionados**
(Anexo I §11.1) por três caminhos: o próprio spec, o spec homônimo do arquivo, e
o raio de alcance conhecido da área. Ruby sob `app/` ou `lib/` que nenhum spec
cobre **reprova** em vez de selecionar nada — "não havia o que rodar" e "tudo
passou" não são a mesma resposta. O post-commit passou a exigir exemplos
executados, zero falhas registradas e cobertura das suítes que a Story declara em
`Required Tests`.

**Evidência.** `spec/gates/gate_scripts_spec.rb`:

- `selects a changed spec directly`, `selects the spec named after a changed
  source file`, `falls back to the suite that would notice, when nothing is named
  after the file`, `ignores what RSpec cannot be selected for`;
- `reports application code no spec and no suite covers`, `exits non-zero rather
  than selecting nothing`;
- `refuses a run that executed no examples`, `refuses evidence that contradicts
  itself`, `refuses evidence from a suite the Story does not declare`.

A regra encontrou um caso real neste próprio repositório: `lib/rubocop/cop/opanel/`
não tinha suíte mapeada. Foi mapeada para `spec/gates/lint_rules_spec.rb`, que é
onde esses cops são provados — plantando a violação e exigindo que seja
reportada.

### M00-R07 — reviews e critérios apenas declaratórios (`lib/gates/post_commit.rb:99`; `lib/gates/stop_gate.rb:138`)

**Causa.** O mapeamento de acceptance criteria era satisfeito por um relatório que
contivesse a palavra "acceptance" — um check sobre vocabulário, não sobre
trabalho. Os findings do reviewer vinham de um glob `review/*.json`, do qual este
repositório não tem nenhum: dezoito reviews em Markdown estavam ao lado, nenhum
era lido, e toda Story reportava zero findings bloqueantes — inclusive um
Milestone sem review algum.

**Correção.** `lib/gates/acceptance_mapping.rb` presta contas de cada critério
declarado, por número: ou **satisfeito** (caixa marcada, ou linha de tabela com
célula de evidência não vazia) ou **diferido a uma decisão nomeada** (ADR ou
Story), a mesma regra que o Suppression Gate aplica a uma regra silenciada.
`lib/gates/review_findings.rb` lê a forma canônica de
`docs/templates/REVIEW_FINDINGS.md` (JSON continua aceito) e trata **review
ausente como falha**: um check satisfeito por não escrever nada é pior que não
ter check. Post-commit e Stop Gate usam os dois módulos.

**Evidência.** `spec/gates/stop_gate_spec.rb`:

- `refuses a done Story whose report maps no acceptance criteria`;
- `refuses a report that maps only some of them`;
- `refuses a required Story with no review at all`;
- `reads the Markdown review the template defines`.

Verificação de que a leitura não é vazia: sobre `docs/implementation/M00/review/`
o parser lê 3–4 findings por Story (54 no total), incluindo dois `high` marcados
como resolvidos dentro da própria Story — ou seja, ele distingue severidade e
estado em vez de devolver lista vazia.

### M00-R08 — schema não aplicado (`lib/gates/pack.rb:71`)

**Causa.** `config/pack/tasks.schema.json` era chamado de contrato e não era
executado. O checker reimplementava cinco de suas regras à mão e ignorava o
resto: um `status` de tipo errado, `attempts: -3`, uma propriedade desconhecida,
um `commit` que não é hash e um `diagnosis` abaixo do mínimo declarado validavam
limpos.

**Correção.** `lib/gates/json_schema.rb` aplica o schema — `type`, `properties`,
`required`, `additionalProperties`, `enum`, `pattern`, `minLength`, `maxLength`,
`minItems`, `maxItems`, `minimum`, `maximum`, `items` — e **recusa validar contra
um keyword que não implementa** (`UnsupportedKeyword`) em vez de ignorá-lo em
silêncio. Essa recusa é o ponto: ignorar em silêncio é precisamente o modo de
falha que produziu este finding. Em seguida rodam as regras semânticas que nenhum
schema expressa (`file` que existe, `dependsOn` do Milestone, ciclo, `done` sem
commit).

Sem dependência nova: o schema usa treze keywords estruturais, e o que uma gem
adicionaria são os keywords que não usamos — enquanto o risco que ela removeria
já é coberto pelo `UnsupportedKeyword`.

**Evidência.** `spec/gates/pack_spec.rb`:

- `accepts the shape the schema declares`;
- `rejects #{description}` — tabela de payloads inválidos por tipo, padrão, enum
  e limite;
- `rejects an empty name`;
- `rejects a blockedReason carrying a field the schema does not declare`;
- `refuses to validate against a keyword it cannot apply`.

### M00-R09 — baseline de segurança incompleta (`spec/security/security_scan_spec.rb:285`)

Três partes de M00-10 estavam descritas e não executadas.

**Dependency Gate (AC7).** Existia como checklist; o que fazia as vezes dele era
um spec afirmando que dez nomes fixos apareciam em algum relatório. Uma lista
escrita à mão não percebe a décima-primeira dependência, que é aquela para a qual
o gate existe. `bin/dependency-gate` compara as dependências **diretas** da árvore
de trabalho com as do merge-base e exige, para cada nome adicionado,
justificativa em Story Report ou ADR e presença no lockfile.

**Allowlist do secret scan (AC4).** Era verificada contando caracteres `#` no
arquivo, o que um parágrafo no topo satisfaz para qualquer número de entradas.
`lib/gates/secret_allowlist.rb` casa cada entrada com o bloco de comentário
imediatamente acima, e uma linha em branco encerra o trecho que aquele comentário
explica — anexar sob um grupo alheio é como uma entrada passa a ser "justificada"
por uma razão escrita sobre outra coisa.

**Security Report (AC8, Anexo D §24).** Não existia. Um exit code diz que um scan
aconteceu e não diz o que foi escaneado, por qual versão de quê, nem quais
findings foram aceitos e por quem. `bin/security --out` escreve o relatório a
partir da execução que o produziu — scanner e versão, findings, severidade e
disposição, waivers ativos/expirando/expirados, commit e branch. O job
`security-fast` passa a flag, e a action `archive` já sobe e redige `tmp/security/`.

**Evidência.** `spec/security/security_scan_spec.rb`:

- allowlist: `explains every entry, checked one entry at a time`, `refuses an
  entry with no reason above it`, `is a check bin/security runs, not a spec nobody
  wires up`;
- dependency gate: `refuses a dependency no Story Report or ADR justifies`,
  `accepts one the Story Report explains`, `refuses an npm package that is
  declared but not pinned in the lockfile`, `runs inside bin/security, so CI
  executes it on every push`;
- report: `records the scanner and its version`, `records each finding with a
  severity and a disposition`, `records the waivers, so an accepted finding is
  visible as accepted`, `names the commit it describes`, `is written by the run
  that produced it, and archived`.

### M00-R10 — AF-06/07 não verificam os comportamentos declarados (`lib/gates/fitness_functions.rb:228`)

**AF-06.** Olhava cinco diretórios e chamava isso de "logs". Um
`Rails.logger.info(user.password)` num controller, num Command ou num reconciler
nunca era examinado — e o vazamento que a regra existe para pegar é exatamente o
que alguém escreve fora de um serializer. Agora há duas formas: um **emissor**
(serializer, jbuilder, audit, operation, event, job) nomeando um campo sensível, e
um **sink** (chamada de log, error reporter, `render`, `to_json`, publicação de
audit) em qualquer ponto da aplicação carregando um.

**AF-07.** Verificava que o arquivo da Policy declarava a ação e parava aí, de modo
que uma Policy que ninguém chama satisfazia "um caminho de autorização
server-side". Agora exige que o Command **alcance** a Policy, e diz isso por
extenso quando não alcança. O casamento é estrito (o nome da Policy, ou
`authorize` com a ação): qualquer ocorrência da palavra da ação casaria com
`record.destroy!` e liberaria um Command que não autoriza nada.

**Evidência.** `spec/gates/fitness_functions_spec.rb`:

- `detects a secret logged from a controller`, `detects a secret handed to an
  error reporter`, `detects a secret rendered in a response`, `accepts a
  controller that names a sensitive field without emitting it`;
- `detects a declared mutation whose Command does not exist`, `detects a Command
  that never reaches the Policy`, `accepts a Command that goes through the
  Policy`, `accepts a Command that authorizes by action name`.

### M00-R11 — bootstrap Swarm muta destino não identificado (`bin/swarm-lab:75`)

**Causa.** `up` era o único comando do arquivo que mutava um destino que não tinha
identificado. O label de nó identifica um daemon que **já é** o laboratório e não
consegue identificar um que nunca foi inicializado — label de nó exige um Swarm.
`up` consultava `LocalNodeState`, recusava um swarm ativo que não fosse nosso e
rodava `swarm init` contra qualquer coisa inativa. Um Engine de produção
aguardando entrar num cluster é exatamente isso, e por `docker info` é
indistinguível de um laptop vazio.

**Correção.** `assert_claimable!` verifica o **endpoint** antes da criação, contra
`lab.claimable_endpoints` em `config/architecture/docker-lab.yml`: um daemon
alcançado pela rede nunca é reivindicado automaticamente. Declaração versionada em
vez de variável de ambiente — apontar `DOCKER_HOST` para outro lugar torna a
verificação mais estrita, nunca mais frouxa, e alargar a lista exige a revisão
humana que `.github/CODEOWNERS` impõe a `config/architecture/`.

**Evidência.** `spec/integration/swarm_lab_spec.rb`, com transporte substituído em
memória (nenhuma chamada Docker real nos negativos):

- `refuses a daemon reached over the network`;
- `refuses it before any mutation, not after` — a prova que importa: nenhum
  `swarm init` é emitido;
- `refuses a local daemon already running a swarm that is not ours`;
- `accepts an inactive local daemon`;
- `declares the claimable endpoints in a versioned file, not in an env var`.

### M00-R12 — controles reduzidos para obter verde (`tsconfig.json:9`; `eslint.config.js`; `e2e/gallery.spec.ts`)

**Causa.** Onze controles estavam reduzidos e justificados por um comentário
escrito ao lado: dois flags de strictness do TypeScript, seis regras de ESLint
sobre a árvore importada, e três violações WCAG 2.2 AA registradas no baseline de
acessibilidade. Um comentário não tem dono, não tem declaração de risco e,
sobretudo, não tem data — é assim que um relaxamento temporário se torna
permanente sem ninguém decidir nada.

**Correção.** `config/quality/waivers.yml` registra cada um no mesmo contrato dos
waivers de segurança: `id`, `tool`, `finding`, `risk`, `owner`, `justification`,
`mitigation`, `removal_story`, `expires_at`. `lib/gates/control_reductions.rb` lê
as três configurações de volta e reprova uma redução sem waiver **e um waiver
expirado**; `bin/suppression-gate` o executa na passagem sobre o repositório
inteiro, portanto o job `static` do CI o carrega. `e2e/gallery.spec.ts` reprova
uma entrada do baseline que passou da data.

Os controles **não** foram restaurados aqui: cada entrada é dívida da biblioteca
de componentes que M00-05 importa verbatim e proíbe redesenhar, então o conserto
é upstream em gba.dev e reimportação. O que muda é que a exceção agora expira, em
`2027-03-31`, com dono nomeado.

**Evidência.** `spec/gates/lint_rules_spec.rb`:

- `is satisfied by this repository — every reduction is waived, owned and dated`;
- `detects an ESLint rule turned off with no waiver`;
- `accepts it once a waiver names it, with an owner and a date`;
- `blocks again the day after the waiver expires` — o mecanismo;
- `detects a TypeScript flag that is not enabled`;
- `detects a baselined accessibility violation with no waiver`.

E, em `e2e/gallery.spec.ts`, `carries no baseline entry that has outlived its
waiver`.

### M00-R13 — DDL destrutivo oculto em reversible (`lib/gates/migration_gate.rb:214`)

**Causa.** O checker pulava inteiramente o corpo de `reversible do ... end`. Isso
escondia um `drop_table` da regra de fase contract e um `add_index` da regra de
segurança de índice: escrever `reversible` tornava uma migration destrutiva
invisível para as duas regras que não têm nada a ver com reversibilidade. Pior, a
profundidade não era rastreada — decrementava no primeiro `end` de qualquer
nível, deixando o checker convencido de que ainda estava dentro do bloco pelo
resto do arquivo.

**Correção.** O bloco é percorrido como qualquer outro código, com um flag que
**apenas** a regra de reversibilidade pode ler, e a profundidade é contada
(`BLOCK_OPENER` reconhece o que precisa ser fechado por `end`). AF-09 herdava esse
bypass e deixou de herdar.

**Evidência.** `spec/gates/migration_gate_spec.rb`:

- `detects a drop_table written inside reversible`;
- `detects destructive SQL written inside reversible`;
- `detects an index build written inside reversible`;
- `stops treating code as reversible after the block's own end`;
- `still accepts a reversible destructive change that declares phase and
  reference` — o positivo, para que a regra não vire "reprove tudo".

### M00-R14 — setup positivo/idempotente não testado no CI (`spec/integration/development_environment_spec.rb:12`)

**Causa.** AC1 e AC3 de M00-06 eram verificados lendo o código-fonte de
`bin/setup`, que não pode falhar do jeito que um clone limpo falha. Um script que
lê o próprio texto é um script que ninguém executou.

**Correção.** O job `setup` (`config/ci/jobs.yml`) roda `bin/setup --skip-server`
**duas vezes** no checkout novo do runner — a primeira para o clone limpo, a
segunda para a idempotência, que é a propriedade que apodrece primeiro num script
de setup que as pessoas têm medo de reexecutar. O job entrou na matriz do PR
stage e em `required_for_merge`.

**Evidência.** `spec/integration/development_environment_spec.rb`:

- `is executed in CI, twice, on a disposable checkout`;
- `blocks a merge, so a broken setup cannot ship`;
- `is scheduled by the workflow`.

Execução real: `bin/ci-job setup` → `clean-clone PASS`, `idempotent PASS`, exit 0
(tabela de gates).

### M00-R15 — request_id perdido na fila (`app/jobs/application_job.rb:43`)

**Causa.** O `request_id` era lido de `Current` dentro de `perform`, e a requisição
já havia terminado — e resetado `Current` — muito antes de um worker pegar o job.
A serialização não o carregava.

**Correção.** `request_id` é capturado no enfileiramento, serializado ao lado de
`correlation_id` e restaurado em volta de `perform`. Mantido **separado** de
`correlation_id` de propósito: são o mesmo valor numa fronteira HTTP e divergem em
todo o resto — um job enfileirado por scheduler tem correlação e não tem
requisição. `defined?` em vez de `||=`, porque `nil` é a resposta correta para um
job sem requisição por trás, e reler `Current` a cada chamada deixaria um worker
atribuir um job à requisição de outro.

**Evidência.** `spec/unit/application_job_spec.rb` (`captures the enqueuing request
into the serialized payload`, `restores it when the payload is deserialized`, `is
nil when no request enqueued the job`, `does not re-read Current after it was
captured`) e `spec/integration/job_correlation_spec.rb` (novo): `writes the
request id into the persisted payload and a real worker runs it` — enfileira numa
requisição real, lê o payload persistido pelo Solid Queue e executa o job por um
worker, fora do contexto da requisição.

### M00-R16 — lifecycle Swarm incompleto e cleanup silencioso (`spec/support/swarm_lab.rb:32`)

**Causa.** O cleanup descartava o exit code de cada remoção: `down` podia deixar um
Swarm secret para trás e ainda imprimir "down" — e, depois que o nó sai do swarm,
nada mais o encontra. Além disso, M00-17 declara quatro tipos de recurso e o
harness só criava dois; o `status` e o `reset` do próprio laboratório já
procuravam secrets e configs órfãos, que nada podia criar, então metade do
caminho de limpeza nunca fora exercitada.

**Correção.** `SwarmLab.remove` distingue "já não existe" (estado desejado) de
"não removeu" (estado herdado pela próxima execução). `down` e `reset` param com o
motivo em vez de seguir adiante; o helper de teste tenta **todos** os recursos
antes de levantar, para que um recurso travado não abandone os demais. Foram
acrescentados `create_lab_secret` e `create_lab_config`, com o valor entrando por
stdin — um Swarm secret carregado de arquivo é um secret no disco de alguém, que
é justamente o que ele existe para evitar.

**Evidência.** `spec/integration/swarm_lab_spec.rb`:

- `creates a secret, finds it, and removes it`;
- `creates a config, finds it, and removes it`;
- `raises when a removal really fails, instead of discarding the exit code`;
- `attempts every resource before it raises, so one failure strands nothing`.

## Arquivos alterados

57 arquivos entre `2a38d11` e `77a3cb0`.

| Arquivo | Mudança |
|---|---|
| `config/environments/production.rb` | formatter instalado no logger efetivo, antes do TaggedLogging |
| `app/jobs/application_job.rb` | `request_id` capturado, serializado e restaurado |
| `bin/redact-artifacts` | arquivos abertos e inspecionados; formato não inspecionável recusado |
| `bin/ci-job` | divisão no shell, contagem de checks, escrita do resultado obrigatória |
| `bin/_gate_lib.sh` | `mktemp` verificado, prestação de contas dos resultados, falha em JSON |
| `bin/gate` | evidência pre-commit só quando o gate passou, nomeando os checks |
| `bin/test` | seleção dos specs **relacionados** |
| `bin/security` | `--out`, check de allowlist, Dependency Gate |
| `bin/setup` | major do Node lido de `engines.node` |
| `bin/suppression-gate` | executa o checker de reduções de controle |
| `bin/swarm-lab` | `assert_claimable!` antes de criar; falhas de remoção param a teardown |
| `bin/dependency-gate` | **novo** — CLI do Dependency Gate |
| `lib/gates/related_specs.rb` | **novo** — seleção de testes relacionados |
| `lib/gates/acceptance_mapping.rb` | **novo** — prestação de contas por critério |
| `lib/gates/review_findings.rb` | **novo** — leitura da review canônica |
| `lib/gates/json_schema.rb` | **novo** — validador dos keywords usados |
| `lib/gates/control_reductions.rb` | **novo** — reduções de controle e seus waivers |
| `lib/gates/dependency_gate.rb` | **novo** — dependências adicionadas vs. merge-base |
| `lib/gates/secret_allowlist.rb` | **novo** — razão por entrada da allowlist |
| `lib/gates/security_report.rb` | **novo** — Security Report do Anexo D §24 |
| `lib/gates/post_commit.rb` | acceptance, findings, tests e registro pre-commit lidos de verdade |
| `lib/gates/stop_gate.rb` | idem, do lado do Milestone |
| `lib/gates/pack.rb` | schema aplicado antes das regras semânticas |
| `lib/gates/fitness_functions.rb` | AF-06 com sinks; AF-07 com o caminho efetivo |
| `lib/gates/migration_gate.rb` | `reversible` percorrido, profundidade rastreada |
| `lib/gates/swarm_lab.rb` | `assert_claimable!`, `remove`, `docker_input` |
| `config/quality/waivers.yml` | **novo** — os onze controles reduzidos, com dono e data |
| `config/ci/jobs.yml` | job `setup`; `bin/security --out` no `security-fast` |
| `config/architecture/docker-lab.yml` | `lab.claimable_endpoints` |
| `.github/actions/setup/action.yml` | `node-version-file: package.json` |
| `.github/workflows/ci.yml` | `setup` na matriz do PR stage |
| `package.json` | `engines.node` |
| `tsconfig.json`, `eslint.config.js`, `e2e/accessibility-baseline.json` | comentário substituído por referência ao waiver |
| `e2e/gallery.spec.ts` | reprova entrada de baseline expirada |
| `spec/**` (16 arquivos) | os negativos citados acima |
| `docs/engineering/quality-gates.md`, `docs/engineering/ci-pipeline.md` | os controles novos e o orçamento marcado como desatualizado |
| `docs/implementation/M00/boundaries.yml` | fronteiras das Stories tocadas |
| `.gitignore` | linha em branco final removida (`git diff --check`) |

## Testes executados

Executados no commit `77a3cb0`, com o laboratório Docker no ar (nenhum exemplo
`pending`).

| Comando | Resultado | Exit code |
|---|---|---|
| `bin/test` | PASS — 651 examples, 0 failures, 0 pending | `0` |
| `bin/test:js` | PASS — 4 files, 74 tests | `0` |
| `bin/test:e2e` | PASS — 9 tests (chromium) | `0` |
| `bin/ci-job unit` | PASS | `0` |
| `bin/ci-job integration` | PASS — integration, request, policy | `0` |
| `bin/ci-job contract` | PASS | `0` |
| `bin/ci-job frontend` | PASS | `0` |
| `bin/ci-job e2e-critical` | PASS | `0` |
| `bin/ci-job swarm-smoke` | PASS — lab-up, lab, lab-down | `0` |
| `bin/ci-job setup` | PASS — clean-clone, idempotent | `0` |

`tmp/test-results/rspec-metadata.json`: `type=all`, `tests=651`, `failures=0`,
`errors=0`, `skipped=0`, `commit=77a3cb0…`.

## Quality Gates

| Gate | Resultado | Exit code |
|---|---|---|
| `bin/gate local` | PASS — 8 checks | `0` |
| `bin/gate pre-commit` (hook, em cada um dos 11 commits) | PASS — 8 checks | `0` |
| `bin/lint` | PASS | `0` |
| `bin/format --check` | PASS | `0` |
| `bin/typecheck` | PASS | `0` |
| `bin/fitness` | PASS — AF-01..AF-10, uma linha cada | `0` |
| `bin/migration-gate` | PASS — 2 migrations | `0` |
| `bin/suppression-gate` | PASS — 420 arquivos | `0` |
| `ruby bin/dependency-gate` | PASS | `0` |
| `bin/security --history --out tmp/security/security-report.json` | PASS — 8 checks | `0` |
| `bin/workspace-guardrail` | PASS | `0` |
| `bin/install-hooks --check` | PASS — `core.hooksPath=.githooks` | `0` |
| `bin/pack validate` | PASS — 15 Milestones contra o schema | `0` |
| `bin/pack next M00` | nenhuma Story elegível | `0` |
| `bin/ci-job static` | PASS — 5 checks | `0` |
| `bin/ci-job migrations` | PASS — 2 checks | `0` |
| `bin/ci-job security-fast` | PASS — 4 checks | `0` |
| `bin/stop-gate M00` | `ok: true` — 10 checks | `0` |
| `bin/swarm-lab up` / `down`, duas vezes | PASS nas quatro invocações | `0` |
| `bin/merge-gate` | **FAIL — `required-approvals`** | `1` |

`bin/merge-gate` reprova em um único item, `required-approvals`: "the pull request
is not reviewed". Não há pull request nem aprovação humana neste ponto do fluxo, e
é exatamente isso que o gate deve dizer — os outros cinco itens
(`migration-rollout-safe`, `rollback-known`, `story-status-consistent`,
`documentation-current`, `pipeline-change-authorised`) passam. Não é um defeito e
não foi contornado.

## Findings não corrigidos

Nenhum. O review emitiu 1 Critical e 15 High, todos endereçados acima, e **zero**
findings Medium ou Low.

## Conflitos e bloqueios

Nenhum bloqueio. Três limites do ambiente ficam registrados, nenhum deles tratado
como aprovação:

1. **CI remoto não observado.** `api.github.com` está inacessível deste ambiente,
   então nenhuma execução do GitHub Actions foi observada. O que é verificável
   localmente foi verificado: a definição dos jobs, a referência de arquivo da
   action de setup, e a execução de **todos** os jobs de PR e de merge por
   `bin/ci-job`, com exit code.
2. **`bin/merge-gate`** reprova por falta de revisão do pull request, como descrito
   acima.
3. **Arquivos do orquestrador não tocados.** `.claude/settings.json` e
   `scripts/run-claude-fix.sh` estavam modificados na árvore de trabalho antes
   deste ciclo — o `CODEX_REVIEW_01` já os registrou como pré-existentes. São do
   orquestrador; `CLAUDE.md` proíbe o IMPLEMENTER de modificá-los durante um
   Milestone ou uma correção de review, então foram deixados exatamente como
   estavam e **não** entraram em nenhum commit deste fix.

## Fronteiras alargadas

`boundaries.yml` ganhou entradas para M00-06, M00-08, M00-09, M00-10, M00-13 e
M00-15, que não declaravam nenhuma — sem elas
`bin/gate post-commit --story <id>` **reprova** por fronteira não declarada, de
modo que declará-las é o que sujeita este trabalho à verificação.

Três alargamentos deliberados, cada um com a razão escrita no arquivo:

- **M00-12** ganha `lib/gates/related_specs.rb`, `acceptance_mapping.rb` e
  `review_findings.rb`: M00-R06 e M00-R07 pedem uma seleção de testes e dois
  leitores que não cabem dentro de um script de shell.
- **M00-14** ganha `lib/gates/json_schema.rb` (M00-R08) e os mesmos dois leitores,
  mais a papelada do próprio loop — `review-state.json`, `CODEX_REVIEW_*.md`,
  `FIX_REPORT_*.md`. Nomeados aqui, e não acrescentados a
  `StoryBoundary::ALWAYS`: alargar uma declaração é ato revisável, editar o
  checker não é.
- **M00-06** ganha `package.json`, onde passa a viver a única declaração do major
  do Node.

Nenhuma fronteira foi alargada para acomodar código fora do escopo do finding que
a exigiu.

## Estado

`review-state.json` passa a `ready_for_review`, com `verdict` e os counts do
review anterior limpos. O IMPLEMENTER não emite verdict e não declara aceitação:
a próxima revisão independente é do Codex, sobre o commit final.
