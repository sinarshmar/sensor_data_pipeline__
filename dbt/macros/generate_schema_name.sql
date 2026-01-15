{#
    Custom schema name macro - overrides dbt's default behavior.

    DECISION: We use clean schema names (silver, gold) without environment prefix
    to keep the project simple for single-environment development.

    Default dbt behavior concatenates: {target_schema}_{custom_schema}
    Example: public_silver, dev_silver, prod_silver

    This macro uses exact schema names: silver, gold

    TO ADD MULTI-ENVIRONMENT SUPPORT LATER:
    Replace this macro with:

        {% macro generate_schema_name(custom_schema_name, node) -%}
            {%- if custom_schema_name is none -%}
                {{ default_schema }}
            {%- else -%}
                {{ default_schema }}_{{ custom_schema_name | trim }}
            {%- endif -%}
        {%- endmacro %}

    Then set schema: dev/prod/staging in profiles.yml per environment.
    This will create: dev_silver, prod_silver, staging_silver, etc.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
