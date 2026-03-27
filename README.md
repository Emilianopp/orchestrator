# Orchestrator

Autonomous job orchestration for SLURM-based HPC clusters (Mila, Alliance Canada). Works as a Claude Code plugin and standalone CLI toolkit.

## Quick Start

```bash
# Clone
git clone git@github.com:Emilianopp/orchestrator.git ~/Git/orchestrator

# Warm up SSH connections (once per day for 2FA)
~/Git/orchestrator/scripts/warmup.sh

# Check GPU availability
~/Git/orchestrator/scripts/gpu-status.sh
```

## Install into a project

```bash
cd ~/Git/my-project
~/Git/orchestrator/scripts/install.sh .
```

This symlinks slash commands and cluster context into your project so Claude Code can use them:

- `/orch-gpu-status` — check GPU availability across all clusters
- Cluster knowledge (GPU inventory, partitions, storage, SLURM patterns) available as context

To remove:

```bash
~/Git/orchestrator/scripts/uninstall.sh .
```

## Structure

```
orchestrator/
├── CLAUDE.md              # Cluster knowledge + orchestrator spec
├── commands/              # Claude Code slash commands
│   └── gpu-status.md
├── scripts/
│   ├── gpu-status.sh      # GPU availability checker
│   ├── warmup.sh          # SSH 2FA warmup
│   ├── install.sh         # Install into a project
│   └── uninstall.sh       # Remove from a project
└── configs/
    └── example-job.yaml   # Job config template
```

## Clusters

| Cluster | GPUs | Status |
|---------|------|--------|
| Mila | L40S, A100, H100, RTX 8000, V100, A6000 | Live |
| Rorqual | H100 | Live |
| Fir | H100 | Live |
| Nibi | H100, MI300A | Live |
| Trillium | H100 | Live |
| TamIA | H200, H100 | Connecting |
| Narval | A100 40GB | Down |
