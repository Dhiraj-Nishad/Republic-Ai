#!/bin/bash

# --- CONFIG ---
VALOPER="raivaloper139mdct9kml9ypmp8dxvwcj7gms757quf5e7kyl"
MASTER_IP="20.2.88.32"
GPU_IP="46.62.188.35"
# --------------

while true; do
    echo "--------------------------------------------------"
    echo "🚀 [$(date)] Naya Job Cycle Shuru..."

    # 1. Sequence Sync (Pakka wala)
    SEQ=$(republicd q account $(republicd keys show validator -a) --output json 2>/dev/null | jq -r '.sequence // .value.sequence')
    
    if [ -z "$SEQ" ] || [ "$SEQ" == "null" ]; then
        echo "⚠️ Sequence nahi mila, 5s wait karke retry..."
        sleep 5
        continue
    fi

    # 2. Job Submit (Sequence fix ke saath)
    echo "📡 Chain par Job bhej raha hoon (Seq: $SEQ)..."
    TX_HASH=$(republicd tx computevalidation submit-job $VALOPER republic-llm-inference:latest "http://$MASTER_IP/upload" "http://$MASTER_IP/result" example-verification:latest "1000000arai" --from validator --chain-id raitestnet_77701-1 --fees 5000000000000000arai --sequence $SEQ -y --output json | jq -r '.txhash')
    
    # Wait for Job ID
    echo "⏳ TX Hash: $TX_HASH. Confirmation ka wait..."
    JOB_ID="null"
    for i in {1..6}; do
        sleep 10
        JOB_ID=$(republicd q tx $TX_HASH -o json 2>/dev/null | jq -r '.events[] | select(.type == "job_submitted") | .attributes[] | select(.key == "job_id") | .value' 2>/dev/null)
        [ ! -z "$JOB_ID" ] && [ "$JOB_ID" != "null" ] && break
        echo "🔍 Checking Job ID (Attempt $i/6)..."
    done

    if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
        echo "❌ Job ID nahi mili, next cycle..."
        continue
    fi
    echo "🎯 Job ID Mili: $JOB_ID"

    # 3. GPU Worker ko Order
    ssh -o StrictHostKeyChecking=no root@$GPU_IP "screen -dmS job_$JOB_ID ~/gpu_worker.sh $ID"
    sleep 25 # GPU ko kaam khatam karne ka time do

    # 4. JSON Cleaning (Sabse Important)
    FILE_PATH="/var/www/republic/result_${JOB_ID}.json"
    if [ -f "$FILE_PATH" ]; then
        echo "🧹 Cleaning JSON..."
        python3 -c "import sys, re; d=open('$FILE_PATH').read(); m=re.search(r'\{.*\}', d, re.DOTALL); open('$FILE_PATH', 'w').write(m.group()) if m else None"
    else
        echo "⚠️ File nahi aayi GPU se!"
        continue
    fi

    # 5. Result Submit (No 50s break, only instant retry)
    echo "📤 Result Explorer par bhej raha hoon..."
    SHA256=$(sha256sum "$FILE_PATH" | awk '{print $1}')
    
    while true; do
        CURRENT_SEQ=$(republicd q account $(republicd keys show validator -a) --output json 2>/dev/null | jq -r '.sequence // .value.sequence')
        SUBMIT_LOG=$(republicd tx computevalidation submit-job-result "$JOB_ID" "http://$MASTER_IP/result_${JOB_ID}.json" "example-verification:latest" "$SHA256" --from validator --chain-id raitestnet_77701-1 --fees 5000000000000000arai --sequence $CURRENT_SEQ -y 2>&1)
        
        if echo "$SUBMIT_LOG" | grep -q "mismatch"; then
            echo "🔄 Seq Mismatch ($CURRENT_SEQ)! 2s mein retry..."
            sleep 2
        elif echo "$SUBMIT_LOG" | grep -q "txhash"; then
            echo "✅ Result Submitted Successfully!"
            break
        else
            echo "✅ Result Done!"
            break
        fi
    done

    echo "⚡ Loop complete, agla job turant..."
done
