#import "PickerProbe.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SkillCappedFolderPickerResult ()
@property (nonatomic, nullable, readwrite) UIViewController *controller;
@property (nonatomic, copy, nullable, readwrite) NSString *reason;
@end

@implementation SkillCappedFolderPickerResult

+ (instancetype)make {
  SkillCappedFolderPickerResult *result = [SkillCappedFolderPickerResult new];
  NSMutableArray<NSString *> *refusals = [NSMutableArray array];

  // Opening a folder in place never goes through an import, and UIKit enforces
  // that at this level: the `asCopy:` pair refuses a folder outright ("folder
  // import is not supported") *even when `asCopy:NO` is passed*, so the plain
  // opening initializer is the one that yields a picker for a folder.
  @try {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]];
    picker.allowsMultipleSelection = NO;
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
    result.controller = picker;
    return result;
  } @catch (NSException *exception) {
    [refusals addObject:[self textFor:exception]];
  }
#pragma clang diagnostic pop

  result.reason = [refusals componentsJoinedByString:@"\n\n"];
  return result;
}

/// UIKit's own sentence, which is the useful one to show when it refuses.
+ (NSString *)textFor:(NSException *)exception {
  return exception.reason.length ? exception.reason : exception.name;
}

@end
