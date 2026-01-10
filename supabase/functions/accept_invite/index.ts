import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Note: This function might be called anonymously (new user signing up) 
        // OR authenticated (existing user joining).
        // We use the Service Role key to perform admin actions (creating membership).
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        )

        // We also use a regular client to get the Current User if they are logged in
        const authHeader = req.headers.get('Authorization')
        let currentUser = null
        if (authHeader) {
            const supabaseUser = createClient(
                Deno.env.get('SUPABASE_URL') ?? '',
                Deno.env.get('SUPABASE_ANON_KEY') ?? '',
                { global: { headers: { Authorization: authHeader } } }
            )
            const { data: { user } } = await supabaseUser.auth.getUser()
            currentUser = user
        }

        const { token } = await req.json()

        // 1. Validate Token
        const { data: invite, error: inviteError } = await supabaseAdmin
            .from('team_invitations')
            .select('*')
            .eq('token', token)
            .gt('expires_at', new Date().toISOString()) // Check expiry
            .single()

        if (inviteError || !invite) throw new Error("Invalid or expired invitation")

        // 2. Identify Target User
        // If the user is logged in, use their ID.
        // If NOT logged in, we expect them to have just Signed Up and passed the Auth Header, 
        // OR they are accepting and we need to know who they are.
        // The safest flow: User signs up / logs in -> Calls accept_invite with token.
        if (!currentUser) throw new Error("Please sign in or sign up to accept the invitation")

        const strictEmailMatch = (Deno.env.get("INVITE_STRICT_EMAIL_MATCH") ?? "true") === "true"
        if (
            strictEmailMatch &&
            invite.email &&
            currentUser.email &&
            invite.email.toLowerCase() !== currentUser.email.toLowerCase()
        ) {
            throw new Error("Email mismatch. Please sign in with the invited address.")
        }

        // 3. Create Membership
        const { error: memberError } = await supabaseAdmin
            .from('dealer_team_members')
            .insert({
                organization_id: invite.organization_id,
                user_id: currentUser.id,
                role: invite.role,
                status: 'active'
            })

        if (memberError) {
            // Handle duplicate join
            if (memberError.code === '23505') throw new Error("You are already a member of this team")
            throw memberError
        }

        // 4. Delete Invitation (Consume it)
        await supabaseAdmin.from('team_invitations').delete().eq('id', invite.id)

        // 5. Audit Log
        await supabaseAdmin.from('audit_logs').insert({
            organization_id: invite.organization_id,
            actor_id: currentUser.id,
            action: 'JOIN_TEAM',
            details: { invite_id: invite.id, role: invite.role }
        })

        return new Response(
            JSON.stringify({
                success: true,
                organization_id: invite.organization_id,
                role: invite.role,
                message: "Welcome to the team!",
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" } }
        )

    } catch (error) {
        return new Response(JSON.stringify({ error: error.message }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
            status: 400,
        })
    }
})
