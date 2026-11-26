-- Bhandari Classes LMS schema. Apply in Supabase SQL Editor or via Supabase CLI.
create extension if not exists pgcrypto;
do $$ begin create type public.user_role as enum ('student','admin'); exception when duplicate_object then null; end $$;
do $$ begin create type public.enrolment_status as enum ('active','suspended','refunded'); exception when duplicate_object then null; end $$;
do $$ begin create type public.payment_status as enum ('created','paid','failed','refunded'); exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default 'Student', role public.user_role not null default 'student',
 avatar_url text, created_at timestamptz not null default now()
);
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Student')) on conflict(id) do nothing;return new;end;$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin');$$;

create table if not exists public.courses (
 id uuid primary key default gen_random_uuid(), title text not null, slug text not null unique,
 description text, category text not null default 'School Mathematics', grade text,
 price_paise bigint not null default 0 check(price_paise>=0), is_published boolean not null default false,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.lessons (
 id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
 title text not null, description text, object_key text not null unique, content_type text not null,
 size_bytes bigint not null check(size_bytes>0), duration_seconds integer, sort_order integer not null default 0,
 is_published boolean not null default false, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.enrollments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 course_id uuid not null references public.courses(id) on delete cascade, status public.enrolment_status not null default 'active',
 starts_at timestamptz not null default now(), expires_at timestamptz, created_at timestamptz not null default now(),
 unique(user_id,course_id)
);
create table if not exists public.payments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id),
 course_id uuid not null references public.courses(id), provider text not null default 'razorpay',
 provider_order_id text unique, provider_payment_id text unique, webhook_event_id text unique,
 amount_paise bigint not null check(amount_paise>=0), currency text not null default 'INR',
 status public.payment_status not null default 'created', created_at timestamptz not null default now()
);
create table if not exists public.quizzes (
 id uuid primary key default gen_random_uuid(), course_id uuid not null references public.courses(id) on delete cascade,
 title text not null, time_limit_seconds integer, total_marks numeric not null default 0,
 is_published boolean not null default false, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.quiz_questions (
 id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id) on delete cascade,
 question_text text not null, options jsonb not null default '[]'::jsonb, correct_option integer not null,
 explanation text, marks numeric not null default 1, sort_order integer not null default 0
);
create table if not exists public.quiz_attempts (
 id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id),
 user_id uuid not null references auth.users(id), score numeric not null default 0,
 answers jsonb not null default '{}'::jsonb, submitted_at timestamptz not null default now()
);
create table if not exists public.daily_questions (
 id uuid primary key default gen_random_uuid(), course_id uuid references public.courses(id) on delete set null,
 question_text text not null, options jsonb not null default '[]'::jsonb, correct_option integer not null,
 explanation text, publish_at timestamptz not null default now(), is_published boolean not null default false,
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.audit_logs (
 id bigint generated always as identity primary key, actor_id uuid references auth.users(id),
 action text not null, target_type text, target_id text, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.courses enable row level security;
alter table public.lessons enable row level security;
alter table public.enrollments enable row level security;
alter table public.payments enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_attempts enable row level security;
alter table public.daily_questions enable row level security;
alter table public.audit_logs enable row level security;

-- Profiles: users can read their own profile and update only non-role profile fields.
drop policy if exists profiles_read_own_or_admin on public.profiles;
create policy profiles_read_own_or_admin on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
revoke update on public.profiles from authenticated;
grant update(full_name,avatar_url) on public.profiles to authenticated;
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());

-- Published courses can be discovered; only admins can mutate.
drop policy if exists courses_read_published_or_admin on public.courses;
create policy courses_read_published_or_admin on public.courses for select to authenticated using(is_published or public.is_admin());
drop policy if exists courses_admin_all on public.courses;
create policy courses_admin_all on public.courses for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Lessons are visible to active enrollees only; admin can manage all lessons.
drop policy if exists lessons_read_authorised on public.lessons;
create policy lessons_read_authorised on public.lessons for select to authenticated using(public.is_admin() or (is_published and exists(select 1 from public.enrollments e where e.course_id=lessons.course_id and e.user_id=auth.uid() and e.status='active' and (e.expires_at is null or e.expires_at>now()))));
drop policy if exists lessons_admin_all on public.lessons;
create policy lessons_admin_all on public.lessons for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Enrolments: students can view only their own; only admin/server may grant or revoke access.
drop policy if exists enrolments_read_own_or_admin on public.enrollments;
create policy enrolments_read_own_or_admin on public.enrollments for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists enrolments_admin_all on public.enrollments;
create policy enrolments_admin_all on public.enrollments for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Payment rows are readable by their owner; creation/status changes must happen through a trusted server webhook.
drop policy if exists payments_read_own_or_admin on public.payments;
create policy payments_read_own_or_admin on public.payments for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists payments_admin_read on public.payments;
create policy payments_admin_read on public.payments for all to authenticated using(public.is_admin()) with check(public.is_admin());

-- Quiz content and daily questions: published content is visible to enrolled students; admin manages it.
drop policy if exists quizzes_read on public.quizzes;
create policy quizzes_read on public.quizzes for select to authenticated using(public.is_admin() or (is_published and exists(select 1 from public.enrollments e where e.course_id=quizzes.course_id and e.user_id=auth.uid() and e.status='active' and (e.expires_at is null or e.expires_at>now()))));
drop policy if exists quizzes_admin_all on public.quizzes;
create policy quizzes_admin_all on public.quizzes for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists quiz_questions_read on public.quiz_questions;
create policy quiz_questions_read on public.quiz_questions for select to authenticated using(public.is_admin() or exists(select 1 from public.quizzes q join public.enrollments e on e.course_id=q.course_id where q.id=quiz_questions.quiz_id and q.is_published and e.user_id=auth.uid() and e.status='active' and (e.expires_at is null or e.expires_at>now())));
drop policy if exists quiz_questions_admin_all on public.quiz_questions;
create policy quiz_questions_admin_all on public.quiz_questions for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists quiz_attempts_read_own on public.quiz_attempts;
create policy quiz_attempts_read_own on public.quiz_attempts for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists quiz_attempts_insert_own on public.quiz_attempts;
create policy quiz_attempts_insert_own on public.quiz_attempts for insert to authenticated with check(user_id=auth.uid());
drop policy if exists daily_questions_read on public.daily_questions;
create policy daily_questions_read on public.daily_questions for select to authenticated using(public.is_admin() or (is_published and publish_at<=now()));
drop policy if exists daily_questions_admin_all on public.daily_questions;
create policy daily_questions_admin_all on public.daily_questions for all to authenticated using(public.is_admin()) with check(public.is_admin());
drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read on public.audit_logs for select to authenticated using(public.is_admin());

-- Never expose a service-role key in browser code. It bypasses RLS; keep it server-side only if used.
