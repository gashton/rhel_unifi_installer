#!/bin/bash
#
# UniFi Installer/Upgrader
#
# This script will install Ubiquiti Networks UniFi controller as a service on RHEL/CentOS 6/7.
#
# Author: Grant Ashton
# Created: 2017-07-22
#

DIR="$(dirname $0)"
EXTRAS_DIR="${DIR}/extras"
TMP_BUILD_PATH="/tmp/unifi-build-$(date +%y%m%d-%H%M%S)"
PACKAGE_NAME="UniFi.unix.zip"
URL="https://dl.ubnt.com/unifi"
RUN_USER="unifi"
INSTALL_DIRECTORY_NAME="unifi"

MINIMUM_MONGOD_VERSION="2.4.14"
MINIMUM_JAVA_VERSION="1.8"

MONGOD_BIN=$(type -p mongod)
JAVA_BIN=$(type -p java)

function usage {
	echo -e "\e[31mUniFi CentOS/RedHat installer/upgrader\e[39m"
	echo -e "\e[31musage:\e[39m $0 \e[97m-f\e[39m install \e[97m-v\e[39m <VERSION> \e[97m-d\e[39m <INSTALL_PATH> {\e[97m-y\e[39m} {\e[97m-s\e[39m} | \e[97m-f\e[39m remove"
	echo -e " \e[97m-f <ACTION>\e[39m         \"install\" or \"remove\""
	echo -e " \e[97m-v <VERSION>\e[39m        (Install) What version to download and install"
	echo -e " \e[97m-d <INSTALL_PATH>\e[39m   (Install) Where to install UniFi"
	echo -e " \e[97m-y\e[39m                  (Install) Overwrite existing installation (Data will be backed up and restored)"
	echo -e " \e[97m-s\e[39m                  (Install) Install as service (WARNING: This will overwrite any existing configuration)"
	exit 1;
}

function check_successful {
	RET=$1
	CMD=$2

	if [[ ${RET} -gt 0 ]]; then
		logError "Error during installation (${CMD}: ${RET})"
		exit 1;
	fi
}

function logInfo {
	echo -e "\e[97m[\e[39m\e[94m${NAME}\e[97m] \e[39m$1"
}

function logError {
	echo -e "\e[39m[\e[34m${NAME}\e[39m] \e[91m$1\e[39m"
}

