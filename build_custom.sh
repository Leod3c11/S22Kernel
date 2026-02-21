#!/bin/bash
set -e

# ==============================================================================
# Script de Compilação Customizado (Não-GKI) para S22 (Waipio)
# Este script ignora o fluxo GKI padrão e foca na configuração da Samsung.
# ==============================================================================

# 1. Configurações de Ambiente
export ROOT_DIR=$(pwd)
export KERNEL_DIR=$ROOT_DIR/kernel_platform/msm-kernel
export OUT_DIR=$ROOT_DIR/out
export ARCH=arm64
export SUBARCH=arm64

# Usa toolchain GNU disponível no Ubuntu (apt) em vez do Android NDK
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-
export LD=ld.lld

# 2. Definir Alvos
DEFCONFIG_BASE="vendor/waipio_sec_defconfig"

# 3. Instalar toolchain de cross-compile
echo "--- Instalando toolchain ---"
sudo apt-get install -y gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi

echo "--- Iniciando compilação Não-GKI ---"
echo "Base Defconfig: $DEFCONFIG_BASE"

# 4. Limpeza (Opcional)
# make -C $KERNEL_DIR O=$OUT_DIR clean

# 5. Criar diretório de saída e gerar .config
mkdir -p $OUT_DIR

echo "Gerando configuração..."
make -C $KERNEL_DIR O=$OUT_DIR \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CC=clang \
    LD=ld.lld \
    $DEFCONFIG_BASE

# 6. Personalização (descomente e ajuste conforme necessário)
# scripts/config --file $OUT_DIR/.config --enable CONFIG_LOCALVERSION_AUTO
# scripts/config --file $OUT_DIR/.config --set-str CONFIG_LOCALVERSION "-Custom-NonGKI"

# 7. Compilar
CPU_CORES=$(nproc)
echo "Compilando com $CPU_CORES núcleos..."

make -C $KERNEL_DIR O=$OUT_DIR -j$CPU_CORES \
    ARCH=arm64 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    LLVM=1 \
    LLVM_IAS=1

# 8. Finalização
if [ -f $OUT_DIR/arch/arm64/boot/Image ]; then
    echo "--- Compilação concluída com sucesso! ---"
    echo "Kernel Image: $OUT_DIR/arch/arm64/boot/Image"
    echo "DTBO: $OUT_DIR/arch/arm64/boot/dts/vendor/qcom/*.dtbo"
else
    echo "--- Erro na compilação! Verifique os logs acima. ---"
    exit 1
fi