#import "PickerProbe.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SkillCappedFolderPickerResult ()
@property (nonatomic, nullable, readwrite) UIViewController *controller;
@property (nonatomic, copy, nullable, readwrite) NSString *reason;
@end

@implementation SkillCappedFolderPickerResult

+ (instancetype)make {
  SkillCappedFolderPickerResult *result = [SkillCappedFolderPickerResult new];
  @try {
    // `asCopy: NO` — the picker hands back a security-scoped URL, which is what
    // lets the app read the folder in place (and remember it across launches).
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ UTTypeFolder ]
                                                                    asCopy:NO];
    picker.allowsMultipleSelection = NO;
    result.controller = picker;
  } @catch (NSException *exception) {
    result.reason = exception.reason ?: exception.name;
  }
  return result;
}

@end
