#!/bin/bash
#**********************************************************************
# Enhanced Multi Testsigma Test Plan Trigger Script - FIXED VERSION
# - Better JSON parsing
# - Handles null/empty values
# - Debug mode to see raw responses
# - Extracts statistics correctly
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

# Debug mode (set to 1 to see raw JSON responses)
DEBUG_MODE=0
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

# Better JSON parsing function using multiple methods
getJsonValue() {
  local json_key=$1
  local json_data=$2
  
  # Try method 1: Using grep and sed
  local value=$(echo "$json_data" | grep -o "\"$json_key\":[^,}]*" | sed "s/\"$json_key\"://g" | tr -d '"' | tr -d ' ')
  
  # If empty, try method 2: awk
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
  
  # Extract status and result
  EXECUTION_STATUS=$(getJsonValue "status" "$RUN_BODY")
  EXECUTION_RESULT=$(getJsonValue "result" "$RUN_BODY")
  
  if [ $DEBUG_MODE -eq 1 ]; then
    echo "DEBUG - Status Response: $RUN_BODY" >> debug.log
  fi
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
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 Extracting Test Case Statistics for Test Plan $TEST_PLAN_ID"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ $DEBUG_MODE -eq 1 ]; then
    echo ""
    echo "DEBUG - Full Response Body:"
    echo "$RUN_BODY" | python3 -m json.tool 2>/dev/null || echo "$RUN_BODY"
    echo ""
  fi
  
  # Extract statistics using improved parsing
  PASSED_COUNT=$(getJsonValue "passedCount" "$RUN_BODY")
  FAILED_COUNT=$(getJsonValue "failedCount" "$RUN_BODY")
  ABORTED_COUNT=$(getJsonValue "abortedCount" "$RUN_BODY")
  NOT_EXECUTED_COUNT=$(getJsonValue "notExecutedCount" "$RUN_BODY")
  QUEUED_COUNT=$(getJsonValue "queuedCount" "$RUN_BODY")
  STOPPED_COUNT=$(getJsonValue "stoppedCount" "$RUN_BODY")
  TOTAL_COUNT=$(getJsonValue "totalCount" "$RUN_BODY")
  DURATION=$(getJsonValue "duration" "$RUN_BODY")
  
  # Alternative field names (some Testsigma versions use different names)
  if [ -z "$PASSED_COUNT" ]; then
    PASSED_COUNT=$(getJsonValue "passed" "$RUN_BODY")
  fi
  if [ -z "$FAILED_COUNT" ]; then
    FAILED_COUNT=$(getJsonValue "failed" "$RUN_BODY")
  fi
  if [ -z "$TOTAL_COUNT" ]; then
    TOTAL_COUNT=$(getJsonValue "total" "$RUN_BODY")
  fi
  
  # Handle empty/null values - set to 0
  PASSED_COUNT=${PASSED_COUNT:-0}
  FAILED_COUNT=${FAILED_COUNT:-0}
  ABORTED_COUNT=${ABORTED_COUNT:-0}
  NOT_EXECUTED_COUNT=${NOT_EXECUTED_COUNT:-0}
  QUEUED_COUNT=${QUEUED_COUNT:-0}
  STOPPED_COUNT=${STOPPED_COUNT:-0}
  TOTAL_COUNT=${TOTAL_COUNT:-0}
  DURATION=${DURATION:-0}
  
  # Remove any non-numeric characters
  PASSED_COUNT=$(echo "$PASSED_COUNT" | tr -dc '0-9')
  FAILED_COUNT=$(echo "$FAILED_COUNT" | tr -dc '0-9')
  ABORTED_COUNT=$(echo "$ABORTED_COUNT" | tr -dc '0-9')
  NOT_EXECUTED_COUNT=$(echo "$NOT_EXECUTED_COUNT" | tr -dc '0-9')
  STOPPED_COUNT=$(echo "$STOPPED_COUNT" | tr -dc '0-9')
  TOTAL_COUNT=$(echo "$TOTAL_COUNT" | tr -dc '0-9')
  DURATION=$(echo "$DURATION" | tr -dc '0-9')
  
  # Default to 0 if still empty
  PASSED_COUNT=${PASSED_COUNT:-0}
  FAILED_COUNT=${FAILED_COUNT:-0}
  ABORTED_COUNT=${ABORTED_COUNT:-0}
  NOT_EXECUTED_COUNT=${NOT_EXECUTED_COUNT:-0}
  STOPPED_COUNT=${STOPPED_COUNT:-0}
  TOTAL_COUNT=${TOTAL_COUNT:-0}
  DURATION=${DURATION:-0}
  
  # Calculate skipped (aborted + not executed + stopped)
  SKIPPED_COUNT=$((ABORTED_COUNT + NOT_EXECUTED_COUNT + STOPPED_COUNT))
  
  # Convert duration from milliseconds to seconds
  if [ $DURATION -gt 0 ]; then
    DURATION_SEC=$((DURATION / 1000))
  else
    DURATION_SEC=0
  fi
  
  echo ""
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
  else
    PASS_RATE=0
    echo "   📈 Pass Rate:        N/A (no test cases)"
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
  
  # Try to extract statistics from JUnit report as fallback
  if [ -f "$REPORT_FILE" ] && [ $TOTAL_COUNT -eq 0 ]; then
    echo "   Attempting to extract statistics from JUnit report..."
    
    # Extract from JUnit XML
    if command -v xmllint &> /dev/null; then
      JUNIT_TOTAL=$(xmllint --xpath "string(//testsuite/@tests)" "$REPORT_FILE" 2>/dev/null)
      JUNIT_FAILURES=$(xmllint --xpath "string(//testsuite/@failures)" "$REPORT_FILE" 2>/dev/null)
      JUNIT_ERRORS=$(xmllint --xpath "string(//testsuite/@errors)" "$REPORT_FILE" 2>/dev/null)
      JUNIT_SKIPPED=$(xmllint --xpath "string(//testsuite/@skipped)" "$REPORT_FILE" 2>/dev/null)
      
      if [ -n "$JUNIT_TOTAL" ] && [ "$JUNIT_TOTAL" != "0" ]; then
        TOTAL_COUNT=$JUNIT_TOTAL
        FAILED_COUNT=$((JUNIT_FAILURES + JUNIT_ERRORS))
        SKIPPED_COUNT=${JUNIT_SKIPPED:-0}
        PASSED_COUNT=$((TOTAL_COUNT - FAILED_COUNT - SKIPPED_COUNT))
        
        echo "   ✓ Extracted from JUnit: Total=$TOTAL_COUNT, Passed=$PASSED_COUNT, Failed=$FAILED_COUNT, Skipped=$SKIPPED_COUNT"
        
        # Update totals
        TOTAL_TEST_CASES=$((TOTAL_TEST_CASES + TOTAL_COUNT))
        TOTAL_PASSED_CASES=$((TOTAL_PASSED_CASES + PASSED_COUNT))
        TOTAL_FAILED_CASES=$((TOTAL_FAILED_CASES + FAILED_COUNT))
        TOTAL_SKIPPED_CASES=$((TOTAL_SKIPPED_CASES + SKIPPED_COUNT))
      fi
    else
      # Fallback: count testcase elements
      JUNIT_TOTAL=$(grep -c "<testcase" "$REPORT_FILE" 2>/dev/null || echo "0")
      JUNIT_FAILURES=$(grep -c "<failure" "$REPORT_FILE" 2>/dev/null || echo "0")
      JUNIT_SKIPPED=$(grep -c "<skipped" "$REPORT_FILE" 2>/dev/null || echo "0")
      
      if [ "$JUNIT_TOTAL" != "0" ]; then
        TOTAL_COUNT=$JUNIT_TOTAL
        FAILED_COUNT=$JUNIT_FAILURES
        SKIPPED_COUNT=$JUNIT_SKIPPED
        PASSED_COUNT=$((TOTAL_COUNT - FAILED_COUNT - SKIPPED_COUNT))
        
        echo "   ✓ Extracted from JUnit: Total=$TOTAL_COUNT, Passed=$PASSED_COUNT, Failed=$FAILED_COUNT, Skipped=$SKIPPED_COUNT"
        
        # Update totals
        TOTAL_TEST_CASES=$((TOTAL_TEST_CASES + TOTAL_COUNT))
        TOTAL_PASSED_CASES=$((TOTAL_PASSED_CASES + PASSED_COUNT))
        TOTAL_FAILED_CASES=$((TOTAL_FAILED_CASES + FAILED_COUNT))
        TOTAL_SKIPPED_CASES=$((TOTAL_SKIPPED_CASES + SKIPPED_COUNT))
      fi
    fi
  fi
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
echo "║  Testsigma Multi Test Plan Execution (Enhanced v2)            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Build Number: $BUILD_NO"
echo "Runtime Data: $RUNTIME_DATA_INPUT"
echo "Test Plans: $TESTSIGMA_TEST_PLAN_IDS"
if [ $DEBUG_MODE -eq 1 ]; then
  echo "🐛 DEBUG MODE: ON (check debug.log for details)"
fi
echo ""

FINAL_EXIT_CODE=0
PLAN_INDEX=0

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  TOTAL_TEST_PLANS=$((TOTAL_TEST_PLANS + 1))
  PLAN_INDEX=$((PLAN_INDEX + 1))
  
  # Reset counters for this plan
  PASSED_COUNT=0
  FAILED_COUNT=0
  SKIPPED_COUNT=0
  TOTAL_COUNT=0
  DURATION_SEC=0
  
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Test Plan ${PLAN_INDEX}/${#TESTSIGMA_TEST_PLAN_IDS} - ID: $TEST_PLAN_ID"
  echo "╚════════════════════════════════════════════════════════════════╝"

  populateJsonPayload

  echo "🚀 Triggering test plan execution..."
  
  if [ $DEBUG_MODE -eq 1 ]; then
    echo "DEBUG - Request: $JSON_DATA" >> debug.log
  fi
  
  HTTP_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/json" \
    -H "content-type:application/json" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL )

  RUN_ID=$(getJsonValue "id" "$HTTP_RESPONSE")
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
  if [ -n "${PLAN_RESULTS[$i]}" ]; then
    echo "│ ${PLAN_RESULTS[$i]}"
  fi
done

echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ TEST PLAN STATISTICS                                           │"
echo "├────────────────────────────────────────────────────────────────┤"
printf "│ %-30s %-34s │\n" "Total Test Plans:" "$TOTAL_TEST_PLANS"
printf "│ %-30s %-34s │\n" "✅ Passed Plans:" "$TOTAL_PASSED_PLANS"
printf "│ %-30s %-34s │\n" "❌ Failed Plans:" "$TOTAL_FAILED_PLANS"
printf "│ %-30s %-34s │\n" "📊 Plan Pass Rate:" "${TOTAL_PLAN_PASS_RATE}%"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ TEST CASE STATISTICS (ACROSS ALL PLANS)                       │"
echo "├────────────────────────────────────────────────────────────────┤"
printf "│ %-30s %-34s │\n" "Total Test Cases:" "$TOTAL_TEST_CASES"
printf "│ %-30s %-34s │\n" "✅ Passed Cases:" "$TOTAL_PASSED_CASES"
printf "│ %-30s %-34s │\n" "❌ Failed Cases:" "$TOTAL_FAILED_CASES"
printf "│ %-30s %-34s │\n" "⏭️  Skipped Cases:" "$TOTAL_SKIPPED_CASES"
printf "│ %-30s %-34s │\n" "📈 Case Pass Rate:" "${TOTAL_CASE_PASS_RATE}%"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ EXECUTION TIME                                                 │"
echo "├────────────────────────────────────────────────────────────────┤"
printf "│ %-30s %-34s │\n" "Total Execution Time:" "${TOTAL_EXECUTION_TIME}s"
printf "│ %-30s %-34s │\n" "Total Wall Time:" "${TOTAL_TIME}s"
echo "└────────────────────────────────────────────────────────────────┘"
echo ""
echo "┌────────────────────────────────────────────────────────────────┐"
echo "│ REPORTS GENERATED                                              │"
echo "├────────────────────────────────────────────────────────────────┤"

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  if [ -f "./junit-report-testplan-${TEST_PLAN_ID}.xml" ]; then
    printf "│ 📄 %-61s │\n" "junit-report-testplan-${TEST_PLAN_ID}.xml"
  fi
  if [ -f "./testsigma-response-testplan-${TEST_PLAN_ID}.json" ]; then
    printf "│ 📄 %-61s │\n" "testsigma-response-testplan-${TEST_PLAN_ID}.json"
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

if [ $DEBUG_MODE -eq 1 ]; then
  echo "🐛 Debug log saved to: debug.log"
fi

exit $FINAL_EXIT_CODE