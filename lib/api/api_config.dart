// Base URLs for the two new NestJS backends (tally-oauth = identity/auth,
// tally-api = per-tenant Tally data/reports). Mirrors the prod/dev toggle
// pattern already used for the legacy backend in constants.dart - swap which
// line is active per environment until these move to a real build-time
// config (--dart-define / flavors).
//
// NOT YET DEPLOYED: these currently point at localhost, matching each
// repo's own PORT (tally-admin-api/.env.example: PORT=3000,
// tally-api/.env.example: PORT=3001). Replace with the real deployed URLs
// before testing against anything other than a local backend.
const String tallyOauthBaseUrl = 'http://localhost:3000';
const String tallyApiBaseUrl = 'http://localhost:3001';

// Both backends share the same global prefix + URI versioning scheme
// (APP_PREFIX=api, defaultVersion: '1' - see each repo's main.ts).
const String tallyOauthApiRoot = '$tallyOauthBaseUrl/api/v1';
const String tallyApiApiRoot = '$tallyApiBaseUrl/api/v1';
