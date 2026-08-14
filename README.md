# Echo Software Engineer Assignment

## Vulnerability Analysis & CVE Selection

After running the baseline security scans on `nginx:1.25-bookworm` (`baseline-trivy.txt`, `baseline-grype.txt`), I selected two key vulnerabilities to fix using two different strategies:

| CVE ID | Package | Severity | Fix Method | Current Version | Fixed Version | Risk & Description | Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CVE-2024-6119** | `openssl` / `libssl3` | **High** | Version bump | `3.0.11-1~deb12u2` | `3.0.14-1~deb12u2` | Memory read issue in OpenSSL certificate validation that can crash the service (DoS). An official updated package is available. | [Debian security tracker](https://security-tracker.debian.org/tracker/CVE-2024-6119) |
| **CVE-2026-42533** | `nginx` | **Critical** (CVSS 9.2) | Backport patch | `1.25.5-1~bookworm` | Fixed only in 1.30.4+ / 1.31.3+ | Buffer overflow in Nginx regex handling that can cause worker crashes or code execution. No official fix exists for version 1.25.x, requiring a manual source patch. | [nginx security advisories](https://nginx.org/en/security_advisories.html), patches in `build/patches/` |

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
| `nginx:1.25-bookworm` | 276MB |
| `nginx-patched:1.25-bookworm` | 142MB |

## Compatibility test

`make test` boots `nginx:1.25-bookworm` and `nginx-patched:1.25-bookworm`, sends the same requests to both, and fails if status / body / headers differ (`Date` is ignored because it changes every request).

Covers: `GET /`, a 404, `HEAD /`, a 256KiB POST, a 2MiB POST (over nginx's default `client_max_body_size`), a malformed HTTP/1.1 request with no Host header, and the same two GETs against a custom `conf.d` file.

## Rescan / VEX

Scanners key off package name + version. After a backport the nginx package is still `1.25.5`, so they keep reporting CVE-2026-42533 even though the code is patched. OpenSSL is a real version bump, so CVE-2024-6119 should actually disappear.

```bash
make scan
make scan-vex
```

The VEX file tells Trivy/Grype the backport is `fixed`. After `make scan-vex`, CVE-2026-42533 should drop out of the report.

## Residual risk

This image is not "clean".
I picked two CVEs and stopped there, like the assignment asked.

OpenSSL is on 3.0.14, which kills CVE-2024-6119, but later OpenSSL bugs are still in there. 
nginx is still 1.25.5 — I patched CVE-2026-42533 in the source, not the other nginx issues on that version. 
There's also a pile of Debian packages I never touched.

If I had to keep going I'd bump OpenSSL again, and either patch more of nginx or just move off 1.25.

## What surprised me

I'm a full stack developer, so a lot of this was new. What surprised me most was that patching nginx in source didn't make CVE-2026-42533 disappear from the scanner. They match on package + version, so a backport needs VEX.

With more time I'd try the third remediation the brief mentions — removing a component — on something we don't actually need, and see how that compares to a bump or a backport.

## AI usage

I used Cursor and Claude a lot, but I also spent a lot of time reading. Most of this was new to me.
The tools drafted a lot of the code. I still had to understand it, run the builds/scans/tests, and change things when they were wrong.

Where it helped: matching the official nginx image layout, OpenVEX syntax, and the compatibility test.

Where it hurt: I asked it to pick the CVEs. The first suggestion didn't even meet the brief (you need a version bump *and* a backport). I had to throw that out and choose again. Same kind of thing on the README — it wrote too much, and some commands weren't valid (for example, `docker images` with two names). So I treated it as a starting point, not as the final call.