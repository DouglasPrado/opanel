# M08-02 — Node bootstrap script and preflight checks

## Objective
Entregar um script de bootstrap que prepara um host limpo, valida as pré-condições e falha fechado quando encontra condição insegura.

## Outcome
O operador executa um comando por HTTPS no host novo; o script verifica o ambiente, instala/valida o Docker e só então tenta o enrollment.

## References
- `docs/architecture/06-infrastructure-provisioning.md` §3.2 (preflight checks), §6.1 (bootstrap.sh), §17.1 (segurança de provisionamento)
- `docs/architecture/10-ui-use-cases.md` §16.4 (Add Node)

## Preconditions
`M08-01` done.

## Scope
- Script de bootstrap **versionado**, servido por HTTPS.
- Preflight do doc 06 §3.2: SO/arquitetura suportados, root/sudo, filesystem gravável, hostname resolvível, **relógio sincronizado**, disco e inodes, portas necessárias, Docker presente ou instalável, interface/IP de advertise, conectividade de saída.
- Escolha explícita do advertise address quando há múltiplas interfaces.
- Autenticação do enrollment por HTTPS antes de receber o material de join.
- Falha fechada: qualquer preflight reprovado aborta **antes** do join.
- Idempotência: reexecutar não corrompe o estado.

## Out of Scope
- Fluxo completo de enrollment do lado da plataforma (`M08-03`).
- Roles e labels (`M08-04`).
- Provisionamento por cloud provider (backlog).

## Security Requirements
- O script é obtido **somente por HTTPS** e possui versão explícita (doc 06 §17.1).
- O material de join só é entregue **após** a autenticação do enrollment; ele nunca está embutido no script.
- **Relógio fora de sincronia aborta**: TLS, tokens e consenso distribuído dependem disso.
- O script não grava o token nem o material de join em disco nem no histórico do shell quando puder ser evitado.
- Falha fechada em todos os preflights: nunca “continuar mesmo assim”.
- O script não abre portas além do necessário e não desabilita firewall.

## Observability Requirements
Cada preflight reporta resultado individual, no host e na plataforma. O motivo do aborto é específico, não “falha no bootstrap”.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| SO ou arquitetura não suportados | Aborta nomeando o que encontrou e o que é suportado. |
| Relógio dessincronizado | Aborta. |
| Porta ocupada | Aborta nomeando a porta. |
| Disco/inodes insuficientes | Aborta com os valores. |
| Múltiplas interfaces | Exige escolha explícita do advertise address. |
| Docker ausente | Instala conforme política, ou aborta se a política não permitir. |
| Sem conectividade de saída | Aborta nomeando o destino inalcançável. |
| Reexecução | Idempotente. |

## Acceptance Criteria
1. O script é servido por HTTPS e tem versão explícita.
2. Todos os preflights do doc 06 §3.2 são executados e reportados individualmente.
3. Qualquer preflight reprovado **aborta antes do join**, com motivo específico.
4. Relógio fora de sincronia aborta o bootstrap.
5. Com múltiplas interfaces, o advertise address é escolhido explicitamente.
6. O material de join só é entregue após a autenticação do enrollment.
7. O material de join não fica embutido no script.
8. O token e o material de join não são gravados em disco nem no histórico do shell quando evitável.
9. Reexecutar o script é idempotente.
10. O script não abre portas além do necessário nem desabilita firewall.
11. O resultado dos preflights é visível também na plataforma.

## Required Tests
- **integration**: cada preflight reprovando isoladamente e abortando.
- **security**: material de join não embutido; ausência de gravação do token; entrega apenas após autenticação.
- **Docker/Swarm**: bootstrap real em host de laboratório; reexecução idempotente.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, falha fechada provada em cada preflight, material de join protegido, Critical/High = 0.
