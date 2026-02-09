#!/bin/bash
#**********************************************************************
#
# TESTSIGMA_API_KEY -> API key generated under Testsigma App >> Configuration >> API Keys
#
# TESTSIGMA_TEST_PLAN_ID -> Testsigma Testplan ID.
# You can get this from Testsigma App >> Test Plans >> <TEST_PLAN_NAME> >> CI/CD Integration
#
# JUNIT_REPORT_FILE_PATH -> File name with directory path to save the report.
# For Example, <DIR_PATH>/report.xml, ./report.xml
#
# RUNTIME_DATA_INPUT -> Specify runtime parameters/variables to be used in the tests in comma-separated manner
# For example, "url=https://the-internet.herokuapp.com/login,variable1=value1"
#
# BUILD_NO -> Specify Build number if you want to track the builds in Testsigma.
#
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY=eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiIyYzI3NWM0OC1jMzcwLTQ0YjgtOGYxYS05ZmZmYzY0MTI4NmUiLCJkb21haW4iOiJldmllLmNvbS5hdSIsInRlbmFudElkIjo2NjY4OCwiaXNJZGxlVGltZW91dENvbmZpZ3VyZWQiOmZhbHNlfQ.4kzfASEr0Bb4_VQTxTdy41f3cKq14dwwRdJZyS9vQUj9SpMhcHv_D4sE3malkop6RSzDDuS7kZ0SAPMUOCtJYw

TESTSIGMA_TEST_PLAN_ID=1985
JUNIT_REPORT_FILE_PATH=./junit-report.xml
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"
BUILD_NO=$(date +"%Y%m%d%H%M")
#********END USER_INPUTS***********

#********GLOBAL variables**********
JSON_REPORT_FILE_PATH=./testsigma.json
TESTSIGMA_TEST_PLAN_REST_URL=https://app.testsigma.com/api/v1/execution_results
TESTSIGMA_JUNIT_REPORT_URL=https://app.testsigma.com/api/v1/reports/junit
#**********************************

#Read arguments
for i in "$@"
  do
  case $i in
    -k=*|--apikey=*)
    TESTSIGMA_API_KEY="${i#*=}"
    shift
    ;;
    -i=*|--testplanid=*)
    TESTSIGMA_TEST_PLAN_ID="${i#*=}"
    shift
    ;;
    -r=*|--reportfilepath=*)
    JUNIT_REPORT_FILE_PATH="${i#*=}"
    shift
    ;;
    -d=*|--runtimedata=*)
    RUNTIME_DATA_INPUT="${i#*=}"
    shift
    ;;
    -b=*|--buildno=*)
    BUILD_NO="${i#*=}"
    shift
    ;;
   -h|--help)
    echo "Arguments: "
    echo " [-k | --apikey] = <TESTSIGMA_API_KEY>"
    echo " [-i | --testplanid] = <TESTSIGMA_TEST_PLAN_ID>"
    echo " [-r | --reportfilepath] = <JUNIT_REPORT_FILE_PATH>"
    echo " [-d | --runtimedata] = <OPTIONAL COMMA SEPARATED KEY VALUE PAIRS>"
    echo " [-b | --buildno] = <BUILD_NO_IF_ANY>"

    printf "Example:\n bash testsigma_cicd.sh --apikey=XXXX --testplanid=230 --reportfilepath=./junit-report.xml \n\n"
    printf "With Runtimedata parameters:\n bash testsigma_cicd.sh --apikey=XXXX --testplanid=230 --reportfilepath=./junit-report.xml --runtimedata=\"url=http://test.com,data1=testdata\" --buildno=773\n\n"

    shift
    exit 1
    ;;
  esac
done

