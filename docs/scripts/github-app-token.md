# github-app-token.sh

[github-app-token.sh](../../control-plane/github-app-token.sh) prints a GitHub App installation token (no newline) for [deploy-pull.sh](deploy-pull.md). Needs OpenSSL, curl and jq.

## Setup

Create a GitHub App with webhooks off and **Contents: Read**, installed only on release repos. On the host (both files root, mode 600):

```bash
# /etc/loft/deploy.env — sourced as shell
LOFT_DEPLOY_APP_ID=<app-id>
LOFT_DEPLOY_INSTALLATION_ID=<installation-id>
LOFT_DEPLOY_KEY_PATH=/etc/loft/loft-deploy-app.pem
```

Verify (deploy-pull hides this script's errors, so test it directly):

```bash
TOKEN="$(sudo /srv/the-loft/control-plane/github-app-token.sh)" && \
  curl -fsS -H "Authorization: Bearer $TOKEN" -H 'Accept: application/vnd.github+json' \
    https://api.github.com/installation/repositories | jq -r '.repositories[].full_name'
unset TOKEN
```

Failures: check App/installation IDs, selected repos, key path and host clock. To rotate, install a new key, verify, then revoke the old one; IDs don't change.
