-- sublet-skills schema v2 (hợp nhất). Supabase project riêng cho sublet.
-- RLS bật, không policy → chỉ service_role (scripts/db.py qua rpc sublet_exec, hoặc Supabase MCP) đọc/ghi.
-- Idempotent: chạy lại được.

create extension if not exists pgcrypto;

-- ---------- helpers ----------
create or replace function sublet_touch() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- ---------- groups (KNOW) ----------
create table if not exists sublet_groups (
  key text primary key,
  name text not null,
  url text unique,
  city text not null default 'Amsterdam',
  tier int check (tier in (1,2,3)),
  is_private boolean,
  member_count int,
  allows_sublet text not null default 'unknown' check (allows_sublet in ('yes','no','unknown')),
  allows_agencies text not null default 'unknown' check (allows_agencies in ('yes','no','unknown')),
  joined boolean not null default false,
  notif_all_posts boolean not null default false,
  offering_7d int not null default 0,
  last_post_seen_at timestamptz,
  last_scanned_at timestamptz,
  last_ranked_at timestamptz,
  discovered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);

-- ---------- listings (CAPTURE + ANALYZE) ----------
create table if not exists sublet_listings (
  id uuid primary key default gen_random_uuid(),
  city text not null default 'Amsterdam',
  -- capture
  source text not null check (source in ('fb_feed','fb_notif','fb_email','form','manual')),
  source_url text unique,
  -- link evidence is captured first; validation happens in a separate browser skill
  link_validation_status text not null default 'unvalidated'
    check (link_validation_status in ('unvalidated','validated','inaccessible','needs_review')),
  link_validated_url text,
  link_validated_at timestamptz,
  link_validation_attempts int not null default 0,
  link_validation_note text,
  group_key text references sublet_groups(key) on delete set null,
  poster_name text,
  posted_at timestamptz,
  seen_at timestamptz not null default now(),
  raw_text text not null,
  text_hash text generated always as (md5(lower(regexp_replace(raw_text, '\s+', ' ', 'g')))) stored,
  canonical_id uuid references sublet_listings(id) on delete set null,   -- cùng 1 listing đăng ở nhiều group → trỏ về bản đầu
  -- analyze (docs/intent-logic.md)
  kind text check (kind in ('offering','seeking','other')),
  subtype text check (subtype in ('sublet_whole','sublet_room','takeover','roommate','swap','short_stay','long_term','seek_sublet','seek_room','seek_group')),
  poster_type text check (poster_type in ('individual','proxy','agency')),
  confidence text check (confidence in ('high','medium','low')),
  area text,
  room_type text check (room_type in ('room','studio','apartment','other')),
  rent_eur int,
  deposit_eur int,
  bills_included text,
  available_from date,
  available_to date,
  min_term_days int,
  furnished boolean,
  registration_allowed text not null default 'unknown' check (registration_allowed in ('yes','no','unknown')),
  sublet_permission text not null default 'unknown' check (sublet_permission in ('yes','no','unknown')),
  max_people int,
  poster_constraints text,
  scam_score int not null default 0,
  scam_flags text[] not null default '{}',
  deal_score int,
  -- lifecycle
  status text not null default 'new' check (status in ('new','contacted','accepted','declined','matched','viewing','filled','dead')),
  contacted_at timestamptz,
  accepted_at timestamptz,
  filled_at timestamptz,
  offer_link text,
  notes text,
  analyzed_at timestamptz,
  updated_at timestamptz not null default now()
);

-- ---------- seekers (demand pool) ----------
create table if not exists sublet_seekers (
  id uuid primary key default gen_random_uuid(),
  city text not null default 'Amsterdam',
  source text not null check (source in ('form','whatsapp','fb_seeking','manual')),
  source_url text,
  name text,
  contact text,
  contact_consent boolean not null default false,
  language text default 'en',
  move_in date,
  move_out date,
  flex_days int not null default 7,
  budget_eur int,
  areas text[] not null default '{}',
  people int not null default 1,
  registration_need boolean not null default false,
  pets boolean not null default false,
  occupation text,
  viewing_availability text,
  status text not null default 'active' check (status in ('active','matched','viewing','housed','inactive')),
  last_pushed_at timestamptz,
  push_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);
create index if not exists sublet_seekers_active_idx on sublet_seekers(move_in) where status='active';
create unique index if not exists sublet_seekers_contact_uq on sublet_seekers(lower(contact)) where contact is not null;

