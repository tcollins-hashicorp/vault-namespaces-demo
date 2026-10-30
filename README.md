# Vault Enterprise namespaces demo

A single-node Vault Enterprise instance on Podman (or Docker) with four namespaces already built, plus a four-step guided walkthrough. It shows what a namespace is, how children pick up a login point from their parent, how an unrelated namespace stays sealed off, and the three ways to grant access across a namespace boundary.

Everything is a demo setting: TLS is off, one unseal key, root token written to disk. Do not copy any of it into a production cluster.

## What a namespace is

A namespace is a sub-tree of the Vault API that behaves like its own small Vault. It has its own auth methods, secrets engines, ACL and Sentinel policies, entities, groups and tokens. HashiCorp calls this secure multi-tenancy. The parent of every namespace is the `root` namespace, which is the Vault you get without the feature.

Three things make namespaces work the way they do:

1. **Paths are relative.** A request for `secret/foo` with the header `X-Vault-Namespace: platform/team-a` and a request for `team-a/secret/foo` with `X-Vault-Namespace: platform` both reach `platform/team-a/secret/foo`. Policies follow the same rule, so a policy written in `platform/` can name `team-a/*` and reach into the child.
2. **Tokens travel down, never up or sideways.** A token issued in `platform/` can be used in `platform/team-a`. It cannot be used in `finance/`, and a `finance/` token cannot be used in `platform/`. Vault does not even look the token up outside its own sub-tree.
3. **Groups can hold entities from ancestor namespaces.** A group in `platform/team-a` can list an entity that lives in `platform/`. When that entity's token makes a request in `team-a`, Vault adds the group's policies for that request. `vault token lookup` shows them under `external_namespace_policies`.

