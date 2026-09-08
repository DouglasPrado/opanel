# M00-11 — evidência dos cinco testes negativos

Required Test do `M00-11`: *"cinco PRs de teste, um por classe de falha (2–6),
cada um comprovadamente bloqueado"*.

Cada PR abaixo plantou **um** defeito e foi reprovado pelo pipeline real — não
por simulação local contra `bin/ci-job`. Os resultados foram capturados da API do
GitHub antes de qualquer mudança de repositório, porque a prova mora no resultado
do CI e não no código: as branches eram descartáveis por construção.

| PR | Critério | Classe | Gate que reprovou | Commit |
|---|---|---|---|---|
| [#5](https://github.com/DouglasPrado/opanel/pull/5) | AC2 | typecheck | `static` | `972c76a62309` |
| [#7](https://github.com/DouglasPrado/opanel/pull/7) | AC4 | teste | `unit` | `ea19516f7e03` |
| [#9](https://github.com/DouglasPrado/opanel/pull/9) | AC6 | migration | `migrations` | `440226f61788` |
| [#10](https://github.com/DouglasPrado/opanel/pull/10) | AC3 | lint | `static` | `44529ba2cb35` |
| [#11](https://github.com/DouglasPrado/opanel/pull/11) | AC5 | secret | `security-fast` | `f797866c805a` |

## Por que aqui e não em `evidence/`

`.gitignore` exclui `docs/implementation/*/evidence/` porque evidência é saída
bruta de comando, regenerável ao reexecutar o check. Esta não é: ela vive no
resultado de CI de pull requests que já foram fechados e cujas branches já foram
apagadas. Reexecutar não a reproduz. Por isso mora em `reports/`, que é
versionado — do contrário desapareceria exatamente por ser evidência.

## Resultado completo por PR

### PR #5 — AC2 (typecheck)

- **reprovou:** `merge-gate`, `pr-gate`, `static`
- **passou:** `contract`, `frontend`, `integration`, `migrations`, `security-fast`, `setup`, `unit`

### PR #7 — AC4 (teste)

- **reprovou:** `merge-gate`, `pr-gate`, `unit`
- **passou:** `contract`, `frontend`, `integration`, `migrations`, `security-fast`, `setup`, `static`

### PR #9 — AC6 (migration)

- **reprovou:** `integration`, `merge-gate`, `migrations`, `pr-gate`, `security-fast`, `setup`, `static`, `unit`
- **passou:** `contract`, `frontend`

### PR #10 — AC3 (lint)

- **reprovou:** `integration`, `merge-gate`, `pr-gate`, `security-fast`, `static`, `unit`
- **passou:** `contract`, `frontend`, `migrations`, `setup`

### PR #11 — AC5 (secret)

- **reprovou:** `merge-gate`, `pr-gate`, `security-fast`
- **passou:** `contract`, `frontend`, `integration`, `migrations`, `setup`, `static`, `unit`

## Nota sobre a limpeza

Os cinco PRs foram mergeados por engano em 2026-09-08 e o conteúdo plantado foi
removido reapontando `main` e `loop/replace-orchestrator` para `31a2cae`, um
commit que nunca os conteve. As branches `ci-negative/*` foram apagadas.

Duas tentativas anteriores (PRs #6 e #8) foram fechadas por serem inválidas: os
defeitos plantados — `x=1` sem espaços e a chave de exemplo da documentação da
AWS — não são detectados por `rubocop-rails-omakase` nem pelo `gitleaks`, que
os ignora de propósito. Os gates estavam certos; os testes é que não testavam.

