# Matriz de cobertura do MVP RBAC

## Escopo e base revisada

Esta matriz foi produzida na Etapa 0 como inventário estático da aplicação Rails/Vue. A seção de fechamento preserva aquele snapshot e registra a implementação do núcleo RBAC da Etapa 1; os sete módulos de negócio continuam sem integração.

| Item | Base |
| --- | --- |
| Branch principal revisada | `main` |
| HEAD revisado | `ab3e7ab96cff004207455a04b7bb7a7d8813594e` (`2026-11-21`) |
| Branch de Fluxos comparada | `feature/flow-manager-mvp` em `b617a1ede3eed9c1fa84701dc63b984cd9f3e28b` |
| Ancestral comum | `26d32738251b69317a178ee4f4462b1ae7753bf2` |
| Diagnóstico anterior | [`RBAC_TECHNICAL_ASSESSMENT.md`](RBAC_TECHNICAL_ASSESSMENT.md) |

Os caminhos abaixo são relativos à raiz do repositório. “Atual” descreve código encontrado, não uma recomendação. “Alvo” registra a cobertura que precisa existir antes de expor uma permissão no catálogo ou na interface. Specs listadas são cobertura existente do produto; ainda não testam um motor RBAC novo.

## Reconciliação das branches

`main` e `feature/flow-manager-mvp` são branches irmãs, não uma relação de avanço linear. `main` contém a implementação de Fluxos/Triagem em `a12f06a444` e seu próprio histórico posterior; a branch comparada encerra em `b617a1ede3`. Portanto, o comportamento-base para a implementação é o HEAD atual de `main`, não o commit isolado da feature.

| Superfície | `main` atual | Estado na branch de feature | Implicação para RBAC |
| --- | --- | --- | --- |
| Rotas e telas de Fluxos/Triagem | Rotas Rails e telas Vue existem; ambos os controllers exigem administrador. | A feature também introduz esses domínios, mas não contém todos os commits posteriores que agora estão em `main`. | Validar ações e campos na versão atual; não tratar o branch como substituto do `main`. |
| Reserva de Triagem | Conversas reservadas são retiradas da listagem comum por `Conversations::PermissionFilterService` e da busca global por `SearchService`. A reserva também limpa notificações de agentes. | A exclusão da fila comum e a busca pertencem à implementação da feature; a limpeza de notificações foi acrescentada em `main`. | Manter filtros antes de paginação/contagem e cobrir notificações residuais ao delegar leitura. |
| Visibilidade por caixa | `ConversationPolicy` e `PermissionFilterService` aplicam a configuração de acesso restrito por inbox, incluindo vínculo do agente com a conversa. | Ausente na ponta da branch de feature; chegou a `main` nos commits `cfccd60d1a` e `f78d0a8dfd`. | O escopo novo deve compor com a regra por inbox existente, sem alargar o universo de conversas. |
| Contagens, notificações e realtime | `main` adiciona escopos de contadores, filtragem de notificações e revalidação de acesso quando o job de ActionCable entrega o evento. Os commits relevantes incluem `0bde9029b3`, `d7c4a5c81d` e `c7947fcac6`. | Esses hardenings posteriores não estão na branch `feature/flow-manager-mvp`. | Grants revogados precisam valer na próxima requisição e na entrega de jobs/eventos já enfileirados; não remover essas proteções na integração. |
| Leitura da tela de Triagem | O endpoint de Triagem continua admin-only; a tela apresenta a conversa como somente leitura e separa a ação de transferência. | A UI da feature também contém modo somente leitura. | O modo Vue é UX: `ConversationPolicy#show?` participa de caminhos de mutação de conversa. Um grant de leitura de Triagem não pode ser implementado apenas por liberar `show?`. |

O diagnóstico anterior registra como base `main@cc6ddd6a`; esta matriz atualiza a referência para `ab3e7ab9`. A avaliação estática anterior continua útil, mas a branch/head e o inventário desta matriz são a referência para a próxima etapa.

## Baseline de autorização e principals

