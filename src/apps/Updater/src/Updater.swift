import Foundation

#if USE_SPARKLE
  import Sparkle
#endif

final class Updater: ObservableObject {
  public static let shared = Updater()

  public static let didFindValidUpdate = Notification.Name("didFindValidUpdate")
  public static let didFinishUpdateCycleFor = Notification.Name("didFinishUpdateCycleFor")

  #if USE_SPARKLE
    private let updaterController: SPUStandardUpdaterController
    private let delegate = SparkleDelegate()
  #endif

  private init() {
    #if USE_SPARKLE
      updaterController = SPUStandardUpdaterController(
        updaterDelegate: delegate,
        userDriverDelegate: nil
      )

      updaterController.updater.clearFeedURLFromUserDefaults()
    #endif
  }

  func checkForUpdatesInBackground() {
    #if USE_SPARKLE
      delegate.includingBetaVersions = false
      updaterController.updater.checkForUpdatesInBackground()
    #endif
  }

  func checkForUpdatesStableOnly() {
    #if USE_SPARKLE
      delegate.includingBetaVersions = false
      updaterController.checkForUpdates(nil)
    #endif
  }

  func checkForUpdatesWithBetaVersion() {
    #if USE_SPARKLE
      delegate.includingBetaVersions = true
      updaterController.checkForUpdates(nil)
    #endif
  }

  #if USE_SPARKLE
    private class SparkleDelegate: NSObject, SPUUpdaterDelegate {
      var includingBetaVersions = false

      func feedURLString(for updater: SPUUpdater) -> String? {
        var url = "https://appcast.pqrs.org/karabiner-elements-appcast.xml"
        if includingBetaVersions {
          url = "https://appcast.pqrs.org/karabiner-elements-appcast-devel.xml"
        }

        print("feedURLString \(url)")

        return url
      }

      func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        NotificationCenter.default.post(name: Updater.didFindValidUpdate, object: nil)
      }

      func updater(
        _: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: Error?
      ) {
        NotificationCenter.default.post(name: Updater.didFinishUpdateCycleFor, object: nil)
      }
    }
  #endif
}
