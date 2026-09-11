---
title: "Opanel — Manutenção de gate e do loop"
type: "maintenance-backlog"
---

# Manutenção de gate e do loop

Trabalho sobre `bin/gate*`, `lib/gates/**` e `tools/opanel-loop/**` **não é Story
de Milestone**. Este arquivo é onde ele vive.

## Por que ele saiu do `tasks.json`

`guard-edit.sh` nega ao implementer, durante um run, exatamente os arquivos que
essas Stories precisam editar. Isso está certo — um builder não edita o próprio
juiz — mas significa que uma Story de manutenção de gate dentro do `tasks.json`
**não pode ser terminada por construção**. Não é uma Story que falhou; é uma
Story que a própria fila proíbe fechar.

O custo medido disso no M01, antes do [`ADR-0007`](../decisions/ADR-0007-autonomous-milestone-chain.md):

| Story | Assunto | Tentativas | Como terminou |
|---|---|---|---|
| `M01-91` | custo de execução do gate | 6 | `done` (`314a472`) |
| `M01-92` | evidência e feedback do loop | 2 | `blocked` — metade entregue (`87a0cdc`), metade negada pelo guard |
| `M01-93` | gate proporcional ao risco | 3 | `fix_required`, sem commit |
| `M01-94` | dividir a suíte de scripts do gate | 0 | nunca começou, dependia da `M01-93` |

Enquanto isso, `tasks.sh active` devolvia `M01-93` e o Stop hook repetia
"Story ainda aberta" a cada turno. Nenhuma Story de produto avançou entre
2026-09-10 02:39 e 08:00.

`M01-90` e `M01-91` continuam no `tasks.json` como `done`: são registro
histórico, já commitado e revisado. Só saíram as três que não fecharam.

## Em aberto

### GM-01 — AF-02 isenta o arquivo inteiro (era `M01-93`, High aberto)

`Af02OnlyExecutorTouchesDocker` pula o arquivo inteiro quando ele está em
`fitness_self_referential`, não só as linhas que justificam a isenção. O teste
compensatório escrito na rodada 2 pega a reprodução literal, mas a revisão
demonstrou que `require "docker"` e `"/var/run/" + "docker.sock"` passam pelos
dois. Evidência: `docs/implementation/M01/review/M01-93.md`.

Correção: isentar **linhas**, não arquivos.

### GM-02 — resto da `M01-92` (ACs 2, 5, 6, 7, 9)

Patch validado e reproduzido em `docs/implementation/M01/reports/M01-92.md`;
comando em `BLOCKERS.md`. Toca `lib/gates/post_commit.rb` e `bin/gate`.

### GM-03 — dividir a suíte de scripts do gate (era `M01-94`)

`spec/gates/gate_scripts_spec.rb` faz 27 `Open3.capture2e` contra binários de
gate. É a maior parcela isolada do custo local.

### GM-04 — o tamanho do `bin/`

`bin/` + `lib/gates/` + `spec/gates/` + `tools/opanel-loop/` somam **17 997
linhas**, contra 18 329 de código de produto (`app/` + `db/`). Cada gate novo
vira código que precisa de spec, que entra na suíte, que deixa a suíte lenta, que
gera uma Story para acelerar o gate — que foi literalmente a `M01-91`, a
`M01-93` e a `M01-94`.

Regra a partir daqui: **nenhum gate novo sem ADR**, e nenhum sem dizer qual sai.

## Como executar

Fora de um run — sem `.backlog-active` na raiz. `guard-edit.sh` libera esses
caminhos quando o arquivo não existe, e aí é trabalho humano-dirigido comum: um
commit por item, com o motivo.

### GM-05 — a seleção de specs relacionados não estreita

`RelatedSpecs::AREAS` mapeia áreas para diretórios inteiros. Medido:

```
app/models/authentication_attempt.rb  ->  1 spec nomeado          (o spec existe)
app/models/project.rb                 ->  spec/unit + spec/integration
app/models/cluster.rb                 ->  spec/unit + spec/integration
bin/gate                              ->  spec/gates inteiro
```

Um model sem spec homônimo cai no fallback de área e arrasta duas suítes. Na
`M01-11` isso deu **77 arquivos de spec** selecionados para uma story de uma
entidade. É a causa real do custo — o [`ADR-0008`](../decisions/ADR-0008-pre-commit-out-of-the-commit-path.md)
tirou o gate do caminho do commit, o que contorna o sintoma e não corrige isto.

Duas saídas, e a segunda tem troca:

1. dar spec homônimo aos models que não têm — sem perda de cobertura;
2. estreitar o próprio fallback (por exemplo, specs que referenciam a constante).
   Isso contraria o que o [`ADR-0006`](../decisions/ADR-0006-incremental-story-gates.md)
   decidiu — "classe sem spec mapeado, rode a classe inteira" — e custa cobertura
   de specs que exercitam a classe sem nomeá-la. Precisa emendar aquele ADR.

### GM-06 — o Stop hook sequestra qualquer sessão do repositório

`stop-gate.sh` age quando `.backlog-active` existe, sem verificar **qual** sessão
está falando. Uma sessão interativa aberta no mesmo repositório durante um run
recebe "Story X is still open. Close it" e é empurrada a escrever na story que a
sessão do autopilot já está escrevendo — dois escritores no mesmo `tasks.json` e
nos mesmos arquivos.

Aconteceu em 2026-09-10. A saída foi remover o `.backlog-active` à mão.

O arquivo deveria registrar o PID (ou o session id) do dono, e o hook sair
silenciosamente quando quem para não é ele.

### GM-07 — gates empilham quando um demora (aberto)

Quando um `bin/gate local` demora, a sessão lança outro por cima. Em 2026-09-10
houve três `bin/gate local --story M01-11` simultâneos disputando o mesmo banco.
O watchdog do `bin/autopilot` só pega sessão **parada**, não sessão lenta.

Precisa de trava por story — um lockfile em `tmp/gate/` que o segundo gate
respeite em vez de concorrer.

### GM-08 — a rodada 2 da review não sobrescreve o arquivo (aberto)

Na `M01-10` a rodada 2 gravou `C=0 H=0` no `tasks.json`, mas `review/M01-10.md`
continuou com a rodada 1 (`COUNTS 1 2 1 1`, mtime 11:21). Os dois discordaram, e
uma verificação posterior releu o arquivo e reabriu a story já commitada.

O `tasks.sh` recusa `done` sem review limpa e está certo — o artefato é a
evidência. O defeito é a rodada de correção não persistir o que produziu.

Neste caso a reabertura foi útil por acaso: o reviewer achou um defeito real
(`466cf7a`, o job de observação não carregava). Não é argumento para manter.

### GM-06 — resolvido em 2026-09-10

`.backlog-active` agora carrega o session id do dono na segunda linha, e
`stop-gate.sh` sai em silêncio quando quem para não é ele. Provado nos dois
sentidos. As skills gravam o dono ao abrir o run.
