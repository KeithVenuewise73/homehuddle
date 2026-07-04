/* ============================================================================
 * Venuewise Core — shared/forms.js  (Dynamic Forms client)
 * Loads a form template, renders a dynamic form, saves drafts, and submits.
 * Reads are RLS-scoped; writes go through the form-save / form-submit Edge
 * Functions (server-authoritative + server-validated). Adopted by NO page yet.
 *
 * API:
 *   VW.forms.loadTemplate(sb, key, workspaceSlug) -> { template, sections }
 *   VW.forms.saveDraft(sb, { submissionId?, formKey?, workspaceSlug?, workflowTaskId?,
 *                            workflowInstanceId?, subjectType?, subjectId?, data }) -> { submissionId }
 *   VW.forms.submit(sb, submissionId, data) -> { ok, errors? , result? }
 *   VW.forms.render(container, { template, sections }, data, opts) -> controller
 *
 * Data shape:
 *   data[sectionKey] = { fieldKey: value }         (non-repeatable)
 *   data[sectionKey] = [ { fieldKey: value }, ... ] (repeatable)
 * ============================================================================ */
;(function (global) {
  'use strict';
  var VW = global.VW = global.VW || {};

  function getClient(client) {
    var sb = client || (typeof VW.createClient === 'function' ? VW.createClient() : null);
    if (!sb) throw new Error('[VW.forms] pass a Supabase client, or load /shared/config.js first.');
    return sb;
  }

  function isEmpty(v) {
    if (v === null || v === undefined) return true;
    if (typeof v === 'string') return v.trim() === '';
    if (Array.isArray(v)) return v.length === 0;
    return false;
  }

  function evalVisible(cond, ctx) {
    if (!cond || Object.keys(cond).length === 0) return true;
    if (cond.all) return cond.all.every(function (c) { return evalVisible(c, ctx); });
    if (cond.any) return cond.any.some(function (c) { return evalVisible(c, ctx); });
    if (cond.not) return !evalVisible(cond.not, ctx);
    if (cond.field !== undefined) {
      var v = ctx[cond.field];
      if (cond.equals !== undefined) return v === cond.equals;
      if (cond.in !== undefined) return Array.isArray(cond.in) && cond.in.indexOf(v) !== -1;
      if (cond.notEquals !== undefined) return v !== cond.notEquals;
      if (cond.isSet !== undefined) return cond.isSet ? !isEmpty(v) : isEmpty(v);
    }
    return true;
  }

  // ── data reads ──────────────────────────────────────────────────────────
  async function loadTemplate(client, key, workspaceSlug) {
    var sb = getClient(client);
    var wsId = null;
    if (workspaceSlug) {
      var ws = await sb.from('business_workspaces').select('id').eq('slug', workspaceSlug).limit(1);
      wsId = ws.data && ws.data[0] ? ws.data[0].id : null;
    }
    var q = sb.from('form_templates').select('*').eq('key', key).eq('status', 'published');
    if (wsId) q = q.or('workspace_id.eq.' + wsId + ',workspace_id.is.null');
    var t = await q.order('version', { ascending: false }).limit(1);
    var template = t.data && t.data[0];
    if (!template) return null;
    var secRes = await sb.from('form_sections').select('*').eq('form_template_id', template.id).order('position', { ascending: true });
    var fldRes = await sb.from('form_fields').select('*').eq('form_template_id', template.id).order('position', { ascending: true });
    var fields = fldRes.data || [];
    var sections = (secRes.data || []).map(function (s) {
      return Object.assign({}, s, { fields: fields.filter(function (f) { return f.section_id === s.id; }) });
    });
    return { template: template, sections: sections };
  }

  // ── writes (via Edge Functions) ───────────────────────────────────────────
  async function saveDraft(client, opts) {
    var sb = getClient(client);
    var resp = await sb.functions.invoke('form-save', { body: opts || {} });
    if (resp.error) return { ok: false, error: (resp.error && resp.error.message) || String(resp.error) };
    return { ok: true, submissionId: resp.data && resp.data.submissionId };
  }

  async function submit(client, submissionId, data) {
    var sb = getClient(client);
    var resp = await sb.functions.invoke('form-submit', { body: { submissionId: submissionId, data: data } });
    if (resp.error) {
      // On a non-2xx (e.g. 422 validation), supabase-js puts the raw Response on
      // error.context — read its JSON body to recover { errors } / { error }.
      var body = null;
      var ctx = resp.error && resp.error.context;
      if (ctx) {
        if (typeof ctx.json === 'function') {
          try { body = await ctx.json(); } catch (e) { body = null; }
        } else if (typeof ctx === 'object') {
          body = ctx; // some SDK versions already provide a parsed object
        }
      }
      if (body && body.errors) return { ok: false, errors: body.errors };
      return { ok: false, errors: null,
               error: (body && body.error) || (resp.error && resp.error.message) || 'submit failed' };
    }
    return { ok: true, result: resp.data && resp.data.result };
  }

  // ── renderer ──────────────────────────────────────────────────────────────
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c];
    });
  }

  function fieldControl(field, value, namePath) {
    var v = value == null ? (field.default_value != null ? field.default_value : '') : value;
    var t = field.field_type;
    var attr = 'data-path="' + esc(namePath) + '" data-key="' + esc(field.key) + '"';
    if (t === 'textarea') return '<textarea ' + attr + ' placeholder="' + esc(field.placeholder || '') + '">' + esc(v) + '</textarea>';
    if (t === 'select' || t === 'multiselect' || t === 'radio') {
      var opts = (field.options || []).map(function (o) {
        var val = o.value != null ? o.value : o; var lab = o.label != null ? o.label : val;
        var sel = (String(v) === String(val)) ? ' selected' : '';
        return '<option value="' + esc(val) + '"' + sel + '>' + esc(lab) + '</option>';
      }).join('');
      var multi = t === 'multiselect' ? ' multiple' : '';
      return '<select ' + attr + multi + '><option value="">—</option>' + opts + '</select>';
    }
    if (t === 'checkbox' || t === 'boolean') {
      var ck = (v === true || v === 'true') ? ' checked' : '';
      return '<input type="checkbox" ' + attr + ck + ' />';
    }
    if (t === 'info') return '<div class="vw-form-info">' + esc(field.help_text || field.label) + '</div>';
    if (t === 'file' || t === 'signature') return '<div class="vw-form-placeholder">(' + esc(t) + ' — available once the File/Document engine is enabled)</div>';
    var inputType = ({ number: 'number', integer: 'number', date: 'date', datetime: 'datetime-local', time: 'time', email: 'email', phone: 'tel', url: 'url' })[t] || 'text';
    return '<input type="' + inputType + '" ' + attr + ' value="' + esc(v) + '" placeholder="' + esc(field.placeholder || '') + '" />';
  }

  // Renders the form into `container`. opts: { onSaved, onSubmitted, autosave }.
  function render(container, loaded, data, opts) {
    opts = opts || {};
    data = data || {};
    var sections = loaded.sections || [];

    function ctxOf() {
      var ctx = {};
      sections.forEach(function (s) { if (!s.repeatable) Object.assign(ctx, data[s.key] || {}); });
      return ctx;
    }

    function draw() {
      var ctx = ctxOf();
      var html = sections.map(function (s) {
        if (!evalVisible(s.visible_if, ctx)) return '';
        var body;
        if (s.repeatable) {
          var rows = Array.isArray(data[s.key]) ? data[s.key] : [];
          body = rows.map(function (row, i) {
            return '<div class="vw-form-row" data-section="' + esc(s.key) + '" data-index="' + i + '">' +
              s.fields.map(function (f) {
                if (!evalVisible(f.visible_if, Object.assign({}, ctx, row))) return '';
                return '<label class="vw-form-field"><span>' + esc(f.label) + (f.required ? ' *' : '') + '</span>' +
                  fieldControl(f, row[f.key], s.key + '[' + i + '].' + f.key) + '</label>';
              }).join('') +
              '<button type="button" class="vw-form-remove" data-section="' + esc(s.key) + '" data-index="' + i + '">Remove</button>' +
            '</div>';
          }).join('') +
          '<button type="button" class="vw-form-add" data-section="' + esc(s.key) + '">+ Add</button>';
        } else {
          var row = data[s.key] || {};
          body = s.fields.map(function (f) {
            if (!evalVisible(f.visible_if, Object.assign({}, ctx, row))) return '';
            return '<label class="vw-form-field"><span>' + esc(f.label) + (f.required ? ' *' : '') + '</span>' +
              fieldControl(f, row[f.key], s.key + '.' + f.key) + '</label>';
          }).join('');
        }
        return '<fieldset class="vw-form-section"><legend>' + esc(s.name || s.key) + '</legend>' + body + '</fieldset>';
      }).join('');
      container.innerHTML = '<form class="vw-form">' + html +
        '<div class="vw-form-errors" style="display:none"></div>' +
        '<button type="button" class="vw-form-submit">Submit</button></form>';
      wire();
    }

    function readControl(el) {
      if (el.type === 'checkbox') return el.checked;
      return el.value;
    }

    function setValue(path, val) {
      // path: "section.field" or "section[i].field"
      var m = path.match(/^([^.[]+)(\[(\d+)\])?\.(.+)$/);
      if (!m) return;
      var sec = m[1], idx = m[3], key = m[4];
      if (idx !== undefined) {
        data[sec] = data[sec] || []; data[sec][+idx] = data[sec][+idx] || {}; data[sec][+idx][key] = val;
      } else {
        data[sec] = data[sec] || {}; data[sec][key] = val;
      }
    }

    var saveTimer = null;
    function scheduleSave() {
      if (!opts.autosave) return;
      clearTimeout(saveTimer);
      saveTimer = setTimeout(function () { if (opts.onSaved) opts.onSaved(data); }, 800);
    }

    function wire() {
      Array.prototype.forEach.call(container.querySelectorAll('[data-path]'), function (el) {
        el.addEventListener('change', function () {
          setValue(el.getAttribute('data-path'), readControl(el));
          scheduleSave();
          // re-draw if any visibility might depend on this field
          draw();
        });
      });
      Array.prototype.forEach.call(container.querySelectorAll('.vw-form-add'), function (btn) {
        btn.addEventListener('click', function () {
          var sec = btn.getAttribute('data-section');
          data[sec] = data[sec] || []; data[sec].push({}); draw();
        });
      });
      Array.prototype.forEach.call(container.querySelectorAll('.vw-form-remove'), function (btn) {
        btn.addEventListener('click', function () {
          var sec = btn.getAttribute('data-section'), i = +btn.getAttribute('data-index');
          if (Array.isArray(data[sec])) { data[sec].splice(i, 1); draw(); }
        });
      });
      var submitBtn = container.querySelector('.vw-form-submit');
      if (submitBtn) submitBtn.addEventListener('click', function () {
        if (opts.onSubmit) opts.onSubmit(data);
      });
    }

    draw();
    return {
      getData: function () { return data; },
      showErrors: function (errors) {
        var box = container.querySelector('.vw-form-errors');
        if (!box) return;
        if (!errors || !errors.length) { box.style.display = 'none'; return; }
        box.innerHTML = errors.map(function (e) { return '<div>' + esc(e.message) + '</div>'; }).join('');
        box.style.display = '';
      }
    };
  }

  VW.forms = { loadTemplate: loadTemplate, saveDraft: saveDraft, submit: submit, render: render, evalVisible: evalVisible };

})(typeof window !== 'undefined' ? window : this);
