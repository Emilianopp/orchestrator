# Orchestrator

Autonomous job orchestration system that SSH-es into SLURM-based HPC clusters, launches jobs from repo/config definitions, and monitors them to completion.

---

## Clusters

### Mila Cluster

| Property | Value |
|---|---|
| **Login** | `ssh -p 2222 <user>@login.server.mila.quebec` |
| **Login nodes** | `login-{1..4}.login.server.mila.quebec` |
| **Scheduler** | SLURM |
| **Internet from compute** | Yes (unrestricted) |
| **Max job duration** | 2d (unkillable), 5d (main), 7d (long/preemptible) |
| **Max concurrent jobs** | 1000 |
| **Auth** | SSH key + MFA (TOTP via privacyIDEA) |
| **Dashboard** | https://dashboard.server.mila.quebec |

**GPU inventory:**

| GPU | Nodes | GPUs/Node | VRAM | SLURM feature |
|---|---|---|---|---|
| H100 | cn-n[001-002] | 8 | 80 GB | `hopper,nvlink,80gb` |
| L40S | cn-l[001-091] | 4 | 48 GB | `lovelace,48gb` |
| A100 80GB | cn-g[001-029], cn-d[003-004], cn-i001 | 4-8 | 80 GB | `ampere,nvlink,80gb` |
| A100 40GB | cn-d[001-002], cn-k[001-004] | 4-8 | 40 GB | `ampere,nvlink,40gb` |
| RTX 8000 | cn-a[001-011], cn-c[001-040] | 8 | 48 GB | `turing,48gb` |
| V100 | cn-b[001-005], cn-e[002-003] | 8 | 32 GB | `volta,nvlink,32gb` |
| A6000 | cn-j001 | 8 | 48 GB | `ampere,48gb` |

**Partitions:**

| Partition | Max GPUs | Max Time | Preemptible | Notes |
|---|---|---|---|---|
| `unkillable` | 1 | 2 days | No | Guaranteed |
| `main` | 2 | 5 days | No | Standard |
| `long` | unlimited | 7 days | Yes | For large runs |
| `short-unkillable` | 4 | 3 hours | No | Only partition with H100 access |

**Storage:**

| Mount | Quota | Backed Up | Purged | Notes |
|---|---|---|---|---|
| `$HOME` | 100 GB | Yes | No | Code, configs |
| `$SCRATCH` | 5 TB | No | 90 days | Fast, temporary |
| `$ARCHIVE` | 5 TB | No | No | Long-term, login+CPU only |
| `/network/projects/` | 1 TB | Yes | No | Group shared |
| `/network/datasets/` | R/O | -- | -- | Curated datasets |
| `/network/weights/` | R/O | -- | -- | Pretrained weights |
| `$SLURM_TMPDIR` | Node disk | No | Job end | Fastest I/O |

---

### Alliance Canada (DRAC) -- General Purpose

All DRAC clusters use SLURM, module-based software (Lmod, StdEnv/2023), and share a common storage model: `$HOME` (small, backed up), `$SCRATCH` (large, purged), `$PROJECT` (group-shared, backed up). Auth is CCDB account + SSH keys.

#### Narval (currently unreachable as of 2026-03-27)

| Property | Value |
|---|---|
| **Login** | `narval.alliancecan.ca` |
| **Location** | ETS, Montreal, QC |
| **GPUs** | 159 nodes x 4x A100 SXM4 40GB (NVLink) |
| **CPUs** | 1,145 nodes x 64c AMD EPYC 7532 |
| **Internet from compute** | No |
| **Max job** | 7 days |
| **Max concurrent jobs** | 1,000 |
| **Network** | InfiniBand HDR |

#### Rorqual (replaced Beluga)

| Property | Value |
|---|---|
| **Login** | `rorqual.alliancecan.ca` |
| **Automation** | `robot.rorqual.alliancecan.ca` |
| **Location** | ETS, Montreal, QC |
| **GPUs** | 8 nodes x 4x H100 SXM5 80GB (NVLink) |
| **CPUs** | 670 nodes x 192c AMD EPYC 9654 |
| **Internet from compute** | No |
| **Max job** | 7 days |
| **Network** | InfiniBand HDR 200 Gb/s |

#### Fir (replaced Cedar)

