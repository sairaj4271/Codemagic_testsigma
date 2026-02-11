#!/bin/bash
#**********************************************************************
# Multi Testsigma Test Plan Trigger Script
# - Triggers multiple test plans one by one
# - Waits until each completes
# - Downloads separate JUnit reports per plan
# - Continues even if one fails
# - Shows PASS/FAIL per test plan
# - Final exit code = FAIL if any plan failed
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiI4MTIyYmM3My1kNzE1LTRmYzYtYjhmYy01MjRmN2U4ODhlMGUiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.b_EFuzJK_iPaZZs6KxCrZOi_X4pX3JUer8Dc8PkGCCUwOnU9oOB940GCvIjyonb_j9O2fuLzAIdmoAXC_MOO7A"

# ✅ Multiple Test Plan IDs
TESTSIGMA_TEST_PLAN_IDS=" 7439 4372 3519"

# Runtime data (optional)
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"

# Build number
BUILD_NO=$(date +"%Y%m%d%H%M")

# Poll wait time
SLEEP_TIME=10
#********END USER_INPUTS***********


#********GLOBAL variables**********
TESTSIGMA_TEST_PLAN_REST_URL="https://app.testsigma.com/api/v1/execution_results"
TESTSIGMA_JUNIT_REPORT_URL="https://app.testsigma.com/api/v1/reports/junit"
#**********************************

getJsonValue() {
  json_key=$1
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/\042'$json_key'\042/){print $(i+1)}}}' | tr -d '"'
}

populateRuntimeData() {
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

populateBuildNo(){
  if [ -z "$BUILD_NO" ]; then
    BUILD_DATA=""
  else
    BUILD_DATA='"buildNo":'$BUILD_NO
  fi
}

populateJsonPayload(){
  JSON_DATA='{"executionId":'$TEST_PLAN_ID
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
}

get_status(){
  RUN_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -X GET $TESTSIGMA_TEST_PLAN_REST_URL/$RUN_ID)

  RUN_BODY=$(echo $RUN_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
  EXECUTION_STATUS=$(echo $RUN_BODY | getJsonValue status)
  EXECUTION_RESULT=$(echo $RUN_BODY | getJsonValue result)
}

checkTestPlanRunStatus(){
  while true
  do
    get_status
    echo "Execution Status:: $EXECUTION_STATUS"

    if [[ $EXECUTION_STATUS =~ "STATUS_IN_PROGRESS" ]]; then
      sleep $SLEEP_TIME

    elif [[ $EXECUTION_STATUS =~ "STATUS_CREATED" ]]; then
      sleep $SLEEP_TIME

    elif [[ $EXECUTION_STATUS =~ "STATUS_COMPLETED" ]]; then
      break

    else
      echo "Unexpected Execution status: $EXECUTION_STATUS"
      sleep $SLEEP_TIME
    fi
  done
}

saveJUnitReport(){
  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID \
    --output $REPORT_FILE

  echo "Saved JUnit report: $REPORT_FILE"
}

saveJsonResponse(){
  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > $JSON_FILE
  echo "Saved JSON response: $JSON_FILE"
}

#******************************************************

echo "************ Testsigma: Start executing multiple Test Plans ************"

FINAL_EXIT_CODE=0

# Store results
SUMMARY_RESULTS=""

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  echo ""
  echo "========================================================"
  echo "Triggering Test Plan ID: $TEST_PLAN_ID"
  echo "========================================================"

  populateJsonPayload

  HTTP_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/json" \
    -H "content-type:application/json" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL )

  RUN_ID=$(echo $HTTP_RESPONSE | getJsonValue id)
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ ! $HTTP_STATUS -eq 200 ]; then
    echo "❌ Failed to start Test Plan execution for Test Plan ID: $TEST_PLAN_ID"
    SUMMARY_RESULTS="$SUMMARY_RESULTS\nTest Plan $TEST_PLAN_ID => FAIL (Trigger Failed)"
    FINAL_EXIT_CODE=1
    continue
  fi

  echo "✅ Run ID: $RUN_ID"
  echo "Waiting until execution completes..."

  checkTestPlanRunStatus

  saveJUnitReport
  saveJsonResponse

  # PASS/FAIL based on result
  if [[ $EXECUTION_RESULT =~ "SUCCESS" ]]; then
    echo "✅ Test Plan $TEST_PLAN_ID Result: PASS"
    SUMMARY_RESULTS="$SUMMARY_RESULTS\nTest Plan $TEST_PLAN_ID => PASS"
  else
    echo "❌ Test Plan $TEST_PLAN_ID Result: FAIL"
    SUMMARY_RESULTS="$SUMMARY_RESULTS\nTest Plan $TEST_PLAN_ID => FAIL"
    FINAL_EXIT_CODE=1
  fi

done

echo ""
echo "==================== FINAL SUMMARY ===================="
echo -e "$SUMMARY_RESULTS"
echo "======================================================="

if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "✅ ALL Test Plans Passed"
else
  echo "❌ One or more Test Plans Failed"
fi

exit $FINAL_EXIT_CODE
