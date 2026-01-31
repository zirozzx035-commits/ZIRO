cat > setup_monogame_complete.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ===== CONFIGURAÇÕES =====
# MonoGame 3.8.1+ e .NET 8 Android exigem:
# - Java 17
# - Build Tools 34.0.0 (ou 33)
# - API Level 34 (Android 14)
: "${DOTNET_CHANNEL:=8.0}"           # Use 8.0 (LTS) ou 9.0 (Standard)
: "${ANDROID_COMPILE_SDK:=34}"       # API level para compilação
: "${ANDROID_MIN_SDK:=21}"           # API minima suportada
: "${INSTALL_NDK:=0}"                # 1 para instalar NDK (geralmente não precisa para pure C#)

# ===== HELPERS =====
log() { echo -e "\n\033[1;32m[SETUP] $*\033[0m\n"; }

append_env() {
  local line="$1"
  local file="$HOME/.bashrc"
  grep -Fqs "$line" "$file" || echo "$line" >> "$file"
}

# ===== 1) DEPENDÊNCIAS DO SO (APT) =====
log "Instalando dependências do sistema (Wine, Java 17, Fontes, Utils)..."
sudo apt-get update -y
sudo apt-get install -y \
  git curl wget unzip zip ca-certificates \
  openjdk-17-jdk \
  python3 \
  build-essential cmake \
  fontconfig libfreetype6 \
  wine64 wine \
  libgtk-3-0

# Verificações básicas
log "Versão do Java (Deve ser 17+):"
java -version 2>&1 | head -n 2

log "Verificando Wine (Necessário para compilar Shaders/Effects):"
wine --version || echo "Aviso: Wine pode não ter instalado corretamente, verifique logs."

# ===== 2) ANDROID SDK =====
export ANDROID_SDK_ROOT="$HOME/android-sdk"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

if [ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]; then
  log "Baixando Android Command-line Tools..."
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  cd /tmp
  # URL hardcoded para versão estável conhecida (commandlinetools-linux-11076708_latest.zip)
  wget -q -O cmdline-tools.zip "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
  unzip -q cmdline-tools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
else
  log "Android SDK já presente."
fi

log "Aceitando licenças..."
yes | sdkmanager --licenses >/dev/null 2>&1 || true

log "Instalando Platform-Tools e Build-Tools (API ${ANDROID_COMPILE_SDK})..."
# Instalamos explicitamente a versão 34.0.0 (padrão .NET 8) para evitar betas instáveis
sdkmanager \
  "platform-tools" \
  "platforms;android-${ANDROID_COMPILE_SDK}" \
  "build-tools;34.0.0" \
  "build-tools;33.0.1"

if [ "$INSTALL_NDK" = "1" ]; then
  log "Instalando NDK (LTS)..."
  sdkmanager "ndk;26.1.10909125"
fi

# ===== 3) .NET SDK + WORKLOADS =====
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

if ! command -v dotnet >/dev/null 2>&1; then
  log "Instalando .NET ${DOTNET_CHANNEL}..."
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh
  /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir "$DOTNET_ROOT"
else
  log ".NET já instalado. Versão: $(dotnet --version)"
fi

log "Instalando Workload Android..."
# --ignore-failed-sources ajuda se houver feeds nuget privados configurados errados
dotnet workload install android --ignore-failed-sources

# ===== 4) MONOGAME =====
log "Instalando Templates e Ferramentas MonoGame..."
dotnet new install MonoGame.Templates.CSharp || true

# Ferramentas globais (MGCB)
log "Instalando MGCB Editor e compilador..."
dotnet tool install --global dotnet-mgcb || dotnet tool update --global dotnet-mgcb
dotnet tool install --global dotnet-mgcb-editor-linux || dotnet tool update --global dotnet-mgcb-editor-linux

# Registra o daemon do MGCB se necessário (opcional no Linux headless, mas bom ter)
# mgcb-editor --register || true 

# ===== 5) CONFIGURAR AMBIENTE FINAL =====
log "Configurando .bashrc..."
append_env 'export ANDROID_SDK_ROOT="$HOME/android-sdk"'
append_env 'export ANDROID_HOME="$ANDROID_SDK_ROOT"'
append_env 'export DOTNET_ROOT="$HOME/.dotnet"'
append_env 'export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"'
# Variável para corrigir problema de renderização de fontes no Java em alguns Linux
append_env 'export _JAVA_OPTIONS="-Djava.awt.headless=true"'

log "SETUP CONCLUÍDO COM SUCESSO!"
echo "----------------------------------------------------"
echo "Para aplicar as mudanças no terminal atual, execute:"
echo "source ~/.bashrc"
echo "----------------------------------------------------"
EOF

# Executa o script
bash setup_monogame_complete.sh
