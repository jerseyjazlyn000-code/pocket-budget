-- Pocket Budget Couples — run this ONCE in your own Supabase SQL Editor.
-- Accounts are private by default: only authenticated members of a household can access records.
create table if not exists public.pb_households (
 id uuid primary key default gen_random_uuid(),
 invitation_code text not null unique check (invitation_code ~ '^[A-Z2-9]{16}$'),
 created_at timestamptz not null default now()
);
create table if not exists public.pb_members (
 household_id uuid not null references public.pb_households(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 display_name text not null check (char_length(display_name) between 1 and 40),
 joined_at timestamptz not null default now(),
 primary key (household_id, user_id),
 unique (user_id)
);
create table if not exists public.pb_opening_balances (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.pb_households(id) on delete cascade,
 owner_id uuid references auth.users(id) on delete cascade,
 account text not null check (account in ('Cash','Bank','Savings','Shared')),
 amount numeric(14,2) not null default 0 check (amount >= 0),
 constraint pb_opening_owner_check check ((account = 'Shared' and owner_id is null) or (account <> 'Shared' and owner_id is not null))
);
create unique index if not exists pb_opening_unique_person on public.pb_opening_balances(household_id,owner_id,account) where owner_id is not null;
create unique index if not exists pb_opening_unique_shared on public.pb_opening_balances(household_id,account) where owner_id is null;
create table if not exists public.pb_entries (
 id uuid primary key default gen_random_uuid(),
 household_id uuid not null references public.pb_households(id) on delete cascade,
 created_by uuid not null references auth.users(id),
 entry_date date not null default current_date,
 kind text not null check (kind in ('Income','Expense','Transfer')),
 description text not null default '' check (char_length(description)<=150),
 category text not null default 'Other' check (char_length(category)<=50),
 amount numeric(14,2) not null check (amount > 0),
 from_owner uuid references auth.users(id),
 to_owner uuid references auth.users(id),
 from_account text check (from_account in ('Cash','Bank','Savings','Shared')),
 to_account text check (to_account in ('Cash','Bank','Savings','Shared')),
 created_at timestamptz not null default now(),
 constraint pb_entry_account_check check (
   (from_account is null or ((from_account='Shared')=(from_owner is null)))
   and (to_account is null or ((to_account='Shared')=(to_owner is null)))
   and ((kind='Income' and from_account is null and to_account is not null)
   or (kind='Expense' and from_account is not null and to_account is null)
   or (kind='Transfer' and from_account is not null and to_account is not null
    and (from_owner is distinct from to_owner or from_account<>to_account)))
 )
);
create index if not exists pb_entries_household_date on public.pb_entries(household_id, entry_date desc);

alter table public.pb_households enable row level security;
alter table public.pb_members enable row level security;
alter table public.pb_opening_balances enable row level security;
alter table public.pb_entries enable row level security;

create or replace function public.pb_is_member(hid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.pb_members m where m.household_id=hid and m.user_id=(select auth.uid()));
$$;
create or replace function public.pb_is_user(hid uuid, person uuid)
returns boolean language sql stable security definer set search_path = '' as $$
 select person is null or exists(select 1 from public.pb_members m where m.household_id=hid and m.user_id=person);
$$;
revoke all on function public.pb_is_member(uuid), public.pb_is_user(uuid,uuid) from public;
grant execute on function public.pb_is_member(uuid), public.pb_is_user(uuid,uuid) to authenticated;

drop policy if exists pb_household_select on public.pb_households;
create policy pb_household_select on public.pb_households for select to authenticated using (public.pb_is_member(id));
drop policy if exists pb_members_select on public.pb_members;
create policy pb_members_select on public.pb_members for select to authenticated using (public.pb_is_member(household_id));

drop policy if exists pb_openings_select on public.pb_opening_balances;
create policy pb_openings_select on public.pb_opening_balances for select to authenticated using (public.pb_is_member(household_id));
drop policy if exists pb_openings_insert on public.pb_opening_balances;
create policy pb_openings_insert on public.pb_opening_balances for insert to authenticated with check (public.pb_is_member(household_id) and public.pb_is_user(household_id,owner_id));
drop policy if exists pb_openings_update on public.pb_opening_balances;
create policy pb_openings_update on public.pb_opening_balances for update to authenticated using (public.pb_is_member(household_id)) with check (public.pb_is_member(household_id) and public.pb_is_user(household_id,owner_id));
drop policy if exists pb_openings_delete on public.pb_opening_balances;
create policy pb_openings_delete on public.pb_opening_balances for delete to authenticated using (public.pb_is_member(household_id));

drop policy if exists pb_entries_select on public.pb_entries;
create policy pb_entries_select on public.pb_entries for select to authenticated using (public.pb_is_member(household_id));
drop policy if exists pb_entries_insert on public.pb_entries;
create policy pb_entries_insert on public.pb_entries for insert to authenticated with check (
 public.pb_is_member(household_id) and created_by=(select auth.uid())
 and public.pb_is_user(household_id,from_owner) and public.pb_is_user(household_id,to_owner));
drop policy if exists pb_entries_update on public.pb_entries;
create policy pb_entries_update on public.pb_entries for update to authenticated using (public.pb_is_member(household_id)) with check (
 public.pb_is_member(household_id) and public.pb_is_user(household_id,from_owner)
 and public.pb_is_user(household_id,to_owner) and public.pb_is_user(household_id,created_by));
drop policy if exists pb_entries_delete on public.pb_entries;
create policy pb_entries_delete on public.pb_entries for delete to authenticated using (public.pb_is_member(household_id));

grant select on public.pb_households, public.pb_members to authenticated;
grant select, insert, update, delete on public.pb_opening_balances, public.pb_entries to authenticated;
revoke all on public.pb_households,public.pb_members,public.pb_opening_balances,public.pb_entries from anon;

-- An invitation code is created by the first device using crypto.getRandomValues.
-- These functions validate the caller and enforce a maximum of two people.
create or replace function public.pb_create_household(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare hid uuid;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 40 then raise exception 'Enter a name'; end if;
 if coalesce(p_code,'') !~ '^[A-Z2-9]{16}$' then raise exception 'Invalid code'; end if;
 if exists(select 1 from public.pb_members where user_id=auth.uid()) then raise exception 'This account already belongs to a household'; end if;
 insert into public.pb_households(invitation_code) values(p_code) returning id into hid;
 insert into public.pb_members(household_id,user_id,display_name) values(hid,auth.uid(),trim(p_name));
 return hid;
end; $$;
create or replace function public.pb_join_household(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare hid uuid; c integer;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 if length(trim(coalesce(p_name,''))) not between 1 and 40 then raise exception 'Enter a name'; end if;
 if exists(select 1 from public.pb_members where user_id=auth.uid()) then raise exception 'This account already belongs to a household'; end if;
 select id into hid from public.pb_households where invitation_code=upper(trim(p_code)) for update;
 if hid is null then raise exception 'Invitation code not found'; end if;
 select count(*) into c from public.pb_members where household_id=hid;
 if c>=2 then raise exception 'This household already has two members'; end if;
 insert into public.pb_members(household_id,user_id,display_name) values(hid,auth.uid(),trim(p_name));
 return hid;
end; $$;
revoke all on function public.pb_create_household(text,text),public.pb_join_household(text,text) from public;
grant execute on function public.pb_create_household(text,text),public.pb_join_household(text,text) to authenticated;

-- Optional real-time notifications (app also polls every 15 seconds for reliability).
do $$ begin
 alter publication supabase_realtime add table public.pb_entries;
 exception when duplicate_object then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.pb_opening_balances;
 exception when duplicate_object then null; end $$;
do $$ begin
 alter publication supabase_realtime add table public.pb_members;
 exception when duplicate_object then null; end $$;
