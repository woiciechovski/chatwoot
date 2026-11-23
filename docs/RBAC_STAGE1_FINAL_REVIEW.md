# Revisão final — fechamento da Etapa 1 do RBAC

**Branch:** `feat/rbac-core`
**Escopo:** fechamento técnico da Etapa 1. Os sete módulos continuam `planned` e não atribuíveis; não foram iniciadas integração de módulos nem telas.

## Parecer

**Aprovar o fechamento técnico da Etapa 1**, sujeito aos limites operacionais descritos abaixo antes de qualquer ativação de módulos. A revisão cobre coordenação de locks, proteção do último administrador, exclusão global, auditoria, isolamento por conta, compatibilidade Community/Enterprise e integridade da migration.

## Alterações realizadas

- Centralizado o protocolo em [`membership_lock_service.rb`](../app/services/rbac/membership_lock_service.rb): `Account → User → AccountUser`, contas por ID crescente; `with_user_memberships` relê os vínculos depois dos locks e reinicia a tentativa inteira em um novo escopo transacional quando surge uma conta ainda não bloqueada. Escopos reentrantes podem reutilizar locks cobertos, mas não expandi-los fora da ordem.
- Revisados os callbacks de `AccountUser` e `User`, os builders e os caminhos de Agents API, Platform API, Super Admin e RBAC. O callback do modelo continua sendo a barreira para chamadas diretas de `destroy`; as operações suportadas passam pelo coordenador. Atualizações de nome e vínculo de agente agora são atômicas.
- Separadas as duas regras administrativas. `usable_administrators` conta vínculos nativos persistidos ligados a usuários existentes somente em contas ativas. O projeto não tem um estado `active` próprio em `User`: confirmação de email e disponibilidade do `AccountUser` não mudam a elegibilidade; usuários `SuperAdmin` com vínculo nativo contam, linhas órfãs não. Já a exclusão global é recusada enquanto existir qualquer vínculo nativo `administrator`, inclusive em conta suspensa. A remoção ou rebaixamento do vínculo deve ocorrer antes por operação autorizada no escopo da conta.
- Negativas são auditadas depois do rollback completo da operação protegida. Se existe transação externa e a conta já está confirmada no banco, o gravador usa uma conexão independente; falha de auditoria não converte a negativa em sucesso. Ator ausente não vira `System` implicitamente. Exclusões globais negadas geram um evento por vínculo administrativo, com alvo local à conta.
- Mantidos `rbac_managed`, isolamento por conta, `expected_version` estrito e o limite Community/Enterprise. Não houve alterações em `enterprise/`, módulos de negócio ou frontend.
- Os caminhos Enterprise existentes para `custom_role_id` e SAML foram revisados: gravações de `AccountUser` passam pelos callbacks compartilhados e pelo coordenador. O recurso `SuperAdmin::AccountUsersController` não expõe rota de `update`; os caminhos suportados são criação, consulta e remoção.
- O contrato e as limitações estão documentados em [`RBAC_CORE_API.md`](RBAC_CORE_API.md). A migration define a FK composta `(account_id, rbac_role_id) → (account_id, id)` para impedir referência de função de outra conta.

## Evidências de PostgreSQL

Os testes concorrentes usam conexões PostgreSQL independentes. O teste de nova associação após descoberta inicial observou três backend PIDs diferentes e a sequência de tabelas bloqueadas `accounts, users, accounts, users, account_users`: a tentativa incompleta foi desfeita antes de adquirir memberships, e a nova tentativa bloqueou as contas em ordem antes de `User` e `AccountUser`.

As agendas exercitadas incluem:

- rebaixamentos simultâneos de administradores, preservando um administrador utilizável;
- promoção versus exclusão global;
- remoções em várias contas versus exclusão global, preservando um administrador em cada conta ativa;
- criação de vínculo em nova conta por `AccountBuilder` enquanto a exclusão descobre os vínculos;
- duas edições concorrentes da mesma função com a mesma versão, em que uma vence e a outra recebe conflito de versão;
- reentrância de callbacks, sem expansão de escopo ou inversão da ordem dos locks.

A validação da migration usou banco PostgreSQL descartável, carregado do schema anterior ao RBAC. A migration foi aplicada, revertida e reaplicada. No primeiro e no segundo `up`, foram confirmadas as três tabelas RBAC, as colunas `rbac_role_id`/`rbac_managed`, os índices exclusivos por conta e a FK composta. Uma atribuição cruzada feita por atualização direta no banco foi rejeitada por `ActiveRecord::InvalidForeignKey`. No `down`, foram confirmadas a remoção das tabelas, colunas e FK. Nenhum rollback foi executado no banco de desenvolvimento compartilhado.

## Testes e lint

