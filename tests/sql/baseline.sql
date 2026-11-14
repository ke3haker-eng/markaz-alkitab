-- يحاكي مشروع Supabase القديم (قبل التحديث)
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema extensions; create extension pgcrypto with schema extensions;
grant usage on schema public, extensions to anon, authenticated, service_role;
create table centers(id uuid primary key default gen_random_uuid(), name text, manager_name text, status text default 'active', icon text, created_at timestamptz default now());
create table users(id uuid primary key default gen_random_uuid(), center_id uuid references centers(id), role text check (role in ('masool','supervisor','teacher','student')), username text, email text, password_hash text, full_name text, status text default 'active' check (status in ('active','pending','rejected')), halaqa_id text, created_at timestamptz default now());
create table halaqat(id text primary key, center_id uuid, name text, sheikh_name text, teacher_username text, teacher_user_id uuid, config jsonb);
create table students(id text primary key, halaqa_id text, user_id uuid references users(id), name text, username_cache text);
create table records(id text primary key, student_id text, halaqa_id text, center_id uuid);
create table messages(id uuid primary key default gen_random_uuid(), center_id uuid);
create table daily_questions(id uuid primary key default gen_random_uuid(), center_id uuid);
create table deleted_ids(id uuid primary key default gen_random_uuid(), center_id uuid);
-- صلاحيات Supabase الافتراضية: anon يملك كل شيء (والحماية على RLS فقط)
grant all on all tables in schema public to anon, authenticated, service_role;
