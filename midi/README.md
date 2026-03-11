# 🎵 MIDI 音乐生成器

仓颉语言实现的 MIDI 音乐生成器，基于 [MIDI.md](../MIDI.md) 设计文档。

## 功能

输入简洁文本乐谱，输出可播放的 `.mid` 文件。

```
TEMPO 120
INSTRUMENT piano
C4 4  C4 4  G4 4  G4 4
A4 4  A4 4  G4 2
```

支持特性：
- MIDI 文件头生成（MThd + MTrk）
- 音符音高映射（C4=60，支持 C0-B8）
- 升降号（`#` 升半音，`b` 降半音）
- 多种时值（全音符、二分、四分、八分、十六分）
- 休止符（`R`）
- BPM 速度控制（`TEMPO`）
- 乐器选择（`INSTRUMENT`，支持 GM 标准乐器）
- 和弦（`[C4 E4 G4] 2`）
- 多轨道（`TRACK`，MIDI Format 1）
- 注释（`//`）

## 构建与运行

```bash
# 下载 Cangjie SDK（如尚未下载）
curl -sL -o cangjie-sdk.tar.gz https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz
tar xzf cangjie-sdk.tar.gz && rm cangjie-sdk.tar.gz

# 构建
source cangjie/envsetup.sh  # 或项目根目录的 ../cangjie/envsetup.sh
cd midi
cjpm build

# 运行测试
cjpm run
```

## 测试用例

包含 10 个经典旋律测试用例（满分 110 分）：

| # | 旋律 | 新特性 | 分值 |
|---|------|--------|------|
| 1 | 🐯 两只老虎 | MIDI 文件头 | 5 |
| 2 | 🐝 小蜜蜂 | 音高映射 | 5 |
| 3 | ⭐ 小星星 | 时值变化 | 10 |
| 4 | 🎉 欢乐颂 | TEMPO + 八分音符 | 10 |
| 5 | 🌸 茉莉花 | 升降号 | 10 |
| 6 | 🏰 天空之城 | 休止符 | 10 |
| 7 | 🎻 卡农 | 乐器选择 | 10 |
| 8 | 🎹 致爱丽丝 | 和弦 + 十六分 | 15 |
| 9 | 🎂 生日快乐 | 多轨道 | 15 |
| 10 | 🌟 小星星变奏曲 | 三轨完整编曲 | 20 |

生成的 `.mid` 文件保存在 `tests/` 目录下，可用任意 MIDI 播放器打开试听。

## 项目结构

```
midi/
├── cjpm.toml           # 项目配置
├── README.md           # 本文件
├── src/
│   ├── main.cj         # 入口 + 测试套件
│   ├── midi_event.cj   # MIDI 事件类型定义
│   ├── parser.cj       # 文本乐谱解析器
│   ├── encoder.cj      # MIDI 二进制编码器
│   └── verifier.cj     # MIDI 文件验证工具
└── tests/              # 生成的 .mid 文件（运行后产生）
```
