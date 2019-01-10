#!/usr/bin/env bash
set -o errexit
set -o nounset

curDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

docker_version=$(cat VERSION)

docker build --no-cache --pull -t mrllsvc/supportone-docker-cicd-service:"${docker_version}-gradle" .

docker run \
		-d -it --rm -p 3000:3000 \
		--name supportone-docker-cicd-gradle \
		mrllsvc/supportone-docker-cicd-gradle:"${docker_version}-gradle"