Docs: [Namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces), [namespace CLI](https://developer.hashicorp.com/vault/docs/commands/namespace), [namespaces API](https://developer.hashicorp.com/vault/api-docs/system/namespaces), [namespaces in the UI](https://developer.hashicorp.com/vault/docs/ui/namespaces).

## When to use them

HashiCorp's own guidance is to use namespaces sparingly. A namespace marks an administrative boundary. Create one when a tenant needs to run its own Vault: write its own policies, mount its own engines, manage its own identities, and be audited as a unit. Examples are a business unit with its own security team, a subsidiary, a regulated workload that must show separation, or an external customer on a shared cluster.

Do not create one per application or per team that only needs a place to put secrets. ACL policies on paths, dedicated mounts and templated policies cover that with far less overhead, and an onboarding layer (Terraform plus a `platform/` namespace that holds shared auth) scales better than hundreds of small namespaces.

Docs: [Best practices for namespaces and mount paths](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-structure), [Running Vault with many namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/namespace-limits), [How to use Vault namespaces (blog)](https://www.hashicorp.com/blog/how-to-use-vault-namespaces).

## Pros and cons

| For | Against |
|---|---|
| Tenants administer themselves. A delegated admin in `platform/` can create children, policies and mounts without a root-namespace operator. | Namespaces are Enterprise and HCP Vault Dedicated only. |
| Hard isolation between unrelated tenants: no shared auth, identity or policy. A mistake in `finance/` cannot leak into `platform/`. | Every namespace costs storage. Each one starts with three mounts (auth, identity, system) and the whole namespace list must fit in one storage entry. Mount tables are capped at 1 MB on integrated storage. |
| One cluster, one set of unseal keys, one licence, one audit pipeline. | Audit, seal, rekey and several other `sys/` paths stay root-only. An administrative namespace gets a subset. |
| Policies and identities in a parent reach down into the children, so shared services (a company Kubernetes auth, an LDAP mount) live once in a parent. | Nothing reaches up or sideways. Sharing across unrelated namespaces needs a global switch (`group_policy_application_mode=any`) or a copy of the secret. |
| Path-relative design means a tenant's scripts and policies do not care where in the tree they sit. | Every client, agent and CI job must set the namespace on every request. Forgetting it gives confusing 403s. `chroot_namespace` on a listener helps for single-tenant endpoints. |
| Metadata on namespaces and namespace-aware audit entries make per-tenant reporting easier. | Nested trees get hard to reason about. Three levels is usually the practical limit. |

Docs: [restricted API paths](https://developer.hashicorp.com/vault/docs/enterprise/namespaces#restricted-api-paths), [create an administrative namespace](https://developer.hashicorp.com/vault/docs/enterprise/namespaces/create-admin-namespace), [Vault limits and maximums](https://developer.hashicorp.com/vault/docs/internals/limits#namespace-limits).

## What the environment builds

```
root
├── platform/                 userpass; entities alice, bob, carol; policy platform-admin
│   ├── team-a/               kv-v2 at secret/; policy team-a-kv; group team-a-devs (alice)
│   └── team-b/               kv-v2 at secret/; policy team-b-kv; group team-b-devs (bob)
└── finance/                  userpass; entity frank; kv-v2 at secret/; group finance-readers
```

Users `alice`, `bob`, `carol` (in `platform/`) and `frank` (in `finance/`) share the password `demo-password`. Entity and accessor IDs are written to `/vault/data/demo.env` inside the container for the walkthrough scripts.

The provisioning lives in `vault/scripts/provision.d/20-namespaces.sh`. It runs once, on first init, after the base image has unsealed and seeded the root-namespace KV at `secret/`.

## Run it

1. Put your Vault Enterprise licence in this directory as `vault-NFR2.0.hclic`. If the file has another name, change the left side of the licence mount in `docker-compose.yml`. Without a licence the container starts and then exits.
2. Build and start:

   ```sh
   podman compose up -d --build
   podman compose logs -f vault
   ```

   Docker users: `docker compose` takes the same arguments, and `CONTAINER_CLI=docker ./demo.sh` for the walkthrough. On an SELinux host the bind mounts carry a `z` flag already.

3. Wait for the `Vault Demo — Ready` box in the log, then run the walkthrough:

   ```sh
   ./demo.sh 1        # tour of the tree
   ./demo.sh 2        # shared auth, inherited by the children
   ./demo.sh 3        # finance/ is a separate tenant
   ./demo.sh 4        # cross-namespace permissions
   ./demo.sh all      # the lot
   PAUSE=0 ./demo.sh all   # no prompts, for a dry run
   ```

   Each script runs inside the container, prints every command before running it, and marks the result `allowed` or `denied`. The denials are the point, so the scripts do not stop on them.

4. The UI is at <http://localhost:8200>. Log in with the root token (`podman exec vault-demo cat /vault/data/.root_token`) and use the namespace picker top left, or open a namespace directly, for example <http://localhost:8200/ui/vault/secrets?namespace=platform%2Fteam-a>. To log in as a user, pick the namespace first, then the Username tab.

Reset to a clean build with `podman compose down -v && podman compose up -d --build`. The `-v` wipes `vault/data`, which is what makes provisioning run again.

## The walkthrough, step by step

### 1. Tour

Lists the namespaces, then shows `auth list` in `platform/`, `platform/team-a` and `finance/`. The children have no auth mount of their own. It finishes by reading the `team-a-devs` group so the audience sees a member entity ID that was created one level up.

### 2. Auth inherited by the children

`alice` logs in once, against the userpass mount in `platform/`. Her token has only the `default` policy at that point. The same token then reads and writes `secret/` in `platform/team-a`, and `token lookup` run in that namespace shows `team-a-kv` under `external_namespace_policies`. The same token is denied in `platform/team-b`, because team-b's group does not list her.

Then `carol` shows the other direction. Her policy, `platform-admin`, is written in `platform/` and contains `path "team-a/*"` and `path "team-b/*"`. Vault evaluates those relative to `platform/`, so she can read both children with no group in either.

The two approaches put the decision with different owners. A group in the child means the child's admin decides. A path-prefixed policy in the parent means the platform team decides.

Docs: [Secure multi-tenancy with namespaces](https://developer.hashicorp.com/vault/tutorials/enterprise/namespaces) (the `education/training` example this step mirrors), [identity concepts](https://developer.hashicorp.com/vault/docs/concepts/identity), [policies](https://developer.hashicorp.com/vault/docs/concepts/policies).

### 3. Segregation

`alice`'s token is tried in `finance/` and fails before any policy check, because `finance/` is outside her token's sub-tree. `frank` logs in to `finance/`, reads the ledger, and is then denied in `platform/` and `platform/team-a` the same way. Finally the root token reads both, which is the one thing to remember about isolation: every namespace is below `root`, so a root-namespace operator sees everything.

### 4. Cross-namespace permissions

Three mechanisms, in rising order of blast radius.

1. **Path prefix in a parent policy.** Already shown with `carol` in step 2. Scope is whatever paths the parent names.
2. **Group in the target namespace, entity from an ancestor.** `alice` is added to `team-b-devs` and, with no new login, can read `team-b` secrets. Scope is one group's policies in one namespace, and the child's admin controls it.
3. **Group in an unrelated namespace.** `finance-readers` cannot help `alice` by default because `finance/` and `platform/` share no ancestor below root. The script sets `sys/config/group-policy-application` to `any`, adds `alice` to the group, and the read succeeds. It then sets the mode back to `within_namespace_hierarchy` and the read is denied again. The setting is cluster-wide and replicates to secondaries, so treat it as a platform decision rather than a per-tenant one. It affects ACL policies only.

The script restores the original group memberships and the default mode when it exits, so step 4 can be rerun.

Docs: [Secrets management across namespaces without a hierarchical relationship](https://developer.hashicorp.com/vault/tutorials/enterprise/namespaces-secrets-sharing), [`sys/config/group-policy-application`](https://developer.hashicorp.com/vault/api-docs/system/config-group-policy-application).

## Files

```
docker-compose.yml                       Vault service, licence and data mounts
demo.sh                                  host-side runner for the walkthrough
vault/Dockerfile                         hashicorp/vault-enterprise + curl, jq, bash
vault/config/vault.hcl                   single-node Raft, TLS off, UI on
vault/scripts/vault-entrypoint.sh        init, unseal, seed, run provision.d/
vault/scripts/provision.d/20-namespaces.sh
vault/scripts/demo/00-lib.sh             helpers shared by the steps
vault/scripts/demo/01-tour.sh
vault/scripts/demo/02-inherited-auth.sh
vault/scripts/demo/03-segregation.sh
vault/scripts/demo/04-cross-namespace.sh
```

`vault/data/` appears at runtime. Keep it out of version control; it holds the unseal key, the root token and `demo.env`.
