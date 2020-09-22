#!/bin/sh

set -o errexit

if [ -z "${CF_DOMAIN}" ]; then
  echo "CF_DOMAIN not defined but required"
  exit 1
fi

if [ -z "${CF_USERNAME}" ]; then
  echo "CF_USERNAME not defined but required"
  exit 1
fi

if [ -z "${CF_PASSWORD}" ]; then
  echo "CF_PASSWORD not defined but required"
  exit 1
fi

cf api --skip-ssl-validation \
   https://api.${CF_DOMAIN}

cf auth ${CF_USERNAME} ${CF_PASSWORD}

cf enable-feature-flag diego_docker

if [ "$CREDHUB_ENABLED" == "true" ]; then
  credhub api --skip-tls-validation \
      https://credhub.$CF_DOMAIN
  credhub login \
      --client-name=$CREDHUB_CLIENT \
      --client-secret=$CREDHUB_SECRET
fi

export BRAIN="/brains/acceptance-tests-brain"
export ASSETS="${BRAIN}/test-resources"
export SCRIPTS_FOLDER="${BRAIN}/test-scripts"

# Announce the versions of the helper apps used by this job. This also
# causes an early abort if these are somehow missing, or not
# accessible/found through the PATH.
cf version      | sed -e 's/^/CF   = /'
kubectl version | sed -e 's/^/KUBE = /'
helm version    | sed -e 's/^/HELM = /'

PARAM="--timeout ${TIMEOUT:-600}"

if [[ "${VERBOSE}" == "true" || "${VERBOSE}" == "1" ]]; then
    PARAM="${PARAM} --verbose"
fi

if [[ "${IN_ORDER}" == "true" || "${IN_ORDER}" == "1" ]]; then
    PARAM="${PARAM} --in-order"
fi

if [ -n "${INCLUDE}" ]; then
    PARAM="${PARAM} --include ${INCLUDE}"
else
    PARAM="${PARAM} --include _test.rb"
fi

if [ -n "${EXCLUDE}" ]; then
    PARAM="${PARAM} --exclude ${EXCLUDE}"
fi

PARAM="${PARAM} ${SCRIPTS_FOLDER}"

if [ -d /tests ]; then
    PARAM="${PARAM} /tests"
fi

set -x
set -o nounset
testbrain run ${PARAM}
