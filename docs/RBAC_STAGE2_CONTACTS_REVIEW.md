# RBAC Stage 2.1 — revisão do módulo Contatos

## Estado

Ativação controlada concluída na branch `feat/rbac-core`: as seis permissões `contacts.*` estão `enforced` e atribuíveis no catálogo. A mudança afeta o código desta branch e o ambiente PostgreSQL descartável usado nos testes; não foram feitas migrações nem alterações de configuração ou implantação em produção.

Os outros seis domínios (`companies`, `reports`, `knowledge_base`, `campaigns`, `flows` e `triage`) permanecem `planned` e não atribuíveis. A ativação reutiliza `ContactPolicy` e `Rbac::Authorizer`. Não houve edição em `enterprise/`, integração dos demais módulos, tela administrativa de RBAC ou dependência do NestJS.

## 1. Arquivos alterados

As mudanças desta etapa abrangem:

- **Autorização e catálogo:** `app/policies/contact_policy.rb`, `app/services/contacts/authorization.rb`, `app/services/rbac/catalog.rb` e o endpoint existente de capabilities em `app/controllers/api/v1/accounts/rbac/`.
- **Endpoints de Contatos e operações relacionadas:** `app/controllers/api/v1/accounts/contacts_controller.rb`, controllers em `app/controllers/api/v1/accounts/contacts/`, `app/controllers/api/v1/accounts/contact_inboxes_controller.rb`, `app/controllers/api/v1/accounts/search_controller.rb`, `app/controllers/api/v1/accounts/bulk_actions_controller.rb`, `app/controllers/api/v1/accounts/actions/contact_merges_controller.rb`, controllers de notas de Empresas e associações de contatos, `app/controllers/api/v1/accounts/data_imports_controller.rb` e integrações Shopify/Stripe que consultam contatos.
- **Downloads e serialização:** `config/routes.rb`, `app/controllers/concerns/contacts/authenticated_blob_downloads.rb`, controllers de download de avatar/exportação, `app/helpers/api/v1/conversations_helper.rb`, templates Jbuilder de Contatos e anexos e `app/views/api/v1/conversations/partials/_conversation.json.jbuilder`.
- **Jobs, serviços e callbacks:** exportação de contatos, ações em lote, importação, atualização de avatares, associação de Empresas, broadcasts ActionCable e call sites de integrações usados para criar ou consultar contatos.
- **Dashboard:** `app/javascript/dashboard/api/contacts.js`, `usePolicy.js`, `useProtectedContactMedia.js` e componentes existentes de Contatos, anexos e ações em lote.
- **Ativação, capabilities e cache protegido no Vue:** `app/services/rbac/catalog.rb` altera somente as seis entradas `contacts.*`; `usePolicy.js` e `ContactMoreActions.vue` exigem simultaneamente `contacts.read` e `contacts.export`; `app/javascript/dashboard/store/modules/contactReadCache.js` centraliza a limpeza dos caches de Contatos após leituras negadas, e a tela de detalhe mostra a mensagem de autorização recebida sem iniciar leituras de sub-recursos quando o contato foi negado.
- **Cobertura:** specs de policy, requests, controllers, jobs, serviços e Vue, incluindo `spec/requests/api/v1/accounts/contacts_rbac_spec.rb` e o spec concorrente PostgreSQL `spec/requests/api/v1/accounts/contacts_rbac_concurrency_spec.rb`.

As mudanças pré-existentes da Etapa 1 e da integração 2.1 foram preservadas. Os testes de ativação agora consultam o catálogo real em vez de simular `contacts` como ativo por stubs.

## 2. Permissões implementadas

| Permissão | Operações autorizadas |
| --- | --- |
| `contacts.read` | **Enforced, atribuível.** Listar, consultar, buscar, filtrar, ler histórico, notas, etiquetas, avatares e anexos visíveis. |
| `contacts.create` | **Enforced, atribuível.** Criar contato; qualquer associação a Empresa ou Inbox continua sujeita à policy correspondente. |
| `contacts.update` | **Enforced, atribuível.** Editar contato, avatar, atributos personalizados, notas, etiquetas e vínculos de contato. Alterações em Empresas continuam exigindo `CompanyPolicy`. |
| `contacts.delete` | **Enforced, atribuível.** Excluir contato. |
| `contacts.import` | **Enforced, atribuível.** Importar contatos por CSV ou integração; integrações com outros tipos de dados não são liberadas por esta permissão. |
| `contacts.export` | **Enforced, atribuível.** Solicitar exportação e baixar o arquivo gerado junto com `contacts.read`. |