get_status(){
  RUN_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY"\
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -X GET $TESTSIGMA_TEST_PLAN_REST_URL/$RUN_ID)

  # extract the body
  RUN_BODY=$(echo $RUN_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

  echo "Test Plan Result Response: $RUN_BODY"

  # extract exec status
  EXECUTION_STATUS=$(echo $RUN_BODY | getJsonValue status)
}

function checkTestPlanRunStatus(){
  IS_TEST_RUN_COMPLETED=0

  while true
  do
    get_status
    echo "Execution Status:: $EXECUTION_STATUS"

    if [[ $EXECUTION_STATUS =~ "STATUS_IN_PROGRESS" ]]; then
      echo "Test Execution running... Waiting 10 seconds..."
      sleep 10

    elif [[ $EXECUTION_STATUS =~ "STATUS_CREATED" ]]; then
      echo "Test Execution created... Waiting 10 seconds..."
      sleep 10

    elif [[ $EXECUTION_STATUS =~ "STATUS_COMPLETED" ]]; then
      IS_TEST_RUN_COMPLETED=1
      echo "Test Execution completed..."
      break

    else
      echo "Unexpected Execution status: $EXECUTION_STATUS"
      echo "Waiting 10 seconds..."
      sleep 10
    fi
  done
}

function saveFinalResponseToJSONFile(){
  echo "$RUN_BODY" > $JSON_REPORT_FILE_PATH
  echo "Saved response to JSON Reports file - $JSON_REPORT_FILE_PATH"
}

function saveFinalResponseToJUnitFile(){
  echo ""
  echo "Downloading the Junit report..."

  curl --progress-bar -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID --output $JUNIT_REPORT_FILE_PATH

  echo "JUNIT Reports file - $JUNIT_REPORT_FILE_PATH"
}

function getJsonValue() {
  json_key=$1
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/\042'$json_key'\042/){print $(i+1)}}}' | tr -d '"'
}

function populateRuntimeData() {
  if [ -z "$RUNTIME_DATA_INPUT" ]; then
    RUN_TIME_DATA=""
    return
  fi

  IFS=',' read -r -a VARIABLES <<< "$RUNTIME_DATA_INPUT"
  RUN_TIME_DATA='"runtimeData":{'
  DATA_VALUES=
  for element in "${VARIABLES[@]}"
  do
    DATA_VALUES=$DATA_VALUES","
    IFS='=' read -r -a VARIABLE_VALUES <<< "$element"
    DATA_VALUES="$DATA_VALUES"'"'"${VARIABLE_VALUES[0]}"'":"'"${VARIABLE_VALUES[1]}"'"'
  done
  DATA_VALUES="${DATA_VALUES:1}"
  RUN_TIME_DATA=$RUN_TIME_DATA$DATA_VALUES"}"
}

function populateBuildNo(){
  if [ -z "$BUILD_NO" ]
    then
      BUILD_DATA=""
  else
    BUILD_DATA='"buildNo":'$BUILD_NO
  fi
}

function populateJsonPayload(){
  JSON_DATA='{"executionId":'$TESTSIGMA_TEST_PLAN_ID
  populateRuntimeData
  populateBuildNo

  if [ -z "$BUILD_DATA" ] && [ -z "$RUN_TIME_DATA" ]; then
    JSON_DATA=$JSON_DATA"}"
  elif [ -z "$BUILD_DATA" ]; then
    JSON_DATA=$JSON_DATA,$RUN_TIME_DATA"}"
  elif [ -z "$RUN_TIME_DATA" ]; then
    JSON_DATA=$JSON_DATA,$BUILD_DATA"}"
  else
    JSON_DATA=$JSON_DATA,$RUN_TIME_DATA,$BUILD_DATA"}"
  fi

  echo "InputData=$JSON_DATA"
}

function setExitCode(){
  RESULT=$(echo $RUN_BODY | getJsonValue result)

  if [[ $RESULT =~ "SUCCESS" ]];then
    EXITCODE=0
  else
    EXITCODE=1
  fi

  echo "Final Result: $RESULT"
  echo "Exit Code: $EXITCODE"
}

#******************************************************

echo "************ Testsigma: Start executing automated tests ************"

populateJsonPayload

HTTP_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
  -H "Accept: application/json" \
  -H "content-type:application/json" \
  --silent --write-out "HTTPSTATUS:%{http_code}" \
  -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL )

HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
RUN_ID=$(echo $HTTP_RESPONSE | getJsonValue id)
HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

NUMBERS_REGEX="^[0-9].*"
if [[ $RUN_ID =~ $NUMBERS_REGEX ]]; then
  echo "Run ID: $RUN_ID"
else
  echo "$RUN_ID"
fi

EXITCODE=0

if [ ! $HTTP_STATUS -eq 200  ]; then
  echo "Failed to start Test Plan execution!"
  echo "$HTTP_RESPONSE"
  EXITCODE=1
else
  echo "Waiting until execution completes..."
  checkTestPlanRunStatus
  saveFinalResponseToJUnitFile
  saveFinalResponseToJSONFile
  setExitCode
fi

echo "************************************************"
echo "Result JSON Response: $RUN_BODY"
echo "************ Testsigma: Completed executing automated tests ************"
exit $EXITCODE
