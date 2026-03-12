package midi.core

import std.collection.*

// ============================================================
// General MIDI 乐器映射（完整 128 音色）
// ============================================================

// GM 乐器编号 → 乐器名（索引即编号，共 128 项）
public let GM_INSTRUMENTS: Array<String> = [
    // ── Piano (0-7) ──
    "piano",                  // 0:  Acoustic Grand Piano
    "bright_piano",           // 1:  Bright Acoustic Piano
    "electric_grand_piano",   // 2:  Electric Grand Piano
    "honky_tonk_piano",       // 3:  Honky-tonk Piano
    "electric_piano",         // 4:  Electric Piano 1
    "electric_piano_2",       // 5:  Electric Piano 2
    "harpsichord",            // 6:  Harpsichord
    "clavinet",               // 7:  Clavinet
    // ── Chromatic Percussion (8-15) ──
    "celesta",                // 8:  Celesta
    "glockenspiel",           // 9:  Glockenspiel
    "music_box",              // 10: Music Box
    "vibraphone",             // 11: Vibraphone
    "marimba",                // 12: Marimba
    "xylophone",              // 13: Xylophone
    "tubular_bells",          // 14: Tubular Bells
    "dulcimer",               // 15: Dulcimer
    // ── Organ (16-23) ──
    "drawbar_organ",          // 16: Drawbar Organ
    "percussive_organ",       // 17: Percussive Organ
    "rock_organ",             // 18: Rock Organ
    "church_organ",           // 19: Church Organ
    "reed_organ",             // 20: Reed Organ
    "accordion",              // 21: Accordion
    "harmonica",              // 22: Harmonica
    "tango_accordion",        // 23: Tango Accordion
    // ── Guitar (24-31) ──
    "guitar",                 // 24: Acoustic Guitar (nylon)
    "acoustic_guitar",        // 25: Acoustic Guitar (steel)
    "electric_guitar_jazz",   // 26: Electric Guitar (jazz)
    "electric_guitar_clean",  // 27: Electric Guitar (clean)
    "electric_guitar_muted",  // 28: Electric Guitar (muted)
    "overdriven_guitar",      // 29: Overdriven Guitar
    "distortion_guitar",      // 30: Distortion Guitar
    "guitar_harmonics",       // 31: Guitar Harmonics
    // ── Bass (32-39) ──
    "acoustic_bass",          // 32: Acoustic Bass
    "bass",                   // 33: Electric Bass (finger)
    "electric_bass",          // 34: Electric Bass (pick)
    "fretless_bass",          // 35: Fretless Bass
    "slap_bass_1",            // 36: Slap Bass 1
    "slap_bass_2",            // 37: Slap Bass 2
    "synth_bass_1",           // 38: Synth Bass 1
    "synth_bass_2",           // 39: Synth Bass 2
    // ── Strings (40-47) ──
    "violin",                 // 40: Violin
    "viola",                  // 41: Viola
    "cello",                  // 42: Cello
    "contrabass",             // 43: Contrabass
    "tremolo_strings",        // 44: Tremolo Strings
    "pizzicato_strings",      // 45: Pizzicato Strings
    "harp",                   // 46: Orchestral Harp
    "timpani",                // 47: Timpani
    // ── Ensemble (48-55) ──
    "strings",                // 48: String Ensemble 1
    "ensemble",               // 49: String Ensemble 2
    "synth_strings_1",        // 50: Synth Strings 1
    "synth_strings_2",        // 51: Synth Strings 2
    "choir_aahs",             // 52: Choir Aahs
    "voice_oohs",             // 53: Voice Oohs
    "voice",                  // 54: Synth Voice
    "orchestra_hit",          // 55: Orchestra Hit
    // ── Brass (56-63) ──
    "trumpet",                // 56: Trumpet
    "trombone",               // 57: Trombone
    "tuba",                   // 58: Tuba
    "muted_trumpet",          // 59: Muted Trumpet
    "horn",                   // 60: French Horn
    "brass_section",          // 61: Brass Section
    "synth_brass_1",          // 62: Synth Brass 1
    "synth_brass_2",          // 63: Synth Brass 2
    // ── Reed (64-71) ──
    "soprano_sax",            // 64: Soprano Sax
    "saxophone",              // 65: Alto Sax
    "tenor_sax",              // 66: Tenor Sax
    "baritone_sax",           // 67: Baritone Sax
    "oboe",                   // 68: Oboe
    "english_horn",           // 69: English Horn
    "bassoon",                // 70: Bassoon
    "clarinet",               // 71: Clarinet
    // ── Pipe (72-79) ──
    "piccolo",                // 72: Piccolo
    "flute",                  // 73: Flute
    "recorder",               // 74: Recorder
    "pan_flute",              // 75: Pan Flute
    "blown_bottle",           // 76: Blown Bottle
    "shakuhachi",             // 77: Shakuhachi
    "whistle",                // 78: Whistle
    "ocarina",                // 79: Ocarina
    // ── Synth Lead (80-87) ──
    "lead_square",            // 80: Lead 1 (square)
    "lead_sawtooth",          // 81: Lead 2 (sawtooth)
    "lead_calliope",          // 82: Lead 3 (calliope)
    "lead_chiff",             // 83: Lead 4 (chiff)
    "lead_charang",           // 84: Lead 5 (charang)
    "lead_voice",             // 85: Lead 6 (voice)
    "lead_fifths",            // 86: Lead 7 (fifths)
    "lead_bass",              // 87: Lead 8 (bass+lead)
    // ── Synth Pad (88-95) ──
    "pad_new_age",            // 88: Pad 1 (new age)
    "pad_warm",               // 89: Pad 2 (warm)
    "pad_polysynth",          // 90: Pad 3 (polysynth)
    "pad_choir",              // 91: Pad 4 (choir)
    "pad_bowed",              // 92: Pad 5 (bowed)
    "pad_metallic",           // 93: Pad 6 (metallic)
    "pad_halo",               // 94: Pad 7 (halo)
    "pad_sweep",              // 95: Pad 8 (sweep)
    // ── Synth Effects (96-103) ──
    "fx_rain",                // 96:  FX 1 (rain)
    "fx_soundtrack",          // 97:  FX 2 (soundtrack)
    "fx_crystal",             // 98:  FX 3 (crystal)
    "fx_atmosphere",          // 99:  FX 4 (atmosphere)
    "fx_brightness",          // 100: FX 5 (brightness)
    "fx_goblins",             // 101: FX 6 (goblins)
    "fx_echoes",              // 102: FX 7 (echoes)
    "fx_sci_fi",              // 103: FX 8 (sci-fi)
    // ── Ethnic (104-111) ──
    "sitar",                  // 104: Sitar
    "banjo",                  // 105: Banjo
    "shamisen",               // 106: Shamisen
    "koto",                   // 107: Koto
    "kalimba",                // 108: Kalimba
    "bagpipe",                // 109: Bagpipe
    "fiddle",                 // 110: Fiddle
    "shanai",                 // 111: Shanai
    // ── Percussive (112-119) ──
    "tinkle_bell",            // 112: Tinkle Bell
    "agogo",                  // 113: Agogo
    "steel_drums",            // 114: Steel Drums
    "woodblock",              // 115: Woodblock
    "taiko_drum",             // 116: Taiko Drum
    "melodic_tom",            // 117: Melodic Tom
    "synth_drum",             // 118: Synth Drum
    "reverse_cymbal",         // 119: Reverse Cymbal
    // ── Sound Effects (120-127) ──
    "guitar_fret_noise",      // 120: Guitar Fret Noise
    "breath_noise",           // 121: Breath Noise
    "seashore",               // 122: Seashore
    "bird_tweet",             // 123: Bird Tweet
    "telephone_ring",         // 124: Telephone Ring
    "helicopter",             // 125: Helicopter
    "applause",               // 126: Applause
    "gunshot"                 // 127: Gunshot
]

