# 🎵 MIDI 音乐编解码器

仓颉语言实现的 MIDI 音乐编解码器，支持**乐谱记谱格式**与 **`.mid` 音频文件**之间的双向转换。

编码（乐谱 → `.mid`）和解码（`.mid` → 乐谱）使用**统一的乐谱记谱格式**，对用户完全对称友好。同时提供无损的可读事件格式用于精确还原。

---

## MIDI / 音乐基础概念

| 概念 | 说明 |
|------|------|
| **MIDI** | Musical Instrument Digital Interface，数字音乐的通用标准协议，用于电子乐器与计算机之间通信 |
| **`.mid` 文件** | 标准 MIDI 文件，存储音乐事件序列的二进制格式 |
| **MThd** | MIDI 文件头（Header），声明格式版本、轨道数、时间分辨率 |
| **MTrk** | MIDI 轨道块（Track），包含按时间排列的事件序列 |
| **Format 0/1** | MIDI 格式：0 = 单轨道，1 = 多轨道（最常用） |
| **TPQ** | Ticks Per Quarter note，每四分音符的 tick 数，决定时间精度（常见值：480、120） |
| **Tick** | MIDI 的最小时间单位，1 个四分音符 = TPQ 个 tick |
| **Delta Time** | 相邻事件之间的 tick 间隔，用 VLQ 编码存储 |
| **VLQ** | Variable Length Quantity，变长数值编码，用 1~4 字节表示任意大小的整数 |
| **Note On / Off** | 音符开（按键）/ 关（松键）事件，包含音高和力度 |
| **音高 (Pitch)** | MIDI 音高编号 0~127，C4（中央 C）= 60，每个半音 +1 |
| **力度 (Velocity)** | 按键力度 0~127，决定音量大小，0 表示松键 |
| **音名** | 用字母表示音高：C D E F G A B，加 `#`（升）或 `b`（降），加八度数字，如 `C#4`、`Bb3` |
| **时值** | 音符持续时长：1=全音符、2=二分、4=四分、8=八分、16=十六分、32=三十二分 |
| **附点** | 时值后加 `.`，持续时间 ×1.5，如 `4.` = 附点四分音符 |
| **和弦** | 多个音同时发声，用方括号包围：`[C3 E3 G3]` |
| **休止符** | 无声间隔，用 `R` 表示 |
| **BPM** | Beats Per Minute，每分钟拍数，决定演奏速度 |
| **Tempo** | 速度，MIDI 内部以"微秒/四分音符"存储，BPM = 60000000 / 微秒 |
| **Program Change** | 乐器切换事件，编号 0~127 对应 GM 标准 128 种乐器 |
| **GM** | General MIDI，通用 MIDI 标准，定义 128 种标准乐器音色 |
| **通道 (Channel)** | MIDI 有 16 个通道（0~15），每个通道可独立设置乐器，通道 9 专用于打击乐 |
| **CC** | Control Change，控制器变化，如音量（CC 7）、声像（CC 10）、延音踏板（CC 64） |
| **Pitch Bend** | 弯音，连续改变音高的效果，由 LSB + MSB 两字节组成 |
| **Running Status** | 二进制压缩机制：连续相同状态字节时省略后续的状态字节以节省空间 |
| **Meta 事件** | 非音频元信息：速度设定、拍号、调号、轨道名、歌词等 |
| **SysEx** | System Exclusive，厂商专用数据 |

---

## 项目架构

