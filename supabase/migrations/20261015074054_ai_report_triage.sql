alter table public.reports
  add column ai_triage_status text not null default 'pending'
    check (ai_triage_status in ('pending', 'processing', 'assessed', 'unavailable', 'failed')),
  add column ai_triage_label text
    check (ai_triage_label is null or ai_triage_label in ('relevant', 'uncertain', 'irrelevant')),
  add column ai_triage_reason text
    check (ai_triage_reason is null or length(ai_triage_reason) <= 500),
  add column ai_triage_model text,
  add column ai_triaged_at timestamptz;

comment on column public.reports.ai_triage_label is
  'Unverified AI triage suggestion; never confirmation that an incident occurred.';
comment on column public.reports.ai_triage_reason is
  'Short explanation from the AI triage model; staff must review the visitor report.';
