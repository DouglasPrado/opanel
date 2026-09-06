# M04-06 — Platform default domain under a controlled wildcard zone

## Objective
Reduzir o atrito do primeiro deploy: todo Service público pode receber automaticamente um hostname sob uma zona wildcard controlada pela plataforma.

## Outcome
Ao publicar um Service, o usuário recebe `api-prod-albert.apps.<zona>` funcionando, sem configurar DNS.

## References
- `docs/architecture/08-networking-domains-edge.md` §12 (domínios default da plataforma), §15 (wildcard certificates)
- `docs/architecture/10-ui-use-cases.md` §5.1 (onboarding: configurar ingress/default domain)

## Preconditions
`M04-05` done. Zona DNS controlada pela plataforma configurada, com wildcard apontando para o endpoint do cluster.

## Scope
- Configuração da zona default da instalação e do `EdgeEndpoint` para onde o wildcard aponta.
- Geração determinística do hostname default a partir de service/environment/project, com sanitização e resolução de colisão.
- Criação automática do `Domain` + `DomainBinding` default quando o usuário opta por publicar.
- Reuso do **wildcard certificate** da zona controlada, em vez de emitir um certificado por Service.
- Possibilidade de desabilitar o domínio default por Service.

## Out of Scope
- Domínio customizado do cliente (`M07-01`).
- Emissão do wildcard em si (`M04-09`) — aqui é o consumo.
- Multi-cluster com endpoints distintos (M08).

## Application Layer
- **Commands:** `EnableDefaultDomain`, `DisableDefaultDomain`.
- **Queries:** `DefaultDomainForService`.

## Security Requirements
- O hostname default é gerado a partir de valores **sanitizados**; nenhum nome de Project/Service pode injetar caractere que quebre a regra de roteamento ou permita spoof de outro hostname.
- Colisão é resolvida deterministicamente e verificada contra a unicidade global de `M04-04`.
- Um Team **não** pode escolher um hostname default que colida com o de outro Team.
- O wildcard cobre apenas a zona controlada; ele nunca é usado para um domínio de cliente (blast radius, doc 08 §15).
- Desabilitar o domínio default remove a rota imediatamente.

## Observability Requirements
O hostname default aparece na UI do Service com estado derivado (resolve? cert ativo? router aplicado?).

## Failure Scenarios
| Falha | Comportamento esperado |
|---|---|
| Zona default não configurada | A funcionalidade é oferecida como “configurar depois”; o deploy sem domínio continua possível (doc 10 §5.1). |
| Colisão de hostname gerado | Resolvida deterministicamente com sufixo; nunca sobrescrever binding existente. |
| Nome com caracteres inválidos | Sanitizado; se o resultado for vazio ou ambíguo, usar o ID. |
| Wildcard indisponível | O domínio fica `PENDING_CERT`; a rota HTTP pode existir conforme política, mas nunca declarada como segura. |
| Renomear Project/Service | O hostname default **não** muda automaticamente: mudar URL sem aviso quebra clientes. A mudança é oferecida como ação explícita. |

## Acceptance Criteria
1. Existe configuração da zona default e do `EdgeEndpoint` do cluster.
2. Publicar um Service gera um hostname default determinístico e funcional.
3. O hostname é sanitizado; nenhum nome de recurso injeta caractere perigoso.
4. Colisão é resolvida deterministicamente, sem sobrescrever binding existente.
5. Um Team não consegue gerar um hostname default que colida com o de outro Team.
6. O certificado usado é o wildcard da zona controlada, não um por Service.
7. O wildcard **não** é usado para domínio de cliente.
8. Desabilitar o domínio default remove a rota imediatamente.
9. Renomear Project ou Service **não** altera o hostname default automaticamente.
10. Sem zona configurada, a plataforma oferece “configurar depois” e o deploy sem domínio continua possível.

## Required Tests
- **unit**: geração e sanitização do hostname; resolução de colisão; determinismo sob rename.
- **integration**: criação automática de Domain/Binding; desabilitar removendo a rota.
- **Docker/Swarm/E2E**: request HTTPS real no domínio default.
- **security**: injeção via nome de recurso; colisão entre Teams.

## Quality Gates
Local Quality Gate + suíte Docker/Swarm + `bin/security`.

## Definition of Done
Os 10 Acceptance Criteria satisfeitos, request HTTPS real no domínio default, injeção e colisão cobertas, Critical/High = 0.