| Principal | Comportamento encontrado | Tratamento exigido pelo desenho |
| --- | --- | --- |
| `administrator` | `AccountUser.role` é enum por vínculo da conta. Policies e guards concedem operações administrativas na conta corrente. Disponibilidade do recurso continua sujeita a flag/edição/configuração. | Preservar autoridade integral na própria conta; grants RBAC não podem remover a última autoridade administrativa. |
| `agent` sem função nova | Mantém permissões legadas durante a migração. Por exemplo, pode ler/criar/editar contatos e empresas, mas não excluí-los; pode listar artigos/categorias, mas não administrá-los; não acessa relatórios, campanhas, Fluxos ou Triagem na Community atual. | Não converter agentes existentes automaticamente. |
| `agent` com função RBAC futura | Ainda não existe no core. | Nos domínios migrados, usar somente grants explícitos e escopos válidos; sem grant ou com escopo vazio, negar. Fora dos domínios migrados, preservar o legado. |
| Usuário e vínculo de conta | `User` é identidade global. `AccountUser` associa usuário, conta e enum de role; `EnsureCurrentAccountHelper` valida conta ativa e vínculo na API de conta. | Resolver role e grants pelo `AccountUser` da conta da requisição; nunca anexar role ao `User` global. |
| Token pessoal/dashboard | O token pessoal opera como o usuário autenticado e passa pela conta e autorização atuais. | Recalcular a autorização do vínculo atual a cada requisição; não confiar em permissões serializadas no token. |
| `AgentBot` | Identidade técnica com allowlist de ações e validação própria de conta. | Não herdar grants de agente por inferência. Definir explicitamente se uma operação futura suporta bot. |
| Platform API / `PlatformApp` | Identidade de provisionamento separada, com permissíveis próprios; pode criar/alterar vínculos de conta. | Revisar como caminhos alternativos afetam atribuições e a garantia do último administrador. Não converter PlatformApp em agente. |
| Super Admin | Console com autenticação e autorização próprias da instalação. | Manter como recuperação/operação global explícita; não tratar como administrador de conta comum nem como role atribuível. |
| Widget, Client API, visitante público do Help Center | Identidades externas, como contato/canal ou visitante, não são `AccountUser`. | RBAC de operadores não deve bloquear conteúdo público publicado nem conceder acesso ao visitante como agente. |
| Jobs, callbacks e eventos | Fluxos reservam conversas automaticamente; jobs e listeners executam efeitos de sistema e podem atrasar a entrega. | Definir operações de sistema e ator responsável. Para ação delegada em job/evento, revalidar autorização e audiência antes de executar/entregar. |

O core usa Pundit com `ApplicationPolicy` negando ações convencionais por padrão, mas controllers escolhem entre policies, `check_admin_authorization?`, checagens diretas e escopo por consulta. `Current.account_user` é o vínculo efetivo. A existência de uma rota ou de uma policy não significa que todos os caminhos auxiliares estejam cobertos.

O Enterprise tem `CustomRole` e `custom_role_id`, com catálogo e overlays próprios para conversas, contatos, relatórios e Help Center. Isso não é o RBAC do core Community e não deve virar a fonte de verdade da nova implementação. A proposta ainda precisa definir como os dois vínculos coexistem em runtime Enterprise, especialmente quando um mesmo `AccountUser` já tem `custom_role_id`.

## Matriz fechada dos sete módulos

