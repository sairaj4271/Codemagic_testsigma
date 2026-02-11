#!/bin/bash
#**********************************************************************
# Multi Testsigma Test Plan Trigger Script
# - Triggers multiple test plans one by one
# - Waits until each completes
# - Downloads separate JUnit reports per plan
# - Continues even if one fails
# - Shows PASS/FAIL + Counts per test plan
# - Final exit code = FAIL if any plan failed
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJmZmRiMWQzMi1lNzQ5LTQzNTctOWZkNy02NmE3MTQ2YmMwMWEiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.Z7iytzLk_zxQvhbx6_WPqJQCEF9hRF45QqpTxxajWn5x5GVJRV8FWp3xbfPQgJiytghaYEBAyWAW_Y0V4_aCwA"

# ✅ Multiple Test Plan IDs (space separated)
TESTSIGMA_TEST_PLAN_IDS="7341 3828 3519"

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

  # Result (use consolidatedResult if result is null)
  EXECUTION_RESULT=$(echo $RUN_BODY | getJsonValue result)
  CONSOLIDATED_RESULT=$(echo $RUN_BODY | getJsonValue consolidatedResult)

  if [[ -z "$EXECUTION_RESULT" || "$EXECUTION_RESULT" == "null" ]]; then
    EXECUTION_RESULT=$CONSOLIDATED_RESULT
  fi

  # Counts (try normal first, then consolidated)
  TOTAL_COUNT=$(echo $RUN_BODY | getJsonValue totalCount)
  PASSED_COUNT=$(echo $RUN_BODY | getJsonValue passedCount)
  FAILED_COUNT=$(echo $RUN_BODY | getJsonValue failedCount)
  STOPPED_COUNT=$(echo $RUN_BODY | getJsonValue stoppedCount)
  NOT_EXECUTED_COUNT=$(echo $RUN_BODY | getJsonValue notExecutedCount)

  CONS_TOTAL=$(echo $RUN_BODY | getJsonValue consolidatedPlanTotalCount)
  CONS_PASS=$(echo $RUN_BODY | getJsonValue consolidatedPlanPassedCount)
  CONS_FAIL=$(echo $RUN_BODY | getJsonValue consolidatedPlanFailedCount)
  CONS_STOP=$(echo $RUN_BODY | getJsonValue consolidatedPlanStoppedCount)
  CONS_NOTEXEC=$(echo $RUN_BODY | getJsonValue consolidatedPlanNotExecutedCount)

  if [[ "$TOTAL_COUNT" == "null" || -z "$TOTAL_COUNT" ]]; then TOTAL_COUNT=$CONS_TOTAL; fi
  if [[ "$PASSED_COUNT" == "null" || -z "$PASSED_COUNT" ]]; then PASSED_COUNT=$CONS_PASS; fi
  if [[ "$FAILED_COUNT" == "null" || -z "$FAILED_COUNT" ]]; then FAILED_COUNT=$CONS_FAIL; fi
  if [[ "$STOPPED_COUNT" == "null" || -z "$STOPPED_COUNT" ]]; then STOPPED_COUNT=$CONS_STOP; fi
  if [[ "$NOT_EXECUTED_COUNT" == "null" || -z "$NOT_EXECUTED_COUNT" ]]; then NOT_EXECUTED_COUNT=$CONS_NOTEXEC; fi
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

printRow(){
  printf "%-10s %-8s %-8s %-8s %-8s %-12s %-8s\n" \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

#******************************************************

echo "************ Testsigma: Start executing multiple Test Plans ************"
echo ""
printRow "TESTPLAN" "TOTAL" "PASS" "FAIL" "STOP" "NOT_EXEC" "RESULT"
printRow "--------" "-----" "----" "----" "----" "--------" "------"
echo ""

FINAL_EXIT_CODE=0
SUMMARY_RESULTS=""

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
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
    printRow "$TEST_PLAN_ID" "-" "-" "-" "-" "-" "FAIL"
    FINAL_EXIT_CODE=1
    continue
  fi

  echo "✅ Run ID: $RUN_ID"
  echo "Waiting until execution completes..."

  checkTestPlanRunStatus

  saveJUnitReport
  saveJsonResponse

  # If still null, replace with "-"
  if [[ -z "$TOTAL_COUNT" || "$TOTAL_COUNT" == "null" ]]; then TOTAL_COUNT="-"; fi
  if [[ -z "$PASSED_COUNT" || "$PASSED_COUNT" == "null" ]]; then PASSED_COUNT="-"; fi
  if [[ -z "$FAILED_COUNT" || "$FAILED_COUNT" == "null" ]]; then FAILED_COUNT="-"; fi
  if [[ -z "$STOPPED_COUNT" || "$STOPPED_COUNT" == "null" ]]; then STOPPED_COUNT="-"; fi
  if [[ -z "$NOT_EXECUTED_COUNT" || "$NOT_EXECUTED_COUNT" == "null" ]]; then NOT_EXECUTED_COUNT="-"; fi

  # PASS/FAIL logic
  if [[ $EXECUTION_RESULT =~ "SUCCESS" ]]; then
    RESULT_STATUS="PASS"
  else
    RESULT_STATUS="FAIL"
    FINAL_EXIT_CODE=1
  fi

  echo ""
  echo "📌 Test Plan $TEST_PLAN_ID Completed"
  echo "Total: $TOTAL_COUNT | Passed: $PASSED_COUNT | Failed: $FAILED_COUNT | Stopped: $STOPPED_COUNT | Not Executed: $NOT_EXECUTED_COUNT"
  echo "Result: $RESULT_STATUS"
  echo ""

  printRow "$TEST_PLAN_ID" "$TOTAL_COUNT" "$PASSED_COUNT" "$FAILED_COUNT" "$STOPPED_COUNT" "$NOT_EXECUTED_COUNT" "$RESULT_STATUS"
  echo ""
done

echo "======================================================="

if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "✅ ALL Test Plans Passed"
else
  echo "❌ One or more Test Plans Failed"
fi

exit $FINAL_EXIT_CODE
