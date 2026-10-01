-- gasprice · regras de acesso (Row Level Security)
-- Consulta é pública; toda alteração exige login. Envio de preço só pela
-- Edge Function "enviar-precos" (service role), nunca direto pelo app.

alter table public.produtos           enable row level security;
alter table public.postos             enable row level security;
alter table public.posto_produtos     enable row level security;
alter table public.sincronizacoes_anp enable row level security;
alter table public.precos_anp         enable row level security;
alter table public.perfis             enable row level security;
alter table public.envios             enable row level security;
alter table public.envio_itens        enable row level security;
alter table public.precos_comunidade  enable row level security;
alter table public.precos_estimados   enable row level security;
alter table public.precos_atuais      enable row level security;
alter table public.avaliacoes         enable row level security;
alter table public.avaliacao_votos    enable row level security;
alter table public.favoritos          enable row level security;
alter table public.pontos_movimentos  enable row level security;
alter table public.notificacoes       enable row level security;
alter table public.previsoes          enable row level security;

-- Leitura pública
create policy "leitura publica" on public.produtos          for select to anon, authenticated using (true);
create policy "leitura publica" on public.postos            for select to anon, authenticated using (ativo);
create policy "leitura publica" on public.posto_produtos    for select to anon, authenticated using (true);
create policy "leitura publica" on public.precos_anp        for select to anon, authenticated using (true);
create policy "leitura publica" on public.precos_comunidade for select to anon, authenticated using (true);
create policy "leitura publica" on public.precos_estimados  for select to anon, authenticated using (true);
create policy "leitura publica" on public.precos_atuais     for select to anon, authenticated using (true);
create policy "leitura publica" on public.avaliacoes        for select to anon, authenticated using (true);
create policy "leitura publica" on public.previsoes         for select to anon, authenticated using (true);

-- Perfil: cada um lê e altera só o próprio, e só algumas colunas
create policy "le o proprio perfil" on public.perfis
  for select to authenticated using (id = (select auth.uid()));
create policy "altera o proprio perfil" on public.perfis
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
revoke update on public.perfis from authenticated, anon;
grant update (nome, avatar_url, notificacoes_ativas) on public.perfis to authenticated;

-- Envios: o usuário vê os próprios; ninguém insere direto
create policy "le os proprios envios" on public.envios
  for select to authenticated using (usuario_id = (select auth.uid()));
create policy "le os proprios itens" on public.envio_itens
  for select to authenticated using (usuario_id = (select auth.uid()));

-- Avaliações: só usuário logado, não banido, e só as próprias
create or replace function public.usuario_pode_contribuir()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.perfis p
    where p.id = auth.uid()
      and not p.banido
      and (p.bloqueado_ate is null or p.bloqueado_ate < now())
  )
$$;

create policy "cria a propria avaliacao" on public.avaliacoes
  for insert to authenticated
  with check (usuario_id = (select auth.uid()) and public.usuario_pode_contribuir());
create policy "altera a propria avaliacao" on public.avaliacoes
  for update to authenticated
  using (usuario_id = (select auth.uid()))
  with check (usuario_id = (select auth.uid()) and public.usuario_pode_contribuir());
create policy "apaga a propria avaliacao" on public.avaliacoes
  for delete to authenticated using (usuario_id = (select auth.uid()));
revoke update on public.avaliacoes from authenticated, anon;
grant update (nota, comentario, atualizado_em) on public.avaliacoes to authenticated;

create policy "le votos" on public.avaliacao_votos for select to anon, authenticated using (true);
create policy "vota" on public.avaliacao_votos
  for insert to authenticated with check (usuario_id = (select auth.uid()));
create policy "retira voto" on public.avaliacao_votos
  for delete to authenticated using (usuario_id = (select auth.uid()));

-- Favoritos, pontos e notificações: só do próprio usuário
create policy "favoritos do usuario" on public.favoritos
  for all to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
create policy "extrato do usuario" on public.pontos_movimentos
  for select to authenticated using (usuario_id = (select auth.uid()));
create policy "notificacoes do usuario" on public.notificacoes
  for select to authenticated using (usuario_id = (select auth.uid()));
create policy "marca notificacao como lida" on public.notificacoes
  for update to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
revoke update on public.notificacoes from authenticated, anon;
grant update (lida) on public.notificacoes to authenticated;

-- Storage: avatares (foto de perfil opcional). Fotos de painel NÃO existem no Storage.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatares', 'avatares', true, 204800, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('anp-historico', 'anp-historico', false)
on conflict (id) do nothing;

create policy "avatar publico" on storage.objects
  for select to anon, authenticated using (bucket_id = 'avatares');
create policy "envia o proprio avatar" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "troca o proprio avatar" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "apaga o proprio avatar" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatares' and (storage.foldername(name))[1] = (select auth.uid())::text);