### 1. Contatos

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V1 `GET/POST /contacts`, `GET/PATCH/PUT/DELETE /contacts/:id`, `GET /contacts/{active,search}`, `POST /contacts/filter`, `POST /contacts/{import,export}`, `GET /contacts/:id/contactable_inboxes`, `POST /contacts/:id/destroy_custom_attributes`, `DELETE /contacts/:id/avatar`. Sub-recursos incluem notas, etiquetas, vínculo de inbox, conversas e anexos. `POST /actions/contact_merge` mescla e remove o contato incorporado. |
| Proteção atual | `ContactsController` chama `ContactPolicy`: agente pode indexar, buscar, filtrar, criar, ver e atualizar; importação, exportação e exclusão exigem admin na Community. Sub-recursos têm controllers próprios e associação ao contato/conta; histórico de conversas e anexos também aplica o filtro de visibilidade de conversa. |
| Consultas e efeitos | Busca global também retorna contatos. Importação/exportação acionam processamento assíncrono; exportação usa [`Account::ContactsExportJob`](../app/jobs/account/contacts_export_job.rb). Mesclagem é uma operação destrutiva distinta da exclusão comum. Notas CRM não têm guarda por autor. |
| UI e testes existentes | [`contacts/routes.js`](../app/javascript/dashboard/routes/dashboard/contacts/routes.js). Specs: [`contacts_controller_spec.rb`](../spec/controllers/api/v1/accounts/contacts_controller_spec.rb), [`contacts/notes_controller_spec.rb`](../spec/controllers/api/v1/accounts/contacts/notes_controller_spec.rb), [`contacts/labels_controller_spec.rb`](../spec/controllers/api/v1/accounts/contacts/labels_controller_spec.rb), [`contacts/conversations_controller_spec.rb`](../spec/controllers/api/v1/accounts/contacts/conversations_controller_spec.rb), [`contacts/attachments_controller_spec.rb`](../spec/controllers/api/v1/accounts/contacts/attachments_controller_spec.rb), [`contacts_export_job_spec.rb`](../spec/jobs/account/contacts_export_job_spec.rb). |
| Alvo antes de habilitar grant | Separar leitura, criação, edição, exclusão, importação e exportação; aplicar escopo na consulta antes de busca, histórico, contagem e job de exportação. Definir como `contact_merge`, notas, labels, avatar/atributos e criação de `contact_inboxes` mapeiam para ações reais. |

### 2. Empresas

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V1 `GET/POST /companies`, `GET/PATCH/PUT/DELETE /companies/:id`, `GET /companies/search`, `POST /companies/:id/destroy_custom_attributes`, `DELETE /companies/:id/avatar`; sub-recursos de contatos (index/search/create/delete), conversas (index/filter), notas (index) e, em Enterprise, enrichment. |
| Proteção atual | `CompaniesController` exige Companies habilitado e chama `CompanyPolicy`. Agente pode ler, criar e editar; exclusão exige admin. Endpoints de associação de contato e histórico têm controllers próprios. Histórico usa filtro de conversa. |
| Consultas e efeitos | A flag/availability do CRM é separada da autorização. Busca global inclui dados relacionados; conversas vinculadas dependem da visibilidade do próprio atendimento. Avatar e atributos são mutações adicionais. |
| UI e testes existentes | [`companies/routes.js`](../app/javascript/dashboard/routes/dashboard/companies/routes.js). Specs: [`companies_controller_spec.rb`](../spec/controllers/api/v1/accounts/companies_controller_spec.rb), [`companies/contacts_controller_spec.rb`](../spec/controllers/api/v1/accounts/companies/contacts_controller_spec.rb). |
| Alvo antes de habilitar grant | Separar leitura, criação, edição e exclusão; definir se vincular/desvincular contatos, editar atributos e apagar avatar entram em `update` ou são grants distintos. Restringir consultas e associações à conta e aplicar escopo antes de search/filter. A flag de disponibilidade não pode ser alterada por grant. |

