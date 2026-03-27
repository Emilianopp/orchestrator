Install the current project onto all live HPC clusters.

You are a remote environment installer. Your goal is to clone the project repo, set up the Python environment (via uv), and verify it's ready to run on every reachable cluster. Follow these steps precisely.

---

## Step 1: Understand the project

Read the current project to determine:
- The **git remote URL**: `git remote get-url origin`
- The **current branch**: `git branch --show-current`
- The **project name**: basename of the repo
- Whether it uses **uv** (look for `pyproject.toml` + `uv.lock`) or **pip** (`requirements.txt`)
- Any special setup (`.env` file, git submodules, LFS, etc.)

---

## Step 2: Check which clusters are live

Run `ssh -O check <host>` for each of: mila, rorqual, fir, nibi, trillium, tamia, narval. All checks in parallel.

Only proceed with clusters that have a live SSH master connection.

---

## Step 3: Install on each live cluster (in parallel)

For each live cluster, run the install sequence via SSH. **Run all clusters in parallel** using background commands or parallel tool calls.

### Cluster-specific details

| Cluster | Username | Home convention | Internet on login | Internet on compute |
|---------|----------|-----------------|-------------------|---------------------|
| mila | `emiliano.penaloza` | `$HOME` = `/home/mila/e/emiliano.penaloza` | Yes | Yes |
| rorqual | `emiliano` | `$HOME` | Yes | No |
| fir | `emiliano` | `$HOME` | Yes | Yes |
| nibi | `emiliano` | `$HOME` | Yes | Yes |
| trillium | `emiliano` | `$HOME` | Yes | Unknown |
| tamia | `emiliano` | `$HOME` | Yes | No |
| narval | `emiliano` | `$HOME` | Yes | No |

**All login nodes have internet**, so `uv sync` / `pip install` works on all of them.

### Install sequence (per cluster)

```bash
# 1. Clone or update the repo
PROJECT=PROJECT_NAME
BRANCH=BRANCH_NAME
REPO_URL=GIT_REMOTE_URL

ssh -o BatchMode=yes -o ConnectTimeout=10 CLUSTER bash -s << 'REMOTE_EOF'
set -euo pipefail

PROJECT="PROJECT_NAME"
BRANCH="BRANCH_NAME"
REPO_URL="GIT_REMOTE_URL"
PROJECT_DIR="$HOME/$PROJECT"

echo "=== Installing $PROJECT on $(hostname) ==="

# Clone or pull
if [ -d "$PROJECT_DIR/.git" ]; then
    echo "Repo exists, pulling latest..."
    cd "$PROJECT_DIR"
    git fetch origin
    git checkout "$BRANCH"
    git pull origin "$BRANCH"
else
    echo "Cloning repo..."
    git clone "$REPO_URL" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    git checkout "$BRANCH"
fi

# Handle submodules if present
if [ -f .gitmodules ]; then
    git submodule update --init --recursive
fi

# Setup environment
if [ -f uv.lock ]; then
    # uv-based project
    echo "Setting up with uv..."
    if ! command -v uv &>/dev/null; then
        echo "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    uv sync --all-extras 2>&1 | tail -5
    echo "uv sync complete"
elif [ -f requirements.txt ]; then
    # pip-based project
    echo "Setting up with pip..."
    python3 -m venv .venv 2>/dev/null || python -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip -q
    pip install -r requirements.txt -q
    echo "pip install complete"
elif [ -f pyproject.toml ]; then
    # pyproject with no lockfile — use uv anyway
    echo "Setting up with uv (from pyproject.toml)..."
    if ! command -v uv &>/dev/null; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.local/bin:$PATH"
    fi
    uv sync 2>&1 | tail -5
    echo "uv sync complete"
else
    echo "WARNING: No dependency file found (uv.lock, requirements.txt, pyproject.toml)"
fi

# Verify
echo ""
echo "Project dir: $PROJECT_DIR"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"
echo "Commit: $(git rev-parse --short HEAD)"
if [ -d .venv ]; then
    echo "Python: $(.venv/bin/python --version 2>&1)"
fi
echo "=== Done ==="
REMOTE_EOF
```

---

## Step 4: Handle failures

If a cluster fails:
- **SSH timeout** → skip it, note as unreachable
- **Git clone fails** → check if the SSH key can access the repo (the user may need to add their cluster's SSH key to GitHub)
- **uv/pip fails** → show the error, suggest running manually

Common fix for git access:
```bash
ssh CLUSTER "cat ~/.ssh/id_rsa.pub || cat ~/.ssh/id_ed25519.pub"
```
Then add that key to GitHub.

---

## Step 5: Report results

Show a summary table:

```
=== Install Summary ===
Cluster      Status    Branch    Commit    Path
==========   =======   =======   =======   ====
mila         OK        main      abc1234   /home/mila/e/emiliano.penaloza/PROJECT
rorqual      OK        main      abc1234   /home/emiliano/PROJECT
fir          OK        main      abc1234   /home/emiliano/PROJECT
nibi         FAILED    -         -         (git clone failed — SSH key not on GitHub)
trillium     SKIP      -         -         (not connected)
```

---

## Notes

- Always use `ssh -o BatchMode=yes -o ConnectTimeout=10` to avoid hangs
- Run installs in parallel across clusters — don't wait for one to finish before starting the next
- On DRAC clusters without internet on compute (rorqual, tamia), the `uv sync` on the login node ensures all packages are cached in `.venv` so compute jobs don't need to download anything
- If the project has a `.env` file locally, do NOT copy it automatically — it may contain secrets. Ask the user first.
- The project is installed to `$HOME/PROJECT_NAME` by default. If the user has a preference for `$SCRATCH`, ask.