| Property | Value |
|---|---|
| **Login** | `fir.alliancecan.ca` |
| **Automation** | `robot.fir.alliancecan.ca` |
| **Location** | SFU, Burnaby, BC |
| **GPUs** | 160 nodes x 4x H100 SXM5 80GB (NVLink) |
| **CPUs** | 864 nodes x 192c AMD EPYC 9655 |
| **Internet from compute** | Yes (full) |
| **Max job** | 7 days |
| **Network** | InfiniBand NDR |

#### Nibi (replaced Graham)

| Property | Value |
|---|---|
| **Login** | `nibi.alliancecan.ca` |
| **Automation** | `robot.nibi.alliancecan.ca` |
| **Location** | U Waterloo, ON |
| **GPUs** | 36 nodes x 8x H100 SXM 80GB + 6 nodes x 4x AMD MI300A |
| **CPUs** | 700 nodes x 192c Intel Xeon 6972P |
| **High-mem** | 10 nodes x 6 TB RAM |
| **Internet from compute** | Yes (full) |
| **Max job** | 7 days |
| **Network** | Nokia 200/400G Ethernet |

---

### Alliance Canada -- PAICE Clusters (AI-focused)

PAICE clusters have additional access requirements: AIP-type RAP membership (prefix `aip-`), CCDB access request, PAICE declaration form, and Canada geo-restriction.

#### TamIA

| Property | Value |
|---|---|
| **Login** | `tamia.alliancecan.ca` |
| **Automation** | `robot.tamia.ecpia.ca` |
| **Portal** | https://portail.tamia.ecpia.ca/ |
| **Location** | U Laval, QC (co-managed with Mila & Calcul Quebec) |
| **H200 nodes** | 12 nodes x 8x H200 141GB HBM3 (NVLink) |
| **H100 nodes** | 53 nodes x 4x H100 80GB HBM3 (NVLink) |
| **CPU nodes** | 8 nodes x 64c Intel Xeon |
| **Internet from compute** | No |
| **Max job** | 24 hours |
| **Allocation** | Whole-node GPU only (all 4 H100 or all 8 H200) |
| **Network** | InfiniBand NDR, fat-tree, 400 Gb/s |

#### Killarney

| Property | Value |
|---|---|
| **Login** | `killarney.alliancecan.ca` |
| **Location** | U Toronto (Vector Institute + SciNet) |
| **Standard tier** | 168 nodes x 4x L40S 48GB |
| **Performance tier** | 10 nodes x 8x H100 SXM 80GB (NVLink) |
| **Access** | Vector-affiliated PIs, CCAI Chairs, Canadian university AI researchers |
| **Network** | InfiniBand HDR100/HDR |

#### Vulcan

| Property | Value |
|---|---|
| **Login** | `vulcan.alliancecan.ca` |
| **Location** | U Alberta (Amii) |
| **GPUs** | 252 nodes x 4x L40S 48GB (1,008 total) |
| **Internet from compute** | Whitelisted proxy only |
| **Max job** | 7 days |
| **Network** | 100 Gbps Ethernet with RoCE |

---

## GPU Inventory (Aggregate)

### By GPU Type (all clusters)

| GPU | VRAM | Total GPUs | Clusters |
|---|---|---|---|
| **H200** | 141 GB HBM3 | 96 | TamIA (96) |
| **H100** | 80 GB | 1,268 | Fir (640), Nibi (288), TamIA (212), Killarney (80), Rorqual (32), Mila (16) |
| **A100** | 80 GB | 136 | Mila (136) |
| **A100** | 40 GB | 668 | Narval (636), Mila (32) |
| **L40S** | 48 GB | 2,044 | Vulcan (1,008), Killarney (672), Mila (364) |
| **RTX 8000** | 48 GB | 408 | Mila (408) |
| **A6000** | 48 GB | 8 | Mila (8) |
| **V100** | 32 GB | 56 | Mila (56) |
| **MI300A** | -- | 24 | Nibi (24) |
| | | **4,960** | |

### By Cluster (accessible)

| Cluster | GPUs | Status |
|---|---|---|
| **Mila** | 1,020 (L40S, RTX 8000, A100, H100, V100, A6000) | Live |
| **Fir** | 640 (H100) | Live |
| **Nibi** | 312 (H100, MI300A) | Live |
| **TamIA** | 308 (H200, H100) | Connecting |
| **Rorqual** | 32 (H100) | Live |
| **Narval** | 636 (A100 40GB) | Down |
| **Killarney** | 752 (L40S, H100) | Restricted (Vector) |
| **Vulcan** | 1,008 (L40S) | Restricted (Amii) |