### 3. Relatórios

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V2 `/reports` e ações `summary`, `bot_summary`, `agents`, `inboxes`, `labels`, `teams`, `conversations`, `conversations_summary`, `conversation_traffic`, `drilldown`, `bot_metrics`, `inbox_label_matrix`, `first_response_time_distribution`, `outgoing_messages_count`; `/summary_reports/{agent,team,inbox,label,channel}`; `/live_reports/{conversation_metrics,grouped_conversation_metrics}`. V1 acrescenta CSAT e, conforme edição/flag, SLA, reporting events e monitors. Algumas ações de report retornam CSV. |
| Proteção atual | `ReportPolicy#view?` exige admin na Community; Enterprise pode delegar via `report_manage`. `drilldown` tem uma checagem direta de admin no controller. CSAT/SLA/events/monitors possuem policies, flags e guards próprios; não presumir que uma autorização central cubra todas as rotas. |
| Consultas e efeitos | Filtros e agregações consultam equipes/inboxes da conta. O filtro de equipe em live reports busca a equipe na conta, mas não exige que o leitor pertença a ela. CSV está associado a ações GET de relatório, então read/export ainda não são fronteiras independentes. |
| UI e testes existentes | [`reports.routes.js`](../app/javascript/dashboard/routes/dashboard/settings/reports/reports.routes.js). Specs: [`reports_controller_spec.rb`](../spec/controllers/api/v2/accounts/reports_controller_spec.rb), [`summary_reports_controller_spec.rb`](../spec/controllers/api/v2/accounts/summary_reports_controller_spec.rb), [`live_reports_controller_spec.rb`](../spec/controllers/api/v2/accounts/live_reports_controller_spec.rb), [`csat_survey_responses_controller_spec.rb`](../spec/controllers/api/v1/accounts/csat_survey_responses_controller_spec.rb). |
| Alvo antes de habilitar grant | Separar `read` e `export` em toda rota que produz CSV/download, incluindo caminhos V1 relevantes. Aplicar escopo antes de filtros, agregações, drilldown e exportação. Manter regras de edição/flag e exceções de cada superfície; não oferecer escopo por equipe até revisar todas as consultas. |

### 4. Base de conhecimento

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API administrativa V1 `/portals` e sub-recursos `/portals/:portal_id/{articles,categories}` com listagem, detalhe, criação, atualização, exclusão e reorder. Há logo, archive, envio de instruções e SSL status. Artigos têm lote de tradução, atualização de status/categoria e exclusão. Rotas públicas distintas servem portais/artigos em `/hc/...`. |
| Proteção atual | `ArticlePolicy` e `CategoryPolicy` permitem listagem a membro da conta; detalhe e mutações exigem admin na Community. Portal tem policy própria; Enterprise adiciona delegações. Tradução em lote depende de integração/edição. Rotas públicas são para visitantes e não usam autorização de operador. |
| Inconsistência de rota | `PATCH /portals/:id/archive` está declarado e `PortalsController#archive` tenta alterar o portal, mas não foi encontrado `archive?` em `PortalPolicy`, `ApplicationPolicy` nem overlays Enterprise revistos. Como `check_authorization` usa o nome da ação, o caminho não tem autorização explícita e tende a falhar antes da ação. Precisa de correção própria ou remoção/definição antes de classificar no catálogo. |
| UI e testes existentes | [`helpcenter.routes.js`](../app/javascript/dashboard/routes/dashboard/helpcenter/helpcenter.routes.js). Specs: [`articles_controller_spec.rb`](../spec/controllers/api/v1/accounts/articles_controller_spec.rb), [`categories_controller_spec.rb`](../spec/controllers/api/v1/accounts/categories_controller_spec.rb), [`portals_controller_spec.rb`](../spec/controllers/api/v1/accounts/portals_controller_spec.rb), [`articles/bulk_actions_controller_spec.rb`](../spec/controllers/api/v1/accounts/articles/bulk_actions_controller_spec.rb). Busca global também tem endpoint de artigos. |
| Alvo antes de habilitar grant | Separar leitura, criação, atualização, publicação (mudança de status), exclusão e reorder onde cada operação existir; cobrir ações em lote e portal. Distinguir conteúdo administrativo de publicação pública. Definir escopo de portal/artigo real; a proposta não oferece leitura privada por artigo sem mecanismo correspondente. |

