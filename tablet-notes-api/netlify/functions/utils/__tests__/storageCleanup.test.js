const test = require('node:test');
const assert = require('node:assert/strict');
const { cleanupOrphanAudioUpload } = require('../storageCleanup');

const silentLogger = { info() {}, warn() {}, error() {} };

function fakeSupabase({ referencingSermonIds = [] } = {}) {
  const removedPaths = [];
  return {
    removedPaths,
    from(table) {
      assert.equal(table, 'sermons');
      return {
        select() {
          return {
            eq() {
              return {
                async limit() {
                  return {
                    data: referencingSermonIds.map(id => ({ id })),
                    error: null
                  };
                }
              };
            }
          };
        }
      };
    },
    storage: {
      from() {
        return {
          async remove(paths) {
            removedPaths.push(...paths);
            return { error: null };
          }
        };
      }
    }
  };
}

test('removes an unreferenced upload under the user prefix', async () => {
  const supabase = fakeSupabase();

  const removed = await cleanupOrphanAudioUpload({
    supabase,
    audioFilePath: 'user-1/abc.m4a',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.equal(removed, true);
  assert.deepEqual(supabase.removedPaths, ['user-1/abc.m4a']);
});

test('refuses to delete a path outside the user prefix', async () => {
  const supabase = fakeSupabase();

  const removed = await cleanupOrphanAudioUpload({
    supabase,
    audioFilePath: 'other-user/abc.m4a',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.equal(removed, false);
  assert.deepEqual(supabase.removedPaths, []);
});

test('refuses paths containing traversal segments', async () => {
  const supabase = fakeSupabase();

  const removed = await cleanupOrphanAudioUpload({
    supabase,
    audioFilePath: 'user-1/../other-user/abc.m4a',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.equal(removed, false);
  assert.deepEqual(supabase.removedPaths, []);
});

test('refuses to delete a path referenced by an existing sermon row', async () => {
  const supabase = fakeSupabase({ referencingSermonIds: ['sermon-1'] });

  const removed = await cleanupOrphanAudioUpload({
    supabase,
    audioFilePath: 'user-1/abc.m4a',
    userId: 'user-1',
    logger: silentLogger
  });

  assert.equal(removed, false);
  assert.deepEqual(supabase.removedPaths, []);
});

test('does nothing when no path is provided', async () => {
  const supabase = fakeSupabase();

  const removed = await cleanupOrphanAudioUpload({
    supabase,
    audioFilePath: null,
    userId: 'user-1',
    logger: silentLogger
  });

  assert.equal(removed, false);
  assert.deepEqual(supabase.removedPaths, []);
});
