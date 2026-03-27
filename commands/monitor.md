Monitor active training runs and autonomously restart failed jobs across clusters.

You are an autonomous job monitoring agent. You check SLURM job states, track training progress, and — in autonomous mode — keep jobs alive by pushing checkpoints to HuggingFace Hub and resubmitting on the best available cluster. Follow these steps precisely.

**You are the sole resubmitter.** Sbatch scripts do NOT self-resubmit.

---

## Determine mode

- **Status** (default): one-shot status check across all runs. Use this when the user just wants to see what's happening.
- **Autonomous**: continuous monitoring loop that keeps jobs alive until training completes. Use this when the user says "keep it running", "autonomous", "loop", or similar.

If the user specifies a run name, operate on just that run. Otherwise, operate on all active runs.

---

## Mode: Status

### Step 1: Load state

Read all `state/*.json` files from the orchestrator repo directory. Each file represents one run. Filter to runs where `status` is not `"completed"` or `"flushed"`.

If no state files exist, tell the user there are no tracked runs and suggest `/orch-launch`.

### Step 2: Refresh job states

For each active run, check the leader cluster's job:

If the job might still be in the queue:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "squeue -j JOB_ID -h -o '%T %M'"
```

If squeue returns nothing (job ended), check accounting:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "sacct -j JOB_ID --format=State,ExitCode,Elapsed --noheader -P | head -1"
```

Run these checks in parallel across all runs/clusters.

### Step 3: Check step progress

For RUNNING jobs, check the latest training step:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER '
  WEIGHTS_DIR="${SCRATCH}/outputs/{run_name}/weights"
  LATEST=0
  for d in "$WEIGHTS_DIR"/step_*/; do
    [ -d "$d" ] || continue
    S=$(basename "$d" | sed "s/step_//")
    [ "$S" -gt "$LATEST" ] && LATEST=$S
  done
  echo "STEP:$LATEST"
'
```

### Step 4: Display summary table

```
Run                           Cluster   Job        State     Step/Target   Elapsed
============================  ========  =========  ========  ===========   =======
compaction-suffix-queries     fir       12345678   RUNNING   120/600       1:42:00
another-run                   nibi      87654321   PENDING   0/1000        0:00:00
```

### Step 5: Update state files

Update each `state/{run_name}.json` with refreshed values:
- `status`: map SLURM states → `"running"`, `"pending"`, `"completed"`, `"failed"`
- `latest_step`
- `updated_at`
- Leader cluster's `state`, `end_time` (if ended)

Update `state/{run_name}.md` with current status line and any new timeline events.

If `latest_step >= target_steps`, set `status` to `"completed"` and congratulate the user.

---

## Mode: Autonomous

Run the Status flow (Steps 1-5 above) first, then enter a loop.

### Step 6: Detect jobs needing restart

After refreshing states, for each run check:
- Job ended (COMPLETED, FAILED, TIMEOUT, OUT_OF_MEMORY, CANCELLED, etc.)
- AND `latest_step < target_steps`

If so, this run needs a restart.

If `latest_step >= target_steps`, mark as `"completed"` and skip.

### Step 7: Push checkpoint from source cluster

On the cluster where the job just ended, find and push the latest STABLE checkpoint:

```bash
ssh -o ServerAliveInterval=30 -o BatchMode=yes CLUSTER '
  source ~/attention-matching-rl/.venv/bin/activate
  OUTPUT_DIR="${SCRATCH}/outputs/{run_name}"
  WEIGHTS_DIR="${OUTPUT_DIR}/weights"

  # Find latest STABLE checkpoint
  LATEST=""
  LATEST_STEP=0
  for d in "$WEIGHTS_DIR"/step_*/; do
    [ -f "${d}STABLE" ] || continue
    STEP=$(basename "$d" | sed "s/step_//")
    if [ "$STEP" -gt "$LATEST_STEP" ]; then
      LATEST_STEP=$STEP
      LATEST="$d"
    fi
  done

  if [ -z "$LATEST" ]; then
    echo "NO_STABLE_CHECKPOINT"
    exit 0
  fi

  # Write checkpoint metadata
  cat > "${LATEST}/checkpoint_info.json" << EOF
{
  "step": $LATEST_STEP,
  "source_cluster": "CLUSTER_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "run_name": "{run_name}"
}
EOF

  # Upload to HF Hub (per-run subdirectory)
  hf upload ppEmiliano/attention-matching-rl-checkpoints "$LATEST" {run_name}/ \
    --repo-type model \
    --delete "{run_name}/*" \
    --commit-message "step $LATEST_STEP from CLUSTER_NAME for {run_name}"

  echo "PUSHED:$LATEST_STEP"
