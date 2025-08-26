# ServerSideApply — revisão e ação recomendada

Resumo:
- `ServerSideApply=true` altera propriedade de campos (field ownership) no servidor e pode criar conflitos com outros controllers (ex: Crossplane).
- Evitar habilitar globalmente; optar por opt-in em aplicações/CRDs que realmente precisam (ex: CRDs grandes com muitos campos dinâmicos).

Passos recomendados:
1. Fazer inventário das ApplicationSet/Application que usam `ServerSideApply=true`.
2. Para cada app, checar se há outros controllers que atualizam os mesmos recursos.
3. Remover `ServerSideApply=true` onde não for estritamente necessário.
4. Quando necessário, documentar a justificativa e monitorar pelo menos 24h após mudança.
5. Alternativa: usar `ApplyOutOfSyncOnly` e `RespectIgnoreDifferences` combinados conforme necessidade.

Exemplo de how-to:
- Para habilitar em um app específico (ApplicationSet), adicionar condicional baseada em uma annotation/values:
  - `syncOptions: ['ServerSideApply=true']` somente em charts/addons que exigem.
- Ferramenta rápida para localizar usos:
  - `grep -R "ServerSideApply=true" bootstrap/control-plane | sed -n '1,200p'`

Documentação:
- Argo CD syncOptions: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/
- Server-side apply (k8s): https://kubernetes.io/docs/reference/using-api/server-side-apply/
