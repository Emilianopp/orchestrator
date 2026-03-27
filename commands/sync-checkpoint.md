Sync weight checkpoints between HPC clusters via HuggingFace Hub.

You are a checkpoint synchronization agent. You push trained weight checkpoints from one cluster to HuggingFace Hub, and pull them down on another cluster to continue training. Follow these steps precisely.

**Per-run subdirectories:** Checkpoints are stored under `{run_name}/` within the shared HF repo, so multiple runs can coexist. The run name is the basename of `output_dir` (e.g., `outputs/compaction-suffix-queries` → `compaction-suffix-queries`). If no run name is given, ask the user or infer from context.

---

## Determine mode

Ask the user which operation they need (or infer from context):

- **push** — upload the latest checkpoint from a cluster to HF Hub
- **pull** — download the latest checkpoint from HF Hub to a cluster
- **status** — show what's currently on HF Hub

---

## Mode: Push

### Step 1: Identify source

Determine:
- **Source cluster** — which cluster has the checkpoint (ask or infer from context)
- **Output dir** — where checkpoints live (default: `$SCRATCH/outputs/`)
- **HF repo** — convention: `ppEmiliano/{project_name}-checkpoints`

Verify the cluster has a live SSH connection:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "echo ok"
```

### Step 2: Find the latest STABLE checkpoint

Search for the latest weight checkpoint with a STABLE marker:
```bash
ssh -o BatchMode=yes CLUSTER '
  OUTPUT_DIR="${SCRATCH}/outputs/OUTPUT_DIR_NAME"
  WEIGHTS_DIR="${OUTPUT_DIR}/weights"
  if [ ! -d "$WEIGHTS_DIR" ]; then
    echo "ERROR: No weights directory at $WEIGHTS_DIR"
    exit 1
  fi
  # Find latest step with STABLE marker
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
    echo "ERROR: No STABLE checkpoint found in $WEIGHTS_DIR"
    exit 1
  fi
  echo "FOUND:${LATEST_STEP}:${LATEST}"
  # Show contents for verification
  ls -lh "$LATEST"
'
```

**Never push a checkpoint without a STABLE marker.**

### Step 3: Verify HF CLI is available and authenticated

The CLI command is `hf` (huggingface_hub >= 1.0). Activate the project venv first:
```bash
ssh -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate
  command -v hf >/dev/null 2>&1 || { echo "ERROR: hf CLI not found. Install with: uv pip install huggingface-hub"; exit 1; }
  hf auth whoami || { echo "ERROR: Not authenticated. Run: hf auth login"; exit 1; }
'
```

If missing, install with `uv pip install huggingface-hub` (or `~/.local/bin/uv pip install huggingface-hub` on Mila).

### Step 4: Upload to HuggingFace Hub

Push the checkpoint contents to the HF repo. Use `--delete '*'` to ensure only the latest checkpoint exists on the hub (no history accumulation of old steps).

```bash
ssh -o ServerAliveInterval=30 -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate 2>/dev/null
  STEP=STEP_NUMBER
  CHECKPOINT_PATH=FULL_CHECKPOINT_PATH
  HF_REPO=HF_REPO_NAME

  # Create checkpoint_info.json
  cat > "${CHECKPOINT_PATH}/checkpoint_info.json" << EOF
{
  "step": $STEP,
  "source_cluster": "CLUSTER_NAME",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "output_dir": "OUTPUT_DIR"
}
EOF

  # Upload — replaces all files in the run's subdirectory
  hf upload "$HF_REPO" "$CHECKPOINT_PATH" {run_name}/ \
    --repo-type model \
    --delete "{run_name}/*" \
    --commit-message "step $STEP from CLUSTER_NAME for {run_name}"
'
```

If the repo doesn't exist, create it first:
```bash
ssh -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate 2>/dev/null
  hf repo create HF_REPO_NAME --type model 2>/dev/null || true
'
```

### Step 5: Clean up old checkpoints on source cluster

After a successful push, remove older weight checkpoint directories (keep only the one just pushed):

```bash
ssh -o BatchMode=yes CLUSTER '
  WEIGHTS_DIR=WEIGHTS_DIR_PATH
  KEEP_STEP=STEP_NUMBER
  for d in "$WEIGHTS_DIR"/step_*/; do
    STEP=$(basename "$d" | sed "s/step_//")
    if [ "$STEP" != "$KEEP_STEP" ]; then
      echo "Removing old checkpoint: $d"
      rm -rf "$d"
    fi
  done
'
```

### Step 6: Report success

```
Checkpoint pushed:
  Step:    STEP_NUMBER
  Source:  CLUSTER_NAME
  HF repo: https://huggingface.co/HF_REPO_NAME

To pull on another cluster:
  /orch-sync-checkpoint pull → HF_REPO_NAME → target cluster
```

---

## Mode: Pull

### Step 1: Identify target

Determine:
- **Target cluster** — where to download the checkpoint
- **HF repo** — `ppEmiliano/{project_name}-checkpoints`
- **Output dir** — destination (default: `$SCRATCH/outputs/`)

Verify the cluster has a live SSH connection:
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "echo ok"
```

### Step 2: Read checkpoint metadata from HF

