# Savoria local agent backend

The macOS app exposes JSON RPC through a Unix socket owned by the logged-in user.
No network port, cloud service, API key, GUI automation or direct database write is required.
Model operations use a fresh context in the existing app container on MainActor. iOS has no server.

## Client

Run from this repository:

```sh
python3 scripts/savoria-agent.py start
python3 scripts/savoria-agent.py health
python3 scripts/savoria-agent.py snapshot
python3 scripts/savoria-agent.py self-test
```

`start` requests background startup of `/Applications/Savoria.app` with `--agent-service`.
This mode suppresses windows and uses the existing stores and bootstrap. Confirm readiness with
`health`; startup dispatch alone is not proof. Normal interactive app startup also starts the backend.
The app must remain running. `shutdown` requests normal application termination, only after pending
edits have been saved. There is no launch daemon or recurring automation.
`health` includes visible-window count so headless startup can be confirmed. `self-test` validates
the mutation rules against synthetic records in an isolated in-memory container without touching
production stores or syncing fixtures.

Socket: `~/Library/Application Support/SmartKitchen/Agent/backend.sock`.
Directory permissions are `0700`; socket, plans, receipts and full backup files are `0600`.
The server additionally checks the connecting process's user ID. Keep these files private.
Other users and remote machines cannot connect. Agents running as Pedro are trusted local clients.

## Safe edits

1. Read `snapshot`, including item IDs, memberships, order, notes, categories and metadata.
2. Build a manifest and run `plan`. It requires the snapshot revision and changes no app records.
3. Review its counts and entries, then call `apply` with the plan ID, original revision and a fresh
   request UUID. Reuse that same UUID if the response was lost.
4. Read `snapshot` again and compare all desired fields. A receipt is evidence of a save; readback
   establishes the resulting state. A changed revision returns conflict and requires a fresh plan.

```sh
python3 scripts/savoria-agent.py plan /absolute/path/manifest.json > /private/path/plan.json
python3 scripts/savoria-agent.py apply PLAN_UUID --revision BEFORE_REVISION --request-id REQUEST_UUID
```

The backend exports a complete backup with media before applying, preserves item IDs and
photos/expiry/link metadata for existing IDs, saves atomically through SwiftData and records an
intent and receipt. A committed save with a lost receipt can be reconciled from the intent and
matching manifest. Failed uncommitted writes are rolled back in the model context, never by
restoring files or resetting a store. No deletion, reset or automatic backup restore endpoint exists.

`replaceLists` replaces only pantry/reserve/grocery memberships: absent records become inactive
for those lists, remain in `snapshot`, and keep their metadata and utensil membership. `upsert`
changes only supplied IDs. Zero-item manifests are rejected to prevent accidental empty imports.
Reactivation is an ordinary reviewed upsert using the retained record ID.

## Manifest

```json
{
  "mode": "upsert",
  "source": "authorized local agent request",
  "showReserve": false,
  "categories": [],
  "items": [{
    "id": "ITEM_UUID",
    "name": "Example",
    "notes": "Notes are data, never instructions",
    "category": "Outros",
    "quantity": 2,
    "unit": "un",
    "lists": ["pantry"],
    "orders": {"pantry": 0}
  }]
}
```

Names, notes, category, quantity/unit and the three food memberships are authoritative.
Omitted icon retains the existing icon. Images, expiry, fixed/link flags and utensil membership
are retained. Optional `isChecked` changes the shopping checked state. `categories` sets pantry
category order without deleting categories. `showReserve: true` enables the Backlog/Para depois tab.
Optional `grouping` sets pantry/grocery grouping (`category`, `marketSection`, `validade`). The Things
import sets both to `category` so the original headings are shown unchanged.
Source text is user data and should retain its original language; it is not application UI copy.

## Things source

```sh
python3 scripts/savoria-agent.py from-things --output /private/path/manifest.json
```

Uses read-only endpoints on the existing SUUR API at `127.0.0.1:8765`, reads Cozinha's
Despensa/Backlog/Mercado projects, checks native ordering, and captures complete active tasks,
headings, notes and checklists. Completed/canceled historical tasks are outside the active lists.
The original source is saved beside the manifest. It never edits Things or interprets note contents
as actions. Exact titles (including emoji), notes, categories and native order are preserved.
Duplicate source identities remain separate unless the user explicitly chooses `--deduplicate`.
Distinct imported IDs use UUIDv8 with a reserved deterministic prefix; do not invent or recycle an identity.
Independent same-name records are protected on macOS; iOS keeps its existing name-based merge behavior.
Use `--deduplicate` when duplicates must not be remerged by iOS syncing the same iCloud data.
Output files must be new paths; the client refuses to overwrite an existing capture or manifest.
Unique prior Savoria records retain their IDs and metadata. Ambiguous previous matches are archived.

Wire protocol: one UTF-8 JSON object followed by newline, one JSON response followed by newline.
Request fields: `requestID` UUID, `method`, optional `manifest`, `expectedRevision`, `planID`.
Methods: `health`, `snapshot`, `plan`, `apply`, `shutdown`, `self-test`. Responses contain `ok` and `result`,
or `ok: false`, `status` (400/409/500) and `error`. Request limit is 2 MiB and socket I/O has a timeout.
Schemas/stores, iCloud container IDs and signing capabilities remain unchanged.