Uma permissão não substitui outra. A mesclagem exige simultaneamente `contacts.read`, `contacts.update` e `contacts.delete`. Respostas de criação/edição sem `contacts.read` não serializam os campos do contato.

Administradores nativos e agentes com `rbac_managed: false` continuam no comportamento legado. Agentes gerenciados dependem exclusivamente de grants explícitos nas permissões aplicáveis. Revogar a função ou grant não redefine `rbac_managed`.

### Matriz de perfis validada por API

| Perfil | Evidência observada após ativação |
| --- | --- |
| Administrador nativo | Listagem e criação de contato respondem com sucesso; mantém autorização administrativa legada. |
| Agente legado, não gerenciado | Listagem e criação respondem com sucesso, sem exigir grant. |
| Gerenciado sem função ou grants | Com `rbac_role` ausente e com função sem grants, `GET /contacts` é negado sem e-mail no corpo; criação também é negada sem mutação. |
| Somente `contacts.read` | Listagem permitida; criação, edição e exclusão negadas. |
| Somente `contacts.create` | Criação permitida; listagem, edição e exclusão negadas. A resposta não revela dados existentes. |
| Somente `contacts.update` | Edição permitida e corpo minimizado; listagem e exclusão negadas. |
| Somente `contacts.delete` | Exclusão permitida; listagem e edição negadas. |
| Somente `contacts.import` | Importação de contatos permitida; listagem negada; importação mista com conversas negada. |
| Somente `contacts.export` | Solicitação, processamento e download da exportação negados; capability de exportação falsa porque falta `contacts.read`. |
| Todas as seis permissões | API administrativa aceita e persiste os seis grants; listagem, criação, edição e exclusão são permitidas. Importação e exportação também têm casos de sucesso com seus respectivos grants isolados. |

Os cinco perfis sem `contacts.read` (create, update, delete, import e export) não obtêm leitura indireta. Para gerenciados, a exportação também não é concedida por `contacts.export` isoladamente: solicitações, worker, download e capability exigem read+export. Specs de capabilities e do menu Vue validam os casos parciais; a ação de mesclagem permanece oculta porque exige read+update+delete.

## 3. Matriz de endpoints protegidos

