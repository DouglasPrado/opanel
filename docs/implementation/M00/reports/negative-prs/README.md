# M00-11 — evidência dos cinco testes negativos

Required Test do `M00-11`: *"cinco PRs de teste, um por classe de falha (2–6),
cada um comprovadamente bloqueado"*.

Cinco pull requests foram abertos contra a `main` **protegida** — proteção ativa
desde `2026-09-08`, com os onze status checks obrigatórios e force-push negado —
cada um plantando **um** defeito, verificado localmente antes de ser empurrado.

Todos reprovaram. Nenhum foi mergeado: cada um foi **fechado** assim que o
resultado vermelho ficou registrado. Um PR fechado continua verificável por
terceiros, e é essa a diferença em relação à tentativa anterior.

| PR | Critério | Classe | Gate que reprovou | Estado |
|---|---|---|---|---|
| [#2](https://github.com/DouglasPrado/opanel/pull/2) | AC2 | typecheck | `static` | CLOSED |
| [#3](https://github.com/DouglasPrado/opanel/pull/3) | AC3 | lint | `static` | CLOSED |
| [#4](https://github.com/DouglasPrado/opanel/pull/4) | AC4 | teste | `unit` | CLOSED |
| [#5](https://github.com/DouglasPrado/opanel/pull/5) | AC5 | secret | `security-fast` | CLOSED |
| [#6](https://github.com/DouglasPrado/opanel/pull/6) | AC6 | migration | `migrations` | CLOSED |

O resultado por job de cada um está em `pr-NN-checks.json`, com o link da
execução; `pr-NN.json` traz o commit que a branch carregava.

## Falhas em cascata, e por que elas não invalidam nada

Cada PR reprovou no gate da sua classe, e vários reprovaram também em outros. As
cascatas têm causa conhecida:

- **#3 (lint)** quebrou `unit`, `integration`, `e2e-critical` e `swarm-smoke`
  além de `static`: o arquivo plantado em `app/models/` não define a constante
  que o Zeitwerk espera pelo nome, então o autoload falha em tudo que carrega a
  aplicação. O defeito é maior do que o pretendido; o gate que importa para o
  AC3 — `static` — reprovou.
- **#6 (migration)** quebrou quase tudo: `drop_table :users` invalida o schema
  para todo job que toca o banco. `migrations`, que é o gate do AC6, reprovou.
- **`security-fast` reprovou nos cinco.** A causa é o próprio #5: o scan varre
  árvore **e histórico**, e enquanto a branch com a chave existia no repositório
  ela era alcançável a partir de qualquer PR. Um teste negativo de secret tem
  alcance maior que o seu próprio pull request — anotado aqui porque afeta quem
  repetir este exercício.
- **`pr-gate` e `merge-gate`** reprovam por composição, agregando os demais.

## O que a tentativa anterior tinha de errado

Cinco PRs equivalentes foram abertos em 2026-09-08 e **mergeados por engano**,
levando os defeitos plantados — incluindo um bloco de chave privada — para a
`main`. O repositório foi recriado para remover o objeto, e com ele foram-se os
PRs e a evidência pública.

O registro daquele episódio está em [`../../FIX_REPORT_04.md`](../../FIX_REPORT_04.md).
Duas mudanças impedem a repetição:

1. **A `main` está protegida.** Um PR vermelho não pode mais ser mergeado, nem
   por acidente.
2. **Um PR negativo é fechado assim que o CI registra o resultado.** Depois
   disso ele não tem função nenhuma além de ser mergeado por engano — foi
   exatamente o que aconteceu.

## Por que aqui e não em `evidence/`

`.gitignore` exclui `docs/implementation/*/evidence/` porque evidência é saída
bruta de comando, regenerável ao reexecutar o check. Esta não é: ela vive no
resultado de CI de pull requests. Por isso mora em `reports/`, que é versionado.

Diferente da captura anterior, os PRs aqui **existem**: os links acima abrem, e
os checks podem ser conferidos sem depender deste arquivo.
