#import <XCTest/XCTest.h>

@interface ScoreMakerXcodeTests : XCTestCase
@end

@implementation ScoreMakerXcodeTests

- (void)testCompleteApplicationCompatibilitySuite
{
  NSString *bundlePath = [[NSBundle bundleForClass:[self class]] bundlePath];
  NSString *productsDirectory = [bundlePath stringByDeletingLastPathComponent];
  NSString *executable = [productsDirectory
    stringByAppendingPathComponent:@"ScoreMakerCompatibilityTests"];
  XCTAssertTrue ([[NSFileManager defaultManager] isExecutableFileAtPath:executable],
                 @"Missing shared test executable at %@", executable);

  NSTask *task = [[[NSTask alloc] init] autorelease];
  NSPipe *output = [NSPipe pipe];
  [task setExecutableURL:[NSURL fileURLWithPath:executable]];
  [task setCurrentDirectoryURL:[NSURL fileURLWithPath:PROJECT_DIR]];
  [task setStandardOutput:output];
  [task setStandardError:output];
  NSError *launchError = nil;
  XCTAssertTrue ([task launchAndReturnError:&launchError], @"Could not launch suite: %@", launchError);
  [task waitUntilExit];
  NSData *data = [[output fileHandleForReading] readDataToEndOfFile];
  NSString *log = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  XCTAssertEqual ([task terminationStatus], 0, @"Shared suite failed:\n%@", log);
}

@end