```bash
ssh -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate 2>/dev/null
  hf download HF_REPO_NAME --include "{run_name}/checkpoint_info.json" --local-dir /tmp/hf_ckpt_info --quiet
  cat /tmp/hf_ckpt_info/{run_name}/checkpoint_info.json
  rm -rf /tmp/hf_ckpt_info
'
```

Extract the step number from `checkpoint_info.json`.

### Step 3: Download checkpoint

```bash
ssh -o ServerAliveInterval=30 -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate 2>/dev/null
  STEP=STEP_NUMBER
  OUTPUT_DIR="${SCRATCH}/outputs/OUTPUT_DIR_NAME"
  DEST="${OUTPUT_DIR}/weights/step_${STEP}"
  mkdir -p "$DEST"

  hf download HF_REPO_NAME \
    --include "{run_name}/*" \
    --local-dir /tmp/_orch_hf_pull \
    --quiet

  # Move files from run subdirectory into weights structure
  cp -r /tmp/_orch_hf_pull/{run_name}/* "$DEST/"
  rm -rf /tmp/_orch_hf_pull

  echo "Downloaded to: $DEST"
  ls -lh "$DEST"
'
```

### Step 4: Verify checkpoint integrity

```bash
ssh -o BatchMode=yes CLUSTER '
  DEST=DEST_PATH
  ERRORS=0

  # Check for safetensors files
  if ! ls "$DEST"/*.safetensors 1>/dev/null 2>&1; then
    echo "ERROR: No safetensors files found"
    ERRORS=$((ERRORS + 1))
  fi

  # Check for config.json
  if [ ! -f "$DEST/config.json" ]; then
    echo "ERROR: config.json missing"
    ERRORS=$((ERRORS + 1))
  fi

  # Ensure STABLE marker exists
  if [ ! -f "$DEST/STABLE" ]; then
    echo "Adding STABLE marker"
    touch "$DEST/STABLE"
  fi

  if [ $ERRORS -gt 0 ]; then
    echo "INTEGRITY CHECK FAILED ($ERRORS errors)"
    exit 1
  fi

  echo "Checkpoint integrity OK"
'
```

### Step 5: Clean up old checkpoints on target cluster

Remove any pre-existing weight checkpoint directories (keep only the one just pulled):

```bash
ssh -o BatchMode=yes CLUSTER '
  WEIGHTS_DIR=WEIGHTS_DIR_PATH
  KEEP_STEP=STEP_NUMBER
  for d in "$WEIGHTS_DIR"/step_*/; do
    [ -d "$d" ] || continue
    STEP=$(basename "$d" | sed "s/step_//")
    if [ "$STEP" != "$KEEP_STEP" ]; then
      echo "Removing old checkpoint: $d"
      rm -rf "$d"
    fi
  done
'
```

### Step 6: Report success

```
Checkpoint pulled:
  Step:    STEP_NUMBER
  Source:  SOURCE_CLUSTER (from checkpoint_info.json)
  Target:  TARGET_CLUSTER
  Path:    $SCRATCH/outputs/OUTPUT_DIR_NAME/weights/step_STEP/

Training will auto-detect this checkpoint with resume_step = -1.
Ready to launch: /orch-launch-job
```

---

## Mode: Status

Query the HF repo for the latest checkpoint metadata for a specific run:

```bash
ssh -o BatchMode=yes CLUSTER '
  source PROJECT_PATH/.venv/bin/activate 2>/dev/null
  hf download HF_REPO_NAME --include "{run_name}/checkpoint_info.json" --local-dir /tmp/hf_ckpt_info --quiet
  cat /tmp/hf_ckpt_info/{run_name}/checkpoint_info.json
  rm -rf /tmp/hf_ckpt_info
'
```

Or if `huggingface-cli` is available locally:
```bash
hf download HF_REPO_NAME --include "{run_name}/checkpoint_info.json" --local-dir /tmp/hf_ckpt_info --quiet
cat /tmp/hf_ckpt_info/{run_name}/checkpoint_info.json
rm -rf /tmp/hf_ckpt_info
```

Report:
```
HF repo: https://huggingface.co/HF_REPO_NAME
  Step:    STEP_NUMBER
  Source:  CLUSTER_NAME
  Pushed:  TIMESTAMP
```

---

## Important reminders

- **Weights only** — we push `weights/step_{N}/` (safetensors + config.json + tokenizer), NOT full DCP trainer checkpoints. These are small and HF-compatible.
- **Only keep the latest checkpoint** everywhere:
  - HF Hub: `--delete '{run_name}/*'` on upload ensures only one step per run
  - Source cluster: delete older `weights/step_*/` after push
  - Target cluster: delete older `weights/step_*/` after pull
- **Per-run subdirectories** — each run stores checkpoints under `{run_name}/` in the HF repo, so multiple runs can coexist in the same repo
- **STABLE marker required** — never push without one, add one after pull if missing
- **Login nodes only** — all uploads/downloads run on login nodes (internet available)
- **Idempotent** — `hf upload` is safe to re-run
- **HF repo convention** — `ppEmiliano/{project_name}-checkpoints`
- **Default output dir** — `$SCRATCH/outputs/` on all clusters
- Use `ssh -o ServerAliveInterval=30` for upload/download to prevent timeout on large transfers
- Use `ssh -o BatchMode=yes -o ConnectTimeout=5` for quick checks
