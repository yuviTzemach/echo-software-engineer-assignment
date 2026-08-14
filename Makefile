NGINX_VERSION ?= 1.25.5
DEB_REVISION  ?= 1~bookworm
IMAGE_NAME    ?= nginx-patched
IMAGE_TAG     ?= 1.25-bookworm
IMAGE         := $(IMAGE_NAME):$(IMAGE_TAG)
VEX           := vex/CVE-2026-42533.openvex.json

.PHONY: deb image test scan scan-vex clean

deb:
	docker build \
		--build-arg NGINX_VERSION=$(NGINX_VERSION) \
		--build-arg DEB_REVISION=$(DEB_REVISION) \
		--target export \
		--output type=local,dest=build/output \
		build/

image: deb
	docker build \
		--build-arg NGINX_VERSION=$(NGINX_VERSION) \
		--build-arg DEB_REVISION=$(DEB_REVISION) \
		-f Containerfile \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		.

test:
	python3 test/test.py

scan:
	trivy image $(IMAGE) > patched-trivy.txt
	grype $(IMAGE) > patched-grype.txt
	@echo ""
	@echo "=== CVE-2024-6119 (OpenSSL bump — should be gone) ==="
	@grep CVE-2024-6119 patched-trivy.txt patched-grype.txt || echo "not found (good)"
	@echo ""
	@echo "=== CVE-2026-42533 (backport — scanners still flag the old version) ==="
	@grep CVE-2026-42533 patched-trivy.txt patched-grype.txt || echo "not found"

scan-vex:
	trivy image --vex $(VEX) $(IMAGE) > patched-trivy-vex.txt
	grype $(IMAGE) --vex $(VEX) > patched-grype-vex.txt
	@echo ""
	@echo "=== CVE-2026-42533 after VEX (should be gone) ==="
	@grep CVE-2026-42533 patched-trivy-vex.txt patched-grype-vex.txt || echo "not found (good)"

clean:
	rm -rf build/output
