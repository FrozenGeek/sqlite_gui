#!/bin/bash -e

# OpenRVDAS is available as open source under the MIT License at
#   https:/github.com/oceandatatools/openrvdas
#
# A separate SQLite-based GUI for OpenRVDAS, developed by Kevin Pedigo,
# is available at
#   https://github.com/FrozenGeek/sqlite_gui
#
# This script is a part of the SQLite-based GUI. It installs the additional
# packages needed for the GUI to run, and reconfigures OpenRVDAS to use it
# by default.

# Warning:  Bashism's ahead.
########################################
#
# Initial default values
#
########################################
PREFERENCES_FILE='.install_sqlite_gui_preferences'

###########################################################################
###########################################################################
function exit_gracefully {
    echo Exiting.

    # Try deactivating virtual environment, if it's active
    if [ -n "$INSTALL_ROOT" ];then
        deactivate
    fi
    return -1 2> /dev/null || exit -1  # exit correctly if sourced/bashed
}

#########################################################################
#########################################################################
# Return a normalized yes/no for a value
yes_no() {
    QUESTION=$1
    DEFAULT_ANSWER=$2

    while true; do
        read -p "$QUESTION ($DEFAULT_ANSWER) " yn
        case $yn in
            [Yy]* )
                YES_NO_RESULT=yes
                break;;
            [Nn]* )
                YES_NO_RESULT=no
                break;;
            "" )
                YES_NO_RESULT=$DEFAULT_ANSWER
                break;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}


###########################################################################
###########################################################################
# Read any pre-saved default variables from file
function set_default_variables {
    # Defaults that will be overwritten by the preferences file, if it
    # exists.
    OPENRVDAS_ROOT='/opt/openrvdas'
    RVDAS_USER='rvdas'
    RANDOM_SECRET=yes
    MAKE_CERT=no
    USE_HTTP=no

    # Read in the preferences file, if it exists, to overwrite the defaults.
    if [ -e $PREFERENCES_FILE ]; then
        echo "#####################################################################"
        echo Reading pre-saved defaults from "$PREFERENCES_FILE"
        source $PREFERENCES_FILE
    fi
}

###########################################################################
###########################################################################
# Save defaults in a preferences file for the next time we run.
function save_default_variables {
    cat > $PREFERENCES_FILE <<EOF
# Defaults written by/to be read by install_sqlite_gui.sh
OS_TYPE=${OS_TYPE}
OPENRVDAS_ROOT=${OPENRVDAS_ROOT}
RVDAS_USER=${RVDAS_USER}
MAKE_CERT=${MAKE_CERT}
USE_HTTP=${USE_HTTP}

# For security purposes, do not save SECRET in prefs file ??
# [[ -n "${SECRET}" ]] && echo "SECRET=\"${SECRET}\""
RANDOM_SECRET=${RANDOM_SECRET}
EOF
}

# On exit, save default variables
trap save_default_variables EXIT

########################################
#
# Process command line options
#
########################################
function show_help {
    echo "Basic installation script for the sqlite_gui extension to"
    echo "OpenRVDAS."
    echo
    echo "On startup, reads .sqlitegui.prefs.  These preferences can"
    echo "be over-ridden by command line arguments."
    echo
    echo "Arguments:"
    echo " -h          show this help message"
    echo " -f <file>   load alternate config file.  Preferences will be"
    echo "             processed in the order found, so command line args"
    echo "             might get over-ridden by the included config"
    echo " -makecert   Create certificates for nginx (if you don't have any)"
    echo " -nomakecert  Don't create a certificate"
    echo " -OS_TYPE <type>  Override automatic detection of OS_TYPE and use the"
    echo "             supplied option.  Currently will accept:"
    echo "             Ubuntu - use for debian derived distros"
    echo "             CentOS - use for redhat derived distros"
    echo "             Darwin - use for apple products"
    echo " -secret <\"quoted text\">   Secret for CGI's to use for auth"
    echo " -randomsecret  Generate a random secret"
    echo " -user <OpenRVDAS user name>"
    echo " -http       Use (non-secure) http instead of https"
    echo
    echo "On exiting the script, preferences will be written out"
}

