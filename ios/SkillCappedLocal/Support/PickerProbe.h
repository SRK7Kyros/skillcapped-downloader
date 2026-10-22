#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds the system folder picker, or carries the reason UIKit refused.
///
/// UIKit raises an **Objective-C exception** from the initializer — when the
/// running signature carries no iCloud container entitlement ("Application
/// initializing document picker is missing the iCloud entitlement"), and when
/// the requested presentation cannot return a folder ("folder import is not
/// supported, use asCopy:false"). Swift cannot catch an NSException, so a build
/// that hits either used to die the instant the folder button was tapped. The
/// call lives in Objective-C so a refusal becomes a message instead of a crash.
@interface SkillCappedFolderPickerResult : NSObject

/// Ready to present, or `nil` when the picker is unavailable.
@property (nonatomic, nullable, readonly) UIViewController *controller;
/// Why the picker is unavailable, straight from UIKit.
@property (nonatomic, copy, nullable, readonly) NSString *reason;

/// Ready to present, or `nil` when the picker is unavailable.
+ (instancetype)make;

/// Same, browsing from `directory` rather than the default "Recents" root —
/// which can keep Open disabled and gives the user nothing to select.
+ (instancetype)makeStartingAt:(nullable NSURL *)directory;

@end

NS_ASSUME_NONNULL_END
