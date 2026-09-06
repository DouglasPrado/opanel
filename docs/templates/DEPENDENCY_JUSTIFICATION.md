---
title: "Template — Dependency Justification"
type: "template"
---

# Template — Dependency Justification

One block per new gem or npm package, written inside the Story Report section
"Dependências novas". Format from Annex I §23.3; the questions come from the
Dependency Gate (Annex I §10.1).

"For convenience" is not a justification. A dependency added without this block is
rejected by the Dependency Gate in CI.

**No sensitive content.** See [`README.md`](README.md) — never paste a registry
token or a private repository credential here.

---

```markdown
### Dependency: `<name>` `<pinned version>`

- **Story:** `<STORY-ID>`
- **Ecosystem:** rubygems | npm
- **Problema resolvido:** <1-2 lines, tied to a requirement of this Story>
- **Alternativas avaliadas:** <what is already in the approved stack or installed>
- **Por que não bastam:** <short, concrete>
- **Maintenance:** <last release, activity, maintainer count>
- **Security:** <known advisories; result of the dependency scan>
- **License:** <SPDX id, and whether it is compatible with the intended distribution>
- **Escopo:** <proportional to the problem, or does it drag in a platform?>
- **Impacto de longo prazo:** baixo | médio | alto
- **Lockfile:** `Gemfile.lock` | `package-lock.json` — pinned at `<version>`
```

## Checklist (Annex I §10.1)

- [ ] Necessidade — a real problem in this Story requires it.
- [ ] Alternativa — the approved stack or an installed library does not solve it.
- [ ] Manutenção — maintained, with an acceptable release and security posture.
- [ ] Escopo — proportional; it does not import an entire platform.
- [ ] Licença — compatible.
- [ ] Segurança — no unmitigated Critical/High advisory.
- [ ] Lockfile — the effective version is pinned and reproducible.