```
midi/
├── cjpm.toml                          # 项目配置
├── README.md                          # 本文件
├── src/
│   ├── main.cj                        # 程序入口与 CLI
│   ├── verifier.cj                    # MIDI 文件验证工具
│   ├── verifier_utils.cj              # 验证辅助（十六进制、VLQ、轨道解析）
│   ├── core/                          # 核心数据类型与解析
│   │   ├── types.cj                   #   乐谱数据模型（ScoreData, TrackData, MusicElement）
│   │   ├── parser.cj                  #   乐谱格式主解析器（parseScore）
│   │   ├── parser_utils.cj            #   解析辅助工具（字符判定、数值读取）
│   │   ├── parser_note.cj             #   音符与和弦解析（parseNoteToken, parseChordContent）
│   │   └── instrument.cj              #   GM 标准乐器映射表（128 种乐器）
│   ├── encoder/                       # MIDI 编码器（文本 → 二进制）
│   │   ├── encoder.cj                 #   乐谱格式编码器（generate 入口）
│   │   ├── readable_encoder.cj        #   可读事件格式编码入口（generateReadable）
│   │   ├── readable_events.cj         #   可读事件各类型编码实现
│   │   ├── event.cj                   #   MIDI 事件类型定义与底层编码
│   │   └── utils.cj                   #   编码器共用工具（十六进制、音名解析）
│   ├── decoder/                       # MIDI 解码器（二进制 → 文本）
│   │   ├── decoder.cj                 #   解码入口（decompile / decompileReadable）
│   │   ├── score_decoder.cj           #   乐谱格式反编译主逻辑
│   │   ├── score_duration.cj          #   时值转换与内联输出工具
│   │   ├── score_analysis.cj          #   MIDI 事件解码与音符配对
│   │   ├── score_grouping.cj          #   和弦检测与轨道信息提取
│   │   ├── score_types.cj             #   乐谱解码内部类型定义
│   │   ├── readable_decoder.cj        #   可读事件格式反编译
│   │   ├── readable_utils.cj          #   可读格式工具（Running Status 检测）
│   │   ├── binary.cj                  #   二进制读取工具（VLQ、大端序）
│   │   └── note.cj                    #   MIDI 编号 → 音名转换
│   ├── midi_test.cj                   #   测试辅助函数
│   ├── score_test.cj                  #   乐谱格式编码测试
│   ├── score_extra_test.cj            #   乐谱格式扩展测试
│   ├── decompile_test.cj              #   可读格式无损回环测试
│   ├── decompile_score_test.cj        #   乐谱格式回环测试
│   ├── readable_test.cj               #   可读事件格式基础测试
│   └── readable_extra_test.cj         #   可读事件格式扩展测试
└── testcase/                          # 测试数据
    ├── source/                        #   20 个乐谱记谱格式源文件
    └── binary/                        #   3 个外部 .mid 测试文件
```

---

## 构建与测试

```bash
# 下载 Cangjie SDK
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

---

## 命令行用法

```bash
# 编译：乐谱 → .mid
midi testcase/source/              # 编译目录下所有 .txt
midi testcase/source/10_swan_lake_full.txt  # 编译单个文件

# 反编译：.mid → 乐谱（用户友好，允许少量精度损失）
midi -d testcase/binary/test.mid
midi --decompile testcase/binary/

