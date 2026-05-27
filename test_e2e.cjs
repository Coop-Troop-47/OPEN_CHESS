const { createClient } = require('/tmp/supabase-test/node_modules/@supabase/supabase-js');

const SUPABASE_URL = 'https://pwnblygocbbizpbscqig.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3bmJseWdvY2JiaXpwYnNjcWlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4MDE0MzIsImV4cCI6MjA5NTM3NzQzMn0.HbtM3SjKLaVpUDKHB44NxOBQbRH5cLfwwngEABPVAco';

(async () => {
  const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  let authEventFired = false;

  console.log('1. Registering onAuthStateChange listener...');
  sb.auth.onAuthStateChange(async (event, session) => {
    console.log(`\n>>> onAuthStateChange fired! event="${event}", session=${session ? 'EXISTS' : 'NULL'}`);
    authEventFired = true;
    if (session) {
      const uid = session.user.id;
      console.log('>>> Loading profile...');
      for (let i = 1; i <= 8; i++) {
        await new Promise(r => setTimeout(r, 500));
        const { data, error } = await sb.from('profiles').select('id,username').eq('id', uid).single();
        if (data) { console.log(`>>> Profile loaded on attempt ${i}:`, data); break; }
        console.log(`>>> Attempt ${i}: not found (${error?.code})`);
        if (i === 8) console.log('>>> Profile never found after 4s!');
      }
    }
  });

  const testEmail = `e2e_${Date.now()}@example.com`;
  const testUsername = `u${Date.now().toString().slice(-7)}`;

  console.log(`\n2. Calling signUp (email=${testEmail}, username=${testUsername})...`);
  const t0 = Date.now();
  const { data, error } = await sb.auth.signUp({
    email: testEmail,
    password: 'TestPassword123!',
    options: { data: { username: testUsername } },
  });
  const elapsed = Date.now() - t0;

  console.log(`\n3. signUp returned in ${elapsed}ms`);
  console.log('   error:', error ? JSON.stringify(error) : null);
  console.log('   user.id:', data?.user?.id);
  console.log('   user.identities.length:', data?.user?.identities?.length);
  console.log('   session:', data?.session ? 'EXISTS' : 'NULL');

  if (!data?.session) {
    console.log('\n❌ NO SESSION — this is the bug.');
    if (data?.user?.identities?.length === 0) {
      console.log('   Email already registered (ghost signup).');
    } else {
      console.log('   Email confirmation is ON in Supabase Dashboard → Auth → Email must be turned off.');
    }
  } else {
    console.log('\n✅ Session returned. Waiting 3s for onAuthStateChange...');
    await new Promise(r => setTimeout(r, 3000));
    if (!authEventFired) {
      console.log('❌ onAuthStateChange NEVER fired — this is the bug.');
    } else {
      console.log('✅ onAuthStateChange fired correctly.');
    }
  }

  process.exit(0);
})();
