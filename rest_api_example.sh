#!/bin/bash

######################################################################
#
### rest_api_example.sh
#
#   Small example of the SF REST API scripting
#
#   Copyright (C) 2016 Salesforce
#
#   @author ashekhter@salesforce.com
#
#####################################################################

# ===================================================================
# Global Variables
# ===================================================================
SFUSER=''
SFPSWD=''

SFLOGIN_END_POINT=     # test.salesforce.com by default

API_VERSION="37.0"

CONTENT_TYPE_XML="text/xml"
CONTENT_TYPE_JSON="application/json"
CONTENT_TYPE="$CONTENT_TYPE_JSON"

BASE_URL="services/data/v$API_VERSION"
BASE_URL_QUERY="$BASE_URL/query/?q="
BASE_URL_SOBJS="$BASE_URL/sobjects"
BASE_URL_BATCH="$BASE_URL/composite/batch"
BASE_URL_TREE="$BASE_URL/composite/tree"

# ===================================================================
# Functions
# ===================================================================

# -------------------------------------------------------------------
# Prepare SOAP XML request for SF login
#
# @param user's name
# @param password 
# @return xml request
#
soap_login_xml() {
    local usr="$1"
    local pswd="$2"

cat << EOXML
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
    <env:Body>
        <n1:login xmlns:n1="urn:partner.soap.sforce.com">
            <n1:username>$usr</n1:username>
            <n1:password>$pswd</n1:password>
        </n1:login>
    </env:Body>
</env:Envelope>    
EOXML
}

# -------------------------------------------------------------------
# login to SF - SOAP POST since we do not want to use oAuth here
#
# @param user's name
# @param password 
# @param login end point (opt) test.salesforce.com by default
# @return SF response
#
sflogin() {
    local usr="${1}"
    local pswd="${2}"
    local lep="${3:-test.salesforce.com}"
    local xml="$(soap_login_xml $usr $pswd)"
    
    echo -e "$xml" | curl -s 'https://'"$lep"'/services/Soap/u/'"$API_VERSION" \
        -H "Content-Type: text/xml; charset=UTF-8" \
        -H "SOAPAction: login" -d @-
}

