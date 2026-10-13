create index discussion_replies_author_idx on public.discussion_replies(author_id, created_at desc);
create index event_media_uploader_idx on public.event_media(uploaded_by, created_at desc);
