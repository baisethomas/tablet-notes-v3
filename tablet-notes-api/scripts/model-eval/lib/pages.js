'use strict';

// Every row of a PostgREST query. One GET returns at most the server's row
// cap (1,000 by default), so a single request silently drops the rest of a
// large account. Pages are read until one comes back empty rather than until
// one comes back short: the server may cap a page below the size asked for.

async function allRows(get, query, { pageSize = 1000, order = 'id', maxPages = 1000 } = {}) {
  const rows = [];
  for (let page = 0; page < maxPages; page++) {
    const batch = await get(`${query}&order=${order}&limit=${pageSize}&offset=${rows.length}`);
    if (!Array.isArray(batch)) throw new Error('expected a JSON array of rows');
    if (!batch.length) return rows;
    rows.push(...batch);
  }
  throw new Error(`more than ${maxPages} pages; refusing to guess that the result is complete`);
}

module.exports = { allRows };
