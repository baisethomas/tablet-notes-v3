export interface SupabaseSchema {
  tableName: string;
  sql: string;
}

export const supabaseSchema: SupabaseSchema[] = [
  {
    tableName: "sermons",
    sql: `-- Sermons table
create table sermons (
  id uuid primary key,
  user_id uuid references auth.users not null,
  title text not null,
  recording_date timestamp with time zone not null,
  service_type text not null,
  duration integer not null,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);`
  },
  {
    tableName: "transcriptions",
    sql: `-- Transcriptions table
create table transcriptions (
  id uuid primary key,
  sermon_id uuid references sermons on delete cascade not null,
  text text not null,
  segments jsonb,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);`
  },
  {
    tableName: "notes",
    sql: `-- Notes table
create table notes (
  id uuid primary key,
  sermon_id uuid references sermons on delete cascade not null,
  text text not null,
  timestamp integer not null,
  is_highlighted boolean default false,
  is_bookmarked boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);`
  },
  {
    tableName: "summaries",
    sql: `-- Summaries table
create table summaries (
  id uuid primary key,
  sermon_id uuid references sermons on delete cascade not null,
  text text not null,
  format text not null,
  retry_count integer default 0,
  status text not null,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);`
  },
  {
    tableName: "security policies",
    sql: `-- Row level security policies
alter table sermons enable row level security;
alter table transcriptions enable row level security;
alter table notes enable row level security;
alter table summaries enable row level security;

create policy "Users can view their own sermons"
  on sermons for select
  using (auth.uid() = user_id);

create policy "Users can insert their own sermons"
  on sermons for insert
  with check (auth.uid() = user_id);`
  }
];
