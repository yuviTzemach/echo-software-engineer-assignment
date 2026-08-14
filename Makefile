NGINX_VERSION ?= 1.25.5
DEB_REVISION  ?= 1~bookworm
IMAGE_NAME    ?= nginx-patched
IMAGE_TAG     ?= 1.25-bookworm

.PHONY: deb image test clean

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

clean:
	rm -rf build/output