###########################################################################
###########################################################################
function ask_os_type {
    declare -A allowed
    allowed[CentOS]=CentOS
    allowed[Ubuntu]=Ubuntu
    allowed[Darwin]=Darwin
    echo "Cannot determine the OS Type.  Please select"
    while [ -z ${OS_TYPE} ] ; do
        read -p "(CentOS, Ubuntu, Darwin): " reply
        [ -z "${reply}" ] && reply="Argabarg"   # Blank indexes bad
        [[ ${allowed[$reply]+_} ]] && OS_TYPE=$reply
    done
}

###########################################################################
###########################################################################
function determine_flavor {
    # We don't need to check versions because they're already
    # running OpenRVDAS.  Simplified.  Just get the flavor.
    if [ `uname -s` == 'Darwin' ] ; then
        OS_TYPE='MacOS'
        return
    fi
    LIKE=`grep -i "id_like" /etc/os-release`
    # This will work on Fedora, Rocky, RHEL, CentOS, etc.
    [[ ${LIKE} =~ 'rhel' ]] && OS_TYPE='CentOS'
    # This will work on debian, ubuntu, RaspiOS, etc...
    [[ ${LIKE} =~ 'debian' ]] && OS_TYPE='Ubuntu'
    # SUSE/OpenSUSE say "suse" in the id_like

    echo "#####################################################################"
    echo "Detected OS = $OS_TYPE"
}