'
```

Replace `CLUSTER_NAME` with the actual cluster name.

**If no STABLE checkpoint exists**, the run made no progress — resubmit anyway (it will start from scratch or from a pre-existing checkpoint).

### Step 8: Select next cluster

Check GPU availability across all live clusters (same as `/orch-launch` Step 3):
- Run `ssh -O check` for each cluster
- Run gpu-status checks on live clusters
- Filter to clusters with >= {gpu_count} GPUs available
- Pick best by preference: H200 > H100 > A100 80GB

**If the same cluster** that just finished has GPUs available, prefer it — no checkpoint transfer needed (weights are already on disk).

**If all clusters are full**, wait 5 minutes and retry. Log the wait. Retry up to 12 times (1 hour), then alert the user and pause.

### Step 9: Pull checkpoint on target (if different cluster)

If the target cluster differs from the source:

```bash
ssh -o ServerAliveInterval=30 -o BatchMode=yes TARGET_CLUSTER '
  source ~/attention-matching-rl/.venv/bin/activate
  OUTPUT_DIR="${SCRATCH}/outputs/{run_name}"
  WEIGHTS_DIR="${OUTPUT_DIR}/weights"
  mkdir -p "$WEIGHTS_DIR"

  # Download from HF Hub (per-run subdirectory)
  hf download ppEmiliano/attention-matching-rl-checkpoints \
    --include "{run_name}/*" \
    --local-dir /tmp/_orch_hf_{run_name}

  # Move files into the expected weights structure
  STEP=$(cat /tmp/_orch_hf_{run_name}/{run_name}/checkpoint_info.json | python3 -c "import sys,json; print(json.load(sys.stdin)[\"step\"])")
  DEST="$WEIGHTS_DIR/step_${STEP}"
  mkdir -p "$DEST"
  cp -r /tmp/_orch_hf_{run_name}/{run_name}/* "$DEST/"
  rm -rf /tmp/_orch_hf_{run_name}

  # Verify integrity
  ERRORS=0
  ls "$DEST"/*.safetensors 1>/dev/null 2>&1 || ERRORS=$((ERRORS + 1))
  [ -f "$DEST/config.json" ] || ERRORS=$((ERRORS + 1))
  [ -f "$DEST/STABLE" ] || touch "$DEST/STABLE"

  if [ $ERRORS -gt 0 ]; then
    echo "INTEGRITY_FAILED"
    exit 1
  fi

  # Clean older checkpoints
  for d in "$WEIGHTS_DIR"/step_*/; do
    [ -d "$d" ] || continue
    S=$(basename "$d" | sed "s/step_//")
    [ "$S" != "$STEP" ] && rm -rf "$d"
  done

  echo "PULLED:$STEP:$DEST"
'
```

### Step 10: Submit new job on target cluster

Generate and upload an sbatch script exactly as in `/orch-launch` Step 7, using the target cluster's settings. Then submit:

```bash
ssh -o BatchMode=yes TARGET_CLUSTER "cd ~/attention-matching-rl && sbatch scripts/_orch/{run_name}.sbatch"
```

Capture the new job ID.

### Step 11: Update state

Update `state/{run_name}.json`:
- `leader_cluster` → new cluster
- `status` → `"running"` (or `"pending"` if PENDING)
- Add new cluster entry to `clusters` with new job ID
- Update `latest_step`
- Add history entry: `"Resubmitted on {cluster} (job {id}) at step {step}. Previous: {old_cluster} {end_reason}."`
- `updated_at` → now

Update `state/{run_name}.md`:
```markdown
| {HH:MM} | {old_cluster} ended ({reason}) at step {step} |
| {HH:MM} | Checkpoint pushed to HF Hub (step {step}) |
| {HH:MM} | Resubmitted on {new_cluster} (job {id}) |
```

### Step 12: Continue monitoring

Wait 5 minutes (`sleep 300`), then loop back to Step 1 (Status flow).

**Continue until ALL tracked runs have `latest_step >= target_steps`** or the user interrupts.

Between iterations, display a short heartbeat:
```
[{HH:MM}] Heartbeat — {N} run(s) active. Next check in 5 min.
```

---

## State Markdown Format

`state/{run_name}.md` should look like:

```markdown
# {run_name}

**Status**: RUNNING on fir | **Step**: 120 / 600 | **Job**: 12345678

## Timeline
| Time | Event |
|------|-------|
| 14:01 | Submitted to fir, rorqual, nibi |
| 14:06 | fir started - cancelled rorqual, nibi |
| 15:30 | Step 120 reached |
| 17:01 | fir COMPLETED at step 300 |
| 17:02 | Checkpoint pushed to HF Hub (step 300) |
| 17:03 | Resubmitted on nibi (job 87654321) |
```

---

## Important reminders

- **You are the sole resubmitter.** Sbatch scripts do NOT self-resubmit.
- All SSH commands use `-o BatchMode=yes` to avoid hangs.
- Use `-o ServerAliveInterval=30` for long-running uploads/downloads.
- Use `-o ConnectTimeout=5` for quick status checks.
- HF uploads/downloads use per-run subdirectories: `{run_name}/` within the shared repo.
- If a cluster becomes unreachable mid-monitoring, skip it and note in state. Try again next iteration.
- If a checkpoint push fails, retry once. If still failing, try pushing from a different approach or alert user.
- State files are in the orchestrator repo's `state/` directory.
- Never request MIG slices. Always full GPUs.
- GPU preference: H200 > H100 > A100 80GB (`a100l`).
