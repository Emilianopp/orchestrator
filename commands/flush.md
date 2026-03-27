Cancel all jobs and clean up all artifacts for a specific training run.

You are a run cleanup agent. You cancel SLURM jobs, delete remote outputs and configs, clean HuggingFace Hub files, and remove local state. Follow these steps precisely.

---

## Step 0: Identify the run

If the user provides a run name, use it. Otherwise, list all runs from `state/*.json` and ask the user which one to flush.

If no state files exist, tell the user there are no tracked runs.

---

## Step 1: Load state and confirm

Read `state/{run_name}.json`. Display what will be destroyed:

```
Flush: {run_name}

This will:
  - Cancel active SLURM jobs on: {cluster1}, {cluster2}, ...
  - Delete $SCRATCH/outputs/{run_name}/ on: {cluster1}, {cluster2}, ...
  - Delete configs/_orch/{run_name}.toml and scripts/_orch/{run_name}.sbatch on all clusters
  - Delete {run_name}/ from HF repo ppEmiliano/attention-matching-rl-checkpoints
  - Remove local state files

Proceed? (y/n)
```

**Wait for user confirmation before proceeding.**

---

## Step 2: Cancel SLURM jobs

For each cluster that has an active or recent job (state is RUNNING or PENDING), run in parallel:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 CLUSTER "scancel JOB_ID 2>/dev/null; scancel --name={run_name} 2>/dev/null; echo 'cancelled'"
```

The `scancel --name` catches any stragglers (e.g., resubmitted jobs the state file doesn't know about).

---

## Step 3: Clean remote outputs

For each cluster that was involved in the run (listed in state `clusters` field), run in parallel:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 CLUSTER '
  rm -rf $SCRATCH/outputs/{run_name}
  rm -f ~/attention-matching-rl/configs/_orch/{run_name}.toml
  rm -f ~/attention-matching-rl/scripts/_orch/{run_name}.sbatch
  echo "cleaned"
'
```

If a cluster is unreachable, warn but continue with the others.

---

## Step 4: Clean HuggingFace Hub

Delete this run's files from the shared checkpoint repo. Use any live cluster with the `hf` CLI:

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 CLUSTER '
  source ~/attention-matching-rl/.venv/bin/activate
  # Upload empty dir to delete the run subfolder
  mkdir -p /tmp/_orch_flush_empty
  hf upload ppEmiliano/attention-matching-rl-checkpoints /tmp/_orch_flush_empty {run_name}/ \
    --repo-type model \
    --delete "{run_name}/*" \
    --commit-message "flush {run_name}" 2>/dev/null
  rm -rf /tmp/_orch_flush_empty
  echo "hf cleaned"
'
```

If this fails (no files on HF, repo doesn't exist, etc.), that's fine — just note it.

---

## Step 5: Remove local state

```bash
rm -f state/{run_name}.json state/{run_name}.md
```

---

## Step 6: Report

```
Flushed: {run_name}

  Jobs cancelled:     {cluster1} (job XXXX), {cluster2} (job XXXX)
  Outputs deleted:    {cluster1}, {cluster2}, ...
  HF Hub cleaned:     ppEmiliano/attention-matching-rl-checkpoints/{run_name}/
  Local state removed

  Unreachable clusters (manual cleanup needed): {list, if any}
```

---

## Important reminders

- **Always ask for confirmation** before flushing. This is destructive.
- Run cancellations and cleanups in parallel across clusters.
- Use `-o BatchMode=yes` on all SSH commands.
- If a cluster is down, skip it and report it as needing manual cleanup later.
- State files are in the orchestrator repo's `state/` directory.
- Only flush the specified run — never touch other runs' data.
