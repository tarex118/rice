#!/usr/bin/env bash
# Rice setup script for Fedora
# Uses dnf only - no flatpak, no snap
set -euo pipefail

ARCH=$(uname -m)
# Map kernel arch to release arch names (kubectl/k9s/kubecolor use amd64/arm64; lazygit/AWS use x86_64/aarch64)
case "$ARCH" in
  x86_64)   RELEASE_ARCH="amd64"; RUST_ARCH="x86_64"; AWS_ARCH="x86_64" ;;
  aarch64)  RELEASE_ARCH="arm64"; RUST_ARCH="arm64"; AWS_ARCH="aarch64" ;;
  arm64)    RELEASE_ARCH="arm64"; RUST_ARCH="arm64"; AWS_ARCH="aarch64" ;;
  *) echo "[!] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Non-zero exit from a step function = failure. This code = skipped (wrong arch/CPU), not failure.
RICE_STEP_SKIP=99

# ------------------------- Functions -------------------------
install_core_packages() {
  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  local pkgs=(
    dnf-plugins-core curl wget git unzip zsh
    neovim ripgrep fd-find bat
    jq pwgen tmux xclip fontconfig fzf glibc-langpack-en
  )
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    rpm -q "$p" &>/dev/null || missing+=("$p")
  done
  if ((${#missing[@]} > 0)); then
    echo "[*] Installing missing base packages (${#missing[@]}): ${missing[*]}..."
    sudo dnf install -y "${missing[@]}"
  else
    echo "[✓] Base dnf packages already installed."
  fi
  if ! rpm -q gcc &>/dev/null; then
    echo "[*] Installing @development-tools (gcc not present)..."
    sudo dnf install -y @development-tools
  else
    echo "[✓] @development-tools already satisfied (gcc present)."
  fi

  # Fedora: fd-find provides fdfind; create fd symlink for compatibility
  if command -v fdfind &>/dev/null && [ ! -e ~/.local/bin/fd ]; then
    ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  fi

  export LANG=en_US.UTF-8
}

install_rpmfusion() {
  if rpm -q rpmfusion-free-release rpmfusion-nonfree-release &>/dev/null; then
    echo "[✓] RPM Fusion already enabled."
    return
  fi
  echo "[*] Adding RPM Fusion repositories..."
  sudo dnf install -y \
    "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
  echo "[✓] RPM Fusion enabled."
}

# Intel i7-1185G7 (11th Gen Tiger Lake, Iris Xe 96 EU) and same-class CPUs: microcode + VA-API/Vulkan.
# Mesa + linux-firmware usually cover the GPU; this pulls microcode_ctl and the standard media/Vulkan stack.
install_intel_microcode_and_igpu() {
  if [[ "$ARCH" != "x86_64" ]]; then
    echo "[!] Intel microcode / iGPU packages: skipping (x86_64 only)."
    return "$RICE_STEP_SKIP"
  fi
  if ! grep -qE '^vendor_id\s*:\s*GenuineIntel' /proc/cpuinfo 2>/dev/null; then
    echo "[!] Intel microcode / iGPU: skipping (no Intel CPU in /proc/cpuinfo)."
    return "$RICE_STEP_SKIP"
  fi
  local intel_pkgs=(microcode_ctl intel-media-driver mesa-vulkan-drivers libva-utils)
  local missing=()
  local p
  for p in "${intel_pkgs[@]}"; do
    rpm -q "$p" &>/dev/null || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    echo "[✓] Intel microcode + iGPU packages already installed."
    return
  fi
  echo "[*] Installing Intel CPU microcode / iGPU packages (missing: ${missing[*]})..."
  sudo dnf install -y "${missing[@]}"
  echo "[✓] Intel microcode + iGPU stack installed. Reboot to apply microcode; optional: vainfo"
}

install_easyeffects() {
  if command -v easyeffects &>/dev/null || rpm -q easyeffects &>/dev/null 2>&1; then
    echo "[✓] Easy Effects already installed."
    return
  fi
  echo "[*] Installing Easy Effects..."
  sudo dnf install -y easyeffects
  echo "[✓] Easy Effects installed."
}

install_easyeffects_thinkpad_preset() {
  local preset="$HOME/.config/easyeffects/output/thinkpad-unsuck.json"
  if [[ -s "$preset" ]]; then
    echo "[✓] Easy Effects thinkpad-unsuck preset already present."
    return
  fi
  echo "[*] Installing Thinkpad P14s Gen 2 AMD preset (thinkpad-unsuck)..."
  mkdir -p ~/.config/easyeffects/output
  curl -sSLo "$preset" \
    "https://raw.githubusercontent.com/sebastian-de/easyeffects-thinkpad-unsuck/main/thinkpad-unsuck.json"
  echo "[✓] Preset installed. Load 'thinkpad-unsuck' in Easy Effects → Output → Presets."
}

install_brave() {
  if command -v brave-browser &>/dev/null || rpm -q brave-browser &>/dev/null 2>&1; then
    echo "[✓] Brave already installed."
    return
  fi
  echo "[*] Adding Brave Browser RPM repository..."
  sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null || {
    sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
  }
  echo "[*] Installing Brave..."
  sudo dnf install -y brave-browser
  echo "[✓] Brave installed."
}

install_cursor() {
  if command -v cursor &>/dev/null || rpm -q cursor &>/dev/null 2>&1; then
    echo "[✓] Cursor already installed."
    return
  fi
  echo "[*] Installing Cursor (official RPM)..."
  curl -fsSL -o /tmp/cursor.rpm "https://www.cursor.com/download/linux/rpm"
  sudo dnf install -y /tmp/cursor.rpm
  rm -f /tmp/cursor.rpm
  echo "[✓] Cursor installed."
}

install_claude_cli() {
  if command -v claude &>/dev/null; then
    echo "[✓] Claude Code CLI already installed."
    return
  fi
  echo "[*] Installing Claude Code CLI (official installer → ~/.local/bin)..."
  curl -fsSL https://claude.ai/install.sh | bash
  echo "[✓] Claude CLI installed. Ensure ~/.local/bin is on PATH."
}

install_spotify() {
  if command -v spotify &>/dev/null || rpm -q spotify-client &>/dev/null 2>&1; then
    echo "[✓] Spotify already installed."
    return
  fi
  if [[ "$ARCH" != "x86_64" ]]; then
    echo "[!] Spotify RPM from negativo17 is x86_64-only. Try: sudo dnf install lpf-spotify-client (RPM Fusion)."
    return "$RICE_STEP_SKIP"
  fi
  echo "[*] Adding negativo17 Spotify RPM repository..."
  sudo dnf config-manager addrepo --from-repofile=https://negativo17.org/repos/fedora-spotify.repo 2>/dev/null || \
    sudo dnf config-manager --add-repo=https://negativo17.org/repos/fedora-spotify.repo
  echo "[*] Installing spotify-client..."
  sudo dnf install -y spotify-client
  echo "[✓] Spotify installed."
}

install_zoxide() {
  if ! command -v zoxide &>/dev/null; then
    echo "[*] Installing zoxide..."
    curl -sSf https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  else
    echo "[✓] zoxide already installed."
  fi
}

install_lazygit() {
  if ! command -v lazygit &>/dev/null; then
    echo "[*] Installing LazyGit (latest)..."
    VERSION=$(curl -sL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | jq -r '.tag_name')
    # Format: lazygit_0.59.0_linux_x86_64.tar.gz (lowercase linux)
    LAZYGIT_URL="https://github.com/jesseduffield/lazygit/releases/download/${VERSION}/lazygit_${VERSION#v}_linux_${RUST_ARCH}.tar.gz"
    curl -sSLo /tmp/lazygit.tar.gz "$LAZYGIT_URL"
    tar -xzf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo install /tmp/lazygit /usr/local/bin/
    rm -f /tmp/lazygit /tmp/lazygit.tar.gz
    echo "[✓] lazygit installed ($VERSION)."
  else
    echo "[✓] lazygit already installed."
  fi
}

install_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "[*] Installing kubectl (stable)..."
    KUBE_VER=$(curl -sL https://dl.k8s.io/release/stable.txt)
    curl -sLO "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/${RELEASE_ARCH}/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
    echo "[✓] kubectl installed ($KUBE_VER)."
  else
    echo "[✓] kubectl already installed."
  fi
}

install_kubecolor() {
  if ! command -v kubecolor &>/dev/null; then
    echo "[*] Installing kubecolor (latest)..."
    TAG=$(curl -sL https://api.github.com/repos/kubecolor/kubecolor/releases/latest | jq -r '.tag_name')
    VER="${TAG#v}"
    # Prefer RPM on Fedora
    RPM_URL="https://github.com/kubecolor/kubecolor/releases/download/${TAG}/kubecolor_${VER}_linux_${RELEASE_ARCH}.rpm"
    curl -sSLo /tmp/kubecolor.rpm "$RPM_URL"
    sudo dnf install -y /tmp/kubecolor.rpm
    rm -f /tmp/kubecolor.rpm
    echo "[✓] kubecolor installed ($TAG)."
  else
    echo "[✓] kubecolor already installed."
  fi
}

install_kubectx_kubens() {
  if command -v kubectx &>/dev/null && command -v kubens &>/dev/null; then
    echo "[✓] kubectx and kubens already installed."
    return
  fi
  echo "[*] Installing kubectx and kubens..."
  [ -d ~/.kubectx ] || git clone --depth 1 https://github.com/ahmetb/kubectx ~/.kubectx
  sudo ln -sf ~/.kubectx/kubectx /usr/local/bin/kubectx
  sudo ln -sf ~/.kubectx/kubens /usr/local/bin/kubens
  echo "[✓] kubectx/kubens installed."
}

install_k9s() {
  if ! command -v k9s &>/dev/null; then
    echo "[*] Installing k9s (latest)..."
    TAG=$(curl -sL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    # Prefer RPM on Fedora
    RPM_URL="https://github.com/derailed/k9s/releases/download/${TAG}/k9s_linux_${RELEASE_ARCH}.rpm"
    curl -sSLo /tmp/k9s.rpm "$RPM_URL"
    sudo dnf install -y /tmp/k9s.rpm
    rm -f /tmp/k9s.rpm
    echo "[✓] k9s installed ($TAG)."
  else
    echo "[✓] k9s already installed."
  fi
}

install_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "[*] Installing AWS CLI v2..."
    curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" -o /tmp/awscliv2.zip
    unzip -q -o /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
    echo "[✓] AWS CLI installed."
  else
    echo "[✓] AWS CLI already installed."
  fi
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "[*] Installing Docker Engine (official repo)..."
    # Fedora 41+ (DNF 5) uses addrepo --from-repofile; older Fedora uses --add-repo
    sudo dnf config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo 2>/dev/null || \
      sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    echo "[i] Added $USER to docker group. Log out & back in (or run: newgrp docker)."
    echo "[✓] Docker installed. Use 'docker compose' (with space) for compose."
  else
    echo "[✓] Docker already installed."
  fi
}

install_fonts() {
  if fc-list 2>/dev/null | grep -qiE 'FiraCode.*Nerd|Nerd.*FiraCode'; then
    echo "[✓] FiraCode Nerd Font already installed (fc-list)."
    return
  fi
  echo "[*] Installing FiraCode Nerd Font..."
  [ -d ~/nerd-fonts ] || git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ~/nerd-fonts
  ~/nerd-fonts/install.sh FiraCode
  rm -rf ~/nerd-fonts
  fc-cache -fv
  echo "[✓] FiraCode Nerd Font installed."
}

install_ohmyzsh_and_plugins() {
  export ZSH="$HOME/.oh-my-zsh"
  local ZSH_CUSTOM="$ZSH/custom"
  if [[ -d "$ZSH" && -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" && -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" && -d "${ZSH_CUSTOM}/themes/powerlevel10k" && -d ~/.kube-ps1 ]]; then
    echo "[✓] Oh My Zsh and plugins already installed."
    return
  fi
  if [ ! -d "$ZSH" ]; then
    echo "[*] Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  [ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] || git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  [ -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] || git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  [ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ] || git clone --depth 1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
  [ -d ~/.kube-ps1 ] || git clone --depth 1 https://github.com/jonmosco/kube-ps1.git ~/.kube-ps1
}

write_zshrc() {
  if [[ -f ~/.zshrc ]] && head -n 1 ~/.zshrc | grep -q 'rice-fedora: managed dotfile'; then
    echo "[✓] ~/.zshrc already installed (rice-fedora marker); not overwriting."
    return
  fi
  echo "[*] Writing .zshrc..."
  cat > ~/.zshrc << 'EOF'
# rice-fedora: managed dotfile
# Enable Powerlevel10k instant prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$HOME/.local/bin:$PATH"
export KUBECONFIG="$HOME/.kube/config"

ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git fzf zsh-syntax-highlighting zsh-autosuggestions kube-ps1)
RPROMPT='$(kube_ps1)'

source ~/.kube-ps1/kube-ps1.sh
source $ZSH/oh-my-zsh.sh

compdef kubecolor=kubectl
source <(kubectl completion zsh)

ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
ZSH_HIGHLIGHT_STYLES[default]=none
ZSH_HIGHLIGHT_STYLES[unknown-token]=fg=red,bold
ZSH_HIGHLIGHT_STYLES[reserved-word]=fg=cyan,bold
ZSH_HIGHLIGHT_STYLES[suffix-alias]=fg=green,underline
ZSH_HIGHLIGHT_STYLES[global-alias]=fg=magenta
ZSH_HIGHLIGHT_STYLES[precommand]=fg=green,underline
ZSH_HIGHLIGHT_STYLES[commandseparator]=fg=blue,bold
ZSH_HIGHLIGHT_STYLES[autodirectory]=fg=green,underline
ZSH_HIGHLIGHT_STYLES[path]=underline
ZSH_HIGHLIGHT_STYLES[globbing]=fg=blue,bold
ZSH_HIGHLIGHT_STYLES[history-expansion]=fg=blue,bold
ZSH_HIGHLIGHT_STYLES[command-substitution-delimiter]=fg=magenta
ZSH_HIGHLIGHT_STYLES[process-substitution-delimiter]=fg=magenta
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]=fg=magenta
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]=fg=magenta
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]=fg=yellow
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]=fg=yellow
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]=fg=yellow
ZSH_HIGHLIGHT_STYLES[comment]=fg=black,bold
ZSH_HIGHLIGHT_STYLES[arg0]=fg=green
ZSH_HIGHLIGHT_STYLES[bracket-error]=fg=red,bold
ZSH_HIGHLIGHT_STYLES[bracket-level-1]=fg=blue,bold
ZSH_HIGHLIGHT_STYLES[bracket-level-2]=fg=green,bold
ZSH_HIGHLIGHT_STYLES[bracket-level-3]=fg=magenta,bold
ZSH_HIGHLIGHT_STYLES[bracket-level-4]=fg=yellow,bold
ZSH_HIGHLIGHT_STYLES[bracket-level-5]=fg=cyan,bold
ZSH_HIGHLIGHT_STYLES[cursor-matchingbracket]=standout

ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#999999"

