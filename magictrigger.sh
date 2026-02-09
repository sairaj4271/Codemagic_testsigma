#!/bin/bash
#**********************************************************************
# Multi Testsigma Test Plan Trigger Script (PARALLEL)
# - Triggers multiple test plans at once
# - Polls all until completion
# - Downloads separate JUnit reports per plan
# - Continues even if one fails
# - Final exit code = FAIL if any plan failed
#**********************************************************************

#********START USER_INPUTS*********
TESTSIGMA_API_KEY="YOUR_API_KEY_HERE"

# ✅ Multiple Test Plan IDs (space separated)
TESTSIGMA_TEST_PLAN_IDS="3160 1985 735"

# Runtime data (optional)
RUNTIME_DATA_INPUT="url=https://the-internet.herokuapp.com/login,test=1221"

# Build number
BUILD_NO=$(date +"%Y%m%d%H%M")

# Poll interval seconds
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
    BUILD_DATA='"buildNo":'$BUILD_NO
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

get_status() {
  local RUN_ID=$1

  RUN_RESPONSE=$(curl -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    --silent --write-out "HTTPSTATUS:%{http_code}" \
    -X GET $TESTSIGMA_TEST_PLAN_REST_URL/$RUN_ID)

  RUN_BODY=$(echo $RUN_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')
  EXECUTION_STATUS=$(echo $RUN_BODY | getJsonValue status)
  EXECUTION_RESULT=$(echo $RUN_BODY | getJsonValue result)
}

saveJUnitReport() {
  local TEST_PLAN_ID=$1
  local RUN_ID=$2

  REPORT_FILE="./junit-report-testplan-${TEST_PLAN_ID}.xml"

  curl --silent -H "Authorization:Bearer $TESTSIGMA_API_KEY" \
    -H "Accept: application/xml" \
    -H "content-type:application/json" \
    -X GET $TESTSIGMA_JUNIT_REPORT_URL/$RUN_ID \
    --output $REPORT_FILE

  echo "Saved JUnit report: $REPORT_FILE"
}

saveJsonResponse() {
  local TEST_PLAN_ID=$1
  local RUN_BODY=$2

  JSON_FILE="./testsigma-response-testplan-${TEST_PLAN_ID}.json"
  echo "$RUN_BODY" > $JSON_FILE
  echo "Saved JSON response: $JSON_FILE"
}

#******************************************************

echo "************ Testsigma: Start executing multiple Test Plans (PARALLEL) ************"

declare -A RUN_IDS
declare -A PLAN_STATUS
declare -A PLAN_RESULT

FINAL_EXIT_CODE=0
SUMMARY_RESULTS=""

# ======================================================
# 1) Trigger ALL test plans first
# ======================================================
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
    -d "$JSON_DATA" -X POST $TESTSIGMA_TEST_PLAN_REST_URL)

  RUN_ID=$(echo $HTTP_RESPONSE | getJsonValue id)
  HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

  if [ ! "$HTTP_STATUS" -eq 200 ]; then
    echo "❌ Failed to start execution for Test Plan ID: $TEST_PLAN_ID"
    PLAN_STATUS[$TEST_PLAN_ID]="TRIGGER_FAILED"
    PLAN_RESULT[$TEST_PLAN_ID]="FAIL"
    FINAL_EXIT_CODE=1
    continue
  fi

  echo "✅ Started Run ID: $RUN_ID"
  RUN_IDS[$TEST_PLAN_ID]=$RUN_ID
  PLAN_STATUS[$TEST_PLAN_ID]="RUNNING"
done

# ======================================================
# 2) Poll all runs until all are completed
# ======================================================
echo ""
echo "================== WAITING FOR ALL TEST PLANS =================="

ALL_DONE=0

while [ $ALL_DONE -eq 0 ]
do
  ALL_DONE=1

  for TEST_PLAN_ID in "${!RUN_IDS[@]}"
  do
    RUN_ID=${RUN_IDS[$TEST_PLAN_ID]}

    # Skip completed ones
    if [[ "${PLAN_STATUS[$TEST_PLAN_ID]}" == "COMPLETED" ]]; then
      continue
    fi

    get_status $RUN_ID

    echo "Test Plan $TEST_PLAN_ID | Run $RUN_ID | Status: $EXECUTION_STATUS"

    if [[ "$EXECUTION_STATUS" == "STATUS_COMPLETED" ]]; then
      PLAN_STATUS[$TEST_PLAN_ID]="COMPLETED"
      PLAN_RESULT[$TEST_PLAN_ID]="$EXECUTION_RESULT"

      # Save reports
      saveJUnitReport $TEST_PLAN_ID $RUN_ID
      saveJsonResponse $TEST_PLAN_ID "$RUN_BODY"

    else
      ALL_DONE=0
    fi
  done

  if [ $ALL_DONE -eq 0 ]; then
    echo "------------------------------------------------------"
    echo "Some test plans still running... Waiting $SLEEP_TIME sec"
    echo "------------------------------------------------------"
    sleep $SLEEP_TIME
  fi
done

# ======================================================
# 3) Final summary
# ======================================================
echo ""
echo "==================== FINAL SUMMARY ===================="

for TEST_PLAN_ID in $TESTSIGMA_TEST_PLAN_IDS
do
  if [[ "${PLAN_STATUS[$TEST_PLAN_ID]}" == "TRIGGER_FAILED" ]]; then
    echo "❌ Test Plan $TEST_PLAN_ID => FAIL (Trigger Failed)"
    FINAL_EXIT_CODE=1

  elif [[ "${PLAN_RESULT[$TEST_PLAN_ID]}" == "SUCCESS" ]]; then
    echo "✅ Test Plan $TEST_PLAN_ID => PASS"

  else
    echo "❌ Test Plan $TEST_PLAN_ID => FAIL"
    FINAL_EXIT_CODE=1
  fi
done

echo "======================================================="

if [ $FINAL_EXIT_CODE -eq 0 ]; then
  echo "✅ ALL Test Plans Passed"
else
  echo "❌ One or more Test Plans Failed"
fi

exit $FINAL_EXIT_CODE
