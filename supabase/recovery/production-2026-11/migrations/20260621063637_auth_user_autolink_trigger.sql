-- Glue between native phone-auth and our person model.
-- When a phone-auth user is created/confirmed, fire verify_and_link with the
-- REAL auth_user_id, so their people row gets the auth link and family_access
-- is created/updated. Defensive: a link error NEVER blocks the auth signup.
--
-- Supabase stores auth.users.phone WITHOUT a leading '+', so we normalize
-- to E.164 to match people.phone (+1716...).

CREATE OR REPLACE FUNCTION public.handle_phone_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_phone text;
    v_name  text;
BEGIN
    IF NEW.phone IS NULL OR NEW.phone = '' THEN
        RETURN NEW;
    END IF;
    IF NEW.phone_confirmed_at IS NULL THEN
        RETURN NEW;  -- only act once the phone is actually verified
    END IF;

    v_phone := CASE WHEN left(NEW.phone, 1) = '+' THEN NEW.phone ELSE '+' || NEW.phone END;
    v_name  := COALESCE(NEW.raw_user_meta_data->>'display_name',
                        NEW.raw_user_meta_data->>'name');

    BEGIN
        PERFORM public.verify_and_link(v_phone, NEW.id, v_name);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'verify_and_link failed for auth user % (%): %', NEW.id, v_phone, SQLERRM;
    END;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_phone_auth_user_confirmed ON auth.users;
CREATE TRIGGER on_phone_auth_user_confirmed
    AFTER INSERT OR UPDATE OF phone_confirmed_at ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_phone_auth_user();