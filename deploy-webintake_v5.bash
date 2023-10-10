#!/bin/bash
#============================================================================
# TITLE  :  NeoXam Deploy Webintake Shell
# Subject : Script for deploying Webintake
# Author: Ahmed JALLALI; Client Support Consultant
# Creation date: N/A
# Need file: N/A
#
# How To launch: ./deploy-webintake-kit.bash $WEBINTAKE_INSTALLATION_PATH $WEBINTAKE_INIT_PATH $WEBINTAKE_VERSION $INSTALL_KEYCLOAK $DROP_INIT_DB
#
# Arguments:
# - $1: Webintake installation path
# - $2: Common initialization file
# - $3: Webintake version to be installed
# - $4: Install Keycloak (Y/N)
# - $5: Drop and initialize Webintake/Keycloak databases (Y/N)
#
# Options:
# - --help: Display script usage
#
# History
# R&D: N/A          Internal script provided by R&D for internal installation
# AJA: 15/09/2023	Adapt the script to the requirements of the webintake deployment automation project
# AJA: 15/09/2023	Add fix FK_JAC_SIT 
# AJA: 10/10/2023	Add fix distiller PDF files
#================== Mail address =========================================



# Exit if any command fails
set -e
# Exit if a variable is unset
set -u

# Display script usage
usage() {
  echo -e "\e[31mExpected usage:"
  echo "5 arguments expected:"
  echo " - First argument: Webintake installation path (absolute path)"
  echo " - Second argument: Webintake initialization params file (absolute path)"
  echo " - Third argument: Webintake version to be installed"
  echo " - Fourth argument: Install Keycloak (Y/N)"
  echo " - Fifth argument: Drop and initialize Webintake/Keycloak databases (Y/N)"
  echo "Possible options:"
  echo " - --help: Display script usage"
  echo "Command examples:"
  echo -e "\e[32m - ./deploy-webintake-kit.bash /path/to/webintake /path/to/commons.sh 5.2.2 N N\e[0m"
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
if [[ ${#args[@]} -ne 5 ]]; then
  usage
  exit 1
fi

declare WEBINTAKE_INSTALLATION_PATH="${args[0]}"
declare WEBINTAKE_INIT_PATH="${args[1]}"
declare WEBINTAKE_VERSION="${args[2]}"
declare INSTALL_KEYCLOAK="${args[3]}"
declare DROP_INIT_DB="${args[4]}"

# Validate arguments
# Check if WEBINTAKE_INSTALLATION_PATH is an absolute path
if [[ "${WEBINTAKE_INIT_PATH}" != /* ]]; then
  echo -e "\e[31mERROR: Installation path ${WEBINTAKE_INSTALLATION_PATH} is not an absolute path.\e[0m"
  exit 1
fi

# Check if WEBINTAKE_INIT_PATH exists and is an absolute path
if [[ ! -e "${WEBINTAKE_INIT_PATH}" || "${WEBINTAKE_INIT_PATH}" != /* ]]; then
  echo -e "\e[31mERROR: common path ${WEBINTAKE_INIT_PATH} does not exist or is not an absolute path.\e[0m"
  exit 1
fi

# Check if WEBINTAKE_VERSION has the format x.y.z where x is exclusively 5
if [[ ! "${WEBINTAKE_VERSION}" =~ ^5\.[0-9]+\.[0-9]+$ ]]; then
  echo -e "\e[31mERROR: WEBINTAKE_VERSION must have the format 5.y.z.\e[0m"
  exit 1
fi

# Check values of INSTALL_KEYCLOAK and DROP_INIT_DB
if [[ ! "${INSTALL_KEYCLOAK}" =~ ^(Y|N)$ || ! "${DROP_INIT_DB}" =~ ^(Y|N)$ ]]; then
  echo -e "\e[31mERROR: Values of INSTALL_KEYCLOAK and DROP_INIT_DB must be 'Y' or 'N'.\e[0m"
  exit 1
fi

# Check Server UP
if ! pgrep -f "bin/tomcatinstances/middleware" > /dev/null; then
    echo -e "\e[31mERROR: WEBINTAKE must be started before running this script.\e[0m"
    exit 1
fi

# Source the commons.sh file
source "$WEBINTAKE_INIT_PATH"

# Variables
#declare SCRIPT_FILE
#SCRIPT_FILE=$(realpath "$0")
#export SCRIPT_DIR="${SCRIPT_FILE%/*}"

declare CURRENT_DIR="$PWD"
declare TODAY=$(date '+%Y-%m-%d')
declare GPROOT=$(ps -ef | grep middleware1 | grep -oP '(?<=Dfr.sgf.gp.root=)[^ ]+')
declare GPROOT_PARENT=$(dirname "$GPROOT")
declare INSTALL_DIR="$GPROOT_PARENT/kit_install_$TODAY"
declare KIT_FILENAME="webintake-installation-kit-${WEBINTAKE_VERSION}.tar"
declare WEBINTAKE_KIT_PATH="${INSTALL_DIR}/${KIT_FILENAME%%.tar}"
declare COMMON_PROPERTIES_FILE="${WEBINTAKE_KIT_PATH}/conf/common.properties.orig.full"
#declare LOG_FILE="${INSTALL_DIR}/upgrade_wit_$(date '+%Y-%m-%d_%H-%M-%S').log" # Added LOG_FILE variable
declare LOG_FILE="upgrade_wit_$(date '+%Y-%m-%d_%H-%M-%S').log" # Added LOG_FILE variable
#declare WEBINTAKE_CURRENT_VERSION=$(grep -o 'Application Version | [0-9]\+\.[0-9]\+\.[0-9]\+' "${GPROOT}/logs/webintake/middleware1.log" "${GPROOT}/logs/webintake/webintake-server1.log" 2>/dev/null | tail -n 1 | awk -F '|' '{gsub(/ /, "", $2); print $2}')
declare WEBINTAKE_CURRENT_VERSION=$(unzip -p ${GPROOT}/app/webintake/wiserver.war META-INF/MANIFEST.MF | grep Implementation-Version | cut -d ' ' -f2)
declare COMPARE_VERSION="5.2.0"

# Add log file to the script
#exec &> "$LOG_FILE"
exec 2> >( tee -a "$LOG_FILE" ) 3>&1 1>>"$LOG_FILE"

declare -A WEBINTAKE_SEMVER=()

###########
# Functions
###########
# Parse semver value
# $1: the semver result (as a map)
# $3: the version to parse
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

    if [[ -z "$minor" ]]; then minor=0; else minor="${minor:1}"; fi
    if [[ -z "$patch" ]]; then patch=0; else patch="${patch:1}"; fi
    if [[ -z "$build" ]]; then build=0; else build="${build:1}"; fi
    if [[ -n "$qualifier" ]]; then qualifier="${qualifier:1}"; fi
    eval "${name}=( [major]=\"\${major}\" [minor]=\"\${minor}\" [patch]=\"\${patch}\" [build]=\"\${build}\" [qualifier]=\"\${qualifier}\" )"
    return 0
  fi
  return 1
}

# Launch the server_local.sh command
# $1: the command to launch: start, stop, ...
serverLocalCommand() {
  local COMMAND="$1"
  local SERVER_LOCAL_SCRIPT="${GPROOT}/bin/server_local.sh"

  if [[ -f "${SERVER_LOCAL_SCRIPT}" ]]; then "${SERVER_LOCAL_SCRIPT}" "${COMMAND}"; fi;
}

# Drop content of database schema
# $1: the schema to drop
# $2: the schema password
dropSchema() {
  local SCHEMA="$1"
  local SCHEMA_PASSWORD="$2"
  local ORACLE_ENV_FILE="${GPROOT}/install/scripts/database/SQL/Oracle/env-${SCHEMA}-oracle.sh"
  local POSTGRES_ENV_FILE="${GPROOT}/install/scripts/database/SQL/Postgres/env-${SCHEMA}-postgres.sh"

  echo "------> Populating ${SCHEMA} SQL env files with passwords"
  sed -e "s/##TO_CHANGE##/${SCHEMA_PASSWORD}/" -i "${ORACLE_ENV_FILE}" "${POSTGRES_ENV_FILE}"

  echo "------> Dropping ${SCHEMA} schema"
  "${GPROOT}/install/scripts/database/drop-schema.sh" "${SCHEMA}"
}

# Retrieve schema password from common.properties file
# $1: database schema (webintake, keycloak, core)
getPassword() {
  local SCHEMA="$1"
  sed -n "/^${SCHEMA}_db_password/p" "${COMMON_PROPERTIES_FILE}" | awk -F'=' '{print $3}' | xargs
}

# Install Webintake using Webintake install Kit
# $1: install Keycloak (Y/N)
# $3: update Webintake database (Y/N)
# $4: init Webintake database with data (Y/N)
installWebintake() {
  local LOCAL_INSTALL_KEYCLOAK="$1"
  local LOCAL_UPDATE_DB="$2"
  local LOCAL_DROP_INIT_DB="$3"

  "${WEBINTAKE_KIT_PATH}/setup.sh" --no-interactive << EOF
${WEBINTAKE_INSTALLATION_PATH}
${LOCAL_INSTALL_KEYCLOAK}
${LOCAL_UPDATE_DB}
${LOCAL_DROP_INIT_DB}
y
${COMMON_PROPERTIES_FILE}
EOF
}

# Fix FK_JAC_SIT 
WitQueries() {
  local DB_USER="$1"
  local DB_PASSWORD="$2"
  local DB_HOST="$3"
  local DB_PORT="$4"
  local ORACLE_SERVICE_NAME="$5"
  
  local DELETE_JAAS_QUERY="DELETE FROM jaas_config WHERE SITE_CODE=0;"
  local INSERT_JAAS_QUERY="INSERT INTO JAAS_CONFIG SELECT HIBERNATE_SEQUENCE.NEXTVAL, 0, 'Console', 'fr.sgf.wit.security.login.module.GPRoleLoginModule', 'REQUIRED' FROM DUAL;"
  local INSERT_SITES_QUERY="INSERT INTO SITES SELECT 0, 'Console adm site', WEBINTAKE_DB_VERSION, COMPRESSRESPONSELIMIT, SESSIONLOGPATH, ENVLOGPATH, ALGORITHMENCRYPTION, REFERENTIAL_TYPE, FLUSHSIZE, 'CONSOLE', SIT_SECU_MANAGED_BY_GP, SIT_COMPRESS_REPORT, SIT_COMPRESS_RESPONSE, SIT_CLIENT_LIVE_DELAY, SIT_SERVER_LIVE_DELAY, SIT_FLUSH_DELAY, SIT_CLIENT_TIMEOUT FROM SITES WHERE SITE_CODE=1;"
  local COMMIT_QUERY="COMMIT;"
  
  # Execute the SQL queries
  echo "${DELETE_JAAS_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
  echo "${INSERT_JAAS_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
  echo "${INSERT_SITES_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
  echo "${COMMIT_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
}

# Fix distiller PDF files
CoreQueries() {
  local DB_USER="$1"
  local DB_PASSWORD="$2"
  local DB_HOST="$3"
  local DB_PORT="$4"
  local ORACLE_SERVICE_NAME="$5"
  
  local DELETE_OLD_PARAM="DELETE FROM PARAMETRE_CHAMP_TRAITEMENT WHERE CODE_TRAITEMENT='TOUS' AND CRITERE_SAISIE_1='.' AND CRITERE_SAISIE_2='.' AND NOM_CHAMP='Runtime.distiller';"
  local INSERT_NEW_QUERY="INSERT INTO PARAMETRE_CHAMP_TRAITEMENT (CODE_TRAITEMENT,CRITERE_SAISIE_1,CRITERE_SAISIE_2,NOM_CHAMP,LIB_PARAMETRE_CHAMP_C,LIB_PARAMETRE_CHAMP_L,VALEUR_PAR_DEFAUT,TYPE_SAISIE,CODE_GESTION,KRONECKER_1,KRONECKER_2) VALUES ('TOUS','. ','. ','Runtime.distiller',' ',' ',' ',' ','O ','0','0');"
  local COMMIT_QUERY="COMMIT;"
  
  # Execute the SQL queries
  echo "${DELETE_OLD_PARAM}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
  echo "${INSERT_NEW_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
  echo "${COMMIT_QUERY}" | sqlplus "${DB_USER}/${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${ORACLE_SERVICE_NAME}"
}


# Function to check for errors in the log file
CheckErrors() {
  if grep -qi "error" "$1"; then
    echo "There are errors to check in the log file ($1)." | tee /dev/fd/3
  else
    echo "The installation completed successfully. No errors found in the log file ($LOG_FILE)." | tee /dev/fd/3
    echo " " | tee /dev/fd/3
    echo -e "\e[32m####################################################################\e[0m" | tee /dev/fd/3
    echo -e "\e[32mInstallation of webintake ${WEBINTAKE_VERSION} finished with Success\e[0m" | tee /dev/fd/3
    echo -e "\e[32m####################################################################\e[0m" | tee /dev/fd/3
  fi
}

########
# Main #
########

echo "------> Determining kit URL"
if ! parseSemver WEBINTAKE_SEMVER "${WEBINTAKE_VERSION}"; then
  echo "An error occurred while parsing Webintake version ${WEBINTAKE_VERSION}" >&2
  exit 1
fi

#declare KIT_URL="https://access.my-nx.com/artifactory/nxgp-webintake-generic-dev"
#[[ -n "${WEBINTAKE_SEMVER[qualifier]}" ]] && KIT_URL="${KIT_URL}/for-test-use-only"
#KIT_URL="${KIT_URL}/installation-kit/${WEBINTAKE_VERSION:0:3}.x/${WEBINTAKE_VERSION}/${KIT_FILENAME}"
#echo "------> Kit URL: ${KIT_URL}"


declare KIT_URL="https://access.my-nx.com/artifactory/nxgp-webintake-generic-dev/installation-kit/5.2.x"
declare KIT_URL="${KIT_URL}/${WEBINTAKE_VERSION}/webintake-installation-kit-${WEBINTAKE_VERSION}.tar"


echo "------> Stopping Webintake"
serverLocalCommand stop

#echo "------> Deleting Webintake directory: ${GPROOT}"
#[[ -d "${GPROOT}" ]] && rm -rf "${GPROOT}"

echo "------> Backing up Webintake directory: ${GPROOT}"
declare GPROOT_OLD="${GPROOT}.bckp.${TODAY}"
[[ -d "${GPROOT}" ]] && mv "${GPROOT}" "${GPROOT_OLD}"

#echo "------> Deleting Webintake directory: webintake"
#rm -rf webintake

#echo "------> Deleting Webintake kit directory: ${WEBINTAKE_KIT_PATH}"
#[[ -d "${WEBINTAKE_KIT_PATH}" ]] && rm -rf "${WEBINTAKE_KIT_PATH}"
echo "------> Deleting Webintake kit directory: ${INSTALL_DIR}"
[[ -d "${INSTALL_DIR}" ]] && rm -rf "${INSTALL_DIR}"

#echo "------> Deleting Webintake kit file: ${KIT_FILENAME}"
#[[ -f "${KIT_FILENAME}" ]] && rm -rf "${KIT_FILENAME}"

#cd "$HOME" || exit 1
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}" || exit 1

echo "------> Downloading Webintake kit from URL: ${KIT_URL}"
curl -f -L --insecure "${KIT_URL}" -o "${KIT_FILENAME}"

echo "------> Extracting Webintake kit"
tar xvf "${KIT_FILENAME}"


cd "${WEBINTAKE_KIT_PATH}" || exit 1

echo "------> Modifying common.properties file: ${COMMON_PROPERTIES_FILE}"
sed -e 's/\(.*\) = \(.*\)/\1 = \${\1:-\2}/g' -i "${COMMON_PROPERTIES_FILE}"

# Special part if dropping and initializing databases:
# - install minimal Webintake installation (no Keycloak, no database update, ...)
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

  #echo "------> Deleting Webintake directory: ${WEBINTAKE_INSTALLATION_PATH}"
  #rm -rf "${WEBINTAKE_INSTALLATION_PATH}"

fi


# Fix FK_JAC_SIT 
if [[ "$WEBINTAKE_CURRENT_VERSION" < "$COMPARE_VERSION" ]]; then
  echo "------> Fix FK_JAC_SIT"
  source ${GPROOT_OLD}/install/scripts/database/liquibase/env.sh
  WitQueries "${webintake_db_user}" "${webintake_db_password}" "${webintake_db_host}" "${webintake_db_port}" "${webintake_db_oracle_service_name}"

  echo "------> CORE queries to distill PDF files"
  CoreQueries "${runtime_db_user}" "${runtime_db_password}" "${runtime_db_host}" "${runtime_db_port}" "${runtime_db_oracle_service_name}"

fi

echo "------> Launching Webintake installation"
installWebintake "${INSTALL_KEYCLOAK}" "Y" "${DROP_INIT_DB}"


#echo "------> Creating symbolic link: webintake -> ${WEBINTAKE_INSTALLATION_PATH}"
#cd "$HOME" || exit 1
#ln -s "${WEBINTAKE_INSTALLATION_PATH}" webintake

echo "------> Launching Webintake"
serverLocalCommand start

# Check if the installation directory exists before deleting it
if [[ -d "${INSTALL_DIR}" ]]; then
  rm -rf "${INSTALL_DIR}"
  echo "The installation directory has been successfully deleted."
else
  echo "The installation directory does not exist."
fi

#Verify Installation
CheckErrors "${CURRENT_DIR}/${$LOG_FILE}"

