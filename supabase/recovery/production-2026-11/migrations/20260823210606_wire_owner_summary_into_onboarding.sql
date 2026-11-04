-- Populate player_id on the player member row, and send the owner summary.
-- Rest of the function is unchanged.
do $do$
declare v_src text;
begin
  select pg_get_functiondef('public.create_family_onboarding(jsonb)'::regprocedure) into v_src;

  -- 1. link the player member row to its player record
  v_src := replace(v_src,
    E'        v_family, pl->>\'name\', \'player\', pl->>\'phone\',\n        coalesce((pl->>\'receives_sms\')::boolean, false), true,\n        false, false, false\n      )\n      RETURNING id INTO v_member_id;',
    E'        v_family, pl->>\'name\', \'player\', pl->>\'phone\',\n        coalesce((pl->>\'receives_sms\')::boolean, false), true,\n        false, false, false\n      )\n      RETURNING id INTO v_member_id;\n\n      UPDATE public.family_members SET player_id = v_player WHERE id = v_member_id;'
  );

  -- 2. owner summary immediately before the return
  v_src := replace(v_src,
    E'  RETURN jsonb_build_object(\'family_id\', v_family, \'email\', v_email);',
    E'  BEGIN\n    PERFORM public.queue_owner_member_summary(v_family);\n  EXCEPTION WHEN OTHERS THEN NULL;\n  END;\n\n  RETURN jsonb_build_object(\'family_id\', v_family, \'email\', v_email);'
  );

  execute v_src;
end
$do$;

select 'player_id wired: ' ||
  (pg_get_functiondef('public.create_family_onboarding(jsonb)'::regprocedure) like '%SET player_id = v_player%')::text
  || ' | summary wired: ' ||
  (pg_get_functiondef('public.create_family_onboarding(jsonb)'::regprocedure) like '%queue_owner_member_summary%')::text as result;