###########################################################################
###########################################################################
### supervisor
function setup_supervisor {
    echo "Setting up the supervisor config for SQLite GUI"
    if [ $OS_TYPE == 'MacOS' ]; then
        SUPERVISOR_DIR=/usr/local/etc/supervisor.d
        SUPERVISOR_SOCKET=/usr/local/var/run/supervisor.sock
        SUPERVISOR_SOURCE_FILE=${OPENRVDAS_ROOT}/sqlite_gui/supervisor/openrvdas_sqlite.ini.macos
        SUPERVISOR_TARGET_FILE=$SUPERVISOR_DIR/openrvdas_sqlite.ini
        OLD_SUPERVISOR_FILE=$SUPERVISOR_DIR/openrvdas.ini

        FCGI_PATH=/usr/local/homebrew
        FCGI_SOCKET=/var/run/fcgiwrap.sock
        NGINX_PATH=/usr/local/homebrew/bin
        NGINX_FILES=/usr/local/etc/nginx

    # CentOS/RHEL
    elif [ $OS_TYPE == 'CentOS' ]; then

        sudo ln -s -f /etc/nginx /usr/local/etc/nginx

        SUPERVISOR_DIR=/etc/supervisord.d
        SUPERVISOR_SOCKET=/var/run/supervisor/supervisor.sock
        SUPERVISOR_SOURCE_FILE=${OPENRVDAS_ROOT}/sqlite_gui/supervisor/openrvdas_sqlite.ini
        SUPERVISOR_TARGET_FILE=$SUPERVISOR_DIR/openrvdas_sqlite.ini
        OLD_SUPERVISOR_FILE=$SUPERVISOR_DIR/openrvdas.ini

        FCGI_PATH=/usr
        FCGI_SOCKET=/var/run/supervisor/fcgiwrap.sock
        NGINX_PATH=/usr/sbin
        NGINX_FILES=/etc/nginx

    # Ubuntu/Debian
    elif [ $OS_TYPE == 'Ubuntu' ]; then

        # Hack so that NGinx can look for files in same place whether we're on
        # MacOS (/usr/local/etc/nginx) or Linux (/etc/nginx)
        sudo ln -s -f /etc/nginx /usr/local/etc/nginx

        SUPERVISOR_DIR=/etc/supervisor/conf.d
        SUPERVISOR_SOCKET=/var/run/supervisor.sock
        SUPERVISOR_SOURCE_FILE=${OPENRVDAS_ROOT}/sqlite_gui/supervisor/openrvdas_sqlite.ini
        SUPERVISOR_TARGET_FILE=$SUPERVISOR_DIR/openrvdas_sqlite.conf
        OLD_SUPERVISOR_FILE=$SUPERVISOR_DIR/openrvdas.conf

        FCGI_PATH=/usr
        FCGI_SOCKET=/var/run/fcgiwrap.sock
        NGINX_PATH=/usr/sbin
        NGINX_FILES=/etc/nginx
    fi

    if [ -n "${SUPERVISOR_DIR}" ] ; then
        if [ -f ${DEST} ] ; then
            yes_no "Overwrite existing supervisor config file? " "no"
            OVERWRITE_CONFIG=$YES_NO_RESULT
        else
            OVERWRITE_CONFIG='no'
        fi
        if [ $OVERWRITE_CONFIG == 'yes' ]; then
            #echo "Copying supervisor file \"${SUPERVISOR_SOURCE_FILE}\" to \"$SUPERVISOR_TARGET_FILE"
            SUPERVISOR_TEMP_FILE='/tmp/openrvdas_sqlite.ini.tmp'
            cp ${SUPERVISOR_SOURCE_FILE} ${SUPERVISOR_TEMP_FILE}

            # First replace variables in the file with actual installation-specific values
            $SED_IE "s#OPENRVDAS_ROOT#${OPENRVDAS_ROOT}#g" ${SUPERVISOR_TEMP_FILE}
            $SED_IE "s#RVDAS_USER#${RVDAS_USER}#g" ${SUPERVISOR_TEMP_FILE}
            $SED_IE "s#SUPERVISOR_SOCKET#${SUPERVISOR_SOCKET}#g" ${SUPERVISOR_TEMP_FILE}
            $SED_IE "s#FCGI_PATH#${FCGI_PATH}#g" ${SUPERVISOR_TEMP_FILE}
            $SED_IE "s#FCGI_SOCKET#${FCGI_SOCKET}#g" ${SUPERVISOR_TEMP_FILE}
            $SED_IE "s#NGINX_PATH#${NGINX_PATH}#g" ${SUPERVISOR_TEMP_FILE}

            # Then copy into place
            sudo /bin/mv ${SUPERVISOR_TEMP_FILE} ${SUPERVISOR_TARGET_FILE}

            ## Move old openrvdas config out of the way
            #if [ -e "${OLD_SUPERVISOR_FILE}" ]; then
            #    echo "Moving OpenRVDAS supervisor config file \"${OLD_SUPERVISOR_FILE}\" out of the way"
            #    sudo /bin/mv -f ${OLD_SUPERVISOR_FILE} ${OLD_SUPERVISOR_FILE}.bak
            #fi
        fi
    else
        echo "Unable to set up supervisor for you."
    fi
}

###########################################################################
###########################################################################
function normalize_path {
    echo $(cd ${1} ; echo ${PWD})
}

###########################################################################
###########################################################################
# Figure out which directory is root for OpenRVDAS code
function get_openrvdas_root {
    DEFAULT_OPENRVDAS_ROOT=$OPENRVDAS_ROOT
    read -p "Path to OpenRVDAS installation? ($DEFAULT_OPENRVDAS_ROOT) " OPENRVDAS_ROOT
    OPENRVDAS_ROOT=${OPENRVDAS_ROOT:-$DEFAULT_OPENRVDAS_ROOT}

    # Check that we're linked in. Arbitrarily, do it by looking for this file.
    while [[ ! -f ${OPENRVDAS_ROOT}/sqlite_gui/utils/install_sqlite_gui.sh ]]; do
        echo
        echo "No \"sqlite_gui\" subdir found in OpenRVDAS installation at \"${OPENRVDAS_ROOT}\"."
        echo "Please create a symlink from the sqlite_gui code to this directory, then hit"
        read -p "\"Return\" to continue. "
    done
}

