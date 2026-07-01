-- ROLLBACK: restores the ORIGINAL definitions of the 9 listing-admin functions
-- (as they were BEFORE the 2026-07-01 mandatory-session-validation hardening).
-- Run this whole file against project haordpdxyyreliyzmire to revert.
-- Captured verbatim via pg_get_functiondef before the fix.

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

  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
  END IF;

  PERFORM 1 FROM public.listings WHERE id = p_listing_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Listing not found');
  END IF;

  INSERT INTO public.listing_admin_notes (listing_id, admin_user_id, note_text)
  VALUES (p_listing_id, p_admin_user_id, p_note_text)
  RETURNING 1 INTO v_rows;

  PERFORM public.log_admin_activity(
    p_admin_user_id, 'add_listing_note', 'listing', p_listing_id::text,
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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

  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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

CREATE OR REPLACE FUNCTION public.admin_moderate_listing(p_listing_id uuid, p_admin_user_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions', 'pg_temp'
AS $function$
DECLARE
  result JSON;
  listing_title TEXT;
BEGIN
  SELECT title INTO listing_title FROM public.listings WHERE id = p_listing_id;
  IF listing_title IS NULL THEN
    result := json_build_object('success', false, 'error', 'Listing not found');
    RETURN result;
  END IF;

  IF p_action = 'approve' THEN
    UPDATE public.listings SET moderation_status = 'approved', status = 'active', updated_at = NOW()
    WHERE id = p_listing_id;
    PERFORM log_user_activity((SELECT user_id FROM public.listings WHERE id = p_listing_id),
      'listing_approved', p_admin_user_id,
      json_build_object('listing_id', p_listing_id, 'listing_title', listing_title, 'action', 'approved')::jsonb);
    result := json_build_object('success', true, 'message', 'Listing approved successfully');
  ELSIF p_action = 'reject' THEN
    UPDATE public.listings SET moderation_status = 'rejected', status = 'inactive', updated_at = NOW()
    WHERE id = p_listing_id;
    PERFORM log_user_activity((SELECT user_id FROM public.listings WHERE id = p_listing_id),
      'listing_rejected', p_admin_user_id,
      json_build_object('listing_id', p_listing_id, 'listing_title', listing_title, 'action', 'rejected', 'reason', p_reason)::jsonb);
    result := json_build_object('success', true, 'message', 'Listing rejected successfully');
  ELSE
    result := json_build_object('success', false, 'error', 'Invalid action. Use approve or reject');
  END IF;
  RETURN result;
EXCEPTION
  WHEN OTHERS THEN
    result := json_build_object('success', false, 'error', SQLERRM);
    RETURN result;
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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

  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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
  IF p_session_token IS NOT NULL THEN
    PERFORM 1 FROM public.admin_sessions s
    WHERE s.session_token = p_session_token
      AND s.admin_user_id = p_admin_user_id
      AND s.is_active = true
      AND s.expires_at > now();
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired admin session');
    END IF;
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
