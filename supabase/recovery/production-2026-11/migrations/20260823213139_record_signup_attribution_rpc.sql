-- Attribution write path for the founders launch.
--
-- Why an RPC and not an anon INSERT policy: signup_attribution is the table the
-- founders spend is judged on. An open "WITH CHECK (true)" policy (the shape of
-- anon_insert_leads) would let anyone holding the public anon key fabricate
-- signups and conversions. This function is the only anon write path, it
-- requires a family_id that actually exists, and it is first-touch only.
--
-- NOTE: signup_attribution has no utm_term column; utm_term is captured on
-- page_views only.

create or replace function public.record_signup_attribution(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family uuid;
  v_id     uuid;
begin
  begin
    v_family := nullif(p_payload->>'family_id','')::uuid;
  exception when others then
    return jsonb_build_object('ok', false, 'reason', 'bad family_id');
  end;

  if v_family is null then
    return jsonb_build_object('ok', false, 'reason', 'family_id required');
  end if;

  -- Forged/random uuids get nothing.
  if not exists (select 1 from public.families where id = v_family) then
    return jsonb_build_object('ok', false, 'reason', 'unknown family');
  end if;

  insert into public.signup_attribution
    (family_id, session_id, utm_source, utm_medium, utm_campaign, utm_content,
     referrer, landing_page)
  values (
    v_family,
    left(nullif(p_payload->>'session_id',''),   120),
    left(nullif(p_payload->>'utm_source',''),   120),
    left(nullif(p_payload->>'utm_medium',''),   120),
    left(nullif(p_payload->>'utm_campaign',''), 120),
    left(nullif(p_payload->>'utm_content',''),  120),
    left(nullif(p_payload->>'referrer',''),     500),
    left(nullif(p_payload->>'landing_page',''), 500)
  )
  on conflict (family_id) where family_id is not null do nothing
  returning id into v_id;

  -- First touch wins: a second call for the same family is a no-op, not an error.
  if v_id is null then
    select id into v_id
      from public.signup_attribution
     where family_id = v_family
     limit 1;
    return jsonb_build_object('ok', true, 'first_touch', false, 'id', v_id);
  end if;

  return jsonb_build_object('ok', true, 'first_touch', true, 'id', v_id);
end;
$$;

revoke all on function public.record_signup_attribution(jsonb) from public;
grant execute on function public.record_signup_attribution(jsonb) to anon, authenticated;

comment on function public.record_signup_attribution(jsonb) is
  'First-touch signup attribution write path for anon clients. Validates family_id against families; relies on signup_attr_family_uniq so a repeat call never overwrites the original touch.';