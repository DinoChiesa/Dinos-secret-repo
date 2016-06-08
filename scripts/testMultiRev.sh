#!/bin/bash
# -*- mode:shell-script; coding:utf-8; -*-
#
# testMultiRev.sh
#
# A bash script for testing and demonstrating the multi-revision deployment capability within Apigee Edge. 
#
# Last saved: <2016-June-08 11:48:49>
#

verbosity=1
waittime=2
want_undeploy=1
have_proxy_revisions=0
netrccreds=0
apiproxy=""
envname="test"
apiendpoint=""
httpmethod="GET"
ntrials=100
split=()
defaultmgmtserver="https://api.enterprise.apigee.com"
credentials=""
numre='^[0-9]+$'
TAB=$'\t'


function usage() {
  local CMD=`basename $0`
  echo "$CMD: "
  echo "  Tests and demonstrates the multi-revision deployment in Apigee Edge"
  echo "  Uses the curl utility."
  echo "usage: "
  echo "  $CMD [options] "
  echo "options: "
  echo "  -o org    the org to use."
  echo "  -e env    the environment to deploy API proxy on."
  echo "  -u user   Edge admin user for the Admin API calls."
  echo "  -n        use .netrc to retrieve credentials (in lieu of -u)"
  echo "  -m url    the base url for the mgmt server."
  echo "  -a proxy  the apiproxy to use. should already be present in the org."
  echo "  -E endpt  the API endpoint to test.  eg, https://foo-test.apigee.net/basepath/suffix"
  echo "  -R n:w    the revision number and relative weighting. Use this multiple times."
  echo "  -t n      number of trials to run"
  echo "  -M verb   http method to use for trial (Default: $httpmethod)"
  echo "  -U        DO NOT undeploy revisions before and after tests"
  echo "  -q        quiet; decrease verbosity by 1"
  echo "  -v        verbose; increase verbosity by 1"
  echo
  echo "Current parameter values:"
  echo "  mgmt api url: $defaultmgmtserver"
  echo "     verbosity: $verbosity"
  echo "   environment: $envname"
  echo "        trials: $ntrials"
  echo
  exit 1
}

## function MYCURL
## Print the curl command, omitting sensitive parameters, then run it.
## There are side effects:
## 1. puts curl output into file named ${CURL_OUT}. If the CURL_OUT
##    env var is not set prior to calling this function, it is created
##    and the name of a tmp file in /tmp is placed there.
## 2. puts curl http_status into variable CURL_RC
function MYCURL() {
  [ -z "${CURL_OUT}" ] && CURL_OUT=`mktemp /tmp/apigee-multirev-demo.curl.out.XXXXXX`
  [ -f "${CURL_OUT}" ] && rm ${CURL_OUT}
  [ $verbosity -gt 0 ] && echo "curl $@"
  # run the curl command
  CURL_RC=`curl $credentials -s -w "%{http_code}" -o "${CURL_OUT}" "$@"`
  [ $verbosity -gt 0 ] && echo "==> ${CURL_RC}"
}


function CleanUp() {
  [ -f ${CURL_OUT} ] && rm -rf ${CURL_OUT}
}

function echoerror() { echo "$@" 1>&2; }

function choose_mgmtserver() {
  local name
  echo
  read -p "  Which mgmt server (${defaultmgmtserver}) :: " name
  name="${name:-$defaultmgmtserver}"
  mgmtserver=$name
  echo "  mgmt server = ${mgmtserver}"
}


function verify_numeric() {
    local num=$1 label=$2
    if ! [[ $num =~ $numre ]] ; then
        echo "error: $label is not a number" >&2
        echo
        usage
        exit 1
    fi
    if [[ $num -le 0 ]]; then
        echo "error: $label must be positive" >&2
        echo
        usage
        exit 1
    fi
}


function choose_credentials() {
  local username password

  read -p "username for Edge org ${orgname} at ${mgmtserver} ? (blank to use .netrc): " username
  echo
  if [[ "$username" = "" ]] ; then  
    credentials="-n"
  else
    echo -n "Org Admin Password: "
    read -s password
    echo
    credentials="-u ${username}:${password}"
  fi
}

function maybe_ask_password() {
  local password
  if [[ ${credentials} =~ ":" ]]; then
    credentials="-u ${credentials}"
  else
    echo -n "password for ${credentials}?: "
    read -s password
    echo
    credentials="-u ${credentials}:${password}"
  fi
}


function check_org() {
  echo "  checking org ${orgname}..."
  MYCURL -X GET  ${mgmtserver}/v1/o/${orgname}
  if [ ${CURL_RC} -eq 200 ]; then
    check_org=0
  else
    check_org=1
  fi
}

function check_env() {
  echo "  checking environment ${envname}..."
  MYCURL -X GET  ${mgmtserver}/v1/o/${orgname}/e/${envname}
  if [ ${CURL_RC} -eq 200 ]; then
    check_env=0
  else
    check_env=1
  fi
}


function get_proxy_revisions() {
    local deployment rev
    if [ $have_proxy_revisions -lt 1 ]; then
  echo "  getting proxy revisions..."
    MYCURL -X GET "${mgmtserver}/v1/o/$orgname/apis/$apiproxy/revisions"
    if [ ${CURL_RC} -eq 200 ]; then
        if [ $verbosity -gt 1 ]; then
            cat ${CURL_OUT}
            echo
        fi
        proxy_revisions=(`cat ${CURL_OUT} | sed -E 's/[][",:]//g'`)
        have_proxy_revisions=1
    else
        echo "An unknown error occurred." >&2
        echo
        exit 1
    fi
    fi
}


