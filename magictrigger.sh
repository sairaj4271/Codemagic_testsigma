#!/bin/bash
#**********************************************************************
# Enhanced Multi Testsigma Test Plan Trigger Script
# - Triggers multiple test plans one by one
# - Waits until each completes
# - Downloads separate JUnit reports per plan
# - Shows detailed statistics: PASSED/FAILED/SKIPPED test cases
# - Continues even if one fails
# - Comprehensive summary with totals
# - Final exit code = FAIL if any plan failed
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY="eyJhbGciOiJIUzUxMiJ9.eyJzdWIiOiJmZmRiMWQzMi1lNzQ5LTQzNTctOWZkNy02NmE3MTQ2YmMwMWEiLCJkb21haW4iOiJzeXNsYXRlY2guY29tIiwidGVuYW50SWQiOjU5Mzg0LCJpc0lkbGVUaW1lb3V0Q29uZmlndXJlZCI6ZmFsc2V9.Z7iytzLk_zxQvhbx6_WPqJQCEF9hRF45QqpTxxajWn5x5GVJRV8FWp3xbfPQgJiytghaYEBAyWAW_Y0V4_aCwA"

# ✅ Multiple Test Plan IDs
TESTSIGMA_TEST_PLAN_IDS="7341 3461 3828"

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

# Statistics tracking
TOTAL_TEST_PLANS=0
TOTAL_PASSED_PLANS=0
TOTAL_FAILED_PLANS=0
TOTAL_TEST_CASES=0
TOTAL_PASSED_CASES=0
TOTAL_FAILED_CASES=0
TOTAL_SKIPPED_CASES=0
TOTAL_EXECUTION_TIME=0

# Array to store detailed results
declare -a PLAN_RESULTS
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

extractTestCaseStatistics() {
  # Extract statistics from the final response
  PASSED_COUNT=$(echo $RUN_BODY | getJsonValue passedCount)
  FAILED_COUNT=$(echo $RUN_BODY | getJsonValue failedCount)
  ABORTED_COUNT=$(echo $RUN_BODY | getJsonValue abortedCount)
  NOT_EXECUTED_COUNT=$(echo $RUN_BODY | getJsonValue notExecutedCount)
  QUEUED_COUNT=$(echo $RUN_BODY | getJsonValue queuedCount)
  STOPPED_COUNT=$(echo $RUN_BODY | getJsonValue stoppedCount)
  TOTAL_COUNT=$(echo $RUN_BODY | getJsonValue totalCount)
  DURATION=$(echo $RUN_BODY | getJsonValue duration)
  
  # Handle empty values
  PASSED_COUNT=${PASSED_COUNT:-0}
  FAILED_COUNT=${FAILED_COUNT:-0}
  ABORTED_COUNT=${ABORTED_COUNT:-0}
  NOT_EXECUTED_COUNT=${NOT_EXECUTED_COUNT:-0}
  QUEUED_COUNT=${QUEUED_COUNT:-0}
  STOPPED_COUNT=${STOPPED_COUNT:-0}
  TOTAL_COUNT=${TOTAL_COUNT:-0}
  DURATION=${DURATION:-0}
  
  # Calculate skipped (aborted + not executed + stopped)
  SKIPPED_COUNT=$((ABORTED_COUNT + NOT_EXECUTED_COUNT + STOPPED_COUNT))
  
  # Convert duration from milliseconds to seconds
  DURATION_SEC=$((DURATION / 1000))
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Test Case Statistics for Test Plan $TEST_PLAN_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   Total Test Cases:    $TOTAL_COUNT"
  echo "   ✅ Passed:           $PASSED_COUNT"
  echo "   ❌ Failed:           $FAILED_COUNT"
  echo "   ⏭️  Skipped:          $SKIPPED_COUNT"
  echo "      - Aborted:        $ABORTED_COUNT"
  echo "      - Not Executed:   $NOT_EXECUTED_COUNT"
  echo "      - Stopped:        $STOPPED_COUNT"
  echo "   ⏱️  Duration:         ${DURATION_SEC}s (${DURATION}ms)"
  
  # Calculate pass rate
  if [ $TOTAL_COUNT -gt 0 ]; then
    PASS_RATE=$((PASSED_COUNT * 100 / TOTAL_COUNT))
    echo "   📈 Pass Rate:        ${PASS_RATE}%"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Update totals
  TOTAL_TEST_CASES=$((TOTAL_TEST_CASES + TOTAL_COUNT))
  TOTAL_PASSED_CASES=$((TOTAL_PASSED_CASES + PASSED_COUNT))
  TOTAL_FAILED_CASES=$((TOTAL_FAILED_CASES + FAILED_COUNT))
  TOTAL_SKIPPED_CASES=$((TOTAL_SKIPPED_CASES + SKIPPED_COUNT))
  TOTAL_EXECUTION_TIME=$((TOTAL_EXECUTION_TIME + DURATION_SEC))
}

saveJUnitReport(){
  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID \
    --output $REPORT_FILE

  echo "💾 Saved JUnit report: $REPORT_FILE"
}

saveJsonResponse(){
  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > $JSON_FILE
  echo "💾 Saved JSON response: $JSON_FILE"
}

#******************************************************
# MAIN EXECUTION
#******************************************************

START_TIME=$(date +%s)

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Testsigma Multi Test Plan Execution                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Build Number: $BUILD_NO"
echo "Runtime Data: $RUNTIME_DATA_INPUT"
echo "Test Plans: $TESTSIGMA_TEST_PLAN_IDS"
echo ""