alias shoot='kubectl run net-test --rm -it --image=nicolaka/netshoot --restart=Never -- bash'
alias vim='nvim'
alias c="xclip -selection clipboard"
alias cat="bat"
alias k="kubecolor"
alias mount-backup='sudo mount -t nfs -o resvport 192.168.1.20:/mnt/backup ~/mnt/backup'
alias myip='curl -s https://icanhazip.com'
alias kx='kubectx'
alias kn='kubens'
alias pw1='pwgen -s 15'
alias projects='cd ~/Documents/projects/'
alias code='cursor'
alias mount-personal='sudo mount -t nfs -o resvport 192.168.1.200:/mnt/Personal ~/Personal'
source <(fzf --zsh)
eval "$(zoxide init zsh)"

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
EOF
}

run_step() {
  local name="$1" ec=0
  shift
  "$@" || ec=$?
  if [[ $ec -eq 0 ]]; then
    RICE_PASSED+=("$name")
  elif [[ $ec -eq "$RICE_STEP_SKIP" ]]; then
    RICE_SKIPPED+=("$name")
  else
    RICE_FAILED+=("$name")
    echo "[!] Step failed: $name (exit $ec)" >&2
  fi
}

print_rice_summary() {
  echo ""
  echo "========== Rice summary =========="
  if ((${#RICE_PASSED[@]} > 0)); then
    echo "OK (${#RICE_PASSED[@]}):"
    printf '  • %s\n' "${RICE_PASSED[@]}"
  fi
  if ((${#RICE_SKIPPED[@]} > 0)); then
    echo "Skipped (${#RICE_SKIPPED[@]}):"
    printf '  • %s\n' "${RICE_SKIPPED[@]}"
  fi
  if ((${#RICE_FAILED[@]} > 0)); then
    echo "Failed (${#RICE_FAILED[@]}):"
    printf '  • %s\n' "${RICE_FAILED[@]}"
    echo ""
    echo "Fix the failed steps (or run this script again; idempotent steps will no-op), then re-run if needed."
    return 1
  fi
  echo ""
  echo "All runnable steps succeeded. Launch with: exec zsh"
  echo "Set terminal font to: FiraCode Nerd Font"
}

# ------------------------- Main -------------------------
main() {
  RICE_PASSED=()
  RICE_SKIPPED=()
  RICE_FAILED=()

  run_step "Core packages (dnf)" install_core_packages
  run_step "RPM Fusion" install_rpmfusion
  run_step "Intel microcode + iGPU" install_intel_microcode_and_igpu
  run_step "Brave Browser" install_brave
  run_step "Cursor" install_cursor
  run_step "Claude Code CLI" install_claude_cli
  run_step "Spotify" install_spotify
  run_step "Easy Effects" install_easyeffects
  run_step "Easy Effects thinkpad-unsuck preset" install_easyeffects_thinkpad_preset
  run_step "zoxide" install_zoxide
  run_step "LazyGit" install_lazygit
  run_step "kubectl" install_kubectl
  run_step "kubecolor" install_kubecolor
  run_step "kubectx / kubens" install_kubectx_kubens
  run_step "k9s" install_k9s
  run_step "Docker" install_docker
  run_step "AWS CLI" install_aws_cli
  run_step "FiraCode Nerd Font" install_fonts
  run_step "Oh My Zsh + plugins" install_ohmyzsh_and_plugins
  run_step "Write ~/.zshrc" write_zshrc

  print_rice_summary
}

main "$@"
