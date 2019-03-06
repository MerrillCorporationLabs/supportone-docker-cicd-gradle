#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
export DEBUG=true
[[ ${DEBUG:-} == true ]] && set -o xtrace

usage() {
    cat <<END
validate-test-deploy-health.sh [-d] jsonFile

Validates that test deploy app is healthy:
    - app is started
    - app has running instance
    - app has no crashes

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
read -r CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_ORGANIZATION CF_SPACE TEST_APP_NAME <<<$(jq -r '. | "\(.api_endpoint) \(.username) \(.password) \(.organization) \(.space) \(.test_app_name)"' "${json_file}")

if [[ ${DEBUG} == true ]]; then
	echo "CF_API_ENDPOINT => ${CF_API_ENDPOINT}"
	echo "CF_ORGANIZATION => ${CF_ORGANIZATION}"
	echo "CF_SPACE => ${CF_SPACE}"
	echo "TEST_APP_NAME => ${TEST_APP_NAME}"
fi

cf api --skip-ssl-validation "${CF_API_ENDPOINT}"
cf login -u "${CF_USERNAME}" -p "${CF_PASSWORD}" -o "${CF_ORGANIZATION}" -s "${CF_SPACE}"

SPACE_GUID=$(cf space "${CF_SPACE}" --guid)
DEPLOYED_INSTANCES=$(cf curl /v2/apps -X GET -H 'Content-Type: application/x-www-form-urlencoded' -d "q=name:${TEST_APP_NAME}" | jq -r --arg DEPLOYED_APP "${TEST_APP_NAME}" \
  ".resources[] | select(.entity.space_guid == \"${SPACE_GUID}\") | select(.entity.name == \"${TEST_APP_NAME}\") | .entity.instances | numbers")

if [[ -z "$DEPLOYED_INSTANCES" ]]; then
echo "Test deploy app ${TEST_APP_NAME} not found so nothing to validate"
exit 1
fi

#    cf app ZZZ-TESTDEPLOY-metadata-composite-service-fecfdbdf-2c77-4c6f-ba
#    Showing health and status for app ZZZ-TESTDEPLOY-metadata-composite-service-fecfdbdf-2c77-4c6f-ba in org us2-datasiteone / space devg as shartma...
#
#    name:              ZZZ-TESTDEPLOY-metadata-composite-service-fecfdbdf-2c77-4c6f-ba
#    requested state:   started
#    routes:            ZZZ-TESTDEPLOY-metadata-composite-service-fecfdbdf-2c77-4c6f-ba.apps.us2.devg.foundry.mrll.com
#    last uploaded:     Wed 06 Mar 19:03:29 UTC 2019
#    stack:             cflinuxfs2
#    buildpacks:        https://github.com/cloudfoundry/java-buildpack.git#v4.9
#
#    type:           web
#    instances:      1/1
#    memory usage:   3072M
#         state     since                  cpu    memory       disk           details
#    #0   running   2019-03-06T19:04:19Z   0.3%   1.1G of 3G   196.9M of 1G

CRASH_EVENT_ENDPOINT="/v2/events?order-by=timestamp&order-direction=desc&results-per-page=5&q=type:app.crash"

cf app "$TEST_APP_NAME" > app
cf app "$TEST_APP_NAME" --guid > guid
awk 'NR==4' app > status
awk 'NR==11' app > instances
APP_GUID=$(cat guid)
STATUS=$(cat status)
INSTANCES=$(cat instances)
cf curl "${CRASH_EVENT_ENDPOINT}&q=actee:${APP_GUID}" --output crash_events
readarray -t CRASHES <<<"$(jq -r '.resources[]' "crash_events")"

[[ "$STATUS" =~ 'started'$ ]] && is_started=true || is_started=false
echo "app is started = $is_started"
[[ "$INSTANCES" =~ '1/1'$ ]] && has_running_instance=true || has_running_instance=false
echo "app has running instance = $has_running_instance"
[[ !${CRASHES[@]} ]] && has_no_crashes=true || has_no_crashes=false
echo "app has no crashes = $has_no_crashes"

[[ ! $is_started && ! $has_running_instance && ! $has_no_crashes ]] && exit 1
