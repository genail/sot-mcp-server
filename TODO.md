# SOT Server — Known Gaps

## High Severity

### ~~1. Data replacement on update is silent and destructive~~ DONE
Update now merges by default. Null-to-delete supported. `replace_data: true` for full replacement.

### ~~2. No fetch-record-by-ID~~ DONE
`sot_query` now accepts `record_id` parameter.

### 3. No way to promote/demote a user
`UserService.update` exists but `sot_admin_manage_users` has no `update` action. Changing `is_admin` requires delete + recreate, which is blocked by FK constraints if the user has any activity.
- `lib/sot/tools/admin/manage_users.rb`
- `lib/sot/services/user_service.rb:7-10`

### 4. Delete user/schema suggests impossible cleanup
Error messages say "reassign or delete those first" but no tool exists to delete/reassign activity log entries or records owned by a user. Dead-end workflow.
- `lib/sot/tools/admin/manage_users.rb:77-82`
- `lib/sot/tools/admin/manage_schema.rb:123-128`

### 5. No activity log pagination or date filtering
No `offset` parameter, no `since`/`until`. Entries beyond the `limit` are inaccessible. Admins can't answer "what happened yesterday?"
- `lib/sot/tools/user/activity_log.rb`

## Medium Severity

### 6. Query results omit ownership and timestamps
`created_by`, `updated_by`, `created_at`, `updated_at` exist on records but are never shown. Users can't tell who owns a record or when it was last changed.
- `lib/sot/tools/user/query.rb:64-67`

### 7. `sot_whoami` doesn't reveal admin status
A user can't discover whether they have admin privileges without trying an admin operation and failing.
- `lib/sot/tools/user/whoami.rb:16`

### 8. Schema create/update responses don't echo the result
Admin gets "Updated table 'X'" but not the resulting fields/states. REST API returns the full schema; MCP doesn't.
- `lib/sot/tools/admin/manage_schema.rb:86,104`

### 9. Feedback table link silently dropped
If table name doesn't resolve, feedback saves with `schema_id: nil` — no error. Admin sees feedback with no table context.
- `lib/sot/tools/user/feedback.rb:31`

### 10. Users can't view their own submitted feedback
`sot_feedback` creates feedback, but only admins can read it. Users can't check if their feedback was addressed.
- `lib/sot/tools/user/feedback.rb`
- `lib/sot/tools/admin/view_feedback.rb`

### 11. Activity log `changes` is raw JSON string
MCP renders `e.changes` as raw JSON. REST API calls `parsed_changes`. Inconsistent and hard to read.
- `lib/sot/tools/user/activity_log.rb:76`

### 12. No admin view feedback pagination offset
`limit` exists but no `offset`. Older feedback entries are inaccessible.
- `lib/sot/tools/admin/view_feedback.rb:51`

### 13. Schema changes not logged in activity log
Only record mutations are tracked. Admin schema edits leave no audit trail.
- `lib/sot/services/schema_service.rb`

### 14. Feedback can't be deleted or unresolved
No delete action, `resolved` is one-way. Duplicates or mistakes can't be cleaned up.
- `lib/sot/tools/admin/view_feedback.rb`

## Low Severity

### 15. Filters are exact-match only
No range queries, partial matching, or multi-value filters. Integer/float fields can't be queried numerically.
- `lib/sot/services/query_service.rb:8-13`

### 16. Default state not marked in `sot_list_tables`
States are listed without indicating which is the default initial state.
- `lib/sot/tools/user/list_tables.rb`

### 17. Inconsistent default limits
REST defaults to 50, MCP to 100.
- `lib/sot/api_app.rb` vs `lib/sot/tools/user/query.rb`

### 18. Query pagination doesn't indicate remaining pages
Shows total count but no "showing X-Y of Z" message.
- `lib/sot/tools/user/query.rb:69-75`
