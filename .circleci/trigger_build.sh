#!/bin/bash

# from https://circleci.com/docs/1.0/nightly-builds/
# See also https://circleci.com/docs/2.0/defining-multiple-jobs/

# trigger_build.sh $circle_token $project_optional $branch_optional

CIRCLE_TOKEN=$1
CIRCLE_JOB=${2:-nightly_build}
PROJECT=${3:-drud/ddev}
BRANCH=${4:-master}
GITHUB_TOKEN=${5:-}
RELEASE_TAG=${6:-}

trigger_build_url=https://circleci.com/api/v1.1/project/github/$PROJECT/tree/$BRANCH?circle-token=${CIRCLE_TOKEN}

BUILD_PARAMS="\"CIRCLE_JOB\": \"${CIRCLE_JOB}\", \"GITHUB_TOKEN\":\"${GITHUB_TOKEN}\", \"RELEASE_TAG\": \"${RELEASE_TAG}\""

curl -sS \
  --header "Content-Type: application/json" \
  --data "{\"build_parameters\": {${BUILD_PARAMS}}}" \
  --request POST \
    $trigger_build_url