---

## GPU Policy

**Only request full GPUs. Never request MIG slices.**

| Cluster | GPU to request | SLURM GRES syntax |
|---|---|---|
| Mila | A100 80GB | `--gres=gpu:a100l:N` |
| Mila | H100 80GB | `--gres=gpu:h100:N` (short-unkillable only, 3h max) |
| Rorqual | H100 80GB | `--gres=gpu:h100:N` |
| Fir | H100 80GB | `--gres=gpu:h100:N` |
| Nibi | H100 80GB | `--gres=gpu:h100:N` |
| TamIA | H100/H200 | Whole-node only (all 4 H100 or all 8 H200) |

Notes:
- On Mila, `a100l` = A100 80GB (NVLink). Plain `a100` = A100 40GB -- avoid unless 80GB is unavailable.
- DRAC clusters expose MIG slices (`nvidia_h100_80gb_hbm3_3g.40gb`, `1g.10gb`, etc.) -- do NOT use these. Always request `gpu:h100` for full GPUs.
- Default GPU preference order: H100 > A100 80GB (a100l) > A100 40GB

## Cluster Selection Strategy

When choosing where to submit a job, consider:

1. **GPU availability** -- check live availability first (`savail` on Mila, `sinfo` on DRAC)
2. **Duration** -- TamIA caps at 24h; Mila unkillable at 2d; most DRAC at 7d
3. **Internet access** -- needed for downloads/API calls: Mila, Fir, Nibi
4. **Queue pressure** -- spread load across clusters
5. **Data locality** -- prefer clusters where data already lives
6. **Allocation** -- TamIA requires whole-node; others allow fractional

**Priority order (for GPU work):** Rorqual > Fir > Nibi > Mila (a100l) > TamIA (if AIP RAP)

---

## Orchestrator Workflow

### 1. Configuration

A job config specifies:
```yaml
# Example: jobs/train_llm.yaml
name: train-llm-v2
clusters:
  preferred: [mila, narval]
  fallback: [rorqual, fir]
resources:
  gpus: 4
  gpu_type: a100  # or h100, l40s, any
  gpu_mem_min: 40  # GB
  cpus_per_task: 8
  mem: 64G
  time: "2-00:00:00"  # 2 days
partition: main  # per-cluster override possible
env:
  modules: [python/3.10]
  venv: $HOME/envs/llm
  setup: |
    pip install -r requirements.txt
script: train.sh
repo:
  url: git@github.com:org/model.git
  branch: main
  commit: HEAD
data:
  source: /network/datasets/my_dataset
  copy_to_tmpdir: true
monitoring:
  check_interval: 300  # seconds
  alert_on: [FAILED, TIMEOUT, OOM]
  auto_resubmit: true
  max_resubmits: 3
```

### 2. SSH Connection Management

Connections rely on SSH multiplexing (`ControlMaster auto` + `ControlPersist yes` in `~/.ssh/config`). The user runs `warmup.sh` once per day to establish master sockets with 2FA.

**The orchestrator does NOT manage SSH auth.** It checks which connections are live and works with what's available.

**Pre-flight connection check:**
```bash
# Run before any job submission
for host in mila rorqual fir nibi tamia; do
  ssh -O check "$host" 2>/dev/null && echo "$host: live" || echo "$host: down"
done
```

Only clusters with a live master socket are considered for job placement. If no cluster meets the job's requirements, prompt the user to warm up the needed connection.

### 3. Job Submission Pipeline

```
[Config] → [Check Live Connections] → [Filter Eligible Clusters] → [Select Best] → [Setup Env] → [Submit] → [Monitor]
```

**Steps:**
1. Parse job config
2. Check which clusters have live SSH master sockets
3. Filter to clusters that meet resource requirements (GPU type, VRAM, time limit)
4. Select best cluster (least queue pressure, data locality, priority order)
5. SSH into login node via multiplexed connection
6. Clone/update repo on remote `$SCRATCH` or `$HOME`
7. Set up environment (modules, venv, conda)
8. Copy data to appropriate location
9. Generate SLURM sbatch script from config
10. Submit via `sbatch` and capture job ID
11. Enter monitoring loop

### 4. Job Monitoring

Poll jobs via SSH at configured intervals:
- `squeue -j <job_id> -h -o "%T"` -- job state
- `sacct -j <job_id> --format=State,ExitCode,Elapsed,MaxRSS` -- post-completion stats
- Tail `slurm-<job_id>.out` for live output

