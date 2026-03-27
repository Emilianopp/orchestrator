Launch a job on a SLURM HPC cluster (Mila or Alliance Canada).

You are an HPC job launcher. Your goal is to generate an sbatch script, upload it to the right cluster, and submit it. Follow these steps precisely.

---

## Step 1: Gather job requirements

Read the current project to understand what needs to run. Look for:
- Training scripts, config files (`.toml`, `.yaml`), `pyproject.toml`
- Existing sbatch scripts in the project (under `scripts/`, etc.)
- Whether the project uses `uv`, `pip`, `conda`, or modules

Ask the user ONLY for information you can't infer:
- **What to run** (command/script + config) — if not obvious from context
- **GPU count** — default to 1 if unclear
- **Target cluster** — or auto-select based on availability

Do NOT ask about wall time, partitions, CPU counts, or memory — use the defaults below.

---

## Step 2: Check GPU availability

Run `/orch-gpu-status` (or `scripts/gpu-status.sh` from the orchestrator repo) to see what's free right now.

Pick the best cluster using this priority:
1. User's explicit choice (if given)
2. Cluster with most free GPUs of the requested type
3. Tiebreaker: rorqual > fir > nibi > trillium > mila

---

## Step 3: Generate the sbatch script

Use the appropriate template below based on the target cluster. **Always prefer short wall times (3h) for faster scheduling** — the scheduler backfills short jobs into gaps.

### Cluster-specific settings

| Setting | Mila | DRAC (rorqual, fir, nibi, trillium) |
|---------|------|--------------------------------------|
| GPU flag | `--gres=gpu:MODEL:N` | `--gpus-per-node=MODEL:N` |
| Account | not needed | `--account=def-emilianopp` (ask user if unknown) |
| CPUs/GPU | 4 (default) | rorqual: 16, fir: 12, nibi: 14 |
| Partitions | see below | no partition flag needed (auto) |
| Internet | yes (all nodes) | fir, nibi: yes; rorqual, trillium: no |
| Env setup | `source .venv/bin/activate` | `source .venv/bin/activate` |
| Pip | normal | `--no-index` (pre-built wheels, no internet) |

### Mila partitions

| Partition | Max GPUs | Max Time | Preemptible | Use when |
|-----------|----------|----------|-------------|----------|
| `short-unkillable` | 4 | 3h | No | H100s, or guaranteed short runs |
| `unkillable` | 1 | 2d | No | Single-GPU guaranteed runs |
| `main` | 2 | 5d | Yes | Standard multi-GPU |
| `long` | unlimited | 7d | Yes | Large runs (no H100 access) |

**Default partition logic for Mila:**
- H100 requested → `short-unkillable` (only partition with H100)
- 1 GPU, ≤2 days → `unkillable`
- ≤2 GPUs → `main`
- >2 GPUs → `long`

### GPU model names in SLURM

| GPU | Mila GRES | DRAC GRES |
|-----|-----------|-----------|
| H100 80GB | `h100` | `h100` |
| A100 80GB | `a100l` | n/a (narval has `a100`, 40GB) |
| A100 40GB | `a100` | `a100` |
| L40S | `l40s` | `l40s` |
| RTX 8000 | `rtx8000` | n/a |

---

## Step 4: Script templates

### Single-node job (Mila)

```bash
#!/bin/bash
#SBATCH --job-name=JOB_NAME
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=CPUS
#SBATCH --mem=MEM
#SBATCH --gres=gpu:GPU_MODEL:GPU_COUNT
#SBATCH --partition=PARTITION
#SBATCH --time=WALLTIME
#SBATCH --output=SCRATCH_PATH/slurm-%j.out
#SBATCH --error=SCRATCH_PATH/slurm-%j.out

set -euo pipefail

export PROJECT_DIR=PROJECT_PATH
cd $PROJECT_DIR
[ -f .env ] && source .env
source .venv/bin/activate

# Checkpoint resume: add --resume flag if checkpoint exists
CKPT_DIR=SCRATCH_PATH/checkpoints
RESUME_FLAG=""
if [ -d "$CKPT_DIR" ] && ls "$CKPT_DIR"/*.pt 2>/dev/null | head -1 > /dev/null; then
    LATEST=$(ls -t "$CKPT_DIR"/*.pt | head -1)
    RESUME_FLAG="--resume $LATEST"
    echo "Resuming from checkpoint: $LATEST"
fi

COMMAND $RESUME_FLAG

# Self-resubmit if not done
if [ ! -f "$CKPT_DIR/DONE" ]; then
    echo "Job incomplete, resubmitting..."
    sbatch ${BASH_SOURCE[0]}
fi
```

