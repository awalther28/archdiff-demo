# archdiff demo: IAM permission-graph diffing

A small, deliberately constructed OpenTofu estate used to exercise an IAM
permission-graph differ. It contains two root modules in two AWS accounts,
one child module, twenty resources, and three pull-request branches that each
demonstrate one thing the differ must get right.

Nothing here is ever applied. Every plan runs offline: no AWS account, no
state, no network (beyond the one-time provider download), fake credentials.
Plan JSON is never committed: CI plans both sides of every pull request
itself, and `scripts/gen-plans.sh` writes plans on demand into the gitignored
`plans/` directory (see [Generating the plans](#generating-the-plans)).

## Accounts

| root        | `account_id`   | role                  |
|-------------|----------------|-----------------------|
| `live/mgmt` | `999988887777` | management account    |
| `live/prod` | `111122223333` | prod workload account |

A third account, `555566667777`, appears only as an external principal (a
third-party auditor). Nothing in it is managed here.

Both IDs are passed at plan time as `-var account_id=...`: by
`scripts/gen-plans.sh` locally, and by the CI action from the `vars` map in
`.archdiff.json`. There is no committed plan to look them up in.

Each root declares its account identity through a single required input
variable, `account_id`, which carries a `validation {}` block asserting a
12-digit AWS account ID and which is used to assemble literal ARNs. It is
visible in the plan JSON as `variables.account_id.value`, and the validation
regex is visible in the HCL, so an extractor can resolve each root's scope
with high confidence from the plan alone. The `provider "aws"` blocks carry
only fake inline credentials (`access_key = "fake"`) plus the offline `skip_*`
flags; they say nothing about which account they target.

> Why a variable and not a provider-level setting? A credentials `profile` is
> a name, not an account ID: resolving it means reading `~/.aws/config`,
> ambient state a plan consumer must not depend on. `allowed_account_ids` is
> validated against the account ID the provider discovers at plan time; with
> `skip_requesting_account_id = true` that ID is empty and the plan fails with
> `AWS account ID not allowed:` (verified on provider 5.100.0 and 6.63.0).
> Without the skip, the provider calls STS and fails on fake credentials.
> `assume_role {}` has the same problem. A plain input variable is the only
> account handle that both survives offline planning and lands in the plan
> JSON as a literal.

## Layout

```
live/mgmt/            root module, management account
live/prod/            root module, prod workload account
modules/app-role/     child module: application runtime role + read policy
plans/<ref>/          generated plan JSON, one file per root; gitignored,
                      never committed
scripts/gen-plans.sh  writes plans/<ref>/ for the working tree or for any
                      committed ref(s)
scripts/effective_permissions.py
                      verification aid: name-keyed, order-independent view of
                      effective permissions; diffs two refs' generated plans
```

## Resources

### `live/mgmt` (999988887777)

| address | purpose |
|---|---|
| `aws_iam_openid_connect_provider.github` | GitHub Actions OIDC entry point |
| `aws_iam_role.gha` | low-trust CI role; trust policy carries **two `Condition` blocks** (`aud`, `sub`) |
| `aws_iam_policy.gha_artifacts` + attachment | `s3:GetObject` / `s3:ListBucket` on the artifact bucket |
| `aws_iam_role.mgmt_deploy` | deployment role; trusted by an SSO operator role that is **not managed here** (external) |
| `aws_iam_policy.mgmt_deploy` + attachment | `sts:AssumeRole` on `prod-deployer` and `prod-app-admin`; read/write artifacts |
| `aws_s3_bucket.artifacts` | `acme-build-artifacts` |

### `live/prod` (111122223333)

| address | purpose |
|---|---|
| `aws_kms_key.main` | application data key |
| `aws_s3_bucket.data` | `acme-prod-app-data` |
| `aws_iam_role.app_admin` | **privileged**. Trusted by `mgmt-deploy` (cross-account) and by an external auditor role **with an `sts:ExternalId` `Condition`** |
| `aws_iam_policy.app_admin` + attachment | `iam:*` on `role/prod-*`, `s3:*` on the data bucket, `kms:*` on `*` (wildcard target) |
| `aws_iam_role.deployer` | trusted by `mgmt-deploy`; holds **`iam:PassRole`** on `prod-app` plus Lambda deploy actions (inline `aws_iam_role_policy`) |
| `module.app.aws_iam_role.this` | `prod-app`, Lambda runtime role (child module) |
| `module.app.aws_iam_policy.data_read` + attachment | `s3:GetObject` / `s3:ListBucket` on the data bucket (child module) |
| `aws_iam_policy.kms_use` + attachment to `prod-app` | **deliberately poisoned**: references `aws_kms_key.main.arn`, so the whole rendered body is `unknown` at plan time, including its literal `s3:PutObject` statement |

### Things the differ must surface rather than evaluate

- `aws_iam_policy.kms_use`: `unresolved_policy_body`. The plan JSON has
  `after_unknown.policy = true` and no body.
- `aws_iam_role.gha` trust and the `ThirdPartyAudit` statement on
  `aws_iam_role.app_admin`: `condition`.
- `arn:aws:iam::999988887777:role/aws-reserved/sso.amazonaws.com/...` and
  `arn:aws:iam::555566667777:role/third-party-audit`: `external`.
- `kms:*` on `Resource: "*"`: `wildcard`.

### A plan-time rule this repo relies on

Any `aws_iam_policy_document` that references *any* attribute of a managed
resource being created is deferred in its entirety, even if that attribute
(e.g. `aws_iam_role.gha.name`) is known. All policy bodies here are therefore
assembled from variables, locals and literals; the only exception is the
poisoned `kms_use` document, which is the point.

## Branches and their privilege paths

Edges below are `can_assume` edges derived from trust policies, written
source -> target. `(C)` marks an edge whose statement carries a `Condition`.

### `main`

```
OIDC:github  -(C)-> mgmt:gha                                 (no onward path)
external:sso-operator ---> mgmt:mgmt-deploy ---> prod:prod-app-admin
                                           \--> prod:prod-deployer
external:third-party-audit -(C)-> prod:prod-app-admin
```

`gha` can read build artifacts and nothing else. The cross-account hop
`mgmt-deploy -> prod-app-admin` already exists, but nothing automated can
reach `mgmt-deploy`.

### `pr/star-policy`

One line changed in `modules/app-role/main.tf`: `s3:GetObject` becomes
`s3:*` on `prod-app`'s data-read policy. Tiny textual diff, large capability
delta (write, delete, ACL and policy actions on every object in the bucket).
No path changes.

### `pr/invisible-escalation`

One line changed in `live/mgmt/main.tf`: the trust policy of `mgmt-deploy`
gains `local.gha_role_arn` as an allowed principal. The diff mentions only
`gha` and `mgmt-deploy`; it never mentions `prod`, `admin`, or any privileged
action, and the `live/prod` plan is unchanged (its JSON differs from `main`
only in `timestamp` and in the emission order of `relevant_attributes`, which
OpenTofu does not sort). Yet it creates a new, unconditional, cross-account
path:

```
mgmt:gha ---> mgmt:mgmt-deploy ---> prod:prod-app-admin     (2 hops, NEW)
mgmt:gha ---> mgmt:mgmt-deploy ---> prod:prod-deployer      (2 hops, NEW)
```

A reviewer looking at either root in isolation cannot see this.

### `pr/refactor-noop`

A large refactor with **no effective permission change**:

- `live/mgmt/main.tf` split into `oidc.tf`, `deploy-role.tf`, `storage.tf`;
  statements and condition blocks reordered; locals regrouped.
- `live/prod/main.tf` split into `data.tf`, `admin.tf`, `deployer.tf`,
  `app.tf`; `app_admin_trust` statements reordered.
- `aws_iam_role.deployer` and its inline policy moved into a new child module
  `modules/deployer` (declared with `moved {}` blocks).
- `modules/app-role` renamed to `modules/workload-role`; `module.app`
  renamed to `module.workload` (declared with a `moved {}` block).

Terraform addresses change, file names change, statement order in rendered
JSON changes. Role names, policy names, trust relationships, actions,
resources and conditions do not. The differ must report an empty diff.

Note that `moved {}` blocks do **not** appear anywhere in `tofu show -json`
output when there is no prior state; a differ that honours them must read
them from the HCL source.

## Generating the plans

Plan JSON is a build artifact and is **not committed**. It is large, it is
noisy in diffs, it goes stale the moment the HCL changes, and a reviewer
cannot tell whether a committed plan actually corresponds to the committed
configuration. Plans are therefore generated where they are consumed:

- **In CI, on every pull request.** `.github/workflows/archdiff-pr.yml` runs
  the `awalther28/archdiff` analyze action, which runs `tofu init`,
  `tofu plan -refresh=false` and `tofu show -json` for each root declared in
  `.archdiff.json`, once on the PR head and once on the base ref in a
  separate worktree, then extracts and diffs the two permission graphs. Both
  sides are always planned by the same tool version in the same run, and CI
  reads nothing from `plans/`. `archdiff-baseline.yml` does the same for
  `main` on push to publish the graph baseline.
- **Locally, on demand,** with `scripts/gen-plans.sh`, which writes
  `plans/<ref>/{mgmt,prod}.plan.json`. `plans/` is gitignored.

Requires `tofu` (tested with OpenTofu 1.12.6) and, on first run, network
access to download the AWS provider (`~> 6.0`; the committed lock files pin
`6.63.0` for `darwin_arm64` -- on another platform run `tofu init -upgrade`
in each root once, or `tofu providers lock -platform=...`).

```sh
scripts/gen-plans.sh                  # the working tree -> plans/<current-branch>/
scripts/gen-plans.sh main pr/star-policy
                                      # any committed refs, each checked out in a
                                      # temporary worktree -> plans/<ref>/
```

The script is equivalent to running, in each of `live/mgmt` and `live/prod`,
with `AWS_ACCESS_KEY_ID=fake AWS_SECRET_ACCESS_KEY=fake AWS_REGION=us-east-1
AWS_EC2_METADATA_DISABLED=true` in the environment:

```sh
tofu init
tofu plan -refresh=false -out=tfplan -var account_id=999988887777   # mgmt
tofu plan -refresh=false -out=tfplan -var account_id=111122223333   # prod
tofu show -json tfplan > ../../plans/<ref>/<root>.plan.json
```

## Verifying the branch claims yourself

```sh
# generate all four branches' plans without leaving the current checkout
scripts/gen-plans.sh main pr/star-policy pr/invisible-escalation pr/refactor-noop

# refactor must be a no-op
scripts/effective_permissions.py plans/main plans/pr/refactor-noop
#   -> IDENTICAL effective permissions

# the other two must not be
scripts/effective_permissions.py plans/main plans/pr/star-policy
scripts/effective_permissions.py plans/main plans/pr/invisible-escalation

# assume-role paths between managed roles, from trust policies
scripts/effective_permissions.py --paths plans/main
scripts/effective_permissions.py --paths plans/pr/invisible-escalation
```

`effective_permissions.py` is a verification aid for this repo, not the
differ: it keys roles, policies and buckets by name, drops `Sid`, sorts
statements and list-valued fields, and resolves attachment targets through
`configuration.*.expressions.policy_arn.references` when the ARN is unknown.
