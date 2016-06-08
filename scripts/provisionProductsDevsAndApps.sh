#!/bin/bash
# -*- mode:shell-script; coding:utf-8; -*-
#
# provisionProductsDevsAndApps.sh
#
# A bash script for provisioning a set of API Products, developers, and developer apps on
# a new organization in the Apigee Edge Gateway. Suitable for use when setting up demo orgs,
# for use with the runload proxy.
#
# Last saved: <2016-June-02 16:24:41>
#

verbosity=2
waittime=2
netrccreds=0
apiproxy=""
appslist=()
quotalimit=500
envname=""
productnamebase="TestProduct"
appnamebase="TestApp"
defaultmgmtserver="https://api.enterprise.apigee.com"
num_api_products_to_create=4
num_apps_to_create=5
credentials=""
TAB=$'\t'

developers=("Lois Lane" "Clark Kent" "Tim Prussack" "Anita Desai" "Steve Austin")

function usage() {
  local CMD=`basename $0`
  echo "$CMD: "
  echo "  Creates a set of API Products, Developers, and developer apps enabled on those"
  echo "  products. Emits the client id and secret for each."
  echo "  Uses the curl utility."
  echo "usage: "
  echo "  $CMD [options] "
  echo "options: "
  echo "  -o org    the org to use."
  echo "  -e env    the environment to enable API Products on."
  echo "  -u user   Edge admin user for the Admin API calls."
  echo "  -n        use .netrc to retrieve credentials (in lieu of -u)"
  echo "  -m url    the base url for the mgmt server."
  echo "  -a proxy  the apiproxy to use. should already be present in the org."
  echo "  -P n      specify the number of API products to create. default is ${num_api_products_to_create}"
  echo "  -A n      specify the number of developer apps to create. default is ${num_apps_to_create}"
  echo "  -q        quiet; decrease verbosity by 1"
  echo "  -v        verbose; increase verbosity by 1"
  echo
  echo "Current parameter values:"
  echo "  mgmt api url: $defaultmgmtserver"
  echo "     verbosity: $verbosity"
  echo "   environment: $envname"
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
  [ -z "${CURL_OUT}" ] && CURL_OUT=`mktemp /tmp/apigee-edge-provision-demo-org.curl.out.XXXXXX`
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

function random_string() {
  local rand_string
  rand_string=$(cat /dev/urandom |  LC_CTYPE=C  tr -cd '[:alnum:]' | head -c 10)
  echo ${rand_string}
}


function parse_deployments_output() {
  ## extract the environment names and revision numbers in the list of deployments.
  output_parsed=`cat ${CURL_OUT} | grep -A 6 -B 2 "revision"`

  if [ $? -eq 0 ]; then

    deployed_envs=`echo "${output_parsed}" | grep -B 2 revision | grep name | sed -E 's/[\",]//g'| sed -E 's/name ://g'`

    deployed_revs=`echo "${output_parsed}" | grep -A 5 revision | grep name | sed -E 's/[\",]//g'| sed -E 's/name ://g'`

    IFS=' '; declare -a rev_array=(${deployed_revs})
    IFS=' '; declare -a env_array=(${deployed_envs})

    m=${#rev_array[@]}
    if [ $verbosity -gt 1 ]; then
      echo "found ${m} deployed revisions"
    fi

    deployments=()
    let m-=1
    while [ $m -ge 0 ]; do
      rev=${rev_array[m]}
      env=${env_array[m]}
      # trim spaces
      rev="$(echo "${rev}" | tr -d '[[:space:]]')"
      env="$(echo "${env}" | tr -d '[[:space:]]')"
      echo "${env}=${rev}"
      deployments+=("${env}=${rev}")
      let m-=1
    done
    have_deployments=1
  fi
}


function api_product_name() {
    local n=$1
    local productname="${productnamebase}${n}"
    echo -n ${productname}
}


function create_new_products() {
    local m=$1 productname
    echo "create ${m} new API Products..."
    while [ $m -gt 0 ]; do
        productname=`api_product_name ${m}`
        echo "${productname}"
        sleep 2
        MYCURL \
            -H "Content-Type:application/json" \
            -X POST ${mgmtserver}/v1/o/${orgname}/apiproducts -d '{
   "approvalType" : "auto",
   "attributes" : [ ],
   "displayName" : "'${productname}' - '${apiproxy}' Test product",
   "name" : "'${productname}'",
   "apiResources" : [ "/**" ],
   "description" : "Test for '${apiproxy}'",
   "environments": [ "'${envname}'" ],
   "proxies": [ "'${apiproxy}'" ],
   "quota": "'${quotalimit}'",
   "quotaInterval": "1",
   "quotaTimeUnit": "minute"
  }'
        if [ ${CURL_RC} -ne 201 ]; then
            echo
            echoerror "  failed creating that product."
            cat ${CURL_OUT}
            echo
            echo
            exit 1
        fi

        # MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/apiproducts/${productname}
        # 
        # if [ ${CURL_RC} -ne 200 ]; then
        #     echo
        #     echoerror "  failed querying that product."
        #     cat ${CURL_OUT}
        #     echo
        #     echo
        #     exit 1
        # fi

        cat ${CURL_OUT}
        echo
        echo
        let m-=1
    done
    ## this not a local var
    num_api_products_created=$1
}

function create_new_developers() {
    local m=${#developers[@]}
    local dev names firstname lastname
    echo "creating ${m} developers..."
    let m-=1
    while [ $m -ge 0 ]; do
        dev=${developers[m]}
        names=($dev)
        firstname=${names[0]}
        lastname=${names[1]}
        email="${firstname}@example.com" 
        echo  "  create a new developer (${dev} / ${email})..."
        sleep 2
        MYCURL -X POST \
               -H "Content-type:application/json" \
               ${mgmtserver}/v1/o/${orgname}/developers \
               -d '{
    "email" : "'${email}'",
    "firstName" : "'${firstname}'",
    "lastName" : "'${lastname}'",
    "userName" : "'${firstname}'",
    "organizationName" : "'${orgname}'",
    "status" : "active"
  }' 
        if [ ${CURL_RC} -ne 201 ]; then
            echo
            echoerror "  failed creating a new developer."
            cat ${CURL_OUT}
            echo
            echo
            exit 1
        fi
        let m-=1
    done
}

function select_random_developer() {
  local num_items=${#developers[@]}
  local n=$((RANDOM%num_items))
  local dev=${developers[n]}
  local names=($dev)
  local firstname=${names[0]}
  local lastname=${names[1]}
  local email="${firstname}@example.com" 
  echo -n $email
}

function select_random_api_product() {
  local n=$((RANDOM%num_api_products_created))
  let n+=1
  echo -n `api_product_name ${n}`
}

function create_new_apps() {
    local num_apps_to_create=$1 m
    local payload developer appname apiproduct
    m=$num_apps_to_create
    echo "Creating ${m} new apps...."
    while [ $m -gt 0 ]; do
        appname="${appnamebase}-${apiproxy}-${m}"
        developer=`select_random_developer`
        apiproduct=`select_random_api_product`
        echo "  App ${appname} for ${developer} and ${apiproduct}...."
        sleep 2
        payload=$'{\n'
        payload+=$'  "attributes" : [ {\n'
        payload+=$'     "name" : "creator",\n'
        payload+=$'     "value" : "provisioning script '
        payload+="$0"
        payload+=$'"\n'
        payload+=$'    }],\n'
        payload+=$'  "apiProducts": [ "'
        payload+="${apiproduct}"
        payload+=$'" ],\n'
        payload+=$'  "callbackUrl" : "thisisnotused://www.apigee.com",\n'
        payload+=$'  "name" : "'
        payload+="${appname}"
        payload+=$'"\n}' 

        MYCURL -X POST \
               -H "Content-type:application/json" \
               ${mgmtserver}/v1/o/${orgname}/developers/${developer}/apps \
               -d "${payload}"

        if [ ${CURL_RC} -ne 201 ]; then
            echo
            echoerror "  failed creating a new app."
            cat ${CURL_OUT}
            echo
            echo
            exit 1
        fi
        retrieve_app_keys ${developer} ${appname}
        appdata="${appname}:${developer}:${apiproduct}:${consumerkey}:${consumersecret}"
        appslist+=("$appdata")
        let m-=1
    done
}


function retrieve_app_keys() {
  local devname=$1 appname=$2 array
  MYCURL -X GET ${mgmtserver}/v1/o/${orgname}/developers/${devname}/apps/${appname} 

  if [ ${CURL_RC} -ne 200 ]; then
    echo
    echoerror "  failed retrieving the app details."
    cat ${CURL_OUT}
    echo
    echo
    exit 1
  fi  

  array=(`cat ${CURL_OUT} | grep "consumerKey" | sed -E 's/[",:]//g'`)
  consumerkey=${array[1]}
  array=(`cat ${CURL_OUT} | grep "consumerSecret" | sed -E 's/[",:]//g'`)
  consumersecret=${array[1]}
}


function report_out() {
    #appname="${appnamebase}-${apiproxy}-${m}"
    ## Not sure why, but this does not work.
    ## 
    local num_apps=${#appslist[@]}
    local appinfo pieces
    let m-=1
    while [ $m -ge 0 ]; do
        appinfo=${appslist[$m]}
        pieces="$(echo "${appinfo}" | tr ':' ' ')"
        printf "%-22s %18s %16s \"%s\", \"%s\"\n" $pieces[0] $pieces[1] $pieces[2] $pieces[3] $pieces[4]
        let m-=1
    done
}




## =======================================================

echo
echo "This script creates a set of API Products, Developers, and developer apps enabled on those"
echo "products. Emits the client id and secret for each."
echo "=============================================================================="

while getopts "ho:e:u:nm:a:A:P:qv" opt; do
  case $opt in
    h) usage ;;
    m) mgmtserver=$OPTARG ;;
    o) orgname=$OPTARG ;;
    e) envname=$OPTARG ;;
    u) credentials=$OPTARG ;;
    n) netrccreds=1 ;;
    a) apiproxy=$OPTARG ;;
    A) num_apps_to_create=$OPTARG ;;
    P) num_api_products_to_create=$OPTARG ;;
    q) verbosity=$(($verbosity-1)) ;;
    v) verbosity=$(($verbosity+1)) ;;
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


create_new_products ${num_api_products_to_create}
create_new_developers
create_new_apps ${num_apps_to_create}
report_out

CleanUp
exit 0

