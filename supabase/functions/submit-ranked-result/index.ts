import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4';

type RankedResult = 'white' | 'black' | 'draw' | 'aborted';
type ResultAlias = RankedResult | 'w' | 'b' | 'd';

type ResultBody = {
  white_id?: string;
  black_id?: string;
  whiteId?: string;
  blackId?: string;
  result: ResultAlias;
  result_reason?: string;
  pgn?: string;
  final_fen?: string;
  time_control?: string;
};

const normalizeResult = (result: ResultAlias): RankedResult | null => {
  if (result === 'w') return 'white';
  if (result === 'b') return 'black';
  if (result === 'd') return 'draw';
  if (['white', 'black', 'draw', 'aborted'].includes(result)) return result as RankedResult;
  return null;
};

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return Response.json({ error: 'Method not allowed' }, {
      status: 405,
      headers: corsHeaders,
    });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return Response.json({ error: 'Supabase environment is not configured' }, {
      status: 500,
      headers: corsHeaders,
    });
  }

  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await userClient.auth.getUser();
  if (userError || !user) {
    return Response.json({ error: 'Unauthorized' }, {
      status: 401,
      headers: corsHeaders,
    });
  }

  const body = await req.json().catch(() => null) as ResultBody | null;
  const whiteId = body?.white_id ?? body?.whiteId;
  const blackId = body?.black_id ?? body?.blackId;
  const result = body?.result ? normalizeResult(body.result) : null;

  if (!body || !whiteId || !blackId || !result) {
    return Response.json({ error: 'Missing result fields' }, {
      status: 400,
      headers: corsHeaders,
    });
  }

  if (whiteId === blackId) {
    return Response.json({ error: 'A ranked game requires two different players' }, {
      status: 400,
      headers: corsHeaders,
    });
  }

  if (user.id !== whiteId && user.id !== blackId) {
    return Response.json({ error: 'Only a participant can submit this result' }, {
      status: 403,
      headers: corsHeaders,
    });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data, error } = await admin.rpc('record_ranked_result', {
    p_white_id: whiteId,
    p_black_id: blackId,
    p_result: result,
    p_result_reason: body.result_reason ?? 'normal',
    p_pgn: body.pgn ?? null,
    p_final_fen: body.final_fen ?? null,
    p_time_control: body.time_control ?? null,
  });

  if (error) {
    return Response.json({ error: error.message }, {
      status: 500,
      headers: corsHeaders,
    });
  }

  return Response.json({ success: true, ...data }, { headers: corsHeaders });
});
