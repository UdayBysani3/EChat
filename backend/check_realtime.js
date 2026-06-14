const { Client } = require('pg');

async function run() {
  const client = new Client({
    connectionString: 'postgresql://postgres:Chandrasekharngolla@db.mcvfkikbmbgtzlmgwokl.supabase.co:5432/postgres',
    ssl: { rejectUnauthorized: false }
  });

  try {
    await client.connect();
    console.log('Connected to database.');

    // Query publication tables
    const res = await client.query(`
      SELECT schemaname, tablename 
      FROM pg_publication_tables 
      WHERE pubname = 'supabase_realtime';
    `);
    
    console.log('Current tables in supabase_realtime publication:');
    res.rows.forEach(row => {
      console.log(` - ${row.schemaname}.${row.tablename}`);
    });

    // Make sure call_logs has replica identity FULL
    const replicaRes = await client.query(`
      SELECT relreplident 
      FROM pg_class 
      WHERE relname = 'call_logs';
    `);
    if (replicaRes.rows.length > 0) {
      const ident = replicaRes.rows[0].relreplident;
      console.log(`call_logs replica identity code: '${ident}' (d=default, n=nothing, f=full, i=index)`);
    }

    // Explicitly add call_logs to publication if not present, and ensure replica identity full
    console.log('Ensuring call_logs is added to supabase_realtime publication...');
    await client.query(`
      ALTER PUBLICATION supabase_realtime ADD TABLE IF NOT EXISTS public.call_logs;
    `).catch(async (e) => {
      // Fallback if ADD TABLE IF NOT EXISTS is not supported in this pg version
      console.log('Retrying standard add...');
      await client.query(`
        ALTER PUBLICATION supabase_realtime ADD TABLE public.call_logs;
      `).catch(err => console.log('Re-add notice:', err.message));
    });

    await client.query(`
      ALTER TABLE public.call_logs REPLICA IDENTITY FULL;
    `);
    console.log('Completed replication identity check.');

  } catch (err) {
    console.error('Check failed:', err);
  } finally {
    await client.end();
  }
}

run();
