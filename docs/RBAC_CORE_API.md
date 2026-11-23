# API do núcleo RBAC

**Estado:** Etapa 1. A API e a persistência são nativas do Rails. Nenhum dos sete módulos de negócio está protegido pelo novo RBAC.

## Autenticação e isolamento

Todos os endpoints usam a autenticação e o vínculo de conta existentes em `/api/v1/accounts/:account_id`. Operações administrativas exigem um `AccountUser` nativo com `role=administrator` na conta da URL. Um `User` sem vínculo válido, agente, `AgentBot` e `PlatformApp` não recebem poderes administrativos por token ou por grants.

Os IDs de funções e vínculos são buscados pela conta da requisição. Um ID pertencente a outra conta retorna `404` sem devolver o ID ou dados do registro alheio. `GET me/capabilities` é limitado ao `AccountUser` autenticado.

## Catálogo

`GET /api/v1/accounts/:account_id/rbac/permissions` retorna as chaves versionadas em `Rbac::Catalog`, com `module`, `action`, `description`, `status`, `assignable` e `scope_types`. Na Etapa 1, todas as ações de Contatos, Empresas, Relatórios, Base de Conhecimento, Campanhas, Fluxos e Triagem têm `status=planned` e `assignable=false`. A lista existe para documentar a cobertura futura; não representa proteção já aplicada.

O único tipo de escopo preparado para as ações onde ele é seguro é `all_in_account`. Nenhum grant é atribuível hoje. A substituição de grants aceita somente `[]`; qualquer chave ou escopo enviado agora retorna `422`.

## Funções

Base: `/api/v1/accounts/:account_id/rbac/roles`

| Método | Caminho | Resultado |
| --- | --- | --- |
| `GET` | `/roles` | Lista as funções da conta |
| `POST` | `/roles` | Cria uma função |
| `GET` | `/roles/:id` | Consulta uma função |
| `PATCH` | `/roles/:id` | Atualiza nome, descrição ou estado |
| `DELETE` | `/roles/:id` | Exclui uma função sem vínculos |
| `PUT` | `/roles/:id/grants` | Substitui os grants |

Criar:

```json
{
  "role": {
    "name": "Suporte",
    "description": "Equipe de atendimento"
  }
}
```

A resposta inclui `id`, `name`, `description`, `active`, `lock_version` e `grants`. Nome é normalizado para comparação sem diferenciar maiúsculas, espaços externos são removidos e nomes precisam ser únicos por conta.

Atualizar e excluir exigem a versão lida anteriormente:

```json
{
  "expected_version": 0,
  "role": {
    "name": "Suporte N1",
    "active": true
  }
}
```

Substituição de grants na Etapa 1:

```json
{
  "expected_version": 0,
  "grants": []
}
```

Uma escrita com versão antiga retorna `409` (`stale_version`). Campos inválidos, grants planejados ou escopos não suportados retornam `422`. Uma função atribuída não pode ser excluída; primeiro remova as atribuições.

`expected_version` aceita somente um inteiro JSON ou uma string decimal ASCII de dígitos (`0` a `2147483647`). Floats, booleanos, `null`, campo ausente, sinais, espaços, texto não numérico, valores negativos ou acima do limite retornam `422` (`invalid_version`). Uma versão válida, mas desatualizada, retorna `409`.

## Atribuições

`PUT /api/v1/accounts/:account_id/rbac/account_users/:account_user_id/role`

```json
{ "role_id": 42 }
```

`DELETE /api/v1/accounts/:account_id/rbac/account_users/:account_user_id/role` remove a função e mantém `rbac_managed=true`. Isso distingue uma remoção explícita de um vínculo legado. Como todos os módulos continuam planejados, ambos os casos mantêm o comportamento atual; em um domínio que venha a ser ativado, `rbac_managed=true` sem função significa negar.

Somente agentes da mesma conta podem receber função. Administradores nativos, vínculos com `custom_role_id` Enterprise, funções inativas, autoatribuição e IDs de outra conta são recusados. A atribuição atualiza o vínculo `AccountUser`, não o `User` global.

Um administrador utilizável é um vínculo nativo `administrator` cuja conta está ativa e cujo `User` ainda existe. Confirmação de e-mail e disponibilidade online/offline/busy não alteram a elegibilidade do vínculo. Uma conta suspensa não tem administradores utilizáveis para as validações de última administração; porém, qualquer vínculo `administrator` ainda existente nela bloqueia a exclusão global do usuário.