| Endpoint/operação | Permissão | Proteções adicionais |
| --- | --- | --- |
| `GET /contacts`, `/active`, `/search`, `POST /filter`, `GET /contacts/:id` | `contacts.read` | Consultas limitadas à conta atual. |
| `GET /contacts/:id/contactable_inboxes` | `contacts.read` | Inbox continua sujeita à policy própria. |
| `POST /contacts` | `contacts.create` | Empresa e Inbox exigem as respectivas policies; avatar assíncrono carrega identidade confiável. |
| `PATCH /contacts/:id` | `contacts.update` | Mudanças de Empresa exigem `CompanyPolicy`; resposta minimizada quando falta read. |
| `DELETE /contacts/:id` | `contacts.delete` | Contatos online preservam a validação existente que impede exclusão. |
| `DELETE /contacts/:id/avatar`, `POST /contacts/:id/destroy_custom_attributes` | `contacts.update` | Resposta minimizada quando falta read. |
| `POST /contacts/import` e criação/validação de `data_imports` | `contacts.import` | Job revalida membership/grant antes de executar e nos limites de lote; agentes gerenciados só recebem importações de contatos. |
| `GET /data_imports`, `GET /data_imports/:id`, iniciar, repetir, abandonar e baixar logs de importação | `contacts.import` para importações de Contatos gerenciadas | Agentes gerenciados veem apenas suas importações exclusivamente de contatos; administradores nativos mantêm o comportamento existente. |
| `POST /contacts/export`, worker de exportação, `GET /contacts/export/download` | `contacts.read` **e** `contacts.export` para agentes gerenciados | Solicitação, execução, limites de lote, publicação/anexo, envio e download consultam a mesma `ContactPolicy#export?`; o worker revalida antes da execução, a cada lote de até 100 contatos, antes de anexar o arquivo e antes de enviar o e-mail. Administradores nativos e usuários não gerenciados preservam a policy legada. |
| `GET /contacts/:id/notes` e `GET /notes/:note_id` | `contacts.read` | Escopo pelo contato da conta. |
| `POST`, `PATCH`, `DELETE /contacts/:id/notes/:note_id` | `contacts.update` | Escopo pelo contato da conta. |
| `GET /contacts/:id/labels` | `contacts.read` | Escopo pelo contato da conta. |
| `POST /contacts/:id/labels` | `contacts.update` | Mutação não depende de read. |
| `POST /contacts/:id/contact_inboxes` | `contacts.update` | Inbox exige a policy própria. |
| `GET /contacts/:id/conversations` | `contacts.read` | `Conversations::PermissionFilterService` preserva a visibilidade das conversas; IDs de outra conta não são resolvidos. |
| `GET /contacts/:id/attachments`, `GET /contacts/:id/attachments/:attachment_id/download` | `contacts.read` | Downloads repetem o filtro de visibilidade das conversas e escopo da conta. |
| `GET /contacts/:id/avatar/download` | `contacts.read` | Avatar servido por rota autenticada. |
| Busca global `GET /search` e busca direta `GET /search/contacts` | `contacts.read` | Sem read, o endpoint global omite resultados de Contatos; a busca direta é negada. Outras áreas mantêm suas regras. |
| `POST /actions/contact_merge` | `contacts.read` + `contacts.update` + `contacts.delete` | Ambas as fichas e todas as conversas afetadas precisam ser visíveis. |
| `POST /bulk_actions` para apagar contatos | `contacts.delete` | Job revalida no limite de cada lote de até 100. |
| `POST /bulk_actions` para adicionar/remover etiquetas | `contacts.update` | Job revalida no limite de cada lote de até 100. |
| `GET /companies/:company_id/contacts` e `/search` | `companies.read` e `contacts.read` | Cada domínio exige sua própria autorização. |
| `POST` ou `DELETE /companies/:company_id/contacts` | `companies.update` e `contacts.update` | Não concede nem infere administração de Empresas a partir de `contacts.update`. |
| `GET /companies/:company_id/notes` | `companies.read` e `contacts.read` | A policy de Empresas não substitui a leitura de Contatos para notas ligadas a contato. |
| Shopify e Stripe: endpoints que consultam/criam contatos | `contacts.read` para consulta; policy do provedor e origem confiável para criação de sistema | A autorização é verificada antes de consultar os provedores ou serializar o contato. |
| `POST /contact_inboxes/filter` | `contacts.read` | Resolve primeiro o Inbox/source e depois autoriza o contato dentro da conta. |
| Eventos ActionCable diretos de Contatos | `contacts.read` | Broadcast direcionado a usuários autorizados; o job revalida no envio e interrompe entregas após revogação. Eventos de Conversas continuam seguindo `ConversationPolicy`. |

Quando `contacts.read` está ausente, respostas de mutação e recursos auxiliares que poderiam serializar o contato retornam corpo mínimo (por exemplo, apenas o ID ou `204`) depois da mutação autorizada. Isso evita transformar `create`, `update`, `delete`, `import` ou `export` em leitura indireta.

## 4. Operações auxiliares e limites de autorização

