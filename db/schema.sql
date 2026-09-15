-- sublet-skills schema (Supabase / Postgres). Prefix sublet_. RLS bật, không policy: chỉ service role (MCP) đọc/ghi.

create table if not exists sublet_listings (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('fb_feed','fb_notif','fb_email','form','manual')),
  source_url text unique,
  group_key text,
  poster_name text,
  posted_at timestamptz,
  seen_at timestamptz not null default now(),
  raw_text text not null,
  kind text check (kind in ('offering','seeking','other')),
  area text,
  room_type text check (room_type in ('room','studio','apartment','other')),
  rent_eur int,
  deposit_eur int,
  bills_included text,
  available_from date,
  available_to date,
  min_term_days int,
  furnished boolean,
  registration_allowed text check (registration_allowed in ('yes','no','unknown')) default 'unknown',
  sublet_permission text check (sublet_permission in ('yes','no','unknown')) default 'unknown',
  max_people int,
  scam_score int not null default 0,
  scam_flags text[] not null default '{}',
  status text not null default 'new' check (status in ('new','contacted','accepted','declined','matched','viewing','filled','dead')),
  contacted_at timestamptz,
  accepted_at timestamptz,
  filled_at timestamptz,
  offer_link text,
  notes text
);
create index if not exists sublet_listings_status_idx on sublet_listings(status);
create index if not exists sublet_listings_seen_idx on sublet_listings(seen_at desc);

create table if not exists sublet_seekers (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('form','whatsapp','fb_seeking','manual')),
  source_url text,
  name text,
  contact text,
  contact_consent boolean not null default false,
  move_in date,
  move_out date,
  flex_days int default 7,
  budget_eur int,
  areas text[] not null default '{}',
  people int default 1,
  registration_need boolean default false,
  pets boolean default false,
  occupation text,
  viewing_availability text,
  status text not null default 'active' check (status in ('active','matched','viewing','housed','inactive')),
  created_at timestamptz not null default now(),
  notes text
);

create table if not exists sublet_matches (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references sublet_listings(id) on delete cascade,
  seeker_id uuid not null references sublet_seekers(id) on delete cascade,
  score int not null,
  reasons text,
  risk_flags text[] not null default '{}',
  status text not null default 'proposed' check (status in ('proposed','pushed','replied','shortlisted','viewing','rejected','signed')),
  created_at timestamptz not null default now(),
  unique (listing_id, seeker_id)
);

create table if not exists sublet_viewings (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references sublet_matches(id) on delete cascade,
  scheduled_at timestamptz,
  confirmed boolean not null default false,
  attendance text check (attendance in ('pending','showed','no_show','cancelled')) default 'pending',
  landlord_feedback text,
  created_at timestamptz not null default now()
);

create table if not exists sublet_fees (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references sublet_listings(id) on delete cascade,
  trigger text not null check (trigger in ('three_viewings_72h','signed','manual')),
  amount_eur int not null,
  invoice_status text not null default 'draft' check (invoice_status in ('draft','sent','paid','waived','disputed')),
  sent_at timestamptz,
  paid_at timestamptz,
  notes text
);

create table if not exists sublet_messages (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('listing','seeker','match','viewing')),
  entity_id uuid not null,
  direction text not null check (direction in ('out','in')),
  channel text not null check (channel in ('fb_dm','whatsapp','email','telegram','other')),
  template text,
  body text not null,
  status text not null default 'draft' check (status in ('draft','approved','sent','received')),
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

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

create table if not exists sublet_scan_runs (
  id bigserial primary key,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  mode text not null check (mode in ('feed','notifications','email','group_page','search')),
  page_loads int not null default 0,
  posts_seen int not null default 0,
  new_listings int not null default 0,
  stopped_reason text
);

alter table sublet_listings enable row level security;
alter table sublet_seekers enable row level security;
alter table sublet_matches enable row level security;
alter table sublet_viewings enable row level security;
alter table sublet_fees enable row level security;
alter table sublet_messages enable row level security;
alter table sublet_events enable row level security;
alter table sublet_scan_runs enable row level security;

-- v2: groups registry + scan cursor
create table if not exists sublet_groups (
  key text primary key,
  name text not null,
  url text unique,
  city text,
  tier int check (tier in (1,2,3)),
  is_private boolean,
  member_count int,
  allows_sublet text check (allows_sublet in ('yes','no','unknown')) default 'unknown',
  allows_agencies text check (allows_agencies in ('yes','no','unknown')) default 'unknown',
  joined boolean not null default false,
  notif_all_posts boolean not null default false,
  offering_7d int default 0,
  last_post_seen_at timestamptz,
  last_scanned_at timestamptz,
  last_ranked_at timestamptz,
  discovered_at timestamptz not null default now(),
  notes text
);
alter table sublet_groups enable row level security;
alter table sublet_scan_runs add column if not exists cursor text;
