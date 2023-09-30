//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2014-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Basics
import CoreCommands
import Workspace

extension SwiftPackageTool {
    struct Init: SwiftCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Initialize a new package")

        @OptionGroup(visibility: .hidden)
        var globalOptions: GlobalOptions
        
        @Option(
            name: .customLong("type"),
            help: ArgumentHelp("Package type:", discussion: """
                library           - A package with a library.
                executable        - A package with an executable.
                tool              - A package with an executable that uses
                                    Swift Argument Parser. Use this template if you
                                    plan to have a rich set of command-line arguments.
                build-tool-plugin - A package that vends a build tool plugin.
                command-plugin    - A package that vends a command plugin.
                macro             - A package that vends a macro.
                empty             - An empty package with a Package.swift manifest.
                """))
        var initMode: InitPackage.PackageType = .library

        @Option(name: .customLong("name"), help: "Provide custom package name")
        var packageName: String?
        
        @Flag(help: "Adds default documentation. Only available for library package type.")
        var withDocs: Bool = false
        
        private var initPackageOptions: InitPackage.InitPackageOptions {
            get throws {
                guard withDocs == false || initMode == .library else {
                    throw ValidationError("--with-docs flag is available only for library modules")
                }
                
                return InitPackage.InitPackageOptions(packageType: initMode,
                                                      withDocs: withDocs)
            }
        }

        func run(_ swiftTool: SwiftTool) throws {
            guard let cwd = swiftTool.fileSystem.currentWorkingDirectory else {
                throw InternalError("Could not find the current working directory")
            }

            let packageName = self.packageName ?? cwd.basename
            let initPackageOptions = try initPackageOptions
            let initPackage = try InitPackage(
                name: packageName,
                options: initPackageOptions,
                destinationPath: cwd,
                fileSystem: swiftTool.fileSystem
            )
            initPackage.progressReporter = { message in
                print(message)
            }
            try initPackage.writePackageStructure()
        }
    }
}

extension InitPackage.PackageType: ExpressibleByArgument {}
