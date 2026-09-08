<!--
SPDX-FileCopyrightText: 2025 spatterlight

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Headplane Ansible role

This is an [Ansible](https://www.ansible.com/) role which installs [Headplane](https://github.com/tale/headplane) to run as a [Docker](https://www.docker.com/) container wrapped in a systemd service.

This role *implicitly* depends on:

- [`com.devture.ansible.role.playbook_help`](https://github.com/devture/com.devture.ansible.role.playbook_help)
- [`com.devture.ansible.role.systemd_docker_base`](https://github.com/devture/com.devture.ansible.role.systemd_docker_base)

Check [`defaults/main.yml`](defaults/main.yml) for the full list of supported options.

💡 For an Ansible playbook which integrates this role and makes it easier to use, see the [Mother-of-All-Self-Hosting Ansible playbook](https://github.com/mother-of-all-self-hosting/mash-playbook).

## Public URL

Headplane 0.7 uses `server.base_url` to construct OIDC login callback URLs. The role sets it to `https://{{ headplane_hostname }}` by default.

To use a different public URL, override `headplane_config_server_base_url`, for example:

```yaml
headplane_config_server_base_url: "https://headplane.example.com:8443"
```

For example, if you open the dashboard at `https://headplane.example.com/admin`, set the base URL to `https://headplane.example.com`. Headplane constructs the login callback URL as `https://headplane.example.com/admin/oidc/callback`.

An existing `server.base_url` setting in `headplane_configuration_extension_yaml` continues to override the role variable. If you set `HEADPLANE_SERVER__BASE_URL` through `headplane_environment_variables_additional_variables`, update or remove it when changing the public URL. Headplane applies environment variables after its YAML configuration, so this setting overrides both the role variable and configuration extension.

The standard Headplane image builds callbacks at `/admin/oidc/callback`. Adding a path to `server.base_url` does not relocate that route; deployments beneath an additional URL prefix need matching application and proxy routing.

When upgrading from Headplane 0.6, note that Headplane 0.7 no longer derives the OIDC callback URL from `oidc.redirect_uri` or request headers. If you used `oidc.redirect_uri` to select a different public origin, set `headplane_config_server_base_url` to that origin instead, without the dashboard or callback path.

## Development

### pre-commit

You can optionally install a Git pre-commit hook (via [mise](https://mise.jdx.dev/) + [prek](https://prek.j178.dev/)) that runs formatting and linting checks before each commit. See [`.pre-commit-config.yaml`](./.pre-commit-config.yaml) for which hooks are to be executed.

To install the hook, run the [`just`](https://github.com/casey/just) command below:

```sh
just prek-install-git-pre-commit-hook
```

### Molecule

This role supports [Molecule](https://docs.ansible.com/projects/molecule/), an Ansible testing framework designed for developing and testing Ansible collections, playbooks, and roles.

Refer to [this page](./molecule/README.md) for details about how to utilize it.