function undeploy_as_necessary() {
    local env rev ix array
    echo "  checking to maybe undeploy proxy revisions..."
    get_proxy_revisions
    for ix in "${!proxy_revisions[@]}"; do
        rev=${proxy_revisions[ix]}
        MYCURL -X GET "${mgmtserver}/v1/o/$orgname/apis/$apiproxy/revisions/$rev/deployments"
        if [ ${CURL_RC} -eq 200 ]; then
            array=(`cat ${CURL_OUT} | grep state | sed -E 's/[\",:]//g'`)
            #echo ${array[@]}
            if [ ${#array[*]} -gt 1 ] && [[ ${array[1]} =~ "deployed" ]]; then
                array=(`cat ${CURL_OUT} | grep -A 10 environment | grep name | sed -E 's/[\",:]//g'`)
                env=${array[1]}
                if [ $verbosity -gt 0 ]; then
                    echo "Undeploying revision $rev from environment [${env}]..."
                fi
                MYCURL -X POST "${mgmtserver}/v1/o/$orgname/apis/$apiproxy/r/${rev}/deployments?action=undeploy&env=${env}"
                if [ $verbosity -gt 1 ]; then
                    cat ${CURL_OUT}
                    echo
                fi
                ## check return status, exit on fail.
                if [ ${CURL_RC} -ne 200 ]; then
                    echo "The undeploy failed." >&2
                    echo
                    CleanUp
                    exit 1
                fi
            fi
        fi

    done
}


function store_rev_split() {
    local item=$1 num1 num2
    num1=`expr "$item" : '\([^:]*\)'`
    verify_numeric "$num1" "revision"  
    num2=`expr "$item" : '[^:]*:\([^:]*\)'`
    verify_numeric "$num2" "share"  
    revs+=($num1)
    shares+=($num2)
}


function deploy_with_splits() {
    local ix rev weight
    declare -a counts=()
    for ix in "${!revs[@]}"; do
        rev=${revs[ix]}
        weight=${shares[ix]}
        counts[$rev]=0
        MYCURL -X POST -H Content-Type:application/octet-stream \
               "${mgmtserver}/v1/o/${orgname}/apis/${apiproxy}/r/${rev}/deployments?action=deploy&env=${envname}&abtest=true&weight=${weight}"
    done
}


function run_trials() {
    local m=$ntrials
    local array revision
    local oldv=$verbosity
    verbosity=0
    echo "Running ${m} trials...."
    while [ $m -gt 0 ]; do
        MYCURL -X $httpmethod ${apiendpoint}
        
        if [ ${CURL_RC} -lt 200 -o ${CURL_RC} -gt 299 ]; then
            echo
            echo "  that request failed." >&2
            cat ${CURL_OUT}
            echo
            echo
        else
            printf "."
            array=(`cat ${CURL_OUT} | grep "apiproxy.revision" | sed -E 's/[",:]//g'`)
            revision=${array[1]}
            (('counts[$revision]'++)) 
        fi
        let m-=1
    done
    printf "\n"
    verbosity=$oldv
}

function report_out() {
    local i count total=0
    echo 
    echo 
    echo Report
    echo 
    for i in "${!counts[@]}"; do
        count=${counts[$i]}
        let "total = $total + $count"
    done
        
    printf "revision   count   pct%%\n"
    echo "---------------------------"
    for i in "${!counts[@]}"; do
        count=${counts[$i]}
        let "pct = ($count * 100) / $total"
        printf "%8s  %6s    %2s%%\n" $i $count $pct
    done
    echo 
    echo 
}



## =======================================================

echo
echo "This script deploys an existing API proxy and demonstrates multi-revision deployment. "
echo "=============================================================================="

while getopts "o:e:u:nm:a:E:R:t:M:Uqvh" opt; do
  case $opt in
    o) orgname=$OPTARG ;;
    e) envname=$OPTARG ;;
    u) credentials=$OPTARG ;;
    n) netrccreds=1 ;;
    m) mgmtserver=$OPTARG ;;
    a) apiproxy=$OPTARG ;;
    E) apiendpoint=$OPTARG ;;
    R) store_rev_split $OPTARG ;;
    t) ntrials=$OPTARG ;;
    M) httpmethod=$OPTARG ;;
    U) want_undeploy=0 ;;
    q) verbosity=$(($verbosity-1)) ;;
    v) verbosity=$(($verbosity+1)) ;;
    h) usage ;;
    *) echo "unknown arg" && usage ;;
  esac
done

echo
if [ "X$mgmtserver" = "X" ]; then
  mgmtserver="$defaultmgmtserver"
fi 

echo
if [ "X$apiproxy" = "X" ]; then
    echo "You must specify an apiproxy (-a)."
    echo
    usage
    exit 1
fi 

if [ "X$orgname" = "X" ]; then
    echo "You must specify an org name (-o)."
    echo
    usage
    exit 1
fi

if [ "X$envname" = "X" ]; then
    echo "You must specify an environment name (-e)."
    echo
    usage
    exit 1
fi

num_revs=${#revs[@]}
verify_numeric "$num_revs" "number of revisions"
verify_numeric "$ntrials" "number of trials"


if [ "X$credentials" = "X" ]; then
  if [ ${netrccreds} -eq 1 ]; then
    credentials='-n'
  else
    choose_credentials
  fi 
else
  maybe_ask_password
fi 

check_org 
if [ ${check_org} -ne 0 ]; then
  echo "that org cannot be validated"
  CleanUp
  exit 1
fi

check_env
if [ ${check_env} -ne 0 ]; then
  echo "that environment cannot be validated"
  CleanUp
  exit 1
fi



if [ ${want_undeploy} -ne 0 ]; then
    undeploy_as_necessary
fi

deploy_with_splits

run_trials 

if [ ${want_undeploy} -ne 0 ]; then
  undeploy_as_necessary
fi

report_out

CleanUp

exit 0

