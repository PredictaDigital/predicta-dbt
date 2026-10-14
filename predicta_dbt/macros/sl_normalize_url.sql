{#- Normalise a page URL to one canonical form: lower case, query string and
    fragment dropped, trailing slash dropped. 'HTTPS://Site.io/About/?utm=1#top'
    and 'https://site.io/about' become the same string. -#}
{% macro sl_normalize_url(expr) -%}
    replaceRegexpOne(
        replaceRegexpOne(
            replaceRegexpOne(lowerUTF8(trim({{ expr }})), '[#].*$', ''),
            '[?].*$', ''),
        '/+$', '')
{%- endmacro %}
