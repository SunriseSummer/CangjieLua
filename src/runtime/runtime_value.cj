package cangjie_lua.runtime

public enum RuntimeValue {
    | NilValue
    | IntValue(Int64)
    | FloatValue(Float64)
    | BoolValue(Bool)
    | TextValue(String)
}

public func runtimeValueToDisplayString(v: RuntimeValue): String {
    match (v) {
        case RuntimeValue.NilValue => "nil"
        case RuntimeValue.IntValue(i) => i.toString()
        case RuntimeValue.FloatValue(f) => f.toString()
        case RuntimeValue.BoolValue(b) => b.toString()
        case RuntimeValue.TextValue(s) => s
    }
}