A exclusão global de `User` pela Platform API ou pelo Super Admin só pode ocorrer depois que todas as associações administrativas forem removidas por operações autorizadas no escopo de cada conta. O callback do modelo também recusa exclusão direta ou assíncrona enquanto algum vínculo nativo de administrador continuar presente, inclusive em contas suspensas.

O recurso `SuperAdmin::AccountUsersController` não possui rota `update`: as operações suportadas são criação, consulta e remoção. Não há caminho de edição direta de `role` nessa tela/recurso; a recuperação de administrador ocorre pela criação explícita de outro vínculo.

## Capacidades e auditoria

`GET /api/v1/accounts/:account_id/rbac/me/capabilities` retorna o vínculo atual, sua função (se existir), seus grants e o estado de migração de cada módulo. Estados de autorização centrais:

- `legacy`: agente sem função RBAC nem remoção explícita.
- `legacy_for_unmigrated_domain`: módulo ainda planejado; usa o comportamento anterior mesmo se houver função RBAC.
- `enforced_rbac`: módulo marcado como aplicado e vínculo sob RBAC.
- `native_administrator`: autoridade administrativa nativa da conta.

Nenhuma permissão do catálogo está em `enforced_rbac` nesta etapa. As policies de negócio continuam decidindo acesso aos sete módulos.

`GET /api/v1/accounts/:account_id/rbac/audit_events?limit=50&before_id=123` consulta a trilha somente para administradores nativos. A página é limitada a 100 eventos. Respostas incluem ator (`type` e `id`), ação, alvo (`type` e `id` local à conta), resultado, delta sanitizado, `request_id` e data. Eventos de negativa usam `details={}` e não gravam payload bruto, conteúdo de conversa, tokens ou IDs alheios. A exclusão global com vários vínculos administrativos gera um evento por vínculo, associado à conta e ao `AccountUser` locais.

Eventos incluem criação/edição/exclusão de funções, substituição de grants, atribuições/remoções, tentativas de administração negadas e recuperação de administrador feita por Super Admin. Eventos de sucesso para mutações são gravados na mesma transação da alteração; falha de auditoria cancela a mutação. Eventos de negativa são gravados somente depois do rollback da operação protegida. Se já houver uma transação externa, o gravador usa uma conexão de escrita independente quando a conta estiver confirmada no banco; contas ainda não confirmadas permanecem na transação que as criou. Falha do gravador não transforma a negativa em sucesso: o request permanece negado e a falha é registrada no log da aplicação, mas o evento pode não estar disponível durante a falha. O ator ausente nunca recebe `actor_type=System` por inferência; operações de sistema só podem ser marcadas explicitamente. Remover ou rebaixar o último administrador por Agentes, Platform API ou Super Admin é bloqueado e registrado. O Super Admin recupera uma conta adicionando outro administrador; essa concessão é auditada.

## Códigos HTTP

| Status | Significado |
| --- | --- |
| `200` | Consulta ou atualização concluída |
| `201` | Função criada |
| `204` | Função excluída |
| `401` | Sem autenticação ou sem autoridade administrativa |
| `404` | Recurso não existe na conta solicitada |
| `409` | `expected_version` desatualizado |
| `422` | Payload, escopo, atribuição ou transição inválida |

## Migração e rollback

A migration `20261122141506_create_rbac_core` adiciona tabelas, índices, `account_users.rbac_role_id`, `account_users.rbac_managed` e uma FK composta que impede uma atribuição entre contas. O schema atual usa IDs nativos do Chatwoot; roles e grants são pertencentes à conta.

Para reverter em ambiente de desenvolvimento:

```sh
eval "$(rbenv init -)" && bundle exec rails db:rollback STEP=1
```

O rollback remove as tabelas RBAC e as colunas associadas em `account_users`; portanto, também apaga funções, grants, auditoria e atribuições RBAC existentes. Não há backfill de vínculos legados.

## Próxima etapa

Ativar um módulo somente após cobrir policies, escopos de consulta, filtros, exportações, efeitos, eventos, jobs, integrações e caminhos Community/Enterprise relevantes. Ordem inicial sugerida:

1. Contatos
2. Empresas
3. Relatórios
4. Base de Conhecimento
5. Campanhas
6. Fluxos
7. Triagem

Triagem permanece por último devido a visibilidade de conversa, ActionCable, notificações, busca, contagens, anexos e transferências com origem/destino distintos.
