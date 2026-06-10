-- Muse: Initial database schema
-- Run this in the Supabase SQL Editor (Dashboard > SQL Editor > New Query)

-- 1. Users profile table (extends Supabase auth.users)
create table public.users (
    id uuid references auth.users(id) on delete cascade primary key,
    email text not null,
    display_name text,
    created_at timestamptz default now() not null
);

alter table public.users enable row level security;

create policy "Users can read own profile"
    on public.users for select
    using (auth.uid() = id);

create policy "Users can update own profile"
    on public.users for update
    using (auth.uid() = id);

-- Auto-create a user profile when someone signs up
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.users (id, email, display_name)
    values (
        new.id,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
    );
    return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- 2. Images table
create table public.images (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references public.users(id) on delete cascade not null,
    storage_path text not null,
    thumbnail_path text,
    width int,
    height int,
    source_app text,
    created_at timestamptz default now() not null
);

alter table public.images enable row level security;

create policy "Users can read own images"
    on public.images for select
    using (auth.uid() = user_id);

create policy "Users can insert own images"
    on public.images for insert
    with check (auth.uid() = user_id);

create policy "Users can delete own images"
    on public.images for delete
    using (auth.uid() = user_id);

create index idx_images_user_id on public.images(user_id);
create index idx_images_created_at on public.images(created_at desc);

-- 3. Tags table
create table public.tags (
    id uuid default gen_random_uuid() primary key,
    image_id uuid references public.images(id) on delete cascade not null,
    label text not null,
    category text not null check (category in ('typography', 'color', 'layout', 'style')),
    confidence double precision,
    created_at timestamptz default now() not null
);

alter table public.tags enable row level security;

create policy "Users can read tags on own images"
    on public.tags for select
    using (
        exists (
            select 1 from public.images
            where images.id = tags.image_id
            and images.user_id = auth.uid()
        )
    );

create policy "Service role can insert tags"
    on public.tags for insert
    with check (true);

create index idx_tags_image_id on public.tags(image_id);
create index idx_tags_category on public.tags(image_id, category);

-- 4. Collections table
create table public.collections (
    id uuid default gen_random_uuid() primary key,
    user_id uuid references public.users(id) on delete cascade not null,
    name text not null,
    description text,
    cover_image_id uuid references public.images(id) on delete set null,
    created_at timestamptz default now() not null
);

alter table public.collections enable row level security;

create policy "Users can read own collections"
    on public.collections for select
    using (auth.uid() = user_id);

create policy "Users can insert own collections"
    on public.collections for insert
    with check (auth.uid() = user_id);

create policy "Users can update own collections"
    on public.collections for update
    using (auth.uid() = user_id);

create policy "Users can delete own collections"
    on public.collections for delete
    using (auth.uid() = user_id);

-- 5. Collection-Images junction table
create table public.collection_images (
    collection_id uuid references public.collections(id) on delete cascade not null,
    image_id uuid references public.images(id) on delete cascade not null,
    sort_order int default 0 not null,
    added_at timestamptz default now() not null,
    primary key (collection_id, image_id)
);

alter table public.collection_images enable row level security;

create policy "Users can read own collection images"
    on public.collection_images for select
    using (
        exists (
            select 1 from public.collections
            where collections.id = collection_images.collection_id
            and collections.user_id = auth.uid()
        )
    );

create policy "Users can manage own collection images"
    on public.collection_images for insert
    with check (
        exists (
            select 1 from public.collections
            where collections.id = collection_images.collection_id
            and collections.user_id = auth.uid()
        )
    );

create policy "Users can remove from own collections"
    on public.collection_images for delete
    using (
        exists (
            select 1 from public.collections
            where collections.id = collection_images.collection_id
            and collections.user_id = auth.uid()
        )
    );

create index idx_collection_images_sort
    on public.collection_images(collection_id, sort_order);

-- 6. Create the storage bucket for images
insert into storage.buckets (id, name, public)
values ('inspiration-images', 'inspiration-images', true);

create policy "Users can upload own images"
    on storage.objects for insert
    with check (
        bucket_id = 'inspiration-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    );

create policy "Anyone can view images"
    on storage.objects for select
    using (bucket_id = 'inspiration-images');

create policy "Users can delete own images"
    on storage.objects for delete
    using (
        bucket_id = 'inspiration-images'
        and (storage.foldername(name))[1] = auth.uid()::text
    );
