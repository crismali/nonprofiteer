%Doctor.Config{
  ignore_modules: [],
  # Untouched igniter/phx.new scaffold — no web UI or app code has been hand-written yet (see
  # README.md / CLAUDE.md Status). Remove entries here as each file actually gets built out;
  # don't widen the pattern to all of lib/nonprofiteer_web, or real hand-written code would
  # silently skip doc coverage too.
  ignore_paths: [
    ~r/lib\/nonprofiteer\/mailer\.ex/,
    ~r/lib\/nonprofiteer\/repo\.ex/,
    ~r/lib\/nonprofiteer_web\.ex/,
    ~r/lib\/nonprofiteer_web\/telemetry\.ex/,
    ~r/lib\/nonprofiteer_web\/router\.ex/,
    ~r/lib\/nonprofiteer_web\/endpoint\.ex/,
    ~r/lib\/nonprofiteer_web\/gettext\.ex/,
    ~r/lib\/nonprofiteer_web\/components\/core_components\.ex/,
    ~r/lib\/nonprofiteer_web\/components\/layouts\.ex/,
    ~r/lib\/nonprofiteer_web\/controllers\/error_html\.ex/,
    ~r/lib\/nonprofiteer_web\/controllers\/error_json\.ex/,
    ~r/lib\/nonprofiteer_web\/controllers\/page_controller\.ex/,
    ~r/lib\/nonprofiteer_web\/controllers\/page_html\.ex/
  ],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 100,
  min_overall_moduledoc_coverage: 100,
  # Spec coverage intentionally unenforced — @impl callbacks are exempt from @spec, and
  # default-argument functions generate extra arities doctor flags as spec-less even when the
  # documented arity has one. @doc coverage (enforced above, 100%) is the meaningful signal.
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
