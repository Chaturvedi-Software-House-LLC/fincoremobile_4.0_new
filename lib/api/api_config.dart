// Base URLs for the two new NestJS backends (tally-oauth = identity/auth,
// tally-api = per-tenant Tally data/reports). Mirrors the prod/dev toggle
// pattern already used for the legacy backend in constants.dart - swap which
// line is active per environment until these move to a real build-time
// config (--dart-define / flavors).
//
// Deployed on the Comhard cloud VM behind Caddy (reverse proxy + real
// Let's Encrypt cert reusing fincorego.duckdns.org's DNS, but on separate
// ports so the existing legacy IIS site on 80/443 stays untouched):
// tally-admin-api (identity/auth) -> :8444, tally-api (Tally data) -> :8443.
const String tallyOauthBaseUrl = 'https://fincorego.duckdns.org:8444';
const String tallyApiBaseUrl = 'https://fincorego.duckdns.org:8443';

// Both backends share the same global prefix + URI versioning scheme
// (APP_PREFIX=api, defaultVersion: '1' - see each repo's main.ts).
const String tallyOauthApiRoot = '$tallyOauthBaseUrl/api/v1';
const String tallyApiApiRoot = '$tallyApiBaseUrl/api/v1';
