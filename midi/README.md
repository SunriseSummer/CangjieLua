# 🎵 MIDI 音乐编解码器

仓颉语言实现的 MIDI 音乐编解码器，支持**人类可读的高级语言**与 **`.mid` 音频文件**之间的无损双向转换。

## MIDI 背景

MIDI（Musical Instrument Digital Interface）是数字音乐领域的通用标准协议，定义了电子乐器与计算机之间的通信方式。一个标准 MIDI 文件（`.mid`）包含：

- **MThd 文件头**：声明格式版本（Format 0/1）、轨道数量、时间分辨率（TPQ，每四分音符的 tick 数）
- **MTrk 轨道块**：每条轨道由一系列按时间排列的 MIDI 事件构成，事件之间用 VLQ（变长数值）编码的 delta time 分隔
- **通道事件**：Note On/Off（音符开关）、Program Change（乐器切换）、Control Change（控制器变化）、Pitch Bend（弯音）等
- **Meta 事件**：Set Tempo（速度设定）、Time Signature（拍号）、Key Signature（调号）、Track Name（轨道名）等
- **Running Status**：一种二进制压缩机制，当连续事件使用相同的状态字节时，可省略后续事件的状态字节以节省空间

## 项目架构

```
midi/
├── cjpm.toml                    # 项目配置
├── README.md                    # 本文件
├── src/
│   ├── main.cj                  # 程序入口
│   ├── verifier.cj              # MIDI 文件验证工具
│   ├── core/                    # 核心数据类型与解析
│   │   ├── types.cj             #   乐谱数据模型（ScoreData, TrackData, MusicElement 等）
│   │   ├── parser.cj            #   文本乐谱解析器（乐谱格式 → ScoreData）
│   │   └── instrument.cj        #   GM 标准乐器映射表（128 种乐器）
│   ├── encoder/                 # MIDI 编码器（文本 → 二进制）
│   │   ├── encoder.cj           #   编码入口 + 乐谱格式编码器
│   │   ├── readable_encoder.cj  #   MIDI 可读事件格式编码器
│   │   ├── event.cj             #   MIDI 事件编码（VLQ、事件字节生成）
│   │   └── utils.cj             #   编码器共用工具（十六进制、音名解析等）
│   ├── decoder/                 # MIDI 解码器（二进制 → 文本）
│   │   ├── decoder.cj           #   反编译器（.mid → 可读事件文本）
│   │   ├── binary.cj            #   二进制读取工具（VLQ、大端字节序）
│   │   └── note.cj              #   音高转换（MIDI 编号 ↔ 音名）
│   ├── midi_test.cj             #   测试辅助函数
│   ├── score_test.cj            #   乐谱格式编码测试
│   ├── decompile_test.cj        #   反编译回环测试
│   └── readable_test.cj         #   可读事件格式测试
└── testcase/                    # 外部测试用 MIDI 文件
    ├── test.mid
    ├── test2.mid
    └── test3.mid
```

## 技术方案

### 编码流程（文本 → MIDI 二进制）

系统支持两种输入格式，`generate()` 函数自动检测：

1. **乐谱记谱格式**：面向音乐创作的高级语言，用音名和时值描述旋律
   - 解析：`parser.cj` → `ScoreData` → `encoder.cj` → MIDI 二进制
2. **MIDI 可读事件格式**：面向精确控制的事件级语言，用命名事件和音名描述每个 MIDI 事件
   - 解析：`readable_encoder.cj` → MIDI 二进制（支持 Running Status 自动处理）

### 解码流程（MIDI 二进制 → 文本）

`decompile()` 函数将任意 `.mid` 文件转换为人类可读的 MIDI 事件文本：

1. 解析 MThd 头（格式、轨道数、TPQ）
2. 自动检测是否使用 Running Status
3. 逐轨道解码所有事件，用音名和命名事件类型替代十六进制编码
4. 输出的文本可直接重新编码为二进制完全一致的 `.mid` 文件

### 无损保证

反编译后的文本保留了精确复原所需的全部信息：

- **逐事件保留**：每个 MIDI 事件（包括通道事件、Meta 事件、SysEx 事件）都被完整记录
- **精确时序**：delta time 以十进制数值原样保留
- **Running Status 还原**：通过 `RUNNING_STATUS ON/OFF` 指令控制编码器是否启用 Running Status 压缩
- **音高无损**：MIDI 编号通过音名精确表达（如 C#4 = 61），编码时精确还原

## 构建与测试

```bash
# 下载 Cangjie SDK（如尚未下载）
curl -sL -o cangjie-sdk.tar.gz \
  https://github.com/SunriseSummer/CangjieSDK/releases/download/1.0.5/cangjie-sdk-linux-x64-1.0.5.tar.gz
tar xzf cangjie-sdk.tar.gz && rm cangjie-sdk.tar.gz

# 构建
source cangjie/envsetup.sh
cd midi
cjpm build

# 运行测试
cjpm test
```

## 支持的语法与功能

### 一、乐谱记谱格式（创作友好）

适合人类编写音乐，语法简洁直观。

#### 全局指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `TEMPO <bpm>` | 设定全局速度（BPM） | `TEMPO 120` |
| `TEMPO_AT <tick> <bpm>` | 在指定 tick 位置变速 | `TEMPO_AT 480 100` |
| `TRACK <name>` | 开始新轨道 | `TRACK melody` |
| `INSTRUMENT <name>` | 设定乐器（GM 标准名） | `INSTRUMENT piano` |
| `VELOCITY <0-127>` | 设定力度 | `VELOCITY 90` |
| `CHANNEL <0-15>` | 指定 MIDI 通道 | `CHANNEL 9` |
| `//` | 注释 | `// 这是注释` |

