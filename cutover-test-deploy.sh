#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
export DEBUG=true
[[ ${DEBUG:-} == true ]] && set -o xtrace

usage() {
    cat <<END
cutover-test-deploy.sh [-d] jsonFile

Cutover to test deploy pcf application
NOTE: will go kaboom if existing application not found
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

read -r CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_ORGANIZATION CF_SPACE CF_EXTERNAL_APP_DOMAIN <<<$(jq -r '. | "\(.api_endpoint) \(.username) \(.password) \(.organization) \(.space) \(.external_app_domain)"' "${json_file}")
read -r APP_NAME TEST_APP_NAME INSTANCES EXTERNAL_APP_HOSTNAME <<<$(jq -r '. | "\(.app_name) \(.test_app_name) \(.instances) \(.external_app_hostname)"' "${json_file}")
read -r APP_SUFFIX <<<$(jq -r '. | "\(.app_suffix)"' "${json_file}")
readarray -t CUSTOM_ROUTES <<<"$(jq -r '.custom_routes[]' "${json_file}")"

if [[ ${DEBUG} == true ]]; then
	echo "CF_API_ENDPOINT => ${CF_API_ENDPOINT}"
	echo "CF_ORGANIZATION => ${CF_ORGANIZATION}"
	echo "CF_SPACE => ${CF_SPACE}"
	echo "CF_EXTERNAL_APP_DOMAIN => ${CF_EXTERNAL_APP_DOMAIN}"
	echo "EXTERNAL_APP_HOSTNAME => ${EXTERNAL_APP_HOSTNAME}"
	echo "APP_NAME => ${APP_NAME}"
	echo "TEST_APP_NAME => ${TEST_APP_NAME}"
	echo "APP_SUFFIX => ${APP_SUFFIX}"
	echo "INSTANCES => ${INSTANCES}"
	echo "CUSTOM_ROUTES => ${CUSTOM_ROUTES[@]}"
fi

cf api --skip-ssl-validation "${CF_API_ENDPOINT}"
cf login -u "${CF_USERNAME}" -p "${CF_PASSWORD}" -o "${CF_ORGANIZATION}" -s "${CF_SPACE}"

DEPLOYED_APP="${APP_NAME}"
NEW_APP="${TEST_APP_NAME}"

SPACE_GUID=$(cf space "${CF_SPACE}" --guid)
DEPLOYED_INSTANCES=$(cf curl /v2/apps -X GET -H 'Content-Type: application/x-www-form-urlencoded' -d "q=name:${APP_NAME}" | jq -r --arg DEPLOYED_APP "${DEPLOYED_APP}" \
  ".resources[] | select(.entity.space_guid == \"${SPACE_GUID}\") | select(.entity.name == \"${DEPLOYED_APP}\") | .entity.instances | numbers")

if [[ -z "$DEPLOYED_INSTANCES" ]]; then
echo "Deployed app ${DEPLOYED_APP} not found so doing normal deployment instead"

echo "Mapping route ${EXTERNAL_APP_HOSTNAME}${APP_SUFFIX}.${CF_EXTERNAL_APP_DOMAIN} to app ${NEW_APP}"
cf map-route "${NEW_APP}" "${CF_EXTERNAL_APP_DOMAIN}" -n "${EXTERNAL_APP_HOSTNAME}${APP_SUFFIX}"

for CUSTOM_ROUTE in "${CUSTOM_ROUTES[@]}"; do
  if [ -n "${CUSTOM_ROUTE}" ]; then
    ROUTE=($CUSTOM_ROUTE)
    HOST="${ROUTE[0]}"
    DOMAIN="${ROUTE[1]}"
    echo "Mapping route ${HOST}.${DOMAIN} to deployed app ${DEPLOYED_APP}"
    cf map-route "${DEPLOYED_APP}" "${DOMAIN}" -n "${HOST}"
  fi
done

echo "Scaling app ${NEW_APP} to ${INSTANCES} instances"
cf scale -i ${INSTANCES} "${NEW_APP}"

echo "Renaming app ${NEW_APP} to ${APP_NAME}"
cf rename "${NEW_APP}" "${APP_NAME}"

exit 0
fi

echo "Performing cutover to new app ${NEW_APP}"

echo "Mapping route ${EXTERNAL_APP_HOSTNAME}${APP_SUFFIX}.${CF_EXTERNAL_APP_DOMAIN} to new app ${NEW_APP}"
cf map-route "${NEW_APP}" "${CF_EXTERNAL_APP_DOMAIN}" -n "${EXTERNAL_APP_HOSTNAME}${APP_SUFFIX}"

for CUSTOM_ROUTE in "${CUSTOM_ROUTES[@]}"; do
  if [ -n "${CUSTOM_ROUTE}" ]; then
    ROUTE=($CUSTOM_ROUTE)
    HOST="${ROUTE[0]}"
    DOMAIN="${ROUTE[1]}"
    echo "Mapping route ${HOST}.${DOMAIN} to new app ${NEW_APP}"
    cf map-route "${NEW_APP}" "${DOMAIN}" -n "${HOST}"
  fi
done

echo "A/B deployment"
if [[ ! -z "${DEPLOYED_APP}" && "${DEPLOYED_APP}" != "" ]]; then

    declare -i instances=0
    declare -i old_app_instances=${INSTANCES}
    echo "Begin scaling down deployed app ${DEPLOYED_APP} from ${INSTANCES} instances"

    while (( ${instances} != ${INSTANCES} )); do
      	declare -i instances=${instances}+1
		declare -i old_app_instances=${old_app_instances}-1
      	echo "Scaling up new app ${NEW_APP} to ${instances} instances"
      	cf scale -i ${instances} "${NEW_APP}"
        echo "Scaling down deployed app ${DEPLOYED_APP} to ${old_app_instances} instances"
        cf scale -i ${old_app_instances} "${DEPLOYED_APP}"
    done

    echo "Unmapping external route from deployed app ${DEPLOYED_APP}"
    cf unmap-route "${DEPLOYED_APP}" "${CF_EXTERNAL_APP_DOMAIN}" -n "${EXTERNAL_APP_HOSTNAME}${APP_SUFFIX}"

    echo "Deleting deployed app ${DEPLOYED_APP}"
    cf delete "${DEPLOYED_APP}" -f
fi

echo "Renaming new app ${NEW_APP} to ${APP_NAME}"
cf rename "${NEW_APP}" "${APP_NAME}"
