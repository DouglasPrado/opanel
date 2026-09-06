# M10-13 — Clean Rebuild orchestration

## Objective
Provar a promessa central do Milestone: reconstruir a plataforma inteira em **infraestrutura nova**, a partir de Platform DB + Vault + Registry, sem depender de nenhum disco, manager ou worker do cluster perdido.

## Outcome
Um Clean Rebuild executa o runbook do doc 05 §15.1 de ponta a ponta e termina com serviços saudáveis, TLS válido e tráfego restabelecido — com RPO e RTO medidos.

## References
- `docs/architecture/05-backup-restore-dr.md` §7.3 (Clean Rebuild como estratégia de independência), §14.3 (recuperar instalação inteira), §15 (runbook de DR), §15.2 (teste de independência)
- `docs/annexes/E-operational-runbooks.md` RB-24
- `docs/annexes/D-test-strategy.md` §15 (clean rebuild como evidência)

## Preconditions
`M10-06`, `M10-07` e `M10-11` done. Infraestrutura vazia disponível para o exercício.

## Scope
Orquestração das etapas do doc 05 §15.1, como fluxo de produto:
1. provisionar nodes novos; 2. instalar versão compatível; 3. conectar ao Backup Store e escolher o recovery point; 4. restaurar o Platform Database; 5. fornecer a Recovery Key e validar a MEK; 6. reconectar o Registry e **confirmar a disponibilidade dos digests**; 7. inicializar Swarm novo e registrar nodes; 8. recriar networks e materializar Swarm Secrets a partir do Vault; 9. subir ingress e distribuir certificados; 10. recriar Services por Environment respeitando placement e recursos; 11. health checks e testes sintéticos; 12. atualizar LB/DNS se os IPs mudaram; 13. registrar a conclusão e preservar os artefatos do incidente.

- **Reconcile em modo DR**: detectar recursos existentes no Swarm **antes** de `CREATE`, usando labels/IDs para adoção segura (RB-23).
- Medição de RPO e RTO reais.

## Out of Scope
- Fast Swarm Restore (`M10-14`) — caminho alternativo.
- Provisionamento automático dos hosts.
- Restauração de dados de aplicação.

## Application Layer
- **Commands:** `PlanCleanRebuild`, `ExecuteCleanRebuild`.
- **Reconciler:** modo DR do Service, Network, Secret e Certificate Reconcilers.

## Security Requirements
- **Teste de independência** (doc 05 §15.2, regra explícita): o runbook só é válido se puder ser executado **sem acesso a nenhum disco, manager ou worker do cluster perdido**. O teste automatizado precisa garantir isso.
- A Recovery Key é fornecida pelo operador; ela **não** vem do backup.
- Os digests necessários são confirmados **antes** de recriar Services — descobrir a ausência no meio do rebuild aumenta o RTO no pior momento.
- O reconcile em modo DR **não** duplica recursos: adota por ownership em vez de recriar (RB-23).
- Clean Rebuild é o caminho **preferido** após suspeita de comprometimento profundo (Anexo C §20), porque não carrega estado potencialmente adulterado.
- Toda a operação é auditada; os artefatos do incidente são preservados.

## Observability Requirements
- Progresso por etapa do runbook.
- **RPO e RTO medidos** e registrados como evidência (Anexo D §24).
- Inventário do que foi recriado × o que existia no snapshot.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Recovery Key indisponível | Bloquear: os secrets não serão recuperáveis; a plataforma diz isso claramente. |
| Digest ausente no Registry | Detectado **antes** de recriar; o Service afetado é listado; rebuild reprodutível a partir do commit é último recurso (doc 05 §21). |
| Recursos preexistentes no Swarm | Adotados por ownership, **não** duplicados. |
| Backup incompleto | Bloquear na validação de `M10-11`. |
| IPs de entrada mudaram | Etapa explícita de atualização de LB/DNS. |
| Falha no meio | Estado parcial registrado; retomada a partir da etapa. |
| Acesso ao cluster antigo usado sem querer | O teste de independência falha: é violação do critério. |

## Acceptance Criteria
1. O Clean Rebuild orquestra as 13 etapas do doc 05 §15.1 como fluxo de produto.
2. **O rebuild é executável sem acesso a nenhum disco, manager ou worker do cluster perdido**, provado pelo teste de independência.
3. A Recovery Key é fornecida pelo operador e **não** vem do backup.
4. Os digests necessários são confirmados **antes** de recriar Services; ausência é listada por Service afetado.
5. O reconcile em modo DR adota recursos preexistentes por ownership, **sem duplicar**.
6. Networks, Swarm Secrets, Services, ingress e certificados são recriados a partir do Desired State e do Vault.
7. Backup incompleto é bloqueado na validação.
8. Mudança de IPs de entrada tem etapa explícita de atualização de LB/DNS.
9. Falha no meio registra o estado parcial e permite retomada por etapa.
10. Health checks e testes sintéticos validam o resultado.
11. **RPO e RTO são medidos** e registrados como evidência.
12. Toda a operação é auditada e os artefatos do incidente são preservados.
13. O inventário do que foi recriado é comparado com o esperado.

## Required Tests
- **E2E/DR Lab**: Clean Rebuild completo em **infraestrutura vazia**, com RPO/RTO medidos.
- **security**: teste de independência (sem acesso ao cluster antigo); Recovery Key não vinda do backup.
- **Docker/Swarm**: adoção por ownership sem duplicar; digest ausente detectado antes.
- **integration**: falha no meio com retomada; backup incompleto bloqueado.

## Quality Gates
Local Quality Gate + DR Lab + `bin/security`. **Story crítica: exige plan mode.** É o critério central do Exit Gate de M10.

## Definition of Done
Os 13 Acceptance Criteria satisfeitos, rebuild completo em infraestrutura vazia com RPO/RTO medidos, teste de independência verde, Critical/High = 0.
