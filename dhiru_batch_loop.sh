#!/bin/bash

# --- CONFIG ---
VALOPER="raivaloper139mdct9kml9ypmp8dxvwcj7gms757quf5e7kyl"
MASTER_IP="20.2.88.32"
GPU_IP="46.62.188.35"
BATCH_SIZE=10
# --------------

while true; do
    echo "--------------------------------------------------"
    echo "🚀 [$(date)] Naya Batch (10 Jobs) Shuru ho raha hai..."
    
    JOB_IDS=()

    # --- PHASE 1: SUBMIT 10 JOBS ---
    for ((i=1; i<=BATCH_SIZE; i++)); do
        echo "📡 Submitting Job $i/$BATCH_SIZE..."
        # Sequence mismatch se bachne ke liye --broadcast-mode block use kar rahe hain
        TX_HASH=$(republicd tx computevalidation submit-job $VALOPER republic-llm-inference:latest "http://$MASTER_IP/upload" "http://$MASTER_IP/result" example-verification:latest "1000000arai" --from validator --chain-id raitestnet_77701-1 --fees 5000000000000000arai --broadcast-mode block -y --output json | jq -r '.txhash')
        
        sleep 5 # Chota gap block confirmation ke liye
        
        # Job ID nikalna
        ID=$(republicd q tx $TX_HASH -o json 2>/dev/null | jq -r '.events[] | select(.type == "job_submitted") | .attributes[] | select(.key == "job_id") | .value' 2>/dev/null)
        
        if [ ! -z "$ID" ] && [ "$ID" != "null" ]; then
            echo "🎯 Job ID Mili: $ID"
            JOB_IDS+=("$ID")
            # GPU ko order bhej do turant
            ssh -o StrictHostKeyChecking=no root@$GPU_IP "screen -dmS job_$ID ~/gpu_worker.sh $ID"
        else
            echo "⚠️ Job $i fail ho gaya, skipping..."
        fi
    done

    echo "⏳ Batch submit ho gaya. Sabhi 10 jobs ke complete hone ka wait kar raha hoon (2 mins)..."
    sleep 120 # GPU ko 10 jobs khatam karne ka time do

    # --- PHASE 2: CLEAN & SUBMIT RESULTS ---
    for ID in "${JOB_IDS[@]}"; do
        FILE_PATH="/var/www/republic/result_${ID}.json"
        
        if [ -f "$FILE_PATH" ]; then
            echo "🧹 Cleaning & Submitting Result for Job: $ID"
            # JSON Clean karna
            python3 -c "import sys, re; data = open('$FILE_PATH').read(); match = re.search(r'\{.*\}', data, re.DOTALL); open('$FILE_PATH', 'w').write(match.group()) if match else None"
            
            # Submission
            SHA256=$(sha256sum "$FILE_PATH" | awk '{print $1}')
            republicd tx computevalidation submit-job-result "$ID" "http://$MASTER_IP/result_${ID}.json" "example-verification:latest" "$SHA256" --from validator --chain-id raitestnet_77701-1 --fees 5000000000000000arai --generate-only > unsigned.json
            python3 -c "import json; d=json.load(open('unsigned.json')); d['body']['messages'][0]['validator']='$VALOPER'; json.dump(d, open('unsigned_fixed.json', 'w'))"
            republicd tx sign unsigned_fixed.json --from validator --chain-id raitestnet_77701-1 --keyring-backend test > signed.json
            republicd tx broadcast signed.json --broadcast-mode block -y > /dev/null
            echo "✅ Result Submitted: $ID"
        else
            echo "❌ Job $ID ki file nahi mili, skipping..."
        fi
    done

    echo "🏁 Batch Complete! Agla batch 10 second mein..."
    sleep 10
done
