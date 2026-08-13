# Echo Software Engineer Assignment - Yuval Tzemach

## Vulnerability Analysis & CVE Selection

After running the baseline security scan on `nginx:1.25-bookworm`, I selected two critical vulnerabilities to fix:

| CVE ID | Package | Severity | Installed Version | Fixed Version | Risk & Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CVE-2024-45491** | `libexpat1` | **CRITICAL** | `2.5.0-1` | `2.5.0-1+deb12u1` | Integer overflow in XML parsing library |
| **CVE-2024-37371** | `libkrb5-3` | **CRITICAL** | `1.20.1-2+deb12u1` | `1.20.1-2+deb12u2` | Security flaw in Kerberos authentication tokens |

### Why I chose these CVEs
- **High Security Risk:** Both vulnerabilities are marked as **CRITICAL**, which means they pose a high security risk to the container.
- **Easy to Fix:** Both packages have updated versions available in the Debian repository, so we can fix them directly during the build process.