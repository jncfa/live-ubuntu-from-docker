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
# --cache-from image:buildcache-${ARCH} --cache-to image:buildcache-${ARCH} \

mkdir -p build
DOCKER_BUILDKIT=1 docker buildx build --platform linux/amd64,linux/arm64 \
    --no-cache \
    -t image-builder:latest \
    -f Dockerfile --target iso-archive \
    --output=type=local,dest=./ build #\
    #--progress plain . 2>&1 | tee build.log &
#add_cleanup "kill -SIGINT $!"

#tail -f build.log