###########################################################################
###########################################################################
function make_certificate {
    SAVEPWD=${PWD}
    cd ${OPENRVDAS_ROOT}
    if [ -f ${OPENRVDAS_ROOT}/openrvdas.crt -a -f ${OPENRVDAS_ROOT}/openrvdas.key ] ; then
        echo "Looks like you already have required certificates. If you"
        echo "want to over-write them, run sqlite_gui/utils/generate_cert.sh"
    else
        /bin/bash ${OPENRVDAS_ROOT}/sqlite_gui/utils/generate_cert.sh
    fi
    cd ${SAVEPWD}
}

###########################################################################
###########################################################################
function random_secret {
    x=""
    count=`echo ${RANDOM} | cut -b1-2`
    for i in `seq 1 ${count}` ; do 
        x=${RANDOM}${x}${RANDOM}
    done
    if [ ${OS_TYPE} == 'MacOS' ] ; then
        SECRET=`echo ${x} | md5 | cut -b1-32`
    else
        SECRET=`echo ${x} | md5sum - | cut -b1-32`
    fi
    echo ${SECRET}
}

###########################################################################
###########################################################################
function set_secret {
    # sed the secret into secret.py
    echo "Setting the secret used for CGIs"
    CGIDIR=$OPENRVDAS_ROOT/sqlite_gui/cgi-bin
    /usr/bin/sed -e "s/_SECRET = \".*\"/_SECRET = \"${SECRET}\"/" $CGIDIR/secret.py.dist > $CGIDIR/secret.py
    unset SECRET
}

###########################################################################
###########################################################################
function add_system_packages {
    if [ $OS_TYPE == 'MacOS' ]; then
        echo "Installing MacOS packages"
        brew install spawn-fcgi fcgiwrap
        brew link spawn-fcgi fcgiwrap
    # CentOS/RHEL
    elif [ $OS_TYPE == 'CentOS' ]; then
        echo "Installing CentOS packages"
        sudo yum install -y spawn-fcgi fcgiwrap
    # Ubuntu/Debian
    elif [ $OS_TYPE == 'Ubuntu' ]; then
        echo "Installing Ubuntu packages"
        sudo apt-get install -y spawn-fcgi fcgiwrap
    fi
}

###########################################################################
###########################################################################
function add_python_packages {
    packages="PyJWT yamllint json5"  #  py-setproctitle"
    echo "Installing python libraries: ${packages}"
    for pkg in $packages ; do
        pip -q install $pkg
    done
}

###########################################################################
###########################################################################
function setup_nginx {
    echo "Setting up NGinx"
    NGINXDIR=${OPENRVDAS_ROOT}/sqlite_gui/nginx
    cp ${NGINXDIR}/nginx_sqlite.conf.dist ${NGINXDIR}/nginx_sqlite.conf

    # Fill in wildcards for differences between architectures
    $SED_IE "s#OPENRVDAS_ROOT#${OPENRVDAS_ROOT}#g" ${NGINXDIR}/nginx_sqlite.conf
    $SED_IE "s#RVDAS_USER#${RVDAS_USER}#g" ${NGINXDIR}/nginx_sqlite.conf
    $SED_IE "s#NGINX_PATH#${NGINX_PATH}#g" ${NGINXDIR}/nginx_sqlite.conf
    $SED_IE "s#NGINX_FILES#${NGINX_FILES}#g" ${NGINXDIR}/nginx_sqlite.conf
    $SED_IE "s#FCGI_PATH#${FCGI_PATH}#g" ${NGINXDIR}/nginx_sqlite.conf
    $SED_IE "s#FCGI_SOCKET#${FCGI_SOCKET}#g" ${NGINXDIR}/nginx_sqlite.conf

    # ... well... you never know... use http
    if [[ ${USE_HTTP} == 'yes' ]]; then
        echo "Setting nginx to use (non-secure) port 80"
        # sure, http2 is cool, but sed the sadness.

        $SED_IE "s/listen.*9000.*/listen \*:9000;/" ${NGINXDIR}/nginx_sqlite.conf
        $SED_IE "s/listen.*443.*/listen \*:80;/" ${NGINXDIR}/nginx_sqlite.conf
    fi
}

