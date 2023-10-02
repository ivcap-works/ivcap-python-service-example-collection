SERVICE_CONTAINER_NAME=simple-python-service2
SERVICE_TITLE=Simple Image Analysis Service

SERVICE_FILE=img_analysis_service.py

PROVIDER_NAME=ivcap.test

# don't foget to login 'az acr login --name cipmain'
AZ_DOCKER_REGISTRY=cipmain.azurecr.io
GKE_DOCKER_REGISTRY=australia-southeast1-docker.pkg.dev/reinvent-science-prod-2ae1/ivap-registry
MINIKUBE_DOCKER_REGISTRY=localhost:5000
DOCKER_REGISTRY=${GKE_DOCKER_REGISTRY}

SERVICE_ID:=ivcap:service:$(shell python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, \
        "${PROVIDER_NAME}" + "${SERVICE_CONTAINER_NAME}"));'):${SERVICE_CONTAINER_NAME}

GIT_COMMIT := $(shell git rev-parse --short HEAD)
GIT_TAG := $(shell git describe --abbrev=0 --tags ${TAG_COMMIT} 2>/dev/null || true)

DOCKER_NAME=$(shell echo ${SERVICE_CONTAINER_NAME} | sed -E 's/-/_/g')
DOCKER_VERSION=${GIT_COMMIT}
DOCKER_TAG=$(shell echo ${PROVIDER_NAME} | sed -E 's/[-:]/_/g')/${DOCKER_NAME}:${DOCKER_VERSION}
DOCKER_DEPLOY=${DOCKER_REGISTRY}/${DOCKER_TAG}

PROJECT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

TMP_DIR=/tmp

TEST_IMG_DIR=${PROJECT_DIR}/examples
TEST_IMG_COLLECTION=urn:ivcap:artifact:7797dfa5-a240-4c6b-bb34-f7bd24b163d8 # urn:ibenthos:collection:max-test-1

DOCKER_LOCAL_DATA_DIR=/tmp/DATA

# GITHUB_USER_HOST?=git@github.com
# SDK_CLONE_RELATIVE=.ivcap-sdk-python
# SDK_CLONE_ABSOLUTE=${PROJECT_DIR}/.ivcap-sdk-python
# SDK_COMMIT?=HEAD

# Check if DOCKER_REGISTRY is set to LOCAL_DOCKER_REGISTRY.
# If true, set TARGET_PLATFORM to linux/${GOARCH} to build for the local architecture.
# If false, set TARGET_PLATFORM to linux/amd64 as a default target platform.
ifeq ($(DOCKER_REGISTRY), $(LOCAL_DOCKER_REGISTRY))
TARGET_PLATFORM := linux/${GOARCH}
else
TARGET_PLATFORM := linux/amd64
endif

