#!/usr/bin/env bash
# Show available full GPUs across all connected clusters.
# Skips MIG slices -- only reports full GPUs.
# Usage: ./scripts/gpu-status.sh

CLUSTERS=(mila rorqual fir nibi tamia narval)
DRAC_CLUSTERS=(rorqual fir nibi tamia narval)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Check connectivity ---
LIVE=()
for host in "${CLUSTERS[@]}"; do
  if ssh -O check "$host" 2>/dev/null; then
    LIVE+=("$host")
  fi
done

if [ ${#LIVE[@]} -eq 0 ]; then
  echo "No clusters connected. Run ./warmup.sh first."
  exit 1
fi

echo "Connected: ${LIVE[*]}"
echo ""

# --- Query clusters in parallel ---

# Mila uses savail
for host in "${LIVE[@]}"; do
  if [ "$host" = "mila" ]; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 mila "savail" > "$TMPDIR/mila.txt" 2>/dev/null &
  fi
done

# DRAC clusters use sinfo with GresUsed
for host in "${LIVE[@]}"; do
  for drac in "${DRAC_CLUSTERS[@]}"; do
    if [ "$host" = "$drac" ]; then
      ssh -o BatchMode=yes -o ConnectTimeout=5 "$host" \
        "sinfo -N -O 'NodeHost:20,Gres:50,GresUsed:50,StateLong:15' --noheader" \
        > "$TMPDIR/${host}_raw.txt" 2>/dev/null &
    fi
  done
done

wait

# --- Display Mila ---
if [ -f "$TMPDIR/mila.txt" ] && [ -s "$TMPDIR/mila.txt" ]; then
  echo "=== mila ==="
  # Filter to only full GPU types we care about
  head -2 "$TMPDIR/mila.txt"
  grep -E '^\s*(a100l|a100|h100|l40s|rtx8000|v100|a6000|h200|mi300)' "$TMPDIR/mila.txt" || true
  echo ""
fi

# --- Parse DRAC clusters ---
for host in "${DRAC_CLUSTERS[@]}"; do
  RAW="$TMPDIR/${host}_raw.txt"
  if [ ! -f "$RAW" ] || [ ! -s "$RAW" ]; then
    continue
  fi

  echo "=== $host ==="
  grep gpu "$RAW" | python3 -c "
import sys, re
from collections import defaultdict

# Full GPU types only -- no MIG slices
MIG_PATTERN = re.compile(r'nvidia_.*_\dg\.\d+gb')

total = defaultdict(int)
used = defaultdict(int)
seen = set()

for line in sys.stdin:
    parts = line.split()
    if len(parts) < 4: continue
    node, gres, gres_used, state = parts[0], parts[1], parts[2], parts[3]
    if node in seen: continue
    seen.add(node)

    state_clean = state.rstrip('-@*\$~#')
    if state_clean in ('down', 'drained', 'draining', 'inval'): continue

    # Parse total gres
    for g in gres.split(','):
        m = re.match(r'gpu:([^:]+):(\d+)', g)
        if not m: continue
        gpu_type, cnt = m.group(1), int(m.group(2))
        if MIG_PATTERN.match(gpu_type): continue
        total[gpu_type] += cnt

    # Parse used gres
    for g in gres_used.split(','):
        m = re.match(r'gpu:([^:]+):(\d+)', g)
        if not m: continue
        gpu_type, cnt = m.group(1), int(m.group(2))
        if MIG_PATTERN.match(gpu_type): continue
        used[gpu_type] += cnt

if total:
    print(f'  {\"GPU\":<20s} {\"Avail\":>6s} / Total')
    print(f'  {\"=\"*20} {\"=\"*13}')
    for gt in sorted(total):
        a = total[gt] - used.get(gt, 0)
        print(f'  {gt:<20s} {a:>5d} / {total[gt]}')
else:
    print('  No GPU data')
" 2>/dev/null
  echo ""
done

# --- Cross-cluster summary ---
echo "=== SUMMARY (full GPUs only) ==="
echo ""

# Collect all results into one summary
(
  # Mila: parse savail output
  if [ -f "$TMPDIR/mila.txt" ] && [ -s "$TMPDIR/mila.txt" ]; then
    grep -E '^\s*(a100l|a100|h100|l40s|rtx8000|v100|a6000|h200|mi300)' "$TMPDIR/mila.txt" 2>/dev/null | while read -r line; do
      gpu=$(echo "$line" | awk '{print $1}')
      avail=$(echo "$line" | awk -F'/' '{gsub(/ /,"",$1); split($1,a," "); print a[NF]}')
      total=$(echo "$line" | awk -F'/' '{gsub(/ /,"",$2); print $2}')
      echo "mila $gpu $avail $total"
    done
  fi

  # DRAC: parse sinfo output
  for host in "${DRAC_CLUSTERS[@]}"; do
    RAW="$TMPDIR/${host}_raw.txt"
    if [ ! -f "$RAW" ] || [ ! -s "$RAW" ]; then continue; fi
    grep gpu "$RAW" | python3 -c "
import sys, re
from collections import defaultdict
MIG_PATTERN = re.compile(r'nvidia_.*_\dg\.\d+gb')
total = defaultdict(int)
used = defaultdict(int)
seen = set()
for line in sys.stdin:
    parts = line.split()
    if len(parts) < 4: continue
    node, gres, gres_used, state = parts[0], parts[1], parts[2], parts[3]
    if node in seen: continue
    seen.add(node)
    state_clean = state.rstrip('-@*\$~#')
    if state_clean in ('down','drained','draining','inval'): continue
    for g in gres.split(','):
        m = re.match(r'gpu:([^:]+):(\d+)', g)
        if not m: continue
        gpu_type, cnt = m.group(1), int(m.group(2))
        if MIG_PATTERN.match(gpu_type): continue
        total[gpu_type] += cnt
    for g in gres_used.split(','):
        m = re.match(r'gpu:([^:]+):(\d+)', g)
        if not m: continue
        gpu_type, cnt = m.group(1), int(m.group(2))
        if MIG_PATTERN.match(gpu_type): continue
        used[gpu_type] += cnt
for gt in sorted(total):
    a = total[gt] - used.get(gt, 0)
    print(f'$host {gt} {a} {total[gt]}')
" 2>/dev/null
  done
) | python3 -c "
import sys
from collections import defaultdict

cluster_data = []
gpu_avail = defaultdict(int)
gpu_total = defaultdict(int)

for line in sys.stdin:
    parts = line.split()
    if len(parts) < 4: continue
    cluster, gpu, avail, total = parts[0], parts[1], int(parts[2]), int(parts[3])
    if avail > 0:
        cluster_data.append((cluster, gpu, avail, total))
    gpu_avail[gpu] += avail
    gpu_total[gpu] += total

print(f'{\"Cluster\":<12s} {\"GPU\":<12s} {\"Avail\":>6s} / Total')
print(f'{\"=\"*12} {\"=\"*12} {\"=\"*13}')
for cluster, gpu, avail, total in sorted(cluster_data, key=lambda x: -x[2]):
    print(f'{cluster:<12s} {gpu:<12s} {avail:>5d} / {total}')

print()
print(f'{\"TOTAL\":<12s} {\"GPU\":<12s} {\"Avail\":>6s} / Total')
print(f'{\"=\"*12} {\"=\"*12} {\"=\"*13}')
for gpu in sorted(gpu_total, key=lambda g: -gpu_avail[g]):
    print(f'{\"\":<12s} {gpu:<12s} {gpu_avail[gpu]:>5d} / {gpu_total[gpu]}')
"
