#!/bin/bash
# Script to deploy Webintake installation kit on internal NeoXam VM only
# It should not be used externally !!
# Carefull, it deletes the "${NXIA_DIR}/webintake" directory
# Arguments:
# - $1: the installation path
# - $2: install Keycloak (Y/N)
# - $3: drop and init Webintake/Keycloak databases (Y/N)
# Options:
# - --all-variables: all variables defined in common.properties file should be defined as env variables
# - --help: display script usage

# Exit if any command fails
set -e
# Exit if a variable is unset
set -u

declare NXIA_DIR="${HOME}/nxia"

declare WEBINTAKE_VERSION="5.2.2"
if [[ ! "${WEBINTAKE_VERSION}" ]]; then echo "Missing Webintake version" >&2; exit 1; fi


# Display script usage
usage() {
  echo "Expected usage:"
  echo "3 arguments expected:"
  echo " - First argument: Webintake installation path relative to directory ${NXIA_DIR}. Value \"webintake\" not allowed"
  echo " - Second argument: install Keycloak (Y/N)"
  echo " - Third argument: drop and init Webintake/Keycloak databases (Y/N)"
  echo "Possible options:"
  echo " - --help: display script usage"
  echo "Command examples:"
  echo " - ./deploy-webintake-kit.bash webintake-5.2.2 Y N"
  echo " - ./deploy-webintake-kit.bash webintake-5.2.2 N Y"
}

# Parse arguments
declare SKIP_ARG="no"
declare -a args=()

for arg; do
  if [[ "$SKIP_ARG" == "yes" ]]; then
    args+=( "$arg" )
    continue
  fi
  case "$arg" in
    --help) usage; exit ;;
    --) SKIP_ARG="yes" ;; # to skip options parsing
    -*) usage; exit 1 ;;
    *) args+=( "$arg" )
  esac
done

