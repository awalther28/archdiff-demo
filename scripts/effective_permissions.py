#!/usr/bin/env python3
"""Reduce a branch's plan JSONs to a refactor-invariant view of effective
IAM permissions, so two branches can be compared with a plain diff.

This is a verification aid for the demo repository, NOT the permission-graph
differ. It deliberately keys everything by *name* (role name, policy name,
bucket name) rather than by Terraform address, and it sorts statements, so a
module move, file rename or statement reorder produces byte-identical output.

Usage:
    scripts/effective_permissions.py plans/main                 # dump
    scripts/effective_permissions.py plans/main plans/pr/x      # diff
    scripts/effective_permissions.py --paths plans/main         # assume paths
"""
import difflib
import json
import pathlib
import sys

ROOTS = ("mgmt", "prod")
UNRESOLVED = "<unresolved at plan time>"


def as_list(v):
    return v if isinstance(v, list) else [v]


def canon_policy(doc):
    """Sorted, Sid-less, list-normalised statements. None -> UNRESOLVED."""
    if doc is None:
        return UNRESOLVED
    stmts = []
    for s in as_list(json.loads(doc).get("Statement", [])):
        s = dict(s)
        s.pop("Sid", None)
        for k in ("Action", "NotAction", "Resource", "NotResource"):
            if k in s:
                s[k] = sorted(as_list(s[k]))
        if isinstance(s.get("Principal"), dict):
            s["Principal"] = {k: sorted(as_list(v)) for k, v in s["Principal"].items()}
        stmts.append(json.dumps(s, sort_keys=True, separators=(",", ":")))
    return sorted(stmts)


def walk_config(mod, prefix, out):
    for r in mod.get("resources", []):
        out[prefix + r["address"]] = (r, prefix)
    for name, call in mod.get("module_calls", {}).items():
        walk_config(call["module"], f"{prefix}module.{name}.", out)


def summarise(plan):
    account = plan["variables"]["account_id"]["value"]
    changes = {rc["address"]: rc for rc in plan["resource_changes"]}
    config = {}
    walk_config(plan["configuration"]["root_module"], "", config)

    def after(addr):
        return changes[addr]["change"]["after"] or {}

    def unknown(addr):
        return changes[addr]["change"].get("after_unknown") or {}

    def policy_body(addr):
        return UNRESOLVED if unknown(addr).get("policy") else canon_policy(after(addr).get("policy"))

    def policy_key(addr):
        """Name-keyed identity of the policy an attachment points at."""
        a = after(addr)
        if a.get("policy_arn"):
            return f"external:{a['policy_arn']}"
        cfg, prefix = config[addr]
        for ref in cfg["expressions"]["policy_arn"]["references"]:
            if ref.endswith(".arn"):
                return f"policy:{account}:{after(prefix + ref[:-4])['name']}"
        raise SystemExit(f"cannot resolve policy_arn for {addr}")

    roles, policies, buckets, keys = {}, {}, [], []
    for addr, rc in changes.items():
        t, a = rc["type"], after(addr)
        if t == "aws_iam_role":
            roles.setdefault(a["name"], {"attached": [], "inline": {}})
            roles[a["name"]]["trust"] = (
                UNRESOLVED if unknown(addr).get("assume_role_policy")
                else canon_policy(a["assume_role_policy"]))
        elif t == "aws_iam_policy":
            policies[a["name"]] = policy_body(addr)
        elif t == "aws_iam_role_policy":
            roles.setdefault(a["role"], {"attached": [], "inline": {}})
            roles[a["role"]]["inline"][a["name"]] = policy_body(addr)
        elif t == "aws_iam_role_policy_attachment":
            roles.setdefault(a["role"], {"attached": [], "inline": {}})
            roles[a["role"]]["attached"].append(policy_key(addr))
        elif t == "aws_s3_bucket":
            buckets.append(a["bucket"])
        elif t == "aws_kms_key":
            keys.append(a["description"])
    for r in roles.values():
        r["attached"].sort()
    return {"account": account, "roles": roles, "policies": policies,
            "buckets": sorted(buckets), "kms_keys": sorted(keys)}


def load(branch_dir):
    d = pathlib.Path(branch_dir)
    return {root: summarise(json.load(open(d / f"{root}.plan.json"))) for root in ROOTS}


def dump(summary):
    return json.dumps(summary, indent=2, sort_keys=True) + "\n"


def role_arn(account, name):
    return f"arn:aws:iam::{account}:role/{name}"


def paths(summary):
    """Enumerate sts:AssumeRole paths between roles managed in the repo.

    Edges come from trust policies (target's perspective, inverted). An edge
    whose statement carries a Condition is marked conditional.
    """
    arn_to_role = {}
    for root in ROOTS:
        acct = summary[root]["account"]
        for name in summary[root]["roles"]:
            arn_to_role[role_arn(acct, name)] = f"{root}:{name}"
    edges = {}
    for root in ROOTS:
        acct = summary[root]["account"]
        for name, r in summary[root]["roles"].items():
            if r.get("trust") in (None, UNRESOLVED):
                continue
            for s in r["trust"]:
                s = json.loads(s)
                if s.get("Effect") != "Allow":
                    continue
                for p in s.get("Principal", {}).get("AWS", []):
                    if p in arn_to_role:
                        edges.setdefault(arn_to_role[p], []).append(
                            (f"{root}:{name}", "Condition" in s))
    out = []

    def dfs(node, path, conditional):
        for nxt, cond in sorted(edges.get(node, [])):
            if nxt in path:
                continue
            p = path + [nxt]
            out.append((p, conditional or cond))
            dfs(nxt, p, conditional or cond)

    for start in sorted(arn_to_role.values()):
        dfs(start, [start], False)
    return out


def main(argv):
    if argv and argv[0] == "--paths":
        for p, cond in paths(load(argv[1])):
            print(("conditional " if cond else "confirmed   ") + " -> ".join(p))
        return 0
    if len(argv) == 1:
        sys.stdout.write(dump(load(argv[0])))
        return 0
    a, b = dump(load(argv[0])), dump(load(argv[1]))
    diff = list(difflib.unified_diff(a.splitlines(), b.splitlines(), argv[0], argv[1], lineterm=""))
    if not diff:
        print(f"IDENTICAL effective permissions: {argv[0]} == {argv[1]}")
        return 0
    print("\n".join(diff))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
