import Foundation

// MARK: - Startup Banner

func printBanner() {
    let banner = """

      ___                    __  __
     | | _____   _____      |  \\/  | ___
     | |/ _ \\ \\ / / _ \\     | |\\/| |/ _ \\
     | | (_) \\ V /  __/  _  | |  | |  __/
     |_|\\___/ \\_/ \\___| (_) |_|  |_|\\___|

     Personal AI Assistant Daemon v\(DaemonConfig.version)
    """
    print(banner)
}

// MARK: - Main Entry Point

let config = DaemonConfig()
printBanner()

// Check for API key
if config.apiKey != nil {
    Logger.info("API key configured")
} else {
    Logger.error("WARNING: ANTHROPIC_API_KEY not set. Chat will be unavailable until it is configured.")
}

// Create and start the daemon
let daemon = DaemonApp(config: config)

// Set up signal handling for graceful shutdown
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)
sigintSource.setEventHandler {
    Logger.info("Received SIGINT, shutting down...")
    Task {
        await daemon.stop()
        exit(0)
    }
}
sigintSource.resume()

let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
signal(SIGTERM, SIG_IGN)
sigtermSource.setEventHandler {
    Logger.info("Received SIGTERM, shutting down...")
    Task {
        await daemon.stop()
        exit(0)
    }
}
sigtermSource.resume()

// Start the daemon
Task {
    do {
        try await daemon.start()

        // Print connection info
        print("")
        Logger.info("===========================================")
        Logger.info("  WebSocket: ws://localhost:\(config.port)")
        Logger.info("  Connect from iOS app using the above URL")
        Logger.info("===========================================")
        print("")
    } catch {
        Logger.error("Failed to start daemon: \(error)")
        exit(1)
    }
}

// Keep the run loop alive
RunLoop.main.run()
