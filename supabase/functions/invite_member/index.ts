import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { email, role } = await req.json()
    
    // 1. Get User
    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user) throw new Error("Unauthorized")

    // 2. Identify Organization (Context: User is Member of Org)
    // We assume the inviter is acting on behalf of the org they are effectively "logged into".
    // For now, since 1 User = 1 Org (mostly), we fetch the org where they are an Owner/Admin.
    // In a multi-org future, 'organization_id' should be passed in the body.
    const { data: membership, error: memError } = await supabaseClient
      .from('dealer_team_members')
      .select('organization_id')
      .eq('user_id', user.id)
      .single()

    if (memError || !membership) throw new Error("Organization membership not found")

    // 3. Verify Permission (The Gatekeeper)
    const { data: canManage } = await supabaseClient.rpc('has_permission', {
       _user_id: user.id,
       _org_id: membership.organization_id,
       _perm_key: 'MANAGE_TEAM'
    })

    if (!canManage) throw new Error("Forbidden: insufficient permissions")

    // 4. Create Invitation
    const token = crypto.randomUUID()
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24h

    const { error: inviteError } = await supabaseClient
      .from('team_invitations')
      .insert({
        organization_id: membership.organization_id,
        email,
        role,
        token,
        created_by: user.id,
        expires_at: expiresAt
      })

    if (inviteError) throw inviteError

    // 5. Audit Log
    await supabaseClient.from('audit_logs').insert({
      organization_id: membership.organization_id,
      actor_id: user.id,
      action: 'INVITE_MEMBER',
      details: { email, role, token_id: token } // Log token ID not value? Value needed for link though.
    })

    return new Response(
      JSON.stringify({ success: true, token, message: "Invitation created" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 400,
    })
  }
})
