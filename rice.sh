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
    KUBECOLOR_LATEST=$(curl -s https://api.github.com/repos/hidetatz/kubecolor/releases/latest | grep browser_download_url | grep linux_amd64 | cut -d '"' -f 4)
    curl -Lo kubecolor "$KUBECOLOR_LATEST"
    chmod +x kubecolor
    sudo mv kubecolor /usr/local/bin/
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
# ... same .zshrc content from earlier ...
EOF
}

# ------------------------- Main -------------------------
install_core_packages
install_zoxide
install_lazygit
install_kubectl
install_kubecolor
install_kubectx_kubens
install_aws_cli
install_fonts
install_ohmyzsh_and_plugins
write_zshrc

echo -e "\n✅ All done! Launch with: exec zsh"
echo "🎨 Set terminal font to: FiraCode Nerd Font"
