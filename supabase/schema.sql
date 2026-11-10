-- =====================================================================
-- Money Moves NYC — Supabase schema
-- Run this whole file once in Supabase: Dashboard → SQL Editor → New query → paste → Run.
-- Safe to re-run: it drops and recreates functions/policies, and only
-- creates tables that don't exist yet.
--
-- Who can do what (enforced by Row Level Security, not by the web page):
--   • Students: read/update their own profile + progress, read their own
--     class, read their class leaderboard and class events.
--   • Facilitators: create classes, see every student and their progress
--     in classes they run, send class events. (Become a facilitator by
--     adding your user id to public.facilitators — see README.)
--   • Nobody can read another class's data.
-- Student logins use "class code + username + 6-digit PIN". Under the
-- hood each student is a Supabase Auth user whose email is a placeholder
-- (username.classcode@students.moneyhubnyc.co) that never receives mail.
-- =====================================================================

-- ---------- tables ----------
create table if not exists public.facilitators (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  name       text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.classes (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique check (code ~ '^[A-Z0-9-]{3,16}$'),
  name           text not null default '' check (char_length(name) <= 80),
  facilitator_id uuid not null references public.facilitators(user_id) on delete cascade,
  active         boolean not null default true,
  created_at     timestamptz not null default now()
);

create table if not exists public.students (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  class_id     uuid not null references public.classes(id) on delete cascade,
  username     text not null check (username ~ '^[a-z0-9_]{3,16}$'),
  display_name text not null check (char_length(display_name) between 1 and 14),
  look         smallint not null default 0 check (look between 0 and 3),
  lang         text not null default 'en' check (lang in ('en','es')),
  created_at   timestamptz not null default now(),
  last_seen    timestamptz not null default now(),
  unique (class_id, username)
);
create index if not exists students_class_idx on public.students(class_id);

create table if not exists public.progress (
  user_id    uuid primary key references public.students(user_id) on delete cascade,
  state      jsonb not null default '{}'::jsonb,
  score      int not null default 0,
  best       int not null default 0,
  milestones smallint not null default 0,
  stars      smallint not null default 0,
  done       boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint progress_state_size check (pg_column_size(state) < 200000)
);

create table if not exists public.runs (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.students(user_id) on delete cascade,
  score       int not null check (score between 0 and 16000),
  stars       smallint not null default 0 check (stars between 0 and 60),
  finished_at timestamptz not null default now()
);
create index if not exists runs_user_idx on public.runs(user_id);
-- v2 (3 levels, 20 milestones): widen limits on databases created with v1
alter table public.runs drop constraint if exists runs_score_check;
alter table public.runs add constraint runs_score_check check (score between 0 and 16000);
alter table public.runs drop constraint if exists runs_stars_check;
alter table public.runs add constraint runs_stars_check check (stars between 0 and 60);

create table if not exists public.class_events (
  id         bigint generated always as identity primary key,
  class_id   uuid not null references public.classes(id) on delete cascade,
  ev         text not null check (ev in ('CRASH','RENT','BONUS','PHISH','PRICE','LAYOFF')),
  created_at timestamptz not null default now()
);
create index if not exists class_events_class_idx on public.class_events(class_id, created_at desc);

-- ---------- helper functions (used by policies) ----------
create or replace function public.is_facilitator() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from facilitators where user_id = auth.uid())
$$;

create or replace function public.my_class_id() returns uuid
language sql stable security definer set search_path = public as $$
  select class_id from students where user_id = auth.uid()
$$;

create or replace function public.teaches(p_class uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from classes where id = p_class and facilitator_id = auth.uid())
$$;

create or replace function public.teaches_student(p_student uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from students s join classes c on c.id = s.class_id
    where s.user_id = p_student and c.facilitator_id = auth.uid())
$$;

-- ---------- progress guard: clamps numbers, keeps best score ----------
create or replace function public.progress_guard() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.score      := greatest(0, least(coalesce(new.score, 0), 16000));
  new.milestones := greatest(0, least(coalesce(new.milestones, 0), 20));
  new.stars      := greatest(0, least(coalesce(new.stars, 0), 60));
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.best    := greatest(coalesce(old.best, 0), new.score);
  else
    new.best    := greatest(coalesce(new.best, 0), new.score);
  end if;
  return new;
end $$;

drop trigger if exists progress_guard on public.progress;
create trigger progress_guard before insert or update on public.progress
  for each row execute function public.progress_guard();

-- ---------- row level security ----------
alter table public.facilitators enable row level security;
alter table public.classes      enable row level security;
alter table public.students     enable row level security;
alter table public.progress     enable row level security;
alter table public.runs         enable row level security;
alter table public.class_events enable row level security;

-- table privileges: logged-out visitors get nothing; logged-in users get
-- only what the policies below allow. Student profile rows are created
-- only through join_class(), and students may edit only cosmetic columns.
revoke all on public.facilitators, public.classes, public.students,
              public.progress, public.runs, public.class_events from anon;
revoke all on public.facilitators, public.classes, public.students,
              public.progress, public.runs, public.class_events from authenticated;
grant select on public.facilitators to authenticated;
grant select, insert, update on public.classes to authenticated;
grant select, delete on public.students to authenticated;
grant update (display_name, look, lang, last_seen) on public.students to authenticated;
grant select, update on public.progress to authenticated;
grant select, insert on public.runs to authenticated;
grant select, insert on public.class_events to authenticated;
grant usage on sequence public.runs_id_seq, public.class_events_id_seq to authenticated;

drop policy if exists fac_select_own on public.facilitators;
create policy fac_select_own on public.facilitators for select to authenticated
  using (user_id = auth.uid());

