#!/bin/bash
#**********************************************************************
# Testsigma Multi Test Plan Execution - FINAL FIXED VERSION
# - Runs Test Plans ONE BY ONE
# - Waits until completion
# - Downloads JUnit per plan
# - Extracts REAL testcase counts from JUnit (testcase tags)
# - Prints clean final summary + pass rate
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJmZmRiMWQzMi1lNzQ5LTQzNTctOWZkNy02NmE3MTQ2YmMwMWEiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.Z7iytzLk_zxQvhbx6_WPqJQCEF9hRF45QqpTxxajWn5x5GVJRV8FWp3xbfPQgJiytghaYEBAyWAW_Y0V4_aCwA"

# Space separated test plan IDs
TESTSIGMA_TEST_PLAN_IDS="7341 3461 3828"

# Runtime data (optional)
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"

# Build number
BUILD_NO=$(date +"%Y%m%d%H%M")

# Poll wait time in seconds
SLEEP_TIME=10
#********END USER_INPUTS***********

#********GLOBAL variables**********
TESTSIGMA_TEST_PLAN_REST_URL="https://app.testsigma.com/api/v1/execution_results"
TESTSIGMA_JUNIT_REPORT_URL="https://app.testsigma.com/api/v1/reports/junit"

TOTAL_TEST_PLANS=0
TOTAL_PASSED_PLANS=0
TOTAL_FAILED_PLANS=0

TOTAL_TEST_CASES=0
TOTAL_PASSED_CASES=0
TOTAL_FAILED_CASES=0
TOTAL_SKIPPED_CASES=0

TOTAL_EXECUTION_TIME=0

FINAL_EXIT_CODE=0
declare -a PLAN_RESULTS
#**********************************

getJsonValue() {
  local json_key=$1
  local json_data=$2

  local value=$(echo "$json_data" | grep -o "\"$json_key\":[^,}]*" | sed "s/\"$json_key\"://g" | tr -d '"' | tr -d ' ')

  if [ -z "$value" ]; then
    value=$(echo "$json_data" | awk -F"[,:}]" '{for(i=1;i<=NF;i++){if($i~/\042'$json_key'\042/){print $(i+1)}}}' | tr -d '"' | tr -d ' ')
  fi

  echo "$value"
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
  EXECUTION_STATUS=$(getJsonValue "status" "$RUN_BODY")
  EXECUTION_RESULT=$(getJsonValue "result" "$RUN_BODY")
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
      echo "Unexpected status: $EXECUTION_STATUS"
      sleep $SLEEP_TIME
    fi
  done
}

# ✅ FINAL FIX: Always count <testcase> tags (Most reliable for Testsigma JUnit)
extractFromJUnit(){
  local REPORT_FILE=$1

  PASSED_COUNT=0
  FAILED_COUNT=0
  SKIPPED_COUNT=0
  TOTAL_COUNT=0

  if [ ! -f "$REPORT_FILE" ]; then
    return 1
  fi

  TOTAL_COUNT=$(grep -c "<testcase " "$REPORT_FILE" 2>/dev/null || echo "0")
  FAILED_COUNT=$(grep -c "<failure" "$REPORT_FILE" 2>/dev/null || echo "0")
  ERROR_COUNT=$(grep -c "<error" "$REPORT_FILE" 2>/dev/null || echo "0")
  SKIPPED_COUNT=$(grep -c "<skipped" "$REPORT_FILE" 2>/dev/null || echo "0")

  FAILED_COUNT=$((FAILED_COUNT + ERROR_COUNT))
  PASSED_COUNT=$((TOTAL_COUNT - FAILED_COUNT - SKIPPED_COUNT))

  if [ $PASSED_COUNT -lt 0 ]; then
    PASSED_COUNT=0
  fi

  if [ "$TOTAL_COUNT" -eq 0 ]; then
    return 1
  fi

  return 0
}

extractTestCaseStatistics() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Test Statistics for Plan $TEST_PLAN_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  PASSED_COUNT=0
  FAILED_COUNT=0
  SKIPPED_COUNT=0
  TOTAL_COUNT=0
  DURATION_SEC=0

  # Duration from API (ms)
  DURATION=$(getJsonValue "duration" "$RUN_BODY")
  DURATION=$(echo "$DURATION" | tr -dc '0-9')
  DURATION=${DURATION:-0}
  DURATION_SEC=$((DURATION / 1000))

  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  echo "   📥 Downloading JUnit report..."
  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID \
    --output $REPORT_FILE

  if extractFromJUnit "$REPORT_FILE"; then
    echo "   ✓ Statistics extracted from JUnit XML"
  else
    echo "   ⚠️ Could not extract from JUnit"
  fi

  echo ""
  echo "   Total:    $TOTAL_COUNT test cases"
  echo "   ✅ Passed: $PASSED_COUNT"
  echo "   ❌ Failed: $FAILED_COUNT"
  echo "   ⏭️  Skipped: $SKIPPED_COUNT"
  echo "   ⏱️  Time:   ${DURATION_SEC}s"

  if [ $TOTAL_COUNT -gt 0 ]; then
    PASS_RATE=$((PASSED_COUNT * 100 / TOTAL_COUNT))
  else
    PASS_RATE=0
  fi

  echo "   📈 Rate:   ${PASS_RATE}%"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  TOTAL_TEST_CASES=$((TOTAL_TEST_CASES + TOTAL_COUNT))
  TOTAL_PASSED_CASES=$((TOTAL_PASSED_CASES + PASSED_COUNT))
  TOTAL_FAILED_CASES=$((TOTAL_FAILED_CASES + FAILED_COUNT))
  TOTAL_SKIPPED_CASES=$((TOTAL_SKIPPED_CASES + SKIPPED_COUNT))
  TOTAL_EXECUTION_TIME=$((TOTAL_EXECUTION_TIME + DURATION_SEC))
}

