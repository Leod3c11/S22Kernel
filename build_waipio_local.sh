#!/bin/bash
#
# Script de build local para o kernel Waipio (Samsung S22)
# Baseado no build.config.msm.waipio
#

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções de log
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Variáveis padrão
VARIANT="${VARIANT:-consolidate}"
MSM_ARCH="waipio"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
JOBS="${JOBS:-$(nproc --all 2>/dev/null || echo 4)}"

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_DIR="${SCRIPT_DIR}/kernel_platform/msm-kernel"
COMMON_DIR="${SCRIPT_DIR}/kernel_platform/common"
OUT_DIR="${SCRIPT_DIR}/out/msm-${MSM_ARCH}-${VARIANT}"
BUILD_CONFIG="${KERNEL_DIR}/build.config.msm.waipio"

# Clang
CLANG_VERSION="clang-r416183b"
CLANG_DIR="${SCRIPT_DIR}/kernel_platform/prebuilts-master/clang/host/linux-x86/${CLANG_VERSION}"
CLANG_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/android12L-gsi/${CLANG_VERSION}.tar.gz"

#===============================================================================
# FUNÇÕES
#===============================================================================

show_help() {
    cat << EOF
Uso: $0 [OPÇÕES]

Script de build para o kernel Waipio (Samsung S22)

OPÇÕES:
    -v, --variant VARIANTE    Variante de build: consolidate ou gki (padrão: consolidate)
    -c, --clean               Fazer build limpo (mrproper)
    -j, --jobs N              Número de jobs paralelos (padrão: número de CPUs)
    -d, --download-clang      Baixar toolchain Clang automaticamente
    -h, --help                Mostrar esta ajuda

VARIÁVEIS DE AMBIENTE:
    VARIANT                   Variante de build (consolidate/gki)
    CLEAN_BUILD               1 para build limpo, 0 para incremental
    JOBS                      Número de jobs paralelos
    SKIP_MRPROPER             1 para pular mrproper, 0 para executar

EXEMPLOS:
    $0                        # Build consolidate padrão
    $0 -v gki                 # Build GKI
    $0 -c -v consolidate      # Build limpo consolidate
    $0 -j 8                   # Build com 8 jobs paralelos

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--variant)
                VARIANT="$2"
                shift 2
                ;;
            -c|--clean)
                CLEAN_BUILD=1
                shift
                ;;
            -j|--jobs)
                JOBS="$2"
                shift 2
                ;;
            -d|--download-clang)
                DOWNLOAD_CLANG=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Opção desconhecida: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check_dependencies() {
    log_info "Verificando dependências..."

    local deps=("bc" "bison" "flex" "make" "python3" "dtc")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Dependências faltando: ${missing[*]}"
        log_info "Instale com: sudo apt-get install bc bison flex build-essential python3 device-tree-compiler"
        exit 1
    fi

    log_success "Todas as dependências estão instaladas"
}

download_clang() {
    if [ -f "${CLANG_DIR}/bin/clang" ]; then
        log_info "Clang já instalado em ${CLANG_DIR}"
        return 0
    fi

    log_info "Baixando Clang ${CLANG_VERSION}..."

    mkdir -p "$(dirname "$CLANG_DIR")"
    cd "$(dirname "$CLANG_DIR")"

    local clang_tar="${CLANG_VERSION}.tar.gz"

    if ! wget -q --show-progress --timeout=300 "$CLANG_URL" -O "$clang_tar"; then
        log_error "Falha ao baixar Clang"
        return 1
    fi

    log_info "Extraindo Clang..."
    mkdir -p "$CLANG_VERSION"
    if ! tar -C "$CLANG_VERSION" -xzf "$clang_tar"; then
        log_error "Falha ao extrair Clang"
        return 1
    fi
    rm -f "$clang_tar"

    cd - > /dev/null
    log_success "Clang instalado em ${CLANG_DIR}"
}

setup_environment() {
    log_info "Configurando ambiente de build..."

    # Verificar se o diretório do kernel existe
    if [ ! -d "$KERNEL_DIR" ]; then
        log_error "Diretório do kernel não encontrado: $KERNEL_DIR"
        exit 1
    fi

    # Verificar se o build.config existe
    if [ ! -f "$BUILD_CONFIG" ]; then
        log_error "Arquivo de configuração não encontrado: $BUILD_CONFIG"
        exit 1
    fi

    # Verificar/baixar Clang
    if [ ! -f "${CLANG_DIR}/bin/clang" ]; then
        if [ "$DOWNLOAD_CLANG" == "1" ]; then
            download_clang
        else
            log_warn "Clang não encontrado em ${CLANG_DIR}"
            log_info "Use -d para baixar automaticamente ou defina CLANG_DIR"
            exit 1
        fi
    fi

    # Configurar variáveis de ambiente
    export MAKEFLAGS="-j${JOBS}"
    export HERMETIC_TOOLCHAIN=0
    export LLVM=1
    export LLVM_IAS=1
    export LD=ld.lld

    export PATH="${CLANG_DIR}/bin:/usr/lib/ccache:${PATH}"

    export CC="${CLANG_DIR}/bin/clang"
    export CXX="${CLANG_DIR}/bin/clang++"
    export AR="${CLANG_DIR}/bin/llvm-ar"
    export NM="${CLANG_DIR}/bin/llvm-nm"
    export STRIP="${CLANG_DIR}/bin/llvm-strip"
    export OBJCOPY="${CLANG_DIR}/bin/llvm-objcopy"
    export OBJDUMP="${CLANG_DIR}/bin/llvm-objdump"
    export READELF="${CLANG_DIR}/bin/llvm-readelf"
    export HOSTCC="${CLANG_DIR}/bin/clang"
    export HOSTCXX="${CLANG_DIR}/bin/clang++"

    # Configurações do waipio
    export VARIANT="$VARIANT"
    export MSM_ARCH="$MSM_ARCH"
    export BUILD_VENDOR_DLKM=1
    export DT_OVERLAY_SUPPORT=1
    export TRIM_UNUSED_MODULES=1
    export MODULES_LIST_ORDER=1

    # Configurar mrproper
    if [ "$CLEAN_BUILD" == "1" ]; then
        export SKIP_MRPROPER=0
        log_info "Build limpo ativado (mrproper será executado)"
    else
        export SKIP_MRPROPER=1
        log_info "Build incremental (mrproper será pulado)"
    fi

    # Criar diretório de saída
    mkdir -p "$OUT_DIR"

    log_success "Ambiente configurado"
    log_info "VARIANT: $VARIANT"
    log_info "JOBS: $JOBS"
    log_info "OUT_DIR: $OUT_DIR"
}