run:
	mkdir -p ${PROJECT_DIR}/DATA/run && rm -rf ${PROJECT_DIR}/DATA/run/*
	python ${SERVICE_FILE} \
		--images ${TEST_IMG_DIR} \
		--ivcap:out-dir ${PROJECT_DIR}/DATA/run
	@echo ">>> Output should be in '${PROJECT_DIR}/DATA'"

build:
	pip install -r requirements.txt

run-argo-url:
	make IMAGE_ARTIFACT=urn:${IMG_URL}

docker-run: #docker-build
	@echo ""
	@echo ">>>>>>> On Mac, please ensure that this directory is mounted into minikube (if that's what you are using)"
	@echo ">>>>>>>    minikube mount ${PROJECT_DIR}:${PROJECT_DIR}"
	@echo ""
	mkdir -p ${PROJECT_DIR}/DATA/run && rm -rf ${PROJECT_DIR}/DATA/run/*
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-v ${PROJECT_DIR}:/data/in \
		-v ${PROJECT_DIR}/DATA/run:/data/out \
		-v ${PROJECT_DIR}/DATA/run:/data/cache \
		${DOCKER_NAME} \
		--ivcap:in-dir /data/in \
		--ivcap:out-dir /data/out \
		--ivcap:cache-dir /data/cache \
		--msg "$(shell date "+%d/%m-%H:%M:%S")" \
		--background-img ${IMG_URL}
	@echo ">>> Output should be in '${DOCKER_LOCAL_DATA_DIR}' (might be inside minikube)"

docker-run-nuitka:
	make DOCKER_NAME=simple_python_service-nuitka docker-run

docker-debug: #docker-build
	# If running Minikube, the 'data' directory needs to be created inside minikube
	mkdir -p ${DOCKER_LOCAL_DATA_DIR}/in ${DOCKER_LOCAL_DATA_DIR}/out
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-v ${PROJECT_DIR}:/data\
		--entrypoint bash \
		${DOCKER_NAME}

docker-build:
	@echo "Building docker image ${DOCKER_NAME}"
	@echo "====> TARGET_PLATFORM is ${TARGET_PLATFORM}"
	docker build \
	  --platform=${TARGET_PLATFORM} \
		--build-arg GIT_COMMIT=${GIT_COMMIT} \
		--build-arg GIT_TAG=${GIT_TAG} \
		--build-arg BUILD_DATE="$(shell date)" \
		-t ${DOCKER_NAME} \
		-f ${PROJECT_DIR}/Dockerfile \
		${PROJECT_DIR} ${DOCKER_BILD_ARGS}
	@echo "\nFinished building docker image ${DOCKER_NAME}\n"

docker-build-nuitka:
	@echo "Building docker image ${DOCKER_NAME}"
	docker build \
		--build-arg GIT_COMMIT=${GIT_COMMIT} \
		--build-arg GIT_TAG=${GIT_TAG} \
		--build-arg BUILD_DATE="$(shell date)" \
		-t ${DOCKER_NAME}-nuitka \
		-f ${PROJECT_DIR}/Dockerfile.nuitka \
		${PROJECT_DIR} ${DOCKER_BILD_ARGS}
	@echo "\nFinished building docker image ${DOCKER_NAME}\n"

docker-publish: docker-build
	@echo "Building docker image ${DOCKER_NAME}"
	@echo "====> DOCKER_REGISTRY is ${DOCKER_REGISTRY}"
	@echo "====> DOCKER_TAG is ${DOCKER_TAG}"
	docker tag ${DOCKER_NAME} ${DOCKER_DEPLOY}
	docker push ${DOCKER_DEPLOY}

service-description:
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${DOCKER_DEPLOY} \
	python ${SERVICE_FILE} --ivcap:print-service-description

service-register: docker-publish
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${DOCKER_DEPLOY} \
	python ${SERVICE_FILE} --ivcap:print-service-description \
	| ivcap service update --create ${SERVICE_ID} --format yaml -f - --timeout 600

clean:
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).dist
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).build
	rm -rf ${PROJECT_DIR}/cache ${PROJECT_DIR}/DATA

### ONLY USED BY IVCAP CORE TEAM

docker-run-data-proxy: #docker-build
	rm -rf /tmp/order1
	mkdir -p /tmp/order1/in
	mkdir -p /tmp/order1/out
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="Yes" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-e http_proxy=http://192.168.68.118:9999 \
	  -e https_proxy=http://192.168.68.118:9999 \
		-e IVCAP_STORAGE_URL=http://artifact.local \
	  -e IVCAP_CACHE_URL=http://cache.local \
		${DOCKER_NAME} \
	  --msg "$(shell date "+%d/%m-%H:%M:%S")" \
		--background-img urn:${IMG_URL} \

run-data-proxy:
	mkdir -p ${PROJECT_DIR}/DATA/in && rm -rf ${PROJECT_DIR}/DATA/in/*
	mkdir -p ${PROJECT_DIR}/DATA/out && rm -rf ${PROJECT_DIR}/DATA/out/*
	env PYTHONPATH=${PROJECT_DIR}/../../ivcap-sdk-python/ivcap-service-sdk-python/src \
	  IVCAP_INSIDE_CONTAINER="Yes" \
		IVCAP_ORDER_ID=urn:ivcap:order:0000 \
		IVCAP_NODE_ID=n0 \
		IVCAP_IN_DIR=${PROJECT_DIR}/DATA/run \
		IVCAP_OUT_DIR=${PROJECT_DIR}/DATA/out \
		IVCAP_CACHE_DIR=${PROJECT_DIR}/DATA/in \
		http_proxy=http://localhost:9999 \
		https_proxy=http://localhost:9999 \
	python ${PROJECT_DIR}/${SERVICE_FILE} \
		--images ${TEST_IMG_COLLECTION} \
	@echo ">>> Output should be in '${PROJECT_DIR}/DATA/run'"

# IGNORE
run-max:
	mkdir -p ${PROJECT_DIR}/DATA/run && rm -rf ${PROJECT_DIR}/DATA/run/*
	env PYTHONPATH=${PROJECT_DIR}/../../ivcap-sdk-python/ivcap-service-sdk-python/src \
	python ${SERVICE_FILE} \
		--images ${TEST_IMG_DIR} \
		--ivcap:out-dir ${PROJECT_DIR}/DATA/run
	@echo ">>> Output should be in '${PROJECT_DIR}/DATA'"

FORCE:
