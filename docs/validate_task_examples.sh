#!/bin/bash
# =============================================================================
# CangjieLua 任务示例验证脚本
#
# 本脚本验证 docs/task_examples/ 目录中的所有示例代码能在标准仓颉编译器上
# 正确编译和运行。
#
# 用法:
#   1. 确保已设置仓颉 SDK 环境：source cangjie/envsetup.sh
#   2. 运行本脚本：bash docs/validate_task_examples.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$SCRIPT_DIR/task_examples"
TEMP_DIR=$(mktemp -d)

PASS=0
FAIL=0
TOTAL=0

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "============================================"
echo "任务示例标准仓颉编译器验证"
echo "============================================"
echo ""

for cj_file in "$EXAMPLES_DIR"/task_*.cj; do
    name=$(basename "$cj_file" .cj)
    TOTAL=$((TOTAL + 1))
    out_file="$TEMP_DIR/$name"

    if cjc "$cj_file" -o "$out_file" > "$TEMP_DIR/${name}_compile.log" 2>&1; then
        if "$out_file" > "$TEMP_DIR/${name}_run.log" 2>&1; then
            PASS=$((PASS + 1))
            echo "  [PASS] $name"
        else
            FAIL=$((FAIL + 1))
            echo "  [FAIL] $name (运行失败)"
            cat "$TEMP_DIR/${name}_run.log" | sed 's/^/    /'
        fi
    else
        FAIL=$((FAIL + 1))
        echo "  [FAIL] $name (编译失败)"
        cat "$TEMP_DIR/${name}_compile.log" | sed 's/^/    /' | tail -5
    fi
done

echo ""
echo "============================================"
echo "验证总结"
echo "============================================"
echo "通过: $PASS"
echo "失败: $FAIL"
echo "总计: $TOTAL"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
    echo "⚠️  存在失败的验证项"
    exit 1
else
    echo "✅ 所有任务示例验证通过"
    exit 0
fi
