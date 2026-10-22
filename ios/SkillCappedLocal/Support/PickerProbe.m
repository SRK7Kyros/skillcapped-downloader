#import "PickerProbe.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SkillCappedFolderPickerResult ()
@property (nonatomic, nullable, readwrite) UIViewController *controller;
@property (nonatomic, copy, nullable, readwrite) NSString *reason;

+ (NSString *)textFor:(NSException *)exception;
@end

/// The type lists to ask for, best first.
///
/// A **folder-only** list is what UIKit 26 and later refuses from the
/// initializer ("folder import is not supported, use asCopy:false" — raised even
/// though the call already passes `asCopy:NO`, so the hint names nothing that can
/// be satisfied). Naming `UTTypeItem` beside the folder keeps the picker on the
/// ordinary path while still letting a folder be chosen, and the folder is still
/// handed back in place because `asCopy` stays `NO`.
///
/// `multi` leads because a folder is only *selectable* in the folder-only
/// presentation ("To allow folder selection, initialize with an array containing
/// only kUTTypeFolder" — Apple, Providing access to directories), and that
/// presentation is exactly what iOS 26 refuses. Multiple selection is how
/// LiveContainer's guest-app shim regains it while still naming `UTTypeItem`:
/// `/prevent crash when selecting only folder/`, it sets the type list to
/// `@[UTTypeItem, UTTypeFolder]` **and** turns selection on.
static NSArray<NSDictionary<NSString *, id> *> *SkillCappedRecipes(void) {
  return @[
    @{ @"name": @"item + folder, multiple, in place",
       @"types": @[ UTTypeItem, UTTypeFolder ],
       @"copy": @NO,
       @"multi": @YES },
    @{ @"name": @"item + folder, in place",
       @"types": @[ UTTypeItem, UTTypeFolder ],
       @"copy": @NO,
       @"multi": @NO },
    @{ @"name": @"item + data + folder, in place",
       @"types": @[ UTTypeItem, UTTypeData, UTTypeFolder ],
       @"copy": @NO,
       @"multi": @NO },
    @{ @"name": @"folder only, in place",
       @"types": @[ UTTypeFolder ],
       @"copy": @NO,
       @"multi": @NO },
    @{ @"name": @"folder only, copy in",
       @"types": @[ UTTypeFolder ],
       @"copy": @YES,
       @"multi": @NO },
  ];
}

/// Builds one picker. Raises (Objective-C) when UIKit refuses the request, which
/// is exactly what every caller wraps in `@try`.
static UIViewController *SkillCappedBuild(NSDictionary<NSString *, id> *recipe,
                                          NSURL *_Nullable directory) {
  UIDocumentPickerViewController *picker =
      [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:recipe[@"types"]
                                                                  asCopy:[recipe[@"copy"] boolValue]];
  picker.allowsMultipleSelection = [recipe[@"multi"] boolValue];
  if (directory != nil) {
    // A picker left on its default "Recents" root can keep Open disabled and
    // gives the user nothing to select.
    picker.directoryURL = directory;
  }
  return picker;
}

@implementation SkillCappedFolderPickerResult

+ (instancetype)make {
  return [self makeStartingAt:nil];
}

+ (instancetype)makeStartingAt:(NSURL *)directory {
  NSMutableArray<NSString *> *refusals = [NSMutableArray array];

  for (NSDictionary<NSString *, id> *recipe in SkillCappedRecipes()) {
    @try {
      SkillCappedFolderPickerResult *result = [SkillCappedFolderPickerResult new];
      result.controller = SkillCappedBuild(recipe, directory);
      return result;
    } @catch (NSException *exception) {
      [refusals addObject:[NSString stringWithFormat:@"%@ — %@",
                                                     recipe[@"name"],
                                                     [self textFor:exception]]];
    }
  }

  SkillCappedFolderPickerResult *result = [SkillCappedFolderPickerResult new];
  result.reason = [refusals componentsJoinedByString:@"\n"];
  return result;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)survey {
  NSMutableArray<NSDictionary<NSString *, id> *> *rows = [NSMutableArray array];

  for (NSDictionary<NSString *, id> *recipe in SkillCappedRecipes()) {
    NSMutableDictionary<NSString *, id> *row =
        [@{ @"name": recipe[@"name"], @"ok": @NO } mutableCopy];
    @try {
      (void)SkillCappedBuild(recipe, nil);
      row[@"ok"] = @YES;
    } @catch (NSException *exception) {
      row[@"detail"] = [self textFor:exception];
    }
    [rows addObject:row];
  }

  return rows;
}

+ (NSString *)textFor:(NSException *)exception {
  return exception.reason.length > 0 ? exception.reason : exception.name;
}

@end
