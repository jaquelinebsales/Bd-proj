-- Listas completas do perfil. O resumo (meu_resumo) traz só os últimos envios e avaliações; no perfil, tocar em
-- "preços enviados" ou "avaliações" abre a lista inteira da própria conta, em páginas.
-- As avaliações não expõem usuario_id às consultas diretas (20261006000009), por isso as listas são funções.

create index if not exists avaliacoes_usuario_idx on public.avaliacoes (usuario_id, criado_em desc);

create or replace function public.meus_envios(p_limite integer default 50, p_offset integer default 0)
returns table (id bigint, posto_id bigint, posto text, produto_id smallint, preco numeric, status text, criado_em timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select i.id, i.posto_id, coalesce(p.nome_exibicao, p.razao_social), i.produto_id, i.preco, i.status::text, i.criado_em
  from public.envio_itens i
  join public.postos p on p.id = i.posto_id
  where i.usuario_id = auth.uid()
  order by i.criado_em desc, i.id desc
  limit least(greatest(p_limite, 1), 100) offset greatest(p_offset, 0)
$$;

create or replace function public.minhas_avaliacoes(p_limite integer default 50, p_offset integer default 0)
returns table (id bigint, posto_id bigint, posto text, nota smallint, comentario text, votos_uteis integer, criado_em timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id, a.posto_id, coalesce(p.nome_exibicao, p.razao_social), a.nota, a.comentario, a.votos_uteis, a.criado_em
  from public.avaliacoes a
  join public.postos p on p.id = a.posto_id
  where a.usuario_id = auth.uid()
  order by a.criado_em desc, a.id desc
  limit least(greatest(p_limite, 1), 100) offset greatest(p_offset, 0)
$$;

revoke execute on function public.meus_envios(integer, integer) from public, anon;
grant execute on function public.meus_envios(integer, integer) to authenticated;
revoke execute on function public.minhas_avaliacoes(integer, integer) from public, anon;
grant execute on function public.minhas_avaliacoes(integer, integer) to authenticated;
