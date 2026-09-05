import Foundation

public struct RimeKeyMapping: Equatable, Sendable {
    public let keyCode: Int32
    public let modifiers: Int32

    public init(keyCode: Int32, modifiers: Int32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum RimeKeyboardMapper {
    public static func printable(
        characters: String?,
        charactersIgnoringModifiers: String?,
        shift: Bool,
        control: Bool
    ) -> RimeKeyMapping? {
        guard let unmodified = asciiScalar(in: charactersIgnoringModifiers ?? characters) else {
            return nil
        }

        var modifiers: Int32 = 0
        if shift { modifiers |= 1 }
        if control { modifiers |= 4 }

        if shift,
           !control,
           let actual = asciiScalar(in: characters),
           actual != unmodified,
           !isASCIIAlpha(actual)
        {
            return RimeKeyMapping(keyCode: Int32(actual.value), modifiers: 0)
        }

        return RimeKeyMapping(keyCode: Int32(unmodified.value), modifiers: modifiers)
    }

    private static func asciiScalar(in value: String?) -> Unicode.Scalar? {
        guard let scalar = value?.unicodeScalars.first, scalar.isASCII else { return nil }
        return scalar
    }

    private static func isASCIIAlpha(_ scalar: Unicode.Scalar) -> Bool {
        (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}
