#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds the system folder picker, or carries the reason UIKit refused.
///
/// UIKit raises an **Objective-C exception** from the initializer when the
/// running signature carries no iCloud container entitlement:
/// "Application initializing document picker is missing the iCloud
/// entitlement". Swift cannot catch an NSException, so a build without that
/// entitlement used to die the instant the folder button was tapped. The call
/// lives in Objective-C so a refusal becomes a message instead of a crash.
@interface SkillCappedFolderPickerResult : NSObject

/// Ready to present, or `nil` when the picker is unavailable.
@property (nonatomic, nullable, readonly) UIViewController *controller;
/// Why the picker is unavailable, straight from UIKit.
@property (nonatomic, copy, nullable, readonly) NSString *reason;

+ (instancetype)make;

@end

NS_ASSUME_NONNULL_END
