# M14-01 — End-to-end acceptance suite for the critical journeys

## Objective

Consolidar em uma suíte de aceitação as jornadas que definem o produto, executadas ponta a ponta contra um ambiente completo — do login ao rollback.

## Outcome

Uma execução verde é a resposta objetiva para “a plataforma faz o que promete?”.

## References

- `docs/annexes/D-test-strategy.md` §11, §11.1, §20
- `docs/annexes/A-implementation-roadmap.md` §4, §5 — resultados observáveis por Milestone
- `docs/implementation/COVERAGE.md` — Use Cases

## Preconditions

- Todos os Milestones anteriores `done`; ambiente completo disponível.

## Scope

Jornadas cobertas, cada uma como cenário único e independente:

- Instalação → primeiro login → criação de Team, Project e Environment.
- Deploy a partir de imagem OCI → Service healthy → logs → scale.
- Conectar repositório → `git push` → build → Artifact por digest → Release → Deploy.
- Publicar em domínio default com HTTPS → adicionar domínio customizado → validar DNS → certificado emitido.
- Criar Secret → versionar → injetar no workload → rotacionar → rollback de versão.
- Promover Release de HML para PROD **sem rebuild** → rollback.
- Adicionar node → drenar node → remover node.
- Ver métricas, alertas e incidente; reconhecer e resolver.
- Backup → restaurar em ambiente novo → verificar integridade.
- Conectar agente MCP → executar operação dentro de scope → aprovar operação sensível → revogar conexão.
- Convidar usuário → transferir ownership → revogar acesso.

Regras da suíte:

- Seletores por role, atributo semântico ou test ID estável; **nunca** classe CSS frágil.
- Cada jornada é independente e cria seus próprios dados.
- Falha produz artefato de diagnóstico: screenshot, log e correlação de `request_id`.

## Out of Scope

- Testes de carga, chaos e segurança: M13.

## Security Requirements

- A suíte não usa credencial de produção nem dado real.
- Nenhum secret aparece em screenshot, log ou artefato de falha da suíte.

## Observability Requirements

- Relatório com jornada, duração, resultado e artefatos de diagnóstico.
- Mapeamento explícito de cada jornada para os Use Cases que ela cobre.

## Failure Scenarios

| Cenário | Comportamento esperado |
|---|---|
| Jornada crítica falha | Gate falha; release bloqueado. |
| Suíte flaky | Defeito: quarentena com dono e prazo; retry não mascara. |
| Secret em artefato de falha | Finding **Critical**. |
| Jornada depende de estado deixado por outra | Refatorar; independência é obrigatória. |

## Acceptance Criteria

1. Todas as jornadas listadas estão cobertas e verdes.
2. Cada jornada é independente e cria seus próprios dados.
3. Os seletores são estáveis e semânticos.
4. Falhas produzem screenshot, log e `request_id` correlacionável.
5. Nenhum secret aparece em artefato da suíte.
6. Cada jornada mapeia explicitamente para Use Cases do `COVERAGE.md`.
7. A suíte é gate bloqueante do Release Candidate.
8. Nenhum teste flaky permanece ativo sem quarentena documentada.

## Required Tests

- E2E (Playwright) das jornadas listadas.
- Verificação do mapeamento jornada → Use Case.

## Quality Gates

Local Quality Gate; gate de Release Candidate.

## Definition of Done

- [ ] 8 Acceptance Criteria com evidência.
- [ ] Suíte verde e estável.
- [ ] Self-review; `tasks.json` atualizado com commit.