Suíte Community, em PostgreSQL isolado. O runner definiu `RAILS_ENV=test` e apontou para o cluster descartável usado nesta validação:

```sh
eval "$(rbenv init -)"
RAILS_ENV=test DISABLE_ENTERPRISE=true bundle exec rspec \
  spec/services/rbac spec/models/account_spec.rb spec/models/account_user_spec.rb \
  spec/models/account_user_concurrency_spec.rb spec/models/user_spec.rb \
  spec/models/rbac_role_spec.rb spec/models/rbac_role_permission_spec.rb \
  spec/models/rbac_audit_event_spec.rb spec/builders/account_builder_spec.rb \
  spec/builders/agent_builder_spec.rb spec/requests/api/v1/accounts/rbac_spec.rb \
  spec/controllers/api/v1/accounts/agents_controller_spec.rb \
  spec/controllers/platform/api/v1/account_users_controller_spec.rb \
  spec/controllers/platform/api/v1/users_controller_spec.rb \
  spec/controllers/super_admin/account_users_controller_spec.rb \
  spec/controllers/super_admin/users_controller_spec.rb
```

Resultado: **361 exemplos, 0 falhas, 16 pendências**. Quinze pendências são testes de MFA que exigem configuração ausente neste ambiente; uma é o caso de `custom_role` Enterprise, indisponível em Community.

Compatibilidade Enterprise carregada, no mesmo PostgreSQL isolado e sem mudanças na árvore Enterprise:

```sh
eval "$(rbenv init -)"
RAILS_ENV=test bundle exec rspec \
  spec/requests/api/v1/accounts/rbac_spec.rb spec/models/account_user_concurrency_spec.rb \
  spec/controllers/platform/api/v1/account_users_controller_spec.rb \
  spec/controllers/platform/api/v1/users_controller_spec.rb \
  spec/controllers/super_admin/account_users_controller_spec.rb \
  spec/controllers/super_admin/users_controller_spec.rb
```

Resultado: **126 exemplos, 0 falhas**; inclui o conflito entre atribuição RBAC e `custom_role_id` Enterprise.

O RuboCop inspecionou **52 arquivos Ruby alterados, sem offenses** (o `db/schema.rb` gerado foi excluído da inspeção). `git diff --check` não encontrou whitespace inválido. Há avisos de depreciação de Rails/Rack/Administrate no carregamento das suítes, sem falhas associadas.

## Riscos residuais e limitações

| Risco | Mitigação atual | Responsável e condição de acompanhamento |
| --- | --- | --- |
| A trilha de negativa pode ficar indisponível se o banco ou a conexão independente falhar; a operação continua negada e a classe da falha é registrada no log. Uma conta ainda não confirmada em transação externa não pode ser gravada por outra conexão por causa da FK e usa a conexão da transação. | Tentativa independente para contas confirmadas, captura segura da falha e teste de rollback externo. | Operação da implantação RBAC: acompanhar falhas do log e confirmar disponibilidade/limite do pool antes de habilitar qualquer módulo. O pool adicional é limitado a duas conexões por processo do gravador. |
| `bulk_create` verifica capacidade da conta e depois cada builder adquire seus locks canônicos. Lotes concorrentes podem criar parte dos agentes antes de uma tentativa posterior atingir o limite. | Cada vínculo é protegido e a capacidade é revalidada no builder; o comportamento de lote parcial já existe na integração por email. | Responsável pelo fluxo de onboarding: medir frequência de erros de capacidade em lote e revisar o contrato antes de uso concorrente em alta escala. |
| Os testes demonstram ordenação e serialização em fixtures pequenas, mas não são um benchmark de contenção ou dimensionamento de pool para contas grandes. | Locks são limitados aos vínculos do usuário e a auditoria independente tem pool limitado. | Plataforma/DBA: medir contenção e espera de pool em carga representativa antes de ativar políticas de módulos. |
| A validação de exclusão global depende dos callbacks Rails para caminhos de `destroy`; operações SQL de baixo nível que ignoram callbacks não são uma API suportada para excluir usuários. O único `update_all` RBAC encontrado é a limpeza de atribuições durante teardown da conta para liberar a FK antes da exclusão assíncrona dos vínculos. | Operações globais suportadas e `User#before_destroy` usam o coordenador; a limpeza de teardown é restrita à associação da conta. | Manutenção do core: novas rotas de exclusão global devem passar pelo serviço/callback e ser cobertas por teste concorrente. |

Não foram executados testes de frontend, benchmarks de carga ou integração dos sete módulos, pois essas atividades estão fora da Etapa 1 aprovada. A suíte Community mantém os 15 testes de MFA pendentes por falta de configuração; o caminho Enterprise relevante foi executado separadamente.