- **Importação CSV e integrações:** `contacts.import`. Usuários gerenciados podem importar somente contatos. Jobs verificam o usuário iniciador, membership, grant e tipo da importação. A revogação interrompe lotes futuros; o lote que já iniciou pode terminar.
- **Exportação:** gerenciados precisam de `contacts.read` e `contacts.export` na solicitação, no worker e no download; a UI requer ambas as capabilities. O arquivo não é publicado nem notificado se a autorização falhar em uma verificação de lote ou antes da publicação. O link do e-mail é uma rota autenticada, não uma URL bearer do Active Storage.
- **Avatar por URL/Gravatar:** `contacts.create` ou `contacts.update` para ações iniciadas por usuário. Origens internas passam por allowlist e identidade/principal de contato confiáveis. Ausência de membership não é tratada como autorização de sistema.
- **Notas, etiquetas, atributos personalizados, avatar e vínculos de Inbox:** leitura exige `contacts.read`; mutações exigem `contacts.update`, exceto exclusão do contato, que exige `contacts.delete`.
- **Histórico e anexos de conversas:** exigem `contacts.read` e preservam o filtro de conversas do usuário. URLs de anexos remotos sem blob interno são removidas dos payloads agregados de Contatos.
- **Empresas:** alterações explícitas, resolução de nomes antigos e associação automática por e-mail passam por `CompanyPolicy`. A permissão de Contatos não permite criar ou administrar Empresas por efeito colateral.
- **Frontend:** capabilities servem apenas para ocultar ações. A autorização no Rails continua sendo a barreira efetiva. A cache de capabilities dura até 15 segundos; operações HTTP continuam revalidando a policy no servidor. Em 401/403 de uma leitura de Contatos, a store limpa contatos, notas, históricos e vizinhos de conversa em cache; erros de rede não autenticacionais preservam esses caches. A tela de detalhe mostra a mensagem da API e não solicita inbox, notas ou histórico quando a leitura principal é negada.

As operações cobertas usam permissões existentes ou as duas novas chaves aprovadas (`contacts.import` e `contacts.export`); não foi necessária outra permissão auxiliar.

## 5. Testes executados

| Verificação | Resultado |
| --- | --- |
| Suíte PostgreSQL principal após ativar o catálogo | **403 exemplos, 0 falhas** em catálogo, Authorizer, grants, ContactPolicy, endpoints, downloads, import/export, jobs, ações em lote, busca, integrações e serviços afetados. |
| Reexecução PostgreSQL focada após os últimos ajustes Ruby | **254 exemplos, 0 falhas, 11 pendentes**. Os pendentes são cenários MFA ignorados porque MFA não está configurado no ambiente de teste. Inclui requests RBAC/Contatos, contato-inbox, associações/notas de Empresas, Shopify/Stripe, ActionCable, modelos e serviços de autorização. Há sobreposição intencional com a suíte principal. |
| Revisão final: policy, endpoints, capabilities e worker de exportação PostgreSQL | **86 exemplos, 0 falhas**. Reexecutado após exigir read+export e antes de encerrar esta revisão; inclui perfis parciais, request/download, capability e revalidação do job. |
| Spec concorrente PostgreSQL `contacts_rbac_concurrency_spec.rb` | **2 exemplos, 0 falhas**, executados isoladamente e dentro da suíte; usa conexões PostgreSQL independentes para verificar isolamento de grants por conta, negação cruzada e revalidação de revogação pelo worker. |
| Requests de Contatos com catálogo real | Incluídos nas execuções PostgreSQL: os dez perfis da matriz, usuário vinculado a duas contas, mesmo token pessoal após revogação, import/export e downloads autenticados. |
| Specs Vue de API, capabilities parciais, mídia protegida, navegação, store e tela de detalhe | A execução Vue ampla teve **104 testes, 0 falhas** em 10 arquivos. A revisão de exportação/cache executou **76 testes, 0 falhas** em 7 arquivos; cobre grants parciais, requisito read+export, limpeza de cache após 401/403 e preservação de caches para erros não autenticacionais. |
| RuboCop nos arquivos Ruby alterados | A execução ampla anterior inspecionou **111 arquivos, nenhum offense** (`db/schema.rb` excluído por ser gerado). Nesta revisão final, **4 arquivos Ruby inspecionados, nenhum offense**. |
| ESLint nos arquivos JS/Vue alterados | Execução ampla anterior: **0 erros**, com 8 avisos de chaves i18n dinâmicas e separadores textuais. Nesta revisão final, os arquivos JS/Vue tocados foram aprovados com **0 erros e 0 avisos**. |
| `git diff --check` | Sem erros de whitespace no diff verificado após a atualização deste relatório. |

Os testes Rails foram executados com o PostgreSQL descartável desta tarefa em `127.0.0.1:55440`, sem usar o serviço local em `5432`. Não foi executado `db:migrate` nem foi criada migration nesta ativação; nenhuma configuração de produção foi lida ou alterada. A suíte emite avisos existentes de enum Rails e status Rack deprecados.

