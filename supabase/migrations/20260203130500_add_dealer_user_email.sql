alter table crm.dealer_users
add column if not exists email text;

create or replace view public.crm_dealer_users as
select
    id,
    dealer_id,
    name,
    created_at,
    updated_at,
    deleted_at,
    server_updated_at,
    last_modified_by,
    first_name,
    last_name,
    phone,
    avatar_url,
    email
from crm.dealer_users;

create or replace function public.sync_users(payload jsonb)
returns jsonb
language plpgsql
security definer
as $$
declare
    item jsonb;
    result_record crm.dealer_users%rowtype;
    results jsonb := '[]'::jsonb;
    existing_id uuid;
    is_deleted boolean;
begin
    for item in select * from jsonb_array_elements(payload)
    loop
        -- Determine if this is a deletion
        is_deleted := (item->>'deleted_at') is not null;
        existing_id := null;

        -- Only check for duplicates by name if NOT deleting
        -- If deleting, we strictly target the ID.
        if not is_deleted then
            select id into existing_id
            from crm.dealer_users
            where dealer_id = (item->>'dealer_id')::uuid
              and lower(name) = lower(item->>'name')
              and deleted_at is null
              and id != (item->>'id')::uuid;
        end if;

        if existing_id is not null then
            -- A user with this name already exists (different ID) and we are not deleting
            -- Update the EXISTING user (merge strategy)
            update crm.dealer_users
            set name = item->>'name',
                first_name = item->>'first_name',
                last_name = item->>'last_name',
                email = item->>'email',
                phone = item->>'phone',
                avatar_url = item->>'avatar_url',
                updated_at = (item->>'updated_at')::timestamptz,
                deleted_at = (item->>'deleted_at')::timestamptz
            where id = existing_id
              and updated_at < (item->>'updated_at')::timestamptz
            returning * into result_record;

            if not found then
                select * into result_record from crm.dealer_users where id = existing_id;
            end if;
        else
            -- Normal upsert by ID (Insert or Update own ID)
            -- This handles deletions too (updating own ID with deleted_at)
            insert into crm.dealer_users (
                id,
                dealer_id,
                name,
                first_name,
                last_name,
                email,
                phone,
                avatar_url,
                created_at,
                updated_at,
                deleted_at
            )
            values (
                (item->>'id')::uuid,
                (item->>'dealer_id')::uuid,
                item->>'name',
                item->>'first_name',
                item->>'last_name',
                item->>'email',
                item->>'phone',
                item->>'avatar_url',
                (item->>'created_at')::timestamptz,
                (item->>'updated_at')::timestamptz,
                (item->>'deleted_at')::timestamptz
            )
            on conflict (id) do update
            set name = excluded.name,
                first_name = excluded.first_name,
                last_name = excluded.last_name,
                email = excluded.email,
                phone = excluded.phone,
                avatar_url = excluded.avatar_url,
                updated_at = excluded.updated_at,
                deleted_at = excluded.deleted_at
            where crm.dealer_users.updated_at < excluded.updated_at
            returning * into result_record;

            if not found then
                select * into result_record from crm.dealer_users where id = (item->>'id')::uuid;
            end if;
        end if;

        results := results || to_jsonb(result_record);
    end loop;
    return results;
end;
$$;
