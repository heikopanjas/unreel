import ArgumentParser
import unreel_engine

@main
struct Unreel: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unreel",
        abstract: "A command line tool for managing podcast feeds",
        version: unreelEngineVersion
    )

    mutating func run() throws {
        print("unreel v\(unreelEngineVersion)")
        print("Use --help to see available commands")
    }
}
