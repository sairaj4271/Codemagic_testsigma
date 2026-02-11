#!/bin/bash
#**********************************************************************
# Multi Testsigma Test Plan Trigger Script
#
# ✅ Triggers multiple test plans one by one
# ✅ Waits until each completes
# ✅ Downloads separate JUnit reports per plan
# ✅ Saves JSON response per plan
# ✅ Continues even if one fails
# ✅ Shows PASS/FAIL per test plan in summary table
# ✅ Final exit code = FAIL if any plan failed
# ✅ Prints real API error message when trigger fails
#**********************************************************************

#==================== USER INPUTS ====================

TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiI4MTIyYmM3My1kNzE1LTRmYzYtYjhmYy01MjRmN2U4ODhlMGUiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.b_EFuzJK_iPaZZs6KxCrZOi_X4pX3JUer8Dc8PkGCCUwOnU9oOB940GCvIjyonb_j9O2fuLzAIdmoAXC_MOO7A"

# Space separated Test Plan IDs
TESTSIGMA_TEST_PLAN_IDS="7439 4372 3519"

# Optional runtime data (comma separated key=value)
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"

# Build number (optional)
BUILD_NO=$(date +"%Y%m%d%H%M")

# Max wait time in minutes per plan
MAX_WAIT_TIME_FOR_SCRIPT_TO_EXIT=180

#=====================================================


#==================== GLOBAL ==========================
POLL_COUNT=60
SLEEP_TIME=$(((MAX_WAIT_TIME_FOR_SCRIPT_TO_EXIT*60)/$POLL_COUNT))

TESTSIGMA_TEST_PLAN_REST_URL="https://app.testsigma.com/api/v1/execution_results"
TESTSIGMA_JUNIT_REPORT_URL="https://app.testsigma.com/api/v1/reports/junit"

FINAL_EXIT_CODE=0
#=====================================================


#==================== FUNCTIONS =======================

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
  DATA_VALUES=""

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
    BUILD_DATA='"buildNo":"'$BUILD_NO'"'
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

  TOTAL_COUNT=$(echo $RUN_BODY | getJsonValue totalCount)
  PASSED_COUNT=$(echo $RUN_BODY | getJsonValue passedCount)
  FAILED_COUNT=$(echo $RUN_BODY | getJsonValue failedCount)
  SKIPPED_COUNT=$(echo $RUN_BODY | getJsonValue skippedCount)

  # If null show "-"
  [ -z "$TOTAL_COUNT" ] || [ "$TOTAL_COUNT" = "null" ] && TOTAL_COUNT="-"
  [ -z "$PASSED_COUNT" ] || [ "$PASSED_COUNT" = "null" ] && PASSED_COUNT="-"
  [ -z "$FAILED_COUNT" ] || [ "$FAILED_COUNT" = "null" ] && FAILED_COUNT="-"
  [ -z "$SKIPPED_COUNT" ] || [ "$SKIPPED_COUNT" = "null" ] && SKIPPED_COUNT="-"
}

checkTestPlanRunStatus(){
  IS_TEST_RUN_COMPLETED=0

  for ((i=0;i<=POLL_COUNT;i++))
  do
    get_status
    echo "Execution Status:: $EXECUTION_STATUS"

    if [[ $EXECUTION_STATUS =~ "STATUS_IN_PROGRESS" ]]; then
      sleep $SLEEP_TIME

    elif [[ $EXECUTION_STATUS =~ "STATUS_CREATED" ]]; then
      sleep $SLEEP_TIME

    elif [[ $EXECUTION_STATUS =~ "STATUS_COMPLETED" ]]; then
      IS_TEST_RUN_COMPLETED=1
      break

    else
      echo "Unexpected Execution status: $EXECUTION_STATUS"
      sleep $SLEEP_TIME
    fi
  done
}

saveJUnitReport(){
  if [ $IS_TEST_RUN_COMPLETED -eq 0 ]; then
    echo "❌ Timeout waiting for completion for Test Plan $TEST_PLAN_ID"
    return
  fi

  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID \
    --output "$REPORT_FILE"

  echo "Saved JUnit report: $REPORT_FILE"
}

saveJsonResponse(){
  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > "$JSON_FILE"
  echo "Saved JSON response: $JSON_FILE"
}

printRow(){
  printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" \
    "$TEST_PLAN_ID" "$TOTAL_COUNT" "$PASSED_COUNT" "$FAILED_COUNT" "$SKIPPED_COUNT" "$FINAL_RESULT"
}

#=====================================================


#==================== MAIN ============================

echo "************ Testsigma: Start executing multiple Test Plans ************"
echo ""
printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" "TESTPLAN" "TOTAL" "PASS" "FAIL" "SKIP" "RESULT"
printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" "--------" "-----" "----" "----" "----" "------"
echo ""

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

  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  RUN_ID=$(echo $HTTP_BODY | getJsonValue id)

  # ✅ IMPORTANT: Print real API response when trigger fails
  if [ ! "$HTTP_STATUS" -eq 200 ]; then
    echo "❌ Failed to start execution for Test Plan ID: $TEST_PLAN_ID"
    echo "HTTP STATUS: $HTTP_STATUS"
    echo "HTTP BODY  : $HTTP_BODY"
    echo ""

    FINAL_RESULT="FAIL"
    TOTAL_COUNT="-"
    PASSED_COUNT="-"
    FAILED_COUNT="-"
    SKIPPED_COUNT="-"

    printRow
    FINAL_EXIT_CODE=1
    echo ""
    continue
  fi

  echo "✅ Run ID: $RUN_ID"
  echo "Waiting until execution completes..."

  checkTestPlanRunStatus
  saveJUnitReport
  saveJsonResponse

  # Decide PASS/FAIL
  if [[ $EXECUTION_RESULT =~ "SUCCESS" ]]; then
    FINAL_RESULT="PASS"
  else
    FINAL_RESULT="FAIL"
    FINAL_EXIT_CODE=1
  fi

  printRow
  echo ""
done

echo "======================================================="
if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "✅ ALL Test Plans Passed"
else
  echo "❌ One or more Test Plans Failed"
fi
echo "======================================================="

exit $FINAL_EXIT_CODE
