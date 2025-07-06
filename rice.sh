#!/usr/bin/env bash
set -euo pipefail

# ------------------------- Functions -------------------------
install_core_packages() {
  echo "[*] Installing base packages..."
  sudo apt update
  sudo apt install -y \
    curl wget git unzip build-essential zsh \
    neovim ripgrep jq pwgen fd-find \
    bat tmux unzip xclip locales fontconfig fzf

  mkdir -p ~/.local/bin
  export PATH="$HOME/.local/bin:$PATH"

  ln -sf "$(which fdfind)" ~/.local/bin/fd || true
  ln -sf "$(which batcat)" ~/.local/bin/bat || true
  sudo locale-gen en_US.UTF-8
  export LANG=en_US.UTF-8
}

install_zoxide() {
  if ! command -v zoxide &>/dev/null; then
    echo "[*] Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  else
    echo "[✓] zoxide already installed."
  fi
}

install_lazygit() {
  if ! command -v lazygit &>/dev/null; then
    echo "[*] Installing LazyGit..."
    VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep tag_name | cut -d '"' -f 4)
    curl -Lo lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/${VERSION}/lazygit_${VERSION#v}_Linux_x86_64.tar.gz"
    tar xf lazygit.tar.gz lazygit && sudo install lazygit /usr/local/bin
    rm -f lazygit lazygit.tar.gz
  else
    echo "[✓] lazygit already installed."
  fi
}

install_kubectl() {
  if ! command -v kubectl &>/dev/null; then
    echo "[*] Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
  else
    echo "[✓] kubectl already installed."
  fi
}


install_kubecolor() {
  if ! command -v kubecolor &>/dev/null; then
    echo "[*] Installing kubecolor..."
    KUBECOLOR_LATEST=$(curl -s https://api.github.com/repos/kubecolor/kubecolor/releases/latest | grep browser_download_url | grep linux_amd64.tar.gz | cut -d '"' -f 4)
    curl -Lo kubecolor.tar.gz "$KUBECOLOR_LATEST"
    tar -xzf kubecolor.tar.gz kubecolor
    chmod +x kubecolor
    sudo mv kubecolor /usr/local/bin/
    rm kubecolor.tar.gz
  else
    echo "[✓] kubecolor already installed."
  fi
}


install_kubectx_kubens() {
  if ! command -v kubectx &>/dev/null; then
    echo "[*] Installing kubectx and kubens..."
    git clone https://github.com/ahmetb/kubectx ~/.kubectx || true
    sudo ln -sf ~/.kubectx/kubectx /usr/local/bin/kubectx
    sudo ln -sf ~/.kubectx/kubens /usr/local/bin/kubens
  else
    echo "[✓] kubectx and kubens already installed."
  fi
}

install_k9s() {
  if ! command -v k9s &>/dev/null; then
    echo "[*] Installing k9s..."
    K9S_LATEST=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest \
      | grep browser_download_url \
      | grep 'k9s_Linux_amd64\.tar\.gz"' \
      | cut -d '"' -f 4 | head -n1)

    curl -Lo k9s.tar.gz "$K9S_LATEST"
    tar -xzf k9s.tar.gz k9s
    chmod +x k9s
    sudo mv k9s /usr/local/bin/
    rm k9s.tar.gz
    echo "[✓] k9s installed."
  else
    echo "[✓] k9s already installed."
  fi
}


install_aws_cli() {
  if ! command -v aws &>/dev/null; then
    echo "[*] Installing AWS CLI..."
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
  else
    echo "[✓] AWS CLI already installed."
  fi
}

install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "[*] Installing Docker..."
    # official convenience script (latest stable CLI + Engine)
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh                          # installs & enables the service
    rm get-docker.sh

    # add current user to the docker group (so you can run without sudo)
    sudo usermod -aG docker "$USER"
    echo "[i] Added $USER to the docker group. Log out & back in (or run: newgrp docker)."
    echo "[✓] Docker installed ($(/usr/bin/docker --version))."
  else
    echo "[✓] Docker already installed."
  fi
}

install_docker_compose() {
  if ! command -v docker-compose &>/dev/null; then
    echo "[*] Installing Docker Compose..."
    COMPOSE_URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
      | grep browser_download_url \
      | grep "docker-compose-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)\"" \
      | cut -d '"' -f 4 | head -n1)

    sudo curl -L "$COMPOSE_URL" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "[✓] Docker Compose installed ($(/usr/local/bin/docker-compose --version))."
  else
    echo "[✓] Docker Compose already installed."
  fi
}

install_fonts() {
  echo "[*] Installing FiraCode Nerd Font..."
  git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git ~/nerd-fonts
  ~/nerd-fonts/install.sh FiraCode
  rm -rf ~/nerd-fonts
  fc-cache -fv
}

install_ohmyzsh_and_plugins() {
  export ZSH="$HOME/.oh-my-zsh"
  if [ ! -d "$ZSH" ]; then
    echo "[*] Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi

  ZSH_CUSTOM="$ZSH/custom"
  git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" || true
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" || true
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM}/themes/powerlevel10k" || true
  git clone https://github.com/jonmosco/kube-ps1.git ~/.kube-ps1 || true
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
alias proxmox="wakeonlan d8:5e:d3:d9:ed:b7"
alias new-server="curl -sS https://gist.githubusercontent.com/zAbuQasem/cbdc151a15277a96117b34b6c56934d9/raw/0b3cf9203c3842c670bf8a5be3f99deae949b454/terminal.sh |c"
alias mount-backup='sudo mount -t nfs -o resvport 192.168.1.20:/mnt/backup ~/mnt/backup'
alias myip='curl https://icanhazip.com'
alias kx='kubectx'
alias kn='kubens'
alias p='pwgen -s 15'
alias projects='cd ~/Documents/projects/'
source <(fzf --zsh)

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
[ -s "$HOME/.config/envman/load.sh" ] && source "$HOME/.config/envman/load.sh"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
EOF
}

# ------------------------- Main -------------------------
install_core_packages
install_zoxide
install_lazygit
install_kubectl
install_kubecolor
install_kubectx_kubens
install_k9s
install_docker
install_docker_compose
install_aws_cli
install_fonts
install_ohmyzsh_and_plugins
write_zshrc

echo -e "\n✅ All done! Launch with: exec zsh"
echo "🎨 Set terminal font to: FiraCode Nerd Font"

