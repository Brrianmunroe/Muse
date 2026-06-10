-- Add user notes and AI-generated description to images

alter table public.images
    add column if not exists ai_description text,
    add column if not exists notes text;

create policy "Users can update own images"
    on public.images for update
    using (auth.uid() = user_id);
