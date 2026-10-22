#import "PickerProbe.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SkillCappedFolderPickerResult ()
@property (nonatomic, nullable, readwrite) UIViewController *controller;
@property (nonatomic, copy, nullable, readwrite) NSString *reason;
@end

@implementation SkillCappedFolderPickerResult

+ (instancetype)make {
  return [self makeStartingAt:nil];
}

+ (instancetype)makeStartingAt:(NSURL *)directory {
  SkillCappedFolderPickerResult *result = [SkillCappedFolderPickerResult new];
  NSMutableArray<NSString *> *refusals = [NSMutableArray array];

  // Opening a folder in place means asking for the `.folder` type with
  // `asCopy:NO` — spelled out. The bare `initForOpeningContentTypes:` resolves
  // to a copy-in (import) presentation on some iOS builds, which UIKit refuses
  // for a folder ("folder import is not supported, use asCopy:false", the exact
  // sentence a device running 26.6.2 printed), and which in any case only
  // enables Files' Open button for files.
  @try {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]
                                                                    asCopy:NO];
    picker.allowsMultipleSelection = NO;
    // A picker left on its default "Recents" root can keep Open disabled and
    // gives the user nothing to select; hand it a real, browsable directory.
    if (directory != nil) {
      picker.directoryURL = directory;
    }
    result.controller = picker;
    return result;
  } @catch (NSException *exception) {
    [refusals addObject:[self textFor:exception]];
  }

  // Second try: the pre-iOS-14 open-mode initializer, which has always taken a
  // folder type. A device that refuses the modern call still gets a picker.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  @try {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[ @"public.folder" ]
                                                               inMode:UIDocumentPickerModeOpen];
    picker.allowsMultipleSelection = NO;
    if (directory != nil) {
      picker.directoryURL = directory;
    }
    result.controller = picker;
    return result;
  } @catch (NSException *exception) {
    [refusals addObject:[self textFor:exception]];
  }
#pragma clang diagnostic pop

  // Last try: the convenience initializer, in case a build implements it
  // correctly where the explicit pair does not.
  @try {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
    picker.allowsMultipleSelection = NO;
    if (directory != nil) {
      picker.directoryURL = directory;
    }
    result.controller = picker;
    return result;
  } @catch (NSException *exception) {
    [refusals addObject:[self textFor:exception]];
  }

  result.reason = [refusals componentsJoinedByString:@"\n\n"];
  return result;
}

/// UIKit's own sentence, which is the useful one to show when it refuses.
+ (NSString *)textFor:(NSException *)exception {
  return exception.reason.length ? exception.reason : exception.name;
}

@end
