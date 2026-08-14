# Echo Software Engineer Assignment - Yuval Tzemach

## Vulnerability Analysis & CVE Selection

After running the baseline security scans on `nginx:1.25-bookworm` (`baseline-trivy.txt`, `baseline-grype.txt`), I selected two key vulnerabilities to fix using two different strategies:

| CVE ID | Package | Severity | Fix Method | Current Version | Fixed Version | Risk & Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CVE-2024-6119** | `openssl` / `libssl3` | **High** | Version bump | `3.0.11-1~deb12u2` | `3.0.14-1~deb12u2` | Memory read issue in OpenSSL certificate validation that can crash the service (DoS). An official updated package is available. |
| **CVE-2026-42533** | `nginx` | **Critical** (CVSS 9.2) | Backport patch | `1.25.5-1~bookworm` | Fixed only in 1.30.4+ / 1.31.3+ | Buffer overflow in Nginx regex handling that can cause worker crashes or code execution. No official fix exists for version 1.25.x, requiring a manual source patch. |

### Why I Chose These CVEs

- **CVE-2026-42533 (Backport Patch):** This is a Critical vulnerability without an official fix for the Nginx 1.25.x branch. It represents a real-world scenario where upgrading the whole minor version isn't an option, so I manually backported the patch into our source code.
- **CVE-2024-6119 (Version Bump):** This is a High-severity OpenSSL issue with an existing Debian fix. Upgrading the package version during the build process provides a clean and effective solution.

## Build

Needs Docker (BuildKit) and `make`.

```bash
make image
```

That builds the patched `.deb` from source (`make deb`) and then the runtime image (`nginx-patched:1.25-bookworm`).

To run just one stage:

```bash
make deb                                          
docker build -f Containerfile -t nginx-patched:1.25-bookworm .
```

Smoke test:

```bash
docker run --rm -d -p 8080:80 --name patched nginx-patched:1.25-bookworm
curl -I http://localhost:8080
docker stop patched
```

## Image size

| Image | Size |
| :--- | :--- |
| `nginx:1.25-bookworm` | 273MB |
| `nginx-patched:1.25-bookworm` | 142MB |