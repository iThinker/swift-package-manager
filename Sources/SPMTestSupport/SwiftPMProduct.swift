//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation

import class TSCBasic.Process
import struct TSCBasic.ProcessResult

/// Defines the executables used by SwiftPM.
/// Contains path to the currently built executable and
/// helper method to execute them.
public enum SwiftPM {
    case Build
    case Package
    case Registry
    case Test
    case Run
}

extension SwiftPM {
    /// Executable name.
    private var executableName: RelativePath {
        switch self {
        case .Build:
            return "swift-build"
        case .Package:
            return "swift-package"
        case .Registry:
            return "swift-package-registry"
        case .Test:
            return "swift-test"
        case .Run:
            return "swift-run"
        }
    }

    /// Path to currently built binary.
    public var path: AbsolutePath {
        #if canImport(Darwin)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return try! AbsolutePath(AbsolutePath(validating: bundle.bundlePath).parentDirectory, self.executableName)
        }
        fatalError()
        #else
        return try! AbsolutePath(validating: CommandLine.arguments.first!, relativeTo: localFileSystem.currentWorkingDirectory!)
            .parentDirectory.appending(self.executableName)
        #endif
    }
}

extension SwiftPM {
    /// Executes the product with specified arguments.
    ///
    /// - Parameters:
    ///         - args: The arguments to pass.
    ///         - env: Additional environment variables to pass. The values here are merged with default env.
    ///         - packagePath: Adds argument `--package-path <path>` if not nil.
    ///
    /// - Returns: The output of the process.
    @discardableResult
    public func execute(
        _ args: [String] = [],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> (stdout: String, stderr: String) {
        let result = try executeProcess(
            args,
            packagePath: packagePath,
            env: env
        )
        
        let stdout = try result.utf8Output()
        let stderr = try result.utf8stderrOutput()
        
        if result.exitStatus == .terminated(code: 0) {
            return (stdout: stdout, stderr: stderr)
        }
        throw SwiftPMError.executionFailure(
            underlying: ProcessResult.Error.nonZeroExit(result),
            stdout: stdout,
            stderr: stderr
        )
    }
    
    private func executeProcess(
        _ args: [String],
        packagePath: AbsolutePath? = nil,
        env: [String: String]? = nil
    ) throws -> ProcessResult {
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in env ?? [:] {
            environment[key] = value
        }
#if Xcode
        // Unset these variables which causes issues when running tests via Xcode.
        environment["XCTestConfigurationFilePath"] = nil
        environment["XCTestSessionIdentifier"] = nil
        environment["XCTestBundlePath"] = nil
        environment["NSUnbufferedIO"] = nil
#endif
        // FIXME: We use this private environment variable hack to be able to
        // create special conditions in swift-build for swiftpm tests.
        environment["SWIFTPM_TESTS_MODULECACHE"] = self.path.parentDirectory.pathString
#if !os(Windows)
        environment["SDKROOT"] = nil
#endif
        
        // Unset the internal env variable that allows skipping certain tests.
        environment["_SWIFTPM_SKIP_TESTS_LIST"] = nil
        
        var completeArgs = [self.path.pathString]
        if let packagePath = packagePath {
            completeArgs += ["--package-path", packagePath.pathString]
        }
        completeArgs += args
        
        return try Process.popen(arguments: completeArgs, environment: environment)
    }
}

extension SwiftPM {
    public static func packagePath(for packageName: String, packageRoot: AbsolutePath) throws -> AbsolutePath {
        // FIXME: The directory paths are hard coded right now and should be replaced by --get-package-path
        // whenever we design that. https://bugs.swift.org/browse/SR-2753
        let packagesPath = packageRoot.appending(components: ".build", "checkouts")
        for name in try localFileSystem.getDirectoryContents(packagesPath) {
            if name.hasPrefix(packageName) {
                return try AbsolutePath(validating: name, relativeTo: packagesPath)
            }
        }
        throw SwiftPMError.packagePathNotFound
    }
}

public enum SwiftPMError: Error {
    case packagePathNotFound
    case executionFailure(underlying: Error, stdout: String, stderr: String)
}

public enum SwiftPMProductError: Swift.Error {
    case packagePathNotFound
    case executionFailure(error: Swift.Error, output: String, stderr: String)
}
