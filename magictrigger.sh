#!/bin/bash
#**********************************************************************
# Multi Testsigma Test Plan Trigger Script (FINAL)
#
# ✅ Triggers multiple test plans ONE BY ONE
# ✅ Waits until each completes
# ✅ Downloads separate JUnit reports per plan
# ✅ Saves separate JSON response per plan
# ✅ Continues even if one fails
# ✅ Shows PASS/FAIL per test plan in a summary table
# ✅ Final exit code = FAIL if any plan failed
#
# Count logic:
# 1) Try normal counts (totalCount, passedCount, failedCount...)
# 2) If null -> try consolidated counts
# 3) If still null -> parse JUnit XML (tests/failures/skipped)
#**********************************************************************

#==================== USER INPUTS ====================
TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJmZmRiMWQzMi1lNzQ5LTQzNTctOWZkNy02NmE3MTQ2YmMwMWEiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.Z7iytzLk_zxQvhbx6_WPqJQCEF9hRF45QqpTxxajWn5x5GVJRV8FWp3xbfPQgJiytghaYEBAyWAW_Y0V4_aCwA"

# Space separated test plan IDs
TESTSIGMA_TEST_PLAN_IDS="7439 4372 3519"

# Runtime data (optional)
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"

# Build number
BUILD_NO=$(date +"%Y%m%d%H%M")

# Max wait time (minutes)
MAX_WAIT_TIME_FOR_SCRIPT_TO_EXIT=180
#=====================================================


#==================== GLOBALS =========================
POLL_COUNT=60
SLEEP_TIME=$(((MAX_WAIT_TIME_FOR_SCRIPT_TO_EXIT*60)/$POLL_COUNT))

TESTSIGMA_TEST_PLAN_REST_URL="https://app.testsigma.com/api/v1/execution_results"
TESTSIGMA_JUNIT_REPORT_URL="https://app.testsigma.com/api/v1/reports/junit"

FINAL_EXIT_CODE=0
#=====================================================


#==================== HELPERS =========================
getJsonValue() {
  json_key=$1
  awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/\042'$json_key'\042/){print $(i+1)}}}' | tr -d '"'
}