-- ---------- matches ----------
create table if not exists sublet_matches (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references sublet_listings(id) on delete cascade,
  seeker_id uuid not null references sublet_seekers(id) on delete cascade,
  score int not null,
  reasons text,
  risk_flags text[] not null default '{}',
  status text not null default 'proposed' check (status in ('proposed','pushed','replied','shortlisted','viewing','rejected','signed')),
  pushed_at timestamptz,
  replied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (listing_id, seeker_id)
);
create index if not exists sublet_matches_listing_idx on sublet_matches(listing_id, status);

-- ---------- viewings ----------
create table if not exists sublet_viewings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references sublet_matches(id) on delete cascade,
  scheduled_at timestamptz,
  confirmed boolean not null default false,
  attendance text not null default 'pending' check (attendance in ('pending','showed','no_show','cancelled')),
  landlord_feedback text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- fees ----------
create table if not exists sublet_fees (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references sublet_listings(id) on delete cascade,
  trigger text not null check (trigger in ('three_viewings_72h','move_in','signed','manual')),
  amount_eur int not null,
  invoice_status text not null default 'draft' check (invoice_status in ('draft','sent','paid','waived','disputed')),
  payment_link text,
  sent_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  notes text
);

-- ---------- messages (drafts + inbound) ----------
create table if not exists sublet_messages (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('listing','seeker','match','viewing')),
  entity_id uuid not null,
  direction text not null check (direction in ('out','in')),
  channel text not null check (channel in ('fb_dm','whatsapp','email','telegram','other')),
  template text,                    -- id kiểu offer (partner-voice) để đo yes-rate
  body text not null,
  in_reply_to uuid references sublet_messages(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','approved','sent','received')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index if not exists sublet_messages_entity_idx on sublet_messages(entity_type, entity_id, created_at desc);
create index if not exists sublet_messages_draft_idx on sublet_messages(created_at) where status='draft';

-- ---------- events (provenance) ----------
create table if not exists sublet_events (
  id bigserial primary key,
  entity_type text not null,
  entity_id uuid,
  event text not null,
  actor text not null default 'agent' check (actor in ('agent','human','system')),
  source_url text,
  payload jsonb,
  created_at timestamptz not null default now()
);
create index if not exists sublet_events_entity_idx on sublet_events(entity_type, entity_id, created_at desc);

-- ---------- scan runs (volume control) ----------
create table if not exists sublet_scan_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  mode text not null check (mode in ('feed','notifications','email','group_page','search','backfill')),
  group_key text,
  page_loads int not null default 0,
  posts_seen int not null default 0,
  new_listings int not null default 0,
  cursor text,
  stopped_reason text
);
create index if not exists sublet_scan_runs_started_idx on sublet_scan_runs(started_at desc);

-- ---------- ops ----------
create table if not exists sublet_ops_state (
  key text primary key,
  value text,
  updated_at timestamptz not null default now()
);
create table if not exists sublet_inbox (
  id bigserial primary key,
  level text not null default 'info' check (level in ('info','action','warning','stop')),
  title text not null,
  body text,
  entity_type text,
  entity_id uuid,
  message_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  done_at timestamptz
);
create index if not exists sublet_inbox_open_idx on sublet_inbox(created_at desc) where done_at is null;

-- ---------- upgrade v1 → v2 (idempotent; chạy sau create table) ----------
alter table sublet_groups
  add column if not exists city text not null default 'Amsterdam',
  add column if not exists updated_at timestamptz not null default now();
alter table sublet_listings
  add column if not exists city text not null default 'Amsterdam',
  add column if not exists link_validation_status text not null default 'unvalidated',
  add column if not exists link_validated_url text,
  add column if not exists link_validated_at timestamptz,
  add column if not exists link_validation_attempts int not null default 0,
  add column if not exists link_validation_note text,
  add column if not exists canonical_id uuid references sublet_listings(id) on delete set null,
  add column if not exists subtype text,
  add column if not exists poster_type text,
  add column if not exists poster_constraints text,
  add column if not exists confidence text,
  add column if not exists deal_score int,
  add column if not exists analyzed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();
