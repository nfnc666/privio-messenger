import pg from 'pg';

// Reads every value in every column of every table and looks for phrases you
// just typed into a real client. The server is supposed to hold ciphertext; a
// hit here means it holds something it can read.
//
//   node tools/db-canary-sweep.mjs KANARIE-DIREKT-8801 KANARIE-GRUPPE-8803
//
// Two things make the difference between a measurement and a reassuring
// nothing:
//
//   1. Send from a real client, not through the API. The sealing happens on the
//      device; a test that posts plaintext into the `content` column will find
//      it there and be right to.
//   2. Include a positive control — a phrase that *should* be found, such as the
//      username. "No needle found" from a sweeper that cannot find anything
//      proves nothing at all.
//
// Have the recipient offline while you send, too: an envelope is deleted the
// moment it is acknowledged, and an empty table is not evidence.
const pool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ?? 'postgres://postgres@localhost:5432/privio',
});
const needles = process.argv.slice(2);

const { rows: cols } = await pool.query(
  `SELECT table_name, column_name FROM information_schema.columns
   WHERE table_schema = 'public' ORDER BY table_name, ordinal_position`,
);

const byTable = new Map();
for (const c of cols) {
  if (!byTable.has(c.table_name)) byTable.set(c.table_name, []);
  byTable.get(c.table_name).push(c.column_name);
}

const hits = [];
let scanned = 0;
for (const [table, columns] of byTable) {
  const { rows } = await pool.query(`SELECT * FROM ${table}`);
  for (const row of rows) {
    for (const col of columns) {
      const v = row[col];
      if (v == null) continue;
      const asText = Buffer.isBuffer(v)
        ? [v.toString('utf8'), v.toString('latin1'), v.toString('base64')].join(' ')
        : typeof v === 'object'
          ? JSON.stringify(v)
          : String(v);
      scanned += 1;
      for (const n of needles) {
        if (asText.includes(n)) hits.push(`${table}.${col}  <-  ${n}`);
      }
    }
  }
}

console.log(`scanned ${scanned} values across ${byTable.size} tables`);
console.log(hits.length ? 'FOUND:\n' + [...new Set(hits)].join('\n') : 'no needle found in any column');
await pool.end();
