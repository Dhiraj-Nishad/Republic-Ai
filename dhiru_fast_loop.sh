#!/bin/bash

# --- CONFIG ---
WALLET="validator"  # Keyring name
VALOPER="raivaloper139mdct9kml9ypmp8dxvwcj7gms757quf5e7kyl"
MASTER_IP="20.2.88.32"
GPU_IP="46.62.188.35"
CHAIN_ID="raitestnet_77701-1"
FEES="5000000000000000arai"
# --------------

mkdir -p /root/worker_logs
LOG="/root/worker_logs/fast_loop.log"

echo "🚀 [$(date)] Dhiru Fast Loop Started" | tee -a $LOG

while true; do
    echo "--------------------------------------------------"
    echo "📡 [$(date '+%H:%M:%S')] Submitting New Job..." | tee -a $LOG
    
    # 1. Job Submit
    TX_OUT=$(republicd tx computevalidation submit-job $VALOPER republic-llm-inference:latest "http://$MASTER_IP/upload" "http://$MASTER_IP/result" example-verification:latest "1000000arai" --from $WALLET --chain-id $CHAIN_ID --fees $FEES --broadcast-mode sync -y -o json 2>/dev/null)
    TX_HASH=$(echo $TX_OUT | jq -r '.txhash')

    if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
        echo "❌ Submit Job Failed, retrying..." | tee -a $LOG
        sleep 5
        continue
    fi
    echo "🎯 Job TX: $TX_HASH" | tee -a $LOG
    
    # 2. Parallel Processing (Background)
    (
        sleep 15
        JOB_ID=$(republicd q tx $TX_HASH -o json 2>/dev/null | jq -r '.events[] | select(.type == "job_submitted") | .attributes[] | select(.key == "job_id") | .value' 2>/dev/null)

        if [ ! -z "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
            echo "⚙️  [Job $JOB_ID] Sending to GPU..." | tee -a $LOG
            ssh -o StrictHostKeyChecking=no root@$GPU_IP "screen -dmS job_$JOB_ID ~/gpu_worker.sh $JOB_ID"
            
            # GPU Processing Time (Increase for safety)
            sleep 40 
            
            FILE="/var/www/republic/result_${JOB_ID}.json"
            if [ -f "$FILE" ]; then
                # JSON Clean (Browser fix)
                python3 -c "import sys, re; d=open('$FILE').read(); m=re.search(r'\{.*\}', d, re.DOTALL); open('$FILE', 'w').write(m.group()) if m else None"
                SHA256=$(sha256sum "$FILE" | awk '{print $1}')
                
                # --- EXPLORER SUCCESS FIX ---
                # A. Generate Unsigned
                republicd tx computevalidation submit-job-result "$JOB_ID" "http://$MASTER_IP/result_${JOB_ID}.json" "example-verification:latest" "$SHA256" --from "$WALLET" --chain-id "$CHAIN_ID" --fees "$FEES" --generate-only > /tmp/unsig_${JOB_ID}.json 2>/dev/null

                # B. Force raivaloper prefix in the message body
                python3 -c "import json; tx=json.load(open('/tmp/unsig_${JOB_ID}.json')); tx['body']['messages'][0]['validator']='$VALOPER'; json.dump(tx, open('/tmp/fixed_${JOB_ID}.json','w'))"

                # C. Sign & Broadcast with specific flags
                republicd tx sign /tmp/fixed_${JOB_ID}.json --from "$WALLET" --chain-id "$CHAIN_ID" --output-document /tmp/sig_${JOB_ID}.json 2>/dev/null
                
                # Broadcast Mode 'Block' use kar rahe hain taaki confirmation pakki ho
                RESULT_TX=$(republicd tx broadcast /tmp/sig_${JOB_ID}.json --broadcast-mode sync -o json 2>/dev/null | jq -r '.txhash')
                
                echo "✅ [Job $JOB_ID] Result Explorer TX: $RESULT_TX" | tee -a $LOG
                
                # Cleanup
                rm /tmp/unsig_${JOB_ID}.json /tmp/fixed_${JOB_ID}.json /tmp/sig_${JOB_ID}.json
            else
                echo "⚠️  [Job $JOB_ID] Result file not found!" | tee -a $LOG
            fi
        fi
    ) &

    # 10 second ka gap taaki sequence mismatch na ho
    sleep 10
done