function install {
	#Remove trailing slash from destination path.
	DESTINATION=$(echo ${DESTINATION} | sed -r 's/\/$//g')
	INSTALL_PATH="${DESTINATION}/${INSTALL_DIRECTORY_NAME}"
	DATA_PATH="${INSTALL_PATH}/data"

	NAME="UniFi v${VERSION} Install"

	logInfo "Checking dependencies installed..."

	#Check mongodb-server
	LOCAL_MONGOD_VERSION=$(${MONGOD_BIN} --version | sed -rne 's/.*v([0-9]+\.[0-9]+\.[0-9]+)/\1/p')
	if [[ ! -x ${MONGOD_BIN} || ! $(echo -e "${LOCAL_MONGOD_VERSION}\n${MINIMUM_MONGOD_VERSION}" | sort -V | tail -n 1) == "${LOCAL_MONGOD_VERSION}" ]]; then
		logError "Required: ${MONGOD_BIN} binary version ${MINIMUM_MONGOD_VERSION} or higher. Installed: ${LOCAL_MONGOD_VERSION}"
		exit 1
	else 
		logInfo "Installed: MongoDB ${LOCAL_MONGOD_VERSION}"
	fi

	#Check java
	LOCAL_JAVA_VERSION=$(${JAVA_BIN} -version 2>&1 >/dev/null | sed -rne 's/.*version\s"([0-9]+\.[0-9]+).*/\1/p')
	if [[ ! -x ${JAVA_BIN} || ! $(echo -e "${LOCAL_JAVA_VERSION}\n${MINIMUM_JAVA_VERSION}" | sort -V | tail -n 1) == "${LOCAL_JAVA_VERSION}" ]]; then
		logError "Required: ${JAVA_BIN} binary version ${MINIMUM_JAVA_VERSION} or higher. Installed: ${LOCAL_JAVA_VERSION}"
		exit 1
	else
		logInfo "Installed: Java ${LOCAL_JAVA_VERSION}"
	fi

	mkdir -p "${TMP_BUILD_PATH}"
	check_successful $? "mkdir"

	logInfo "Downloading UniFi v${VERSION} from Ubiquiti"
	wget -P "${TMP_BUILD_PATH}" "${URL}/${VERSION}/${PACKAGE_NAME}"
	check_successful $? "wget"

	#Check if install location already exists, if so backup config.
	if [[ -d "${DATA_PATH}" ]]; then
		logInfo "Destination contains an existing installation"
		
		if [[ -f /etc/init.d/unifi ]]; then
			logInfo "Attempting to stop existing UniFi service..."
			/etc/init.d/unifi stop
		fi

		logInfo "Backing up existing installation data"	
		BACKUP_FILE="${DESTINATION}/unifi.data.$(date +%y%m%d-%H%M%S).backup"
		tar -C "${DATA_PATH}" -czvf "${BACKUP_FILE}" .
		check_successful $? "tar"
		logInfo "Backup Complete - File: ${BACKUP_FILE}"
	fi

	#Delete destination if it exists.
	if [[ -d "${INSTALL_PATH}" ]]; then
		logInfo "Destination \"${INSTALL_PATH}\" already exists, requesting deletion."
		
		if [[ ! ${YES_OVERWRITE_DESTINATION} ]]; then
			echo -n "Proceed? [Y/n]" 
			read PROCEED
		fi

		if [[ ${PROCEED} == "n" || ${PROCEED} == "N" ]]; then
			exit 1;
		fi

		logInfo "Deleted ${INSTALL_PATH}"
		rm -rf "${INSTALL_PATH}"
	fi

	# Try and make the destination in case it doesn't exist.
	mkdir -p "${DESTINATION}"
	check_successful $? "mkdir"

	logInfo "Extracting files"
	unzip -d "${TMP_BUILD_PATH}/" "${TMP_BUILD_PATH}/${PACKAGE_NAME}"
	check_successful $? "unzip"

	if [[ ! $(cat /etc/passwd | grep "^${RUN_USER}:") ]]; then
		logInfo "Adding user ${RUN_USER}"
		useradd -r ${RUN_USER}
		check_successful $? "useradd"
	fi

	mv "${TMP_BUILD_PATH}/UniFi/" "${INSTALL_PATH}"
	check_successful $? "mv"

	mkdir -p "${DATA_PATH}"
	check_successful $? "mkdir"

	if [[ -f "${BACKUP_FILE}" ]]; then
		logInfo "Restoring data backup..."
		tar -C "${DATA_PATH}" -xvf "${BACKUP_FILE}"
	fi

	logInfo "Setting SELinux contexts for mongod"
	mkdir -p "${INSTALL_PATH}/logs/"
	touch "${INSTALL_PATH}/logs/mongod.log"
	#chcon -R -v --type=mongod_var_lib_t "${INSTALL_PATH}/data/db"
	#chcon -v --type=mongod_log_t "${INSTALL_PATH}/logs/mongod.log"
	echo "unifi.db.port=27017" >> "${INSTALL_PATH}/data/system.properties"
	semanage fcontext -a -t mongod_var_lib_t "${INSTALL_PATH}/data/db(/.*)?"
	semanage fcontext -a -t mongod_log_t "${INSTALL_PATH}/logs/mongod.log"

	chown -R ${RUN_USER}:${RUN_USER} "${INSTALL_PATH}"
	check_successful $? "chown"

	if [[ ! ${YES_INSTALL_SERVICE} ]]; then
		echo -n "Install service? [Y/n]"
		read PROCEED
	fi

	if [[ ! ${PROCEED} == "n" && ! ${PROCEED} == "N" ]]; then
		logInfo "Installing service..."

		if [[ $(pgrep systemd) ]]; then
			logInfo "init: Systemd"
			
			if [[ -d "/etc/systemd/system" ]]; then
				cp "${EXTRAS_DIR}/systemd/unifi.service" "/etc/systemd/system/"

				sed -ie "s|#WORKING_DIR#|${INSTALL_PATH}|g" "/etc/systemd/system/unifi.service"

				systemctl daemon-reload
				systemctl start unifi
				systemctl status unifi
			else
				logInfo "Could not find systemd in /etc/systemd/system"
			fi
		else
			logInfo "init: Sysvinit"
			logInfo "Starting service..."
		
			cp "${EXTRAS_DIR}/init.d/unifi" "/etc/init.d/"
			sed -ie "s|BASE_DIR=\"\"|BASE_DIR=\"${INSTALL_PATH}\"|g" "/etc/init.d/unifi"
			chmod +x "/etc/init.d/unifi"

			service unifi start
		fi
	fi

	logInfo "Removing tmp build directory ${TMP_BUILD_PATH}"
	rm -rf "${TMP_BUILD_PATH}"

	logInfo "Complete - Installed: ${INSTALL_PATH}"
}

function remove {
        NAME="UniFi Removal"
	logInfo "Begin Removal"
}

NAME="UniFi Installer"

#Check for required binaries
if [[ -z "$(type unzip)" || -z "$(type wget)" ]]; then
        exit 1
fi

while getopts "v:d:f:ys" opt; do
        case ${opt} in
                v) VERSION="${OPTARG}";;
                d) DESTINATION="${OPTARG}";;
                f) FUNCTION="${OPTARG}";;
                s) YES_INSTALL_SERVICE=1;;
                y) YES_OVERWRITE_DESTINATION=1;;
                *) usage
        esac
done

if [[ "${FUNCTION}" == "install" ]]; then
	if [[ -n "${VERSION}" || -n "${DESTINATION}" ]]; then
		install
	else
		logError "Missing arguments"
		usage
	fi
elif [[ "${FUNCTION}" == "remove" ]]; then
	remove
else
	logError "Invalid function"
	usage
fi
