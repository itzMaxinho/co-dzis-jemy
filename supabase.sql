-- CO DZIŚ JEMY? — Supabase schema
-- Uruchom w Supabase → SQL Editor → New query.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  nickname text,
  role text not null default 'user' check (role in ('user','admin')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare uname text;
begin
  uname := lower(coalesce(new.raw_user_meta_data->>'username', split_part(new.email,'@',1)));
  insert into public.profiles(id, username) values(new.id, uname)
  on conflict (id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, created_at timestamptz not null default now()
);
create table if not exists public.dishes (
  id uuid primary key default gen_random_uuid(), name text not null, category_id uuid references public.categories(id),
  description text, ingredients text, image_url text, available boolean not null default true,
  created_by uuid references public.profiles(id), created_at timestamptz not null default now()
);
create table if not exists public.favorites (
  user_id uuid not null references public.profiles(id) on delete cascade,
  dish_id uuid not null references public.dishes(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id,dish_id)
);
create table if not exists public.ratings (
  user_id uuid not null references public.profiles(id) on delete cascade,
  dish_id uuid not null references public.dishes(id) on delete cascade,
  score integer not null check(score between 0 and 10), updated_at timestamptz not null default now(), primary key(user_id,dish_id)
);
create table if not exists public.dish_requests (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  dish_id uuid not null references public.dishes(id), status text not null default 'pending' check(status in ('pending','accepted','rejected')),
  admin_note text, created_at timestamptz not null default now(), handled_at timestamptz
);
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null, body text not null default '', related_request_id uuid references public.dish_requests(id) on delete set null,
  read boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(), title text not null, status text not null default 'active' check(status in ('active','finished')),
  created_by uuid references public.profiles(id), created_at timestamptz not null default now(), ends_at timestamptz not null
);
create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(), poll_id uuid not null references public.polls(id) on delete cascade,
  dish_id uuid not null references public.dishes(id), sort_order integer not null default 0, unique(poll_id,dish_id)
);
create table if not exists public.poll_votes (
  id uuid primary key default gen_random_uuid(), poll_id uuid not null references public.polls(id) on delete cascade,
  option_id uuid not null references public.poll_options(id) on delete cascade,
  visitor_token uuid not null, created_at timestamptz not null default now(), unique(poll_id,visitor_token,option_id)
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.dishes enable row level security;
alter table public.favorites enable row level security;
alter table public.ratings enable row level security;
alter table public.dish_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

-- Profiles: users can read their own profile; admins can read/manage all profiles.
drop policy if exists "profile read" on public.profiles;
create policy "profile read" on public.profiles for select using (id=auth.uid() or public.is_admin());
drop policy if exists "admin profile update" on public.profiles;
create policy "admin profile update" on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admin profile delete" on public.profiles;
create policy "admin profile delete" on public.profiles for delete to authenticated using (public.is_admin());

-- Categories and dishes are public to read; only admin can change them.
drop policy if exists "categories public read" on public.categories;
create policy "categories public read" on public.categories for select using (true);
drop policy if exists "categories admin write" on public.categories;
create policy "categories admin write" on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "dishes public read" on public.dishes;
create policy "dishes public read" on public.dishes for select using (available=true or public.is_admin());
drop policy if exists "dishes admin write" on public.dishes;
create policy "dishes admin write" on public.dishes for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Personal lists and ratings.
drop policy if exists "favorites owner or admin" on public.favorites;
create policy "favorites owner or admin" on public.favorites for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "favorites owner insert" on public.favorites;
create policy "favorites owner insert" on public.favorites for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "favorites owner delete" on public.favorites;
create policy "favorites owner delete" on public.favorites for delete to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "ratings owner or admin" on public.ratings;
create policy "ratings owner or admin" on public.ratings for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "ratings owner insert" on public.ratings;
create policy "ratings owner insert" on public.ratings for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "ratings owner update" on public.ratings;
create policy "ratings owner update" on public.ratings for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- Dish requests: users submit and see their own; admin handles all.
drop policy if exists "requests owner or admin read" on public.dish_requests;
create policy "requests owner or admin read" on public.dish_requests for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "requests owner insert" on public.dish_requests;
create policy "requests owner insert" on public.dish_requests for insert to authenticated with check (user_id=auth.uid());
drop policy if exists "requests admin update" on public.dish_requests;
create policy "requests admin update" on public.dish_requests for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Notifications are private to their recipient; admin can create notifications.
drop policy if exists "notifications owner read" on public.notifications;
create policy "notifications owner read" on public.notifications for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists "notifications owner update" on public.notifications;
create policy "notifications owner update" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
drop policy if exists "notifications admin insert" on public.notifications;
create policy "notifications admin insert" on public.notifications for insert to authenticated with check (public.is_admin());

-- Polls/options are public to read while active; admin manages them.
drop policy if exists "polls public active read" on public.polls;
create policy "polls public active read" on public.polls for select using (status='active' or public.is_admin());
drop policy if exists "polls admin write" on public.polls;
create policy "polls admin write" on public.polls for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "poll options public read" on public.poll_options;
create policy "poll options public read" on public.poll_options for select using (exists(select 1 from public.polls p where p.id=poll_id and (p.status='active' or public.is_admin())));
drop policy if exists "poll options admin write" on public.poll_options;
create policy "poll options admin write" on public.poll_options for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "poll votes public read" on public.poll_votes;
create policy "poll votes public read" on public.poll_votes for select using (exists(select 1 from public.polls p where p.id=poll_id and p.status='active') or public.is_admin());

-- Anonymous or logged-in visitor can cast at most three options per poll.
create or replace function public.cast_poll_votes(p_poll_id uuid,p_option_ids uuid[],p_visitor_token uuid)
returns void language plpgsql security definer set search_path=public as $$
declare opt_count integer;
begin
  if p_visitor_token is null then raise exception 'Brak identyfikatora głosującego.'; end if;
  if cardinality(coalesce(p_option_ids,'{}'::uuid[])) > 3 then raise exception 'Możesz wybrać maksymalnie trzy dania.'; end if;
  if not exists(select 1 from public.polls where id=p_poll_id and status='active' and ends_at>now()) then raise exception 'Głosowanie jest już zakończone.'; end if;
  select count(*) into opt_count from public.poll_options where poll_id=p_poll_id and id=any(coalesce(p_option_ids,'{}'::uuid[]));
  if opt_count <> cardinality(coalesce(p_option_ids,'{}'::uuid[])) then raise exception 'Nieprawidłowa opcja głosowania.'; end if;
  delete from public.poll_votes where poll_id=p_poll_id and visitor_token=p_visitor_token;
  insert into public.poll_votes(poll_id,option_id,visitor_token) select p_poll_id,x,p_visitor_token from unnest(coalesce(p_option_ids,'{}'::uuid[])) x;
end; $$;
grant execute on function public.cast_poll_votes(uuid,uuid[],uuid) to anon,authenticated;

create or replace function public.finish_poll(p_poll_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin() then raise exception 'Brak uprawnień administratora.'; end if;
  update public.polls set status='finished' where id=p_poll_id and status='active';
end; $$;
grant execute on function public.finish_poll(uuid) to authenticated;

create or replace function public.finish_expired_polls()
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.polls set status='finished' where status='active' and ends_at<=now();
end; $$;
grant execute on function public.finish_expired_polls() to anon,authenticated;

-- Admin account deletion through a protected function.
create or replace function public.admin_delete_user(p_user_id uuid)
returns void language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_admin() then raise exception 'Brak uprawnień administratora.'; end if;
  if p_user_id=auth.uid() then raise exception 'Nie możesz usunąć własnego konta.'; end if;
  delete from auth.users where id=p_user_id;
end; $$;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- Notify administrators automatically when a poll ends (including timeout).
create or replace function public.notify_admin_poll_result()
returns trigger language plpgsql security definer set search_path=public as $$
declare summary text;
begin
  if old.status='active' and new.status='finished' then
    select string_agg(d.name||': '||coalesce(v.cnt,0)::text||' głosów', E'\n' order by coalesce(v.cnt,0) desc)
    into summary from public.poll_options po join public.dishes d on d.id=po.dish_id
    left join (select option_id,count(*) cnt from public.poll_votes where poll_id=new.id group by option_id) v on v.option_id=po.id
    where po.poll_id=new.id;
    insert into public.notifications(user_id,title,body)
    select id,'Wyniki głosowania: '||new.title,coalesce(summary,'Brak głosów.') from public.profiles where role='admin';
  end if;
  return new;
end; $$;
drop trigger if exists poll_finished_notify_admin on public.polls;
create trigger poll_finished_notify_admin after update of status on public.polls for each row execute function public.notify_admin_poll_result();

-- Storage bucket for dish photos.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('dish-images','dish-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
drop policy if exists "dish photos public read" on storage.objects;
create policy "dish photos public read" on storage.objects for select using(bucket_id='dish-images');
drop policy if exists "dish photos admin upload" on storage.objects;
create policy "dish photos admin upload" on storage.objects for insert to authenticated with check(bucket_id='dish-images' and public.is_admin());
drop policy if exists "dish photos admin update" on storage.objects;
create policy "dish photos admin update" on storage.objects for update to authenticated using(bucket_id='dish-images' and public.is_admin()) with check(bucket_id='dish-images' and public.is_admin());
drop policy if exists "dish photos admin delete" on storage.objects;
create policy "dish photos admin delete" on storage.objects for delete to authenticated using(bucket_id='dish-images' and public.is_admin());

-- Starter categories.
insert into public.categories(name) values ('Obiady'),('Zupy'),('Makarony'),('Desery'),('Przekąski') on conflict(name) do nothing;

-- Notify admins whenever a signed-in user asks for a dish.
create or replace function public.notify_admin_new_request()
returns trigger language plpgsql security definer set search_path=public as $$
declare dish_title text; requester text;
begin
  select name into dish_title from public.dishes where id=new.dish_id;
  select coalesce(nickname,username) into requester from public.profiles where id=new.user_id;
  insert into public.notifications(user_id,title,body,related_request_id)
  select id,'Nowa prośba o danie',requester||' chce zjeść: '||coalesce(dish_title,'danie')||'.',new.id
  from public.profiles where role='admin';
  return new;
end; $$;
drop trigger if exists dish_request_notify_admin on public.dish_requests;
create trigger dish_request_notify_admin after insert on public.dish_requests for each row execute function public.notify_admin_new_request();
