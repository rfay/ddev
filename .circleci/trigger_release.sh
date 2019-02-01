#!/bin/bash

# trigger_release.sh $circle_token $project_optional $branch_optional $github_token_optional $release_tag_optional

# .circleci/trigger_build.sh c4e304eb5323f91900908b3443ecirclekey release_build rfay/ddev 20190131_deploy_artifacts_from_circle 9f622120dd9800f5c59ea80a1ad9f7c353962dea  v1.5.9  | jq -r 'del(.circle_yml)'

# api docs: https://circleci.com/docs/api
# Trigger a new job: https://circleci.com/docs/api/v1-reference/#new-build

CIRCLE_TOKEN=$1
PROJECT=${2:-drud/ddev}
GITHUB_TOKEN=${3:-}
RELEASE_TAG=${4:-}

trigger_build_url=https://circleci.com/api/v1.1/project/github/$PROJECT?circle-token=${CIRCLE_TOKEN}

set -x
BUILD_PARAMS="\"CIRCLE_JOB\": \"release_build\", \"job_name\": \"release_build\", \"GITHUB_TOKEN\":\"${GITHUB_TOKEN}\", \"RELEASE_TAG\": \"${RELEASE_TAG}\""
if [ "${RELEASE_TAG}" != "" ]; then
    DATA="\"tag\": \"$RELEASE_TAG\","
fi

DATA="${DATA} \"build_parameters\": { ${BUILD_PARAMS} } "

curl -X POST -sS \
  --header "Content-Type: application/json" \
  --data "{ ${DATA} }" \
    $trigger_build_url