safeDash() {
  # convert null/empty -> -
  val="$1"
  if [ -z "$val" ] || [ "$val" = "null" ]; then
    echo "-"
  else
    echo "$val"
  fi
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

populateBuildNo() {
  if [ -z "$BUILD_NO" ]; then
    BUILD_DATA=""
  else
    BUILD_DATA='"buildNo":"'$BUILD_NO'"'
  fi
}

populateJsonPayload() {
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

printHeader() {
  echo "************ Testsigma: Start executing multiple Test Plans ************"
  echo ""
  printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" "TESTPLAN" "TOTAL" "PASS" "FAIL" "SKIP" "RESULT"
  printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" "--------" "-----" "----" "----" "----" "------"
  echo ""
}

printRow() {
  printf "%-10s %-7s %-7s %-7s %-7s %-8s\n" \
    "$TEST_PLAN_ID" "$TOTAL_COUNT" "$PASSED_COUNT" "$FAILED_COUNT" "$SKIPPED_COUNT" "$FINAL_RESULT"
}

#=====================================================


#==================== STATUS POLLING ==================
get_status() {
  RUN_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -X GET "$TESTSIGMA_TEST_PLAN_REST_URL/$RUN_ID")

  RUN_BODY=$(echo "$RUN_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')

  EXECUTION_STATUS=$(echo "$RUN_BODY" | getJsonValue status)
  EXECUTION_RESULT=$(echo "$RUN_BODY" | getJsonValue result)

  # Normal counts
  TOTAL_COUNT=$(safeDash "$(echo "$RUN_BODY" | getJsonValue totalCount)")
  PASSED_COUNT=$(safeDash "$(echo "$RUN_BODY" | getJsonValue passedCount)")
  FAILED_COUNT=$(safeDash "$(echo "$RUN_BODY" | getJsonValue failedCount)")
  STOPPED_COUNT=$(safeDash "$(echo "$RUN_BODY" | getJsonValue stoppedCount)")
  NOT_EXECUTED_COUNT=$(safeDash "$(echo "$RUN_BODY" | getJsonValue notExecutedCount)")

  # Consolidated counts (fallback)
  CON_TOTAL=$(safeDash "$(echo "$RUN_BODY" | getJsonValue consolidatedPlanTotalCount)")
  CON_PASS=$(safeDash "$(echo "$RUN_BODY" | getJsonValue consolidatedPlanPassedCount)")
  CON_FAIL=$(safeDash "$(echo "$RUN_BODY" | getJsonValue consolidatedPlanFailedCount)")
  CON_STOP=$(safeDash "$(echo "$RUN_BODY" | getJsonValue consolidatedPlanStoppedCount)")
  CON_NOTEXEC=$(safeDash "$(echo "$RUN_BODY" | getJsonValue consolidatedPlanNotExecutedCount)")

  # If normal counts are "-" then use consolidated if available
  if [ "$TOTAL_COUNT" = "-" ] && [ "$CON_TOTAL" != "-" ]; then TOTAL_COUNT="$CON_TOTAL"; fi
  if [ "$PASSED_COUNT" = "-" ] && [ "$CON_PASS" != "-" ]; then PASSED_COUNT="$CON_PASS"; fi
  if [ "$FAILED_COUNT" = "-" ] && [ "$CON_FAIL" != "-" ]; then FAILED_COUNT="$CON_FAIL"; fi
  if [ "$STOPPED_COUNT" = "-" ] && [ "$CON_STOP" != "-" ]; then STOPPED_COUNT="$CON_STOP"; fi
  if [ "$NOT_EXECUTED_COUNT" = "-" ] && [ "$CON_NOTEXEC" != "-" ]; then NOT_EXECUTED_COUNT="$CON_NOTEXEC"; fi

  # We show SKIP as: stopped + notExecuted (if available)
  # (JUnit skip will be more accurate)
  if [ "$STOPPED_COUNT" != "-" ] && [ "$NOT_EXECUTED_COUNT" != "-" ]; then
    SKIPPED_COUNT=$((STOPPED_COUNT + NOT_EXECUTED_COUNT))
  else
    SKIPPED_COUNT="-"
  fi
}

checkTestPlanRunStatus() {
  IS_TEST_RUN_COMPLETED=0

  for ((i=0;i<=POLL_COUNT;i++))
  do
    get_status
    echo "Execution Status:: $EXECUTION_STATUS"

    if [[ "$EXECUTION_STATUS" =~ "STATUS_IN_PROGRESS" ]]; then
      sleep $SLEEP_TIME
    elif [[ "$EXECUTION_STATUS" =~ "STATUS_CREATED" ]]; then
      sleep $SLEEP_TIME
    elif [[ "$EXECUTION_STATUS" =~ "STATUS_COMPLETED" ]]; then
      IS_TEST_RUN_COMPLETED=1
      break
    else
      echo "Unexpected Execution status: $EXECUTION_STATUS"
      sleep $SLEEP_TIME
    fi
  done
}
#=====================================================


#==================== REPORT DOWNLOAD =================
saveJUnitReport() {
  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  if [ $IS_TEST_RUN_COMPLETED -eq 0 ]; then
    echo "❌ Timeout waiting for completion for Test Plan $TEST_PLAN_ID"
    return 1
  fi

  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET "$TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID" \
    --output "$REPORT_FILE"

  echo "Saved JUnit report: $REPORT_FILE"
  return 0
}

saveJsonResponse() {
  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > "$JSON_FILE"
  echo "Saved JSON response: $JSON_FILE"
}
#=====================================================


#==================== JUNIT PARSING ===================
parseJUnitCounts() {
  # Parses:
  # <testsuite tests="10" failures="1" skipped="2">
  #
  # Works without grep -P (Codemagic safe)

  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  if [ ! -f "$REPORT_FILE" ]; then
    return
  fi

  # Extract first testsuite line attributes
  TS_LINE=$(head -n 50 "$REPORT_FILE" | grep "<testsuite" | head -n 1)

  if [ -z "$TS_LINE" ]; then
    return
  fi

  J_TESTS=$(echo "$TS_LINE" | sed -n 's/.*tests="\([^"]*\)".*/\1/p')
  J_FAILS=$(echo "$TS_LINE" | sed -n 's/.*failures="\([^"]*\)".*/\1/p')
  J_SKIPS=$(echo "$TS_LINE" | sed -n 's/.*skipped="\([^"]*\)".*/\1/p')

  # If values found, override API values
  if [ -n "$J_TESTS" ]; then TOTAL_COUNT="$J_TESTS"; fi
  if [ -n "$J_FAILS" ]; then FAILED_COUNT="$J_FAILS"; fi
  if [ -n "$J_SKIPS" ]; then SKIPPED_COUNT="$J_SKIPS"; fi

  # Passed = total - fail - skip
  if [ "$TOTAL_COUNT" != "-" ] && [ "$FAILED_COUNT" != "-" ] && [ "$SKIPPED_COUNT" != "-" ]; then
    PASSED_COUNT=$((TOTAL_COUNT - FAILED_COUNT - SKIPPED_COUNT))
  fi
}
#=====================================================


#==================== MAIN ============================
printHeader

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
    -d "$JSON_DATA" -X POST "$TESTSIGMA_TEST_PLAN_REST_URL")

  RUN_ID=$(echo "$HTTP_RESPONSE" | getJsonValue id)
  HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  # If trigger failed
  if [ ! "$HTTP_STATUS" -eq 200 ]; then
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
  saveJsonResponse
  saveJUnitReport

  # Parse junit for real counts (fixes null issue)
  parseJUnitCounts

  # Decide PASS/FAIL from API result
  if [[ "$EXECUTION_RESULT" =~ "SUCCESS" ]]; then
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
#=====================================================