do $$ begin
  if not exists (select 1 from information_schema.columns where table_name='sublet_listings' and column_name='text_hash') then
    alter table sublet_listings add column text_hash text generated always as (md5(lower(regexp_replace(raw_text, '\s+', ' ', 'g')))) stored;
  end if;
end $$;
alter table sublet_seekers
  add column if not exists city text not null default 'Amsterdam',
  add column if not exists language text default 'en',
  add column if not exists last_pushed_at timestamptz,
  add column if not exists push_count int not null default 0,
  add column if not exists updated_at timestamptz not null default now();
alter table sublet_matches
  add column if not exists pushed_at timestamptz,
  add column if not exists replied_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();
alter table sublet_viewings add column if not exists updated_at timestamptz not null default now();
alter table sublet_fees
  add column if not exists payment_link text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
alter table sublet_fees drop constraint if exists sublet_fees_trigger_check;
alter table sublet_fees add constraint sublet_fees_trigger_check check (trigger in ('three_viewings_72h','move_in','signed','manual'));
alter table sublet_messages add column if not exists in_reply_to uuid references sublet_messages(id) on delete set null;
alter table sublet_scan_runs add column if not exists group_key text, add column if not exists cursor text;
alter table sublet_listings drop constraint if exists sublet_listings_link_validation_status_check;
alter table sublet_listings add constraint sublet_listings_link_validation_status_check
  check (link_validation_status in ('unvalidated','validated','inaccessible','needs_review'));
alter table sublet_scan_runs drop constraint if exists sublet_scan_runs_mode_check;
alter table sublet_scan_runs add constraint sublet_scan_runs_mode_check
  check (mode in ('feed','notifications','email','group_page','search','backfill','validation'));
alter table sublet_ops_state add column if not exists updated_at timestamptz not null default now();

-- ---------- indexes ----------
create index if not exists sublet_listings_status_idx on sublet_listings(status);
create index if not exists sublet_listings_seen_idx on sublet_listings(seen_at desc);
create index if not exists sublet_listings_kind_idx on sublet_listings(kind) where kind is null;   -- hàng đợi intent-analyze
create index if not exists sublet_listings_hash_idx on sublet_listings(text_hash);
create index if not exists sublet_listings_link_validation_idx
  on sublet_listings(link_validation_status, seen_at, id)
  where source in ('fb_feed','fb_notif');
create index if not exists sublet_listings_deal_idx on sublet_listings(deal_score desc) where status in ('new','matched');
create index if not exists sublet_listings_fp_idx on sublet_listings(poster_name, rent_eur, available_from) where kind='offering';

-- ---------- updated_at triggers ----------
do $$ declare t text;
begin
  foreach t in array array['sublet_groups','sublet_listings','sublet_seekers','sublet_matches','sublet_viewings','sublet_fees','sublet_ops_state'] loop
    execute format('drop trigger if exists %I_touch on %I', t, t);
    execute format('create trigger %I_touch before update on %I for each row execute function sublet_touch()', t, t);
  end loop;
end $$;

-- ---------- views cho skill (đọc 1 câu thay vì 5) ----------
create or replace view sublet_v_deal_queue as
  select l.*, g.name as group_name
  from sublet_listings l left join sublet_groups g on g.key = l.group_key
  where l.kind='offering' and l.status in ('new','matched') and l.canonical_id is null
    and coalesce(l.deal_score,0) >= 60 and l.scam_score < 60 and coalesce(l.confidence,'low') <> 'low'
    and coalesce(l.poster_type,'individual') <> 'agency'
  order by l.deal_score desc, l.seen_at desc;

create or replace view sublet_v_analyze_queue as
  select id, source, source_url, group_key, poster_name, posted_at, seen_at, raw_text
  from sublet_listings where kind is null order by seen_at limit 40;

create or replace view sublet_v_link_validation_queue as
  select id, source, source_url, group_key, poster_name, raw_text, seen_at,
         link_validation_status, link_validated_url, link_validated_at,
         link_validation_attempts, link_validation_note
  from sublet_listings
  where source in ('fb_feed','fb_notif')
    and source_url is not null
    and link_validation_status = 'unvalidated'
  order by seen_at, id;

create or replace view sublet_v_seekers_active as
  select * from sublet_seekers where status='active' and (move_in is null or move_in >= current_date - 14);

