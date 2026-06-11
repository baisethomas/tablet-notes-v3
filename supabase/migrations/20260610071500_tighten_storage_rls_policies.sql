-- TAB-25: Tighten storage RLS policies
--
-- Problem: storage.objects had overlapping policies. In addition to the
-- correct per-user policies (scoped to auth.uid() = first path folder),
-- there were broad bucket-wide policies that let:
--   * ANY authenticated user read/update/delete ANY user's sermon audio
--     in the `sermon-audio` bucket (cross-tenant data leak), and
--   * anonymous (unauthenticated) clients upload arbitrary files to the
--     legacy `audio-files` bucket (abuse/storage-cost vector).
--
-- Since policies are OR'd together, the broad policies silently defeated
-- the per-user ones. This migration drops the broad policies and keeps
-- the per-user policies as the only access path.
--
-- Verified before applying (2026-06-10):
--   * All 876 objects in `sermon-audio` live under {userId}/... folders
--     that match real auth.users rows, so per-user policies fully cover
--     every legitimate access.
--   * App uploads go through service-role signed upload URLs (not RLS),
--     and app downloads use the owner's JWT against {userId}/{filename}
--     paths, so no app flow depends on the broad policies.

-- Cross-tenant access to sermon-audio (read/update/delete/insert bucket-wide)
drop policy if exists "Authenticated users can read sermon audio" on storage.objects;
drop policy if exists "Authenticated users can upload sermon audio" on storage.objects;
drop policy if exists "Authenticated users can update sermon audio" on storage.objects;
drop policy if exists "Authenticated users can delete sermon audio" on storage.objects;

-- Anonymous uploads to the legacy audio-files bucket
drop policy if exists "Allow public uploads to audio-files" on storage.objects;

-- Remaining (kept) policies, for reference:
--   "Users can upload their own audio files"      (sermon-audio, INSERT, owner folder)
--   "Users can view their own audio files"        (sermon-audio, SELECT, owner folder)
--   "Users can update their own audio files"      (sermon-audio, UPDATE, owner folder)
--   "Users can delete their own audio files"      (sermon-audio, DELETE, owner folder)
--   "Users can upload own audio files 1o4vxz4_0"  (audio-files,  INSERT, owner folder)
--   "Users can view own audio files 1o4vxz4_0"    (audio-files,  SELECT, owner folder)
--   "Users can update own audio files 1o4vxz4_0"  (audio-files,  UPDATE, owner folder)
--   "Users can delete own audio files 1o4vxz4_0"  (audio-files,  DELETE, owner folder)