# Check arguments
if [[ ${#args[@]} -ne 3 ]]; then usage; exit 1; fi

declare WEBINTAKE_INSTALLATION_PATH="${args[0]}"
declare INSTALL_KEYCLOAK="${args[1]}"
declare DROP_INIT_DB="${args[2]}"
if [[ "${WEBINTAKE_INSTALLATION_PATH}" == "webintake" || ! "${INSTALL_KEYCLOAK}" =~ ^(Y|N)$ || ! "${DROP_INIT_DB}" =~ ^(Y|N)$ ]]; then
  usage
  exit 1
fi

# Variables
declare SCRIPT_FILE
SCRIPT_FILE=$(realpath "$0")
export SCRIPT_DIR="${SCRIPT_FILE%/*}"

declare WEBINTAKE_STANDARD_PATH="${NXIA_DIR}/webintake"
declare WEBINTAKE_FINAL_PATH="${NXIA_DIR}/${WEBINTAKE_INSTALLATION_PATH}"
declare KIT_FILENAME="webintake-installation-kit-${WEBINTAKE_VERSION}.tar"
declare WEBINTAKE_KIT_PATH="${NXIA_DIR}/${KIT_FILENAME%%.tar}"
declare COMMON_PROPERTIES_FILE="${WEBINTAKE_KIT_PATH}/conf/common.properties.orig.full"
declare -A WEBINTAKE_SEMVER=()

###########
# Functions
###########
# Parse semver value
# $1: the semver result (as a map)
# $2: the version to parse
# return:
# 0: if semver is standard
# 1: otherwise
parseSemver() {
  local name="$1"
  local value="$2"
  local re="^([0-9]+)([.][0-9]+|)([.][0-9]+|)([.][0-9]+|)([.-].+|)$"

  # shellcheck disable=SC2034
  if [[ "$value" =~ $re ]]; then
    local major="${BASH_REMATCH[1]}"
    local minor="${BASH_REMATCH[2]}"
    local patch="${BASH_REMATCH[3]}"
    local build="${BASH_REMATCH[4]}"
    local qualifier="${BASH_REMATCH[5]}"

    if [[ -z "$minor"     ]]; then minor=0     ; else minor="${minor:1}" ; fi
    if [[ -z "$patch"     ]]; then patch=0     ; else patch="${patch:1}" ; fi
    if [[ -z "$build"     ]]; then build=0     ; else build="${build:1}" ; fi
    if [[ -n "$qualifier" ]]; then qualifier="${qualifier:1}" ; fi
    eval "${name}=( [major]=\"\${major}\" [minor]=\"\${minor}\" [patch]=\"\${patch}\" [build]=\"\${build}\" [qualifier]=\"\${qualifier}\" )"
    return 0
  fi
  return 1
}

# Launch the server_local.sh command
# $1: the command to launch: start, stop, ...
serverLocalCommand() {
  local COMMAND="$1"
  local SERVER_LOCAL_SCRIPT="${WEBINTAKE_STANDARD_PATH}"/bin/server_local.sh

  if [[ -f "${SERVER_LOCAL_SCRIPT}" ]]; then "${SERVER_LOCAL_SCRIPT}" "${COMMAND}"; fi;
}

# Drop content of database schema
# $1: the schema to drop
# $2: the schema password
dropSchema() {
  local SCHEMA="$1"
  local SCHEMA_PASSWORD="$2"
  local ORACLE_ENV_FILE="${WEBINTAKE_FINAL_PATH}/install/scripts/database/SQL/Oracle/env-${SCHEMA}-oracle.sh"
  local POSTGRES_ENV_FILE="${WEBINTAKE_FINAL_PATH}/install/scripts/database/SQL/Postgres/env-${SCHEMA}-postgres.sh"

  echo "------> Populating ${SCHEMA} SQL env files with passwords"
  sed -e "s/##TO_CHANGE##/${SCHEMA_PASSWORD}/" -i "${ORACLE_ENV_FILE}" "${POSTGRES_ENV_FILE}"

  echo "------> Dropping ${SCHEMA} schema"
  "${WEBINTAKE_FINAL_PATH}/install/scripts/database/drop-schema.sh" "${SCHEMA}"
}

# Retrieve schema password from common.properties file
# $1: database schema (webintake, keycloak, core)
getPassword() {
  local SCHEMA="$1"
  sed -n "/^${SCHEMA}_db_password/p" "${COMMON_PROPERTIES_FILE}" | awk -F'=' '{print $2}' | xargs
}

# Install Webintake using Webintake install Kit
# $1: install Keycloak (Y/N)
# $2: update Webintake database (Y/N)
# $3: init Webintake database with data (Y/N)
installWebintake() {
  local LOCAL_INSTALL_KEYCLOAK="$1"
  local LOCAL_UPDATE_DB="$2"
  local LOCAL_DROP_INIT_DB="$3"

"${WEBINTAKE_KIT_PATH}"/setup.sh --no-interactive << EOF
${WEBINTAKE_FINAL_PATH}
${LOCAL_INSTALL_KEYCLOAK}
${LOCAL_UPDATE_DB}
${LOCAL_DROP_INIT_DB}
y
${COMMON_PROPERTIES_FILE}
EOF
}

########
# Main #
########

echo "------> Determining kit URL"
if ! parseSemver WEBINTAKE_SEMVER "${WEBINTAKE_VERSION}"; then echo "An error occured while parsing Webintake version ${WEBINTAKE_VERSION}" >&2; exit 1; fi

declare KIT_URL="https://access.my-nx.com/artifactory/nxgp-webintake-generic-dev"
[[ -n "${WEBINTAKE_SEMVER[qualifier]}" ]] && KIT_URL="${KIT_URL}/for-test-use-only"
KIT_URL="${KIT_URL}/installation-kit/${WEBINTAKE_VERSION:0:3}.x/${WEBINTAKE_VERSION}/${KIT_FILENAME}"
echo "------> Kit URL: ${KIT_URL}"

cd "${NXIA_DIR}" || exit 1

echo "------> Stopping Webintake"
serverLocalCommand stop

echo "------> Deleting Webintake directory: ${WEBINTAKE_FINAL_PATH}"
[[ -d "${WEBINTAKE_FINAL_PATH}" ]] && rm -rf "${WEBINTAKE_FINAL_PATH}"

echo "------> Deleting Webintake directory: webintake"
rm -rf webintake

echo "------> Deleting Webintake kit directory: ${WEBINTAKE_KIT_PATH}"
[[ -d "${WEBINTAKE_KIT_PATH}" ]] && rm -rf "${WEBINTAKE_KIT_PATH}"

echo "------> Deleting Webintake kit file: ${KIT_FILENAME}"
[[ -f "${KIT_FILENAME}" ]] && rm -rf "${KIT_FILENAME}"

echo "------> Downloading Webintake kit from URL: ${KIT_URL}"
curl -f -L --insecure "${KIT_URL}" -o "${KIT_FILENAME}"

echo "------> Extracting Webintake kit"
tar xvf "${KIT_FILENAME}"

cd "${WEBINTAKE_KIT_PATH}" || exit 1

echo "------> Modifying common.properties file: ${COMMON_PROPERTIES_FILE}"
sed -e 's/\(.*\) = \(.*\)/\1 = \${\1:-\2}/g' -i "${COMMON_PROPERTIES_FILE}"

# Special part if dropping and initializing databases:
# - install minimal Webintake installation (no keycloak, no database update, ...)
# - launch scripts to drop databases schemas
if [[ "${DROP_INIT_DB}" == "Y" ]]; then
  echo "------> Retrieving DB passwords"
  declare WEBINTAKE_DB_PASSWORD
  WEBINTAKE_DB_PASSWORD="$(getPassword webintake)"
  declare KEYCLOAK_DB_PASSWORD
  KEYCLOAK_DB_PASSWORD="$(getPassword keycloak)"

  echo "------> Launching Minimal Webintake installation to drop database schema"
  installWebintake "N" "N" "N"

  dropSchema webintake "${WEBINTAKE_DB_PASSWORD}"

  [[ "${INSTALL_KEYCLOAK}" == "Y" ]] && dropSchema keycloak "${KEYCLOAK_DB_PASSWORD}"

  echo "------> Deleting Webintake directory: ${WEBINTAKE_FINAL_PATH}"
  rm -rf "${WEBINTAKE_FINAL_PATH}"
fi

echo "------> Launching Webintake installation"
installWebintake "${INSTALL_KEYCLOAK}" "Y" "${DROP_INIT_DB}"

echo "------> Creating symbolic link: webintake -> ${WEBINTAKE_INSTALLATION_PATH}"
cd "${NXIA_DIR}" || exit 1
ln -s "${WEBINTAKE_INSTALLATION_PATH}" webintake

echo "------> Launching Webintake"
serverLocalCommand start
