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

# ------------------------- Functions -------------------------
install_core_packages() {
  echo "[*] Installing base packages (Fedora/dnf)..."
  sudo dnf install -y dnf-plugins-core
  sudo dnf install -y \
    curl wget git unzip zsh \
    neovim ripgrep fd-find bat \
    jq pwgen tmux xclip fontconfig fzf \
    @development-tools \
    glibc-langpack-en

  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  # Fedora: fd-find provides fdfind; create fd symlink for compatibility
  if command -v fdfind &>/dev/null && [ ! -e ~/.local/bin/fd ]; then
    ln -sf "$(which fdfind)" ~/.local/bin/fd
  fi
  # Fedora: bat is just 'bat', no batcat

  export LANG=en_US.UTF-8
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
  if ! command -v kubectx &>/dev/null; then
    echo "[*] Installing kubectx and kubens..."
    [ -d ~/.kubectx ] || git clone --depth 1 https://github.com/ahmetb/kubectx ~/.kubectx
    sudo ln -sf ~/.kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -sf ~/.kubectx/kubens /usr/local/bin/kubens
    echo "[✓] kubectx/kubens installed."
  else
    echo "[✓] kubectx and kubens already installed."
  fi
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
  echo "[*] Installing FiraCode Nerd Font..."
  [ -d ~/nerd-fonts ] || git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ~/nerd-fonts
  ~/nerd-fonts/install.sh FiraCode
  rm -rf ~/nerd-fonts
  fc-cache -fv
  echo "[✓] FiraCode Nerd Font installed."
}

install_ohmyzsh_and_plugins() {
  export ZSH="$HOME/.oh-my-zsh"
  if [ ! -d "$ZSH" ]; then
    echo "[*] Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  ZSH_CUSTOM="$ZSH/custom"
  [ -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ] || git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  [ -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ] || git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  [ -d "${ZSH_CUSTOM}/themes/powerlevel10k" ] || git clone --depth 1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k"
  [ -d ~/.kube-ps1 ] || git clone --depth 1 https://github.com/jonmosco/kube-ps1.git ~/.kube-ps1
}

write_zshrc() {
  echo "[*] Writing .zshrc..."
  cat > ~/.zshrc << 'EOF'
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
alias mount-personal='sudo mount -t nfs -o resvport 192.168.1.20:/mnt/Personal ~/Personal'
source <(fzf --zsh)
eval "$(zoxide init zsh)"

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
EOF
}

# ------------------------- Main -------------------------
main() {
  install_core_packages
  install_zoxide
  install_lazygit
  install_kubectl
  install_kubecolor
  install_kubectx_kubens
  install_k9s
  install_docker
  install_aws_cli
  install_fonts
  install_ohmyzsh_and_plugins
  write_zshrc

  echo ""
  echo "✅ All done! Launch with: exec zsh"
  echo "🎨 Set terminal font to: FiraCode Nerd Font"
}

main "$@"
