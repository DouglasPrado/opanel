# M01-20 — Live service logs

## Objective
Permitir que o usuário diagnostique um Service sem acesso ao host, lendo logs ao vivo através do Control Plane, com RBAC e redaction.

## Outcome
A tela de Logs mostra a saída das Tasks do Service em tempo real, com identificação da Task, e continua funcionando quando uma Task é substituída.

## References
- `docs/architecture/03-runtime-observability.md` §10 (logs), §10.1 (dois modos), §10.3 (segurança de logs)
- `docs/architecture/10-ui-use-cases.md` UC-033, §13.1 (controles de logs)
- `docs/annexes/D-test-strategy.md` §12 (realtime, logs e terminal)
- `docs/annexes/C-threat-model-security-hardening.md` §17 (build/application logs)

## Preconditions
`M01-09` e `M01-19` done.

## Scope
- Streaming de logs **live** via `ServiceLogs` do Executor (Docker Service/Task logs).
- Seleção de escopo: Service inteiro ou Task específica.
- Follow ligado/desligado; reconexão com continuidade razoável.
- Identificação por Task e timestamp.
- **Redaction** de padrões sensíveis conhecidos antes de o dado sair do Control Plane.
- Backpressure: cliente lento não pode derrubar o worker nem fazer a memória crescer sem limite.
- Limite de streams simultâneos por usuário/Team.

## Out of Scope
- Logs históricos e busca (`M09-05`, `M09-06`) — em M01 só existe o modo live.
- Download/export de logs (`M09-06`, com audit).
- Terminal/exec (`M09-14`).
- Logs de build (`M05-14`).

## Application Layer
- **Queries:** `ServiceLogStream` (leitura, via Executor).
- **Policies:** exige `logs.read` no escopo do Service/Environment; `VIEWER` pode ler conforme escopo.

## API Impact
Stream servido pelo Control Plane; o navegador **nunca** fala com o Docker. O stream carrega `requestId` para correlação.

## UI Impact
Tela de Logs com: seletor de Task, follow, timestamps e indicação explícita quando o stream cai ou quando há lacuna. A UI sinaliza gaps em vez de fingir continuidade (doc 10 UC-033).

## Security Requirements
- **Nunca** logar valor de SecretVersion na plataforma; e aplicar redaction de padrões conhecidos no que vem da aplicação (doc 03 §10.3).
- Acesso a logs respeita RBAC por Environment; produção pode ter restrição adicional (o caminho fica pronto, é exercido em `M11-08`).
- O conteúdo de log da aplicação é **dado não confiável**: nunca interpretado como instrução, nunca renderizado como HTML ativo.
- Limite de streams e backpressure são controles de abuso (Anexo C §19: “Log streaming”).
- O acesso a logs de produção é auditável — o evento de abertura de stream é registrado.

## Observability Requirements
- Abertura e encerramento de stream registram `actor_id`, `service_id`, `environment_id` e `request_id`.
- Métrica: número de streams ativos e streams rejeitados por limite.

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Task substituída durante o follow | Permitir alternar instâncias e mostrar o lifecycle; não travar o stream silenciosamente. |
| Conexão cai | Reconexão com indicação explícita de lacuna. |
| Cliente lento | Backpressure; o worker não cresce em memória nem cai. |
| Muitos streams simultâneos | Rejeitar acima do limite com erro claro, não degradar o Control Plane. |
| Docker indisponível | Erro classificado na UI; não tela vazia sugerindo “sem logs”. |
| Log com padrão sensível | Mascarado antes de sair do Control Plane. |

## Acceptance Criteria
1. O usuário autorizado lê logs ao vivo de um Service com múltiplas Tasks.
2. Cada linha identifica a Task e o timestamp.
3. Substituir uma Task não interrompe silenciosamente a experiência: a UI mostra o lifecycle e permite alternar.
4. Queda de conexão é sinalizada e a lacuna é explícita — a UI não finge continuidade.
5. Padrões sensíveis conhecidos são mascarados antes de o dado sair do Control Plane, provado com valor plantado.
6. Conteúdo de log nunca é renderizado como HTML ativo, provado por teste com payload de injeção.
7. Um cliente lento não derruba o worker nem faz a memória crescer sem limite, provado por teste de backpressure.
8. O limite de streams por usuário/Team é aplicado e o excedente recebe erro claro.
9. Docker indisponível produz erro classificado, não tela vazia.
10. O navegador não fala com o Docker em nenhum momento.
11. Abertura de stream exige permissão e é registrada; negativo cross-team coberto.

## Required Tests
- **unit**: redaction; sanitização de conteúdo para renderização.
- **integration**: backpressure com cliente lento; limite de streams; Docker indisponível.
- **Docker/Swarm**: stream real com múltiplas Tasks; Task substituída durante o follow.
- **policy**: negativo cross-team; leitura sem permissão negada.
- **security**: valor sensível mascarado; payload de injeção não executado.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + testes de realtime do Anexo D §12.

## Definition of Done
Os 11 Acceptance Criteria satisfeitos, backpressure e redaction provados, Task substituída tratada, Critical/High = 0.
