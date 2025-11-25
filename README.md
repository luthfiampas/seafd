# Seafd

A dockerized [Seafile client for a CLI server](https://help.seafile.com/syncing_client/linux-cli/), inspired by [flrnnc/docker-seafile-client](https://gitlab.com/flrnnc-oss/docker-seafile-client). It supports syncing multiple accounts and libraries, including password-protected libraries and TOTP-based 2FA.

## Current limitations

Seafile's 2FA does not accept reused TOTP tokens, even if they are still valid within the time window. As a workaround, the script waits for a new TOTP code before syncing each library. See: [haiwen/seafile#2939](https://github.com/haiwen/seafile/issues/2939)

## Environment variables

Each account is prefixed with `SEAFD_ACCOUNT_<IDENTIFIER>`, where `<IDENTIFIER>` is a label (e.g., `ACC1`, `ACC2`) that determines the account's directory path (e.g., `/seafd/acc1`). Each library under an account also uses a unique `<IDENTIFIER>`, which becomes a lowercase subdirectory within the account's `libraries` folder (e.g., `/seafd/acc1/libraries/work`).

> ⚠️ Use only letters and digits (a-z, 0-9) for all identifiers to ensure correct parsing.

| Variable                                                | Purpose                                                              |
| :------------------------------------------------------ | :------------------------------------------------------------------- |
| `SEAFD_ACCOUNT_<IDENTIFIER>`                            | **\*** Account username or email (can be anything when using token). |
| `SEAFD_ACCOUNT_<IDENTIFIER>_TOKEN`                      | **\*** Account web API token (if not using password).                |
| `SEAFD_ACCOUNT_<IDENTIFIER>_PASSWORD`                   | **\*** Account password (if not using token).                        |
| `SEAFD_ACCOUNT_<IDENTIFIER>_URL`                        | **\*** Seafile instance base URL.                                    |
| `SEAFD_ACCOUNT_<IDENTIFIER>_2FA_SECRET`                 | TOTP secret for 2FA-enabled accounts.                                |
| `SEAFD_ACCOUNT_<IDENTIFIER>_SKIP_CERT`                  | Set to `true` to skip SSL certificate verification.                  |
| `SEAFD_ACCOUNT_<IDENTIFIER>_DOWNLOAD_SPEED`             | Download rate limit in bytes/sec.                                    |
| `SEAFD_ACCOUNT_<IDENTIFIER>_UPLOAD_SPEED`               | Upload rate limit in bytes/sec.                                      |
| `SEAFD_ACCOUNT_<IDENTIFIER>_LIBS_<IDENTIFIER>`          | **\*** Seafile library GUID.                                         |
| `SEAFD_ACCOUNT_<IDENTIFIER>_LIBS_<IDENTIFIER>_PASSWORD` | Password for that specific library (if protected).                   |

## Directory structure

Each account defined in the environment will be assigned a dedicated configuration directory inside the mounted volume. This ensures that multiple accounts remain isolated, each with its own sync state, logs, and credentials. Here's a typical layout:

```
seafd
├── acc1
│   ├── config/ (seaf-cli config and logs)
│   ├── libraries/
│   │   ├── notes/ (synced library 'notes')
│   │   └── secured/ (synced password-protected library 'secured')
│   └── seafile-data/ (internal sync data, like storage, commits, fs, etc.)
└── acc2
    ├── config/
    ├── libraries/
    │   ├── library1/
    │   └── library2/
    └── seafile-data/
```

## Usage example

```yaml
services:
  seafd:
    container_name: seafd
    image: luthfiampas/seafd:latest
    restart: unless-stopped
    volumes:
      - ./seafd:/seafd
    environment:
      # Account 1
      SEAFD_ACCOUNT_ACC1: "<username-or-email>"
      SEAFD_ACCOUNT_ACC1_PASSWORD: "<seafile-password>"
      SEAFD_ACCOUNT_ACC1_URL: "https://seafile.example.com"
      SEAFD_ACCOUNT_ACC1_2FA_SECRET: "<totp-secret>"
      SEAFD_ACCOUNT_ACC1_DOWNLOAD_SPEED: 5242880
      SEAFD_ACCOUNT_ACC1_UPLOAD_SPEED: 5242880
      SEAFD_ACCOUNT_ACC1_SKIP_CERT: "false"
      SEAFD_ACCOUNT_ACC1_LIBS_WORK: "e1000e58-aaaa-bbbb-cccc-deadbeef0001"
      SEAFD_ACCOUNT_ACC1_LIBS_WORK_PASSWORD: "secret"
      SEAFD_ACCOUNT_ACC1_LIBS_NOTES: "e1000e58-ffff-bbbb-cccc-deadbeef0002"

      # Account 2
      SEAFD_ACCOUNT_ACC2: "<another-account>"
      SEAFD_ACCOUNT_ACC2_TOKEN: "<web-api-token>"
      SEAFD_ACCOUNT_ACC2_URL: "https://another-seafile-instance.com"
      SEAFD_ACCOUNT_ACC2_DOWNLOAD_SPEED: 5242880
      SEAFD_ACCOUNT_ACC2_UPLOAD_SPEED: 5242880
      SEAFD_ACCOUNT_ACC2_SKIP_CERT: "false"
      SEAFD_ACCOUNT_ACC2_LIBS_LIBRARY1: "f2000e58-aaaa-2222-cccc-deadbeef0003"
      SEAFD_ACCOUNT_ACC2_LIBS_LIBRARY1_PASSWORD: "secretpass"
      SEAFD_ACCOUNT_ACC2_LIBS_LIBRARY2: "f2000e58-bbbb-3333-cccc-deadbeef0004"

    networks:
      - seafd-network

networks:
  seafd-network:
    name: seafd-network
```