### 5. Campanhas

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V1 `GET/POST /campaigns`, `GET/PATCH/PUT/DELETE /campaigns/:id`; em Enterprise, analytics de métricas/contatos e histórico da campanha na conversa. |
| Proteção atual | `CampaignPolicy` exige administrador para listar, ver, criar, atualizar e excluir. Os registros são consultados pela conta; analytics e histórico têm controllers/condições próprios. |
| Consultas e efeitos | Criar/atualizar pode configurar `enabled`, `scheduled_at`, audiência, inbox e regras. [`TriggerScheduledItemsJob`](../app/jobs/trigger_scheduled_items_job.rb) enfileira [`Campaigns::TriggerOneoffCampaignJob`](../app/jobs/campaigns/trigger_oneoff_campaign_job.rb), que pode iniciar envio; não foi localizada uma rota separada chamada “disparar”. Disponibilidade por canal/plano é independente do role. |
| UI e testes existentes | [`campaigns.routes.js`](../app/javascript/dashboard/routes/dashboard/campaigns/campaigns.routes.js). Spec: [`campaigns_controller_spec.rb`](../spec/controllers/api/v1/accounts/campaigns_controller_spec.rb); analytics tem testes Enterprise próprios. |
| Alvo antes de habilitar grant | Separar leitura, criação, edição e exclusão. Garantir que leitura não altere estado, calendário ou audiência. Decidir se agendar/ativar envio permanece coberto por create/update ou se existe uma operação real separada; não adicionar `campaigns.execute` apenas como checkbox sem rota/comando próprio e testes. |

### 6. Fluxos

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V1 `GET/POST /conversation_flows`, `GET/PATCH/PUT /conversation_flows/:id`. A atualização inclui habilitação, definição e `inbox_ids`. **Não há rota DELETE**; desativação ocorre por update. |
| Proteção atual | `ConversationFlowsController` usa `check_admin_authorization?` para index, show, create e update. Consulta o fluxo em `Current.account`; atribuição de inbox valida que todos os IDs pertençam à conta. |
| Consultas e efeitos | `ReservationService` executa automaticamente em callbacks elegíveis de conversa/mensagem; não existe endpoint manual de execução. Alterar `enabled` e inboxes muda futuras reservas. Conversas reservadas ficam fora da listagem e busca comum. |
| UI e testes existentes | [`flows.routes.js`](../app/javascript/dashboard/routes/dashboard/settings/flows/flows.routes.js). Specs: [`conversation_flows_controller_spec.rb`](../spec/controllers/api/v1/accounts/conversation_flows_controller_spec.rb), [`conversation_flow_spec.rb`](../spec/models/conversation_flow_spec.rb), [`reservation_service_spec.rb`](../spec/services/conversation_flows/reservation_service_spec.rb). |
| Alvo antes de habilitar grant | Separar leitura de alteração da definição e alteração de vínculos com inbox. `manage_inboxes` é uma mutação real dentro de update, embora ainda não tenha endpoint próprio. Escopar fluxos à conta e às caixas válidas. Não cadastrar permissão de exclusão. |

### 7. Triagem

| Item | Cobertura encontrada |
| --- | --- |
| Endpoints e operações reais | API V1 `GET /triage/conversations`, `GET /triage/conversations/:id`, `POST /triage/conversations/:id/transfer`. Transferência exige equipe da conta e execução ainda em triagem; serviço aplica lock/validações de estado. Não há CRUD de Triagem nem exclusão. |
| Proteção atual | `Triage::ConversationsController` exige admin para listar, abrir e transferir. A fila consulta execuções da conta e aceita filtros por caixa/busca. `ConversationPolicy#show?` participa de mutações usuais; liberar o detalhe para um agente também poderia abrir resposta/notas/atribuição por APIs de conversa. |
| Isolamento e eventos | Conversas em triagem são excluídas da listagem normal e da busca global. `ConversationFlowBroadcasts` restringe parte dos eventos; `ActionCableBroadcastJob` revalida audiência na entrega. Reserva remove notificações de agentes e serviços de email/push verificam destinatários. Contadores e notificações têm caminhos próprios. |
| UI e testes existentes | [`triage.routes.js`](../app/javascript/dashboard/routes/dashboard/triage/triage.routes.js), [`TriageView.vue`](../app/javascript/dashboard/routes/dashboard/triage/TriageView.vue), [`TransferPanel.vue`](../app/javascript/dashboard/routes/dashboard/triage/TransferPanel.vue). Specs: [`triage/conversations_controller_spec.rb`](../spec/controllers/api/v1/accounts/triage/conversations_controller_spec.rb), [`transfer_service_spec.rb`](../spec/services/conversation_flows/transfer_service_spec.rb), mais specs de reserva, busca, policy, notificações e ActionCable. |
| Alvo antes de habilitar grant | Separar `triage.read` de `triage.transfer` e de qualquer permissão de mutação de conversa. A leitura precisa limitar fila, detalhe, histórico/contato/anexos, contagens e audiências; o destino precisa validar `selected_teams` antes de mudar a equipe. Aplicar escopo de origem por fluxos/caixas e manter reservas invisíveis a agentes sem grant em listagem, busca, eventos, notificações, email/push e jobs. |

