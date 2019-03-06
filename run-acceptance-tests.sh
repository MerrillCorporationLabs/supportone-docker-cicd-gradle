#!/usr/bin/env bash
set -o errexit
set -o pipefail
set -o nounset
export DEBUG=true
[[ ${DEBUG:-} == true ]] && set -o xtrace

usage() {
    cat <<END
run-acceptance-tests.sh [-d] jsonFile

Runs acceptance tests against test deploy app
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
read -r CF_API_ENDPOINT CF_USERNAME CF_PASSWORD CF_ORGANIZATION CF_SPACE CF_BASE_ENVIRONMENT CF_EXTERNAL_APP_DOMAIN TEST_APP_NAME <<<$(jq -r '. | "\(.api_endpoint) \(.username) \(.password) \(.organization) \(.space) \(.base_environment) \(.external_app_domain) \(.test_app_name)"' "${json_file}")

if [[ ${DEBUG} == true ]]; then
	echo "CF_API_ENDPOINT => ${CF_API_ENDPOINT}"
	echo "CF_ORGANIZATION => ${CF_ORGANIZATION}"
	echo "CF_SPACE => ${CF_SPACE}"
	echo "CF_BASE_ENVIRONMENT => ${CF_BASE_ENVIRONMENT}"
	echo "CF_EXTERNAL_APP_DOMAIN => ${CF_EXTERNAL_APP_DOMAIN}"
	echo "TEST_APP_NAME => ${TEST_APP_NAME}"
fi

./gradlew runAcceptance --no-daemon -DPR=true -DPCF_USER="${CF_USERNAME}" -DPCF_PWD="${CF_PASSWORD}" -DTARGET_SERVICE="${TEST_APP_NAME}" -DTARGET_DOMAIN="${CF_EXTERNAL_APP_DOMAIN}" -DTARGET_ENVIRONMENT="${CF_BASE_ENVIRONMENT}" -DPCF_URI="${CF_API_ENDPOINT}" -DPCF_API_DOMAIN="${CF_API_ENDPOINT}" -DPCF_SPACE="${CF_SPACE}" -DPCF_ORG="${CF_ORGANIZATION}"
