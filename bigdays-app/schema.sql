-- Big Days schema — run this once in Supabase SQL Editor

create table public.profiles (
  id uuid references auth.users on delete cascade primary key,
  username text unique not null,
  display_name text not null,
  avatar_color text default '#F5A623',
  created_at timestamptz default now()
);

create table public.events (
  id uuid default gen_random_uuid() primary key,
  owner_id uuid references public.profiles(id) on delete cascade not null,
  title text not null,
  event_date date not null,
  category text not null default 'other',
  visibility text not null default 'private', -- 'private' | 'friends'
  created_at timestamptz default now()
);

create table public.friendships (
  id uuid default gen_random_uuid() primary key,
  requester_id uuid references public.profiles(id) on delete cascade not null,
  addressee_id uuid references public.profiles(id) on delete cascade not null,
  status text not null default 'pending', -- 'pending' | 'accepted'
  created_at timestamptz default now(),
  unique(requester_id, addressee_id)
);

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.friendships enable row level security;

-- Profiles: any signed-in kid can search all usernames; only you can edit your own
create policy "profiles readable by all authenticated" on public.profiles
  for select using (auth.role() = 'authenticated');
create policy "profiles insert own" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles update own" on public.profiles
  for update using (auth.uid() = id);

-- Events: you fully control your own events
create policy "events owner all" on public.events
  for all using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
-- Events: accepted friends can see events you've marked "friends" visible
create policy "events friends can view shared" on public.events
  for select using (
    visibility = 'friends' and exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
      and ((f.requester_id = auth.uid() and f.addressee_id = owner_id)
        or (f.addressee_id = auth.uid() and f.requester_id = owner_id))
    )
  );

-- Friendships: only the two people involved can see or act on a friendship row
create policy "friendships select own" on public.friendships
  for select using (auth.uid() = requester_id or auth.uid() = addressee_id);
create policy "friendships insert as requester" on public.friendships
  for insert with check (auth.uid() = requester_id);
create policy "friendships update as participant" on public.friendships
  for update using (auth.uid() = addressee_id or auth.uid() = requester_id);

-- Enable live sync: lets connected devices see changes instantly without refreshing
alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.friendships;