// 构建乐器名 → GM 编号的 HashMap（包含常用别名）
func buildInstrumentMap(): HashMap<String, Int64> {
    let m = HashMap<String, Int64>(200)
    // 注册全部 128 个标准名称
    var i: Int64 = 0
    while (i < GM_INSTRUMENTS.size) {
        m[GM_INSTRUMENTS[i]] = i
        i++
    }
    // 注册常用别名（GM 标准全称 → 对应编号）
    m["acoustic_grand_piano"] = 0
    m["bright_acoustic_piano"] = 1
    m["electric_piano_1"] = 4
    m["acoustic_guitar_nylon"] = 24
    m["acoustic_guitar_steel"] = 25
    m["steel_guitar"] = 25
    m["electric_bass_finger"] = 33
    m["electric_bass_pick"] = 34
    m["orchestral_harp"] = 46
    m["string_ensemble_1"] = 48
    m["string_ensemble_2"] = 49
    m["synth_voice"] = 54
    m["french_horn"] = 60
    m["alto_sax"] = 65
    m
}

// 全局乐器名映射表（模块加载时构建一次）
let GM_INSTRUMENT_MAP: HashMap<String, Int64> = buildInstrumentMap()

// 乐器名 → GM 编号（HashMap 查表，未知名称返回 0 即 piano）
public func instrumentNumber(name: String): Int64 {
    let lower = name.toAsciiLower()
    if (let Some(v) <- GM_INSTRUMENT_MAP.get(lower)) {
        v
    } else {
        0
    }
}

// GM 编号 → 乐器名（数组索引，越界返回 "piano"）
public func programToInstrument(program: Int64): String {
    if (program >= 0 && program < GM_INSTRUMENTS.size) {
        GM_INSTRUMENTS[program]
    } else {
        "piano"
    }
}
