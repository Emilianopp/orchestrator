Check GPU availability across all connected clusters. Only report full GPUs (no MIG slices).

Steps:
1. Check which clusters have live SSH master connections by running `ssh -O check <host>` for each of: mila, rorqual, fir, nibi, tamia, narval. Run all checks in parallel.

2. For all live clusters, run `scripts/gpu-status.sh` which handles both Mila (`savail`) and DRAC (`sinfo` with GresUsed) automatically.

3. Present results to the user as the script outputs them.

4. If the script doesn't exist or fails, fall back to running the commands manually:
   - **Mila**: `ssh -o BatchMode=yes -o ConnectTimeout=5 mila "savail"`
   - **DRAC clusters**: `ssh -o BatchMode=yes -o ConnectTimeout=5 <host> "sinfo -N -O 'NodeHost:20,Gres:50,GresUsed:50,StateLong:15' --noheader"`
   Then filter to only full GPUs (h100, a100l, a100, a6000, l40s, rtx8000, v100, mi300a, h200). Ignore any MIG types containing `_Xg.YYgb` patterns.

Notes:
- Only report full GPUs per our GPU policy: H100 full, A100 80GB (a100l on Mila), etc.
- Never report MIG slices (nvidia_h100_80gb_hbm3_3g.40gb, 2g.20gb, 1g.10gb)
- Always use `ssh -o BatchMode=yes -o ConnectTimeout=5` to avoid hanging
- Highlight clusters with the most available GPUs
