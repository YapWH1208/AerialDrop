import Darwin
import Foundation

// Read only from an explicitly copied Index.plist. This intentionally captures
// only one global native Automatic Aerial selection, without target identifiers
// or timestamps from the surrounding wallpaper store.
private enum CaptureError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw CaptureError.message(message) }
}

private func dictionary(_ value: Any?, _ description: String) throws -> [String: Any] {
    guard let result = value as? [String: Any] else {
        throw CaptureError.message("\(description) must be a dictionary")
    }
    return result
}

private func exactKeys(_ value: [String: Any], _ keys: Set<String>, _ description: String) throws {
    try require(Set(value.keys) == keys, "\(description) has missing or unexpected fields")
}

private func decodedPlist(_ data: Data, _ description: String) throws -> [String: Any] {
    let value: Any
    do {
        value = try PropertyListSerialization.propertyList(from: data, format: nil)
    } catch {
        throw CaptureError.message("\(description) is not a valid property list")
    }
    return try dictionary(value, description)
}

private func sanitizedFixture(from input: Data) throws -> Data {
    let root = try decodedPlist(input, "input")
    let selection = try dictionary(root["AllSpacesAndDisplays"], "global selection")
    try require(selection["Type"] as? String == "linked", "global selection must be linked")
    let linked = try dictionary(selection["Linked"], "Linked")
    let content = try dictionary(linked["Content"], "Linked.Content")
    try exactKeys(content, ["Choices", "EncodedOptionValues", "Shuffle"], "Linked.Content")
    try require(content["Shuffle"] as? String == "$null", "Shuffle must be $null")
    guard let choices = content["Choices"] as? [Any], choices.count == 1 else {
        throw CaptureError.message("global selection must contain exactly one choice")
    }
    let choice = try dictionary(choices[0], "Aerial choice")
    try exactKeys(choice, ["Configuration", "Files", "Provider"], "Aerial choice")
    try require(choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials", "choice provider is not Aerial")
    guard let files = choice["Files"] as? [Any], files.isEmpty else {
        throw CaptureError.message("Aerial choice Files must be empty")
    }
    guard let configuration = choice["Configuration"] as? Data else {
        throw CaptureError.message("Aerial choice Configuration must be data")
    }
    try require(configuration.starts(with: Data("bplist00".utf8)), "Configuration must be a binary property list")
    let decodedConfiguration = try decodedPlist(configuration, "Configuration")
    try exactKeys(decodedConfiguration, ["assetID"], "Configuration")
    guard let assetID = decodedConfiguration["assetID"] as? String,
          UUID(uuidString: assetID) != nil else {
        throw CaptureError.message("Configuration assetID must be a UUID string")
    }
    guard let options = content["EncodedOptionValues"] as? Data else {
        throw CaptureError.message("EncodedOptionValues must be data")
    }
    try require(options.starts(with: Data("bplist00".utf8)), "EncodedOptionValues must be a binary property list")
    let optionRoot = try decodedPlist(options, "EncodedOptionValues")
    try exactKeys(optionRoot, ["values"], "EncodedOptionValues")
    let values = try dictionary(optionRoot["values"], "EncodedOptionValues.values")
    try exactKeys(values, ["aerialVariant"], "EncodedOptionValues.values")
    let variant = try dictionary(values["aerialVariant"], "aerialVariant")
    try exactKeys(variant, ["picker"], "aerialVariant")
    let picker = try dictionary(variant["picker"], "aerialVariant.picker")
    try exactKeys(picker, ["_0"], "aerialVariant.picker")
    let slot = try dictionary(picker["_0"], "aerialVariant.picker._0")
    try exactKeys(slot, ["id"], "aerialVariant.picker._0")
    try require(slot["id"] as? String == "automatic", "Aerial variant is not automatic")

    // Re-serialize the validated trees. An opaque binary plist may contain
    // unreachable object-table values that its decoded root does not expose.
    let cleanConfiguration = try PropertyListSerialization.data(
        fromPropertyList: decodedConfiguration, format: .binary, options: 0
    )
    let cleanOptions = try PropertyListSerialization.data(
        fromPropertyList: optionRoot, format: .binary, options: 0
    )
    let fixture: [String: Any] = [
        "Type": "linked",
        "Linked": [
            "Content": [
                "Choices": [[
                    "Configuration": cleanConfiguration,
                    "Files": [Any](),
                    "Provider": "com.apple.wallpaper.choice.aerials"
                ]],
                "EncodedOptionValues": cleanOptions,
                "Shuffle": "$null"
            ]
        ]
    ]
    return try PropertyListSerialization.data(fromPropertyList: fixture, format: .xml, options: 0)
}

private func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 5,
          arguments[1] == "--input",
          arguments[3] == "--output",
          !arguments[2].isEmpty,
          !arguments[4].isEmpty else {
        throw CaptureError.message("usage: capture-dynamic-aerial-fixture --input COPIED_INDEX.plist --output SANITIZED.plist")
    }
    let rawInputPath = arguments[2]
    let inputURL = URL(fileURLWithPath: rawInputPath).standardizedFileURL.resolvingSymlinksInPath()
    let outputURL = URL(fileURLWithPath: arguments[4]).standardizedFileURL
    try require(inputURL != outputURL.resolvingSymlinksInPath(), "input and output must differ")
    var inputMetadata = stat()
    try require(lstat(rawInputPath, &inputMetadata) == 0, "cannot inspect input")
    try require(inputMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), "input must be a regular file, not a symlink")
    let inputDescriptor = open(rawInputPath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    try require(inputDescriptor >= 0, "cannot open input")
    defer { _ = close(inputDescriptor) }
    var openedMetadata = stat()
    try require(fstat(inputDescriptor, &openedMetadata) == 0, "cannot inspect opened input")
    try require(openedMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), "input must be a regular file")
    try require(openedMetadata.st_dev == inputMetadata.st_dev && openedMetadata.st_ino == inputMetadata.st_ino,
                "input changed before reading")
    let input: Data
    do {
        input = try FileHandle(fileDescriptor: inputDescriptor, closeOnDealloc: false).readToEnd() ?? Data()
    } catch {
        throw CaptureError.message("cannot read input")
    }
    let output = try sanitizedFixture(from: input)
    let path = outputURL.path
    let descriptor = path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600) }
    guard descriptor >= 0 else {
        throw CaptureError.message("cannot create output; check parent directory or existing file")
    }
    var completed = false
    defer {
        _ = close(descriptor)
        if !completed { _ = unlink(path) }
    }
    try output.withUnsafeBytes { bytes in
        guard let base = bytes.baseAddress else { return }
        var written = 0
        while written < bytes.count {
            let count = write(descriptor, base.advanced(by: written), bytes.count - written)
            guard count > 0 else { throw CaptureError.message("cannot write output") }
            written += count
        }
    }
    completed = true
}

do {
    try run()
} catch {
    fputs("capture-dynamic-aerial-fixture: \(error)\n", stderr)
    exit(1)
}
