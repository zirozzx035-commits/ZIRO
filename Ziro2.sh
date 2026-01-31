cat > setup_android_monogame_codespaces.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIG (ajuste se quiser) =====
: "${DOTNET_CHANNEL:=10.0}"          # "10.0" (atual estável) | "LTS" | "STS"
: "${ANDROID_API_REQUIRED:=31}"      # exigido pelo MonoGame (SDK 31)
: "${INSTALL_NDK:=0}"                # 1 para instalar NDK também (opcional)
: "${MONOGAME_PREVIEW:=0}"           # 1 para instalar templates prerelease (não recomendado para port em produção)

# ===== HELPERS =====
log() { echo -e "\n[setup] $*\n"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

append_bashrc_once() {
  local line="$1"
  local file="$HOME/.bashrc"
  grep -Fqs "$line" "$file" || echo "$line" >> "$file"
}

# ===== 1) APT BASE + JAVA 11 =====
log "Atualizando apt e instalando dependências base + OpenJDK 11..."
sudo apt-get update -y
sudo apt-get install -y \
  git curl wget unzip zip ca-certificates \
  openjdk-11-jdk \
  python3 \
  libc6 libstdc++6 libgcc-s1 \
  build-essential cmake ninja-build pkg-config

log "Java instalado:"
java -version || true

# ===== 2) ANDROID SDK (cmdline-tools + sdkmanager) =====
export ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
  log "Baixando Android SDK Command-line Tools (latest) e instalando em $ANDROID_SDK_ROOT..."
  cd /tmp
  wget -q -O cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-latest.zip"
  unzip -q cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
else
  log "Android cmdline-tools já existe: $ANDROID_SDK_ROOT/cmdline-tools/latest"
fi

export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

log "Aceitando licenças do Android SDK..."
yes | sdkmanager --licenses >/dev/null

log "Atualizando/instalando packages obrigatórios (platform-tools, API ${ANDROID_API_REQUIRED}, build-tools) ..."
# Descobrir automaticamente o MAIOR build-tools e MAIOR platform API disponíveis, para ficar "mais atualizado".
SDK_LIST="$(sdkmanager --list || true)"

latest_build_tools="$(
  echo "$SDK_LIST" \
  | grep -oE 'build-tools;[0-9]+\.[0-9]+\.[0-9]+' \
  | sed 's/build-tools;//' \
  | sort -V \
  | tail -n 1
)"

latest_platform_api="$(
  echo "$SDK_LIST" \
  | grep -oE 'platforms;android-[0-9]+' \
  | sed 's/platforms;android-//' \
  | sort -V \
  | tail -n 1
)"

# fallback se parsing falhar
latest_build_tools="${latest_build_tools:-31.0.0}"
latest_platform_api="${latest_platform_api:-$ANDROID_API_REQUIRED}"

log "Detectado latest build-tools: ${latest_build_tools}"
log "Detectado latest platform API: ${latest_platform_api}"

# Sempre instalar o REQUIRED (31) + o latest detectado
sdkmanager \
  "platform-tools" \
  "platforms;android-${ANDROID_API_REQUIRED}" \
  "build-tools;31.0.0" \
  "build-tools;${latest_build_tools}" \
  "platforms;android-${latest_platform_api}"

if [ "$INSTALL_NDK" = "1" ]; then
  log "INSTALL_NDK=1: Instalando NDK (maior versão disponível detectada)..."
  ndk_latest="$(
    echo "$SDK_LIST" \
    | grep -oE 'ndk;[0-9]+\.[0-9]+\.[0-9]+' \
    | sed 's/ndk;//' \
    | sort -V \
    | tail -n 1
  )"
  if [ -n "${ndk_latest:-}" ]; then
    sdkmanager "ndk;${ndk_latest}"
  else
    log "Não consegui detectar NDK automaticamente via sdkmanager --list; pulando."
  fi
fi

log "Android SDK pronto em: $ANDROID_SDK_ROOT"
adb version || true

# ===== 3) .NET (última do canal escolhido) + WORKLOAD ANDROID =====
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"

if ! need_cmd dotnet; then
  log "Instalando .NET SDK (canal ${DOTNET_CHANNEL}) via dotnet-install.sh..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir "$DOTNET_ROOT"
else
  log "dotnet já existe; mantendo e atualizando workloads."
fi

log "dotnet versão:"
dotnet --version

log "Atualizando workloads e instalando workload android..."
dotnet workload update
dotnet workload install android
dotnet workload list || true

# ===== 4) MONOGAME TEMPLATES =====
log "Instalando templates do MonoGame (latest stable por padrão)..."
if [ "$MONOGAME_PREVIEW" = "1" ]; then
  log "MONOGAME_PREVIEW=1: instalando templates prerelease (atenção: maior risco)."
  # Para prerelease, você normalmente precisa informar uma versão específica;
  # aqui instalamos o pacote sem fixar versão (pode ficar stable). Se quiser fixar,
  # ajuste manualmente para MonoGame.Templates.CSharp::<versão preview>.
  dotnet new install MonoGame.Templates.CSharp || true
else
  dotnet new install MonoGame.Templates.CSharp
fi

log "Listando templates MonoGame instalados:"
dotnet new list | grep -i monogame || true

# ===== 5) TOOLS DO CONTENT PIPELINE (MGCB/MGFXC + EDITOR) =====
log "Instalando ferramentas do Content Pipeline (MGCB e MGFXC) como dotnet tools globais..."
# MGCB / MGFXC são recomendados para compilar conteúdo/shaders via CLI.
dotnet tool install -g dotnet-mgcb    || dotnet tool update -g dotnet-mgcb
dotnet tool install -g dotnet-mgfxc   || dotnet tool update -g dotnet-mgfxc

# MGCB Editor (Linux). Em Codespaces (sem GUI), o editor pode não ser usado, mas instalamos mesmo.
dotnet tool install -g dotnet-mgcb-editor-linux || dotnet tool update -g dotnet-mgcb-editor-linux

# Garantir PATH do dotnet tools
export PATH="$HOME/.dotnet/tools:$PATH"

log "Versões de ferramentas (se disponíveis):"
mgcb /version 2>/dev/null || true
mgfxc /version 2>/dev/null || true

# ===== 6) PERSISTIR ENV NO .bashrc =====
log "Persistindo variáveis de ambiente no ~/.bashrc..."
append_bashrc_once 'export ANDROID_SDK_ROOT="$HOME/android-sdk"'
append_bashrc_once 'export ANDROID_HOME="$ANDROID_SDK_ROOT"'
append_bashrc_once 'export DOTNET_ROOT="$HOME/.dotnet"'
append_bashrc_once 'export PATH="$DOTNET_ROOT:$HOME/.dotnet/tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"'

log "Concluído. Recomendo rodar: source ~/.bashrc"
echo
echo "CHECKLIST:"
echo "  dotnet --version"
echo "  dotnet workload list"
echo "  java -version"
echo "  sdkmanager --list | head"
echo "  adb version"
echo "  dotnet new list | grep -i monogame"
EOF

bash setup_android_monogame_codespaces.sh