# 无损反编译：.mid → 可读事件格式（二进制精确还原）
midi -dr testcase/binary/test.mid
midi --decompile-readable testcase/binary/
```

---

## 两种编解码格式对比

| 特性 | 乐谱记谱格式 | 可读事件格式 |
|------|-------------|-------------|
| **面向用户** | 音乐人、作曲者 | 开发者、MIDI 工程师 |
| **编码** | ✅ `generate()` | ✅ `generate()` |
| **解码** | ✅ `decompile()` / `-d` | ✅ `decompileReadable()` / `-dr` |
| **可读性** | ⭐⭐⭐ 高（音名 + 时值） | ⭐⭐ 中（事件级） |
| **二进制还原** | ❌ 有损 | ✅ 无损（逐字节一致） |
| **格式标识** | 以 `TEMPO` 开头 | 以 `MIDI` 开头 |

### 乐谱格式的有损情况说明

乐谱格式解码（`-d`）在以下情况存在精度损失：

| 有损项 | 说明 |
|--------|------|
| **BPM 精度** | MIDI 以微秒存储速度，转为 BPM 取整会丢失小数部分（如 857142µs ≈ 70 BPM，实际 69.99...） |
| **时值量化** | MIDI 音符的 tick 时长会被四舍五入到最接近的标准时值，非标准时值用 `T<ticks>` 表示 |
| **力度量化** | 每音符力度变化 <15 的会被合并，减少 `VELOCITY` 行数 |
| **微小间隙** | 相邻音符间 <TPQ/8 的间隙（演奏表情）被吸收，不产生 `R` 休止 |
| **SysEx/Meta** | 部分 Meta 事件（拍号、调号等）和 SysEx 数据在乐谱格式中被忽略 |
| **Running Status** | 解码时不保留原始 RS 压缩信息，重编码始终不使用 RS |
| **TPQ 标准化** | 非 480 的 TPQ 值被等比缩放到 480，可能因整数截断丢失极小精度 |

### 可读事件格式的无损保证

可读事件格式（`-dr`）保证：

- 逐事件、逐字节、逐 tick 精确保留所有 MIDI 信息
- 反编译后重编码产生**二进制完全一致**的 `.mid` 文件
- 包含 Running Status 标记，确保压缩行为一致

---

## 支持的语法与功能

### 一、乐谱记谱格式（创作友好）

适合人类编写音乐，语法简洁直观。编码和解码使用统一格式。

#### 全局指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `TEMPO <bpm>` | 设定全局速度（BPM） | `TEMPO 120` |
| `TEMPO_AT <tick> <bpm>` | 在指定 tick 位置变速 | `TEMPO_AT 480 100` |
| `TRACK <name>` | 开始新轨道 | `TRACK melody` |
| `INSTRUMENT <name>` | 设定乐器（GM 标准名） | `INSTRUMENT piano` |
| `VELOCITY <0-127>` | 设定力度 | `VELOCITY 90` |
| `CHANNEL <0-15>` | 指定 MIDI 通道 | `CHANNEL 9` |
| `CC <控制器> <值>` | 控制器变化 | `CC 64 127`（延音踏板开） |
| `PITCH_BEND <lsb> <msb>` | 弯音控制 | `PITCH_BEND 0 64` |
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

由 `decompileReadable()` / `-dr` 输出，用于 `.mid` 文件的无损表达。每行一个事件，格式为 `<delta> <事件类型> <参数...>`。

#### 文件头指令

| 指令 | 说明 | 示例 |
|------|------|------|
| `MIDI` | 格式标识（必须为首行） | `MIDI` |
| `TPQ <n>` | 每四分音符 tick 数 | `TPQ 480` |
| `FORMAT <0\|1>` | MIDI 格式 | `FORMAT 1` |
| `RUNNING_STATUS ON` | 启用 Running Status 编码 | `RUNNING_STATUS ON` |
| `TRACK` / `TRACK_END` | 轨道起止标记 | |

#### 通道事件

| 事件 | 格式 | 示例 |
|------|------|------|
| Note On | `<delta> ON <音名> <力度> CH <通道>` | `0 ON C4 80 CH 0` |
| Note Off | `<delta> OFF <音名> <力度> CH <通道>` | `480 OFF C4 64 CH 0` |
| Program Change | `<delta> PROGRAM <编号> CH <通道>` | `0 PROGRAM 0 CH 0` |
| Control Change | `<delta> CC <控制器> <值> CH <通道>` | `0 CC 64 127 CH 0` |
| Pitch Bend | `<delta> PITCH_BEND <LSB> <MSB> CH <通道>` | `0 PITCH_BEND 0 64 CH 0` |
| Aftertouch | `<delta> AFTERTOUCH <音名> <压力> CH <通道>` | `0 AFTERTOUCH C4 80 CH 0` |
| Channel Pressure | `<delta> CHAN_PRESSURE <值> CH <通道>` | `0 CHAN_PRESSURE 64 CH 0` |

#### Meta 事件

| 事件 | 格式 | 示例 |
|------|------|------|
| Set Tempo | `<delta> SET_TEMPO <微秒>` | `0 SET_TEMPO 500000`（120 BPM） |
| End of Track | `<delta> END_TRACK` | `0 END_TRACK` |
| 其他 Meta | `<delta> META <类型hex> <数据hex...>` | `0 META 03 50 69 61 6E 6F` |

#### SysEx 事件

| 事件 | 格式 | 示例 |
|------|------|------|
| SysEx | `<delta> SYSEX <状态hex> <数据hex...>` | `0 SYSEX F0 7E 7F 09 01 F7` |

### 三、常用 GM 标准乐器

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
| `harmonica` | 22 | 簧管 |
| `sitar` | 104 | 民族乐器 |
| `steel_drums` | 114 | 打击乐 |
| `gunshot` | 127 | 音效 |

### 四、常用 CC 控制器编号

| CC 编号 | 名称 | 说明 |
|---------|------|------|
| 1 | Modulation | 调制轮 |
| 7 | Volume | 音量 |
| 10 | Pan | 声像（左右位置） |
| 11 | Expression | 表情控制 |
| 64 | Sustain | 延音踏板（0=关, 127=开） |
| 91 | Reverb | 混响量 |
| 93 | Chorus | 合唱量 |
