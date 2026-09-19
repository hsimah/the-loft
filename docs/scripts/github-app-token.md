# GitHub App installation tokens

[github-app-token.sh](../../control-plane/github-app-token.sh) sources `/etc/loft/deploy.env` (or `LOFT_DEPLOY_ENV`), signs a short-lived RS256 JWT with OpenSSL, exchanges it for an installation token and prints the token without a newline. [deploy-pull.sh](deploy-pull.md) invokes it as a subprocess. Dependencies: OpenSSL, curl and jq.

## One-time setup

Create a GitHub App for this account with webhooks disabled and repository **Contents: Read** permission. Install it on only the release-source repositories. Record its App ID, installation ID and generated private key. See [GitHub's installation-authentication guide](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation).

On the deploying host, place the PEM at `/etc/loft/loft-deploy-app.pem` and create `/etc/loft/deploy.env`:

```bash
LOFT_DEPLOY_APP_ID=<app-id>
LOFT_DEPLOY_INSTALLATION_ID=<installation-id>
LOFT_DEPLOY_KEY_PATH=/etc/loft/loft-deploy-app.pem
```

Both files should be owned by root with mode 600. The env file is sourced as shell code, so keep it administrator-controlled.

Verify repository access without printing the token:

```bash
TOKEN="$(sudo /srv/the-loft/control-plane/github-app-token.sh)" && \
  curl -fsS -H "Authorization: Bearer $TOKEN" \
    -H 'Accept: application/vnd.github+json' \
    https://api.github.com/installation/repositories | jq -r '.repositories[].full_name'
unset TOKEN
```

## Failure contract

| Condition | Result |
|---|---|
| Required variable unset/empty | Silent nonzero exit |
| PEM path missing | Error on stderr, exit 1 |
| Signing or HTTP failure | Tool error/nonzero exit; `set -e` stops execution |
| Successful HTTP response without a token | Script error with response, exit 1 |
| Success | Token on stdout; no caching |

For auth failures, check App/installation IDs, selected repos, key path and host clock. The deploy puller suppresses this helper's stderr and falls back to anonymous access, so run the helper through the verification command above to see its actual error.

For rotation, generate a new key, install it with the same restrictive permissions, verify access, then revoke the old key. The App and installation IDs stay the same. Do not paste private keys or tokens into tickets/logs.