## Inconsistências registradas na Etapa 0

| Achado | Efeito e encaminhamento |
| --- | --- |
| `RBAC_CHATWOOT_ARQUITETURA_E_IMPLEMENTACAO.md`, citado como base, não existe em `docs/` neste checkout. O diagnóstico técnico existe. | A matriz usa a especificação anexada e o código atual como fontes. Se há uma cópia de arquitetura fora do repositório, ela não foi possível de reconciliar nesta etapa. |
| `administrator` conserva autoridade integral, mas a UI proposta fala em atribuir role ao agente sem definir o que ocorre se um `AccountUser` admin receber uma role RBAC. | Definir validação/precedência: role customizada não pode reduzir admin nem dar um caminho implícito de delegação. A invariável do último admin deve cobrir rebaixamento, desvinculação e provisionamento. |
| A proposta veda misturar RBAC novo e `custom_role` Enterprise, mas não define comportamento quando ambos existem no mesmo `AccountUser`. | Manter os campos/fontes independentes e decidir uma compatibilidade explícita no EE antes de integrar; não ler grants novos por meio de `custom_role_id` nem apagar silenciosamente a role EE existente. |
| Catálogo, escopos e ações não têm semântica operacional fechada para todos os sub-recursos. | Fixar representação de “sem linha de scope”, “scope vazio” e `all_in_account`; definir chaves para contatos mesclados/notas, associação de contatos a empresas, exportações, publicação, atualização de caixas de fluxo e transferência de Triagem. Só mostrar ações cobertas por policy, consulta, efeitos assíncronos e testes. |
| Relatórios usam GETs de mesma família para leitura e CSV; campanhas agendam/disparam por atributos de create/update; publicar artigo é mudança de status. | Não há fronteira de autorização separada por verbo HTTP nesses casos. Classificar a operação pelo efeito real do controller/serviço e testar que grant read não aciona o efeito. Não criar ações fantasmas ou depender só de formato da UI. |
| A trilha exige auditar tentativas administrativas negadas, mas o desenho não define quais falhas registrar, retenção nem como um ator sem autoridade registra evento sem converter a falha em sucesso ou revelar dados cross-tenant. | Especificar formato mínimo, autorização de leitura do log e casos registráveis antes de implementar a API de auditoria. Não guardar conteúdo nem IDs de tenant alheio em resposta ao solicitante. |
| A arquitetura separa disponibilidade comercial de autorização, mas módulos têm gates de edição/feature/canal e rotas Enterprise. | A decisão final deve continuar sendo “recurso disponível AND grant”; matriz e testes devem identificar Community/Enterprise e flags por endpoint. Role algum pode habilitar recurso indisponível. |

## Critério de saída da Etapa 0

- Base e divergência entre branches identificadas acima.
- Os sete módulos foram mapeados até rotas, proteções, consultas/efeitos relevantes, telas e specs existentes.
- A rota de archive de Portal e decisões de escopo/precedência estão registradas como lacunas.
- Nenhuma migration ou alteração de aplicação foi feita nesta etapa.

As decisões necessárias para construir o núcleo foram tomadas na Etapa 1; as integrações e lacunas de cobertura acima continuam pendentes antes de ativar qualquer módulo.

## Estado da Etapa 1 — núcleo administrativo

