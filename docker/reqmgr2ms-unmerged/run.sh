#!/bin/bash

### Usage: Usage: run.sh [-e 'RSE Expression']
### Usage:
### Usage:   -e  <RSE Expression>   A Rucio RSE Expression to be passed to the service configuration
### Usage:                          before service start
### Usage:   -h <help>              Provides help to the current script
### Usage:
### Usage: Example: ./run.sh -e 'rse_type=DISK&country=US&tier=3&cms_type=real'
### Usage: Example: ./run.sh
### Usage:

FULL_SCRIPT_PATH="$(realpath "${0}")"

usage()
{
    echo -e $1
    grep '^### Usage:' < $FULL_SCRIPT_PATH
    exit 1
}

help()
{
    echo -e $1
    grep '^### Usage:' < $FULL_SCRIPT_PATH
    exit 0
}

### Searching for the mandatory and optional arguments:
# export OPTIND=1
while getopts ":e:h" opt; do
    case ${opt} in
        e)
            rseExpr=${OPTARG}
            # escaping all possible special characters in the RSE expression:
            # NOTE: One should always start escaping the escaping chars first
            rseExpr=${rseExpr//\\/\\\\}
            rseExpr=${rseExpr//&/\\&}
            rseExpr=${rseExpr//|/\\|}
            ;;
        h)
            help
            ;;
        \? )
            msg="Invalid Option: -$OPTARG"
            usage "$msg"
            ;;
        : )
            msg="Invalid Option: -$OPTARG requires an argument"
            usage "$msg"
            ;;
    esac
done


srv=`echo $USER | sed -e "s,_,,g"`

# overwrite host PEM files in /data/srv area

if [ -f /etc/robots/robotkey.pem ]; then
    sudo cp /etc/robots/robotkey.pem /data/srv/current/auth/$srv/dmwm-service-key.pem
    sudo cp /etc/robots/robotcert.pem /data/srv/current/auth/$srv/dmwm-service-cert.pem
    sudo chown $USER.$USER /data/srv/current/auth/$srv/dmwm-service-key.pem
    sudo chown $USER.$USER /data/srv/current/auth/$srv/dmwm-service-cert.pem
    sudo chmod 400  /data/srv/current/auth/$srv/dmwm-service-key.pem
    sudo chmod 440  /data/srv/current/auth/$srv/dmwm-service-cert.pem
fi

# overwrite proxy if it is present in /etc/proxy
if [ -f /etc/proxy/proxy ]; then
    export X509_USER_PROXY=/etc/proxy/proxy
    mkdir -p /data/srv/state/$srv/proxy
    if [ -f /data/srv/state/$srv/proxy/proxy.cert ]; then
        rm /data/srv/state/$srv/proxy/proxy.cert
    fi
    ln -s /etc/proxy/proxy /data/srv/state/$srv/proxy/proxy.cert
    mkdir -p /data/srv/current/auth/proxy
    if [ -f /data/srv/current/auth/proxy/proxy ]; then
        rm /data/srv/current/auth/proxy/proxy
    fi
    ln -s /etc/proxy/proxy /data/srv/current/auth/proxy/proxy
fi

# overwrite header-auth key file with one from secrets

if [ -f /etc/hmac/hmac ]; then
    mkdir -p /data/srv/current/auth/wmcore-auth
    if [ -f /data/srv/current/auth/wmcore-auth/header-auth-key ]; then
        sudo rm /data/srv/current/auth/wmcore-auth/header-auth-key
    fi
    sudo cp /etc/hmac/hmac /data/srv/current/auth/wmcore-auth/header-auth-key
    sudo chown $USER.$USER /data/srv/current/auth/wmcore-auth/header-auth-key
    sudo chmod 440 /data/srv/current/auth/wmcore-auth/header-auth-key

    mkdir -p /data/srv/current/auth/$srv
    if [ -f /data/srv/current/auth/$srv/header-auth-key ]; then
        sudo rm /data/srv/current/auth/$srv/header-auth-key
    fi
    sudo cp /etc/hmac/hmac /data/srv/current/auth/$srv/header-auth-key
    sudo chown $USER.$USER /data/srv/current/auth/$srv/header-auth-key
    sudo chmod 440 /data/srv/current/auth/$srv/header-auth-key
fi

# In case there is at least one configuration file under /etc/secrets, remove
# the default config files from the image and copy over those from the secrets area
cdir=/data/srv/current/config/$srv
cfiles="config-monitor.py config-output.py config-transferor.py config-ruleCleaner.py config-unmerged.py"
for fname in $cfiles; do
    if [ -f /etc/secrets/$fname ]; then
        pushd $cdir
        rm $cfiles
        popd
        break
    fi
done
for fname in $cfiles; do
    if [ -f /etc/secrets/$fname ]; then
        sudo cp /etc/secrets/$fname $cdir/$fname
        sudo chown $USER.$USER $cdir/$fname
    fi
done

files=`ls $cdir`
for fname in $files; do
    if [ -f /etc/secrets/$fname ]; then
        if [ -f $cdir/$fname ]; then
            rm $cdir/$fname
        fi
        sudo cp /etc/secrets/$fname $cdir/$fname
        sudo chown $USER.$USER $cdir/$fname
    fi
done

files=`ls /etc/secrets`
for fname in $files; do
    if [ ! -f $cdir/$fname ]; then
        sudo cp /etc/secrets/$fname /data/srv/current/auth/$srv/$fname
        sudo chown $USER.$USER /data/srv/current/auth/$srv/$fname
    fi
done

# before running the service, we need to make sure rucio.cfg has the correct URLs
SERVICE_CONFIG=${cdir}/config-*.py
RUCIO_CONFIG=${cdir}/etc/rucio.cfg
MATCH_RUCIO_URL=`cat ${SERVICE_CONFIG} | egrep '^RUCIO_URL =' | awk -F'=' '{print $2}' | sed 's/"//g'`
MATCH_RUCIO_AUTH_URL=`cat ${SERVICE_CONFIG} | egrep '^RUCIO_AUTH_URL =' | awk -F'=' '{print $2}' | sed 's/"//g'`
# now replace it in the rucio.cfg file
sed -i -e "s,rucio_host.*,rucio_host =${MATCH_RUCIO_URL},g" ${RUCIO_CONFIG}
sed -i -e "s,auth_host.*,auth_host =${MATCH_RUCIO_AUTH_URL},g" ${RUCIO_CONFIG}

# Edit the MSUnmerged configuration file (msConfig for the service) at runtime
# based on the set of arguments passed to the run.sh script by the service
# statrtup command defined in the .yaml file of the currently starting service
[[ -n $rseExpr ]] && sed -i -e "s/^[[:blank:]]*RSEEXPR.*/RSEEXPR = \"${rseExpr}\"/g" ${cdir}/config-unmerged.py



# start the service
sudo chmod 755 /data/srv/current/config/$srv/manage
/data/srv/current/config/$srv/manage start 'I did read documentation'

# run monitoring script
#if [ -f /data/monitor.sh ]; then
#    /data/monitor.sh
#fi

# start cron daemon
sudo /usr/sbin/crond -n