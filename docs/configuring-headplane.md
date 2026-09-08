<!--
SPDX-FileCopyrightText: 2026 QEDeD

SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Configuring Headplane

See [`defaults/main.yml`](../defaults/main.yml) for the full list of settings supported by this role.

## Headplane and Headscale compatibility

Headplane and Headscale have version-specific compatibility requirements. See the [Headplane release notes](https://github.com/tale/headplane/releases) and [Headplane agent documentation](https://headplane.net/features/agent) for the relevant upstream information.

## Enabling the Headplane agent

The optional Headplane agent periodically syncs information about the nodes in your Tailnet. It is disabled by default and requires a Headscale API key when enabled. If Headplane already uses one, you can reuse the same key. Otherwise, create one as described in [Headscale's API documentation](https://headscale.net/stable/ref/api/):

```yaml
headplane_config_integration_agent_enabled: true
headplane_config_headscale_api_key: "YOUR_HEADSCALE_API_KEY_HERE"
```

Treat the API key as a secret. It is not a pre-auth key: the agent uses it to create its own short-lived pre-auth keys. A pre-auth key cannot be used instead.

`headplane_config_integration_agent_tailscale_netns` defaults to `true`, preserving Headplane's default behavior. Setting it to `false` lets the agent use ordinary route selection. This is required for the agent in the typical [MASH](https://github.com/mother-of-all-self-hosting/mash-playbook/blob/main/docs/services/headplane.md) network topology.

### Upgrading custom agent configuration from Headplane 0.6

In Headplane 0.7, `integration.agent.cache_ttl` controls the interval between sync attempts in **milliseconds**. The default is `180000` (three minutes). Headplane 0.6.3 did not use this setting, despite including it in the example configuration.

If you set `cache_ttl` through `headplane_configuration_extension_yaml`, check its value before upgrading. An old example value of `60` now means 60 milliseconds. To request one-minute intervals, merge the following setting into your existing configuration extension, preserving its other settings:

```yaml
headplane_configuration_extension_yaml: |
  integration:
    agent:
      cache_ttl: 60000
```

The `integration.agent.cache_path` setting is deprecated and has no effect in Headplane 0.7. Remove it from your configuration extension. The agent's persistent working directory is still controlled by `integration.agent.work_dir`; its default, `/var/lib/headplane/agent`, is inside the data directory mounted by this role.