FINAL_EXIT_CODE=0
PLAN_INDEX=0

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  TOTAL_TEST_PLANS=$((TOTAL_TEST_PLANS + 1))
  PLAN_INDEX=$((PLAN_INDEX + 1))
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Test Plan ${PLAN_INDEX}/${TOTAL_TEST_PLANS} - ID: $TEST_PLAN_ID"
  echo "╚════════════════════════════════════════════════════════════════╝"

  populateJsonPayload

  echo "🚀 Triggering test plan execution..."
  
  HTTP_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/json" \
    -H "content-type:application/json" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL )

  RUN_ID=$(echo $HTTP_RESPONSE | getJsonValue id)
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')
  HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

  if [ ! $HTTP_STATUS -eq 200 ]; then
    echo "❌ Failed to start Test Plan execution"
    echo "   HTTP Status: $HTTP_STATUS"
    echo "   Error: $HTTP_BODY"
    
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ❌ TRIGGER FAILED | 0/0/0 | HTTP $HTTP_STATUS"
    TOTAL_FAILED_PLANS=$((TOTAL_FAILED_PLANS + 1))
    FINAL_EXIT_CODE=1
    continue
  fi

  echo "✅ Execution started successfully"
  echo "   Run ID: $RUN_ID"
  echo ""
  echo "⏳ Waiting for execution to complete..."
  echo ""

  checkTestPlanRunStatus

  echo ""
  echo "✓ Execution completed"
  echo ""

  # Extract and display statistics
  extractTestCaseStatistics

  # Save reports
  saveJUnitReport
  saveJsonResponse

  # Determine plan result
  if [[ $EXECUTION_RESULT =~ "SUCCESS" ]]; then
    echo "✅ Test Plan $TEST_PLAN_ID Result: PASSED"
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ✅ PASSED | ${PASSED_COUNT}/${FAILED_COUNT}/${SKIPPED_COUNT} | ${DURATION_SEC}s"
    TOTAL_PASSED_PLANS=$((TOTAL_PASSED_PLANS + 1))
  else
    echo "❌ Test Plan $TEST_PLAN_ID Result: FAILED"
    PLAN_RESULTS[$PLAN_INDEX]="Plan $TEST_PLAN_ID | ❌ FAILED | ${PASSED_COUNT}/${FAILED_COUNT}/${SKIPPED_COUNT} | ${DURATION_SEC}s"
    TOTAL_FAILED_PLANS=$((TOTAL_FAILED_PLANS + 1))
    FINAL_EXIT_CODE=1
  fi
done

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))

# Calculate totals
TOTAL_PLAN_PASS_RATE=0
if [ $TOTAL_TEST_PLANS -gt 0 ]; then
  TOTAL_PLAN_PASS_RATE=$((TOTAL_PASSED_PLANS * 100 / TOTAL_TEST_PLANS))
fi

TOTAL_CASE_PASS_RATE=0
if [ $TOTAL_TEST_CASES -gt 0 ]; then
  TOTAL_CASE_PASS_RATE=$((TOTAL_PASSED_CASES * 100 / TOTAL_TEST_CASES))
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
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ TEST PLAN RESULTS                                              │"
echo "├────────────────────────────────────────────────────────────────┤"

for i in "${!PLAN_RESULTS[@]}"; do
  echo "│ ${PLAN_RESULTS[$i]}"
done

echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ TEST PLAN STATISTICS                                           │"
echo "├────────────────────────────────────────────────────────────────┤"
echo "│ Total Test Plans:         $TOTAL_TEST_PLANS                    "
echo "│ ✅ Passed Plans:           $TOTAL_PASSED_PLANS                  "
echo "│ ❌ Failed Plans:           $TOTAL_FAILED_PLANS                  "
echo "│ 📊 Plan Pass Rate:        ${TOTAL_PLAN_PASS_RATE}%             "
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ TEST CASE STATISTICS (ACROSS ALL PLANS)                       │"
echo "├────────────────────────────────────────────────────────────────┤"
echo "│ Total Test Cases:         $TOTAL_TEST_CASES                    "
echo "│ ✅ Passed Cases:           $TOTAL_PASSED_CASES                  "
echo "│ ❌ Failed Cases:           $TOTAL_FAILED_CASES                  "
echo "│ ⏭️  Skipped Cases:          $TOTAL_SKIPPED_CASES                "
echo "│ 📈 Case Pass Rate:        ${TOTAL_CASE_PASS_RATE}%             "
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ EXECUTION TIME                                                 │"
echo "├────────────────────────────────────────────────────────────────┤"
echo "│ Total Execution Time:     ${TOTAL_EXECUTION_TIME}s             "
echo "│ Total Wall Time:          ${TOTAL_TIME}s                       "
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ REPORTS GENERATED                                              │"
echo "├────────────────────────────────────────────────────────────────┤"

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  if [ -f "./junit-report-testplan-${TEST_PLAN_ID}.xml" ]; then
    echo "│ 📄 junit-report-testplan-${TEST_PLAN_ID}.xml                  "
  fi
  if [ -f "./testsigma-response-testplan-${TEST_PLAN_ID}.json" ]; then
    echo "│ 📄 testsigma-response-testplan-${TEST_PLAN_ID}.json           "
  fi
done

echo "└────────────────────────────────────────────────────────────────┘"
echo ""

# Final result
if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  ✅ ALL TEST PLANS PASSED                                      ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
else
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  ❌ ONE OR MORE TEST PLANS FAILED                              ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
fi

echo ""
echo "Build completed at: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

exit $FINAL_EXIT_CODE