### Single-node job (DRAC)

```bash
#!/bin/bash
#SBATCH --job-name=JOB_NAME
#SBATCH --account=ACCOUNT
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=CPUS
#SBATCH --mem=MEM
#SBATCH --gpus-per-node=GPU_MODEL:GPU_COUNT
#SBATCH --time=WALLTIME
#SBATCH --output=SCRATCH_PATH/slurm-%j.out
#SBATCH --error=SCRATCH_PATH/slurm-%j.out

set -euo pipefail

export PROJECT_DIR=PROJECT_PATH
cd $PROJECT_DIR
[ -f .env ] && source .env
source .venv/bin/activate

# Checkpoint resume
CKPT_DIR=SCRATCH_PATH/checkpoints
RESUME_FLAG=""
if [ -d "$CKPT_DIR" ] && ls "$CKPT_DIR"/*.pt 2>/dev/null | head -1 > /dev/null; then
    LATEST=$(ls -t "$CKPT_DIR"/*.pt | head -1)
    RESUME_FLAG="--resume $LATEST"
    echo "Resuming from checkpoint: $LATEST"
fi

COMMAND $RESUME_FLAG

# Self-resubmit if not done
if [ ! -f "$CKPT_DIR/DONE" ]; then
    echo "Job incomplete, resubmitting..."
    sbatch ${BASH_SOURCE[0]}
fi
```

---

## Step 5: Upload and submit

1. **Determine remote project path.** Convention:
   - Mila: `$HOME/PROJECT_NAME` or `$SCRATCH/PROJECT_NAME`
   - DRAC: `$HOME/PROJECT_NAME` or `$SCRATCH/PROJECT_NAME`
   - Check if the project already exists on the cluster: `ssh CLUSTER "ls -d ~/PROJECT_NAME 2>/dev/null || ls -d \$SCRATCH/PROJECT_NAME 2>/dev/null"`

2. **Ensure the repo is up to date on the remote:**
   ```bash
   ssh CLUSTER "cd PROJECT_PATH && git pull origin BRANCH"
   ```
   If the repo doesn't exist, clone it:
   ```bash
   ssh CLUSTER "git clone REPO_URL PROJECT_PATH && cd PROJECT_PATH && git checkout BRANCH"
   ```

3. **Create output directory:**
   ```bash
   ssh CLUSTER "mkdir -p SCRATCH_PATH"
   ```

4. **Write the sbatch script to the remote:**
   ```bash
   ssh CLUSTER "cat > PROJECT_PATH/scripts/run.sbatch << 'SBATCH_EOF'
   ... script content ...
   SBATCH_EOF"
   ```

5. **Submit:**
   ```bash
   ssh CLUSTER "cd PROJECT_PATH && sbatch scripts/run.sbatch"
   ```

6. **Report the job ID** and how to monitor:
   ```
   Job submitted: JOB_ID on CLUSTER
   Monitor: ssh CLUSTER "squeue -j JOB_ID"
   Logs:    ssh CLUSTER "tail -f SCRATCH_PATH/slurm-JOB_ID.out"
   Cancel:  ssh CLUSTER "scancel JOB_ID"
   ```

---

## Step 6: Wall time strategy

**Default: 3 hours.** This gets scheduled fastest via backfill.

DRAC time-based partitions (nested — shorter = more eligible partitions):
- ≤3h → runs in ALL partitions (fastest scheduling)
- ≤12h → most partitions
- ≤24h → fewer partitions
- ≤3d → standard
- ≤7d → minimum partitions (slowest scheduling)

Only increase wall time if the user explicitly asks. When using short jobs + self-resubmission, the training runs indefinitely via checkpoint chaining.

**Trillium exception:** Max 24h wall time, whole-node allocation only.
**TamIA exception:** Max 24h, whole-node only (all 4 H100 or all 8 H200).

---

## Important reminders

- **Never request MIG slices.** Always use full GPU names (`h100`, `a100l`, etc.)
- On Mila, `a100l` = A100 80GB. Plain `a100` = 40GB.
- On DRAC clusters without internet (rorqual, trillium): all dependencies must be pre-installed or use `--no-index` wheels.
- Always use `ssh -o BatchMode=yes -o ConnectTimeout=5` for non-interactive commands.
- If the project uses `uv`: `uv sync` on login node first, then `source .venv/bin/activate` in the job.
- Multi-GPU DDP on Mila needs:
  ```bash
  export MASTER_PORT=$(expr 10000 + $(echo -n $SLURM_JOBID | tail -c 4))
  export MASTER_ADDR="127.0.0.1"
  ```
