# archdiff demo: IAM permission-graph diffing

A small, deliberately constructed OpenTofu estate used to exercise an IAM
permission-graph differ. It contains two root modules in two AWS accounts,
one child module, twenty resources, and three pull-request branches that each
demonstrate one thing the differ must get right.

Nothing here is ever applied. Every plan runs offline: no AWS account, no
state, no network (beyond the one-time provider download), fake credentials.

## Accounts

| root        | profile | account        | role                |
|-------------|---------|----------------|---------------------|
| `live/mgmt` | `mgmt`  | `999988887777` | management account  |
| `live/prod` | `prod`  | `111122223333` | prod workload account |

A third account, `555566667777`, appears only as an external principal (a
third-party auditor). Nothing in it is managed here.

Each root's `provider "aws"` block names a credentials `profile`, and each
root takes a required `account_id` variable which is used to assemble literal
ARNs. Both are visible in the plan JSON (`configuration.provider_config` and
`variables` respectively), so the extractor can resolve scope from either.

> Why `profile` and not `allowed_account_ids`? The AWS provider validates
> `allowed_account_ids` against the account ID it discovers at plan time. With
> `skip_requesting_account_id = true` that ID is empty, and the plan fails
> with `AWS account ID not allowed:` (verified on provider 5.100.0 and 6.63.0).
> Without the skip, the provider calls STS and fails on fake credentials.
> `assume_role {}` has the same problem. A named profile is the only
> provider-level account handle that survives offline planning.

## Layout

```
live/mgmt/            root module, management account
live/prod/            root module, prod workload account
modules/app-role/     child module: application runtime role + read policy
plans/<branch>/       committed plan JSON for each branch, one file per root
scripts/gen-plans.sh  regenerates plans/<branch>/ for the current branch
scripts/effective_permissions.py
                      verification aid: name-keyed, order-independent view of
                      effective permissions; diffs two branches' plans
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

## Regenerating the plans

Requires `tofu` (tested with OpenTofu 1.12.6) and, on first run, network
access to download the AWS provider (`~> 6.0`; the committed lock files pin
`6.63.0` for `darwin_arm64` -- on another platform run `tofu init -upgrade`
in each root once, or `tofu providers lock -platform=...`).

```sh
git checkout <branch>
scripts/gen-plans.sh            # writes plans/<branch>/{mgmt,prod}.plan.json
```

The script is equivalent to running, in each of `live/mgmt` and `live/prod`,
with `AWS_CONFIG_FILE` / `AWS_SHARED_CREDENTIALS_FILE` pointing at throwaway
files that define fake-credential profiles `mgmt` and `prod`:

```sh
tofu init
tofu plan -refresh=false -out=tfplan -var account_id=999988887777   # mgmt
tofu plan -refresh=false -out=tfplan -var account_id=111122223333   # prod
tofu show -json tfplan > ../../plans/<branch>/<root>.plan.json
```

## Verifying the branch claims yourself

```sh
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
