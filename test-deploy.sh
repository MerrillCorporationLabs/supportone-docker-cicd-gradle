#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
export DEBUG=true
[[ ${DEBUG:-} == true ]] && set -o xtrace

usage() {
    cat <<END
test-deploy.sh [-d] jsonFile

Test deploy for pcf application
jsonFile: jsonFile with all the vars needed to run the script. see: example
	-d: (optional) debug will print details
    -h: show this help message
END
}

error () {
    echo "Error: $1"
    exit "$2"
} >&2

while getopts ":hd" opt; do
    case $opt in
        d)
            is_debug=true
            ;;
        h)
            usage
            exit 0
            ;;
        :)
            error "Option -${OPTARG} is missing an argument" 2
            ;;
        \?)
            error "unkown option: -${OPTARG}" 3
            ;;
    esac
done

shift $(( OPTIND -1 ))
[[ -f ${1} ]] || { echo "missing an argument. first argument must be location of json file with vars" >&2; exit 1; }
declare json_file="${1}"

# set cf vars
read -r CF_API_ENDPOINT CF_BUILDPACK CF_USERNAME CF_PASSWORD CF_ORGANIZATION CF_SPACE CF_INTERNAL_APP_DOMAIN CF_EXTERNAL_APP_DOMAIN <<<$(jq -r '. | "\(.api_endpoint) \(.buildpack) \(.username) \(.password) \(.organization) \(.space) \(.internal_app_domain) \(.external_app_domain)"' "${json_file}")
read -r TEST_APP_NAME APP_MEMORY APP_DISK TIMEOUT INSTANCES ARTIFACT_PATH ARTIFACT_TYPE EXTERNAL_APP_HOSTNAME PUSH_OPTIONS <<<$(jq -r '. | "\(.test_app_name) \(.app_memory) \(.app_disk) \(.timeout) \(.instances) \(.artifact_path) \(.artifact_type) \(.external_app_hostname) \(.push_options)"' "${json_file}")
read -r APP_SUFFIX <<<$(jq -r '. | "\(.app_suffix)"' "${json_file}")
readarray -t CF_SERVICES <<<"$(jq -r '.services[]' "${json_file}")"

if [[ "$ARTIFACT_TYPE" == "directory" && ! -d ${ARTIFACT_PATH} ]]; then
    echo "Exiting before test deploy because artifact path directory ${ARTIFACT_PATH} not found"
    exit 1
fi
if [[ "$ARTIFACT_TYPE" == "file" && ! -f ${ARTIFACT_PATH} ]]; then
    echo "Exiting before test deploy because artifact path file ${ARTIFACT_PATH} not found"
    exit 1
fi

if [[ ${DEBUG} == true ]]; then
	echo "CF_API_ENDPOINT => ${CF_API_ENDPOINT}"
	echo "CF_BUILDPACK => ${CF_BUILDPACK}"
	echo "CF_ORGANIZATION => ${CF_ORGANIZATION}"
	echo "CF_SPACE => ${CF_SPACE}"
	echo "CF_INTERNAL_APP_DOMAIN => ${CF_INTERNAL_APP_DOMAIN}"
	echo "CF_EXTERNAL_APP_DOMAIN => ${CF_EXTERNAL_APP_DOMAIN}"
	echo "EXTERNAL_APP_HOSTNAME => ${EXTERNAL_APP_HOSTNAME}"
	echo "TEST_APP_NAME => ${TEST_APP_NAME}"
	echo "APP_MEMORY => ${APP_MEMORY}"
	echo "APP_DISK => ${APP_DISK}"
	echo "TIMEOUT => ${TIMEOUT}"
	echo "INSTANCES => ${INSTANCES}"
	echo "APP_SUFFIX => ${APP_SUFFIX}"
	echo "ARTIFACT_PATH => ${ARTIFACT_PATH}"
	echo "ARTIFACT_TYPE => ${ARTIFACT_TYPE}"
	echo "PUSH_OPTIONS => ${PUSH_OPTIONS}"
	echo "CF_SERVICES => ${CF_SERVICES[@]}"
fi

cf api --skip-ssl-validation "${CF_API_ENDPOINT}"
cf login -u "${CF_USERNAME}" -p "${CF_PASSWORD}" -o "${CF_ORGANIZATION}" -s "${CF_SPACE}"

echo "Performing test deploy of application ${TEST_APP_NAME}"

cf push "${TEST_APP_NAME}" -i 1 -m "${APP_MEMORY}" -k "${APP_DISK}" -t "${TIMEOUT}" -b "${CF_BUILDPACK}" \
  -n "${TEST_APP_NAME}${APP_SUFFIX}" -d "${CF_INTERNAL_APP_DOMAIN}" -p "${ARTIFACT_PATH}" ${PUSH_OPTIONS}

for CF_SERVICE in "${CF_SERVICES[@]}"; do
  if [ -n "${CF_SERVICE}" ]; then
    echo "Binding service ${CF_SERVICE} to test app ${TEST_APP_NAME}"
    cf bind-service "${TEST_APP_NAME}" "${CF_SERVICE}"
  fi
done

cf start "${TEST_APP_NAME}"