**State machine:**
```
PENDING → RUNNING → COMPLETED
                  → FAILED → [auto-resubmit if configured]
                  → TIMEOUT → [auto-resubmit with extended time]
                  → OOM → [auto-resubmit with more memory]
          CANCELLED (user or system preemption)
```

### 5. Multi-Cluster Orchestration

- If preferred cluster is full/down, try fallback clusters
- Track jobs across all clusters in a local state file
- Aggregate logs and results back to local machine
- Support dependency chains: job B starts after job A completes

### 6. Remote Environment Setup

Per-cluster setup considerations:
- **Mila:** `module load python/3.10`, unrestricted internet, `milatools` for SSH config
- **DRAC (Narval, Rorqual, Fir, etc.):** `module load StdEnv/2023`, `module load python/3.10`
- **TamIA:** whole-node allocation only, 24h max, no internet on compute
- **Clusters without internet:** pre-download wheels/data, use `$SCRATCH` staging

---

## Common SLURM Reference

```bash
# Submit
sbatch job.sh

# Interactive
salloc --gres=gpu:1 --mem=16G --time=1:00:00
srun --pty bash

# Monitor
squeue --me                          # my jobs
squeue -j <id> -o "%T %M %R"        # specific job state, time, reason
sacct -j <id> --format=JobID,State,ExitCode,Elapsed,MaxRSS,MaxVMSize
scontrol show job <id>               # full details
sinfo -p <partition>                 # partition availability

# Cancel
scancel <id>
scancel --user=$USER                 # all my jobs

# GPU request patterns
--gres=gpu:1                         # any GPU
--gres=gpu:a100:4                    # 4x A100
--constraint="ampere&nvlink"         # feature-based selection
--gpus-per-task=l40s:1               # alternative syntax (Mila)
```

---

## SSH Access

**Usernames:**
- DRAC / Compute Canada: `emiliano`
- Mila: `emiliano.penaloza`

SSH config is at `~/.ssh/config` with multiplexing already enabled (`ControlMaster auto`, `ControlPersist yes`). Socket files in `~/.cache/ssh/`.

**Active cluster aliases:** `narval`, `rorqual`, `fir`, `nibi` (+ legacy: `beluga`, `cedar`, `graham`, `niagara`)
**Mila:** `mila` (port 2222), `mila-cpu` (via slurm-proxy)

**Connection warmup (do once per day for 2FA):**
```bash
ssh narval echo "OK"
ssh rorqual echo "OK"
ssh fir echo "OK"
ssh nibi echo "OK"
ssh mila echo "OK"
```
After this, the orchestrator uses the persistent multiplexed connections with no further 2FA.

---

## Scheduling Strategy

**Prefer short jobs (≤3h) for fastest scheduling.** SLURM backfill scheduling fills gaps with short jobs, so a 3h job starts much sooner than a 7d job. Use checkpoint-resume + self-resubmission to chain short jobs into long training runs.

**DRAC nested time partitions (shorter = more partitions = faster start):**
- ≤3h → eligible for ALL partitions
- ≤12h → most partitions
- ≤24h → fewer
- ≤7d → minimum partitions

**Mila:** Use `short-unkillable` (3h, up to 4 GPUs) for H100 or guaranteed short runs. Use `unkillable` (2d, 1 GPU) for single-GPU guaranteed. Use `main` (5d, 2 GPU) for standard. `long` (7d, no GPU limit) for large runs but lowest priority.

---

## DRAC Accounts

| Account | Use for | Clusters |
|---------|---------|----------|
| `rrg-bengioy-ad` | Default for all CC jobs (RAC, higher priority) | rorqual, fir, nibi, narval |
| `def-bengioy` | Fallback / low-priority test jobs | rorqual, fir, nibi, narval |
| `aip-lcharlin` | TamIA (PAICE, required) | tamia |

---

## TODO

- [x] ~~Define job config schema~~ → see `configs/example-job.yaml`
- [x] ~~Implement job submission pipeline~~ → see `/launch-job` skill
- [ ] Determine which clusters we actually have active allocations on
- [ ] Implement monitoring loop with state persistence
- [ ] Add auto-resubmit logic (FAILED, TIMEOUT, OOM)
- [ ] Add multi-cluster failover
- [ ] Add log aggregation (tail remote logs to local)
- [ ] Add notification system (Slack/email on job state changes)
