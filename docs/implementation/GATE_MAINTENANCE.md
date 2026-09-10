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
