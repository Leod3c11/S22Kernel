#!/bin/bash

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
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-

# 2. Definir Alvos
# Para o S22 (Waipio), usamos o sec_defconfig da Samsung como base.
# Variantes comuns: waipio_sec_defconfig, waipio_sec_userdebug_defconfig
DEFCONFIG_BASE="vendor/waipio_sec_defconfig"

# 3. Preparar ferramentas de build (Clang/GCC)
# O repositório já possui pré-built em kernel_platform/prebuilts (ajuste se necessário)
# Se estiver usando o ambiente padrão do Android:
# export PATH=$ROOT_DIR/kernel_platform/prebuilts/clang/host/linux-x86/clang-r416183b/bin:$PATH

echo "--- Iniciando compilação Não-GKI ---"
echo "Base Defconfig: $DEFCONFIG_BASE"

# 4. Limpeza (Opcional)
# make -C $KERNEL_DIR O=$OUT_DIR clean

# 5. Gerar .config
echo "Gerando configuração..."
make -C $KERNEL_DIR O=$OUT_DIR $DEFCONFIG_BASE

# 6. Personalização (Aqui você pode adicionar seus fragmentos)
# Exemplo: desabilitar verificação de assinatura de módulos ou habilitar overclock
# scripts/config --file $OUT_DIR/.config --enable CONFIG_LOCALVERSION_AUTO
# scripts/config --file $OUT_DIR/.config --set-str CONFIG_LOCALVERSION "-Custom-NonGKI"

# 7. Compilar
CPU_CORES=$(nproc)
echo "Compilando com $CPU_CORES núcleos..."

make -C $KERNEL_DIR O=$OUT_DIR -j$CPU_CORES \
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