**Implementado no worktree `feat/rbac-core`, sobre `main@ab3e7ab96cff004207455a04b7bb7a7d8813594e`.** Esta seção descreve a alteração corrente; as linhas da matriz por módulo continuam sendo o inventário do comportamento anterior e o alvo para futuras ativações.

| Parte | Estado da Etapa 1 |
| --- | --- |
| Persistência | Tabelas de funções, grants e auditoria; nomes normalizados únicos por conta; role e grants vinculados à conta; FK composta impede referência cruzada de `AccountUser` para role de outra conta. IDs nativos permanecem como estão. |
| Ciclo do vínculo | Um agente recebe no máximo uma função. Atribuição marca `rbac_managed`; remoção preserva o marcador para que uma futura área enforced não volte silenciosamente ao legado. Administradores nativos e vínculos `custom_role_id` Enterprise não podem receber função RBAC. |
| Catálogo e autorizações | Sete módulos e suas chaves candidatas constam no catálogo de código como `planned`/não atribuíveis. O autorizador identifica estados legados, módulo ainda não migrado, RBAC enforced e administrador nativo; role inativa, grant ausente, escopo desconhecido, vínculo inválido e recurso de outra conta negam na área enforced. Nenhuma policy de negócio chama o autorizador nesta etapa. |
| API | Endpoints Rails account-scoped listam catálogo, gerenciam funções, aceitam apenas substituição vazia de grants, atribuem/removem função, expõem capacidades do vínculo corrente e consultam auditoria. Somente administradores nativos podem administrar. |
| Auditoria | Mudanças transacionais registram ator, ação, alvo, resultado, delta limitado e request ID. Tentativas humanas e técnicas negadas são registradas quando ator e conta podem ser identificados sem criar registro em conta não autorizada. |
| Último administrador | Guard compartilhado em `AccountUser` serializa alterações por lock da conta e protege demissão/remoção em Agentes, Platform API e Super Admin. Exclusão global de usuário com vínculo administrador é bloqueada. Recuperação Super Admin por inclusão de administrador é auditada. |
| Enterprise | `custom_role_id` permanece separado. Conflito é recusado sem limpar a role Enterprise. Fluxo SAML e regras atuais de role Enterprise continuam sob seus próprios mecanismos. |
| Experiência visual e SaaS | Nenhuma tela Vue, NestJS, billing, token universal ou gerenciamento cross-account foi adicionado. |

### Decisões da Etapa 1 para lacunas registradas

| Lacuna de Etapa 0 | Decisão tomada |
| --- | --- |
| Admin nativo junto com role RBAC | Proibido atribuir role RBAC a `AccountUser.role=administrator`. Promoção de agente só mantém a role nativa quando a role RBAC tiver sido removida; o último admin nunca é removido por um caminho operacional. |
| `custom_role_id` Enterprise junto com role RBAC | Conflito recusado por validação compartilhada; nenhum dado Enterprise é substituído. |
| Scope sem linha/nulo e chaves futuras | Um grant tem `permission_key` e `scope_type` na mesma linha, ambos obrigatórios. Só `all_in_account` está previsto onde o catálogo declara o tipo; todas as chaves seguem não atribuíveis até a cobertura de ponta a ponta. |
| Tentativa negada e informações cross-tenant | A auditoria grava ator identificável, ação/resultado, tipo do alvo e request ID, sem payload. IDs de outra conta não são retornados nem copiados para o evento. A leitura requer administrador nativo. |
| Gate de edição/feature | Não se altera disponibilidade: nenhum grant futuro supera feature flag, edição, canal, tenant ou gate de segurança. A ativação futura precisa compor o gate de produto com autorização. |

### Verificação associada

Os specs de RBAC cobrem persistência, catálogo, estados do autorizador, grants e scopes, CRUD/versionamento, isolamento de contas, auditoria, atribuição/revogação, principal técnico, conflito Enterprise, caminhos de alteração de administrador, rollback transacional e concorrência em PostgreSQL. A lista exata de comandos e resultados está no handoff da Etapa 1 e na execução local desta branch; nenhum módulo de negócio foi testado como protegido pelo RBAC porque nenhum foi integrado.