saveJsonResponse(){
  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > $JSON_FILE
  echo "💾 Saved: $JSON_FILE"
}

#******************************************************
# MAIN EXECUTION
#******************************************************

START_TIME=$(date +%s)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       Testsigma Multi Test Plan Execution                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Build: $BUILD_NO"
echo "Plans: $TESTSIGMA_TEST_PLAN_IDS"
echo ""

PLAN_INDEX=0
TOTAL_PLANS_COUNT=$(echo "$TESTSIGMA_TEST_PLAN_IDS" | wc -w | tr -d ' ')

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  TOTAL_TEST_PLANS=$((TOTAL_TEST_PLANS + 1))
  PLAN_INDEX=$((PLAN_INDEX + 1))

  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Test Plan $PLAN_INDEX/$TOTAL_PLANS_COUNT - ID: $TEST_PLAN_ID"
  echo "════════════════════════════════════════════════════════════════"

  populateJsonPayload
  echo "🚀 Triggering execution..."

  HTTP_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/json" \
    -H "content-type:application/json" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL )

  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

  RUN_ID=$(getJsonValue "id" "$HTTP_BODY")

  if [ "$HTTP_STATUS" != "200" ]; then
    echo "❌ Failed to start execution for Test Plan ID: $TEST_PLAN_ID"
    echo "HTTP STATUS: $HTTP_STATUS"
    echo "HTTP BODY  : $HTTP_BODY"
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ❌ FAILED | Trigger Failed"
    TOTAL_FAILED_PLANS=$((TOTAL_FAILED_PLANS + 1))
    FINAL_EXIT_CODE=1
    continue
  fi

  echo "✅ Started - Run ID: $RUN_ID"
  echo "⏳ Waiting for completion..."
  echo ""

  checkTestPlanRunStatus

  echo ""
  echo "✓ Execution completed"

  extractTestCaseStatistics
  saveJsonResponse

  if [ $FAILED_COUNT -eq 0 ] && [ $TOTAL_COUNT -gt 0 ]; then
    echo "✅ PASSED"
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ✅ PASSED | P:$PASSED_COUNT F:$FAILED_COUNT S:$SKIPPED_COUNT | ${DURATION_SEC}s"
    TOTAL_PASSED_PLANS=$((TOTAL_PASSED_PLANS + 1))
  else
    echo "❌ FAILED"
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ❌ FAILED | P:$PASSED_COUNT F:$FAILED_COUNT S:$SKIPPED_COUNT | ${DURATION_SEC}s"
    TOTAL_FAILED_PLANS=$((TOTAL_FAILED_PLANS + 1))
    FINAL_EXIT_CODE=1
  fi
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

PLAN_PASS_RATE=0
if [ $TOTAL_TEST_PLANS -gt 0 ]; then
  PLAN_PASS_RATE=$((TOTAL_PASSED_PLANS * 100 / TOTAL_TEST_PLANS))
fi

CASE_PASS_RATE=0
if [ $TOTAL_TEST_CASES -gt 0 ]; then
  CASE_PASS_RATE=$((TOTAL_PASSED_CASES * 100 / TOTAL_TEST_CASES))
fi

#******************************************************
# FINAL SUMMARY
#******************************************************

echo ""
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    EXECUTION SUMMARY                           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "TEST PLAN RESULTS:"
echo "──────────────────────────────────────────────────────────────────"

for i in $(seq 1 $PLAN_INDEX); do
  if [ -n "${PLAN_RESULTS[$i]}" ]; then
    echo "${PLAN_RESULTS[$i]}"
  fi
done

echo ""
echo "TEST PLAN STATISTICS:"
echo "──────────────────────────────────────────────────────────────────"
echo "Total Plans:     $TOTAL_TEST_PLANS"
echo "✅ Passed:       $TOTAL_PASSED_PLANS"
echo "❌ Failed:       $TOTAL_FAILED_PLANS"
echo "📊 Pass Rate:    ${PLAN_PASS_RATE}%"

echo ""
echo "TEST CASE STATISTICS (ALL PLANS):"
echo "──────────────────────────────────────────────────────────────────"
echo "Total Cases:     $TOTAL_TEST_CASES"
echo "✅ Passed:       $TOTAL_PASSED_CASES"
echo "❌ Failed:       $TOTAL_FAILED_CASES"
echo "⏭️  Skipped:      $TOTAL_SKIPPED_CASES"
echo "📈 Pass Rate:    ${CASE_PASS_RATE}%"

echo ""
echo "EXECUTION TIME:"
echo "──────────────────────────────────────────────────────────────────"
echo "Test Time:       ${TOTAL_EXECUTION_TIME}s"
echo "Wall Time:       ${TOTAL_TIME}s"

echo ""
echo "══════════════════════════════════════════════════════════════════"

if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "✅ ALL TEST PLANS PASSED"
else
  echo "❌ ONE OR MORE TEST PLANS FAILED"
fi

echo "══════════════════════════════════════════════════════════════════"
echo ""
echo "Completed: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

exit $FINAL_EXIT_CODE