# -------------------------------------------------------------------
# extracts actual target server host from SF response
#
# Very dirty solution for simplification
#
# @param SF login response text
# @return server's host
#
server_host() {
    echo -e "$1" | awk '
    /<serverUrl>/ { 
        gsub( /^.*<serverUrl>https?:\/\//, "" ) 
        gsub( /\/.*<\/serverUrl>.*/, "" ) 
        print
    }    
    '
}

# -------------------------------------------------------------------
# extracts session id from SF login response
#
# @param SF login response text
# @return session id
#
session_id() {
    echo -e "$1" | awk '
    /<sessionId>/ {
        gsub( /^.*<sessionId>/, "" )
        gsub( /<\/sessionId>.*/, "" )
        print
    }
    '
}

# -------------------------------------------------------------------
# SF Rest POST request
#
# @param target url
# @param bearer token
# @param payload
# @return response
#
sf_rest_post() {
    echo -e "$3" | \
        curl -s -H "Content-Type: $CONTENT_TYPE; charset=UTF-8" \
            -H "Authorization: Bearer $2" "$1" -d @-
}

# -------------------------------------------------------------------
# SF Rest GET request
#
# @param target url
# @param bearer token
# @return response
#
sf_rest_get() {
    curl -s -H "Content-Type: $CONTENT_TYPE; charset=UTF-8" \
            -H "Authorization: Bearer $2" "$1"
}

# -------------------------------------------------------------------
# Prepare batch json request with accounts for deletin based 
# on batch response
#
# @param batch response
# @return json for batch deletion
#
prepare_json_for_integration_accts_deletion() {
    local batch_resp="$1"
    echo -e "{ \"batchRequests\" : ["
    python -c '
import json
jsonobj = json.loads("""'"$batch_resp"'""")
urls = list()
for r in jsonobj[ "results" ][0][ "result" ][ "records" ]:
    urls.append( """{{ "method" : "DELETE", "url" : "{0}" }}""".format( r[ "attributes" ][ "url" ] ) )
print """, """.join( urls )    
'
    echo -e "] }"
}

# -------------------------------------------------------------------
# prepares batch request to list integration Accounts and Contacts
#
# @return json for request
#
prepare_batch_list_accts_contacts_json() {
    cat <<JSON_PL
{
    "batchRequests" : [
        {
        "method" : "GET",
        "url" : "${BASE_URL_QUERY}select+id,+name+from+Account+where+name+like'IntegrationBatch%25'"
        },
        {
        "method" : "GET",
        "url" : "${BASE_URL_QUERY}select+id,+name,+AccountId+from+Contact+where+Account.name+like'IntegrationBatch%25'"
        }
    ]
}
JSON_PL

}

# -------------------------------------------------------------------
# Checks if we have Integration accounts in the ORG already
#
# @param batch_list_response
# @return 0 if we do not have and 1 if we have
#
have_integration_accts() {
    local batch_resp="$1"
    local total_integr_accts=$(python -c '
import json
jsonobj = json.loads("""'"$batch_resp"'""")
print jsonobj[ "results" ][0][ "result" ][ "totalSize" ]
')

    if [ "$total_integr_accts" -gt "0" ]; then
        return 1
    else
        return 0
    fi
}

# -------------------------------------------------------------------
# Prepares Tree request to insert Accounts and Contacts
#
# #return json 
#
prepare_tree_accounts_contacts_json() {
    cat <<JSON_PL
{
"records" :[{
    "attributes" : {"type" : "Account", "referenceId" : "ref1"},
    "name" : "IntegrationBatch 1",
    "phone" : "1234567890",
    "website" : "www.salesforce.com",
    "numberOfEmployees" : "100",
    "industry" : "Banking",
    "Contacts" : {
      "records" : [{
         "attributes" : {"type" : "Contact", "referenceId" : "ref2"},
         "lastname" : "Smith",
         "title" : "President",
         "email" : "sample@salesforce.com"
         },{         
         "attributes" : {"type" : "Contact", "referenceId" : "ref3"},
         "lastname" : "Evans",
         "title" : "Vice President",
         "email" : "sample@salesforce.com"
         }]
      }
    },{
    "attributes" : {"type" : "Account", "referenceId" : "ref4"},
    "name" : "IntegrationBatch 2",
    "phone" : "1234567890",
    "website" : "www.salesforce2.com",
    "numberOfEmployees" : "100",
    "industry" : "Banking"
     }]
}
JSON_PL

}

# ===================================================================
# Entry Point
# ===================================================================

if [[ "$usr" == "" || "$pswd" == "" ]]; then
    echo "ERROR: Please make sure that SFUSER and SFPSWD global script constants are set!"
    exit 1
fi    

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Login
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
login_resp="$(sflogin ''"$SFUSER"'' ''"$SFPSWD"'')"
echo -e "\n>>> Login Response:\n\n$login_resp"
sfhost=$(server_host "$login_resp") 
session=$(session_id "$login_resp")

echo -e "\nSF HOST=$sfhost"
echo -e "SESSION=$session"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Batch request to get Accounts and Contacts
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
batch_req=$(prepare_batch_list_accts_contacts_json)
echo -e "\n>>> BATCH REQUEST FOR EXISTING INTEGRATION ACCOUNTS and CONTACTS:\n\n$batch_req"
batch_resp=$(sf_rest_post "https://$sfhost/$BASE_URL_BATCH" "$session" "$batch_req")
echo -e "\n>>> BATCH RESPONSE TO GET INTEGRATION ACCOUNTS and CONTACTS:\n\n$batch_resp"

have_integration_accts "$batch_resp"
if [ "$?" -gt "0" ]; then
    batch_req=$(prepare_json_for_integration_accts_deletion "$batch_resp")
    echo -e "\n>>> BATCH JSON TO CLEANUP INTEGRATION ACCOUNTS\n\n$batch_req"
    batch_resp=$(sf_rest_post "https://$sfhost/$BASE_URL_BATCH" "$session" "$batch_req")
    echo -e "\n>>> BATCH RESPONSE AFTER ACCOUNTS CLEANUP:\n\n$batch_resp"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Tree request to create multiple Accounts and Contacts
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
tree_req=$(prepare_tree_accounts_contacts_json)
echo -e "\n>>> TREE REQUEST:\n\n$tree_req"
tree_resp=$(sf_rest_post "https://$sfhost/$BASE_URL_TREE/Account/" "$session" "$tree_req")
echo -e "\n>>> TREE RESPONSE:\n\n$tree_resp"
