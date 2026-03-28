#!/bin/bash
WALLET="validator"
VALOPER="raivaloper139mdct9kml9ypmp8dxvwcj7gms757quf5e7kyl"
GH_USER="Dhiraj-Nishad"
GH_REPO="Republic-Ai"
MASTER_IP="20.2.88.32"

mkdir -p /root/worker_logs
LOG="/root/worker_logs/github_loop.log"

while true; do
    echo "--------------------------------------------------"
    echo "📡 [$(date '+%H:%M:%S')] Submitting New Job..." | tee -a $LOG
    
    TX_OUT=$(republicd tx computevalidation submit-job $VALOPER republic-llm-inference:latest "http://$MASTER_IP/upload" "http://$MASTER_IP/result" example-verification:latest "1000000arai" --from $WALLET --chain-id raitestnet_77701-1 --fees 5000000000000000arai --broadcast-mode sync -y -o json 2>/dev/null)
    TX_HASH=$(echo $TX_OUT | jq -r '.txhash')
    
    if [ -z "$TX_HASH" ] || [ "$TX_HASH" == "null" ]; then
        echo "❌ Submit Job Failed, retrying..." | tee -a $LOG
        sleep 10
        continue
    fi

    (
        sleep 20 
        JOB_ID=$(republicd q tx $TX_HASH -o json 2>/dev/null | jq -r '.events[] | select(.type == "job_submitted") | .attributes[] | select(.key == "job_id") | .value' 2>/dev/null)

        if [ ! -z "$JOB_ID" ] && [ "$JOB_ID" != "null" ]; then
            echo "⚙️ [Job $JOB_ID] Found! Ordering GPU..." | tee -a $LOG
            ssh -o StrictHostKeyChecking=no root@46.62.188.35 "screen -dmS job_$JOB_ID ~/gpu_worker.sh $JOB_ID"
            
            # GPU ko apna kaam khatam karke Master ko file bhejne ka time do
            sleep 60 
            
            RAW_FILE="/var/www/republic/result_${JOB_ID}.json"
            TARGET_DIR="/var/www/republic/results"
            mkdir -p "$TARGET_DIR"

            if [ -f "$RAW_FILE" ]; then
                mv "$RAW_FILE" "$TARGET_DIR/"
                FINAL_FILE="$TARGET_DIR/result_${JOB_ID}.json"

                # 1. GitHub Push (Pehle Backup)
                cd /var/www/republic
                git add "results/result_${JOB_ID}.json"
                git commit -m "Backup Job $JOB_ID"
                git push origin main
                
                # 2. Explorer Link Submission
                SHA256=$(sha256sum "$FINAL_FILE" | awk '{print $1}')
                GITHUB_LINK="https://raw.githubusercontent.com/$GH_USER/$GH_REPO/main/results/result_${JOB_ID}.json"

                republicd tx computevalidation submit-job-result "$JOB_ID" "$GITHUB_LINK" "example-verification:latest" "$SHA256" --from "$WALLET" --chain-id raitestnet_77701-1 --fees 5000000000000000arai --generate-only > /tmp/unsig_${JOB_ID}.json 2>/dev/null
                python3 -c "import json; tx=json.load(open('/tmp/unsig_${JOB_ID}.json')); tx['body']['messages'][0]['validator']='$VALOPER'; json.dump(tx, open('/tmp/fixed_${JOB_ID}.json','w'))"
                republicd tx sign /tmp/fixed_${JOB_ID}.json --from "$WALLET" --chain-id raitestnet_77701-1 --output-document /tmp/sig_${JOB_ID}.json 2>/dev/null
                RESULT_TX=$(republicd tx broadcast /tmp/sig_${JOB_ID}.json --broadcast-mode sync -o json 2>/dev/null | jq -r '.txhash')

                echo "✅ [Job $JOB_ID] Link: $GITHUB_LINK" | tee -a $LOG
                
                # 3. Yahan hai aapka "10 Minute Delay" fix
                echo "⏳ Job $JOB_ID: Result uploaded. local file 10 min baad delete hogi..." | tee -a $LOG
                (sleep 600 && rm -f "$FINAL_FILE" && echo "♻️ [Job $JOB_ID] Local file cleaned up after 10 min delay.") &
            else
                echo "⚠️ [Job $JOB_ID] Result file NOT received from GPU yet." | tee -a $LOG
            fi
        fi
    ) &
    sleep 15
done
