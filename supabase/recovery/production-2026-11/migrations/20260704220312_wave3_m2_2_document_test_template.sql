begin;

insert into public.document_templates
  (workspace_id, industry_pack, key, name, description, subject_type, version, status, output_format, content_spec, created_by)
select
  (select id from public.business_workspaces where slug='venuewise'),
  'generic', 'demo_intake_summary', 'Demo Intake Summary',
  'Test document that merges demo_intake form data into a PDF.',
  'demo', 1, 'published', 'pdf',
  $json$
  {
    "blocks": [
      {"type":"heading","text":"Intake Summary"},
      {"type":"paragraph","text":"Generated {{now.datetime}} for {{workspace.name}}. This document was produced by the Venuewise Document Engine from submitted form data."},
      {"type":"divider"},
      {"type":"fields","items":[
        {"label":"Full name","value":"{{form.demo_intake.contact.full_name}}"},
        {"label":"Email","value":"{{form.demo_intake.contact.email}}"},
        {"label":"Workflow","value":"{{workflow.title}}"}
      ]},
      {"type":"spacer","height":18},
      {"type":"paragraph","text":"By signing below, the parties acknowledge the information above is accurate."},
      {"type":"spacer","height":24},
      {"type":"signature_line","label":"Signature"},
      {"type":"spacer","height":10},
      {"type":"signature_line","label":"Date"}
    ]
  }
  $json$::jsonb,
  '6ee85982-6b8f-4d07-a345-665f9fac0efb'::uuid;

commit;