import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService`, which registers the app itself: no helper tool,
/// no privileged daemon, no launchd plist to install.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// `SMAppService` registers whatever path the app is running from. Registering a
    /// copy in a temporary or download directory produces a login item that breaks the
    /// moment the copy is cleaned up, so the app has to be somewhere it will stay.
    static var isInAStableLocation: Bool {
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let volatilePrefixes = ["/private/tmp", "/tmp", "/private/var/folders"]
        if volatilePrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        // A bundle still inside a mounted disk image cannot be a login item either.
        return !path.hasPrefix("/Volumes/")
            || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path)
    }

    enum Failure: LocalizedError {
        case unstableLocation
        case system(Error)

        var errorDescription: String? {
            switch self {
            case .unstableLocation:
                "Move Bendable to your Applications folder first."
            case let .system(error):
                (error as NSError).localizedDescription
            }
        }
    }

    static func set(_ enabled: Bool) throws {
        guard enabled else {
            if SMAppService.mainApp.status == .enabled {
                do { try SMAppService.mainApp.unregister() } catch { throw Failure.system(error) }
            }
            return
        }
        guard isInAStableLocation else { throw Failure.unstableLocation }
        do { try SMAppService.mainApp.register() } catch { throw Failure.system(error) }
    }
}