fix_defconfigs() {
    log_info "Corrigindo defconfigs..."

    local config_dir="${KERNEL_DIR}/arch/arm64/configs/vendor"

    if [ ! -d "$config_dir" ]; then
        log_warn "Diretório de configs não encontrado: $config_dir"
        return 0
    fi

    cd "$config_dir"

    # Criar symlinks para defconfigs waipio
    for defconfig in waipio_sec_defconfig waipio_gki_defconfig; do
        if [ -f "$defconfig" ]; then
            local double_underscore="${defconfig/_defconfig/__defconfig}"
            if [ ! -f "$double_underscore" ]; then
                ln -sf "$defconfig" "$double_underscore"
                log_success "Symlink criado: $double_underscore -> $defconfig"
            fi
        fi
    done

    cd - > /dev/null
}

build_kernel() {
    log_info "Iniciando build do kernel Waipio (${VARIANT})..."
    log_info "========================================"

    cd "$SCRIPT_DIR"

    # Configurar ambiente para o build
    export ROOT_DIR="${SCRIPT_DIR}/kernel_platform"
    export KERNEL_DIR="msm-kernel"
    export COMMON_OUT_DIR="$OUT_DIR"

    # Executar build
    local start_time=$(date +%s)

    if ! bash -c "
        export VARIANT=$VARIANT
        export BUILD_CONFIG=$BUILD_CONFIG
        source $BUILD_CONFIG
        make_defconfig
        make_kernel
    " 2>&1 | tee "${OUT_DIR}/build.log"; then

        log_error "Build falhou!"
        log_info "Verifique o log em: ${OUT_DIR}/build.log"
        exit 1
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    log_success "Build concluído em ${minutes}m ${seconds}s"
}

package_output() {
    log_info "Empacotando saída do build..."

    local release_dir="${SCRIPT_DIR}/release/waipio-${VARIANT}"
    mkdir -p "$release_dir"

    # Copiar imagens do kernel
    find "$OUT_DIR" -type f \( \
        -name "Image" -o -name "Image.gz" -o \
        -name "*.img" -o -name "*.dtb" -o \
        -name "*.dtbo" \
    \) 2>/dev/null | while read f; do
        cp "$f" "$release_dir/" 2>/dev/null && \
            log_success "Copiado: $(basename "$f")"
    done

    # Copiar módulos
    local modules_dir="$release_dir/modules"
    mkdir -p "$modules_dir"

    find "$OUT_DIR" -name "*.ko" 2>/dev/null | while read f; do
        cp "$f" "$modules_dir/" 2>/dev/null
    done

    local module_count=$(find "$modules_dir" -name "*.ko" 2>/dev/null | wc -l)
    log_success "Módulos copiados: $module_count"

    # Criar info do build
    cat > "$release_dir/build_info.txt" << EOF
Waipio Kernel Build Info
========================
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Variant: ${VARIANT}
MSM_ARCH: ${MSM_ARCH}
Clang Version: ${CLANG_VERSION}
Git Commit: $(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
Git Branch: $(git branch --show-current 2>/dev/null || echo "N/A")
EOF

    # Compactar
    local release_tar="${SCRIPT_DIR}/release/waipio-${VARIANT}-$(date +%Y%m%d-%H%M%S).tar.gz"
    cd "${SCRIPT_DIR}/release"
    tar -czf "$release_tar" "waipio-${VARIANT}"

    log_success "Pacote criado: $release_tar"
    ls -lh "$release_tar"
}

show_summary() {
    echo ""
    log_info "========================================"
    log_info "RESUMO DO BUILD"
    log_info "========================================"
    log_info "Variante: $VARIANT"
    log_info "Diretório de saída: $OUT_DIR"
    log_info ""
    log_info "Arquivos gerados:"

    if [ -d "$OUT_DIR" ]; then
        find "$OUT_DIR" -type f \( -name "Image*" -o -name "*.img" -o -name "*.dtb" \) 2>/dev/null | \
            while read f; do
                echo "  - $(basename "$f") ($(stat -c%s "$f" 2>/dev/null | numfmt --to=iec-i))"
            done

        local ko_count=$(find "$OUT_DIR" -name "*.ko" 2>/dev/null | wc -l)
        log_info "Módulos: $ko_count"
    fi

    log_info "========================================"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo "========================================"
    echo "  Waipio Kernel Build Script"
    echo "  Samsung S22 (SM-S901B)"
    echo "========================================"
    echo ""

    parse_args "$@"

    log_info "Variante: $VARIANT"
    log_info "Jobs: $JOBS"

    check_dependencies
    setup_environment
    fix_defconfigs
    build_kernel
    package_output
    show_summary

    log_success "Build completo!"
}

# Executar main
main "$@"
