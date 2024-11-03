SERVICE_NAME=simple-python-service2
SERVICE_TITLE=Simple Image Analysis Service
PROVIDER_NAME=ivcap.test

SERVICE_FILE=img_analysis_service.py

SERVICE_ID:=urn:ivcap:service:$(shell python3 -c 'import uuid; print(uuid.uuid5(uuid.NAMESPACE_DNS, \
        "${PROVIDER_NAME}" + "${SERVICE_NAME}"));')

GIT_COMMIT := $(shell git rev-parse --short HEAD)
GIT_TAG := $(shell git describe --abbrev=0 --tags ${TAG_COMMIT} 2>/dev/null || true)
VERSION="${GIT_TAG}|${GIT_COMMIT}|$(shell date -Iminutes)"

DOCKER_USER="$(shell id -u):$(shell id -g)"
DOCKER_DOMAIN=$(shell echo ${PROVIDER_NAME} | sed -E 's/[-:]/_/g')
DOCKER_NAME=$(shell echo ${SERVICE_NAME} | sed -E 's/-/_/g')
DOCKER_VERSION=${GIT_COMMIT}
DOCKER_TAG=${DOCKER_NAME}:${DOCKER_VERSION}
DOCKER_TAG_LOCAL=${DOCKER_NAME}:latest
TARGET_PLATFORM := linux/amd64

PROJECT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
DATA_DIR=${PROJECT_DIR}/DATA
RUN_DIR = ${DATA_DIR}/RUN
TMP_DIR=/tmp

TEST_IMG_DIR=${PROJECT_DIR}/examples
TEST_IMG_COLLECTION=urn:ivcap:artifact:7797dfa5-a240-4c6b-bb34-f7bd24b163d8 # urn:ibenthos:collection:max-test-1

