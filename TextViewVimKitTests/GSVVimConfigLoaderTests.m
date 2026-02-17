#import <XCTest/XCTest.h>

#import "GSVVimConfig.h"
#import "GSVVimConfigLoader.h"

static NSString *GSVWriteTempConfig(NSString *name, NSString *contents)
{
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"gsv-%@-%@.vim",
                                                                             name,
                                                                             [[NSUUID UUID] UUIDString]]];
    NSError *error = nil;
    BOOL wrote = [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!wrote || error != nil) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"Failed to write temp config %@ (%@)", path, [error localizedDescription]];
    }
    return path;
}

@interface GSVVimConfigLoaderTests : XCTestCase
@end

@implementation GSVVimConfigLoaderTests

- (void)testLoadsAndMergesInsertMappingsWithInternalOverride
{
    NSString *vimrcPath = GSVWriteTempConfig(@"vimrc", @"inoremap jk <Esc>\ninoremap xx <Esc>\n");
    NSString *internalPath = GSVWriteTempConfig(@"internal", @"inoremap jk <Esc>\ninoremap JK <ESC>\n");

    GSVVimConfig *config = [GSVVimConfigLoader loadConfigWithInternalConfigPath:internalPath
                                                                       vimrcPath:vimrcPath];
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"jk"], @"<Esc>");
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"xx"], @"<Esc>");
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"JK"], @"<Esc>");
}

- (void)testParsesProvidedPersonalEscapeMappings
{
    NSString *contents = @"inoremap jk <ESC>\n"
                         @"inoremap Jk <ESC>\n"
                         @"inoremap jK <ESC>\n"
                         @"inoremap JK <ESC>\n";
    NSString *internalPath = GSVWriteTempConfig(@"personal", contents);
    NSString *vimrcPath = GSVWriteTempConfig(@"empty", @"");

    GSVVimConfig *config = [GSVVimConfigLoader loadConfigWithInternalConfigPath:internalPath
                                                                       vimrcPath:vimrcPath];

    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"jk"], @"<Esc>");
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"Jk"], @"<Esc>");
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"jK"], @"<Esc>");
    XCTAssertEqualObjects([config insertMappingRHSForSequence:@"JK"], @"<Esc>");
}

- (void)testReportsUnsupportedDirectives
{
    NSString *vimrcPath = GSVWriteTempConfig(@"vimrc", @"set number\n");
    NSString *internalPath = GSVWriteTempConfig(@"internal", @"inoremap jk xx\n");
    GSVVimConfig *config = [GSVVimConfigLoader loadConfigWithInternalConfigPath:internalPath
                                                                       vimrcPath:vimrcPath];
    XCTAssertTrue([[config diagnostics] count] >= 2);
}

- (void)testParsesClipboardOptInFromConfig
{
    NSString *vimrcPath = GSVWriteTempConfig(@"vimrc-clipboard", @"set clipboard=unnamed\n");
    NSString *internalPath = GSVWriteTempConfig(@"internal-empty", @"");

    GSVVimConfig *config = [GSVVimConfigLoader loadConfigWithInternalConfigPath:internalPath
                                                                       vimrcPath:vimrcPath];
    XCTAssertTrue(config.unnamedRegisterUsesSystemClipboard);
}

- (void)testInternalClipboardSettingOverridesVimrc
{
    NSString *vimrcPath = GSVWriteTempConfig(@"vimrc-clipboard-on", @"set clipboard=unnamedplus\n");
    NSString *internalPath = GSVWriteTempConfig(@"internal-clipboard-off", @"set clipboard=\n");

    GSVVimConfig *config = [GSVVimConfigLoader loadConfigWithInternalConfigPath:internalPath
                                                                       vimrcPath:vimrcPath];
    XCTAssertFalse(config.unnamedRegisterUsesSystemClipboard);
}

@end
