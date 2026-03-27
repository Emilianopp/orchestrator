Launch a PrimeRL training run across all eligible clusters simultaneously, elect a leader, cancel the rest.

You are an autonomous multi-cluster job launcher. The user provides a PrimeRL `.toml` config file. You manage everything else: SLURM scripts, submission, leader election. Follow these steps precisely.

**The sbatch scripts do NOT self-resubmit.** The monitor agent (`/orch-monitor`) is the sole resubmitter.

---

## Step 1: Parse the config

Read the `.toml` file the user provides. Extract:
- `output_dir` — use its basename as the **run name** (e.g. `output_dir = "outputs/compaction-suffix-queries"` → run name `compaction-suffix-queries`)
- `max_steps` (under `[train]` or top-level) — the target step count
- `[model].name` — the base model
- `[ckpt]` section — verify `resume_step = -1` is set (auto-resume from latest)
- `[deployment].num_train_gpus` — GPU count (default 4)

**Reject** the config if it contains a `[slurm]` section — we manage SLURM, not the config.

---

## Step 2: Check SSH connections

Run in parallel:
```bash
ssh -O check mila 2>/dev/null && echo "mila: live" || echo "mila: down"
ssh -O check rorqual 2>/dev/null && echo "rorqual: live" || echo "rorqual: down"
ssh -O check fir 2>/dev/null && echo "fir: live" || echo "fir: down"
ssh -O check nibi 2>/dev/null && echo "nibi: live" || echo "nibi: down"
```

Only live clusters proceed to the next steps.

---

## Step 3: Check GPU availability

Run `scripts/gpu-status.sh` (from the orchestrator repo) or equivalent on live clusters. Filter to clusters with **>= 4 GPUs** of acceptable type available.

GPU preference order: **H200 > H100 > A100 80GB (`a100l`)**

Record which GPU model each cluster will use.

---

## Step 4: Verify project is installed

For each eligible cluster, check:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "test -d ~/attention-matching-rl/.venv && echo ok || echo missing"
```

Drop any cluster where the project is not installed. Warn the user and suggest `/orch-install-project`.

---

## Step 5: Sync project repo

For each eligible cluster, in parallel:
```bash
ssh -o BatchMode=yes CLUSTER "cd ~/attention-matching-rl && git pull origin main"
```

If git pull fails (conflicts, etc.), warn but don't block — the code on disk may still be fine.

---

## Step 6: Upload config to each cluster

Write the `.toml` contents to `~/attention-matching-rl/configs/_orch/{run_name}.toml` on each cluster:
```bash
ssh -o BatchMode=yes CLUSTER "mkdir -p ~/attention-matching-rl/configs/_orch && cat > ~/attention-matching-rl/configs/_orch/{run_name}.toml << 'CONFIG_EOF'
... toml contents verbatim ...
CONFIG_EOF"
```

The config goes **as-is** — `output_dir` is overridden at runtime via a secondary TOML (Step 7).

---

## Step 7: Generate & upload cluster-specific sbatch

Write to `~/attention-matching-rl/scripts/_orch/{run_name}.sbatch` on each cluster.

### Template

```bash
#!/bin/bash
#SBATCH --job-name={run_name}
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task={cpus}
#SBATCH --mem=64G
#SBATCH {gpu_flag}
#SBATCH {partition_flag}
#SBATCH {account_flag}
#SBATCH --time=03:00:00
#SBATCH --output={scratch}/outputs/{run_name}/slurm-%j.out
#SBATCH --error={scratch}/outputs/{run_name}/slurm-%j.out

set -euo pipefail
export PROJECT_DIR=$HOME/attention-matching-rl
cd $PROJECT_DIR
[ -f .env ] && source .env
source .venv/bin/activate

mkdir -p {scratch}/outputs/{run_name}

# Runtime override: set output_dir to this cluster's $SCRATCH
cat > /tmp/_orch_override_{run_name}.toml << OVERRIDE
output_dir = "{scratch}/outputs/{run_name}"
OVERRIDE

