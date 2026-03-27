#!/usr/bin/env bash
# Warm up SSH master connections to all clusters.
# Run once per day to satisfy 2FA, then the orchestrator reuses them.
# Auto-selects option 1 for the 2FA prompt.

CLUSTERS=(narval rorqual fir nibi tamia)

for host in "${CLUSTERS[@]}"; do
  if ssh -O check "$host" 2>/dev/null; then
    echo "$host: already connected"
    continue
  fi

  echo "--- $host ---"
  expect -c "
    set timeout 60
    spawn ssh -N $host
    expect {
      \"yes/no\"  { send \"yes\r\"; exp_continue }
      \"Option\"  { send \"1\r\"; exp_continue }
      \"option\"  { send \"1\r\"; exp_continue }
      timeout     { puts \"timed out\"; exit 1 }
    }
  " &

  # Wait until the master socket appears or timeout after 60s
  for i in $(seq 1 60); do
    if ssh -O check "$host" 2>/dev/null; then
      echo "$host: OK"
      break
    fi
    sleep 1
  done

  if ! ssh -O check "$host" 2>/dev/null; then
    echo "$host: FAILED (timed out after 60s)"
  fi
done

echo ""
echo "=== Summary ==="
for host in "${CLUSTERS[@]}"; do
  if ssh -O check "$host" 2>/dev/null; then
    echo "$host: OK"
  else
    echo "$host: FAILED"
  fi
done
