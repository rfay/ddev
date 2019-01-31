#!/bin/bash

# from https://circleci.com/docs/1.0/nightly-builds/
# See also https://circleci.com/docs/2.0/defining-multiple-jobs/

# trigger_build.sh $circle_token $project_optional $branch_optional $github_token_optional $release_tag_optional

# .circleci/trigger_build.sh c4e304eb5323f91900908b3443ea583circletoken release_build rfay/ddev 20190131_deploy_artifacts_from_circle 9f622120dd9800f5c59ea80a1ad9github_token  v1.5.7  | jq -r

CIRCLE_TOKEN=$1
CIRCLE_JOB=${2:-nightly_build}
PROJECT=${3:-drud/ddev}
BRANCH=${4:-master}
GITHUB_TOKEN=${5:-}
RELEASE_TAG=${6:-}

trigger_build_url=https://circleci.com/api/v1.1/project/github/$PROJECT?circle-token=${CIRCLE_TOKEN}

set -x
BUILD_PARAMS="\"CIRCLE_JOB\": \"${CIRCLE_JOB}\", \"job_name\": \"${CIRCLE_JOB}\", \"GITHUB_TOKEN\":\"${GITHUB_TOKEN}\", \"RELEASE_TAG\": \"${RELEASE_TAG}\""
if [ "${RELEASE_TAG}" != "" ]; then
    DATA="\"tag\": \"$RELEASE_TAG\","
fi

DATA="${DATA} \"build_parameters\": { ${BUILD_PARAMS} } "

curl -X POST -sS \
  --header "Content-Type: application/json" \
  --data "{ ${DATA} }" \
    $trigger_build_url

#curl -X POST --header "Content-Type: application/json" -d '{
#  "tag": "v0.1", // optional
#  "parallel": 2, //optional, default null
#  "build_parameters": { // optional
#    "RUN_EXTRA_TESTS": "true"
#  }
#}
#' https://circleci.com/api/v1.1/project/:vcs-type/:username/:project?circle-token=:token