create or replace view sublet_v_today as
  select 'draft' as kind, m.id::text as ref, m.created_at as at, left(m.body,80) as summary
    from sublet_messages m where m.status='draft'
  union all
  select 'viewing', v.id::text, v.scheduled_at, 'viewing ' || coalesce(v.attendance,'')
    from sublet_viewings v where v.attendance='pending' and v.scheduled_at < now() + interval '36 hours'
  union all
  select 'fee', f.id::text, coalesce(f.sent_at, f.created_at), f.invoice_status || ' €' || f.amount_eur
    from sublet_fees f where f.invoice_status in ('draft','sent')
  union all
  select 'inbox', i.id::text, i.created_at, i.level || ': ' || i.title
    from sublet_inbox i where i.done_at is null
  order by at;

-- ---------- RLS ----------
do $$ declare t text;
begin
  foreach t in array array['sublet_groups','sublet_listings','sublet_seekers','sublet_matches','sublet_viewings','sublet_fees','sublet_messages','sublet_events','sublet_scan_runs','sublet_ops_state','sublet_inbox'] loop
    execute format('alter table %I enable row level security', t);
  end loop;
end $$;

-- ---------- RPC cho scripts/db.py (chỉ service_role) ----------
create or replace function sublet_exec(q text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  if q ~* '^\s*(select|with)\y' or q ~* '\yreturning\y' then
    execute 'select coalesce(jsonb_agg(t), ''[]''::jsonb) from (' || q || ') t' into r;
    return r;
  else
    execute q;
    return jsonb_build_object('ok', true);
  end if;
end $$;
revoke all on function sublet_exec(text) from public, anon, authenticated;
grant execute on function sublet_exec(text) to service_role;

-- ---------- seed groups (bỏ qua nếu key HOẶC url đã có) ----------
insert into sublet_groups (key, name, url, city, tier, allows_sublet, allows_agencies, notes)
select v.* from (values
 ('ams_housing_sublet','Amsterdam Housing Group: Studio, Room, House, Sublet','https://www.facebook.com/groups/706725492790937/','Amsterdam',1,'yes','unknown',null),
 ('ams_housing_rooms_sublets','Amsterdam Housing, Rooms, Apartments, Sublets','https://www.facebook.com/groups/251441185632701/','Amsterdam',1,'yes','unknown',null),
 ('ams_housing_apts_rooms_sublets','AMSTERDAM - Housing, Apartments, Rooms, Sublets','https://www.facebook.com/groups/3396846493712419/','Amsterdam',1,'yes','unknown',null),
 ('ams_housing_roommates','Amsterdam - housing and roommates','https://www.facebook.com/groups/amsterdam.housing.and.roommates/','Amsterdam',2,'unknown','unknown',null),
 ('ams_no_agencies','Amsterdam Apartment and Rooms for Rent No AGENCIES','https://www.facebook.com/groups/231203323708543/','Amsterdam',2,'unknown','no','Cấm agency. Chỉ đọc.'),
 ('ams_housing_no_sublets','AMSTERDAM - HOUSING (sublets and illegal rentals NOT allowed)','https://www.facebook.com/groups/396367587188451/','Amsterdam',3,'no','unknown','Bỏ qua cho sublet.'),
 ('housingrocket_ams','Amsterdam Apartments and Housing (NO SPAM) — Housing Rocket','https://housingrocket.com/group/amsterdam-apartments-and-housing','Amsterdam',2,'unknown','unknown','Housing Rocket sở hữu, 23k members')
) as v(key, name, url, city, tier, allows_sublet, allows_agencies, notes)
where not exists (select 1 from sublet_groups g where g.key = v.key or g.url = v.url);

-- ---------- group metrics (do Codex thêm 2026-09-15: kết quả verify từng group trong browser panel) ----------
create table if not exists sublet_group_metrics (
  id bigserial primary key,
  group_key text references sublet_groups(key) on delete cascade,
  checked_at timestamptz not null default now(),
  join_status text,                 -- joined | pending | not_joined | blocked | unknown
  member_count int,
  posts_per_day numeric,
  last_active_post_at timestamptz,
  last_active_label text,
  last_active_post_url text,
  membership_questions jsonb,       -- câu hỏi khi join (để bạn trả lời tay)
  activity_sample jsonb,            -- vài post gần nhất (title/snippet/url) làm mẫu
  source text,                      -- panel | web
  posts_14d_count int,
  posts_14d_complete boolean not null default false,
  posts_14d_checked_at timestamptz
);
create index if not exists sublet_group_metrics_group_idx on sublet_group_metrics(group_key, checked_at desc);
alter table sublet_group_metrics enable row level security;
alter table sublet_group_metrics add column if not exists posts_14d_count int;
alter table sublet_group_metrics add column if not exists posts_14d_complete boolean not null default false;
alter table sublet_group_metrics add column if not exists posts_14d_checked_at timestamptz;

-- ---------- metrics (1 dòng/ngày/metric; sublet-report ghi 18:00) ----------
create table if not exists sublet_metrics (
  id bigserial primary key,
  day date not null default current_date,
  workflow text not null check (workflow in ('know','capture','analyze','demand','match','outreach','inbox','viewing','fee','ops')),
  metric text not null,
  value numeric,
  target numeric,
  meta jsonb,
  computed_at timestamptz not null default now(),
  unique (day, workflow, metric)
);
alter table sublet_metrics enable row level security;

-- ---------- jobs: hàng đợi việc cho worker (1 cron tick = 1 job step có time-box) ----------
create table if not exists sublet_jobs (
  id bigserial primary key,
  job_type text not null check (job_type in ('scan','email','analyze','match','backfill','verify_group','followup','report','backup','groups_rank')),
  key text,                                  -- group_key / listing_id / null
  priority int not null default 50,          -- thấp = ưu tiên cao
  status text not null default 'queued' check (status in ('queued','running','done','failed','paused')),
  progress jsonb not null default '{}'::jsonb, -- backfill: {last_post_at, posts_done, scrolls}; verify: {checked}
  attempts int not null default 0,
  next_run_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists sublet_jobs_due_idx on sublet_jobs(priority, next_run_at) where status in ('queued','running');
create unique index if not exists sublet_jobs_open_uq on sublet_jobs(job_type, coalesce(key,'')) where status in ('queued','running','paused');
drop trigger if exists sublet_jobs_touch on sublet_jobs;
create trigger sublet_jobs_touch before update on sublet_jobs for each row execute function sublet_touch();
alter table sublet_jobs enable row level security;

-- ---------- audit: phân biệt validated thật (browser-verified) vs bulk-override chưa mở link ----------
create or replace view sublet_v_link_needs_reverification as
  select l.id, l.poster_name, l.group_key, l.source_url, l.link_validated_at,
         e.payload->>'link_resolution_method' as link_resolution_method,
         e.payload->>'note' as note
  from sublet_listings l
  join lateral (
    select payload from sublet_events e
    where e.entity_type='listing' and e.entity_id=l.id and e.event='link_validated'
    order by e.id desc limit 1
  ) e on true
  where l.link_validation_status = 'validated'
    and e.payload->>'link_resolution_method' = 'bulk_unverified_override'
  order by l.link_validated_at;

-- ---------- insight matching candidates (analyze-insights, NOT the official sublet_matches pipeline) ----------
-- Read-only signal from analyze-insights: candidate seeker<->offering pairs among
-- genuinely-validated + classified listings. Distinct from sublet_matches/sublet_seekers
-- (official outreach pipeline, out of active scope) so this never gets confused with a
-- committed match or drives outreach on its own.
create table if not exists sublet_insight_matches (
  id bigserial primary key,
  run_at timestamptz not null default now(),
  seeker_listing_id uuid not null references sublet_listings(id) on delete cascade,
  offering_listing_id uuid not null references sublet_listings(id) on delete cascade,
  confidence text not null check (confidence in ('high','medium','low','weak')),
  score int not null,
  reasons text[] not null default '{}',
  seeker_budget_eur int,
  offering_price_eur int,
  seeker_areas text[] not null default '{}',
  offering_areas text[] not null default '{}',
  created_at timestamptz not null default now(),
  unique (seeker_listing_id, offering_listing_id)
);
create index if not exists sublet_insight_matches_seeker_idx on sublet_insight_matches(seeker_listing_id);
create index if not exists sublet_insight_matches_offering_idx on sublet_insight_matches(offering_listing_id);
alter table sublet_insight_matches enable row level security;
-- upgrade: 'weak' tier added 2026-09-16 (seen_at-gated candidates with no
-- area/budget evidence either way -- Kien: don't drop a candidate just
-- because area/budget wasn't disclosed).
alter table sublet_insight_matches drop constraint if exists sublet_insight_matches_confidence_check;
alter table sublet_insight_matches add constraint sublet_insight_matches_confidence_check
  check (confidence in ('high','medium','low','weak'));

create or replace view sublet_v_insight_matches_report as
  select im.id, im.run_at, im.confidence, im.score, im.reasons,
         sl.poster_name as seeker_poster, sl.source_url as seeker_url,
         ol.poster_name as offering_poster, ol.source_url as offering_url,
         im.seeker_budget_eur, im.offering_price_eur, im.seeker_areas, im.offering_areas
  from sublet_insight_matches im
  join sublet_listings sl on sl.id = im.seeker_listing_id
  join sublet_listings ol on ol.id = im.offering_listing_id
  order by (case im.confidence when 'high' then 0 when 'medium' then 1 when 'low' then 2 else 3 end), im.score desc;

-- ---------- normalized per-listing profile (data-engineer, 2026-09-16) ----------
-- Join tới event insight_reviewed mới nhất của mỗi listing; luôn phản ánh
-- state hiện tại vì là view (không phải bảng vật lý), không cần checkpoint.
-- analyze-insights sở hữu ý nghĩa các cột suy ra (offer_or_need, pricing_tag,
-- start_date...); view này chỉ join lại cho dễ query.
-- drop trước vì đổi thứ tự cột (CREATE OR REPLACE VIEW không cho đổi thứ tự
-- cột hiện có, chỉ cho thêm cột mới ở cuối)
drop view if exists sublet_v_listing_profile;
create or replace view sublet_v_listing_profile as
  select
    l.id as listing_id,
    l.group_key,
    l.poster_name,
    l.source_url,
    l.seen_at,
    l.posted_at,
    l.link_validation_status,
    insight.payload->>'insight_kind_guess' as offer_or_need,
    insight.payload->>'insight_method' as insight_method,
    (insight.payload->>'offering_score')::int as offering_score,
    (insight.payload->>'seeking_score')::int as seeking_score,
    insight.payload->>'pricing_tag' as pricing_tag,
    (insight.payload->>'price_or_budget_eur')::int as budget_or_price_eur,
    norm.payload->>'start_date' as start_date,
    norm.payload->>'start_date_label' as start_date_label,
    norm.payload->>'end_date' as end_date,
    norm.payload->>'duration_label' as duration_label,
    insight.payload->'risk_flags' as risk_flags,
    insight.payload->>'duplicate_of' as duplicate_of,
    (insight.payload->>'repost_same_poster')::boolean as repost_same_poster,
    insight.payload->>'run_at' as insight_run_at,
    norm.payload->>'normalized_at' as normalized_at,
    l.raw_text
  from sublet_listings l
  -- offer_or_need/pricing/risk: owned by analyze-insights, event insight_reviewed
  left join lateral (
    select e.payload
    from sublet_events e
    where e.entity_type = 'listing' and e.entity_id = l.id and e.event = 'insight_reviewed'
    order by e.id desc
    limit 1
  ) insight on true
  -- start/end date, duration: owned by data-engineer, event listing_normalized
  left join lateral (
    select e.payload
    from sublet_events e
    where e.entity_type = 'listing' and e.entity_id = l.id and e.event = 'listing_normalized'
    order by e.id desc
    limit 1
  ) norm on true;

-- ---------- outreach queue view (outreach-prep, 2026-09-16) ----------
-- Gộp sublet_messages (draft/sent) + poster_name/source_url/profile_url để
-- Kien nhìn 1 lần ra đủ ai/gửi gì/mở link nào, không phải tự JOIN 3 bảng.
create or replace view sublet_v_outreach_queue as
  select
    sm.id as message_id,
    sm.status,
    sm.template,
    sm.body,
    sm.created_at,
    sm.sent_at,
    l.poster_name,
    l.source_url,
    l.offer_or_need,
    ctx.payload->'poster'->>'profile_url' as poster_profile_url,
    l.group_key
  from sublet_messages sm
  join sublet_v_listing_profile l on l.listing_id = sm.entity_id
  left join lateral (
    select e.payload
    from sublet_events e
    where e.entity_type = 'listing' and e.entity_id = l.listing_id and e.event = 'context_captured'
    order by e.id desc limit 1
  ) ctx on true
  where sm.channel = 'fb_dm'
  order by sm.status, sm.created_at;