uv run rl @ configs/_orch/{run_name}.toml @ /tmp/_orch_override_{run_name}.toml
```

**No self-resubmit.** The job runs once and exits. The monitor handles restarts.

### Cluster-specific values

| Cluster | GPU flag | CPUs | Partition flag | Account flag | `{scratch}` |
|---------|----------|------|----------------|--------------|-------------|
| mila (H100) | `--gres=gpu:h100:4` | 16 | `--partition=short-unkillable` | _(none)_ | `$SCRATCH` |
| mila (A100 80G) | `--gres=gpu:a100l:4` | 16 | `--partition=long` | _(none)_ | `$SCRATCH` |
| rorqual | `--gpus-per-node=h100:4` | 16 | _(none)_ | `--account=rrg-bengioy-ad` | `$SCRATCH` |
| fir | `--gpus-per-node=h100:4` | 12 | _(none)_ | `--account=rrg-bengioy-ad` | `$SCRATCH` |
| nibi | `--gpus-per-node=h100:4` | 14 | _(none)_ | `--account=rrg-bengioy-ad` | `$SCRATCH` |

Upload:
```bash
ssh -o BatchMode=yes CLUSTER "mkdir -p ~/attention-matching-rl/scripts/_orch && cat > ~/attention-matching-rl/scripts/_orch/{run_name}.sbatch << 'SBATCH_EOF'
... script content ...
SBATCH_EOF"
```

---

## Step 8: Submit to all clusters

In parallel:
```bash
ssh -o BatchMode=yes CLUSTER "cd ~/attention-matching-rl && sbatch scripts/_orch/{run_name}.sbatch"
```

Capture each job ID from the output (`Submitted batch job XXXXXXXX`).

---

## Step 9: Initialize state file

Create `state/` directory locally if it doesn't exist. Write `state/{run_name}.json`:

```json
{
  "run_name": "{run_name}",
  "config_path": "{path to the .toml the user provided}",
  "hf_repo": "ppEmiliano/attention-matching-rl-checkpoints",
  "output_dir_name": "{run_name}",
  "gpu_count": 4,
  "target_steps": {max_steps from config},
  "created_at": "{ISO 8601 timestamp}",
  "updated_at": "{ISO 8601 timestamp}",
  "status": "pending_leader",
  "leader_cluster": null,
  "latest_step": 0,
  "clusters": {
    "CLUSTER1": {
      "job_id": "XXXXXXXX",
      "state": "PENDING",
      "gpu_model": "h100",
      "submit_time": "{ISO timestamp}",
      "start_time": null,
      "end_time": null
    },
    "CLUSTER2": { ... }
  },
  "history": [
    {"timestamp": "...", "action": "submitted", "details": "Submitted to CLUSTER1 (job XXXX), CLUSTER2 (job XXXX), ..."}
  ]
}
```

Also write `state/{run_name}.md`:
```markdown
# {run_name}

**Status**: PENDING leader election | **Step**: 0 / {target_steps}

## Timeline
| Time | Event |
|------|-------|
| {HH:MM} | Submitted to {cluster1}, {cluster2}, ... |
```

---

## Step 10: Leader election

Poll every 15 seconds for up to 5 minutes:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "squeue -j JOB_ID -h -o '%T'"
```

For each cluster's job, check if the state is `RUNNING`.

- **First job to reach RUNNING** wins — it becomes the leader.
- Immediately `scancel` all other jobs:
  ```bash
  ssh -o BatchMode=yes CLUSTER "scancel JOB_ID"
  ```
- Update `state/{run_name}.json`:
  - Set `leader_cluster` to the winner
  - Set `status` to `"running"`
  - Set winner's state to `"RUNNING"`, losers to `"CANCELLED"`
  - Add history entry

- Update `state/{run_name}.md` with the leader election result.

**If no job starts within 5 minutes:** stop polling, report current states, set status to `"pending"`. The user can re-check later or run `/orch-monitor`.

**If a job FAILS during election** (state goes to FAILED, etc.), remove it from contention but continue waiting for others.

---

## Step 11: Report

Display a summary:

```
Run: {run_name}
Leader: {cluster} (job {job_id})
GPU: {gpu_count}x {gpu_model}
Target: {target_steps} steps
Config: {config_path}

Cancelled: {cluster2} (job XXXX), {cluster3} (job XXXX)

Monitor:  /orch-monitor
Flush:    /orch-flush {run_name}
Logs:     ssh {cluster} "tail -f $SCRATCH/outputs/{run_name}/slurm-{job_id}.out"
```

---

## Important reminders

- **Never request MIG slices.** Always full GPUs.
- On Mila, `a100l` = A100 80GB. Plain `a100` = 40GB.
- `{scratch}` in sbatch templates must be the literal string `$SCRATCH` (resolved at runtime by SLURM).
- The `@ config1.toml @ config2.toml` syntax is PrimeRL's config merging — the second TOML overrides fields in the first.
- GPU count comes from the config's `num_train_gpus` field, defaulting to 4.
- All SSH commands use `-o BatchMode=yes` to avoid interactive prompts.
- State files go in the orchestrator repo's `state/` directory (gitignored).
