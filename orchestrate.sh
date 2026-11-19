#!/bin/bash
# 起点诡秘之主段评批量抓取编排器 v2 —— 6 路并行
export GH_TOKEN=$(python3 -c "import json; print(json.load(open('/tmp/ri/token.json'))['access_token'])")
REPO=zb3173496/qd-cm
RUN=/tmp/ri/qd-run
mkdir -p $RUN/dl $RUN/log
BATCH=30

worker() {
  local name=$1 start=$2 end=$3
  local cur=$start
  while [ $cur -lt $end ]; do
    local cnt=$BATCH
    if [ $((cur + BATCH)) -gt $end ]; then cnt=$((end - cur)); fi
    echo "[$name] trigger start=$cur count=$cnt $(date +%H:%M:%S)"
    gh workflow run qd-comments.yml --repo $REPO -f start=$cur -f count=$cnt > /dev/null 2>&1
    sleep 20
    local rid=$(gh run list --repo $REPO --workflow=qd-comments.yml --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run watch $rid --repo $REPO --interval 45 > /dev/null 2>&1
    local concl=$(gh run view $rid --repo $REPO --json conclusion --jq '.conclusion' 2>/dev/null)
    rm -rf $RUN/dl/$name
    gh run download $rid --repo $REPO --dir $RUN/dl/$name > /dev/null 2>&1
    local f=$RUN/dl/$name/comments-$cur/comments.json
    if [ -f "$f" ]; then
      cp "$f" $RUN/log/comments-$cur.json
      local nxt=$(python3 -c "import json; print(json.load(open('$f'))['nextStart'])" 2>/dev/null || echo $cur)
      local done=$(python3 -c "import json; print(len(json.load(open('$f'))['chapters']))" 2>/dev/null || echo 0)
      echo "[$name] batch done=$done next=$nxt conclusion=$concl $(date +%H:%M:%S)"
      if [ "$nxt" = "$cur" ]; then
        echo "[$name] no progress, cool down 180s"
        sleep 180
      fi
      cur=$nxt
    else
      echo "[$name] no artifact, cool down 120s $(date +%H:%M:%S)"
      sleep 120
    fi
    sleep 5
  done
  echo "[$name] FINISHED range $start-$end"
}

worker A 0 237 &
worker B 237 474 &
worker C 474 711 &
worker D 711 948 &
worker E 948 1184 &
worker F 1184 1419 &
wait
echo "ALL WORKERS DONE"
python3 - << 'EOF'
import json, glob
master = {}
reqs = 0
for f in sorted(glob.glob('/tmp/ri/qd-run/log/comments-*.json')):
    d = json.load(open(f))
    master.update(d.get('chapters', {}))
    reqs += d.get('reqs', 0)
json.dump(master, open('/tmp/ri/qd-run/master.json', 'w'), ensure_ascii=False)
tot = sum(s['n'] for e in master.values() for s in e['segs'].values())
print('MASTER chapters:', len(master), 'reqs:', reqs, 'comments:', tot)
EOF
