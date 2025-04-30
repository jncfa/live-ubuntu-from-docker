#!/bin/bash

cleanup_stack=()

add_cleanup(){
    cleanup_stack+=("$*")
}
cleanup(){
    # traverse array in reverse order
    for ((i=${#cleanup_stack[@]}-1; i>=0; i--)); do
        cmd="${cleanup_stack[$i]}"
        echo "Cleaning up $cmd"
        # this can be stupidly dangerous, only use if you know what you're doing
        eval "${cmd}"
    done
}

trap cleanup EXIT

mkdir -p build-context build-result

export DOCKER_BUILDKIT=1

# build up to the indicated stage
STAGE=${1:-iso-archive}
PLATFORMS=${PLATFORMS:-"linux/arm64,linux/amd64"}
DATE=$(date "+%Y%m%d_%H%M%S")
DOCKER_ARGS=()

# for iso-archive, just dump the iso to the result folder
if [ "$STAGE" = "iso-archive" ]; then
    DOCKER_ARGS+=(--output "type=local,dest=./build-result/result-${DATE}")
fi
DOCKER_ARGS+=(--tag "image-builder/${STAGE}:latest")
DOCKER_ARGS+=(--tag "image-builder/${STAGE}:${DATE}")
DOCKER_ARGS+=(--target "${STAGE}")
DOCKER_ARGS+=(--platform ${PLATFORMS})
DOCKER_ARGS+=(-f Dockerfile)
DOCKER_ARGS+=(--build-context local-context=./build-context)
docker buildx build "${DOCKER_ARGS[@]}" .
