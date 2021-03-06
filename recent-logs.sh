#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
export DEBUG=true
[[ ${DEBUG:-} == true ]] && set -o xtrace

usage() {
    cat <<END
recent-logs.sh [-d] jsonFile

Print recent logs for pcf application
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

read -r CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_ORGANIZATION CF_SPACE APP_NAME TEST_APP_NAME <<<$(jq -r '. | "\(.api_endpoint) \(.username) \(.password) \(.organization) \(.space) \(.app_name) \(.test_app_name)"' "${json_file}")

if [[ ${DEBUG} == true ]]; then
	echo "CF_API_ENDPOINT => ${CF_API_ENDPOINT}"
	echo "CF_ORGANIZATION => ${CF_ORGANIZATION}"
	echo "CF_SPACE => ${CF_SPACE}"
	echo "APP_NAME => ${APP_NAME}"
	echo "TEST_APP_NAME => ${TEST_APP_NAME}"
fi

cf api --skip-ssl-validation "${CF_API_ENDPOINT}"
cf login -u "${CF_USERNAME}" -p "${CF_PASSWORD}" -o "${CF_ORGANIZATION}" -s "${CF_SPACE}"

SPACE_GUID=$(cf space "${CF_SPACE}" --guid)
DEPLOYED_APP_INSTANCES=$(cf curl /v2/apps -X GET -H 'Content-Type: application/x-www-form-urlencoded' -d "q=name:${APP_NAME}" | jq -r --arg DEPLOYED_APP "${APP_NAME}" \
  ".resources[] | select(.entity.space_guid == \"${SPACE_GUID}\") | select(.entity.name == \"${APP_NAME}\") | .entity.instances | numbers")
DEPLOYED_TEST_APP_INSTANCES=$(cf curl /v2/apps -X GET -H 'Content-Type: application/x-www-form-urlencoded' -d "q=name:${TEST_APP_NAME}" | jq -r --arg DEPLOYED_APP "${TEST_APP_NAME}" \
  ".resources[] | select(.entity.space_guid == \"${SPACE_GUID}\") | select(.entity.name == \"${TEST_APP_NAME}\") | .entity.instances | numbers")

if [[ -z "$DEPLOYED_APP_INSTANCES" ]]; then
echo "App ${APP_NAME} not found so no logs to print"
else
cf logs "${APP_NAME}" --recent
fi

if [[ -z "$DEPLOYED_TEST_APP_INSTANCES" ]]; then
echo "Test app ${TEST_APP_NAME} not found so no logs to print"
else
cf logs "${TEST_APP_NAME}" --recent
fi
