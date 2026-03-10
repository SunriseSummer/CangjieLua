package cangjie_lua.runtime

import std.collection.*

public class PrintRuntime {
    private static var currentOutputs: ?ArrayList<RuntimeValue> = None

    public static func beginCapture(outputs: ArrayList<RuntimeValue>): Unit {
        currentOutputs = outputs
    }

    public static func endCapture(): Unit {
        currentOutputs = None
    }

    public static func appendOutputValue(v: RuntimeValue): Unit {
        if (let Some(buf) <- currentOutputs) {
            buf.add(v)
        }
    }
}