run:
	mkdir -p ${RUN_DIR} && rm -rf ${RUN_DIR}/*
	python ${SERVICE_FILE} \
		--images ${TEST_IMG_DIR} \
		--ivcap:out-dir ${RUN_DIR}
	@echo ">>> Output should be in '${RUN_DIR}'"

build:
	pip install -r requirements.txt

docker-run: #docker-build
	@echo ""
	@echo ">>>>>>> On Mac, please ensure that this directory is mounted into minikube (if that's what you are using)"
	@echo ">>>>>>>    minikube mount ${PROJECT_DIR}:${PROJECT_DIR}"
	@echo ""
	mkdir -p ${RUN_DIR} && rm -rf ${RUN_DIR}/*
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-e IVCAP_IN_DIR=/data/in \
		-e IVCAP_OUT_DIR=/data/out \
		-e IVCAP_CACHE_DIR=/data/cache \
		-v ${PROJECT_DIR}:/data/in \
		-v ${RUN_DIR}:/data/out \
		-v ${RUN_DIR}:/data/cache \
		--user ${DOCKER_USER} \
		${DOCKER_NAME} \
		--images /data/in/examples
	@echo ">>> Output should be in '${DOCKER_LOCAL_DATA_DIR}' (might be inside minikube)"

docker-debug: #docker-build
	# If running Minikube, the 'data' directory needs to be created inside minikube
	mkdir -p ${DOCKER_LOCAL_DATA_DIR}/in ${DOCKER_LOCAL_DATA_DIR}/out
	docker run -it \
		-e IVCAP_INSIDE_CONTAINER="" \
		-e IVCAP_ORDER_ID=ivcap:order:0000 \
		-e IVCAP_NODE_ID=n0 \
		-v ${PROJECT_DIR}:/data\
		--entrypoint bash \
		${DOCKER_TAG_LOCAL}

docker-build:
	@echo "Building docker image ${DOCKER_NAME}"
	@echo "====> DOCKER_REGISTRY is ${DOCKER_REGISTRY}"
	@echo "====> LOCAL_DOCKER_REGISTRY is ${LOCAL_DOCKER_REGISTRY}"
	@echo "====> TARGET_PLATFORM is ${TARGET_PLATFORM}"
	DOCKER_BUILDKIT=1 docker build \
		-t ${DOCKER_TAG_LOCAL} \
		--platform=${TARGET_PLATFORM} \
		--build-arg GIT_COMMIT=${GIT_COMMIT} \
		--build-arg GIT_TAG=${GIT_TAG} \
		--build-arg BUILD_DATE="$(shell date)" \
		-f ${PROJECT_DIR}/Dockerfile \
		${PROJECT_DIR} ${DOCKER_BILD_ARGS}
	@echo "\nFinished building docker image ${DOCKER_TAG_LOCAL}\n"

docker-publish: docker-build
	@echo "Publishing docker image '${DOCKER_TAG}'"
	docker tag ${DOCKER_TAG_LOCAL} ${DOCKER_TAG}
	sleep 1
	$(eval size:=$(shell docker inspect ${DOCKER_TAG_LOCAL} --format='{{.Size}}' | tr -cd '0-9'))
	$(eval imageSize:=$(shell expr ${size} + 0 ))
	@echo "... imageSize is ${imageSize}"
	@if [ ${imageSize} -gt 2000000000 ]; then \
		set -e ; \
		echo "preparing upload from local registry"; \
		if [ -z "$(shell docker ps -a -q -f name=registry-2)" ]; then \
			echo "running local registry-2"; \
			docker run --restart always -d -p 8081:5000 --name registry-2 registry:2 ; \
		fi; \
		docker tag ${DOCKER_TAG} localhost:8081/${DOCKER_TAG} ; \
		docker push localhost:8081/${DOCKER_TAG} ; \
		$(MAKE) PUSH_FROM="localhost:8081/" docker-publish-common ; \
	else \
		$(MAKE) PUSH_FROM="--local " docker-publish-common; \
	fi

docker-publish-common:
	$(eval log:=$(shell ivcap package push --force ${PUSH_FROM}${DOCKER_TAG} | tee /dev/tty))
	$(eval registry := $(shell echo ${DOCKER_REGISTRY} | cut -d'/' -f1))
	$(eval SERVICE_IMG := $(shell echo ${log} | sed -E "s/.*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}.*) pushed/\1/"))
	@if [ "${SERVICE_IMG}" == "" ] || [ "${SERVICE_IMG}" == "${DOCKER_TAG}" ]; then \
		echo "service package push failed"; \
		exit 1; \
	fi
	@echo ">> Successfully published '${DOCKER_TAG}' as '${SERVICE_IMG}'"

service-description:
	$(eval image:=$(shell ivcap package list ${DOCKER_TAG}))
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${image} \
	python ${SERVICE_FILE} --ivcap:print-service-description

service-register: docker-publish
	$(eval image:=$(shell ivcap package list ${DOCKER_TAG}))
	env IVCAP_SERVICE_ID=${SERVICE_ID} \
		IVCAP_PROVIDER_ID=$(shell ivcap context get provider-id) \
		IVCAP_ACCOUNT_ID=$(shell ivcap context get account-id) \
		IVCAP_CONTAINER=${image} \
	python ${SERVICE_FILE} --ivcap:print-service-description \
	| ivcap service update --create ${SERVICE_ID} --format yaml -f - --timeout 600

clean:
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).dist
	rm -rf ${PROJECT_DIR}/$(shell echo ${SERVICE_FILE} | cut -d. -f1 ).build
	rm -rf ${PROJECT_DIR}/cache ${PROJECT_DIR}/DATA

### IGNORE - ONLY USED BY IVCAP CORE TEAM FOR INTERNAL TESTING

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
		${DOCKER_TAG} \
	  --images urn:ivcap:artifact:78523710-86aa-4302-a842-63e1ea789909

run-data-proxy-collection:
	mkdir -p ${PROJECT_DIR}/DATA/in && rm -rf ${PROJECT_DIR}/DATA/in/*
	mkdir -p ${PROJECT_DIR}/DATA/out && rm -rf ${PROJECT_DIR}/DATA/out/*
	env PYTHONPATH=${PROJECT_DIR}/../../ivcap-sdk-python/ivcap-service-sdk-python/src \
	  IVCAP_INSIDE_CONTAINER="Yes" \
		IVCAP_ORDER_ID=urn:ivcap:order:0000 \
		IVCAP_NODE_ID=n0 \
		IVCAP_IN_DIR=${PROJECT_DIR}/DATA/in \
		IVCAP_OUT_DIR=${PROJECT_DIR}/DATA/out \
		IVCAP_CACHE_DIR=${PROJECT_DIR}/DATA/out \
		http_proxy=http://localhost:9999 \
		https_proxy=http://localhost:9999 \
	python ${PROJECT_DIR}/${SERVICE_FILE} \
		--images urn:ivcap:artifact:78523710-86aa-4302-a842-63e1ea789909
	@echo ">>> Output should be in '${RUN_DIR}'"

run-data-proxy-image:
	mkdir -p ${PROJECT_DIR}/DATA/in && rm -rf ${PROJECT_DIR}/DATA/in/*
	mkdir -p ${PROJECT_DIR}/DATA/out && rm -rf ${PROJECT_DIR}/DATA/out/*
	env PYTHONPATH=${PROJECT_DIR}/../../ivcap-sdk-python/ivcap-service-sdk-python/src \
	  IVCAP_INSIDE_CONTAINER="Yes" \
		IVCAP_ORDER_ID=urn:ivcap:order:0000 \
		IVCAP_NODE_ID=n0 \
		IVCAP_IN_DIR=${RUN_DIR} \
		IVCAP_OUT_DIR=${PROJECT_DIR}/DATA/out \
		IVCAP_CACHE_DIR=${PROJECT_DIR}/DATA/in \
		http_proxy=http://localhost:9999 \
		https_proxy=http://localhost:9999 \
	python ${PROJECT_DIR}/${SERVICE_FILE} \
		--images urn:ivcap:artifact:78523710-86aa-4302-a842-63e1ea789909 \
	@echo ">>> Output should be in '${RUN_DIR}'"

FORCE:
.PHONY: run