O Vitest também reporta o `caniuse-lite` desatualizado e a ausência do source map distribuído junto de `@chatwoot/prosemirror-schema`; as execuções Vue continuam aprovadas. O ESLint registra somente os oito avisos listados acima.

## 6. Compatibilidade com usuários legados

- Administradores nativos mantêm acesso administrativo e continuam autorizados para importar/exportar conforme as policies existentes.
- Agentes sem gerenciamento RBAC continuam usando as permissões legadas, inclusive operações que já eram permitidas a agentes comuns.
- Agentes gerenciados usam exclusivamente os grants explícitos de Contatos, agora que `contacts` está `enforced`.
- `rbac_managed` continua verdadeiro após revogação de função/grant.
- Os seis outros domínios permanecem `planned`; suas regras não foram migradas.
- O código alterado está na Community; nenhum arquivo `enterprise/` foi modificado. O catálogo e as APIs RBAC permanecem independentes do NestJS.

## 7. Evidências de isolamento

- As queries de Contatos partem de `Current.account.contacts`; IDs estrangeiros retornam not found sem expor dados.
- O spec com usuário vinculado a duas contas comprova listas separadas por conta e rejeita o ID do contato da outra conta.
- O spec concorrente executa avaliações de grants em conexões PostgreSQL distintas para memberships diferentes do mesmo usuário e confirma que grant de update não vira read; também confirma a rechecagem após revogação.
- Busca, histórico, notas, anexos, exportação, importação e mutações em lote têm casos de autorização/escopo na suíte consolidada.
- O mesmo token pessoal foi reutilizado depois de remover o grant; a segunda request foi negada.
- Downloads nas rotas autenticadas do módulo Contatos revalidam a permissão antes de enviar o blob. Os payloads de avatar/anexo/exportação desse módulo apontam para rotas autenticadas; os serializadores comuns de anexos de Conversas mantêm os links legados descritos na seção 9.
- Eventos diretos de Contatos usam canais por usuário e a autorização é revalidada pelo job de broadcast no momento do envio, inclusive após revogação. Isso não altera a autorização independente de eventos de Conversas.

## 8. Riscos residuais e limitações

| Risco/limitação | Efeito e mitigação |
| --- | --- |
| URLs Active Storage permanentes antigas e links de anexos de Conversas | Não podem ser revogados automaticamente; links bearer podem continuar acessíveis conforme o storage e sua expiração. Novos downloads via rotas do módulo Contatos usam autenticação, mas mensagens comuns de Conversas ainda emitem links legados. |
| Conteúdo já baixado ou URL de objeto local após revogação | Não é possível retirar bytes já recebidos pelo navegador. O dashboard revoga object URLs ao desmontar componentes de mídia; novos downloads por rotas protegidas passam novamente pela autorização Rails. |
| Revogação durante uma requisição HTTP ou lote já iniciado | Uma requisição que já passou pela autorização e o lote de até 100 registros em execução podem concluir. A verificação interrompe trabalho nos limites seguintes; efeitos já confirmados não são revertidos. |
| Cache de capabilities no navegador | A visibilidade de botões pode levar até 15 segundos para refletir uma revogação. O backend revalida cada operação e não aceita essa cache como autorização. |
| Dados já carregados no dashboard | Não há invalidação push das telas quando uma função é revogada. A store é limpa quando a próxima leitura recebe negação, e novas operações são negadas pelo Rails; dados já exibidos podem permanecer na tela até essa nova leitura ou desmontagem da tela. |
| Identidade de contato embutida em respostas/eventos de Conversas autorizados | Conversas ainda podem incluir campos completos de identidade CRM quando o usuário tem acesso à conversa pelas regras legadas de inbox/conversa, mesmo sem `contacts.read`. Nenhuma serialização foi alterada nesta revisão. Produto/segurança deve aceitar formalmente a fronteira antes de produção; a proposta para separar identidade operacional do cadastro CRM está na seção 9. |
| Anexos remotos sem blob interno | `data_url` e `thumb_url` externos são omitidos nos payloads agregados de Contatos; esses arquivos podem não aparecer nessa visualização. A conversa segue sujeita à policy própria. |
| Operações de Empresas acionadas por Contatos | Enquanto `companies` está `planned`, `CompanyPolicy` Community continua legada; `contacts.update` pode acionar associação automática/criação de Empresa por e-mail se a feature de Empresas estiver habilitada. Há preautorização por `CompanyPolicy` em requests de criação/edição, mas ela ainda não expressa grants RBAC de Companies. A seção 9 detalha os caminhos e exige revisão própria antes de ativar esse domínio. |
| Concorrência | A prova concorrente cobre isolamento de grants entre contas com conexões PostgreSQL independentes, mas não é um teste de carga nem mede throughput em escala de produção. |

## 9. Revisão final de segurança

### 9.1 Identidade de Contatos embutida em Conversas

As serializações de Conversas e Mensagens não foram modificadas. Para um agente sem `contacts.read`, mas autorizado a uma conversa pelas regras de acesso próprias daquela conversa/inbox, os caminhos observados permanecem:

| Caminho | Campos de identidade de Contato que podem permanecer visíveis |
| --- | --- |
| Listagem, detalhe e eventos REST de Conversa | O `meta.sender` usa o partial de Contato com `additional_attributes`, `availability_status`, `email`, `id`, `name`, `phone_number`, `blocked`, `identifier`, `company_id` quando a feature Empresas está habilitada, `thumbnail`, `custom_attributes`, `last_activity_at`, `created_at` e, em endpoints de Contato, vínculos de Inbox. O campo `thumbnail` aponta para rota autenticada que exige `contacts.read`; a URL pode aparecer, mas o download é negado sem a permissão. |
| Busca global | A seção direta `contacts` é omitida sem `contacts.read`. Ainda assim, a busca de Conversas procura por nome, e-mail, telefone e identifier e seus resultados incluem contato com `email`, `id`, `name`, `phone_number`, `identifier`, `additional_attributes` e `last_activity_at`. Resultados de Mensagens incluem os dados do sender Contato. |
| Mensagens REST e histórico da Conversa | `Message#push_event_data` e o partial de Mensagem incluem `sender.push_event_data`; para Contato isso inclui `additional_attributes`, `custom_attributes`, e-mail, id, identifier, nome, telefone, thumbnail, blocked, contact_type e type, além de `company_id` quando Empresas está habilitada. Anexos de mensagens da Conversa mantêm o `data_url`/`thumb_url` produzido pelo serializador legado. O endpoint específico `contacts/:id/conversations` exige `contacts.read` e reescreve os links de anexos para rotas autenticadas; o histórico acessado pela própria Conversa segue a autorização de Conversas e mantém o sender/serializador de anexos legado. |
| WebSocket | Eventos diretos `CONTACT_*` são filtrados por `contacts.read` no job de broadcast. Eventos de Conversa e Mensagem incluem `Conversation EventDataPresenter#push_meta` e sender de mensagem com `Contact#push_event_data`; sua entrega segue as regras atuais de visibilidade da Conversa/inbox e não verifica `contacts.read`. |
| Notificações | O ator principal é a Conversa e serializa o payload de Conversa com `meta.sender`; o corpo pode conter nome do remetente e trecho da mensagem. Notificações seguem a visibilidade de notificação/conversa, sem uma checagem adicional de `contacts.read`. Modelos de e-mail de notificações também usam `conversation.contact_name` em alguns tipos. O payload FCM reduzido expõe referências da conversa. |

**Proposta para uma decisão futura:** definir uma projeção de identidade operacional mínima para atendimento sob acesso à Conversa (por exemplo, nome de exibição e identificador de canal/source, com avatar sujeito a decisão de produto). Manter o cadastro CRM completo — e-mail, telefone, identifier de CRM, campos adicionais/customizados, empresa, notas, etiquetas, mídia e busca direta — sob `contacts.read`. Um presenter comum deve produzir essa projeção para REST, histórico, eventos, busca e notificações, com allowlist de campos aprovada pelo produto. O conteúdo das mensagens pode conter dados pessoais próprios e continuaria sujeito à policy da Conversa. Essa proposta não foi ativada nesta entrega.

### 9.2 Operações que continuam usando `CompanyPolicy` legada

