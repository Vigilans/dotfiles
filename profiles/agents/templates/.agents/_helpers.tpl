{% macro resolve_model(selector, effort, default_effort="") -%}
{%- set selector = selector or "" %}
{%- set alias = selector.toUpperCase() %}
{%- set registered = os.environ["AGENTS_" + alias + "_MODEL"] if not alias.startsWith("SUBAGENT_") else "" %}
{%- set model = registered or selector %}
{%- set alias_effort = os.environ["AGENTS_" + alias + "_REASONING_EFFORT"] if registered else "" %}
{%- set long_context = model.endsWith("[1m]") %}
{%- if long_context %}{% set model = model.slice(0, -4) %}{% endif %}
{%- set encoded_effort = "" %}
{%- if AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX == "true" %}
{%-   for level in ["none", "minimal", "low", "medium", "high", "xhigh", "ultra", "max"] %}
{%-     if not encoded_effort and model.endsWith("-" + level) %}
{%-       set encoded_effort = level %}
{%-       set model = model.slice(0, -(level.length + 1)) %}
{%-     endif %}
{%-   endfor %}
{%- endif %}
{#- An effort passed by the caller, even empty, is final; otherwise the alias,
    the model suffix, and the caller's default are tried in turn. -#}
{%- set effort = effort if effort is defined else (alias_effort or encoded_effort or default_effort or "") %}
{{- {"model": model, "effort": effort, "long_context": long_context} | dump -}}
{%- endmacro %}

{% macro claude_model(resolved) -%}
{%- set model = resolved.model %}
{%- if AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX == "true" and resolved.effort and model and not ["inherit", "default"].includes(model) %}
{%-   set model = model + "-" + resolved.effort %}
{%- endif %}
{{- (model + ("[1m]" if resolved.long_context else "")) | dump -}}
{%- endmacro %}

{% macro toml_multiline(value) -%}
"""
{% for line in value.split("\n") %}{% set encoded = line | dump %}{{ encoded.slice(1, -1) | replace(r/\x7f/g, "\\u007f") }}
{% endfor %}"""
{%- endmacro %}

{% macro yaml_model(value) -%}
{%- if r/^[A-Za-z_][A-Za-z0-9_.\/+-]*(?:\[1m\])?$/.test(value)
      and not ["null", "true", "false", "yes", "no", "on", "off", "y", "n"].includes(value.toLowerCase()) -%}
{{- value -}}
{%- else -%}
{{- value | dump -}}
{%- endif -%}
{%- endmacro %}

{% macro render_agent(role, description, instructions, defaults) -%}
{%- if relative_path.startsWith(".codex/agents/") %}
{%-   set client = "CODEX" %}
{%- elif relative_path.startsWith(".claude/agents/") %}
{%-   set client = "CLAUDE_CODE" %}
{%- elif relative_path.startsWith(".config/opencode/agents/") %}
{%-   set client = "OPENCODE" %}
{%- else %}
{%-   set _ = fail("unsupported agent output path: " + relative_path) %}
{%- endif %}
{%- set filename = relative_path.split("/") | last %}
{%- set name = filename.slice(0, filename.lastIndexOf(".")) %}
{%- set key = name.toUpperCase().replaceAll("-", "_") %}
{%- set app = client + "_SUBAGENT_" + key %}
{%- set shared = "AGENTS_SUBAGENT_" + role %}
{%- set defaults = defaults["CLAUDE_CODE" if client == "OPENCODE" else client] or {} %}
{%- set model = json.parse(resolve_model(
      os.environ[app + "_MODEL"] if (app + "_MODEL") in os.environ
        else (os.environ[shared + "_MODEL"] if (shared + "_MODEL") in os.environ else defaults.model),
      os.environ[app + "_REASONING_EFFORT"] if (app + "_REASONING_EFFORT") in os.environ
        else os.environ[shared + "_REASONING_EFFORT"],
      defaults.effort)) %}
{%- if model.effort and (not model.model or ["inherit", "default"].includes(model.model))
      and client == "CLAUDE_CODE" and AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX == "true" %}
{%-   set _ = fail(relative_path + ": effort requires a concrete model; set " + app + "_MODEL or " + shared + "_MODEL") %}
{%- endif %}
{%- set description = description | trim %}
{%- set instructions = instructions | trim %}
{%- if client == "CODEX" -%}
{{ toml.stringify({"name": name}) | trim }}

description = {{ toml_multiline(description) }}

{% if model.model -%}
{{ toml.stringify({"model": model.model}) | trim }}
{% endif -%}
{% if model.effort -%}
{{ toml.stringify({"model_reasoning_effort": model.effort}) | trim }}
{% endif -%}
{% for key, value in defaults -%}
{% if not ["model", "effort"].includes(key) -%}
{{ toml.stringify(json.merge({}, key, value)) | trim }}
{% endif -%}
{% endfor %}
developer_instructions = {{ toml_multiline(instructions) }}
{% else -%}
---
name: {{ name }}
description: |
{{ description | indent(2, true) }}
{% if client == "OPENCODE" -%}
mode: subagent
{% if model.model -%}
model: {{ yaml_model((AGENTS_MODEL_PROVIDER or "custom") + "/" + model.model) }}
{% endif -%}
{% if model.effort -%}
variant: {{ model.effort | dump }}
{% endif -%}
{% else -%}
{% if model.model -%}
model: {{ yaml_model(json.parse(claude_model(model))) }}
{% endif -%}
{% if model.effort and AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX != "true" -%}
effort: {{ model.effort | dump }}
{% endif -%}
{% endif -%}
---

{{ instructions }}
{% endif -%}
{%- endmacro %}
