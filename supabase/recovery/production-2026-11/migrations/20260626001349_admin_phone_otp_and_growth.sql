
-- is_admin() now recognizes BOTH:
--   1) the email allowlist (admin_users)  -> your email backup login
--   2) an active roster member with role 'admin' matched by phone -> phone OTP + future admins
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = auth.uid())
      OR EXISTS (
        SELECT 1 FROM public.academy_members m
        JOIN auth.users u ON u.id = auth.uid()
        WHERE m.active AND m.role = 'admin'
          AND m.phone = public.norm_phone(u.phone)
      );
$$;

-- Promote Keith's roster entry to admin so his PHONE session is recognized as admin.
UPDATE public.academy_members
SET role = 'admin'
WHERE phone = public.norm_phone('7162703874');