`companies` continua `planned` e sem grants atribuíveis. Em Community, `CompanyPolicy#index?`, `search?`, `show?`, `create?` e `update?` retornam `true`; `destroy?` permanece restrito a administrador nativo. Os caminhos relacionados a Contatos são:

- Criar/editar Contato com `company_id`, remover uma associação, ou trocar Empresa: o controller de Contatos exige `CompanyPolicy#update?` para a Empresa anterior/nova, além de `contacts.create` ou `contacts.update` para a operação de Contato.
- Resolver `company_name` legado: o controller pré-autoriza `CompanyPolicy#update?` na Empresa existente ou `CompanyPolicy#create?` antes de criar/resolver uma nova.
- Associar por domínio de e-mail comercial: o controller também pré-autoriza update/create antes da escrita de Contato. O callback `ContactCompanyAssociation` chama `Contacts::CompanyAssociationService` após commit; o service cria/associa a Empresa e não consulta policy por conta própria. Escritores não HTTP de Contato que acionem esse callback continuam no comportamento legado.
- Endpoints de associação em `/companies/:id/contacts`: listagem/busca exigem `CompanyPolicy#show?` e `ContactPolicy#index?`; inclusão/remoção exige `CompanyPolicy#update?` e `ContactPolicy#update?`.
- Notas de Empresas filtradas por contatos exigem `CompanyPolicy#show?` e `ContactPolicy#index?`.

Assim, `contacts.update` sozinho não bypassa um `CompanyPolicy` customizado/restritivo, mas como o domínio Companies está `planned`, a policy OSS atual não confere grants RBAC de Companies. A criação/associação automática por e-mail permanece uma consequência do comportamento legado ao editar um Contato. Isso é limitação conhecida para a integração futura de Empresas, não ativação de `companies` nesta revisão.

### 9.3 Revogação, caches e downloads

- A capability Vue é armazenada por conta/usuário por até 15 segundos. Uma revogação pode deixar ações visíveis nesse intervalo; os endpoints Rails reavaliam autorização imediatamente. Não há sincronização push de capabilities.
- Após 401/403 em uma leitura de Contatos, as mutações Vuex removem as listas/fichas de Contato e limpam notas, histórico de Contatos e vizinhos em cache. Uma negativa de leitura na página de detalhe também faz a ficha desaparecer da store, desmontando os subcomponentes do cadastro. A limpeza é disparada pela resposta negada; uma página aberta sem novas requests pode continuar mostrando os dados que já havia carregado.
- O componente principal recebe snapshot de `selectedContact` em estado local enquanto a tela está montada. Sem nova leitura negada, navegação ou desmontagem, esse snapshot e dados já renderizados permanecem visíveis após revogação. Nenhum mecanismo de sincronização em tempo real foi adicionado. Negar uma escrita, por si só, não limpa caches se o usuário ainda tem leitura permitida.
- Downloads de exportação, avatar e anexos nas rotas do módulo Contatos usam rotas Rails autenticadas, com autorização revalidada em cada nova request e `Cache-Control: private, no-store`. Revogação impede novos downloads por essas rotas. Um stream já iniciado e bytes já entregues ao navegador não podem ser recolhidos.
- URLs Active Storage permanentes emitidas antes desta mudança podem continuar funcionando como URLs bearer conforme o storage e expiração configurados; não há revogação retroativa. Além disso, os serializadores comuns de mensagens de Conversa continuam emitindo os links de anexo legados, não alterados nesta revisão. Somente o endpoint específico de histórico de Contatos reescreve anexos para rotas autenticadas. Object URLs e arquivos já baixados também não podem ser revogados no cliente depois que os bytes foram recebidos.

## 10. Recomendação

**Recomendação: encerrar tecnicamente a Etapa 2.1 e liberar para homologação controlada, condicionado ao registro do risco de identidade de Contatos em Conversas.** A integração de permissões de Contatos e a revisão de exportação/caches estão cobertas por testes; a serialização de Conversas mantém a identidade CRM existente para agentes autorizados à Conversa. Antes de promoção a produção, produto/segurança deve aceitar formalmente essa exposição ou aprovar uma tarefa separada para definir e aplicar a projeção de identidade operacional. Companies permanece `planned`; não iniciar o próximo módulo automaticamente. Esta recomendação não autoriza implantação em produção.