###########################################################################
###########################################################################
###########################################################################
###########################################################################
# Start of actual script
###########################################################################
###########################################################################
echo
echo "SQLite-GUI configuration script for OpenRVDAS"

###########################################################################
# Load default variables from preferences file, if it exists
set_default_variables

###########################################################################
# Parse command line arguments
while [ $# -gt 0 ] ; do
    case "$1" in
         -f)
             if [ -f $2 ] ; then
                 source $2
             else
                 echo "Config file not found: $2"
             fi
             shift
             ;;
         -makecert)
             MAKE_CERT=yes
             ;;
         -nomakecert)
             MAKE_CERT=no
             ;;
         -OS_TYPE)
             OS_TYPE=$2
             shift
             ;;
         -openrvdas_root)
             if [ -d $2 ] ; then
                 OPENRVDAS_ROOT=$2
             else
                 echo "openrvdas_root not a directory: $2"
             fi
             shift
             ;;
         -randomsecret)
             RANDOM_SECRET=yes
             ;;
         -secret)
             SECRET=$2
             shift
             ;;
         -user)
             RVDAS_USER=$2
             shift
             ;;
         -http)
             USE_HTTP=yes
             ;;
         -h)
             show_help
             exit
             ;;
         *)
             echo "Ignoring unknown option: $1"
             ;;
    esac
    shift
done

# We might have OS_TYPE in prefs
if [ -n "$OS_TYPE" ]; then
    echo "OS type set to \"$OS_TYPE\""
else
    determine_flavor
    echo "OS type inferred to be \"$OS_TYPE\""
fi

# MacOS sed uses different parameters. Sigh.
if [ $OS_TYPE == 'MacOS' ]; then
    SED_IE='/usr/bin/sed -Ie'
else
    SED_IE='/usr/bin/sed -ie'
fi

# Figure out where our installation is
echo
echo "############################################"
get_openrvdas_root

# Set ourselves up in the same virtual environment
source ${OPENRVDAS_ROOT}/venv/bin/activate

DEFAULT_RVDAS_USER=$RVDAS_USER
read -p "User to set GUI up as? ($DEFAULT_RVDAS_USER) " RVDAS_USER
RVDAS_USER=${RVDAS_USER:-$DEFAULT_RVDAS_USER}

# Set up a helper file for CGI scripts
cat >> ${OPENRVDAS_ROOT}/sqlite_gui/cgi-bin/openrvdas_vars.py << EOF
# Helper variables from OpenRVDAS

OPENRVDAS_ROOT = '${OPENRVDAS_ROOT}'
EOF

# As it says on the tin, set up the supervisor file
echo
echo "############################################"
setup_supervisor

# Generate cert/key for nginx if requested
echo
echo "############################################"
echo "Generating self-signed certificates in $OPENRVDAS_ROOT/openrvdas.[key,crt]"
#[[ "${MAKE_CERT}" == 'yes' ]] && make_certificate
make_certificate

# Generate a random secret if requested
[ "${RANDOM_SECRET}" == 'yes' ] && SECRET=`random_secret`
# If we have a secret (supplied or random), set it
[ -n "${SECRET}" ] && set_secret

echo
echo "############################################"
# Add needed system and python packages
add_system_packages
add_python_packages

echo
echo "############################################"
# Copy our NGinx config file into place and, if requested,
# modify it to use vanilla HTTP
setup_nginx

echo
echo "############################################"
echo "Reloading/restarting supervisord"
sudo supervisorctl reload
#sleep 5
#supervisorctl start sqlite:*

echo "Success! Please run "
echo
echo "  cgi-bin/user_tool.py -add --user <user> --password <password>"
echo
echo "to create a user for the SQLite web interface. "
echo
echo "Happy logging..."