drop policy if exists classes_select on public.classes;
create policy classes_select on public.classes for select to authenticated
  using (facilitator_id = auth.uid() or id = public.my_class_id());
drop policy if exists classes_insert on public.classes;
create policy classes_insert on public.classes for insert to authenticated
  with check (facilitator_id = auth.uid() and public.is_facilitator());
drop policy if exists classes_update on public.classes;
create policy classes_update on public.classes for update to authenticated
  using (facilitator_id = auth.uid()) with check (facilitator_id = auth.uid());

drop policy if exists students_select on public.students;
create policy students_select on public.students for select to authenticated
  using (user_id = auth.uid() or public.teaches(class_id));
drop policy if exists students_update_own on public.students;
create policy students_update_own on public.students for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists students_delete_teacher on public.students;
create policy students_delete_teacher on public.students for delete to authenticated
  using (public.teaches(class_id));

drop policy if exists progress_select on public.progress;
create policy progress_select on public.progress for select to authenticated
  using (user_id = auth.uid() or public.teaches_student(user_id));
drop policy if exists progress_update_own on public.progress;
create policy progress_update_own on public.progress for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists runs_select on public.runs;
create policy runs_select on public.runs for select to authenticated
  using (user_id = auth.uid() or public.teaches_student(user_id));
drop policy if exists runs_insert_own on public.runs;
create policy runs_insert_own on public.runs for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists events_select on public.class_events;
create policy events_select on public.class_events for select to authenticated
  using (class_id = public.my_class_id() or public.teaches(class_id));
drop policy if exists events_insert_teacher on public.class_events;
create policy events_insert_teacher on public.class_events for insert to authenticated
  with check (public.teaches(class_id));

-- ---------- RPCs the game calls ----------

-- Before creating a login: is the class real, and is the username free?
-- Callable while logged out. Returns 'ok', 'class_not_found',
-- 'username_taken' or 'bad_username'.
create or replace function public.check_signup(p_code text, p_username text) returns text
language plpgsql stable security definer set search_path = public as $$
declare cid uuid;
begin
  if lower(trim(p_username)) !~ '^[a-z0-9_]{3,16}$' then return 'bad_username'; end if;
  select id into cid from classes where code = upper(trim(p_code)) and active;
  if cid is null then return 'class_not_found'; end if;
  if exists (select 1 from students where class_id = cid and username = lower(trim(p_username))) then
    return 'username_taken';
  end if;
  return 'ok';
end $$;

-- Right after sign-up: attach the new login to a class.
create or replace function public.join_class(p_code text, p_username text, p_display text,
                                             p_look int default 0, p_lang text default 'en')
returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cid uuid;
begin
  if uid is null then raise exception 'not_signed_in'; end if;
  if exists (select 1 from facilitators where user_id = uid) then raise exception 'facilitators_cannot_join'; end if;
  select id into cid from classes where code = upper(trim(p_code)) and active;
  if cid is null then raise exception 'class_not_found'; end if;
  if exists (select 1 from students where user_id = uid) then raise exception 'already_joined'; end if;
  insert into students (user_id, class_id, username, display_name, look, lang)
  values (uid, cid, lower(trim(p_username)), left(coalesce(nullif(trim(p_display), ''), trim(p_username)), 14),
          greatest(0, least(coalesce(p_look, 0), 3)),
          case when p_lang = 'es' then 'es' else 'en' end);
  insert into progress (user_id) values (uid);
  return cid;
end $$;

-- Everything the game needs about the logged-in student, in one call.
-- squad = which group of 8 they share the live world with (keeps
-- realtime traffic within Supabase plan limits).
create or replace function public.my_context()
returns table (class_id uuid, code text, class_name text, username text, display_name text,
               look smallint, lang text, squad int)
language sql stable security definer set search_path = public as $$
  with me as (select * from students where user_id = auth.uid()),
  ranked as (
    select s.user_id, (row_number() over (order by s.created_at, s.user_id) - 1)::int / 8 as squad
    from students s where s.class_id = (select class_id from me))
  select c.id, c.code, c.name, me.username, me.display_name, me.look, me.lang,
         (select r.squad from ranked r where r.user_id = me.user_id)
  from me join classes c on c.id = me.class_id
$$;

-- Class leaderboard. Students see their own class; facilitators see classes they run.
create or replace function public.class_leaderboard(p_class uuid)
returns table (username text, display_name text, best int, score int, milestones smallint,
               done boolean, updated_at timestamptz, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  if p_class is null or not (coalesce(p_class = public.my_class_id(), false) or public.teaches(p_class)) then
    raise exception 'not_allowed';
  end if;
  return query
    select s.username, s.display_name, p.best, p.score, p.milestones, p.done, p.updated_at,
           s.user_id = auth.uid()
    from students s join progress p on p.user_id = s.user_id
    where s.class_id = p_class
    order by p.best desc, p.updated_at asc
    limit 300;
end $$;

-- Class events from the last 15 minutes for the student's own class.
create or replace function public.recent_class_events()
returns table (id bigint, ev text, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select e.id, e.ev, e.created_at from class_events e
  where e.class_id = public.my_class_id() and e.created_at > now() - interval '15 minutes'
  order by e.created_at
$$;

-- lock down function execution
revoke execute on all functions in schema public from public, anon;
grant execute on function public.check_signup(text, text) to anon, authenticated;
grant execute on function public.join_class(text, text, text, int, text) to authenticated;
grant execute on function public.my_context() to authenticated;
grant execute on function public.class_leaderboard(uuid) to authenticated;
grant execute on function public.recent_class_events() to authenticated;
grant execute on function public.is_facilitator(), public.my_class_id(),
                          public.teaches(uuid), public.teaches_student(uuid) to authenticated;
