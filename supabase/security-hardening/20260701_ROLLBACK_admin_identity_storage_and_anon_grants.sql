CREATE OR REPLACE FUNCTION public.admin_add_listing_note(p_listing_id uuid, p_admin_user_id uuid, p_note_text text, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  IF p_note_text IS NULL OR length(trim(p_note_text)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Note text is required');
  END IF;

  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  PERFORM 1 FROM public.listings WHERE id = p_listing_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  INSERT INTO public.listing_admin_notes (listing_id, admin_user_id, note_text)
  VALUES (p_listing_id, p_admin_user_id, p_note_text) RETURNING 1 INTO v_rows;

  PERFORM public.log_admin_activity(p_admin_user_id, 'add_listing_note', 'listing', p_listing_id::text,
    jsonb_build_object('note_length', char_length(p_note_text)));
  RETURN jsonb_build_object('success', true, 'message', 'Note added');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_archive_listing(p_listing_id uuid, p_admin_user_id uuid, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  UPDATE public.listings SET status = 'inactive', updated_at = now()
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'archive_listing', 'listing', p_listing_id::text);
  RETURN jsonb_build_object('success', true, 'message', 'Listing archived');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_mark_listing_sold(p_listing_id uuid, p_admin_user_id uuid, p_sold_price numeric DEFAULT NULL::numeric, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  UPDATE public.listings SET status = 'sold', sold_price = p_sold_price, sold_at = now(), updated_at = now()
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'mark_listing_sold', 'listing', p_listing_id::text,
    jsonb_build_object('sold_price', p_sold_price));
  RETURN jsonb_build_object('success', true, 'message', 'Listing marked as sold');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_moderate_listing(p_listing_id uuid, p_admin_user_id uuid, p_action text, p_reason text DEFAULT NULL::text, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_new_status text;
  v_rows integer;
BEGIN
  IF p_action = 'approve' THEN
    v_new_status := 'approved';
  ELSIF p_action = 'reject' THEN
    v_new_status := 'rejected';
  ELSE
    RAISE EXCEPTION 'Invalid action: %', p_action;
  END IF;

  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  PERFORM 1 FROM public.admin_users au
  WHERE au.id = p_admin_user_id AND au.is_active = true
    AND au.role IN ('admin','moderator','super_admin');
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  UPDATE public.listings
  SET moderation_status = v_new_status, moderation_reason = p_reason, moderated_at = now(),
      moderated_by = p_admin_user_id,
      status = CASE WHEN v_new_status = 'approved' THEN 'active' ELSE status END,
      is_draft = CASE WHEN v_new_status = 'approved' THEN false ELSE is_draft END
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  IF v_new_status = 'rejected' THEN
    UPDATE public.listings SET status = CASE WHEN status = 'active' THEN 'inactive' ELSE status END
    WHERE id = p_listing_id;
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'moderate_listing', 'listing', p_listing_id::text,
    jsonb_build_object('status', v_new_status, 'reason', p_reason));
  RETURN jsonb_build_object('success', true, 'message', 'Listing updated');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_restore_listing(p_listing_id uuid, p_admin_user_id uuid, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  UPDATE public.listings SET status = 'active', updated_at = now()
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'restore_listing', 'listing', p_listing_id::text);
  RETURN jsonb_build_object('success', true, 'message', 'Listing restored to active');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_send_message_to_seller(p_listing_id uuid, p_admin_user_id uuid, p_message_content text, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_listing_owner_id uuid;
  v_message_id uuid;
BEGIN
  IF p_message_content IS NULL OR length(trim(p_message_content)) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Message content is required');
  END IF;

  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  SELECT user_id INTO v_listing_owner_id FROM public.listings WHERE id = p_listing_id;
  IF v_listing_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  INSERT INTO public.messages (listing_id, sender_id, receiver_id, content)
  VALUES (p_listing_id, p_admin_user_id, v_listing_owner_id, p_message_content)
  RETURNING id INTO v_message_id;

  PERFORM public.log_admin_activity(p_admin_user_id, 'send_message_to_seller', 'listing', p_listing_id::text,
    jsonb_build_object('message_id', v_message_id, 'receiver_id', v_listing_owner_id, 'content_length', char_length(p_message_content)));
  RETURN jsonb_build_object('success', true, 'message', 'Message sent to seller', 'message_id', v_message_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_unmark_listing_sold(p_listing_id uuid, p_admin_user_id uuid, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  UPDATE public.listings SET status = 'active', sold_price = NULL, sold_at = NULL, updated_at = now()
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'unmark_listing_sold', 'listing', p_listing_id::text);
  RETURN jsonb_build_object('success', true, 'message', 'Listing sale reverted');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_listing_fields(p_listing_id uuid, p_admin_user_id uuid, p_title text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_price numeric DEFAULT NULL::numeric, p_location text DEFAULT NULL::text, p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  UPDATE public.listings
  SET title = COALESCE(p_title, title), description = COALESCE(p_description, description),
      price = COALESCE(p_price, price), location = COALESCE(p_location, location), updated_at = now()
  WHERE id = p_listing_id RETURNING 1 INTO v_rows;
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'update_listing_fields', 'listing', p_listing_id::text,
    jsonb_build_object('title_updated', p_title IS NOT NULL, 'description_updated', p_description IS NOT NULL,
      'price_updated', p_price IS NOT NULL, 'location_updated', p_location IS NOT NULL));
  RETURN jsonb_build_object('success', true, 'message', 'Listing updated');
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_update_listing_images(p_listing_id uuid, p_admin_user_id uuid, p_cover_image_id uuid DEFAULT NULL::uuid, p_ordered_ids uuid[] DEFAULT NULL::uuid[], p_session_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rows int;
  v_id uuid;
  v_pos int := 0;
BEGIN
  PERFORM 1 FROM public.admin_sessions s
  WHERE s.session_token = p_session_token AND s.admin_user_id = p_admin_user_id
    AND s.is_active = true AND s.expires_at > now();
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
  END IF;

  PERFORM 1 FROM public.listings WHERE id = p_listing_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  IF p_cover_image_id IS NOT NULL THEN
    PERFORM 1 FROM public.listing_images WHERE id = p_cover_image_id AND listing_id = p_listing_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Cover image does not belong to listing');
    END IF;
    UPDATE public.listing_images SET is_cover = (id = p_cover_image_id) WHERE listing_id = p_listing_id;
  END IF;

  IF p_ordered_ids IS NOT NULL THEN
    v_pos := 0;
    FOREACH v_id IN ARRAY p_ordered_ids LOOP
      UPDATE public.listing_images SET sort_order = v_pos WHERE id = v_id AND listing_id = p_listing_id;
      v_pos := v_pos + 1;
    END LOOP;
  END IF;

  PERFORM public.log_admin_activity(p_admin_user_id, 'update_listing_images', 'listing', p_listing_id::text,
    jsonb_build_object('cover_updated', p_cover_image_id IS NOT NULL, 'reordered', p_ordered_ids IS NOT NULL,
      'count', COALESCE(array_length(p_ordered_ids, 1), 0)));
  RETURN jsonb_build_object('success', true, 'message', 'Images updated');
END;
$function$;

DROP POLICY IF EXISTS "Authenticated users can select own avatars" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can select own car reports" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can select own listing images" ON storage.objects;

CREATE POLICY "Avatar images are publicly accessible"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'avatars');

CREATE POLICY "Public read access for car-reports"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'car-reports');

CREATE POLICY "Listing images are publicly accessible"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'listing-images');

CREATE POLICY "Public read for listing-images"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'listing-images');

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT *
        FROM (
            VALUES
                ('public', 'app_feedback_requests'),
                ('public', 'app_feedback_votes'),
                ('public', 'app_feedback_views'),
                ('public', 'ai_insight_reports'),
                ('public', 'monthly_report_deliveries'),
                ('public', 'monthly_report_preferences'),
                ('public', 'organization_deal_desk_settings'),
                ('public', 'organization_holding_cost_settings'),
                ('app_private', 'admin_bot_events'),
                ('app_private', 'admin_bot_alert_deliveries')
        ) AS t(schema_name, table_name)
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', 'No direct API access', r.schema_name, r.table_name);
    END LOOP;
END $$;

GRANT EXECUTE ON FUNCTION public.assert_crm_access(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.assert_crm_permission(uuid, text[]) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_dealer_referral(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_organization(text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_vehicle_share_link(uuid, uuid, text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_can_access(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_effective_any_permission(uuid, text[]) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_effective_permission(uuid, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_deal_desk_read_access(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_deal_desk_write_access(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_personal_organization() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_organizations() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_permissions(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_role(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_or_create_dealer_referral_code(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_referral_stats() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_team_members_secure() TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_team_members_secure(uuid) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.has_permission(uuid, uuid, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_referral_reward(uuid, text, text, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_team_invite_access(uuid, uuid, public.app_role, jsonb) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_team_member_access(uuid, uuid, public.app_role, jsonb) TO PUBLIC;

NOTIFY pgrst, 'reload schema';