#### 音符语法

| 语法 | 说明 | 示例 |
|------|------|------|
| `<音名> <时值>` | 单音符 | `C4 4`（四分音符 C4） |
| `<音名>#` | 升半音 | `F#4 8`（八分音符 F#4） |
| `<音名>b` | 降半音 | `Bb3 2`（二分音符 Bb3） |
| `<时值>.` | 附点（时值 ×1.5） | `C4 4.`（附点四分音符） |
| `T<ticks>` | 原始 tick 时值 | `C4 T216` |
| `R <时值>` | 休止符 | `R 4`（四分休止符） |
| `[<音名>...] <时值>` | 和弦 | `[C3 E3 G3] 2` |

#### 标准时值

| 时值 | 名称 | ticks (TPQ=480) |
|------|------|-----------------|
| `1` | 全音符 | 1920 |
| `2` | 二分音符 | 960 |
| `4` | 四分音符 | 480 |
| `8` | 八分音符 | 240 |
| `16` | 十六分音符 | 120 |
| `32` | 三十二分音符 | 60 |

#### 乐谱格式示例

```
TEMPO 120

TRACK melody
INSTRUMENT piano
C4 4  C4 4  G4 4  G4 4
A4 4  A4 4  G4 2
F4 4  F4 4  E4 4  E4 4
D4 4  D4 4  C4 2

TRACK harmony
INSTRUMENT strings
[C3 E3 G3] 2  [C3 E3 G3] 2
[F3 A3 C4] 2  [C3 E3 G3] 2

TRACK bass
INSTRUMENT bass
C2 2  E2 2
F2 2  C2 2
```

### 二、MIDI 可读事件格式（精确无损）

由反编译器输出，用于 `.mid` 文件的无损表达。每行一个事件，格式为 `<delta> <事件类型> <参数...>`。

#### 文件头指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `MIDI` | 格式标识（必须为首行） | `MIDI` |
| `TPQ <n>` | 每四分音符 tick 数 | `TPQ 480` |
| `FORMAT <0\|1>` | MIDI 格式 | `FORMAT 1` |
| `RUNNING_STATUS ON` | 启用 Running Status 编码 | `RUNNING_STATUS ON` |
| `TRACK` / `TRACK_END` | 轨道起止标记 | |

#### 通道事件

| 事件 | 格式 | 说明 |
|------|------|------|
| Note On | `<delta> ON <音名> <力度> CH <通道>` | `0 ON C4 80 CH 0` |
| Note Off | `<delta> OFF <音名> <力度> CH <通道>` | `480 OFF C4 64 CH 0` |
| Program Change | `<delta> PROGRAM <编号> CH <通道>` | `0 PROGRAM 0 CH 0` |
| Control Change | `<delta> CC <控制器> <值> CH <通道>` | `0 CC 64 127 CH 0` |
| Pitch Bend | `<delta> PITCH_BEND <LSB> <MSB> CH <通道>` | `0 PITCH_BEND 0 64 CH 0` |
| Aftertouch | `<delta> AFTERTOUCH <音名> <压力> CH <通道>` | `0 AFTERTOUCH C4 80 CH 0` |
| Channel Pressure | `<delta> CHAN_PRESSURE <值> CH <通道>` | `0 CHAN_PRESSURE 64 CH 0` |

#### Meta 事件

| 事件 | 格式 | 说明 |
|------|------|------|
| Set Tempo | `<delta> SET_TEMPO <微秒>` | `0 SET_TEMPO 500000`（120 BPM） |
| End of Track | `<delta> END_TRACK` | `0 END_TRACK` |
| 其他 Meta | `<delta> META <类型hex> <数据hex...>` | `0 META 03 50 69 61 6E 6F`（轨道名 "Piano"） |

#### SysEx 事件

| 事件 | 格式 | 说明 |
|------|------|------|
| SysEx | `<delta> SYSEX <状态hex> <数据hex...>` | `0 SYSEX F0 7E 7F 09 01 F7` |

#### 可读事件格式示例

```
MIDI
TPQ 480
FORMAT 1

TRACK
0 META 03 50 69 61 6E 6F
0 META 58 04 02 18 08
0 SET_TEMPO 500000
0 END_TRACK
TRACK_END

TRACK
0 PROGRAM 0 CH 0
0 CC 10 64 CH 0
0 ON C4 80 CH 0
480 OFF C4 64 CH 0
0 ON D4 80 CH 0
480 OFF D4 64 CH 0
0 END_TRACK
TRACK_END
```

### 三、GM 标准乐器（128 种）

支持完整的 General MIDI 标准乐器集。常用乐器名及别名：

| 乐器名 | MIDI 编号 | 类别 |
|---------|-----------|------|
| `piano` | 0 | 钢琴 |
| `bright_piano` | 1 | 钢琴 |
| `harpsichord` | 6 | 钢琴 |
| `glockenspiel` | 9 | 色彩打击乐 |
| `church_organ` | 19 | 风琴 |
| `guitar` | 24 | 吉他 |
| `steel_guitar` | 25 | 吉他 |
| `bass` | 33 | 贝斯 |
| `violin` | 40 | 弦乐 |
| `cello` | 42 | 弦乐 |
| `strings` | 48 | 合奏 |
| `trumpet` | 56 | 铜管 |
| `tuba` | 58 | 铜管 |
| `french_horn` | 60 | 铜管 |
| `saxophone` / `alto_sax` | 65 | 簧管 |
| `flute` | 73 | 木管 |
| `sitar` | 104 | 民族乐器 |
| `steel_drums` | 114 | 打击乐 |
| `gunshot` | 127 | 音效 |
