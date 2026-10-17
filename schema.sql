-- Caltera City Forum database schema for Supabase/Postgres
-- Run once in Supabase Dashboard > SQL Editor.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (char_length(username) between 2 and 24),
  role text not null default 'Spieler',
  profile_visibility text not null default 'Öffentlich' check (profile_visibility in ('Öffentlich','Nur Mitglieder')),
  mention_notifications boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.custom_roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (char_length(name) between 2 and 30),
  permissions jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.topics (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  forum text not null,
  title text not null check (char_length(title) between 2 and 120),
  body text not null check (char_length(body) > 0),
  player_id text not null,
  organization text not null default '',
  prefix text not null default 'Wartet auf Bearbeitung',
  tags text[] not null default '{}',
  closed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists topics_forum_created_idx on public.topics (forum, created_at desc);

create table if not exists public.replies (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.topics(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 5000),
  created_at timestamptz not null default now()
);
create index if not exists replies_topic_created_idx on public.replies (topic_id, created_at);

create table if not exists public.achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  topic_id uuid not null references public.topics(id) on delete cascade,
  label text not null,
  earned_at timestamptz not null default now(),
  unique (user_id, topic_id)
);

create or replace function public.has_forum_permission(permission_name text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    case p.role
      when 'Inhaber' then true
      when 'Adminleitung' then permission_name in ('adminPanel','closeTopics','changePrefix','assignRanks')
      when 'Administrator' then permission_name in ('adminPanel','closeTopics','changePrefix','assignRanks')
      when 'Moderator' then permission_name in ('adminPanel','closeTopics','changePrefix')
      else coalesce((cr.permissions ->> permission_name)::boolean, false)
    end,
    false
  )
  from public.profiles p
  left join public.custom_roles cr on cr.name = p.role
  where p.id = auth.uid()
$$;

create or replace function public.create_forum_profile()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  desired_name text;
begin
  desired_name := coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), split_part(new.email, '@', 1));
  insert into public.profiles (id, username, role)
  values (new.id, left(desired_name, 24), 'Spieler')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute procedure public.create_forum_profile();

-- A single moderation RPC updates the status and awards the author on acceptance/rejection.
create or replace function public.moderate_topic(topic_id uuid, new_prefix text, new_closed boolean default null)
returns void
language plpgsql security definer
set search_path = public
as $$
declare
  topic_author uuid;
begin
  if new_prefix is not null and not public.has_forum_permission('changePrefix') then
    raise exception 'Missing permission: changePrefix';
  end if;
  if new_closed is not null and not public.has_forum_permission('closeTopics') then
    raise exception 'Missing permission: closeTopics';
  end if;
  update public.topics
  set prefix = coalesce(new_prefix, prefix), closed = coalesce(new_closed, closed)
  where id = topic_id
  returning author_id into topic_author;
  if topic_author is null then raise exception 'Topic not found'; end if;
  if new_prefix = 'Angenommen' then
    insert into public.achievements(user_id, topic_id, label)
    values (topic_author, topic_id, 'Thema angenommen')
    on conflict (user_id, topic_id) do update set label = excluded.label, earned_at = now();
  elsif new_prefix = 'Abgelehnt' then
    insert into public.achievements(user_id, topic_id, label)
    values (topic_author, topic_id, 'Thema abgelehnt')
    on conflict (user_id, topic_id) do update set label = excluded.label, earned_at = now();
  end if;
end;
$$;

alter table public.profiles enable row level security;
alter table public.custom_roles enable row level security;
alter table public.topics enable row level security;
alter table public.replies enable row level security;
alter table public.achievements enable row level security;

-- Public forum content can be read without signing in.
drop policy if exists "profiles are visible" on public.profiles;
create policy "profiles are visible" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "users update own profile" on public.profiles;
create policy "users update own profile" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
grant select on public.profiles to anon, authenticated;
grant update (username, profile_visibility, mention_notifications) on public.profiles to authenticated;

create policy "custom roles are readable" on public.custom_roles for select to anon, authenticated using (true);
create policy "authorized staff create roles" on public.custom_roles for insert to authenticated with check (public.has_forum_permission('manageRanks') and created_by = auth.uid());
create policy "authorized staff edit roles" on public.custom_roles for update to authenticated using (public.has_forum_permission('manageRanks')) with check (public.has_forum_permission('manageRanks'));
create policy "authorized staff delete roles" on public.custom_roles for delete to authenticated using (public.has_forum_permission('manageRanks'));
grant select on public.custom_roles to anon, authenticated;
grant insert, update, delete on public.custom_roles to authenticated;

create policy "topics are readable" on public.topics for select to anon, authenticated using (true);
create policy "signed in players create topics" on public.topics for insert to authenticated with check (author_id = auth.uid());
create policy "staff moderate topics" on public.topics for update to authenticated using (public.has_forum_permission('changePrefix') or public.has_forum_permission('closeTopics')) with check (public.has_forum_permission('changePrefix') or public.has_forum_permission('closeTopics'));
grant select on public.topics to anon, authenticated;
grant insert on public.topics to authenticated;
grant update (prefix, closed) on public.topics to authenticated;

create policy "replies are readable" on public.replies for select to anon, authenticated using (true);
create policy "players reply while open" on public.replies for insert to authenticated with check (
  author_id = auth.uid() and exists (
    select 1 from public.topics t where t.id = topic_id and (not t.closed or public.has_forum_permission('closeTopics'))
  )
);
grant select on public.replies to anon, authenticated;
grant insert on public.replies to authenticated;

create policy "users and staff read achievements" on public.achievements for select to authenticated using (user_id = auth.uid() or public.has_forum_permission('adminPanel'));
grant select on public.achievements to authenticated;
grant execute on function public.moderate_topic(uuid, text, boolean) to authenticated;
