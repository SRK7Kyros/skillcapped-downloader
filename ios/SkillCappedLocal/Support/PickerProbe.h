#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds the system folder picker, or carries the reason UIKit refused.
///
/// UIKit raises an **Objective-C exception** from the initializer, and Swift
/// cannot catch an NSException, so a build that hits one used to die the instant
/// the folder button was tapped. The call lives in Objective-C so a refusal
/// becomes a message instead of a crash.
///
/// The refusal that bit every earlier build is `folder import is not supported,
/// use asCopy:false`, raised even though the call already passes `asCopy:NO`. The
/// message names nothing that can be satisfied: on iOS 26 and later a
/// **folder-only** type array is refused outright. Asking for a folder *beside*
/// `UTTypeItem` is what avoids that path — LiveContainer's guest-app shim rewrites
/// every request to `@[UTTypeItem, UTTypeFolder]` and KartPad's working picker
/// asks for `@[UTTypeItem, UTTypeData, UTTypeDiskImage, UTTypeFolder]`.
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

/// Every spelling the build tries, in order, each marked with whether UIKit
/// built it — `{ name, ok, detail? }`. Read by the in-app diagnostics so a
/// device that refuses one spelling can say which, without a crash.
+ (NSArray<NSDictionary<NSString *, id> *> *)survey;

@end

NS_ASSUME_NONNULL_END
